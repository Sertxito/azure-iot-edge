# 03 - Configuracion local y secrets

## Objetivo

Centralizar secretos y parametros locales en un unico flujo sin versionarlos.

## Archivos clave

- .env.local: valores reales locales (gitignored).
- arduino/secrets.local.h: fichero generado local (gitignored).
- scripts/sync-local-secrets.ps1: sincroniza .env.local -> arduino/secrets.local.h.

## Flujo recomendado

1. Copiar .env.local.example a .env.local.
2. Editar WIFI_SSID, WIFI_PASS, MQTT_HOST y resto de variables.
3. Ejecutar:

```powershell
./scripts/sync-local-secrets.ps1
```

1. Compilar firmware con arduino/secrets.local.h generado.

## Precedencia de configuracion

1. Variables de entorno exportadas por runtime (IoT Edge/OS).
2. Valores cargados desde .env.local en desarrollo.
3. Defaults en codigo como ultimo fallback.

## Variables relevantes

### Bridge

- MQTT_BROKER
- MQTT_PORT
- MQTT_TOPIC
- EDGE_OUTPUT
- MQTT_KEEPALIVE
- LOG_LEVEL

### Decider

- ED_IN
- ED_OUT
- AGG_PUB_SEC
- ALARM_CD_SEC
- LIGHT_BRIGHT_MAX
- LIGHT_AMBIENT_MAX
- TEMP_LOW / TEMP_HIGH
- HUM_LOW / HUM_HIGH

### Firmware

- WIFI_SSID
- WIFI_PASS
- MQTT_HOST

## Regla de seguridad

No almacenar secretos reales en README, docs, codigo ni commits.
