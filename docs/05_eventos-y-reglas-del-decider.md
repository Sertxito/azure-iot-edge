# 05 - Eventos y reglas del decider

## Tipos de eventos

### state.change

Se emite solo ante cambio de estado.

Estados cubiertos:

- armed: ARMED/DISARMED
- door: open/closed
- motion: active/inactive
- light_bucket: bright/ambient/dark/unknown
- temp_band: low/normal/high/unknown
- hum_band: low/normal/high/unknown

### alarm

Sensores discretos con semantica edge-triggered:

- gas: raised/reminder/cleared
- pir: raised/cleared

### security.intrusion

Condicion compuesta:

- armed == true
- door == OPEN
- motion == true

### aggregate

Publicacion periodica (por defecto 900s):

- salud de modulo (uptime_sec, last_input_age_sec, seq)
- estado actual (armed, door, motion)
- medias del periodo (light/temp/humidity)

## Modelo de armado

- Touch true -> ARMED
- Touch false -> DISARMED
- No se persiste entre reinicios (arranque desarmado)

## Umbrales configurables

Por variables de entorno:

- LIGHT_BRIGHT_MAX, LIGHT_AMBIENT_MAX
- TEMP_LOW, TEMP_HIGH
- HUM_LOW, HUM_HIGH
- ALARM_CD_SEC
- AGG_PUB_SEC

## Errores transitorios esperables

Broken pipe (os error 32) puede aparecer en reconexiones edgeHub.

Mientras el modulo se recupere y continen eventos en logs, se considera ruido de runtime y no fallo funcional.
