---
name: azure-deployment-preflight
description: 'Realiza validacion preflight integral de despliegues Bicep en Azure, incluyendo validacion de sintaxis, analisis what-if y comprobaciones de permisos antes de desplegar.'
---

# Azure Deployment Preflight Validation

Esta habilidad valida despliegues de Bicep antes de ejecutar cambios reales, soportando flujos con Azure CLI (`az`) y Azure Developer CLI (`azd`).

## Cuando usar esta habilidad

- Antes de desplegar infraestructura en Azure.
- Al preparar o revisar archivos Bicep.
- Para previsualizar cambios con what-if.
- Para verificar permisos de despliegue.
- Antes de ejecutar `azd up`, `azd provision` o `az deployment`.

## Proceso de validacion

Sigue los pasos en orden. Si un paso falla, continua con el siguiente y registra todos los problemas en el informe final.

### Paso 1: Detectar tipo de proyecto

1. Comprobar si es proyecto `azd`:
- Buscar `azure.yaml` en la raiz.
- Si existe, usar flujo `azd`.
- Si no existe, usar flujo `az CLI`.

2. Localizar archivos Bicep:
- En proyectos `azd`, revisar primero `infra/` y luego raiz.
- En proyectos standalone, usar el archivo indicado por el usuario o buscar en `infra/`, `deploy/` y raiz.

3. Detectar archivos de parametros para cada Bicep:
- `<filename>.bicepparam` (preferido).
- `<filename>.parameters.json`.
- `parameters.json` o `parameters/<env>.json` en la misma carpeta.

### Paso 2: Validar sintaxis Bicep

Ejecutar:

```bash
bicep build <bicep-file> --stdout
```

Capturar:
- Errores de sintaxis con linea/columna.
- Warnings.
- Estado final (ok/fallo).

Si `bicep` no esta instalado:
- Anotarlo en el informe.
- Continuar al paso 3.

### Paso 3: Ejecutar validacion preflight

#### Proyectos azd

Ejecutar:

```bash
azd provision --preview
```

Si hay varios entornos o uno especificado:

```bash
azd provision --preview --environment <env-name>
```

#### Proyectos standalone (sin azure.yaml)

Determinar `targetScope` y usar el comando correspondiente:

- `resourceGroup`: `az deployment group what-if`
- `subscription`: `az deployment sub what-if`
- `managementGroup`: `az deployment mg what-if`
- `tenant`: `az deployment tenant what-if`

Ejecutar primero con `--validation-level Provider`.

Si falla por permisos, reintentar con `ProviderNoRbac` y anotarlo en el informe.

### Paso 4: Capturar resultados what-if

Clasificar cambios:

- `+` Create
- `-` Delete
- `~` Modify
- `=` NoChange
- `*` Ignore
- `!` Deploy

Para recursos modificados, registrar propiedades cambiadas.

### Paso 5: Generar informe

Crear `preflight-report.md` en la raiz del proyecto usando la plantilla:

- [references/REPORT-TEMPLATE.md](references/REPORT-TEMPLATE.md)

Secciones minimas del informe:

1. Resumen
2. Herramientas ejecutadas y comandos
3. Issues (errores/warnings)
4. Resultado de what-if
5. Recomendaciones accionables

## Informacion requerida

Antes de validar, reunir:

- Resource Group (para scope group)
- Subscription
- Location (sub/mg/tenant)
- Environment (si aplica en azd)

Si falta informacion, preguntar al usuario antes de continuar.

## Manejo de errores

Referencia detallada:

- [references/ERROR-HANDLING.md](references/ERROR-HANDLING.md)

Principio: no parar en el primer error; capturar todo lo relevante en el reporte final.

## Requisitos de herramientas

- Azure CLI (`az`)
- Azure Developer CLI (`azd`) para proyectos con `azure.yaml`
- Bicep CLI (`bicep`)

Comprobacion rapida:

```bash
az --version
azd version
bicep --version
```

## Referencias

- [references/VALIDATION-COMMANDS.md](references/VALIDATION-COMMANDS.md)
- [references/REPORT-TEMPLATE.md](references/REPORT-TEMPLATE.md)
- [references/ERROR-HANDLING.md](references/ERROR-HANDLING.md)
