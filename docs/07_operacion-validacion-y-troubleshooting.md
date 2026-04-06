# 07 - Operacion, validacion y troubleshooting

## Checklist de validacion rapida

1. Estado runtime:

```bash
iotedge list
```

Esperado: edgeAgent, edgeHub, mqtt-bridge y edgeDecider en running.

1. Logs bridge:

```bash
iotedge logs mqtt-bridge --tail 100
```

1. Logs decider:

```bash
iotedge logs edgeDecider --tail 100
```

1. Verificar eventos:

- state.change
- alarm
- security.intrusion
- aggregate

1. Verificar llegada a storage por ruta esperada.

## NUC vs Raspberry en operacion

La operacion diaria es la misma en ambos hosts (Linux + IoT Edge), pero cambia la arquitectura de imagen:

- NUC: `linux/amd64`.
- Raspberry Pi: `linux/arm64`.

Validaciones adicionales tras redeploy:

1. Confirmar tag de imagen correcto en `iotedge list`.
2. Confirmar convergencia cloud:
	- `lastDesiredStatus.code = 200`
	- `desiredVersion == reportedLastDesiredVersion`

## Checklist de cambio de red (NodeMCU + Edge)

1. Asegurar WiFi 2.4GHz para ESP8266.
2. Confirmar broker escuchando en 0.0.0.0:1883.
3. Confirmar misma LAN entre NodeMCU y Edge.
4. Validar conexion MQTT desde NodeMCU.

Comandos utiles en host Edge (NUC o Raspberry):

```bash
hostname -I
sudo systemctl status mosquitto
sudo ss -ltnp | grep 1883
mosquitto_sub -h localhost -t '#'
mosquitto_pub -h localhost -t test -m 'hello'
```

## Incidencias comunes

- MQTT state -2 en NodeMCU: broker no alcanzable o IP incorrecta.
- Bridge sin forward: payload no UTF-8 o JSON invalido.
- IoT Hub sin eventos: rutas mal configuradas o filtros incorrectos.
- $body.type no filtra: falta contentType/contentEncoding.
- ACR pull error: credenciales del registry ausentes en deployment.
- `monitor-events` vacio con pipeline sano: IoT Hub sin ruta a endpoint built-in `events`.

## Procedimiento temporal para `monitor-events`

1. Crear ruta debug a endpoint `events` con condicion `true`.
2. Validar trafico con `az iot hub monitor-events`.
3. Eliminar ruta debug al terminar.

No mantener esa ruta como configuracion permanente de produccion.

## Rollback operativo

1. Reasignar prioridad al deployment anterior estable.
2. Confirmar convergencia con iotedge list.
3. Revalidar flujo end-to-end en 5-10 minutos.
