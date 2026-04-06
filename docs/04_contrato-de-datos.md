# 04 - Contrato de datos

## Problema que resuelve el bridge

Los dispositivos pueden publicar formatos RAW distintos entre si.

Si el decider consume directamente esos formatos, se rompe la logica por cambios de estructura.

## Payload RAW (ejemplo NodeMCU)

```json
{
  "deviceId": "nodemcu01",
  "sensors": {
    "motion": false,
    "door": "OPEN",
    "gas": false,
    "touch": false,
    "light": "AMBIENT",
    "ldr_raw": 245,
    "temperature": 22.1,
    "humidity": 52.0
  }
}
```

## Payload normalizado (salida mqtt-bridge)

```json
{
  "deviceId": "nodemcu01",
  "sensors": {
    "gas": {"analog": null, "alarm": false},
    "sound": {"analog": null, "alarm": false},
    "light": {"analog": 245},
    "pir": {"motion": false},
    "dht11": {"temp_c": 22.1, "humidity": 52.0}
  },
  "_meta": {"door": "OPEN", "touch": false}
}
```

## Reglas del contrato estable

- sensors siempre es objeto.
- gas/light/pir/dht11 son objetos con claves conocidas.
- _meta concentra campos auxiliares de contexto (door/touch).
- deviceId siempre presente (fallback unknown si falta).

## Beneficios

- Evita romper el decider por cambios de firmware.
- Permite coexistencia de varios tipos de dispositivo.
- Facilita tests y evolucion de reglas.

## Regla de diseño

El bridge adapta. El decider decide.
