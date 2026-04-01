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

# Cooldown para recordatorios mientras una alarma sigue activa (segundos)
ALARM_COOLDOWN_SEC = int(os.getenv("EDGEDECIDER_ALARM_COOLDOWN_SEC", "60"))

LOG_LEVEL = os.getenv("EDGEDECIDER_LOG_LEVEL", "INFO").upper()

# ---------------------------
# Logging (sin buffering)
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
# Estado compartido (thread-safe)
# ---------------------------
lock = threading.Lock()

latest_data = None
latest_device_id = "unknown"
latest_received_ts = 0.0
seq = 0

# buffers para agregados
buf_light = []
buf_sound = []
last_temp = None
last_hum = None

# alarm state + cooldown
alarm_active = {"gas": False, "sound": False, "pir": False}
last_alarm_emit = {"gas": 0.0, "sound": 0.0, "pir": 0.0}

def on_message_received(message):
    """
    Handler del SDK (evita receive_message_on_input deprecado).
    Filtra por input si el SDK lo expone.
    """
    global latest_data, latest_device_id, latest_received_ts, seq
    global last_temp, last_hum, buf_light, buf_sound

    try:
        # Algunas versiones exponen message.input_name
        in_name = getattr(message, "input_name", None)
        if in_name is not None and in_name != INPUT_NAME:
            return

        data = json.loads(message.data.decode("utf-8"))
        device_id = data.get("deviceId", "unknown")

        sensors = data.get("sensors", {})

        # buffer agregados
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

    while True:
        now = time.time()

        # Copia de estado actual
        with lock:
            data = latest_data
            device_id = latest_device_id
            last_seen = latest_received_ts
            seq_value = seq

        # --- Alarm edge-triggered + cooldown ---
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
                    # rising edge
                    alarm_active[name] = True
                    last_alarm_emit[name] = now
                    evt = build_alarm_event(device_id, name, raw_map[name], state="raised")
                    client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
                    log.info(f"Alarm RAISED: {name}")

                elif active and prev:
                    # still active -> reminder each cooldown
                    if now - last_alarm_emit[name] >= ALARM_COOLDOWN_SEC:
                        last_alarm_emit[name] = now
                        evt = build_alarm_event(device_id, name, raw_map[name], state="reminder")
                        client.send_message_to_output(make_msg(evt), OUTPUT_NAME)
                        log.info(f"Alarm REMINDER: {name}")

                elif (not active) and prev:
                    # falling edge
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
