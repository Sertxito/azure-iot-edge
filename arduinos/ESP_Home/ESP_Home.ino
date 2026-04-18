#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <DHT.h>

#include "../secrets.local.h"

// ================== PINES ==================
#define PIN_PIR     D5
#define PIN_GAS     D6   // MQ DO (activo en LOW)
#define PIN_REED    D7   // Magnetic switch
#define PIN_TOUCH   D1   // Touch sensor
#define PIN_LDR     A0   // LDR analógico
#define PIN_DHT     D2

// ================== DHT ====================
#define DHTTYPE DHT11          // cambia a DHT22 si aplica
DHT dht(PIN_DHT, DHTTYPE);

// ================== LDR (3 estados) ====================
// Ajustados a lo que calibraste (luz -> valores bajos, oscuridad -> altos)
const int LDR_BRIGHT_MAX  = 150;  // <150  => BRIGHT
const int LDR_AMBIENT_MAX = 350;  // <350  => AMBIENT ; >=350 => DARK

// ================== WIFI ===================
// Override these values at build time or before flashing.
#ifndef WIFI_SSID_VALUE
#define WIFI_SSID_VALUE "CHANGE_ME_SSID"
#endif

#ifndef WIFI_PASS_VALUE
#define WIFI_PASS_VALUE "CHANGE_ME_PASSWORD"
#endif

const char* WIFI_SSID = WIFI_SSID_VALUE;
const char* WIFI_PASS = WIFI_PASS_VALUE;

// ================== MQTT ===================
#ifndef MQTT_HOST_VALUE
#define MQTT_HOST_VALUE "192.168.1.50"
#endif

const char* MQTT_HOST  = MQTT_HOST_VALUE; // IP del Edge / broker MQTT
const int   MQTT_PORT  = 1883;

// Topic alineado como has decidido
const char* MQTT_TOPIC = "building/01/home/nodemcu01/telemetry";

// Identidad MQTT (única)
const char* MQTT_CLIENT_ID = "nodemcu01";

WiFiClient espClient;
PubSubClient mqtt(espClient);

unsigned long lastPublishMs = 0;
const unsigned long PUBLISH_EVERY_MS = 5000;

// ================== WIFI ===================
const char* wifiStatusToString(wl_status_t status) {
  switch (status) {
    case WL_IDLE_STATUS: return "IDLE";
    case WL_NO_SSID_AVAIL: return "NO_SSID_AVAIL";
    case WL_SCAN_COMPLETED: return "SCAN_COMPLETED";
    case WL_CONNECTED: return "CONNECTED";
    case WL_CONNECT_FAILED: return "CONNECT_FAILED";
    case WL_CONNECTION_LOST: return "CONNECTION_LOST";
    case WL_DISCONNECTED: return "DISCONNECTED";
    default: return "UNKNOWN";
  }
}

void connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.persistent(false);
  WiFi.disconnect();
  delay(200);

  Serial.print("SSID configured: ");
  Serial.println(WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASS);

  Serial.print("Connecting to WiFi");
  unsigned long start = millis();
  const unsigned long timeoutMs = 20000;
  while (WiFi.status() != WL_CONNECTED && (millis() - start) < timeoutMs) {
    delay(400);
    Serial.print(".");
  }

  wl_status_t st = WiFi.status();
  if (st == WL_CONNECTED) {
    Serial.println("\nWiFi connected ✅");
    Serial.print("Node IP: ");
    Serial.println(WiFi.localIP());
    return;
  }

  Serial.println("\nWiFi connection FAILED ❌");
  Serial.print("Status: ");
  Serial.print((int)st);
  Serial.print(" (");
  Serial.print(wifiStatusToString(st));
  Serial.println(")");
}

// ================== MQTT ===================
void connectMQTT() {
  while (!mqtt.connected()) {
    Serial.print("Connecting to MQTT broker ");
    Serial.print(MQTT_HOST);
    Serial.print(":");
    Serial.print(MQTT_PORT);
    Serial.print(" ... ");

    if (mqtt.connect(MQTT_CLIENT_ID)) {
      Serial.println("connected ✅");
    } else {
      Serial.print("failed (state=");
      Serial.print(mqtt.state());
      Serial.println(") retrying...");
      delay(2000);
    }
  }
}

// ================== SETUP ==================
void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(PIN_PIR, INPUT);
  pinMode(PIN_GAS, INPUT);
  pinMode(PIN_REED, INPUT);
  pinMode(PIN_TOUCH, INPUT);

  dht.begin();

  Serial.println("\nBOOT OK - Smart Home Node (WiFi + MQTT)");

  connectWiFi();
  mqtt.setServer(MQTT_HOST, MQTT_PORT);
}

// ================== LOOP ===================
void loop() {
  // Mantener WiFi
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost -> reconnecting...");
    connectWiFi();
  }

  // Mantener MQTT
  if (!mqtt.connected()) {
    connectMQTT();
  }
  mqtt.loop(); // recomendado llamarlo frecuentemente [1](https://github.com/knolleary/pubsubclient/blob/master/examples/mqtt_esp8266/mqtt_esp8266.ino)

  // Publicación periódica
  unsigned long now = millis();
  if (now - lastPublishMs >= PUBLISH_EVERY_MS) {
    lastPublishMs = now;

    // --------- Lectura sensores ----------
    bool motionDetected = digitalRead(PIN_PIR);

    // Gas activo en LOW (ya lo confirmaste)
    bool gasDetected = (digitalRead(PIN_GAS) == LOW);

    // Reed y touch: si alguno te sale invertido, lo invertimos igual que gas.
    bool doorOpen = (digitalRead(PIN_REED) == LOW);
    bool touchPressed = digitalRead(PIN_TOUCH);

    int ldrRaw = analogRead(PIN_LDR);
    const char* lightState;
    if (ldrRaw < LDR_BRIGHT_MAX)      lightState = "BRIGHT";
    else if (ldrRaw < LDR_AMBIENT_MAX) lightState = "AMBIENT";
    else                               lightState = "DARK";

    float temperature = dht.readTemperature();
    float humidity    = dht.readHumidity();
    bool dhtOk = !(isnan(temperature) || isnan(humidity));

    // --------- JSON payload ----------
    // (simple y fácil de parsear en Edge)
    String payload = "{";
    payload += "\"deviceId\":\"nodemcu01\",";
    payload += "\"building\":\"01\",";
    payload += "\"domain\":\"home\",";
    payload += "\"ts_ms\":" + String((unsigned long)millis()) + ",";
    payload += "\"sensors\":{";
    payload += "\"motion\":" + String(motionDetected ? "true" : "false") + ",";
    payload += "\"door\":\"" + String(doorOpen ? "OPEN" : "CLOSED") + "\",";
    payload += "\"gas\":" + String(gasDetected ? "true" : "false") + ",";
    payload += "\"touch\":" + String(touchPressed ? "true" : "false") + ",";
    payload += "\"light\":\"" + String(lightState) + "\",";
    payload += "\"ldr_raw\":" + String(ldrRaw) + ",";
    if (dhtOk) {
      payload += "\"temperature\":" + String(temperature, 1) + ",";
      payload += "\"humidity\":" + String(humidity, 1);
    } else {
      payload += "\"temperature\":null,";
      payload += "\"humidity\":null";
    }
    payload += "}}";

    // --------- Publish ----------
    bool ok = mqtt.publish(MQTT_TOPIC, payload.c_str());
    Serial.println("========== SMART HOME STATUS ==========");
    Serial.print("MQTT topic: "); Serial.println(MQTT_TOPIC);
    Serial.print("Publish: "); Serial.println(ok ? "OK ✅" : "FAILED ❌");

    Serial.print("MOTION: "); Serial.println(motionDetected ? "DETECTED" : "NO");
    Serial.print("DOOR: ");   Serial.println(doorOpen ? "OPEN" : "CLOSED");
    Serial.print("GAS: ");    Serial.println(gasDetected ? "ALARM" : "OK");
    Serial.print("TOUCH: ");  Serial.println(touchPressed ? "PRESSED" : "IDLE");
    Serial.print("LIGHT: ");  Serial.print(lightState);
    Serial.print(" (RAW ");   Serial.print(ldrRaw); Serial.println(")");

    if (dhtOk) {
      Serial.print("TEMP: "); Serial.print(temperature); Serial.print(" °C | ");
      Serial.print("HUM: ");  Serial.print(humidity);    Serial.println(" %");
    } else {
      Serial.println("DHT: ERROR (null sent)");
    }

    Serial.println("JSON payload:");
    Serial.println(payload);
    Serial.println("======================================\n");
  }
}