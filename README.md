# IoT Edge – MQTT Bridge + Edge Decider

Pipeline Edge real ejecutándose en Azure IoT Edge (Raspberry Pi).

## Arquitectura

NodeMCU → MQTT (Mosquitto)
→ mqtt-bridge (Edge, normaliza payload)
→ edgeDecider (Edge, decide)
→ (cloud opcional)

## Módulos

### mqtt-bridge
- Escucha MQTT
- Normaliza payload (NodeMCU → sensorSim-like)
- Publica a IoT Edge output `telemetry`

### edgeDecider
- Consume `input1`
- Ejecuta lógica:
  - alarmas
  - agregados
  - heartbeat
- NO depende del formato del dispositivo

## Por qué así
- El bridge desacopla dispositivos del core
- El decider es estable y reutilizable
- Edge decide, cloud observa

## Estado
✅ Running en Azure IoT Edge  
✅ Routing limpio (mqtt-bridge → edgeDecider)  
✅ Sin contratos rotos
