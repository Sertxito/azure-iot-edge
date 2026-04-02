import json
import paho.mqtt.client as mqtt
from azure.iot.device import IoTHubModuleClient

MQTT_BROKER = "localhost"
MQTT_PORT = 1883
MQTT_TOPIC = "building/01/home/+/telemetry"

EDGE_OUTPUT = "telemetry"

# Create IoT Edge client
edge_client = IoTHubModuleClient.create_from_edge_environment()

def on_connect(client, userdata, flags, rc):
    print(f"[MQTT] Connected with result code {rc}")
    client.subscribe(MQTT_TOPIC)
    print(f"[MQTT] Subscribed to {MQTT_TOPIC}")

def on_message(client, userdata, msg):
    payload = msg.payload.decode()
    print(f"[MQTT] {msg.topic} -> {payload}")

    # Forward message to IoT Edge
    edge_client.send_message_to_output(payload, EDGE_OUTPUT)
    print("[EDGE] Message forwarded")

mqtt_client = mqtt.Client()
mqtt_client.on_connect = on_connect
mqtt_client.on_message = on_message

mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
mqtt_client.loop_forever()
