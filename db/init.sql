-- ===========================================
-- EXTENSIONS
-- ===========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS timescaledb;


-- ===========================================
-- USERS
-- ===========================================
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    registered_at TIMESTAMPTZ
);


-- ===========================================
-- DEVICES
-- ===========================================
CREATE TABLE devices (
    device_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mac_address VARCHAR(17) NOT NULL UNIQUE,
    name VARCHAR(255),
    ip_address VARCHAR(255),
    discovered BOOLEAN,
    created_at TIMESTAMPTZ
);


-- ===========================================
-- USER_DEVICES (Mapping)
-- ===========================================
CREATE TABLE user_devices (
    user_device_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(device_id) ON DELETE CASCADE,
    linked_at TIMESTAMPTZ
);


-- ===========================================
-- FLOWS (HyperTable)
-- ===========================================
CREATE TABLE flows (
    flow_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_key VARCHAR(255),
    src_ip VARCHAR(255),
    dst_ip VARCHAR(255),
    src_port SMALLINT,
    dst_port SMALLINT,
    l4_proto VARCHAR(32),
    start_ts TIMESTAMPTZ NOT NULL,
    end_ts TIMESTAMPTZ,
    bytes BIGINT,
    pkts BIGINT
);

-- Make hypertable
SELECT create_hypertable('flows', 'start_ts', if_not_exists => TRUE);


-- ===========================================
-- PACKET_META (HyperTable)
-- ===========================================
CREATE TABLE packet_meta (
    packet_meta_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flow_id UUID,
    src_ip VARCHAR(255),
    dst_ip VARCHAR(255),
    src_port SMALLINT,
    dst_port SMALLINT,
    proto VARCHAR(32),
    time_bucket VARCHAR(64),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration DOUBLE PRECISION,
    packet_count INTEGER,
    byte_count BIGINT,
    pps DOUBLE PRECISION,
    bps DOUBLE PRECISION,
    label INTEGER
);

SELECT create_hypertable('packet_meta', 'start_time', if_not_exists => TRUE);


-- ===========================================
-- ANOMALY_SCORES (HyperTable)
-- ===========================================
CREATE TABLE anomaly_scores (
    score_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ts TIMESTAMPTZ NOT NULL,
    packet_meta_id UUID UNIQUE,
    alert_id UUID,
    iso_score DOUBLE PRECISION,
    lstm_score DOUBLE PRECISION,
    hybrid_score DOUBLE PRECISION,
    is_anom BOOLEAN
);

SELECT create_hypertable('anomaly_scores', 'ts', if_not_exists => TRUE);


-- ===========================================
-- TWIN_RESIDUALS (HyperTable)
-- ===========================================
CREATE TABLE twin_residuals (
    residual_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ts TIMESTAMPTZ NOT NULL,
    flow_id UUID,
    twin_ver VARCHAR(255),
    pred DOUBLE PRECISION,
    actual DOUBLE PRECISION,
    residual DOUBLE PRECISION,
    state VARCHAR(128)
);

SELECT create_hypertable('twin_residuals', 'ts', if_not_exists => TRUE);


-- ===========================================
-- ALERTS
-- ===========================================
CREATE TABLE alerts (
    alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ts TIMESTAMPTZ,
    anomaly_score_id UUID UNIQUE,
    device_id UUID REFERENCES devices(device_id) ON DELETE SET NULL,
    severity VARCHAR(64),
    reason TEXT,
    evidence JSONB,
    status VARCHAR(64)
);


-- ===========================================
-- USER_ALERTS
-- ===========================================
CREATE TABLE user_alerts (
    user_alert_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    alert_id UUID REFERENCES alerts(alert_id) ON DELETE CASCADE,
    notified_at TIMESTAMPTZ,
    is_read BOOLEAN,
    channel VARCHAR(64),
    delivery_status VARCHAR(64)
);
