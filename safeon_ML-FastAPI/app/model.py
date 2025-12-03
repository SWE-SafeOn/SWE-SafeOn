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
from pydantic import BaseModel, validator
from sklearn.ensemble import IsolationForest, RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, MinMaxScaler
from sqlalchemy import create_engine, text

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
DEFAULT_DATASET = PROJECT_ROOT / "datasets" / "esp32-cam" / "dataset.csv"
DEFAULT_ATTACKER_DATASET = PROJECT_ROOT / "datasets" / "esp32-cam" / "attacker.csv"
DEFAULT_DB_URL = os.getenv(
    "DATABASE_URL", "postgresql://safeon:0987@localhost:5432/safeon"
)


# ---------------------------------------------------
# Models and schema
# ---------------------------------------------------
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
    pps_cum_increase: Optional[float] = None
    bps_cum_increase: Optional[float] = None

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
            "pps_cum_increase": 0.0 if self.pps_cum_increase is None else self.pps_cum_increase,
            "bps_cum_increase": 0.0 if self.bps_cum_increase is None else self.bps_cum_increase,
        }
        return pd.DataFrame([data])[feature_order]


@dataclass
class ArtifactPaths:
    enc_src_ip: Path
    enc_dst_ip: Path
    enc_proto: Path
    scaler: Path
    isolation_forest: Path
    meta: Path
    rf_model: Path


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
    feature_columns = base_feature_columns + [
        "pps_delta",
        "bps_delta",
        "pps_cum_increase",
        "bps_cum_increase",
    ]
    # delta 특성을 포함해 정적 값 + 변화량을 동시에 학습한다.

    def __init__(
        self,
        model_dir: Path = DEFAULT_MODEL_DIR,
        dataset_path: Path = DEFAULT_DATASET,
        attacker_dataset_path: Optional[Path] = DEFAULT_ATTACKER_DATASET,
        database_url: Optional[str] = DEFAULT_DB_URL,
        allow_dummy: bool = True,
        threshold: float = 0.51,
    ) -> None:
        self.model_dir = Path(model_dir)
        self.dataset_path = Path(dataset_path)
        self.attacker_dataset_path = Path(attacker_dataset_path) if attacker_dataset_path else None
        self.database_url = database_url
        self.allow_dummy = allow_dummy
        self.threshold = threshold

        self.paths = ArtifactPaths(
            enc_src_ip=self.model_dir / "enc_src_ip.pkl",
            enc_dst_ip=self.model_dir / "enc_dst_ip.pkl",
            enc_proto=self.model_dir / "enc_proto.pkl",
            scaler=self.model_dir / "scaler.pkl",
            isolation_forest=self.model_dir / "isolation_forest.pkl",
            meta=self.model_dir / "meta.json",
            rf_model=self.model_dir / "rf_model.pkl",
        )

        self.enc_src_ip: Optional[LabelEncoder] = None
        self.enc_dst_ip: Optional[LabelEncoder] = None
        self.enc_proto: Optional[LabelEncoder] = None
        self.scaler: Optional[MinMaxScaler] = None
        self.iso_model: Optional[IsolationForest] = None
        self.rf_model: Optional[RandomForestClassifier] = None
        self.iso_decision_min: float = 0.0
        self.iso_decision_max: float = 1.0
        self.engine = create_engine(self.database_url) if self.database_url else None
        self.model_loaded = False
        self.prev_flow_stats: Dict[str, Tuple[float, float, float, float]] = {}
        # 최근 플로우의 pps/bps를 기억해 추론 시 delta를 보정한다.

        os.makedirs(self.model_dir, exist_ok=True)
        self._load_artifacts()

    # ---------------------------------------------------
    # Construction helpers
    # ---------------------------------------------------
    @classmethod
    def from_env(cls) -> "ModelService":
        allow_dummy = os.getenv("ALLOW_DUMMY", "true").lower() != "false"
        threshold = float(os.getenv("ANOMALY_THRESHOLD", "0.51"))

        model_dir = Path(os.getenv("MODEL_DIR", DEFAULT_MODEL_DIR))
        dataset_path = Path(os.getenv("DATASET_PATH", DEFAULT_DATASET))
        database_url = os.getenv("DATABASE_URL", DEFAULT_DB_URL)
        attacker_dataset_path = os.getenv("ATTACKER_DATASET_PATH", str(DEFAULT_ATTACKER_DATASET))

        return cls(
            model_dir=model_dir,
            dataset_path=dataset_path,
            attacker_dataset_path=Path(attacker_dataset_path) if attacker_dataset_path else None,
            database_url=database_url,
            allow_dummy=allow_dummy,
            threshold=threshold,
        )

    # ---------------------------------------------------
    # Training
    # ---------------------------------------------------
    def train(
        self,
        dataset_path: Optional[Path] = None,
        attacker_dataset_path: Optional[Path] = None,
    ) -> Dict[str, str]:
        path = Path(dataset_path or self.dataset_path)
        if not path.exists():
            raise FileNotFoundError(f"Dataset not found at {path}")

        LOGGER.info("Loading dataset from %s", path)
        df = pd.read_csv(path)
        attacker_path = attacker_dataset_path or self.attacker_dataset_path
        if attacker_path:
            attacker_path = Path(attacker_path)
            if attacker_path.exists():
                LOGGER.info("Loading attacker dataset from %s", attacker_path)
                attacker_df = pd.read_csv(attacker_path)
                required_attack_cols = [
                    c for c in self.base_feature_columns + ["start_time", "end_time"] if c not in attacker_df.columns
                ]
                if required_attack_cols:
                    raise ValueError(
                        "Attacker dataset missing required columns: "
                        + ", ".join(required_attack_cols)
                    )
                attacker_df = attacker_df.copy()
                attacker_df["label"] = 1
                df = pd.concat([df, attacker_df], ignore_index=True)
            else:
                LOGGER.warning("Attacker dataset path %s does not exist. Skipping attacker samples.", attacker_path)

        missing = [c for c in self.base_feature_columns + ["label"] if c not in df.columns]
        if missing:
            raise ValueError(f"Dataset is missing required columns: {', '.join(missing)}")

        df = df.dropna(subset=self.base_feature_columns + ["label"]).copy()
        df["start_time"] = pd.to_datetime(df["start_time"], errors="coerce")
        df = df.sort_values("start_time").reset_index(drop=True)
        df["proto"] = df["proto"].astype(str).str.upper()
        df["src_port"] = df["src_port"].astype(int)
        df["dst_port"] = df["dst_port"].astype(int)
        df["packet_count"] = df["packet_count"].astype(int)
        df["byte_count"] = df["byte_count"].astype(int)
        df["duration"] = df["duration"].astype(float)
        df["pps"] = df["pps"].astype(float)
        df["bps"] = df["bps"].astype(float)
        df["label"] = df["label"].astype(int)
        df["flow_key"] = (
            df["src_ip"].astype(str)
            + "|"
            + df["dst_ip"].astype(str)
            + "|"
            + df["src_port"].astype(str)
            + "|"
            + df["dst_port"].astype(str)
            + "|"
            + df["proto"].astype(str)
        )
        # 시계열 순서에 맞춰 플로우별 변화량 컬럼을 추가한다.
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
                "pps_cum_increase": df["pps_cum_increase"].astype(float),
                "bps_cum_increase": df["bps_cum_increase"].astype(float),
            }
        )
        encoded["flow_key"] = df["flow_key"].values
        encoded["start_time"] = df["start_time"].values
        encoded["label"] = df["label"].values
        # 후속 스케일링 결과를 안전하게 덮어쓸 수 있도록 float으로 맞춰 dtype 경고를 방지한다.
        encoded[self.feature_columns] = encoded[self.feature_columns].astype(float)

        normal_mask = df["label"].astype(int) == 0
        if not normal_mask.any():
            raise ValueError("No normal samples (label=0) found for training.")

        self.scaler = MinMaxScaler()
        normal_encoded = encoded.loc[normal_mask, self.feature_columns]
        scaled_normal = self.scaler.fit_transform(normal_encoded)
        scaled_all = self.scaler.transform(encoded[self.feature_columns])
        labels_all = encoded["label"].astype(int).to_numpy()
        encoded.loc[:, self.feature_columns] = scaled_all

        joblib.dump(self.enc_src_ip, self.paths.enc_src_ip)
        joblib.dump(self.enc_dst_ip, self.paths.enc_dst_ip)
        joblib.dump(self.enc_proto, self.paths.enc_proto)
        joblib.dump(self.scaler, self.paths.scaler)

        LOGGER.info("Training IsolationForest on normal samples only")
        # 1차 이상 후보를 찾기 위해 IsolationForest를 학습한다.
        self.iso_model = IsolationForest(contamination=0.05, random_state=42)
        self.iso_model.fit(scaled_normal)
        joblib.dump(self.iso_model, self.paths.isolation_forest)
        iso_decisions_all = self.iso_model.decision_function(scaled_all)
        self.iso_decision_min = float(np.min(iso_decisions_all))
        self.iso_decision_max = float(np.max(iso_decisions_all))
        if self.iso_decision_max - self.iso_decision_min <= 1e-9:
            self.iso_decision_max = self.iso_decision_min + 1e-6

        LOGGER.info("Training RandomForest classifier on labeled data")
        self.rf_model = RandomForestClassifier(
            n_estimators=500,
            max_depth=None,
            max_features="sqrt",
            min_samples_leaf=1,
            random_state=42,
            class_weight="balanced",
        )
        unique_labels = np.unique(labels_all)
        if unique_labels.size >= 2:
            self.rf_model.fit(scaled_all, labels_all)
            joblib.dump(self.rf_model, self.paths.rf_model)
        else:
            LOGGER.warning("Skipping RandomForest training (only one label present: %s)", unique_labels.tolist())
            self.rf_model = None

        self.threshold = self._calculate_threshold(scaled_all, labels_all)
        meta = {
            "feature_columns": self.feature_columns,
            "threshold": self.threshold,
            "iso_decision_min": self.iso_decision_min,
            "iso_decision_max": self.iso_decision_max,
        }
        self.paths.meta.write_text(json.dumps(meta, indent=2))

        self._load_artifacts()
        return {
            "dataset": str(path),
            "model_dir": str(self.model_dir),
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

        # IsolationForest와 RandomForest 점수를 혼합해 최종 hybrid 이상 점수를 만든다.
        iso_score = self._iso_score(scaled_vec)
        rf_score = self._rf_score(scaled_vec)
        rf_contrib = rf_score if rf_score is not None else 0.5
        rf_contrib = float(max(0.0, min(1.0, rf_contrib)))
        hybrid_score = float((iso_score + rf_contrib) / 2.0)
        is_anom = hybrid_score >= self.threshold
        record_id = self._persist_score(
            ts=ts,
            iso_score=iso_score,
            rf_score=rf_score,
            hybrid_score=hybrid_score,
            is_anom=is_anom,
            user_id=user_id,
            packet_meta_id=self._coerce_uuid(packet_meta_id),
        )

        if LOGGER.isEnabledFor(logging.DEBUG):
            LOGGER.debug(
                "Inference: iso=%.4f rf=%s hybrid=%.4f thresh=%.4f is_anom=%s record_id=%s",
                iso_score,
                "None" if rf_score is None else f"{rf_score:.4f}",
                hybrid_score,
                self.threshold,
                is_anom,
                record_id,
            )

        return {
            "is_anom": is_anom,
            "iso_score": iso_score,
            "hybrid_score": hybrid_score,
            "rf_score": rf_score
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
        else:
            # meta.json이 없을 때는 학습 데이터 기반으로 IsolationForest 점수 스팬을 다시 계산한다.
            self._recompute_iso_span_from_dataset()

        # 환경변수로 threshold를 강제 오버라이드할 수 있게 한다(실험/운영 튜닝용).
        env_thresh = os.getenv("ANOMALY_THRESHOLD")
        if env_thresh is not None:
            try:
                self.threshold = float(env_thresh)
                LOGGER.info("Threshold overridden by ANOMALY_THRESHOLD=%s", env_thresh)
            except ValueError:
                LOGGER.warning("Invalid ANOMALY_THRESHOLD value: %s (ignoring)", env_thresh)

        if self.paths.rf_model.exists():
            try:
                self.rf_model = joblib.load(self.paths.rf_model)
            except Exception as exc:  # noqa: BLE001
                LOGGER.warning("Failed to load RandomForest weights: %s", exc)
                self.rf_model = None
        else:
            self.rf_model = None

        self.prev_flow_stats.clear()
        # 모델 로딩 여부는 IsolationForest 중심으로 판단하고, RF는 선택적으로 사용한다.
        self.model_loaded = self.iso_model is not None
        LOGGER.info(
            "Artifacts loaded. Threshold=%.3f, ISO span=[%.6f, %.6f], RF loaded=%s",
            self.threshold,
            self.iso_decision_min,
            self.iso_decision_max,
            self.rf_model is not None,
        )

    def _safe_label_encode(self, encoder: LabelEncoder, value: str) -> int:
        classes = set(encoder.classes_.tolist())
        if value not in classes:
            return -1
        # 미리 학습된 클래스에만 존재하는 값을 안전하게 숫자로 변환한다.
        return int(encoder.transform([value])[0])

    def _flow_key(self, flow: FlowFeatures) -> str:
        return "|".join(
            [
                str(flow.src_ip),
                str(flow.dst_ip),
                str(flow.src_port),
                str(flow.dst_port),
                str(flow.proto).upper(),
            ]
        )


    def _resolve_flow_deltas(
        self, flow: FlowFeatures, current_pps: float, current_bps: float
    ) -> Tuple[float, float, float, float]:
        # MQTT/REST 입력에 delta가 없으면 최근 관측값 기준으로 계산한다.
        key = self._flow_key(flow)
        prev_pps, prev_bps, prev_pps_cum, prev_bps_cum = self.prev_flow_stats.get(
            key, (current_pps, current_bps, 0.0, 0.0)
        )
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

        pps_cum = prev_pps_cum + max(0.0, delta_pps)
        bps_cum = prev_bps_cum + max(0.0, delta_bps)
        if flow.pps_cum_increase is not None:
            try:
                pps_cum = float(flow.pps_cum_increase)
            except (TypeError, ValueError):
                pass
        if flow.bps_cum_increase is not None:
            try:
                bps_cum = float(flow.bps_cum_increase)
            except (TypeError, ValueError):
                pass

        self.prev_flow_stats[key] = (current_pps, current_bps, pps_cum, bps_cum)
        return delta_pps, delta_bps, pps_cum, bps_cum

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

        # 추론 시점의 delta 값을 보정해 정규화 파이프라인에 맞춘다.
        (
            pps_delta,
            bps_delta,
            pps_cum_increase,
            bps_cum_increase,
        ) = self._resolve_flow_deltas(flow, float(df.at[0, "pps"]), float(df.at[0, "bps"]))
        df.loc[:, "pps_delta"] = pps_delta
        df.loc[:, "bps_delta"] = bps_delta
        df.loc[:, "pps_cum_increase"] = pps_cum_increase
        df.loc[:, "bps_cum_increase"] = bps_cum_increase

        df["pps"] = np.log1p(df["pps"])
        df["bps"] = np.log1p(df["bps"])

        df["src_ip"] = [self._safe_label_encode(self.enc_src_ip, ip) for ip in df["src_ip"]]
        df["dst_ip"] = [self._safe_label_encode(self.enc_dst_ip, ip) for ip in df["dst_ip"]]
        df["proto"] = [self._safe_label_encode(self.enc_proto, p) for p in df["proto"]]

        scaled = self.scaler.transform(df[self.feature_columns])
        return scaled[0]

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

    def _rf_score(self, scaled_vec: np.ndarray) -> Optional[float]:
        if self.rf_model is None:
            return None
        try:
            return float(self.rf_model.predict_proba([scaled_vec])[0][1])
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("RandomForest prediction failed: %s", exc)
            return None
        
    def _rf_scores(self, scaled_matrix: np.ndarray) -> List[Optional[float]]:
        if self.rf_model is None:
            return [None for _ in range(len(scaled_matrix))]
        try:
            probs = self.rf_model.predict_proba(scaled_matrix)[:, 1]
            return [float(p) for p in probs]
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("RandomForest batch prediction failed: %s", exc)
            return [None for _ in range(len(scaled_matrix))]

    def _iso_scores(self, scaled_matrix: np.ndarray) -> np.ndarray:
        if self.iso_model is None:
            return np.zeros(len(scaled_matrix), dtype=float)
        raw = self.iso_model.decision_function(scaled_matrix)
        span = self.iso_decision_max - self.iso_decision_min
        if span <= 1e-9:
            return np.clip(-raw, 0.0, 1.0)
        scores = (self.iso_decision_max - raw) / span
        return np.clip(scores, 0.0, 1.0)

    def _hybrid_scores(self, scaled_matrix: np.ndarray) -> np.ndarray:
        iso_scores = self._iso_scores(scaled_matrix)
        rf_scores = self._rf_scores(scaled_matrix)
        hybrid = []
        for iso, rf in zip(iso_scores, rf_scores):
            rf_contrib = 0.5 if rf is None else float(max(0.0, min(1.0, rf)))
            hybrid.append(float((iso + rf_contrib) / 2.0))
        return np.asarray(hybrid, dtype=float)

    def _calculate_threshold(self, features: np.ndarray, labels: np.ndarray) -> float:
        """Find a threshold that maximizes F1 on labeled data; fallback to configured default."""
        if features.size == 0 or labels.size == 0:
            LOGGER.info("No data provided for threshold search. Using configured value %.2f", self.threshold)
            return self.threshold

        labels_int = labels.astype(int)
        unique_labels = np.unique(labels_int)
        if unique_labels.size < 2:
            LOGGER.info("Only one class present. Using configured threshold %.2f", self.threshold)
            return self.threshold

        hybrid_scores = self._hybrid_scores(features)
        candidates = np.linspace(0.10, 0.99, 90)

        best_thresh = self.threshold
        best_f1 = -1.0
        for thresh in candidates:
            preds = hybrid_scores >= thresh
            tp = float(np.sum((preds == 1) & (labels_int == 1)))
            fp = float(np.sum((preds == 1) & (labels_int == 0)))
            fn = float(np.sum((preds == 0) & (labels_int == 1)))

            precision = tp / (tp + fp + 1e-9)
            recall = tp / (tp + fn + 1e-9)
            f1 = 2 * precision * recall / (precision + recall + 1e-9)

            if f1 > best_f1:
                best_f1 = f1
                best_thresh = float(thresh)

        LOGGER.info(
            "Selected threshold %.3f maximizing F1=%.4f over %d candidates (default was %.2f)",
            best_thresh,
            best_f1,
            len(candidates),
            self.threshold,
        )
        return best_thresh

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
        working["pps_cum_increase"] = working.groupby(group_cols)["pps_delta"].transform(
            lambda s: s.clip(lower=0.0).cumsum()
        )
        working["bps_cum_increase"] = working.groupby(group_cols)["bps_delta"].transform(
            lambda s: s.clip(lower=0.0).cumsum()
        )
        working = working.sort_values("_orig_idx").drop(columns=["_orig_idx", "_ts"])
        working["pps_delta"] = working["pps_delta"].replace([np.inf, -np.inf], 0.0).fillna(0.0)
        working["bps_delta"] = working["bps_delta"].replace([np.inf, -np.inf], 0.0).fillna(0.0)
        working["pps_cum_increase"] = working["pps_cum_increase"].replace([np.inf, -np.inf], 0.0).fillna(0.0)
        working["bps_cum_increase"] = working["bps_cum_increase"].replace([np.inf, -np.inf], 0.0).fillna(0.0)
        return working

    def _persist_score(
        self,
        ts: datetime,
        iso_score: float,
        rf_score: Optional[float],
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
            "rf_score": rf_score,
            "hybrid_score": hybrid_score,
            "is_anom": is_anom,
        }

        query = text(
            """
            INSERT INTO anomaly_scores (
                score_id, ts, packet_meta_id, alert_id, iso_score, rf_score, hybrid_score, is_anom
            )
            VALUES (:score_id, :ts, :packet_meta_id, :alert_id, :iso_score, :rf_score, :hybrid_score, :is_anom)
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
            "hybrid_score": 0.0,
            "rf_score": 0.5,
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

    # ---------------------------------------------------
    # Recovery helpers
    # ---------------------------------------------------
    def _recompute_iso_span_from_dataset(self) -> None:
        """Recompute IsolationForest decision score span when meta.json is missing."""
        if not all([self.enc_src_ip, self.enc_dst_ip, self.enc_proto, self.scaler, self.iso_model]):
            LOGGER.warning("Cannot recompute ISO span: required artifacts not loaded.")
            return

        dataset_path = self.dataset_path
        if not dataset_path or not Path(dataset_path).exists():
            LOGGER.warning("Cannot recompute ISO span: dataset %s not found.", dataset_path)
            return

        try:
            df = pd.read_csv(dataset_path)
            atk_path = self.attacker_dataset_path
            if atk_path:
                atk_path = Path(atk_path)
                if not atk_path.exists() and atk_path.name == "attacker.csv":
                    fallback = atk_path.with_name("attaker.csv")
                    if fallback.exists():
                        LOGGER.warning("Attacker dataset %s not found. Falling back to %s", atk_path, fallback)
                        atk_path = fallback
                if atk_path.exists():
                    atk_df = pd.read_csv(atk_path).copy()
                    atk_df["label"] = 1
                    df = pd.concat([df, atk_df], ignore_index=True)
                else:
                    LOGGER.warning("Attacker dataset %s not found during ISO span recompute.", atk_path)

            needed = self.base_feature_columns
            missing = [c for c in needed if c not in df.columns]
            if missing:
                LOGGER.warning("Cannot recompute ISO span: dataset missing columns %s", ", ".join(missing))
                return

            df = df.dropna(subset=needed).copy()
            df["start_time"] = pd.to_datetime(df.get("start_time"), errors="coerce")
            df = df.sort_values("start_time").reset_index(drop=True)
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

            df["src_ip"] = [self._safe_label_encode(self.enc_src_ip, v) for v in df["src_ip"].astype(str)]
            df["dst_ip"] = [self._safe_label_encode(self.enc_dst_ip, v) for v in df["dst_ip"].astype(str)]
            df["proto"] = [self._safe_label_encode(self.enc_proto, v) for v in df["proto"].astype(str)]

            scaled = self.scaler.transform(df[self.feature_columns])
            iso_scores = self.iso_model.decision_function(scaled)
            self.iso_decision_min = float(np.min(iso_scores))
            self.iso_decision_max = float(np.max(iso_scores))
            if self.iso_decision_max - self.iso_decision_min <= 1e-9:
                self.iso_decision_max = self.iso_decision_min + 1e-6
            LOGGER.info(
                "Recomputed ISO span from dataset: [%.6f, %.6f]",
                self.iso_decision_min,
                self.iso_decision_max,
            )
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("Failed to recompute ISO span from dataset: %s", exc)
