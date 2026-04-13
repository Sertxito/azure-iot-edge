# edge-decider

Proyecto IoT Edge para ingesta MQTT, normalizacion de payload y decision semantica local antes de subir a Azure IoT Hub.

## Lectura recomendada de documentacion

1. [docs/01_vision-y-alcance.md](docs/01_vision-y-alcance.md)
2. [docs/02_arquitectura-y-flujo.md](docs/02_arquitectura-y-flujo.md)
3. [docs/03_configuracion-local-y-secrets.md](docs/03_configuracion-local-y-secrets.md)
4. [docs/04_contrato-de-datos.md](docs/04_contrato-de-datos.md)
5. [docs/05_eventos-y-reglas-del-decider.md](docs/05_eventos-y-reglas-del-decider.md)
6. [docs/06_despliegue-edge-e-iothub-routing.md](docs/06_despliegue-edge-e-iothub-routing.md)
7. [docs/07_operacion-validacion-y-troubleshooting.md](docs/07_operacion-validacion-y-troubleshooting.md)
8. [docs/08_hardware-y-red-nodemcu.md](docs/08_hardware-y-red-nodemcu.md)
9. [docs/09_historial-de-cambios.md](docs/09_historial-de-cambios.md)
10. [docs/10_extension-cloud-analytics.md](docs/10_extension-cloud-analytics.md)
11. [docs/11_powerbi-dashboard-sesion.md](docs/11_powerbi-dashboard-sesion.md)

## Estructura tecnica

- [bridge/mqtt/main.py](bridge/mqtt/main.py): bridge MQTT -> IoT Edge (normalizacion + forward).
- [decider/main.py](decider/main.py): motor de reglas y eventos semanticos.
- [arduinos/ESP_Home.ino](arduinos/ESP_Home.ino): firmware de referencia NodeMCU.

## Comandos utiles

### Tests

```bash
python -m unittest discover -s tests -v
```

### Secrets locales para Arduino

```powershell
./scripts/sync-local-secrets.ps1
```

### Redeploy completo Edge (build + deployment)

```powershell
./scripts/redeploy-edge.ps1 -SubscriptionId "<SUBSCRIPTION_ID>" -ResourceGroup "<RESOURCE_GROUP>" -IoTHubName "<IOTHUB_NAME>" -DeviceId "<EDGE_DEVICE_ID>" -AcrName "<ACR_NAME>"
```

### Provision base cloud analytics (Event Hubs + ADLS + ruta IoT Hub)

```powershell
./scripts/provision-smartcity-cloud.ps1 -SubscriptionId "<SUBSCRIPTION_ID>" -ResourceGroup "<RG_DATA>" -Location "westeurope" -IoTHubName "<IOTHUB_NAME>" -IoTHubResourceGroup "<RG_IOTHUB>" -EventHubNamespace "<EH_NAMESPACE>" -StorageAccountName "<ADLS_ACCOUNT_NAME>"
```

### Configurar Stream Analytics por CLI (input Event Hub + outputs ADLS)

```powershell
./scripts/create-stream-analytics.ps1 -SubscriptionId "<SUBSCRIPTION_ID>" -ResourceGroup "<RG_DATA>" -Location "<LOCATION>" -JobName "<ASA_JOB>" -EventHubNamespace "<EH_NAMESPACE>" -EventHubName "telemetry" -StorageAccountName "<ADLS_ACCOUNT_NAME>" -FileSystemName "iot-historical" -QueryFilePath "deployment/stream-analytics/query.sql" -StartJob
```

## Entorno operativo actual

El entorno operativo activo es NUC (x86_64) con imagenes `linux/amd64`.

La referencia a Raspberry Pi se mantiene solo como material educativo/historico,
no como objetivo de despliegue actual.

## Nota sobre monitorizacion en IoT Hub

`az iot hub monitor-events` solo muestra trafico del endpoint built-in `events`.

Si el hub enruta solo a endpoints custom (storage/event hubs), puede no mostrar eventos aunque el pipeline funcione.
En ese caso, crear una ruta temporal de debug a `events`, validar y eliminarla.
