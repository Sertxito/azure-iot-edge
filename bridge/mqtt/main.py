import json
import os
from datetime import datetime, timezone

import paho.mqtt.client as mqtt
from azure.iot.device import IoTHubModuleClient

MQTT_BROKER = os.getenv("MQTT_BROKER", "localhost")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "building/01/home/+/telemetry")

EDGE_OUTPUT = os.getenv("EDGE_OUTPUT", "telemetry")

edge_client = IoTHubModuleClient.create_from_edge_environment()

def utc_now():
    return datetime.now(timezone.utc).isoformat()

def is_sensorsim_like(data: dict) -> bool:
    sensors = data.get("sensors", {})
    if not isinstance(sensors, dict):
        return False
    # sensorSim-like: alguno de estos sensores es dict (gas/light/pir/dht11)
    for k in ("gas", "sound", "light", "pir", "dht11"):
        if isinstance(sensors.get(k), dict):
            return True
    return False

def to_sensorsim_like(data: dict) -> dict:
    # Si ya viene como sensorSim-like, no tocamos nada
    if is_sensorsim_like(data):
        return data

    # NodeMCU → sensorSim-like
    device_id = data.get("deviceId", "unknown")
    sensors = data.get("sensors", {}) if isinstance(data.get("sensors", {}), dict) else {}

    motion = bool(sensors.get("motion", False))
    gas_bool = bool(sensors.get("gas", False))
    ldr_raw = sensors.get("ldr_raw", None)
    temp = sensors.get("temperature", None)
    hum = sensors.get("humidity", None)

    return {
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
        }
    }

def on_connect(client, userdata, flags, rc):
    print(f"[MQTT] Connected rc={rc}")
    client.subscribe(MQTT_TOPIC)
    print(f"[MQTT] Subscribed {MQTT_TOPIC}")

def on_message(client, userdata, msg):
    raw = msg.payload.decode("utf-8")
    print(f"[MQTT] {msg.topic} -> {raw}")

    data_in = json.loads(raw)
    data_out = to_sensorsim_like(data_in)

    edge_client.send_message_to_output(json.dumps(data_out), EDGE_OUTPUT)
    print("[EDGE] Forwarded (normalized)")

mqtt_client = mqtt.Client()
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
mqtt_client.loop_forever()
