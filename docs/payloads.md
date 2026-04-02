# Payloads

Este documento explica **por qué existe el mqtt-bridge** y qué problema resuelve.

---

## RAW (NodeMCU)

Ejemplo de payload que llega desde el NodeMCU por MQTT:

    {
      "deviceId": "nodemcu01",
      "sensors": {
        "light": "AMBIENT",
        "gas": false,
        "motion": false
      }
    }

❌ Problema:
- Los sensores no son objetos
- El formato **no es estable**
- Rompe lógica que espera `.get()`

---

## NORMALIZED (salida del mqtt-bridge)

Payload que el bridge envía al Edge runtime:

    {
      "deviceId": "nodemcu01",
      "sensors": {
        "gas": {
          "analog": null,
          "alarm": false
        },
        "sound": {
          "analog": null,
          "alarm": false
        },
        "light": {
          "analog": 245
        },
        "pir": {
          "motion": false
        },
        "dht11": {
          "temp_c": 22.1,
          "humidity": 51.0
        }
      }
    }

✅ Ventajas:
- Contrato estable
- El decider no depende del dispositivo
- Nuevos dispositivos no rompen la lógica

---

## Regla de diseño

> El **bridge adapta**.  
> El **decider decide**.

Nunca mezclar ambas responsabilidades.
