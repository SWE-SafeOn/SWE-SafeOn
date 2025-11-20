# SafeOn ML FastAPI Service

A lightweight FastAPI application that exposes REST endpoints to integrate the future Python-based ML model with the existing Java backend. The service provides a health check and a `/predict` endpoint that accepts JSON payloads and returns an inference result.

## Project layout

```
safeon_ML-FastAPI/
├── app/
│   └── main.py          # FastAPI application with health and prediction endpoints
└── requirements.txt     # Python dependencies
```

## Running locally

1. Create and activate a virtual environment (recommended).
2. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

3. Start the API server:

   ```bash
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

4. Visit the interactive docs at `http://localhost:8000/docs`.

## Example request

`POST /predict`

```json
{
  "user_id": "abc123",
  "features": [0.12, 0.3, 0.58],
  "timestamp": "2024-05-18T12:34:56Z"
}
```

### Example response

```json
{
  "label": "safe",
  "confidence": 0.83,
  "received_at": "2024-05-18T13:00:00.000000"
}
```

## Integration notes

- The request/response schemas are defined in `app/main.py` using Pydantic models.
- Replace the placeholder prediction logic in `predict` with the actual ML inference call once the model is available.
- The Java backend can invoke the endpoint via HTTP POST with the JSON payload shown above; the response includes a label and confidence for straightforward consumption.