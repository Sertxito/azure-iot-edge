# 09 - Historial de cambios

## Estado actual

- Pipeline estable y validado.
- Contrato de datos robusto ante payload RAW y normalizado.
- Eventos semanticos en Edge funcionando (state.change, alarm, security.intrusion, aggregate).
- Routing Edge e IoT Hub alineado y sin duplicados funcionales.
- Flujo de secretos locales centralizado con .env.local y sincronizacion a Arduino.
- Despliegue IoT Edge estabilizado con estrategia blue/green.
- Operacion actual centrada en NUC (amd64).
- Politica definida para ruta debug temporal de `monitor-events` (crear-validar-eliminar).
- Base cloud analytics anadida para sesion: Event Hubs + ADLS + routing IoT Hub.
- Flujo cloud validado extremo a extremo: Event Hubs -> Stream Analytics -> ADLS.

## Cambios relevantes recientes

1. Hardening de runtime:

- Manejo defensivo de payload en bridge.
- Recuperacion de envio en decider.
- Contenedores ejecutando con usuario no root.

1. Reglas y semantica:

- Emision edge-triggered en alarmas e intrusion.
- Agregado periodico con salud y snapshot de sensores.

1. Operacion y pruebas:

- Suite de tests unitarios en verde.
- Checklist de troubleshooting y rollback documentado.

1. Extension cloud analytics:

- Script `scripts/provision-smartcity-cloud.ps1` para bootstrap de Event Hubs + ADLS + ruta IoT Hub.
- Script `scripts/create-stream-analytics.ps1` para configurar ASA por CLI (sin portal).
- Query `deployment/stream-analytics/query.sql` endurecida para payloads telemetry/aggregate y alias de outputs validos (`outputraw`, `outputagg1m`).

## Riesgos abiertos

- Dependencia de calidad de red local WiFi/MQTT.
- Necesidad de disciplina operativa en deployments clonados.

## Siguientes pasos sugeridos

1. Plantilla de deployment JSON versionada con createOptions endurecido.
2. Observabilidad centralizada (workbook/alertas) para eventos clave.
3. Politicas de coste por entorno dev/test/prod.
