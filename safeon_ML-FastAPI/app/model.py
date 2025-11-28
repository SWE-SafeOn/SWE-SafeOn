import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from uuid import UUID, uuid4

import joblib
import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from pydantic import BaseModel, validator
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import LabelEncoder, MinMaxScaler
from sqlalchemy import create_engine, text
from torch.utils.data import DataLoader, TensorDataset

# ---------------------------------------------------
# Logging
# ---------------------------------------------------
LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))


# ---------------------------------------------------
# Paths and defaults
# ---------------------------------------------------
PROJECT_ROOT = Path(__file__).resolve().parents[2]
APP_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL_DIR = APP_ROOT / "models"
DEFAULT_DATASET = PROJECT_ROOT / "datasets" / "esp32-cam" / "esp32_win3_dataset.csv"
DEFAULT_DB_URL = os.getenv(
    "DATABASE_URL", "postgresql://safeon:0987@localhost:5432/safeon"
)


# ---------------------------------------------------
# Models and schema
# ---------------------------------------------------
class TransformerAE(nn.Module):
    """Transformer-based autoencoder for sequence reconstruction."""

    def __init__(self, num_features: int, seq_len: int, emb_dim: int = 64, nhead: int = 4, num_layers: int = 2):
        super().__init__()
        self.input_layer = nn.Linear(num_features, emb_dim)

        encoder_layer = nn.TransformerEncoderLayer(
            d_model=emb_dim, nhead=nhead, batch_first=True
        )
        self.encoder = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)

        decoder_layer = nn.TransformerDecoderLayer(
            d_model=emb_dim, nhead=nhead, batch_first=True
        )
        self.decoder = nn.TransformerDecoder(decoder_layer, num_layers=num_layers)

        self.output_layer = nn.Linear(emb_dim, num_features)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x_emb = self.input_layer(x)
        encoded = self.encoder(x_emb)
        decoded = self.decoder(x_emb, encoded)
        out = self.output_layer(decoded)
        return out


class FlowFeatures(BaseModel):
    """Pydantic model for incoming flow records."""

    src_ip: str
    dst_ip: str
    src_port: int
    dst_port: int
    proto: str
    packet_count: int
    byte_count: int
    duration: Optional[float] = None
    pps: float
    bps: float
    start_time: Optional[float] = None
    end_time: Optional[float] = None

    @validator("duration", pre=True, always=True)
    def compute_duration(cls, v, values) -> float:  # noqa: D417
        """Back-fill duration if missing using start/end timestamps."""
        if v is not None:
            return float(v)
        start_time = values.get("start_time")
        end_time = values.get("end_time")
        if start_time is not None and end_time is not None and end_time >= start_time:
            return float(end_time - start_time)
        return 0.0

    @validator("proto", pre=True)
    def normalize_proto(cls, v) -> str:  # noqa: D417
        return str(v).upper()

    def as_frame(self, feature_order: List[str]) -> pd.DataFrame:
        data = {
            "src_ip": self.src_ip,
            "dst_ip": self.dst_ip,
            "src_port": self.src_port,
            "dst_port": self.dst_port,
            "proto": self.proto,
            "packet_count": self.packet_count,
            "byte_count": self.byte_count,
            "duration": self.duration,
            "pps": self.pps,
            "bps": self.bps,
        }
        return pd.DataFrame([data])[feature_order]


@dataclass
class ArtifactPaths:
    enc_src_ip: Path
    enc_dst_ip: Path
    enc_proto: Path
    scaler: Path
    isolation_forest: Path
    transformer: Path
    meta: Path


# ---------------------------------------------------
# Service
# ---------------------------------------------------
class ModelService:
    """Wraps preprocessing, model inference, and DB persistence."""

    feature_columns = [
        "src_ip",
        "dst_ip",
        "src_port",
        "dst_port",
        "proto",
        "packet_count",
        "byte_count",
        "duration",
        "pps",
        "bps",
    ]

    def __init__(
        self,
        model_dir: Path = DEFAULT_MODEL_DIR,
        dataset_path: Path = DEFAULT_DATASET,
        database_url: Optional[str] = DEFAULT_DB_URL,
        allow_dummy: bool = True,
        seq_len: int = 20,
        threshold: float = 0.35,
    ) -> None:
        self.model_dir = Path(model_dir)
        self.dataset_path = Path(dataset_path)
        self.database_url = database_url
        self.allow_dummy = allow_dummy
        self.seq_len = seq_len
        self.threshold = threshold
        self.num_features = len(self.feature_columns)
        self.packet_buffer: List[np.ndarray] = []

        self.device = torch.device(
            "mps"
            if torch.backends.mps.is_available()
            else ("cuda" if torch.cuda.is_available() else "cpu")
        )
        # 가능하면 GPU/MPS를 활용해 학습·추론 속도를 확보한다.

        self.paths = ArtifactPaths(
            enc_src_ip=self.model_dir / "enc_src_ip.pkl",
            enc_dst_ip=self.model_dir / "enc_dst_ip.pkl",
            enc_proto=self.model_dir / "enc_proto.pkl",
            scaler=self.model_dir / "scaler.pkl",
            isolation_forest=self.model_dir / "isolation_forest.pkl",
            transformer=self.model_dir / "transformer_ae.pth",
            meta=self.model_dir / "meta.json",
        )

        self.enc_src_ip: Optional[LabelEncoder] = None
        self.enc_dst_ip: Optional[LabelEncoder] = None
        self.enc_proto: Optional[LabelEncoder] = None
        self.scaler: Optional[MinMaxScaler] = None
        self.iso_model: Optional[IsolationForest] = None
        self.transformer: Optional[TransformerAE] = None
        self.engine = create_engine(self.database_url) if self.database_url else None
        self.model_loaded = False

        os.makedirs(self.model_dir, exist_ok=True)
        self._load_artifacts()

    # ---------------------------------------------------
    # Construction helpers
    # ---------------------------------------------------
    @classmethod
    def from_env(cls) -> "ModelService":
        allow_dummy = os.getenv("ALLOW_DUMMY", "true").lower() != "false"
        seq_len = int(os.getenv("SEQ_LEN", "20"))
        threshold = float(os.getenv("ANOMALY_THRESHOLD", "0.35"))

        model_dir = Path(os.getenv("MODEL_DIR", DEFAULT_MODEL_DIR))
        dataset_path = Path(os.getenv("DATASET_PATH", DEFAULT_DATASET))
        database_url = os.getenv("DATABASE_URL", DEFAULT_DB_URL)

        return cls(
            model_dir=model_dir,
            dataset_path=dataset_path,
            database_url=database_url,
            allow_dummy=allow_dummy,
            seq_len=seq_len,
            threshold=threshold,
        )

    # ---------------------------------------------------
    # Training
    # ---------------------------------------------------
    def train(self, dataset_path: Optional[Path] = None, epochs: int = 10, batch_size: int = 32) -> Dict[str, str]:
        path = Path(dataset_path or self.dataset_path)
        if not path.exists():
            raise FileNotFoundError(f"Dataset not found at {path}")

        LOGGER.info("Loading dataset from %s", path)
        df = pd.read_csv(path)
        missing = [c for c in self.feature_columns + ["label"] if c not in df.columns]
        if missing:
            raise ValueError(f"Dataset is missing required columns: {', '.join(missing)}")

        df = df.dropna(subset=self.feature_columns + ["label"]).copy()
        df["proto"] = df["proto"].astype(str).str.upper()

        # 문자열 기반 특성은 라벨 인코더로 숫자형으로 치환한다.
        self.enc_src_ip = LabelEncoder().fit(df["src_ip"])
        self.enc_dst_ip = LabelEncoder().fit(df["dst_ip"])
        self.enc_proto = LabelEncoder().fit(df["proto"])

        encoded = pd.DataFrame(
            {
                "src_ip": self.enc_src_ip.transform(df["src_ip"]),
                "dst_ip": self.enc_dst_ip.transform(df["dst_ip"]),
                "src_port": df["src_port"].astype(int),
                "dst_port": df["dst_port"].astype(int),
                "proto": self.enc_proto.transform(df["proto"]),
                "packet_count": df["packet_count"].astype(int),
                "byte_count": df["byte_count"].astype(int),
                "duration": df["duration"].astype(float),
                "pps": df["pps"].astype(float),
                "bps": df["bps"].astype(float),
            }
        )

        self.scaler = MinMaxScaler()
        scaled = self.scaler.fit_transform(encoded[self.feature_columns])
        labels = df["label"].astype(int).to_numpy()

        joblib.dump(self.enc_src_ip, self.paths.enc_src_ip)
        joblib.dump(self.enc_dst_ip, self.paths.enc_dst_ip)
        joblib.dump(self.enc_proto, self.paths.enc_proto)
        joblib.dump(self.scaler, self.paths.scaler)

        LOGGER.info("Training IsolationForest")
        # 1차 이상징후 후보를 찾기 위해 IsolationForest를 학습한다.
        self.iso_model = IsolationForest(contamination=0.05, random_state=42)
        self.iso_model.fit(scaled)
        joblib.dump(self.iso_model, self.paths.isolation_forest)

        sequences, seq_labels = self._create_sequences(scaled, labels, self.seq_len)
        if len(sequences) == 0:
            raise ValueError(f"Not enough rows ({len(scaled)}) to build sequences of length {self.seq_len}. Reduce SEQ_LEN or add data.")
        normal_sequences = sequences[seq_labels == 0]
        if len(normal_sequences) == 0:
            raise ValueError("No normal sequences available for autoencoder training.")

        # 정상 시퀀스를 Reconstruction 기반 AE 학습용으로만 사용한다.
        dataset = DataLoader(
            TensorDataset(
                torch.tensor(normal_sequences, dtype=torch.float32),
                torch.tensor(normal_sequences, dtype=torch.float32),
            ),
            batch_size=batch_size,
            shuffle=True,
        )

        LOGGER.info("Training Transformer Autoencoder on %s using %s", self.device, normal_sequences.shape)
        self.transformer = TransformerAE(num_features=scaled.shape[1], seq_len=self.seq_len).to(self.device)
        optimizer = torch.optim.Adam(self.transformer.parameters(), lr=1e-3)
        criterion = nn.MSELoss()

        for epoch in range(1, epochs + 1):
            self.transformer.train()
            epoch_loss = 0.0
            for batch_x, _ in dataset:
                batch_x = batch_x.to(self.device)
                optimizer.zero_grad()
                recon = self.transformer(batch_x)
                loss = criterion(recon, batch_x)
                loss.backward()
                optimizer.step()
                epoch_loss += loss.item()
            LOGGER.info("AE epoch %s/%s - loss=%.6f", epoch, epochs, epoch_loss)

        torch.save(self.transformer.state_dict(), self.paths.transformer)
        meta = {
            "seq_len": self.seq_len,
            "feature_columns": self.feature_columns,
        }
        self.paths.meta.write_text(json.dumps(meta, indent=2))

        self._load_artifacts()
        return {
            "dataset": str(path),
            "model_dir": str(self.model_dir),
            "device": str(self.device),
        }

    # ---------------------------------------------------
    # Prediction
    # ---------------------------------------------------
    def predict(
        self,
        flow: FlowFeatures,
        user_id: Optional[str] = None,
        timestamp: Optional[datetime] = None,
    ) -> Dict[str, object]:
        ts = timestamp or datetime.now(timezone.utc)
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)

        if not self.model_loaded:
            if not self.allow_dummy:
                raise RuntimeError("Trained model is missing. Run train.py first or set ALLOW_DUMMY=true.")
            return self._dummy_result(ts)

        scaled_vec = self._transform_flow(flow)

        # IsolationForest와 AE 점수를 혼합해 최종 이상 점수를 만든다.
        iso_score = float(max(0.0, min(1.0, -self.iso_model.decision_function([scaled_vec])[0])))
        ae_score = float(self._ae_score(scaled_vec))
        hybrid_score = float(0.5 * iso_score + 0.5 * ae_score)
        is_anom = hybrid_score >= self.threshold
        record_id = self._persist_score(
            ts=ts,
            iso_score=iso_score,
            ae_score=ae_score,
            hybrid_score=hybrid_score,
            is_anom=is_anom,
            user_id=user_id,
        )

        return {
            "is_anom": is_anom,
            "iso_score": iso_score,
            "ae_score": ae_score,
            "hybrid_score": hybrid_score,
        }

    # ---------------------------------------------------
    # Internals
    # ---------------------------------------------------
    def _load_artifacts(self) -> None:
        required = [
            self.paths.enc_src_ip,
            self.paths.enc_dst_ip,
            self.paths.enc_proto,
            self.paths.scaler,
            self.paths.isolation_forest,
            self.paths.transformer,
        ]

        if not all(path.exists() for path in required):
            LOGGER.info("Model artifacts not found. Running in dummy mode until training is executed.")
            self.model_loaded = False
            return

        # 저장된 인코더/스케일러/모델 파라미터를 전부 메모리로 적재한다.
        LOGGER.info("Loading model artifacts from %s", self.model_dir)
        self.enc_src_ip = joblib.load(self.paths.enc_src_ip)
        self.enc_dst_ip = joblib.load(self.paths.enc_dst_ip)
        self.enc_proto = joblib.load(self.paths.enc_proto)
        self.scaler = joblib.load(self.paths.scaler)
        self.iso_model = joblib.load(self.paths.isolation_forest)

        if self.paths.meta.exists():
            try:
                meta = json.loads(self.paths.meta.read_text())
                self.seq_len = int(meta.get("seq_len", self.seq_len))
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("Failed to parse meta.json: %s", exc)

        self.transformer = TransformerAE(num_features=self.num_features, seq_len=self.seq_len).to(self.device)
        self.transformer.load_state_dict(torch.load(self.paths.transformer, map_location=self.device))
        self.transformer.eval()

        self.model_loaded = True

    def _create_sequences(self, data: np.ndarray, labels: np.ndarray, seq_len: int) -> Tuple[np.ndarray, np.ndarray]:
        X, y = [], []
        for i in range(len(data) - seq_len):
            X.append(data[i : i + seq_len])
            y.append(labels[i + seq_len])
        return np.array(X), np.array(y)

    def _safe_label_encode(self, encoder: LabelEncoder, value: str) -> int:
        classes = set(encoder.classes_.tolist())
        if value not in classes:
            return -1
        # 미리 학습된 클래스에만 존재하는 값을 안전하게 숫자로 변환한다.
        return int(encoder.transform([value])[0])

    def _transform_flow(self, flow: FlowFeatures) -> np.ndarray:
        if not all([self.enc_src_ip, self.enc_dst_ip, self.enc_proto, self.scaler]):
            raise RuntimeError("Model artifacts are not loaded.")

        df = flow.as_frame(self.feature_columns)
        df["src_ip"] = df["src_ip"].astype(str)
        df["dst_ip"] = df["dst_ip"].astype(str)
        df["proto"] = df["proto"].astype(str).str.upper()

        df["src_ip"] = [self._safe_label_encode(self.enc_src_ip, ip) for ip in df["src_ip"]]
        df["dst_ip"] = [self._safe_label_encode(self.enc_dst_ip, ip) for ip in df["dst_ip"]]
        df["proto"] = [self._safe_label_encode(self.enc_proto, p) for p in df["proto"]]

        scaled = self.scaler.transform(df[self.feature_columns])
        return scaled[0]

    def _ae_score(self, scaled_vec: np.ndarray) -> float:
        if self.transformer is None:
            return 0.0

        self.packet_buffer.append(scaled_vec)
        if len(self.packet_buffer) < self.seq_len:
            return 0.0
        if len(self.packet_buffer) > self.seq_len:
            self.packet_buffer = self.packet_buffer[-self.seq_len :]

        # 최신 seq_len개 패킷만 유지해 시계열 입력을 구성한다.
        seq = np.array(self.packet_buffer).reshape(1, self.seq_len, self.num_features)
        seq_t = torch.tensor(seq, dtype=torch.float32).to(self.device)

        with torch.no_grad():
            recon = self.transformer(seq_t)
        mse = torch.mean((seq_t - recon) ** 2).item()
        return float(min(1.0, mse * 10))

    def _persist_score(
        self,
        ts: datetime,
        iso_score: float,
        ae_score: float,
        hybrid_score: float,
        is_anom: bool,
        user_id: Optional[str],
    ) -> Optional[UUID]:
        if not self.engine:
            return None

        # 추론 결과를 DB anomaly_scores 테이블에 기록한다.
        payload = {
            "score_id": uuid4(),
            "ts": ts,
            "packet_meta_id": None,
            "alert_id": None,
            "iso_score": iso_score,
            "ae_score": ae_score,
            "hybrid_score": hybrid_score,
            "is_anom": is_anom,
        }

        query = text(
            """
            INSERT INTO anomaly_scores (
                score_id, ts, packet_meta_id, alert_id, iso_score, ae_score, hybrid_score, is_anom
            )
            VALUES (:score_id, :ts, :packet_meta_id, :alert_id, :iso_score, :ae_score, :hybrid_score, :is_anom)
            """
        )

        try:
            with self.engine.begin() as conn:
                conn.execute(query, payload)
            return payload["score_id"]
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("Failed to persist anomaly score to DB: %s", exc)
            return None

    def _dummy_result(self, ts: datetime) -> Dict[str, object]:
        return {
            "is_anom": False,
            "iso_score": 0.0,
            "ae_score": 0.0,
            "hybrid_score": 0.0,
        }
