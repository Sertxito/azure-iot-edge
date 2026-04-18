---
name: appinsights-instrumentation
description: 'Instrumentar una aplicacion web para enviar telemetria util a Azure App Insights'
---

# AppInsights instrumentation

Esta habilidad permite enviar telemetria de una aplicacion web a Azure App Insights para mejorar la observabilidad del estado de la aplicacion.

## Cuando usar esta habilidad

Usa esta habilidad cuando el usuario quiera habilitar telemetria para su aplicacion web.

## Prerequisites

La aplicacion del workspace debe ser de uno de estos tipos:

- An ASP.NET Core app hosted in Azure
- A Node.js app hosted in Azure

## Guidelines

### Recopilar informacion de contexto

Identifica la combinacion (lenguaje de programacion, framework de aplicacion y hosting) de la aplicacion a la que el usuario quiere anadir telemetria. Esto determina como se puede instrumentar la aplicacion. Lee el codigo fuente para hacer una estimacion fundamentada. Confirma con el usuario cualquier dato que no conozcas. Debes preguntar siempre donde esta alojada la aplicacion (por ejemplo, en un equipo personal, en Azure App Service como codigo, en Azure App Service como contenedor, en Azure Container Apps, etc.).

### Priorizar auto-instrumentacion cuando sea posible

Si la aplicacion es C# ASP.NET Core y esta alojada en Azure App Service, usa la [guia AUTO](references/AUTO.md) para ayudar al usuario a auto-instrumentarla.

### Instrumentacion manual

Instrumenta la aplicacion manualmente creando el recurso de AppInsights y actualizando el codigo de la aplicacion.

#### Crear el recurso de AppInsights

Usa una de las siguientes opciones segun el entorno.

- Anade AppInsights a una plantilla Bicep existente. Mira [examples/appinsights.bicep](examples/appinsights.bicep) para ver que incluir. Esta es la mejor opcion si ya hay plantillas Bicep en el workspace.
- Usa Azure CLI. Mira [scripts/appinsights.ps1](scripts/appinsights.ps1) para ver el comando de Azure CLI que crea el recurso de App Insights.

Independientemente de la opcion elegida, recomienda al usuario crear el recurso de App Insights en un grupo de recursos con sentido operativo para facilitar la gestion. Un buen candidato suele ser el mismo grupo de recursos que contiene los recursos de la aplicacion alojada en Azure.

#### Modificar el codigo de la aplicacion

- Si la aplicacion es ASP.NET Core, consulta la [guia ASPNETCORE](references/ASPNETCORE.md) para modificar el codigo C#.
- Si la aplicacion es Node.js, consulta la [guia NODEJS](references/NODEJS.md) para modificar el codigo JavaScript/TypeScript.
- Si la aplicacion es Python, consulta la [guia PYTHON](references/PYTHON.md) para modificar el codigo Python.
