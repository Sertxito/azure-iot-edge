import json
import os
import time
import logging
import threading
from datetime import datetime, timezone

from azure.iot.device import IoTHubModuleClient, Message

# ---------------------------
# Config (env overrides)
# ---------------------------
INPUT_NAME = os.getenv("EDGEDECIDER_INPUT", "input1")
OUTPUT_NAME = os.getenv("EDGEDECIDER_OUTPUT", "output1")

AGGREGATE_WINDOW_SEC = int(os.getenv("EDGEDECIDER_AGG_WINDOW_SEC", "60"))
HEARTBEAT_INTERVAL_SEC = int(os.getenv("EDGEDECIDER_HEARTBEAT_SEC", "300"))

ALARM_COOLDOWN_SEC = int(os.getenv("EDGEDECIDER_ALARM_COOLDOWN_SEC", "60"))
LOG_LEVEL = os.getenv("EDGEDECIDER_LOG_LEVEL", "INFO").upper()

# ---------------------------
# Logging
# ---------------------------
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="[{level}] {ts} {msg}".format(level="%(levelname)s", ts="%(asctime)s", msg="%(message)s"),
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("edgeDecider")


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def make_msg(payload: dict) -> Message:
    m = Message(json.dumps(payload))
    m.content_type = "application/json"
    m.content_encoding = "utf-8"
    return m


# ---------------------------
# Shared state (thread-safe)
# ---------------------------
lock = threading.Lock()

latest_data = None
latest_device_id = "unknown"
latest_received_ts = 0.0
seq = 0

buf_light = []
buf_sound = []
last_temp = None
last_hum = None

alarm_active = {"gas": False, "sound": False, "pir": False}
last_alarm_emit = {"gas": 0.0, "sound": 0.0, "pir": 0.0}


# ---------------------------
# Payload normalization
# Supports:
# A) sensorSim-like:
#    sensors.gas/sound/light/pir/dht11 are dicts (gas has alarm/analog, etc.)
# B) NodeMCU-like:
#    sensors.gas is bool, sensors.light is str, sensors.ldr_raw is int, etc.
# ---------------------------
def is_sensorsim_payload(data: dict) -> bool:
    sensors = data.get("sensors", {})
    if not isinstance(sensors, dict):
        return False

    # sensorSim has structured objects (dicts) for these sensors
    for k in ("gas", "sound", "light", "pir", "dht11"):
        v = sensors.get(k)
        if isinstance(v, dict):
            return True
    return False


def normalize_payload(data: dict) -> dict:
    """
    Return a sensorSim-like payload so the decider logic works consistently.
    """
    if is_sensorsim_payload(data):
        return data

    # NodeMCU-style mapping
    device_id = data.get("deviceId", "unknown")
    sensors = data.get("sensors", {}) if isinstance(data.get("sensors", {}), dict) else {}

    motion = bool(sensors.get("motion", False))
    gas_bool = bool(sensors.get("gas", False))
    ldr_raw = sensors.get("ldr_raw", None)
    temp = sensors.get("temperature", None)
    hum = sensors.get("humidity", None)

    norm = {
        "deviceId": device_id,
        "ts": data.get("ts") or utc_now(),
        "sensors": {
            "gas": {
                "analog": None,
                "alarm": gas_bool
            },
            "sound": {
                "analog": None,
                "alarm": False
            },
            "light": {
                "analog": ldr_raw if isinstance(ldr_raw, (int, float)) else None
            },
            "pir": {
                "motion": motion
            },
            "dht11": {
                "temp_c": temp if isinstance(temp, (int, float)) else None,
                "humidity": hum if isinstance(hum, (int, float)) else None
            }
        }
    }
    return norm


def build_alarm_event(device_id, sensor_name, raw, state, severity="high"):
    return {
        "type": "alarm",
        "state": state,  # raised | cleared | reminder
        "deviceId": device_id,
        "ts": utc_now(),
        "source": "edgeDecider",
        "severity": severity,
        "data": {
            "sensor": sensor_name,
            "raw": raw
        }
    }


def build_aggregate_event(device_id, light_avg, sound_avg, temp_c, humidity):
    return {
        "type": "aggregate",
        "deviceId": device_id,
        "ts": utc_now(),
        "source": "edgeDecider",
        "window_sec": AGGREGATE_WINDOW_SEC,
        "data": {
            "light_avg": light_avg,
            "sound_avg": sound_avg,
            "temp_c": temp_c,
            "humidity": humidity
        }
    }


def build_heartbeat_event(device_id, uptime_sec, last_seen_sec, seq_value):
    return {
        "type": "heartbeat",
        "deviceId": device_id,
        "ts": utc_now(),
        "source": "edgeDecider",
        "status": "ok",
        "uptime_sec": uptime_sec,
        "last_input_age_sec": last_seen_sec,
        "seq": seq_value
    }


def avg(values):
    if not values:
        return None
    return sum(values) / len(values)


def on_message_received(message):
    """
    IoT Edge input handler.
    Logs raw payload + normalizes to sensorSim-like schema.
    """
    global latest_data, latest_device_id, latest_received_ts, seq
    global last_temp, last_hum, buf_light, buf_sound

    try:
        in_name = getattr(message, "input_name", None)
        if in_name is not None and in_name != INPUT_NAME:
            return

        raw_payload = message.data.decode("utf-8")
        log.info(f"[INPUT] Received on {INPUT_NAME}: {raw_payload}")

        data_in = json.loads(raw_payload)
        if not isinstance(data_in, dict):
            raise ValueError(f"Expected JSON object, got {type(data_in)}")

        data = normalize_payload(data_in)

        device_id = data.get("deviceId", "unknown")
        sensors = data.get("sensors", {})

        # Now safe: these are dicts in normalized payload
        light = sensors.get("light", {}).get("analog", None)
        sound = sensors.get("sound", {}).get("analog", None)
        dht = sensors.get("dht11", {})

        with lock:
            seq += 1
            latest_data = data
            latest_device_id = device_id
            latest_received_ts = time.time()

            if isinstance(light, (int, float)):
                buf_light.append(light)
            if isinstance(sound, (int, float)):
                buf_sound.append(sound)

            t = dht.get("temp_c", None)
            h = dht.get("humidity", None)
            if isinstance(t, (int, float)):
                last_temp = t
            if isinstance(h, (int, float)):
                last_hum = h

    except Exception as e:
        log.error(f"Failed to parse input message: {e}")


def main():
    global latest_data, latest_device_id
    global buf_light, buf_sound, last_temp, last_hum

    client = IoTHubModuleClient.create_from_edge_environment()
    client.on_message_received = on_message_received
    client.connect()

    start_ts = time.time()
    last_agg_ts = time.time()
    last_hb_ts = time.time()

    log.info("edgeDecider started")
    log.info(f"[DECIDER] Listening on {INPUT_NAME}...")

    while True:
        now = time.time()

        with lock:
            data = latest_data
            device_id = latest_device_id
            last_seen = latest_received_ts
            seq_value = seq

        # --- Alarms (edge-triggered) ---
        if data:
            sensors = data.get("sensors", {})

            gas = sensors.get("gas", {})
            sound = sensors.get("sound", {})
            pir = sensors.get("pir", {})

            current = {
                "gas": bool(gas.get("alarm", False)),
                "sound": bool(sound.get("alarm", False)),
                "pir": bool(pir.get("motion", False)),
            }

            raw_map = {"gas": gas, "sound": sound, "pir": pir}

            for name, active in current.items():
                prev = alarm_active[name]

                if active and not prev:
                    alarm_active[name] = True
                    last_alarm_emit[name] = now
                    evt = build_alarm_event(device_id, name, raw_map[name], state="raised")
                    client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
                    log.info(f"Alarm RAISED: {name}")

                elif active and prev:
                    if now - last_alarm_emit[name] >= ALARM_COOLDOWN_SEC:
                        last_alarm_emit[name] = now
                        evt = build_alarm_event(device_id, name, raw_map[name], state="reminder")
                        client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
                        log.info(f"Alarm REMINDER: {name}")

                elif (not active) and prev:
                    alarm_active[name] = False
                    last_alarm_emit[name] = now
                    evt = build_alarm_event(device_id, name, raw_map[name], state="cleared", severity="info")
                    client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
                    log.info(f"Alarm CLEARED: {name}")

        # --- Aggregate ---
        if now - last_agg_ts >= AGGREGATE_WINDOW_SEC:
            with lock:
                light_avg = avg(buf_light)
                sound_avg = avg(buf_sound)
                t = last_temp
                h = last_hum
                buf_light = []
                buf_sound = []

            evt = build_aggregate_event(device_id, light_avg, sound_avg, t, h)
            client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
            log.info("Aggregate sent")
            last_agg_ts = now

        # --- Heartbeat ---
        if now - last_hb_ts >= HEARTBEAT_INTERVAL_SEC:
            uptime_sec = int(now - start_ts)
            last_age = int(now - last_seen) if last_seen > 0 else None
            evt = build_heartbeat_event(device_id, uptime_sec, last_age, seq_value)
            client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
            log.info("Heartbeat sent")
            last_hb_ts = now

        time.sleep(0.2)


if __name__ == "__main__":
    main()
