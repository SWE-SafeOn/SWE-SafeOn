# SafeOn
**The Anomaly Detection Framework for Smart Home IoT Security**

---

![safeon](docs/SafeOn.png)

---

## Project Proposal
### Problem
Smart home networks contain many unmanaged IoT devices (cameras, locks, appliances) that rarely receive security updates. Traditional perimeter firewalls lack device-level visibility, leaving households exposed to lateral movement, data exfiltration, and botnet enrollment.

### Vision
SafeOn delivers an on-prem, privacy-preserving anomaly detection and response framework for home IoT. It combines lightweight network telemetry with hybrid ML to surface abnormal behavior in real time and give homeowners clear remediation actions.

### Approach
- **Data plane**: ESP32-based edge agent publishes per-flow metadata (IP/port, packet/byte counts, pps/bps, deltas) over MQTT.
- **ML microservice** (`safeon_ML-FastAPI`): FastAPI service ingests MQTT JSONL payloads, normalizes flow features, and scores anomalies with a calibrated hybrid model (IsolationForest + RandomForest). It returns per-packet meta scores (`iso_score`, `rf_score`, `hybrid_score`, `is_anom`) and can fall back to dummy mode until artifacts are trained.
- **Backend** (`safeon_backend`): Spring Boot API handles auth/JWT, device lifecycle, alerting, and persistence to PostgreSQL. It bridges MQTT topics (`safeon/ml/request` ↔ `safeon/ml/result`, plus router topics) to coordinate scoring and mitigation.
- **Frontend** (`safeon_frontend`): Flutter client surfaces dashboard overviews, traffic charts, alerts, and device controls (claim, delete, block). It auto-selects the correct base URL for web vs Android emulator.
- **Storage**: Postgres stores users, devices, packet metadata, and anomaly scores for forensic review.

### Key Features
- Real-time scoring via MQTT bridge with configurable broker creds (`MQTT_HOST/PORT/USERNAME/PASSWORD`), topics, and client IDs.
- Feature engineering that tracks per-flow deltas and cumulative increases to catch rate-based anomalies while normalizing IPs with label encoders and scaling for robust inference.
- Threshold tuning to maximize F1 on labeled datasets, with optional attacker samples for supervised signals.
- Alert lifecycle management (acknowledge, block device) exposed through REST and mirrored in the mobile/web app.
- Privacy-first: only flow-level metadata leaves the device; no packet payload inspection required.

### Architecture Flow
1. Router/agent publishes flow JSONL to `safeon/ml/request`.
2. ML service scores the flow and publishes results to `safeon/ml/result`.
3. Backend ingests scores, persists them, and emits alerts or block commands over MQTT as needed.
4. Users interact through the Flutter app to view dashboards, device traffic, and respond to alerts.

### Tech Stack
- **Edge/Transport**: MQTT over TCP.
- **ML**: Python, FastAPI, scikit-learn, joblib, Pandas/NumPy.
- **Backend**: Java 17, Spring Boot, PostgreSQL, JWT.
- **Frontend**: Flutter/Dart, HTTP + WebSocket for live traffic.

### Roadmap
- Add model retraining CLI/CI job hooked to new labeled data.
- Expand device profiling features (vendor/firmware identification) to improve baselines.
- Integrate policy-based auto-block rules tied to anomaly confidence bands.
- Harden deployment artifacts (Docker Compose, OpenWrt router scripts) for one-command installs.

---

##  System Architecture
![System Architecture](docs/SafeOn_System_Architecture.png)

---

## Group Members
| Name | Organization | Email |
|------|-------------|--------|
| Juseong Jeon | Department of Information Systems, Hanyang University | hyu22ix@hanyang.ac.kr |
| Jaemin Jung | Department of Information Systems, Hanyang University | woals5633@hanyang.ac.kr |
| Wonyoung Shin | Department of Information Systems, Hanyang University | pingu090@hanyang.ac.kr |
| Seungmin Son | Department of Information Systems, Hanyang University | andyson0205@gmail.com |
