"""FastAPI application exposing ML prediction endpoints.

This module scaffolds a REST API for the ML model that can be consumed by
other services (e.g., the Java backend). It provides a health check and a
predict endpoint that accepts JSON payloads describing the features.
"""

from datetime import datetime
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="SafeOn ML API", version="0.1.0")


class PredictionRequest(BaseModel):
    """Payload schema expected from upstream services.

    The schema can be adjusted to match the exact inputs the ML model needs.
    """

    user_id: str = Field(..., description="Unique identifier for the request originator")
    features: List[float] = Field(..., description="Numeric feature vector for the model")
    timestamp: Optional[datetime] = Field(
        default=None,
        description="Optional timestamp (UTC) when the features were generated",
    )


class PredictionResponse(BaseModel):
    """Response schema returned to consuming services."""

    label: str
    confidence: float
    received_at: datetime


@app.get("/health", summary="Health check")
def health() -> dict:
    """Return service status for liveness checks."""

    return {"status": "ok"}


@app.post("/predict", response_model=PredictionResponse, summary="Run model inference")
def predict(payload: PredictionRequest) -> PredictionResponse:
    """Run model inference.

    Replace the placeholder logic with actual model loading and prediction once the
    Python ML model is available. The endpoint currently checks that features exist
    and returns a dummy label and confidence score.
    """

    if not payload.features:
        raise HTTPException(status_code=400, detail="Feature list cannot be empty")

    dummy_score = min(0.99, 0.5 + (sum(payload.features) % 1) / 2)
    return PredictionResponse(
        label="safe" if dummy_score >= 0.5 else "unsafe",
        confidence=round(dummy_score, 4),
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