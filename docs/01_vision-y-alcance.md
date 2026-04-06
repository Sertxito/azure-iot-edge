# 01 - Vision y alcance

## Objetivo

Construir una solucion IoT Edge para Smart Home/Smart Building donde la decision ocurra en el borde (Edge) y la nube se use para persistencia, analitica y operacion.

Principio rector:

Edge decide, IoT Hub enruta, Storage persiste.

## Alcance funcional

- Ingesta de telemetria desde dispositivos MQTT (NodeMCU/ESP8266).
- Adaptacion de formatos heterogeneos a un contrato estable.
- Emision de eventos semanticos y agregados desde Edge.
- Enrutado en Azure IoT Hub hacia almacenamiento por tipo de dato.
- Operacion reproducible en Raspberry Pi (ARM64) y NUC/equipos x86_64.

## Fuera de alcance

- Visualizacion final en dashboards de negocio.
- Motor de ML en cloud para inferencia en tiempo real.
- Provisioning masivo de dispositivos en este repositorio.

## Criterios de calidad

- Seguridad: no secretos en codigo, uso de configuracion local/entorno.
- Observabilidad: logs accionables y checklist de diagnostico.
- Coste: reduccion de ruido de telemetria al emitir eventos de valor.
- Portabilidad: misma logica para hardware edge distinto.

## Entrega por fases

1. MVP funcional: ingesta, normalizacion, eventos base.
2. Endurecimiento: resiliencia, seguridad, operacion.
3. Escalado: optimizacion de costes, capacidad y gobierno.
