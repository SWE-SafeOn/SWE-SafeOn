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
from lightgbm import LGBMClassifier
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
class FeedForwardAE(nn.Module):
    """Fully-connected autoencoder for single flow reconstruction."""

    def __init__(self, num_features: int, hidden_dim: int = 64, bottleneck: int = 16):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(num_features, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, bottleneck),
            nn.ReLU(),
        )
        self.decoder = nn.Sequential(
            nn.Linear(bottleneck, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, num_features),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        encoded = self.encoder(x)
        return self.decoder(encoded)


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
    pps_delta: Optional[float] = None
    bps_delta: Optional[float] = None

    @validator("start_time", "end_time", pre=True)
    def parse_timestamp(cls, v) -> Optional[float]:  # noqa: D417
        """Parse ISO-8601 or epoch timestamps into float seconds."""
        if v is None:
            return None
        if isinstance(v, (int, float)):
            return float(v)
        if isinstance(v, datetime):
            ts = v
        elif isinstance(v, str):
            try:
                ts = datetime.fromisoformat(v)
            except ValueError:
                return None
        else:
            return None

        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        return float(ts.timestamp())

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
            "pps_delta": 0.0 if self.pps_delta is None else self.pps_delta,
            "bps_delta": 0.0 if self.bps_delta is None else self.bps_delta,
        }
        return pd.DataFrame([data])[feature_order]


@dataclass
class ArtifactPaths:
    enc_src_ip: Path
    enc_dst_ip: Path
    enc_proto: Path
    scaler: Path
    isolation_forest: Path
    autoencoder: Path
    meta: Path
    lgbm: Path


# ---------------------------------------------------
# Service
# ---------------------------------------------------
class ModelService:
    """Wraps preprocessing, model inference, and DB persistence."""

    base_feature_columns = [
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
    feature_columns = base_feature_columns + ["pps_delta", "bps_delta"]

    def __init__(
        self,
        model_dir: Path = DEFAULT_MODEL_DIR,
        dataset_path: Path = DEFAULT_DATASET,
        database_url: Optional[str] = DEFAULT_DB_URL,
        allow_dummy: bool = True,
        threshold: float = 0.35,
    ) -> None:
        self.model_dir = Path(model_dir)
        self.dataset_path = Path(dataset_path)
        self.database_url = database_url
        self.allow_dummy = allow_dummy
        self.threshold = threshold
        self.num_features = len(self.feature_columns)

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
            autoencoder=self.model_dir / "autoencoder.pth",
            meta=self.model_dir / "meta.json",
            lgbm=self.model_dir / "lgbm.pkl",
        )

        self.enc_src_ip: Optional[LabelEncoder] = None
        self.enc_dst_ip: Optional[LabelEncoder] = None
        self.enc_proto: Optional[LabelEncoder] = None
        self.scaler: Optional[MinMaxScaler] = None
        self.iso_model: Optional[IsolationForest] = None
        self.autoencoder: Optional[FeedForwardAE] = None
        self.gbm_model: Optional[LGBMClassifier] = None
        self.iso_decision_min: float = 0.0
        self.iso_decision_max: float = 1.0
        self.engine = create_engine(self.database_url) if self.database_url else None
        self.model_loaded = False
        self.prev_flow_stats: Dict[Tuple[str, str, int, int, str], Tuple[float, float]] = {}

        os.makedirs(self.model_dir, exist_ok=True)
        self._load_artifacts()

    # ---------------------------------------------------
    # Construction helpers
    # ---------------------------------------------------
    @classmethod
    def from_env(cls) -> "ModelService":
        allow_dummy = os.getenv("ALLOW_DUMMY", "true").lower() != "false"
        threshold = float(os.getenv("ANOMALY_THRESHOLD", "0.35"))

        model_dir = Path(os.getenv("MODEL_DIR", DEFAULT_MODEL_DIR))
        dataset_path = Path(os.getenv("DATASET_PATH", DEFAULT_DATASET))
        database_url = os.getenv("DATABASE_URL", DEFAULT_DB_URL)

        return cls(
            model_dir=model_dir,
            dataset_path=dataset_path,
            database_url=database_url,
            allow_dummy=allow_dummy,
            threshold=threshold,
        )

    # ---------------------------------------------------
    # Training
    # ---------------------------------------------------
    def train(self, dataset_path: Optional[Path] = None, epochs: int = 20, batch_size: int = 32) -> Dict[str, str]:
        path = Path(dataset_path or self.dataset_path)
        if not path.exists():
            raise FileNotFoundError(f"Dataset not found at {path}")

        LOGGER.info("Loading dataset from %s", path)
        df = pd.read_csv(path)
        missing = [c for c in self.base_feature_columns + ["label"] if c not in df.columns]
        if missing:
            raise ValueError(f"Dataset is missing required columns: {', '.join(missing)}")

        df = df.dropna(subset=self.base_feature_columns + ["label"]).copy()
        df["proto"] = df["proto"].astype(str).str.upper()
        df["src_port"] = df["src_port"].astype(int)
        df["dst_port"] = df["dst_port"].astype(int)
        df["packet_count"] = df["packet_count"].astype(int)
        df["byte_count"] = df["byte_count"].astype(int)
        df["duration"] = df["duration"].astype(float)
        df["pps"] = df["pps"].astype(float)
        df["bps"] = df["bps"].astype(float)
        df = self._inject_rate_deltas(df)
        df["pps"] = np.log1p(df["pps"])
        df["bps"] = np.log1p(df["bps"])

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
                "pps_delta": df["pps_delta"].astype(float),
                "bps_delta": df["bps_delta"].astype(float),
            }
        )

        normal_mask = df["label"].astype(int) == 0
        if not normal_mask.any():
            raise ValueError("No normal samples (label=0) found for training.")

        self.scaler = MinMaxScaler()
        normal_encoded = encoded.loc[normal_mask, self.feature_columns]
        scaled_normal = self.scaler.fit_transform(normal_encoded)
        labels_normal = df.loc[normal_mask, "label"].astype(int).to_numpy()
        scaled_all = self.scaler.transform(encoded[self.feature_columns])
        labels_all = df["label"].astype(int).to_numpy()

        joblib.dump(self.enc_src_ip, self.paths.enc_src_ip)
        joblib.dump(self.enc_dst_ip, self.paths.enc_dst_ip)
        joblib.dump(self.enc_proto, self.paths.enc_proto)
        joblib.dump(self.scaler, self.paths.scaler)

        LOGGER.info("Training IsolationForest on normal samples only")
        # 1차 이상징후 후보를 찾기 위해 IsolationForest를 학습한다.
        self.iso_model = IsolationForest(contamination=0.05, random_state=42)
        self.iso_model.fit(scaled_normal)
        joblib.dump(self.iso_model, self.paths.isolation_forest)
        iso_decisions_all = self.iso_model.decision_function(scaled_all)
        self.iso_decision_min = float(np.min(iso_decisions_all))
        self.iso_decision_max = float(np.max(iso_decisions_all))
        if self.iso_decision_max - self.iso_decision_min <= 1e-9:
            self.iso_decision_max = self.iso_decision_min + 1e-6

        tensor_normal = torch.tensor(scaled_normal, dtype=torch.float32)
        dataset = DataLoader(
            tensor_normal,
            batch_size=batch_size,
            shuffle=True,
        )

        LOGGER.info("Training FeedForward Autoencoder on %s using %s samples", self.device, tensor_normal.shape)
        self.autoencoder = FeedForwardAE(num_features=scaled_normal.shape[1]).to(self.device)
        optimizer = torch.optim.Adam(self.autoencoder.parameters(), lr=1e-3)
        criterion = nn.MSELoss()

        for epoch in range(1, epochs + 1):
            self.autoencoder.train()
            epoch_loss = 0.0
            for batch_x in dataset:
                batch_x = batch_x.to(self.device)
                optimizer.zero_grad()
                recon = self.autoencoder(batch_x)
                loss = criterion(recon, batch_x)
                loss.backward()
                optimizer.step()
                epoch_loss += loss.item()
            LOGGER.info("AE epoch %s/%s - loss=%.6f", epoch, epochs, epoch_loss)

        self.autoencoder.eval()
        torch.save(self.autoencoder.state_dict(), self.paths.autoencoder)

        LOGGER.info("Training LightGBM classifier on labeled data")
        self.gbm_model = LGBMClassifier(
            n_estimators=500,
            learning_rate=0.05,
            max_depth=-1,
            subsample=0.8,
            colsample_bytree=0.8,
            random_state=42,
            class_weight="balanced",
        )
        self.gbm_model.fit(scaled_all, labels_all)
        joblib.dump(self.gbm_model, self.paths.lgbm)

        self.threshold = self._calculate_threshold(scaled_all, labels_all)
        meta = {
            "feature_columns": self.feature_columns,
            "threshold": self.threshold,
            "ae_type": "feedforward",
            "iso_decision_min": self.iso_decision_min,
            "iso_decision_max": self.iso_decision_max,
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
        packet_meta_id: Optional[object] = None,
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
        iso_score = self._iso_score(scaled_vec)
        ae_score = float(self._ae_score(scaled_vec) or 0.0)
        gbm_score = None
        if self.gbm_model is not None:
            try:
                gbm_score = float(self.gbm_model.predict_proba([scaled_vec])[0][1])
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("LightGBM prediction failed: %s", exc)
        gbm_contrib = gbm_score if gbm_score is not None else 0.5
        hybrid_score = float((iso_score + ae_score + gbm_contrib) / 3.0)
        is_anom = hybrid_score >= self.threshold
        record_id = self._persist_score(
            ts=ts,
            iso_score=iso_score,
            ae_score=ae_score,
            gbm_score=gbm_score,
            hybrid_score=hybrid_score,
            is_anom=is_anom,
            user_id=user_id,
            packet_meta_id=self._coerce_uuid(packet_meta_id),
        )

        return {
            "is_anom": is_anom,
            "iso_score": iso_score,
            "ae_score": ae_score,
            "hybrid_score": hybrid_score,
            "gbm_score": gbm_score
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
            self.paths.autoencoder,
        ]

        if not all(path.exists() for path in required):
            LOGGER.info("Model artifacts not found. Running in dummy mode until training is executed.")
            self.model_loaded = False
            self.prev_flow_stats.clear()
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
                self.threshold = float(meta.get("threshold", self.threshold))
                self.iso_decision_min = float(meta.get("iso_decision_min", self.iso_decision_min))
                self.iso_decision_max = float(meta.get("iso_decision_max", self.iso_decision_max))
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("Failed to parse meta.json: %s", exc)

        self.autoencoder = FeedForwardAE(num_features=self.num_features).to(self.device)
        try:
            state_dict = torch.load(self.paths.autoencoder, map_location=self.device)
            self.autoencoder.load_state_dict(state_dict)
            self.autoencoder.eval()
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("Failed to load feedforward AE weights. Retrain required: %s", exc)
            self.autoencoder = None
        if self.paths.lgbm.exists():
            try:
                self.gbm_model = joblib.load(self.paths.lgbm)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("Failed to load LightGBM weights: %s", exc)
                self.gbm_model = None
        else:
            self.gbm_model = None

        self.prev_flow_stats.clear()
        self.model_loaded = all([self.iso_model, self.autoencoder, self.gbm_model])

    def _safe_label_encode(self, encoder: LabelEncoder, value: str) -> int:
        classes = set(encoder.classes_.tolist())
        if value not in classes:
            return -1
        # 미리 학습된 클래스에만 존재하는 값을 안전하게 숫자로 변환한다.
        return int(encoder.transform([value])[0])

    def _flow_key(self, flow: FlowFeatures) -> Tuple[str, str, int, int, str]:
        return (
            str(flow.src_ip),
            str(flow.dst_ip),
            int(flow.src_port),
            int(flow.dst_port),
            str(flow.proto).upper(),
        )

    def _resolve_flow_deltas(self, flow: FlowFeatures, current_pps: float, current_bps: float) -> Tuple[float, float]:
        key = self._flow_key(flow)
        prev_pps, prev_bps = self.prev_flow_stats.get(key, (current_pps, current_bps))
        delta_pps = float(current_pps - prev_pps)
        delta_bps = float(current_bps - prev_bps)
        if flow.pps_delta is not None:
            try:
                delta_pps = float(flow.pps_delta)
            except (TypeError, ValueError):
                delta_pps = float(current_pps - prev_pps)
        if flow.bps_delta is not None:
            try:
                delta_bps = float(flow.bps_delta)
            except (TypeError, ValueError):
                delta_bps = float(current_bps - prev_bps)

        self.prev_flow_stats[key] = (current_pps, current_bps)
        return delta_pps, delta_bps

    def _transform_flow(self, flow: FlowFeatures) -> np.ndarray:
        if not all([self.enc_src_ip, self.enc_dst_ip, self.enc_proto, self.scaler]):
            raise RuntimeError("Model artifacts are not loaded.")

        df = flow.as_frame(self.feature_columns)
        df["src_ip"] = df["src_ip"].astype(str)
        df["dst_ip"] = df["dst_ip"].astype(str)
        df["proto"] = df["proto"].astype(str).str.upper()
        df["src_port"] = df["src_port"].astype(int)
        df["dst_port"] = df["dst_port"].astype(int)
        df["packet_count"] = df["packet_count"].astype(int)
        df["byte_count"] = df["byte_count"].astype(int)
        df["duration"] = df["duration"].astype(float)
        df["pps"] = df["pps"].astype(float)
        df["bps"] = df["bps"].astype(float)

        pps_delta, bps_delta = self._resolve_flow_deltas(flow, float(df.at[0, "pps"]), float(df.at[0, "bps"]))
        df.loc[:, "pps_delta"] = pps_delta
        df.loc[:, "bps_delta"] = bps_delta

        df["pps"] = np.log1p(df["pps"])
        df["bps"] = np.log1p(df["bps"])

        df["src_ip"] = [self._safe_label_encode(self.enc_src_ip, ip) for ip in df["src_ip"]]
        df["dst_ip"] = [self._safe_label_encode(self.enc_dst_ip, ip) for ip in df["dst_ip"]]
        df["proto"] = [self._safe_label_encode(self.enc_proto, p) for p in df["proto"]]

        scaled = self.scaler.transform(df[self.feature_columns])
        return scaled[0]

    def _ae_score(self, scaled_vec: np.ndarray) -> Optional[float]:
        if self.autoencoder is None:
            return None

        tensor = torch.tensor(scaled_vec.reshape(1, -1), dtype=torch.float32).to(self.device)

        with torch.no_grad():
            recon = self.autoencoder(tensor)
        mse = torch.mean((tensor - recon) ** 2).item()
        return float(min(1.0, mse * 10))

    def _iso_score(self, scaled_vec: np.ndarray) -> float:
        if self.iso_model is None:
            return 0.0
        raw = float(self.iso_model.decision_function([scaled_vec])[0])
        span = self.iso_decision_max - self.iso_decision_min
        if span <= 1e-9:
            # Fallback to simple negation if calibration info is missing.
            return float(max(0.0, min(1.0, -raw)))
        score = (self.iso_decision_max - raw) / span
        return float(max(0.0, min(1.0, score)))

    def _calculate_threshold(self, scaled: np.ndarray, labels: np.ndarray) -> float:
        if self.iso_model is None:
            return self.threshold

        hybrid_scores = self._compute_hybrid_scores(scaled)
        normal_scores = [score for score, label in zip(hybrid_scores, labels) if label == 0]
        attack_scores = [score for score, label in zip(hybrid_scores, labels) if label != 0]

        if not normal_scores or not attack_scores:
            LOGGER.warning(
                "Unable to compute threshold (normal=%s, attack=%s). Retaining %.4f",
                len(normal_scores),
                len(attack_scores),
                self.threshold,
            )
            return self.threshold

        normal_stat = float(np.max(normal_scores))
        attack_stat = float(np.min(attack_scores))
        threshold = float(0.5 * (normal_stat + attack_stat))
        LOGGER.info(
            "Computed threshold %.4f (max normal=%.4f, min attack=%.4f)",
            threshold,
            normal_stat,
            attack_stat,
        )
        return threshold

    def _compute_hybrid_scores(self, scaled: np.ndarray) -> List[float]:
        scores: List[float] = []
        for vec in scaled:
            iso_score = self._iso_score(vec)
            ae_score = self._ae_score(vec) or 0.0
            gbm_score = (
                float(self.gbm_model.predict_proba([vec])[0][1])
                if self.gbm_model is not None
                else 0.5
            )
            scores.append(float((iso_score + ae_score + gbm_score) / 3.0))
        return scores

    def _inject_rate_deltas(self, df: pd.DataFrame) -> pd.DataFrame:
        working = df.copy()
        working["_orig_idx"] = np.arange(len(working))
        working["_ts"] = pd.to_datetime(working.get("start_time"), errors="coerce")
        sort_cols = [
            "src_ip",
            "dst_ip",
            "src_port",
            "dst_port",
            "proto",
            "_ts",
            "_orig_idx",
        ]
        working = working.sort_values(sort_cols)
        group_cols = ["src_ip", "dst_ip", "src_port", "dst_port", "proto"]
        working["pps_delta"] = working.groupby(group_cols)["pps"].diff().fillna(0.0)
        working["bps_delta"] = working.groupby(group_cols)["bps"].diff().fillna(0.0)
        working = working.sort_values("_orig_idx").drop(columns=["_orig_idx", "_ts"])
        working["pps_delta"] = working["pps_delta"].replace([np.inf, -np.inf], 0.0).fillna(0.0)
        working["bps_delta"] = working["bps_delta"].replace([np.inf, -np.inf], 0.0).fillna(0.0)
        return working

    def _persist_score(
        self,
        ts: datetime,
        iso_score: float,
        ae_score: float,
        gbm_score: Optional[float],
        hybrid_score: float,
        is_anom: bool,
        user_id: Optional[str],
        packet_meta_id: Optional[UUID],
    ) -> Optional[UUID]:
        if not self.engine:
            return None

        # 추론 결과를 DB anomaly_scores 테이블에 기록한다.
        payload = {
            "score_id": uuid4(),
            "ts": ts,
            "packet_meta_id": packet_meta_id,
            "alert_id": None,
            "iso_score": iso_score,
            "ae_score": ae_score,
            "gbm_score": gbm_score,
            "hybrid_score": hybrid_score,
            "is_anom": is_anom,
        }

        query = text(
            """
            INSERT INTO anomaly_scores (
                score_id, ts, packet_meta_id, alert_id, iso_score, ae_score, gbm_score, hybrid_score, is_anom
            )
            VALUES (:score_id, :ts, :packet_meta_id, :alert_id, :iso_score, :ae_score, :gbm_score, :hybrid_score, :is_anom)
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
            "gbm_score": 0.5,
        }

    def _coerce_uuid(self, value: Optional[object]) -> Optional[UUID]:
        """Safely parse UUID-like values coming from external payloads."""
        if value is None:
            return None
        if isinstance(value, UUID):
            return value
        try:
            return UUID(str(value))
        except Exception:  # noqa: BLE001
            LOGGER.warning("Ignoring invalid UUID value: %s", value)
            return None
