from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .model import FlowFeatures, ModelService
from .mqtt_bridge import MQTTBridge

app = FastAPI(title="SafeOn ML API", version="0.3.0")
model_service = ModelService.from_env()
mqtt_bridge = MQTTBridge.from_env(model_service)


class PredictionRequest(BaseModel):
    """Payload schema expected from upstream services."""

    user_id: Optional[str] = Field(
        default=None, description="Unique identifier for the request originator"
    )
    flow: FlowFeatures
    timestamp: Optional[datetime] = Field(
        default=None,
        description="Optional timestamp (UTC) when the features were generated",
    )


class PredictionResponse(BaseModel):
    """Response schema returned to consuming services."""

    is_anom: bool
    iso_score: float
    hybrid_score: float
    rf_score: Optional[float] = None


class HealthResponse(BaseModel):
    """Health payload that includes model readiness."""

    status: str
    model_loaded: bool
    mode: str
    model_dir: str
    dataset_path: str


@app.get("/health", summary="Health check", response_model=HealthResponse)
def health() -> HealthResponse:
    """Return service status for liveness checks."""

    return HealthResponse(
        status="ok",
        model_loaded=model_service.model_loaded,
        mode="model" if model_service.model_loaded else "dummy",
        model_dir=str(model_service.model_dir),
        dataset_path=str(model_service.dataset_path),
    )


@app.post("/predict", response_model=PredictionResponse, summary="Run model inference")
def predict(payload: PredictionRequest) -> PredictionResponse:
    """Run model inference and persist results to the DB if configured."""

    try:
        result = model_service.predict(
            payload.flow, user_id=payload.user_id, timestamp=payload.timestamp
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return PredictionResponse(**result)


@app.get("/docs", include_in_schema=False)
def overridden_swagger() -> dict:
    """Redirect default docs path to FastAPI's Swagger UI."""

    return {"message": "Swagger UI available at /docs"}


@app.on_event("startup")
def start_mqtt_bridge() -> None:
    """Start MQTT bridge to receive packet metadata."""

    mqtt_bridge.start()


@app.on_event("shutdown")
def stop_mqtt_bridge() -> None:
    """Stop MQTT bridge on application shutdown."""

    mqtt_bridge.stop()
