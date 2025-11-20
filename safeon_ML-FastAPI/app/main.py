"""FastAPI application exposing ML prediction endpoints.

This module scaffolds a REST API for the ML model that can be consumed by
other services (e.g., the Java backend). It provides a health check and a
predict endpoint that accepts JSON payloads describing the features.
"""

from datetime import datetime
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .model import FlowFeatures, ModelService

app = FastAPI(title="SafeOn ML API", version="0.2.0")
model_service = ModelService.from_env()


class PredictionRequest(BaseModel):
    """Payload schema expected from upstream services.

    This schema matches the network-flow dataset shape shared by the user
    (src/dst IPs and ports, protocol, packet/byte counts, timings, throughput).
    """

    user_id: str = Field(..., description="Unique identifier for the request originator")
    flow: FlowFeatures
    timestamp: Optional[datetime] = Field(
        default=None,
        description="Optional timestamp (UTC) when the features were generated",
    )


class PredictionResponse(BaseModel):
    """Response schema returned to consuming services."""

    label: str
    confidence: float
    received_at: datetime


class HealthResponse(BaseModel):
    """Health payload that includes model readiness."""

    status: str
    model_loaded: bool
    mode: str


@app.get("/health", summary="Health check", response_model=HealthResponse)
def health() -> HealthResponse:
    """Return service status for liveness checks."""

    return HealthResponse(
        status="ok",
        model_loaded=model_service.model_loaded,
        mode="model" if model_service.model_loaded else "dummy",
    )


@app.post("/predict", response_model=PredictionResponse, summary="Run model inference")
def predict(payload: PredictionRequest) -> PredictionResponse:
    """Run model inference.

    Replace the placeholder logic with actual model loading and prediction once the
    Python ML model is available. The endpoint currently checks that a flow record
    is provided and returns a dummy label and confidence score when no trained
    model is loaded.
    """

    try:
        label, confidence = model_service.predict(payload.flow)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return PredictionResponse(
        label=label,
        confidence=confidence,
        received_at=datetime.utcnow(),
    )


@app.get("/docs", include_in_schema=False)
def overridden_swagger() -> dict:
    """Redirect default docs path to FastAPI's Swagger UI.

    This keeps the built-in documentation accessible at `/docs` while being explicit
    about its availability for clients and integrators.
    """

    # FastAPI automatically serves docs at /docs, so this endpoint simply provides
    # an explicit handler that delegates to the default behavior.
    return {"message": "Swagger UI available at /docs"}