# SafeOn ML FastAPI Service

A lightweight FastAPI application that exposes REST endpoints to integrate the future Python-based ML model with the existing Java backend. The service provides a health check and a `/predict` endpoint that accepts JSON payloads and returns an inference result.

## Project layout

```
safeon_ML-FastAPI/
├── app/
│   ├── main.py          # FastAPI application with health and prediction endpoints
│   └── model.py         # ModelService wrapper (dummy mode until a model is available)
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

## Configuration

- `MODEL_PATH` (optional): filesystem path to a serialized model artifact. If omitted, the API stays in **dummy** mode and returns deterministic placeholder predictions so integration work can continue before the dataset/model is ready.
- `ALLOW_DUMMY` (optional, default: `true`): when set to `false`, requests will fail with `503` if `MODEL_PATH` is not provided or cannot be loaded.
- `DATABASE_URL` (optional): PostgreSQL URL for persisting inference scores (defaults to `postgresql://safeon:0987@localhost:5432/safeon`).

The `/health` endpoint reports whether a model is loaded and whether the service is running in `model` or `dummy` mode.

## Example request

`POST /predict`

This schema mirrors the dataset columns the backend shared (IP/port, protocol,
packet/byte counts, timings, and throughput stats).

```json
{
  "user_id": "esp32cam-001",
  "flow": {
    "src_ip": "192.168.0.15",
    "dst_ip": "192.168.0.103",
    "src_port": 58304,
    "dst_port": 80,
    "proto": "TCP",
    "packet_count": 175,
    "byte_count": 34321,
    "start_time": 1706938886.012,
    "end_time": 1706938887.021,
    "duration": 1.009,
    "pps": 173.42,
    "bps": 33792.41
  },
  "timestamp": "2024-05-18T12:34:56Z"
}
```

### Example response (dummy mode)

```json
{
  "label": "safe",
  "confidence": 0.63,
  "received_at": "2024-05-18T13:00:00.000000"
}
```

### Feature encoding

`app/model.py` includes a `FlowFeatures.encode()` helper that turns the flow
record into a numeric vector suitable for ML models. IPs are hashed into a
bounded numeric space, protocol strings are mapped to floats (TCP=1.0,
UDP=0.5, ICMP=0.2, else 0.0), and duration falls back to `end_time - start_time`
if the provided `duration` is zero. Swap this encoding for your model-specific
preprocessing as needed.

## Training with the bundled dataset

1. (Optional) Rebuild the dataset with the new win3 captures:

   ```
   python ../datasets/esp32-cam/combine.py
   ```

   This produces `../datasets/esp32-cam/dataset.csv`.

2. Train the models:

   ```
   python -m app.train --dataset ../datasets/esp32-cam/dataset.csv
   ```

Artifacts (encoders, scaler, IsolationForest, Transformer autoencoder) are
written to `safeon_ML-FastAPI/models`. Subsequent `/predict` calls will load
these artifacts automatically and store scores in the configured database.

## Integration notes

- The request/response schemas are defined in `app/main.py` using Pydantic models.
- `app/model.py` encapsulates model loading and prediction. Replace `_load_model` and `_predict_with_model` with framework-specific logic when a trained model is available.
- While the dataset and trained model are absent, keep `ALLOW_DUMMY` enabled to receive stable placeholder predictions for end-to-end wiring with the Java backend.
- The Java backend can invoke the endpoint via HTTP POST with the JSON payload shown above; the response includes a label and confidence for straightforward consumption.
