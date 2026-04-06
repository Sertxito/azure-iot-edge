# 06 - Despliegue Edge e IoT Hub routing

## Regla operativa

Mantener un solo deployment activo en IoT Hub.

Los cambios se hacen con estrategia blue/green para evitar ventana de configuracion vacia en `$edgeAgent`:

1. Crear deployment nuevo con mayor prioridad.
2. Esperar convergencia del dispositivo.
3. Eliminar deployment anterior.

## Rutas IoT Edge (deployment)

```text
FROM /messages/modules/mqtt-bridge/outputs/telemetry
INTO BrokeredEndpoint("/modules/edgeDecider/inputs/input1")

FROM /messages/modules/mqtt-bridge/outputs/telemetry
INTO $upstream

FROM /messages/modules/edgeDecider/outputs/*
INTO $upstream
```

## Endpoints cloud recomendados

- raw-storage -> raw-data
- events-storage -> events-data
- aggregates-storage -> aggregates-data

## Filtros IoT Hub (Message Routing)

### RAW

```sql
$connectionModuleId = 'mqtt-bridge'
```

### EVENTS

```sql
$connectionModuleId = 'edgeDecider'
AND $body.type != 'aggregate'
```

### AGGREGATES

```sql
$connectionModuleId = 'edgeDecider'
AND $body.type = 'aggregate'
```

## Requisito para filtros $body

Los mensajes del decider deben incluir:

- contentType = application/json
- contentEncoding = utf-8

Si falta esto, IoT Hub no evaluara correctamente $body.type.

## Hardening recomendado

En createOptions por modulo:

```json
{
  "HostConfig": {
    "RestartPolicy": {
      "Name": "always"
    }
  }
}
```

## Automatizacion desde este repo

Se puede automatizar build + nuevo deployment con:

```powershell
./scripts/redeploy-edge.ps1 \
  -SubscriptionId "<SUBSCRIPTION_ID>" \
  -ResourceGroup "<RESOURCE_GROUP>" \
  -IoTHubName "<IOTHUB_NAME>" \
  -DeviceId "<EDGE_DEVICE_ID>" \
  -AcrName "<ACR_NAME>"
```

Que hace el script:

1. Selecciona suscripcion y valida extension azure-iot.
2. Construye imagenes para plataforma objetivo:
  - NUC (x86_64): `linux/amd64`.
  - Raspberry Pi (ARM64): `linux/arm64`.
  - En `-ImagePlatform auto`, la plataforma se infiere por `-DeviceId`.
3. Genera `deployment/modules-content-<tag>.json`.
4. Aplica deployment en IoT Hub con blue/green (create nuevo + delete anterior).

Opciones utiles:

- `-SkipBuild`: reutiliza un tag ya existente.
- `-SkipApply`: solo genera content para revision.
- `-ImagePlatform linux/amd64|linux/arm64`: fuerza arquitectura.

## Nota de observabilidad (monitor-events)

`az iot hub monitor-events` escucha el endpoint built-in `events`.

Si el hub enruta solo a endpoints custom, monitor-events puede verse vacio aunque haya trafico.
En troubleshooting, crear una ruta temporal de debug a `events`, validar y eliminarla.
