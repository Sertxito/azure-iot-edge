Param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$IoTHubName,

    [Parameter(Mandatory = $true)]
    [string]$IoTHubResourceGroup,

    [string]$IoTHubEndpointResourceGroup = "",
    [string]$IoTHubEndpointSubscriptionId = "",

    [Parameter(Mandatory = $true)]
    [string]$EventHubNamespace,

    [string]$EventHubName = "telemetry",
    [string]$EventHubSku = "Standard",

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [string]$DataLakeFileSystem = "iot-historical",

    [string]$IotHubEventHubEndpointName = "eh-telemetry",
    [string]$IotHubRouteName = "route-to-eventhub",

    [switch]$SkipRoute,
    [switch]$SkipStorage,
    [switch]$SkipEventHub
)

$ErrorActionPreference = "Stop"

function Invoke-Az {
    param([string[]]$Args)
    $result = & az @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Args -join ' ')"
    }
    return $result
}

function Invoke-AzTsv {
    param([string[]]$Args)
    $result = & az @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Args -join ' ')"
    }
    return ($result | Out-String).Trim()
}

function Ensure-AzureIotExtension {
    $ext = Invoke-AzTsv @('extension', 'list', '--query', "[?name=='azure-iot'].name", '-o', 'tsv')
    if (-not $ext) {
        Invoke-Az @('extension', 'add', '--name', 'azure-iot', '--yes') | Out-Null
    }
}

function Ensure-ResourceGroup {
    $rgExists = Invoke-AzTsv @('group', 'exists', '--name', $ResourceGroup)
    if ($rgExists -eq "true") { return }
    Invoke-Az @('group', 'create', '--name', $ResourceGroup, '--location', $Location) | Out-Null
}

function Ensure-EventHubNamespace {
    $found = Invoke-AzTsv @('eventhubs', 'namespace', 'list', '--resource-group', $ResourceGroup, '--query', "[?name=='$EventHubNamespace'].name", '-o', 'tsv')
    if ($found) { return }

    Invoke-Az @('eventhubs', 'namespace', 'create', '--name', $EventHubNamespace, '--resource-group', $ResourceGroup, '--location', $Location, '--sku', $EventHubSku) | Out-Null

    $created = Invoke-AzTsv @('eventhubs', 'namespace', 'list', '--resource-group', $ResourceGroup, '--query', "[?name=='$EventHubNamespace'].name", '-o', 'tsv')
    if (-not $created) {
        throw "No se pudo validar la creacion del Event Hubs namespace '$EventHubNamespace' en RG '$ResourceGroup'."
    }
}

function Ensure-EventHub {
    $found = Invoke-AzTsv @('eventhubs', 'eventhub', 'list', '--namespace-name', $EventHubNamespace, '--resource-group', $ResourceGroup, '--query', "[?name=='$EventHubName'].name", '-o', 'tsv')
    if ($found) { return }

    # Use only mandatory args for compatibility across Azure CLI versions.
    Invoke-Az @('eventhubs', 'eventhub', 'create', '--name', $EventHubName, '--namespace-name', $EventHubNamespace, '--resource-group', $ResourceGroup) | Out-Null

    $created = Invoke-AzTsv @('eventhubs', 'eventhub', 'list', '--namespace-name', $EventHubNamespace, '--resource-group', $ResourceGroup, '--query', "[?name=='$EventHubName'].name", '-o', 'tsv')
    if (-not $created) {
        throw "No se pudo validar la creacion del Event Hub '$EventHubName' en namespace '$EventHubNamespace'."
    }
}

function Ensure-StorageAccount {
    $found = Invoke-AzTsv @('storage', 'account', 'list', '--resource-group', $ResourceGroup, '--query', "[?name=='$StorageAccountName'].name", '-o', 'tsv')
    if ($found) { return }
    Invoke-Az @('storage', 'account', 'create', '--name', $StorageAccountName, '--resource-group', $ResourceGroup, '--location', $Location, '--sku', 'Standard_LRS', '--kind', 'StorageV2', '--hns', 'true', '--https-only', 'true', '--allow-blob-public-access', 'false', '--min-tls-version', 'TLS1_2') | Out-Null
}

function Ensure-DataLakeFileSystem {
    $found = Invoke-AzTsv @('storage', 'fs', 'list', '--account-name', $StorageAccountName, '--auth-mode', 'login', '--query', "[?name=='$DataLakeFileSystem'].name", '-o', 'tsv')
    if ($found) { return }
    Invoke-Az @('storage', 'fs', 'create', '--name', $DataLakeFileSystem, '--account-name', $StorageAccountName, '--auth-mode', 'login') | Out-Null
}

function Ensure-IotHubEventHubEndpoint {
    $found = Invoke-AzTsv @('iot', 'hub', 'routing-endpoint', 'list', '--hub-name', $IoTHubName, '--resource-group', $IoTHubResourceGroup, '--endpoint-type', 'eventhub', '--query', "[?name=='$IotHubEventHubEndpointName'].name", '-o', 'tsv')

    if ($found) { return }

    $ehConn = Invoke-AzTsv @('eventhubs', 'namespace', 'authorization-rule', 'keys', 'list', '--resource-group', $ResourceGroup, '--namespace-name', $EventHubNamespace, '--name', 'RootManageSharedAccessKey', '--query', 'primaryConnectionString', '-o', 'tsv')

    $endpointConn = "$ehConn;EntityPath=$EventHubName"
    Invoke-Az @('iot', 'hub', 'routing-endpoint', 'create', '--resource-group', $IoTHubResourceGroup, '--hub-name', $IoTHubName, '--endpoint-name', $IotHubEventHubEndpointName, '--endpoint-type', 'eventhub', '--endpoint-resource-group', $IoTHubEndpointResourceGroup, '--endpoint-subscription-id', $IoTHubEndpointSubscriptionId, '--connection-string', $endpointConn) | Out-Null
}

function Ensure-IotHubRoute {
    $found = Invoke-AzTsv @('iot', 'hub', 'route', 'list', '--resource-group', $IoTHubResourceGroup, '--hub-name', $IoTHubName, '--query', "[?name=='$IotHubRouteName'].name", '-o', 'tsv')

    if ($found) { return }

    $condition = "is_defined(\$connectionModuleId) AND (\$connectionModuleId = 'mqtt-bridge' OR \$connectionModuleId = 'edgeDecider')"
    Invoke-Az @('iot', 'hub', 'route', 'create', '--resource-group', $IoTHubResourceGroup, '--hub-name', $IoTHubName, '--name', $IotHubRouteName, '--source-type', 'DeviceMessages', '--condition', $condition, '--endpoint-name', $IotHubEventHubEndpointName, '--enabled', 'true') | Out-Null
}

function Assert-FinalState {
    if (-not $SkipEventHub) {
        $ns = Invoke-AzTsv @('eventhubs', 'namespace', 'list', '--resource-group', $ResourceGroup, '--query', "[?name=='$EventHubNamespace'].name", '-o', 'tsv')
        if (-not $ns) {
            throw "Validacion final fallida: no existe Event Hubs namespace '$EventHubNamespace' en '$ResourceGroup'."
        }

        $eh = Invoke-AzTsv @('eventhubs', 'eventhub', 'list', '--namespace-name', $EventHubNamespace, '--resource-group', $ResourceGroup, '--query', "[?name=='$EventHubName'].name", '-o', 'tsv')
        if (-not $eh) {
            throw "Validacion final fallida: no existe Event Hub '$EventHubName' en namespace '$EventHubNamespace'."
        }
    }

    if (-not $SkipStorage) {
        $sa = Invoke-AzTsv @('storage', 'account', 'list', '--resource-group', $ResourceGroup, '--query', "[?name=='$StorageAccountName'].name", '-o', 'tsv')
        if (-not $sa) {
            throw "Validacion final fallida: no existe Storage Account '$StorageAccountName' en '$ResourceGroup'."
        }

        $fs = Invoke-AzTsv @('storage', 'fs', 'list', '--account-name', $StorageAccountName, '--auth-mode', 'login', '--query', "[?name=='$DataLakeFileSystem'].name", '-o', 'tsv')
        if (-not $fs) {
            throw "Validacion final fallida: no existe filesystem '$DataLakeFileSystem' en '$StorageAccountName'."
        }
    }

    if (-not $SkipRoute) {
        $endpoint = Invoke-AzTsv @('iot', 'hub', 'routing-endpoint', 'list', '--hub-name', $IoTHubName, '--resource-group', $IoTHubResourceGroup, '--endpoint-type', 'eventhub', '--query', "[?name=='$IotHubEventHubEndpointName'].name", '-o', 'tsv')
        if (-not $endpoint) {
            throw "Validacion final fallida: no existe endpoint IoT Hub '$IotHubEventHubEndpointName'."
        }

        $route = Invoke-AzTsv @('iot', 'hub', 'route', 'list', '--hub-name', $IoTHubName, '--resource-group', $IoTHubResourceGroup, '--query', "[?name=='$IotHubRouteName'].name", '-o', 'tsv')
        if (-not $route) {
            throw "Validacion final fallida: no existe ruta IoT Hub '$IotHubRouteName'."
        }
    }
}

Write-Host "[1/7] Validando Azure CLI..."
$null = (Invoke-Az @('version') | Out-String)

Write-Host "[2/7] Seleccionando suscripcion..."
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

if (-not $IoTHubEndpointResourceGroup) {
    $IoTHubEndpointResourceGroup = $ResourceGroup
}

if (-not $IoTHubEndpointSubscriptionId) {
    $IoTHubEndpointSubscriptionId = $SubscriptionId
}

Write-Host "[3/7] Asegurando extension azure-iot..."
Ensure-AzureIotExtension

Write-Host "[4/7] Asegurando resource group..."
Ensure-ResourceGroup

if (-not $SkipEventHub) {
    Write-Host "[5/7] Asegurando Event Hubs namespace y hub..."
    Ensure-EventHubNamespace
    Ensure-EventHub
}
else {
    Write-Host "[5/7] SkipEventHub activo."
}

if (-not $SkipStorage) {
    Write-Host "[6/7] Asegurando ADLS Gen2 (storage + filesystem)..."
    Ensure-StorageAccount
    Ensure-DataLakeFileSystem
}
else {
    Write-Host "[6/7] SkipStorage activo."
}

if (-not $SkipRoute) {
    Write-Host "[7/7] Asegurando endpoint y ruta IoT Hub hacia Event Hubs..."
    Ensure-IotHubEventHubEndpoint
    Ensure-IotHubRoute
}
else {
    Write-Host "[7/7] SkipRoute activo."
}

Write-Host "[7.1/7] Validando estado final de recursos..."
Assert-FinalState

Write-Host ""
Write-Host "Provision base completada."
Write-Host "- Event Hub namespace: $EventHubNamespace"
Write-Host "- Event Hub: $EventHubName"
Write-Host "- ADLS account: $StorageAccountName"
Write-Host "- ADLS filesystem: $DataLakeFileSystem"
Write-Host "- IoT Hub endpoint: $IotHubEventHubEndpointName"
Write-Host "- IoT Hub route: $IotHubRouteName"
Write-Host ""
Write-Host "Siguiente paso recomendado:"
Write-Host "1) Crear Stream Analytics job con input Event Hub y output ADLS"
Write-Host "2) Aplicar query de deployment/stream-analytics/query.sql"
