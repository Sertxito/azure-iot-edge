# 08 - Hardware y red NodeMCU

## Board y pines

Placa objetivo: NodeMCU ESP8266 (LoLin).

Mapa de pines:

- PIR -> D5
- Gas MQ (DO activo en LOW) -> D6
- Reed puerta/ventana -> D7
- Touch -> D1
- LDR analogico -> A0
- DHT11/DHT22 -> D2

## Alimentacion

- 5V/VU para modulo de gas MQ.
- 3V3 para reed, touch, LDR y DHT.
- GND comun para todos los sensores.

## Modelo de red

- NodeMCU funciona como cliente MQTT saliente.
- No requiere IP fija.
- El broker MQTT en Edge si debe tener IP fija o DNS estable.

## Identidad de dispositivo

Se recomienda identificar por:

1. Topic MQTT (ejemplo):

```text
building/01/home/nodemcu01/telemetry
```

1. MQTT client id (ejemplo): nodemcu01.
1. Campos de payload (deviceId, building, domain).

## Integracion con firmware local

- Firmware: arduino/ESP_Home.ino.
- Secrets locales: arduino/secrets.local.h (generado desde .env.local).

## Objetivo funcional del nodo

- Deteccion de presencia (PIR)
- Estado de puerta/ventana (reed)
- Deteccion de gas (MQ)
- Luz ambiente (LDR)
- Temperatura y humedad (DHT)
- Control local de armado (touch)
