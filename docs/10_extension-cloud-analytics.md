# 10 - Extension cloud analytics (Event Hubs + ADLS + Stream Analytics)

## Objetivo

Extender el pipeline actual (Edge -> IoT Hub -> Storage) para cubrir en la sesion una ruta cloud de analitica en tiempo real:

- IoT Hub -> Event Hubs
- Event Hubs -> Stream Analytics
- Stream Analytics -> ADLS Gen2
- Consumo analitico para Power BI

## Alcance de esta implementacion en repo

Implementado en este repositorio:

1. Script de provision base cloud: [scripts/provision-smartcity-cloud.ps1](../scripts/provision-smartcity-cloud.ps1)
2. Query base para Stream Analytics: [deployment/stream-analytics/query.sql](../deployment/stream-analytics/query.sql)
3. Script de configuracion Stream Analytics por CLI: [scripts/create-stream-analytics.ps1](../scripts/create-stream-analytics.ps1)

## Estado validado (entorno SmartCities)

Estado operativo validado en esta practica:

1. Subscription: `8e6ace56-e0f2-4071-825a-a20363df34f8`
2. Resource group: `SmartCities`
3. IoT Hub: `SmartCitiesIotHub`
4. Event Hubs namespace: `ehsmartcity2604062102`
5. Event Hub: `telemetry`
6. ADLS Gen2 account: `adls260406213642`
7. Filesystem: `iot-historical`
8. Stream Analytics job recomendado: `SmartCitiesAnalyticsV3`
9. Transformacion activa: `tmain`
10. Outputs activos de ASA: `outputraw`, `outputagg1m`

Pendiente de ejecutar en tu suscripcion:

1. Crear Job de Stream Analytics con:

- Input `input` (Event Hubs)
- Output `outputraw` (ADLS Gen2)
- Output `outputagg1m` (ADLS Gen2 o Power BI)

1. Pegar query del archivo `deployment/stream-analytics/query.sql`
1. Iniciar job y validar datos.

Alternativa automatizada por CLI (sin portal):

1. Script: [scripts/create-stream-analytics.ps1](../scripts/create-stream-analytics.ps1)
1. Usa Event Hubs como input, ADLS como outputs y aplica query desde `deployment/stream-analytics/query.sql`.

## Prerrequisitos

- Azure CLI autenticado (`az login`).
- Permisos para crear recursos en `ResourceGroup` destino.
- IoT Hub ya operativo (pipeline Edge actual funcionando).

## Provision base (Event Hubs + ADLS + ruta IoT Hub)

```powershell
./scripts/provision-smartcity-cloud.ps1 \
  -SubscriptionId "<SUBSCRIPTION_ID>" \
  -ResourceGroup "<RG_DATA>" \
  -Location "westeurope" \
  -IoTHubName "<IOTHUB_NAME>" \
  -IoTHubResourceGroup "<RG_IOTHUB>" \
  -IoTHubEndpointResourceGroup "<RG_DATA>" \
  -IoTHubEndpointSubscriptionId "<SUBSCRIPTION_ID>" \
  -EventHubNamespace "<EH_NAMESPACE>" \
  -EventHubName "telemetry" \
  -StorageAccountName "<ADLS_ACCOUNT_NAME>" \
  -DataLakeFileSystem "iot-historical"
```

Resultado esperado:

1. Namespace y Event Hub creados.
2. Storage account ADLS Gen2 creada con HNS activo.
3. Filesystem en ADLS creado.
4. Endpoint de IoT Hub hacia Event Hubs creado.
5. Ruta de IoT Hub para trafico de modulos Edge (`mqtt-bridge` y `edgeDecider`).

## Validacion rapida

1. Revisar endpoint y ruta en IoT Hub.
2. Confirmar mensajes entrantes en Event Hub.
3. Lanzar Stream Analytics con la query y verificar salida en ADLS.

## Smoke-test (10 minutos)

Objetivo: validar que el bootstrap cloud esta operativo de punta a punta sin hacer tuning.

### 1) Preparar variables en PowerShell

```powershell
$SUBSCRIPTION_ID = "<SUBSCRIPTION_ID>"
$RG_DATA = "<RG_DATA>"
$LOCATION = "westeurope"
$IOTHUB_NAME = "<IOTHUB_NAME>"
$RG_IOTHUB = "<RG_IOTHUB>"
$EH_NAMESPACE = "<EH_NAMESPACE>"
$EH_NAME = "telemetry"
$ADLS_ACCOUNT = "<ADLS_ACCOUNT_NAME>"
$ADLS_FS = "iot-historical"
```

### 1.1) Si no recuerdas tus recursos (autodeteccion rapida)

```powershell
# Suscripcion activa
$SUBSCRIPTION_ID = az account show --query id -o tsv

# Ver IoT Hubs disponibles y elegir uno
az iot hub list --query "[].{name:name,resourceGroup:resourcegroup,location:location}" -o table

# Asignar el IoT Hub elegido
$IOTHUB_NAME = "<IOTHUB_ELEGIDO>"
$RG_IOTHUB = "<RG_DEL_IOTHUB_ELEGIDO>"

# Reutiliza location del IoT Hub para simplificar
$LOCATION = az iot hub show --hub-name $IOTHUB_NAME --resource-group $RG_IOTHUB --query location -o tsv

# Resource group para data (puede ser nuevo o existente)
$RG_DATA = "<RG_DATA>"

# Nombres unicos sugeridos (cumplen reglas de naming)
$SUFFIX = (Get-Date -Format "yyMMddHHmm")
$EH_NAMESPACE = "ehsmartcity$SUFFIX"
$ADLS_ACCOUNT = "adlsmartcity$SUFFIX"
```

### 2) Ejecutar provision base

```powershell
./scripts/provision-smartcity-cloud.ps1 `
  -SubscriptionId $SUBSCRIPTION_ID `
  -ResourceGroup $RG_DATA `
  -Location $LOCATION `
  -IoTHubName $IOTHUB_NAME `
  -IoTHubResourceGroup $RG_IOTHUB `
  -IoTHubEndpointResourceGroup $RG_DATA `
  -IoTHubEndpointSubscriptionId $SUBSCRIPTION_ID `
  -EventHubNamespace $EH_NAMESPACE `
  -EventHubName $EH_NAME `
  -StorageAccountName $ADLS_ACCOUNT `
  -DataLakeFileSystem $ADLS_FS
```

### 3) Verificaciones minimas (debe devolver al menos una fila)

```powershell
az iot hub routing-endpoint list --hub-name $IOTHUB_NAME --resource-group $RG_IOTHUB --endpoint-type eventhub -o table
az iot hub route list --hub-name $IOTHUB_NAME --resource-group $RG_IOTHUB -o table
az eventhubs namespace list --resource-group $RG_DATA -o table
az eventhubs eventhub list -g $RG_DATA --namespace-name $EH_NAMESPACE --query "[].name" -o tsv
az storage fs list --account-name $ADLS_ACCOUNT --auth-mode login -o table
```

### 4) Criterio de exito

1. Existe endpoint IoT Hub de tipo Event Hub.
2. Existe ruta habilitada en IoT Hub hacia ese endpoint.
3. Event Hub `telemetry` existe en el namespace.
4. Filesystem `iot-historical` existe en ADLS.

Si todo esto pasa, la base para crear Stream Analytics y conectar Power BI esta lista.

## Crear Stream Analytics por CLI (sin portal)

```powershell
$SUBSCRIPTION_ID = "<SUBSCRIPTION_ID>"
$RG_DATA = "<RG_DATA>"
$LOCATION = "eastus"
$EH_NAMESPACE = "<EH_NAMESPACE>"
$EH_NAME = "telemetry"
$ADLS_ACCOUNT = "<ADLS_ACCOUNT_NAME>"
$ADLS_FS = "iot-historical"
$ASA_JOB = "asa-smartcity-live"

./scripts/create-stream-analytics.ps1 `
  -SubscriptionId $SUBSCRIPTION_ID `
  -ResourceGroup $RG_DATA `
  -Location $LOCATION `
  -JobName $ASA_JOB `
  -EventHubNamespace $EH_NAMESPACE `
  -EventHubName $EH_NAME `
  -StorageAccountName $ADLS_ACCOUNT `
  -FileSystemName $ADLS_FS `
  -QueryFilePath "deployment/stream-analytics/query.sql" `
  -StartJob
```

Validacion:

```powershell
az stream-analytics job show --resource-group $RG_DATA --name $ASA_JOB --query "{jobState:jobState, provisioningState:provisioningState}" -o table
az stream-analytics input list --resource-group $RG_DATA --job-name $ASA_JOB --query "[].name" -o tsv
az stream-analytics output list --resource-group $RG_DATA --job-name $ASA_JOB --query "[].name" -o tsv
```

## Comandos validados para prueba end-to-end

### Generar trafico en NUC (bash)

```bash
for i in $(seq 1 30); do
  mosquitto_pub -h localhost -t "building/01/home/nodemcu01/telemetry" -m '{"deviceId":"nodemcu01","sensors":{"motion":false,"door":"CLOSED","gas":false,"touch":false,"ldr_raw":245,"temperature":22.4,"humidity":51.2}}'
  sleep 1
done
```

### Descargar ultimo RAW y AGGREGATE

```powershell
$RG = "SmartCities"
$ADLS_ACCOUNT = "adls260406213642"
$ADLS_FS = "iot-historical"
$SA_KEY = az storage account keys list --resource-group $RG --account-name $ADLS_ACCOUNT --query "[0].value" -o tsv

$LATEST_RAW = az storage blob list --account-name $ADLS_ACCOUNT --account-key $SA_KEY --container-name $ADLS_FS --prefix "raw/" --query 'sort_by(@, &properties.lastModified)[-1].name' -o tsv
$LOCAL_RAW = "$env:TEMP\raw-latest.json"
az storage blob download --account-name $ADLS_ACCOUNT --account-key $SA_KEY --container-name $ADLS_FS --name "$LATEST_RAW" --file $LOCAL_RAW --overwrite
Get-Content $LOCAL_RAW -Tail 20

$LATEST_AGG = az storage blob list --account-name $ADLS_ACCOUNT --account-key $SA_KEY --container-name $ADLS_FS --prefix "aggregates/" --query 'sort_by(@, &properties.lastModified)[-1].name' -o tsv
$LOCAL_AGG = "$env:TEMP\agg-latest.json"
az storage blob download --account-name $ADLS_ACCOUNT --account-key $SA_KEY --container-name $ADLS_FS --name "$LATEST_AGG" --file $LOCAL_AGG --overwrite
Get-Content $LOCAL_AGG -Tail 20
```

## Notas operativas importantes

1. En este entorno, nombres de output ASA con `_` no son validos. Usar `outputraw` y `outputagg1m`.
2. Para `az stream-analytics transformation update`, usar `--transformation-name` y no asumir nombre por defecto.
3. Si se pasa SAQL multilínea por CLI y falla compilacion por EOF, normalizar a una linea antes de invocar CLI.
4. `az monitor metrics list` para Event Hubs se consulta sobre el namespace, no sobre el recurso hijo `namespaces/eventhubs`.

## Trade-offs

- Se duplica ruta de datos (Storage directo e Event Hubs) para ganar capacidad analitica en tiempo real.
- Incrementa coste operativo, pero habilita analitica avanzada y visualizacion near-real-time.
- Mantener filtros por `connectionModuleId` evita mezclar trafico no deseado.

## Riesgos y mitigaciones

- Riesgo: crecimiento de coste por unidades de Stream Analytics/Event Hubs.
  Mitigacion: empezar con SKU minimo y alertas de coste.
- Riesgo: rutas solapadas en IoT Hub.
  Mitigacion: convencion de nombres y revision periodica de rutas.
- Riesgo: latencia por backlog en picos.
  Mitigacion: particiones adecuadas y validacion de throughput.
