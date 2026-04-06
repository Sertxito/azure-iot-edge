WITH Base AS (
    SELECT
        System.Timestamp() AS window_end,
        i.ts AS source_ts,
        i.source AS source,
        COALESCE(
            TRY_CAST(i.sensors.dht11.temp_c AS float),
            TRY_CAST(i.sensors.temperature.last AS float),
            TRY_CAST(i.temperature AS float)
        ) AS temperature,
        COALESCE(
            TRY_CAST(i.sensors.dht11.humidity AS float),
            TRY_CAST(i.sensors.humidity.last AS float),
            TRY_CAST(i.humidity AS float)
        ) AS humidity,
        TRY_CAST(i.power_w AS float) AS power_w,
        COALESCE(i.type, 'telemetry') AS message_type,
        COALESCE(i.deviceId, i.device_id) AS device_id,
        i.sensor_id AS sensor_id,
        i.window_sec AS window_sec,
        COALESCE(i._meta.door, i.sensors.door.state) AS door_state,
        i._meta.touch AS touch,
        i.sensors.pir.motion AS pir_motion,
        i.sensors.gas.alarm AS gas_alarm,
        COALESCE(
            TRY_CAST(i.sensors.light.analog AS float),
            TRY_CAST(i.sensors.light.last AS float)
        ) AS light_analog,
        i.sensors.light.state AS light_state,
        i.sensors.temperature.state AS temp_state,
        i.sensors.humidity.state AS hum_state,
        i.system.armed AS system_armed,
        TRY_CAST(i.system.uptime_sec AS bigint) AS system_uptime_sec,
        TRY_CAST(i.system.last_input_age_sec AS bigint) AS system_last_input_age_sec,
        TRY_CAST(i.system.seq AS bigint) AS system_seq
    FROM input i
)

SELECT
    window_end,
    source_ts,
    source,
    message_type,
    device_id,
    sensor_id,
    window_sec,

    door_state,
    touch,
    pir_motion,
    gas_alarm,
    light_analog,
    light_state,

    temperature,
    temp_state,
    humidity,
    hum_state,
    power_w
    ,system_armed
    ,system_uptime_sec
    ,system_last_input_age_sec
    ,system_seq
INTO outputraw
FROM Base;

SELECT
    System.Timestamp() AS window_end,
    device_id,
    COUNT(*) AS events_count,
    AVG(temperature) AS avg_temperature,
    MAX(temperature) AS max_temperature,
    AVG(humidity) AS avg_humidity,
    AVG(power_w) AS avg_power_w
INTO outputagg1m
FROM Base
WHERE message_type = 'telemetry'
GROUP BY device_id, TumblingWindow(minute, 1);
