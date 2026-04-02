# Deployment (Azure IoT Edge)

Este proyecto usa **UN SOLO deployment** en Azure IoT Hub.

## Contiene
- mqtt-bridge
- edgeDecider
- credenciales ACR
- 1 única route

## Importante
- Los deployments NO se editan
- Para cambiar algo:
  - Clonar
  - Ajustar
  - Subir prioridad
  - Borrar el anterior

## Routes válidas
Solo esta:

FROM /messages/modules/mqtt-bridge/outputs/telemetry
INTO BrokeredEndpoint("/modules/edgeDecider/inputs/input1")

Cualquier otra ruta rompe el decider.
