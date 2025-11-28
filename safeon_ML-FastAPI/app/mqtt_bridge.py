import json
import logging
import os
import threading
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import paho.mqtt.client as mqtt

from .model import FlowFeatures, ModelService

LOGGER = logging.getLogger(__name__)


class MQTTBridge:
    """Bridge MQTT topics to the ML model service."""

    def __init__(
        self,
        model_service: ModelService,
        host: str = "192.168.0.103",
        port: int = 1883,
        username: Optional[str] = None,
        password: Optional[str] = None,
        request_topic: str = "safeon/ml/request",
        result_topic: str = "safeon/ml/result",
        keepalive: int = 30,
        client_id: str = "safeon-ml-service",
    ) -> None:
        self.model_service = model_service
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.request_topic = request_topic
        self.result_topic = result_topic
        self.keepalive = keepalive
        self.client = mqtt.Client(client_id=client_id, clean_session=True)
        if self.username:
            self.client.username_pw_set(self.username, self.password)

        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        self.client.on_disconnect = self._on_disconnect

        self._loop_started = False
        self._lock = threading.Lock()

    @classmethod
    def from_env(cls, model_service: ModelService) -> "MQTTBridge":
        """Build the bridge using environment overrides."""

        host = os.getenv("MQTT_HOST", "localhost")
        port = int(os.getenv("MQTT_PORT", "1883"))
        username = os.getenv("MQTT_USERNAME", "safeon")
        password = os.getenv("MQTT_PASSWORD", "1234!")
        request_topic = os.getenv("MQTT_REQUEST_TOPIC", "safeon/ml/request")
        result_topic = os.getenv("MQTT_RESULT_TOPIC", "safeon/ml/result")
        client_id = os.getenv("MQTT_CLIENT_ID", "safeon-ml-service")

        return cls(
            model_service=model_service,
            host=host,
            port=port,
            username=username,
            password=password,
            request_topic=request_topic,
            result_topic=result_topic,
            client_id=client_id,
        )

    def start(self) -> None:
        """Connect to the broker and start the MQTT loop in a background thread."""

        with self._lock:
            if self._loop_started:
                return

            try:
                self.client.connect(self.host, self.port, keepalive=self.keepalive)
            except Exception as exc:  # noqa: BLE001
                LOGGER.error("Failed to connect to MQTT broker at %s:%s - %s", self.host, self.port, exc)
                return

            self.client.loop_start()
            self._loop_started = True
            LOGGER.info("MQTT loop started (broker=%s:%s, request_topic=%s, result_topic=%s)", self.host, self.port, self.request_topic, self.result_topic)

    def stop(self) -> None:
        """Stop the MQTT loop and disconnect from the broker."""

        with self._lock:
            if not self._loop_started:
                return

            self.client.loop_stop()
            self.client.disconnect()
            self._loop_started = False
            LOGGER.info("MQTT loop stopped.")

    # -----------------------------------------------------
    # MQTT callbacks
    # -----------------------------------------------------
    def _on_connect(self, client: mqtt.Client, _userdata: Any, _flags: Dict[str, Any], rc: int) -> None:
        if rc == 0:
            LOGGER.info("Connected to MQTT broker %s:%s", self.host, self.port)
            client.subscribe(self.request_topic)
        else:
            LOGGER.error("MQTT connection failed with code %s", rc)

    def _on_disconnect(self, _client: mqtt.Client, _userdata: Any, rc: int) -> None:
        if rc != 0:
            LOGGER.warning("Unexpected MQTT disconnect (rc=%s). Client will auto-reconnect if broker is available.", rc)

    def _on_message(self, _client: mqtt.Client, _userdata: Any, msg: mqtt.MQTTMessage) -> None:
        payload = msg.payload.decode("utf-8", errors="ignore")
        for line in payload.splitlines():
            line = line.strip()
            if not line:
                continue
            self._process_line(line)

    # -----------------------------------------------------
    # Helpers
    # -----------------------------------------------------
    def _process_line(self, line: str) -> None:
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            LOGGER.warning("Skipping invalid JSONL line: %s", line)
            return

        flow_data: Dict[str, Any]
        user_id: Optional[str] = None
        ts_val: Optional[datetime] = None
        request_id: Optional[str] = None
        packet_meta_id: Optional[str] = None
        device_id: Optional[str] = None

        if isinstance(data, dict):
            flow_data = data.get("flow", data)
            user_id = data.get("user_id") or data.get("userId")
            request_id = data.get("id") or data.get("request_id") or data.get("requestId")
            packet_meta_id = data.get("packet_meta_id") or data.get("packetMetaId")
            device_id = data.get("device_id") or data.get("deviceId")
            ts_val = self._parse_timestamp(
                data.get("timestamp") or data.get("ts") or flow_data.get("start_time")
            )
        else:
            LOGGER.warning("Skipping non-object JSONL line: %s", data)
            return

        try:
            flow = FlowFeatures(**flow_data)
            inference_ts = ts_val or datetime.now(timezone.utc)
            result = self.model_service.predict(
                flow,
                user_id=user_id,
                timestamp=inference_ts,
                packet_meta_id=packet_meta_id,
            )
            response = {
                "packet_meta_id": packet_meta_id,
                "device_id": device_id,
                "iso_score": result.get("iso_score"),
                "ae_score": result.get("ae_score"),
                "hybrid_score": result.get("hybrid_score"),
                "is_anom": result.get("is_anom"),
                "timestamp": inference_ts.isoformat(),
            }
        except Exception as exc:  # noqa: BLE001
            LOGGER.warning("Failed to process MQTT request: %s", exc)
            fallback_ts = datetime.now(timezone.utc)
            response = {
                "packet_meta_id": packet_meta_id,
                "device_id": device_id,
                "iso_score": 0.0,
                "ae_score": 0.0,
                "hybrid_score": 0.0,
                "is_anom": False,
                "timestamp": fallback_ts.isoformat(),
                "error": str(exc),
            }

        self._publish_result(response)

    def _publish_result(self, payload: Dict[str, Any]) -> None:
        compact = {k: v for k, v in payload.items() if v is not None}
        try:
            message = json.dumps(compact)
        except TypeError:
            # Fallback if any value is not JSON-serializable.
            message = json.dumps({"id": compact.get("id"), "error": "Failed to serialize result"})

        result = self.client.publish(self.result_topic, message)
        if result.rc != mqtt.MQTT_ERR_SUCCESS:
            LOGGER.warning("Failed to publish MQTT result (rc=%s)", result.rc)

    def _parse_timestamp(self, value: Any) -> Optional[datetime]:
        if value is None:
            return None
        if isinstance(value, datetime):
            return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        if isinstance(value, (int, float)):
            return datetime.fromtimestamp(value, tz=timezone.utc)
        if isinstance(value, str):
            try:
                dt = datetime.fromisoformat(value)
                return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
            except ValueError:
                return None
        return None
