import json
import time
from datetime import datetime, timezone

from azure.iot.device import IoTHubModuleClient, Message

import config


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def create_message(payload: dict) -> Message:
    msg = Message(json.dumps(payload))
    msg.content_type = "application/json"
    msg.content_encoding = "utf-8"
    return msg


def is_alarm_event(data: dict):
    sensors = data.get("sensors", {})
    if sensors.get("gas", {}).get("alarm"):
        return "gas"
    if sensors.get("sound", {}).get("alarm"):
        return "sound"
    if sensors.get("pir", {}).get("motion"):
        return "pir"
    return None


def main():
    client = IoTHubModuleClient.create_from_edge_environment()
    client.connect()

    last_aggregate_ts = time.time()
    last_heartbeat_ts = time.time()

    aggregate_buffer = {
        "light": [],
        "sound": []
    }

    print("edgeDecider started")

    while True:
        msg = client.receive_message_on_input("input1", timeout=1)

        now = time.time()

        if msg:
            data = json.loads(msg.data.decode("utf-8"))
            device_id = data.get(config.DEVICE_ID_FIELD, "unknown")

            alarm_sensor = is_alarm_event(data)
            if alarm_sensor:
                alarm_event = {
                    "type": "alarm",
                    "deviceId": device_id,
                    "ts": utc_now(),
                    "source": "edgeDecider",
                    "severity": "high",
                    "data": {
                        "sensor": alarm_sensor,
                        "raw": data["sensors"].get(alarm_sensor)
                    }
                }
                client.send_message_to_output(
                    create_message(alarm_event),
                    "output1"
                )
                print(f"Alarm sent: {alarm_sensor}")

            sensors = data.get("sensors", {})
            if "light" in sensors:
                aggregate_buffer["light"].append(sensors["light"]["analog"])
            if "sound" in sensors:
                aggregate_buffer["sound"].append(sensors["sound"]["analog"])

        if now - last_aggregate_ts >= config.AGGREGATE_WINDOW_SEC:
            if aggregate_buffer["light"] or aggregate_buffer["sound"]:
                aggregate_event = {
                    "type": "aggregate",
                    "deviceId": device_id,
                    "ts": utc_now(),
                    "source": "edgeDecider",
                    "window_sec": config.AGGREGATE_WINDOW_SEC,
                    "data": {
                        "light_avg": (
                            sum(aggregate_buffer["light"]) / len(aggregate_buffer["light"])
                            if aggregate_buffer["light"] else None
                        ),
                        "sound_avg": (
                            sum(aggregate_buffer["sound"]) / len(aggregate_buffer["sound"])
                            if aggregate_buffer["sound"] else None
                        )
                    }
                }

                client.send_message_to_output(
                    create_message(aggregate_event),
                    "output1"
                )
                print("Aggregate sent")

            aggregate_buffer = {"light": [], "sound": []}
            last_aggregate_ts = now

        if now - last_heartbeat_ts >= config.HEARTBEAT_INTERVAL_SEC:
            heartbeat_event = {
                "type": "heartbeat",
                "deviceId": device_id,
                "ts": utc_now(),
                "source": "edgeDecider",
                "status": "ok",
                "uptime_sec": int(now)
            }

            client.send_message_to_output(
                create_message(heartbeat_event),
                "output1"
            )
            print("Heartbeat sent")

            last_heartbeat_ts = now


if __name__ == "__main__":
    main()
