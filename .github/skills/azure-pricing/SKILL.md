---
name: azure-pricing
description: 'Obtiene precios retail de Azure en tiempo real usando la API Azure Retail Prices (prices.azure.com) y estima consumo de creditos de agentes de Copilot Studio. Usar cuando el usuario pregunte por coste de cualquier servicio de Azure, quiera comparar precios por SKU, necesite datos de precio para una estimacion de coste, mencione precios/costes/facturacion de Azure, o pregunte por precios de Copilot Studio, Copilot Credits o estimacion de uso de agentes. Cubre compute, storage, networking, bases de datos, AI, Copilot Studio y el resto de familias de servicios de Azure.'
compatibility: Requires internet access to prices.azure.com and learn.microsoft.com. No authentication needed.
metadata:
  author: anthonychu
  version: "1.2"
---

# Azure Pricing Skill

Usa esta habilidad para obtener precios retail de Azure en tiempo real desde la API publica Azure Retail Prices. No requiere autenticacion.

## Cuando usar esta habilidad

- El usuario pregunta por el coste de un servicio de Azure (por ejemplo, "How much does a D4s v5 VM cost?")
- El usuario quiere comparar precios entre regiones o SKUs
- El usuario necesita una estimacion de coste para una carga o arquitectura
- El usuario menciona precios, costes o facturacion de Azure
- El usuario pregunta por precio de instancia reservada frente a pago por uso
- El usuario quiere informacion sobre savings plans o precios Spot

## API Endpoint

```
GET https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview
```

Añade `$filter` como parametro de consulta usando sintaxis OData. Usa siempre `api-version=2023-01-01-preview` para incluir datos de savings plan.

## Instrucciones paso a paso

Si algo de la solicitud del usuario no esta claro, haz preguntas de aclaracion para identificar los campos y valores correctos del filtro antes de llamar a la API.

1. **Identifica campos de filtro** a partir de la solicitud del usuario (nombre de servicio, region, SKU, tipo de precio).
2. **Resuelve la region**: la API requiere valores `armRegionName` en minusculas y sin espacios (p. ej. "East US" → `eastus`, "West Europe" → `westeurope`, "Southeast Asia" → `southeastasia`). Consulta [references/REGIONS.md](references/REGIONS.md) para la lista completa.
3. **Construye la cadena de filtro** usando los campos de abajo y consulta la URL.
4. **Analiza el array `Items`** de la respuesta JSON. Cada item contiene precio y metadatos.
5. **Sigue la paginacion** mediante `NextPageLink` si necesitas mas de los primeros 1000 resultados (normalmente no hace falta).
6. **Calcula estimaciones de coste** con las formulas de [references/COST-ESTIMATOR.md](references/COST-ESTIMATOR.md) para obtener estimaciones mensuales/anuales.
7. **Presenta resultados** en una tabla clara con servicio, SKU, region, precio unitario y estimaciones mensual/anual.

## Campos filtrables

| Field | Type | Example |
|---|---|---|
| `serviceName` | string (exact, case-sensitive) | `'Functions'`, `'Virtual Machines'`, `'Storage'` |
| `serviceFamily` | string (exact, case-sensitive) | `'Compute'`, `'Storage'`, `'Databases'`, `'AI + Machine Learning'` |
| `armRegionName` | string (exact, lowercase) | `'eastus'`, `'westeurope'`, `'southeastasia'` |
| `armSkuName` | string (exact) | `'Standard_D4s_v5'`, `'Standard_LRS'` |
| `skuName` | string (contains supported) | `'D4s v5'` |
| `priceType` | string | `'Consumption'`, `'Reservation'`, `'DevTestConsumption'` |
| `meterName` | string (contains supported) | `'Spot'` |

Usa `eq` para igualdad, `and` para combinar y `contains(field, 'value')` para coincidencias parciales.

## Ejemplos de cadenas de filtro

```
# All consumption prices for Functions in East US
serviceName eq 'Functions' and armRegionName eq 'eastus' and priceType eq 'Consumption'

# D4s v5 VMs in West Europe (consumption only)
armSkuName eq 'Standard_D4s_v5' and armRegionName eq 'westeurope' and priceType eq 'Consumption'

# All storage prices in a region
serviceName eq 'Storage' and armRegionName eq 'eastus'

# Spot pricing for a specific SKU
armSkuName eq 'Standard_D4s_v5' and contains(meterName, 'Spot') and armRegionName eq 'eastus'

# 1-year reservation pricing
serviceName eq 'Virtual Machines' and priceType eq 'Reservation' and armRegionName eq 'eastus'

# Azure AI / OpenAI pricing (now under Foundry Models)
serviceName eq 'Foundry Models' and armRegionName eq 'eastus' and priceType eq 'Consumption'

# Azure Cosmos DB pricing
serviceName eq 'Azure Cosmos DB' and armRegionName eq 'eastus' and priceType eq 'Consumption'
```

## URL de ejemplo completa

```
https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview&$filter=serviceName eq 'Functions' and armRegionName eq 'eastus' and priceType eq 'Consumption'
```

Codifica espacios como `%20` y comillas como `%27` al construir la URL.

## Campos clave de respuesta

```json
{
  "Items": [
    {
      "retailPrice": 0.000016,
      "unitPrice": 0.000016,
      "currencyCode": "USD",
      "unitOfMeasure": "1 Execution",
      "serviceName": "Functions",
      "skuName": "Premium",
      "armRegionName": "eastus",
      "meterName": "vCPU Duration",
      "productName": "Functions",
      "priceType": "Consumption",
      "isPrimaryMeterRegion": true,
      "savingsPlan": [
        { "unitPrice": 0.000012, "term": "1 Year" },
        { "unitPrice": 0.000010, "term": "3 Years" }
      ]
    }
  ],
  "NextPageLink": null,
  "Count": 1
}
```

Usa solo items donde `isPrimaryMeterRegion` sea `true`, salvo que el usuario pida explicitamente medidores no primarios.

## Valores `serviceFamily` soportados

`Analytics`, `Compute`, `Containers`, `Data`, `Databases`, `Developer Tools`, `Integration`, `Internet of Things`, `Management and Governance`, `Networking`, `Security`, `Storage`, `Web`, `AI + Machine Learning`

## Recomendaciones

- Los valores de `serviceName` son sensibles a mayusculas/minusculas. Si hay dudas, filtra primero por `serviceFamily` para descubrir valores validos de `serviceName`.
- Si no hay resultados, amplia el filtro (por ejemplo, elimina primero `priceType` o restricciones de region).
- Los precios estan en USD salvo que se especifique `currencyCode` en la solicitud.
- Para precios de savings plan, revisa el array `savingsPlan` en cada item (solo en `2023-01-01-preview`).
- Consulta [references/SERVICE-NAMES.md](references/SERVICE-NAMES.md) para un catalogo de nombres de servicio comunes y su casing correcto.
- Consulta [references/COST-ESTIMATOR.md](references/COST-ESTIMATOR.md) para formulas y patrones de estimacion de coste.
- Consulta [references/COPILOT-STUDIO-RATES.md](references/COPILOT-STUDIO-RATES.md) para tarifas de Copilot Studio y formulas de estimacion.

## Resolucion de problemas

| Issue | Solution |
|-------|----------|
| Empty results | Amplia el filtro: elimina primero `priceType` o `armRegionName` |
| Wrong service name | Usa filtro `serviceFamily` para descubrir valores validos de `serviceName` |
| Missing savings plan data | Asegura que `api-version=2023-01-01-preview` esta en la URL |
| URL errors | Revisa codificacion de URL: espacios como `%20`, comillas como `%27` |
| Too many results | Anade mas campos de filtro (region, SKU, priceType) para acotar |

---

# Copilot Studio Agent Usage Estimation

Usa esta seccion cuando el usuario pregunte por precios de Copilot Studio, Copilot Credits o costes de uso de agentes.

## Cuando usar esta seccion

- El usuario pregunta por precios o costes de Copilot Studio
- El usuario pregunta por Copilot Credits o consumo de creditos de agente
- El usuario quiere estimar costes mensuales de un agente de Copilot Studio
- El usuario menciona estimacion de uso de agentes o el estimador de Copilot Studio
- El usuario pregunta cuanto costara ejecutar un agente

## Datos clave

- **1 Copilot Credit = $0.01 USD**
- Los creditos se agrupan a nivel de todo el tenant
- Los agentes orientados a empleados con usuarios licenciados de M365 Copilot obtienen respuestas clasicas, respuestas generativas y grounding con tenant graph sin coste
- El control de sobreconsumo se activa al 125% de la capacidad prepagada

## Estimacion paso a paso

1. **Recoge entradas** del usuario: tipo de agente (empleado/cliente), numero de usuarios, interacciones/mes, % de conocimiento, % de tenant graph, uso de herramientas por sesion.
2. **Recupera tarifas en vivo**: usa la herramienta integrada de web fetch para descargar las tarifas mas recientes desde las URLs fuente listadas abajo. Asi la estimacion usa siempre precios actualizados de Microsoft.
3. **Analiza el contenido recuperado** para extraer la tabla actual de tarifas (creditos por tipo de funcionalidad).
4. **Calcula la estimacion** usando tarifas y formulas del contenido recuperado:
   - `total_sessions = users × interactions_per_month`
   - Knowledge credits: apply tenant graph grounding rate, generative answer rate, and classic answer rate
   - Agent tools credits: apply agent action rate per tool call
   - Agent flow credits: apply flow rate per 100 actions
   - Prompt modifier credits: apply basic/standard/premium rates per 10 responses
5. **Presenta resultados** en una tabla clara con desglose por categoria, creditos totales y coste estimado en USD.

## URLs fuente a consultar

Al responder preguntas de precio de Copilot Studio, consulta el contenido mas reciente de estas URLs como contexto:

| URL | Contenido |
|---|---|
| https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-messages-management | Tabla de tarifas, ejemplos de facturacion, reglas de sobreconsumo |
| https://learn.microsoft.com/en-us/microsoft-copilot-studio/billing-licensing | Opciones de licencia, inclusiones de M365 Copilot, prepago vs pago por uso |

Consulta al menos la primera URL (tarifas) antes de calcular. La segunda aporta contexto complementario para preguntas de licenciamiento.

Consulta [references/COPILOT-STUDIO-RATES.md](references/COPILOT-STUDIO-RATES.md) para una copia en cache de tarifas, formulas y ejemplos de facturacion (usar como fallback si web fetch no esta disponible).
