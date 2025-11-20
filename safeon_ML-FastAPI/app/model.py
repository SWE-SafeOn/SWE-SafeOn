"""Model service abstraction used by the FastAPI endpoints.

This module keeps model-loading and inference logic separate from the
HTTP layer so it can be swapped once a trained model is available.
"""

import os
from ipaddress import ip_address
from pathlib import Path
from typing import List, Optional

from pydantic import BaseModel, Field, IPvAnyAddress


class FlowFeatures(BaseModel):
    """Structured network flow features aligned with the expected dataset."""

    src_ip: IPvAnyAddress = Field(..., description="Source IP address")
    dst_ip: IPvAnyAddress = Field(..., description="Destination IP address")
    src_port: int = Field(..., ge=0, le=65535, description="Source port")
    dst_port: int = Field(..., ge=0, le=65535, description="Destination port")
    proto: str = Field(..., description="Transport protocol (e.g., TCP/UDP/ICMP)")
    packet_count: int = Field(..., ge=0, description="Total packets observed")
    byte_count: int = Field(..., ge=0, description="Total bytes observed")
    start_time: float = Field(..., description="Flow start timestamp (epoch seconds)")
    end_time: float = Field(..., description="Flow end timestamp (epoch seconds)")
    duration: float = Field(..., ge=0, description="Reported flow duration in seconds")
    pps: float = Field(..., ge=0, description="Packets per second")
    bps: float = Field(..., ge=0, description="Bytes per second")

    def computed_duration(self) -> float:
        """Return a non-negative duration, falling back to end-start if needed."""

        if self.duration > 0:
            return self.duration
        return max(self.end_time - self.start_time, 0.0)

    def encode(self) -> List[float]:
        """Convert the flow into a numeric vector for model consumption."""

        proto_map = {"TCP": 1.0, "UDP": 0.5, "ICMP": 0.2}
        proto_value = proto_map.get(self.proto.upper(), 0.0)

        # Hash IPs into a bounded numeric space so models can ingest them as features
        src_ip_value = (hash(self._ip_to_int(self.src_ip)) % 2048) / 2048
        dst_ip_value = (hash(self._ip_to_int(self.dst_ip)) % 2048) / 2048

        return [
            src_ip_value,
            dst_ip_value,
            float(self.src_port),
            float(self.dst_port),
            proto_value,
            float(self.packet_count),
            float(self.byte_count),
            self.computed_duration(),
            float(self.pps),
            float(self.bps),
        ]

    @staticmethod
    def _ip_to_int(address: IPvAnyAddress) -> int:
        """Convert IPv4/IPv6 to a stable integer representation."""

        return int(ip_address(str(address)))


class ModelService:
    """Simple service wrapper for loading and invoking an ML model.

    The default behavior is "dummy" mode, which returns deterministic
    placeholder predictions so the API can be exercised before a trained
    model exists. Once a real model artifact is ready, provide its path
    via ``MODEL_PATH`` (or pass ``model_path`` explicitly) and replace the
    ``_load_model`` and ``_predict_with_model`` methods as needed.
    """

    def __init__(self, model_path: Optional[Path] = None, allow_dummy: bool = True):
        self.model_path = model_path
        self.allow_dummy = allow_dummy
        self.model = self._load_model(model_path) if model_path else None

    @classmethod
    def from_env(cls) -> "ModelService":
        """Instantiate from environment variables.

        - ``MODEL_PATH``: optional file path to a serialized model artifact.
        - ``ALLOW_DUMMY``: when set to ``"false"`` (case-insensitive), dummy
          mode is disabled and missing models will trigger errors.
        """

        model_env = os.getenv("MODEL_PATH")
        model_path = Path(model_env) if model_env else None
        allow_dummy = os.getenv("ALLOW_DUMMY", "true").lower() != "false"
        return cls(model_path=model_path, allow_dummy=allow_dummy)

    @property
    def model_loaded(self) -> bool:
        """Return whether a real model artifact is loaded."""

        return self.model is not None

    def predict(self, flow: FlowFeatures) -> tuple[str, float]:
        """Return a label and confidence for the provided flow features."""

        feature_vector = flow.encode()

        if not feature_vector:
            raise ValueError("Feature list cannot be empty")

        if self.model is not None:
            return self._predict_with_model(feature_vector)

        if not self.allow_dummy:
            raise RuntimeError("Model not loaded and dummy mode is disabled")

        return self._dummy_predict(feature_vector)

    def _load_model(self, model_path: Path):
        """Load the serialized model artifact.

        Replace this stub with framework-specific loading logic, e.g.
        ``torch.load`` or ``joblib.load``. The current implementation only
        checks that the file exists to provide a predictable failure mode.
        """

        if not model_path.exists():
            raise FileNotFoundError(f"Model file not found at {model_path}")
        # TODO: replace with actual model load (e.g., torch.load, joblib.load)
        return "dummy_model_placeholder"

    def _predict_with_model(self, features: List[float]) -> tuple[str, float]:
        """Run inference using the loaded model.

        Replace the body with real inference once the model is integrated.
        """

        score = 0.5 + (sum(features) % 1) / 2
        score = min(0.99, score)
        label = "safe" if score >= 0.5 else "unsafe"
        return label, round(score, 4)

    def _dummy_predict(self, features: List[float]) -> tuple[str, float]:
        """Return deterministic placeholder predictions for early testing."""

        checksum = sum(features)
        score = 0.25 + (checksum % 0.5)
        score = round(min(score, 0.99), 4)
        label = "safe" if score >= 0.5 else "unsafe"
        return label, score