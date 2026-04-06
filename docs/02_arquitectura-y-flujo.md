# 02 - Arquitectura y flujo end-to-end

## Vista de alto nivel

NodeMCU/ESP8266
-> MQTT Broker (Mosquitto)
-> mqtt-bridge (IoT Edge)
-> edgeDecider (IoT Edge)
-> edgeHub
-> IoT Hub ($upstream)
-> Blob Storage (raw/events/aggregates)

## Responsabilidades por componente

### NodeMCU

- Captura sensores fisicos.
- Publica payload MQTT.
- No conoce Azure.

### mqtt-bridge

- Se suscribe a topic MQTT.
- Normaliza payload RAW a contrato estable.
- Reenvia por salida IoT Edge telemetry.

### edgeDecider

- Consume input1.
- Aplica reglas de negocio local.
- Emite state.change, alarm, security.intrusion y aggregate.

### IoT Hub

- Recibe mensajes por upstream.
- Filtra por system properties y body JSON.
- Enruta a endpoints de almacenamiento.

## Decisiones clave

1. Separar adaptacion (bridge) de decision (decider).
2. Mantener contrato estable para evitar acoplamiento a firmware.
3. Priorizar eventos semanticos frente a telemetria ruidosa continua.
4. Mantener tambien RAW para auditoria y depuracion.

## Trade-offs

- Se duplica trafico al enviar RAW y eventos, pero se gana trazabilidad.
- Mayor complejidad en routing, pero mejor gobierno de datos.
- Agregado periodico reduce volumen, pero introduce latencia de resumen.
