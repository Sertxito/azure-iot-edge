import json
import os
import logging
import time
from datetime import datetime, timezone
from pathlib import Path

import paho.mqtt.client as mqtt
from azure.iot.device import IoTHubModuleClient


def _load_local_env():
    """Load local key=value files without overriding already exported env vars."""
    script_path = Path(__file__).resolve()
    candidates = [Path.cwd() / ".env.local", script_path.parent / ".env.local"]
    candidates.extend(parent / ".env.local" for parent in script_path.parents)

    # Preserve order but avoid checking the same path repeatedly.
    unique_candidates = []
    seen = set()
    for env_path in candidates:
        key = str(env_path)
        if key in seen:
            continue
        seen.add(key)
        unique_candidates.append(env_path)

    for env_path in unique_candidates:
        if not env_path.exists() or not env_path.is_file():
            continue
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value
        break


_load_local_env()

MQTT_BROKER = os.getenv("MQTT_BROKER", "localhost")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "building/01/home/+/telemetry")
EDGE_OUTPUT = os.getenv("EDGE_OUTPUT", "telemetry")
MQTT_KEEPALIVE = int(os.getenv("MQTT_KEEPALIVE", "60"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="[%(levelname)s] %(asctime)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("mqtt-bridge")

edge_client = None

def utc_now():
    return datetime.now(timezone.utc).isoformat()


def ensure_edge_client_connected():
    global edge_client
    if edge_client is None:
        edge_client = IoTHubModuleClient.create_from_edge_environment()
        edge_client.connect()
        log.info("[EDGE] Connected module client")


def send_to_edge(payload: dict):
    global edge_client
    try:
        ensure_edge_client_connected()
        edge_client.send_message_to_output(json.dumps(payload), EDGE_OUTPUT)
        return True
    except Exception as ex:
        log.error(f"[EDGE] Send failed: {ex}")
        # Force recreate on next send in case current client is stale.
        edge_client = None
        return False

def is_sensorsim_like(data: dict) -> bool:
    s = data.get("sensors", {})
    if not isinstance(s, dict):
        return False
    return any(isinstance(s.get(k), dict) for k in ("gas","sound","light","pir","dht11"))

def to_sensorsim_like(data: dict) -> dict:
    # Si ya viene en formato estable, lo dejamos tal cual
    if is_sensorsim_like(data):
        return data

    device_id = data.get("deviceId", "unknown")
    s = data.get("sensors", {}) if isinstance(data.get("sensors"), dict) else {}

    motion = bool(s.get("motion", False))
    gas_bool = bool(s.get("gas", False))
    ldr_raw = s.get("ldr_raw", None)
    temp = s.get("temperature", None)
    hum = s.get("humidity", None)

    # PRESERVAR door/touch desde NodeMCU
    door = s.get("door", "UNKNOWN")
    if not isinstance(door, str):
        door = "UNKNOWN"
    touch = bool(s.get("touch", False))

    out = {
        "deviceId": device_id,
        "ts": data.get("ts") or utc_now(),
        "sensors": {
            "gas": {"analog": None, "alarm": gas_bool},
            "sound": {"analog": None, "alarm": False},
            "light": {"analog": ldr_raw if isinstance(ldr_raw, (int, float)) else None},
            "pir": {"motion": motion},
            "dht11": {
                "temp_c": temp if isinstance(temp, (int, float)) else None,
                "humidity": hum if isinstance(hum, (int, float)) else None
            }
        },
        "_meta": {"door": door, "touch": touch}
    }
    return out

def on_connect(client, userdata, flags, rc):
    log.info(f"[MQTT] Connected rc={rc}")
    client.subscribe(MQTT_TOPIC)
    log.info(f"[MQTT] Subscribed {MQTT_TOPIC}")


def on_disconnect(client, userdata, rc):
    if rc != 0:
        log.warning(f"[MQTT] Unexpected disconnect rc={rc}; auto-reconnect enabled")
    else:
        log.info("[MQTT] Disconnected")

def on_message(client, userdata, msg):
    try:
        raw = msg.payload.decode("utf-8")
    except UnicodeDecodeError:
        log.error("[MQTT] Payload is not valid UTF-8; dropping message")
        return

    try:
        data_in = json.loads(raw)
    except json.JSONDecodeError as ex:
        log.error(f"[MQTT] Invalid JSON payload; dropping message: {ex}")
        return

    if not isinstance(data_in, dict):
        log.warning("[MQTT] JSON payload is not an object; dropping message")
        return

    data_out = to_sensorsim_like(data_in)

    if send_to_edge(data_out):
        log.info("[EDGE] Forwarded (normalized + meta)")


def build_mqtt_client():
    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message
    client.reconnect_delay_set(min_delay=1, max_delay=30)
    return client


def connect_mqtt_with_retry(client, retry_seconds: float = 5.0):
    """Retry MQTT connect until broker is available."""
    while True:
        try:
            client.connect(MQTT_BROKER, MQTT_PORT, MQTT_KEEPALIVE)
            return
        except Exception as ex:
            log.error(f"[MQTT] Initial connect failed; retrying in {retry_seconds}s: {ex}")
            time.sleep(retry_seconds)


def main():
    mqtt_client = build_mqtt_client()
    connect_mqtt_with_retry(mqtt_client)
    mqtt_client.loop_forever()


if __name__ == "__main__":
    main()
