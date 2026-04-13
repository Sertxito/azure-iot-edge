# 11 - Power BI para la sesion Smart City

## Objetivo

Definir un informe de Power BI que demuestre en vivo el flujo:

- Edge -> IoT Hub -> Event Hubs -> Stream Analytics -> ADLS

Este dashboard prioriza narrativa de sesion, operacion y claridad para audiencia tecnica.

## Fuente recomendada para demo

Usar la salida agregada de Stream Analytics en ADLS:

- Contenedor: `iot-historical`
- Prefijo: `aggregates/`
- Campos esperados por registro: `window_end`, `device_id`, `events_count`, `avg_temperature`, `max_temperature`, `avg_humidity`, `avg_power_w`

Nota:

- `raw/` se usa para auditoria y troubleshooting, no como visual principal en directo.

## Arquitectura de datos en el informe

1. Tabla principal: `FactAgg1m` (agregados por minuto y dispositivo).
2. Tabla opcional de soporte: `FactRaw` (solo para detalle tecnico).
3. Dimensiones minimas:

- `DimDevice` (unica por `device_id`).
- `DimTime` (si se quiere inteligencia temporal adicional).

Para una demo rapida, con `FactAgg1m` es suficiente.

## Conexion en Power BI Desktop (ADLS Gen2)

### Opcion A: Azure Data Lake Storage Gen2 connector

1. Get Data -> Azure -> Azure Data Lake Storage Gen2.
2. Introducir la cuenta (ejemplo: `adls260406213642`).
3. Seleccionar `iot-historical`.
4. Filtrar objetos por ruta que empiece por `aggregates/`.
5. Combinar y transformar.

### Opcion B: Blob connector

1. Get Data -> Azure -> Azure Blob Storage.
2. Conectar con cuenta y credenciales organizacionales.
3. Filtrar a `aggregates/`.
4. Combinar y transformar.

## Transformacion recomendada en Power Query

Si los archivos vienen como JSON line-separated, convertir binario por lineas y parsear JSON.

Ejemplo de script M (ajustar nombre de pasos segun tu consulta):

```powerquery
let
    Source = AzureStorage.DataLake("https://adls260406213642.dfs.core.windows.net"),
    FileSystem = Source{[Name="iot-historical"]}[Data],
    AggOnly = Table.SelectRows(FileSystem, each Text.StartsWith([Folder Path], "https://adls260406213642.dfs.core.windows.net/iot-historical/aggregates/")),
    KeepContent = Table.SelectColumns(AggOnly, {"Content", "Name", "Date modified"}),
    ExpandedLines = Table.AddColumn(KeepContent, "Lines", each Lines.FromBinary([Content], null, null, 65001)),
    ExpandedList = Table.ExpandListColumn(ExpandedLines, "Lines"),
    RemoveBlanks = Table.SelectRows(ExpandedList, each [Lines] <> null and Text.Trim([Lines]) <> ""),
    ParsedJson = Table.AddColumn(RemoveBlanks, "Json", each Json.Document([Lines])),
    ExpandedJson = Table.ExpandRecordColumn(
        ParsedJson,
        "Json",
        {"window_end", "device_id", "events_count", "avg_temperature", "max_temperature", "avg_humidity", "avg_power_w"},
        {"window_end", "device_id", "events_count", "avg_temperature", "max_temperature", "avg_humidity", "avg_power_w"}
    ),
    ChangedTypes = Table.TransformColumnTypes(
        ExpandedJson,
        {
            {"window_end", type datetimezone},
            {"device_id", type text},
            {"events_count", Int64.Type},
            {"avg_temperature", type number},
            {"max_temperature", type number},
            {"avg_humidity", type number},
            {"avg_power_w", type number}
        }
    )
in
    ChangedTypes
```

## Medidas DAX recomendadas

Crear estas medidas en `FactAgg1m`:

```DAX
Eventos Total = SUM(FactAgg1m[events_count])

Temp Media = AVERAGE(FactAgg1m[avg_temperature])

Humedad Media = AVERAGE(FactAgg1m[avg_humidity])

Potencia Media = AVERAGE(FactAgg1m[avg_power_w])

Temp Max = MAX(FactAgg1m[max_temperature])

Ultima Marca = MAX(FactAgg1m[window_end])
```

Opcional para mostrar ultimo valor de temperatura:

```DAX
Temp Media Ultimo Minuto =
VAR T = [Ultima Marca]
RETURN
CALCULATE(
    [Temp Media],
    FactAgg1m[window_end] = T
)
```

## Layout recomendado (1 pagina de demo)

### Franja superior (KPI)

1. Card: `Eventos Total`
2. Card: `Temp Media`
3. Card: `Humedad Media`
4. Card: `Ultima Marca`

### Zona central

1. Line chart (principal):

- X: `window_end`
- Y: `Temp Media` y `Humedad Media`
- Leyenda opcional: `device_id`

2. Clustered column chart:

- Axis: `device_id`
- Value: `Eventos Total`

### Zona inferior

1. Tabla operativa:

- `window_end`
- `device_id`
- `events_count`
- `avg_temperature`
- `avg_humidity`
- `avg_power_w`

## Filtros de pagina

Aplicar estos filtros para estabilidad de demo:

1. `window_end` relativo: ultimos 15 o 30 minutos.
2. Excluir `device_id` nulo.
3. Si hay mucho ruido, filtrar al nodo principal de la demo.

## Guion tecnico de 2 minutos con el dashboard

1. Mostrar cards: estado actual y que hay eventos en tiempo real.
2. Mostrar linea temporal: variacion de temperatura/humedad por minuto.
3. Mostrar barras por dispositivo: comparativa de actividad.
4. Mostrar tabla: trazabilidad del dato agregado.

Mensaje final:

- El edge decide localmente.
- La nube consolida, agrega y habilita analitica para operacion.

## Riesgos en vivo y mitigaciones

1. No llegan datos nuevos al informe.

- Revisar que Stream Analytics este en `Running`.
- Revisar que haya blobs nuevos en `aggregates/`.
- Refrescar dataset/manual refresh en Desktop.

2. Valores nulos o inconsistentes.

- Verificar query en [deployment/stream-analytics/query.sql](../deployment/stream-analytics/query.sql).
- Confirmar payload actual en `raw/`.

3. Latencia alta en visual.

- Reducir ventana temporal del filtro.
- Limitar visuales a los 3-4 criticos.

## Criterio de aceptacion para la sesion

1. El informe refresca con datos de los ultimos minutos.
2. Se visualizan minimo:

- Una serie temporal.
- Un KPI de estado.
- Una comparativa por dispositivo.

3. La narrativa de arquitectura queda conectada de extremo a extremo.
