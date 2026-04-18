# azure-iot-edge

Proyecto IoT Edge para ingesta MQTT, normalizacion de payload y decision semantica local antes de subir a Azure IoT Hub.

## Arranque rapido operativo

Si quieres ponerlo en marcha sin perderte, sigue este orden:

1. Revisa prerequisitos y prepara secretos locales.
2. Ejecuta tests unitarios para validar contrato y reglas.
3. Despliega o redepliega el runtime Edge.
4. Verifica telemetria y routing en IoT Hub.
5. (Opcional) Activa extension cloud analytics y Stream Analytics.

## Prerequisitos minimos

- Azure CLI autenticado (`az login`).
- Permisos sobre suscripcion, resource group e IoT Hub destino.
- Docker disponible para build de modulos.
- Dispositivo Edge registrado en IoT Hub.
- Secrets locales sincronizados desde plantilla.

## Flujo operativo recomendado

### 1) Sincronizar secretos locales

```powershell
./scripts/sync-local-secrets.ps1
```

### 2) Ejecutar tests

```bash
python -m unittest discover -s tests -v
```

### 3) Redeploy Edge completo

```powershell
./scripts/redeploy-edge.ps1 -SubscriptionId "<SUBSCRIPTION_ID>" -ResourceGroup "<RESOURCE_GROUP>" -IoTHubName "<IOTHUB_NAME>" -DeviceId "<EDGE_DEVICE_ID>" -AcrName "<ACR_NAME>"
```

### 4) Validar monitorizacion/rutas

- Usa `az iot hub monitor-events` para validar trafico en endpoint `events`.
- Si no ves eventos y solo hay rutas a endpoints custom, crea una ruta temporal de debug a `events`, valida y retirala.

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

## Ayuntamiento Landing y dashboard Smart City

La entrada principal de demo es Ayuntamiento Landing, conectada a Blob para datos reales cuando estan disponibles.

1. Abre `docs/blob-config.js`.
2. Configura `enabled: true`.
3. Revisa `baseUrl`, `container`, `prefix` y `sasToken` (si aplica).
4. Abre `docs/ayuntamiento-landing.html` en tu navegador.

Si hay problema de acceso (SAS/CORS/ruta), la pagina entra en modo demo automaticamente para no romper la presentacion.

Vista avanzada estilo sala de operaciones Smart City:

- `docs/smart-city-ops-center.html`
- Incluye gemelo urbano simulado con rutas, semaforos, trafico, red electrica, renovables y optimizacion AI de transporte.
- Usa la misma configuracion de `docs/blob-config.js`.

### Setup rapido (recomendado)

Puedes dejarlo listo con un solo script:

```powershell
./scripts/setup-landing-blob-access.ps1 -SubscriptionId "<SUBSCRIPTION_ID>" -StorageAccountName "<STORAGE_ACCOUNT_NAME>" -ContainerName "iot-historical" -Prefix "aggregates/"
```

El script:

1. Configura CORS para lecturas desde navegador.
2. Genera SAS de lectura/listado para el contenedor.
3. Actualiza `docs/blob-config.js` automaticamente.

Si la landing sigue en demo, revisa primero:

1. `enabled: true` en `docs/blob-config.js`.
2. `sasToken` no vacio y vigente.
3. Que existan blobs en `aggregates/`.

## Estructura tecnica

- [bridge/mqtt/main.py](bridge/mqtt/main.py): bridge MQTT -> IoT Edge (normalizacion + forward).
- [decider/main.py](decider/main.py): motor de reglas y eventos semanticos.
- [arduinos/ESP_Home.ino](arduinos/ESP_Home.ino): firmware de referencia NodeMCU.

## Como usar el agente y las skills

La carpeta [.github](.github) forma parte oficial del repositorio y se publica de forma intencional.

Su objetivo es que cualquier persona del equipo (o externa) pueda usar el agente de forma consistente y productiva.

### Flujo recomendado de uso

1. Pide el objetivo de negocio o tecnico en lenguaje natural.
2. El agente aplicara instrucciones globales de [.github/instructions](.github/instructions).
3. Si aplica, enruta a una skill de [.github/skills](.github/skills).
4. Recibe una salida estructurada (arquitectura, backlog, checklist, pasos de ejecucion).

### Que hace cada carpeta

- [.github/instructions](.github/instructions): reglas base obligatorias para cualquier respuesta.
- [.github/agents](.github/agents): especializacion del rol del agente para este dominio.
- [.github/skills](.github/skills): playbooks para tareas concretas (arquitectura, pricing, preflight, visualizacion, etc.).

## Ejemplos practicos de prompts

### 1) Arquitectura Smart City end-to-end

Prompt:

```text
Disena una arquitectura Smart City para movilidad y calidad del aire en 2 distritos, con edge local y backlog por fases.
```

Artefactos esperados:

- Arquitectura propuesta + flujo de datos.
- Seguridad y operacion.
- Plan por fases con riesgos y KPI.

### 2) Validacion preflight antes de desplegar Bicep

Prompt:

```text
Valida este despliegue Bicep antes de ejecutar azd provision y dame un preflight-report con riesgos y acciones.
```

Artefactos esperados:

- Resultado de validaciones de sintaxis/what-if.
- Problemas detectados con severidad.
- Recomendaciones accionables.

### 3) Estimacion de costes Azure

Prompt:

```text
Calcula coste mensual estimado para IoT Hub + Event Hubs + ADLS en westeurope para 2 millones de eventos/dia.
```

Artefactos esperados:

- Tabla de precios por servicio/SKU.
- Supuestos usados.
- Total mensual y opciones de optimizacion.

### 4) Diagrama de recursos existentes

Prompt:

```text
Analiza mi resource group y generame un diagrama Mermaid con relaciones entre red, compute, datos y seguridad.
```

Artefactos esperados:

- Inventario de recursos.
- Diagrama Mermaid detallado.
- Observaciones de arquitectura.

### Referencias directas de uso

- Skill Smart City: [.github/skills/azure-smart-city-iot-solution-builder/SKILL.md](.github/skills/azure-smart-city-iot-solution-builder/SKILL.md)
- Plantilla de entregables: [.github/skills/azure-smart-city-iot-solution-builder/references/smart-city-solution-template.md](.github/skills/azure-smart-city-iot-solution-builder/references/smart-city-solution-template.md)
- Instruccion IoT Edge: [.github/instructions/azure-iot-edge-architecture.instructions.md](.github/instructions/azure-iot-edge-architecture.instructions.md)
- Agente especializado: [.github/agents/azure-smart-city-iot-architect.agent.md](.github/agents/azure-smart-city-iot-architect.agent.md)

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
