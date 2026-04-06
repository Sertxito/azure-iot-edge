Param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Location,

    [Parameter(Mandatory = $true)]
    [string]$JobName,

    [Parameter(Mandatory = $true)]
    [string]$EventHubNamespace,

    [Parameter(Mandatory = $true)]
    [string]$EventHubName,

    [string]$EventHubPolicyName = "RootManageSharedAccessKey",
    [string]$EventHubConsumerGroup = '$Default',

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$FileSystemName,

    [string]$RawOutputName = "outputraw",
    [string]$AggOutputName = "outputagg1m",
    [string]$InputName = "input",
    [string]$TransformationName = "main-transformation",

    [string]$QueryFilePath = "deployment/stream-analytics/query.sql",

    [int]$StreamingUnits = 1,
    [switch]$StartJob
)

$ErrorActionPreference = "Stop"

function Invoke-Az {
    param([string[]]$AzArgs)
    $result = & az @AzArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($AzArgs -join ' ')"
    }
    return $result
}

function Invoke-AzTsv {
    param([string[]]$AzArgs)
    $result = & az @AzArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($AzArgs -join ' ')"
    }
    return ($result | Out-String).Trim()
}

function New-TempJsonFile {
    param([string]$Json)

    $tmp = [System.IO.Path]::GetTempFileName()
    $jsonPath = [System.IO.Path]::ChangeExtension($tmp, ".json")
    Move-Item -Path $tmp -Destination $jsonPath -Force
    Set-Content -Path $jsonPath -Value $Json -Encoding UTF8
    return $jsonPath
}

function Get-ExistingTransformationName {
    param(
        [string]$Rg,
        [string]$Job
    )

    $fullNames = Invoke-AzTsv @(
        'resource', 'list',
        '--resource-group', $Rg,
        '--resource-type', 'Microsoft.StreamAnalytics/streamingjobs/transformations',
        '--query', "[?starts_with(name, '$Job/')].name",
        '-o', 'tsv'
    )

    if (-not $fullNames) {
        return ""
    }

    $first = ($fullNames -split "`r?`n" | Where-Object { $_ } | Select-Object -First 1)
    if (-not $first) {
        return ""
    }

    if ($first -like "$Job/*") {
        return ($first -split '/', 2)[1]
    }

    return ""
}

function Set-JobState {
    $existing = Invoke-AzTsv @('stream-analytics', 'job', 'list', '--resource-group', $ResourceGroup, '--query', "[?name=='$JobName'].name", '-o', 'tsv')
    if ($existing) { return }

    # Keep create args minimal for cross-version compatibility of the
    # stream-analytics extension in Azure CLI.
    Invoke-Az @(
        'stream-analytics', 'job', 'create',
        '--resource-group', $ResourceGroup,
        '--name', $JobName,
        '--location', $Location
    ) | Out-Null
}

function Set-InputState {
    $existing = Invoke-AzTsv @('stream-analytics', 'input', 'list', '--resource-group', $ResourceGroup, '--job-name', $JobName, '--query', "[?name=='$InputName'].name", '-o', 'tsv')
    if ($existing) { return }

    $ehKey = Invoke-AzTsv @(
        'eventhubs', 'namespace', 'authorization-rule', 'keys', 'list',
        '--resource-group', $ResourceGroup,
        '--namespace-name', $EventHubNamespace,
        '--name', $EventHubPolicyName,
        '--query', 'primaryKey', '-o', 'tsv'
    )

    if (-not $ehKey) {
        throw "No se pudo obtener la primaryKey de Event Hubs policy '$EventHubPolicyName'."
    }

    $properties = @{
        type = 'Stream'
        datasource = @{
            type = 'Microsoft.ServiceBus/EventHub'
            properties = @{
                serviceBusNamespace = $EventHubNamespace
                sharedAccessPolicyName = $EventHubPolicyName
                sharedAccessPolicyKey = $ehKey
                eventHubName = $EventHubName
                consumerGroupName = $EventHubConsumerGroup
            }
        }
        serialization = @{
            type = 'Json'
            properties = @{
                encoding = 'UTF8'
            }
        }
    } | ConvertTo-Json -Compress -Depth 15

    $propertiesPath = New-TempJsonFile -Json $properties
    try {
        Invoke-Az @(
            'stream-analytics', 'input', 'create',
            '--resource-group', $ResourceGroup,
            '--job-name', $JobName,
            '--input-name', $InputName,
            '--properties', "@$propertiesPath"
        ) | Out-Null
    }
    finally {
        if (Test-Path $propertiesPath) {
            Remove-Item -Path $propertiesPath -Force
        }
    }
}

function Set-OutputState {
    param(
        [string]$OutputName,
        [string]$PathPattern
    )

    $existing = Invoke-AzTsv @('stream-analytics', 'output', 'list', '--resource-group', $ResourceGroup, '--job-name', $JobName, '--query', "[?name=='$OutputName'].name", '-o', 'tsv')
    if ($existing) { return }

    $saKey = Invoke-AzTsv @('storage', 'account', 'keys', 'list', '--resource-group', $ResourceGroup, '--account-name', $StorageAccountName, '--query', '[0].value', '-o', 'tsv')
    if (-not $saKey) {
        throw "No se pudo obtener account key de '$StorageAccountName'."
    }

    $dataSource = @{
        type = 'Microsoft.Storage/Blob'
        properties = @{
            storageAccounts = @(
                @{
                    accountName = $StorageAccountName
                    accountKey  = $saKey
                }
            )
            container = $FileSystemName
            pathPattern = $PathPattern
            dateFormat = 'yyyy/MM/dd'
            timeFormat = 'HH'
        }
    } | ConvertTo-Json -Compress -Depth 10

    $serialization = @{
        type = 'Json'
        properties = @{
            encoding = 'UTF8'
            format   = 'LineSeparated'
        }
    } | ConvertTo-Json -Compress -Depth 10

    $dataSourcePath = New-TempJsonFile -Json $dataSource
    $serializationPath = New-TempJsonFile -Json $serialization
    try {
        Invoke-Az @(
            'stream-analytics', 'output', 'create',
            '--resource-group', $ResourceGroup,
            '--job-name', $JobName,
            '--name', $OutputName,
            '--datasource', "@$dataSourcePath",
            '--serialization', "@$serializationPath"
        ) | Out-Null
    }
    finally {
        if (Test-Path $dataSourcePath) {
            Remove-Item -Path $dataSourcePath -Force
        }
        if (Test-Path $serializationPath) {
            Remove-Item -Path $serializationPath -Force
        }
    }
}

function Set-TransformationState {
    if (-not (Test-Path $QueryFilePath)) {
        throw "No existe query file: $QueryFilePath"
    }

    $query = Get-Content -Path $QueryFilePath -Raw
    if (-not $query.Trim()) {
        throw "El query file esta vacio: $QueryFilePath"
    }

    # Some Azure CLI/extension builds truncate multiline --saql arguments.
    # Normalize to a single line to keep the full query intact.
    $queryForCli = ($query -replace "`r?`n", ' ').Trim()

    # ASA allows only one transformation per job. If a different transformation
    # already exists, update that one instead of trying to create a second.
    $resolvedTransformationName = $TransformationName
    $exists = $true
    try {
        Invoke-Az @('stream-analytics', 'transformation', 'show', '--resource-group', $ResourceGroup, '--job-name', $JobName, '--name', $TransformationName) | Out-Null
    }
    catch {
        $exists = $false
    }

    if (-not $exists) {
        $currentName = Invoke-AzTsv @('stream-analytics', 'job', 'show', '--resource-group', $ResourceGroup, '--name', $JobName, '--query', 'transformation.name', '-o', 'tsv')
        if (-not $currentName) {
            $currentName = Invoke-AzTsv @('stream-analytics', 'job', 'show', '--resource-group', $ResourceGroup, '--name', $JobName, '--query', 'properties.transformation.name', '-o', 'tsv')
        }
        if (-not $currentName) {
            $currentName = Invoke-AzTsv @('resource', 'show', '--resource-group', $ResourceGroup, '--name', $JobName, '--resource-type', 'Microsoft.StreamAnalytics/streamingjobs', '--query', 'properties.transformation.name', '-o', 'tsv')
        }
        if (-not $currentName) {
            $currentName = Get-ExistingTransformationName -Rg $ResourceGroup -Job $JobName
        }
        if ($currentName) {
            $resolvedTransformationName = $currentName
            $exists = $true
        }
    }

    if ($exists) {
        Invoke-Az @(
            'stream-analytics', 'transformation', 'update',
            '--resource-group', $ResourceGroup,
            '--job-name', $JobName,
            '--name', $resolvedTransformationName,
            '--saql', $queryForCli,
            '--streaming-units', "$StreamingUnits"
        ) | Out-Null
    }
    else {
        Write-Host "No se detecto transformacion existente. Creando '$resolvedTransformationName'..."
        try {
            Invoke-Az @(
                'stream-analytics', 'transformation', 'create',
                '--resource-group', $ResourceGroup,
                '--job-name', $JobName,
                '--name', $resolvedTransformationName,
                '--saql', $queryForCli,
                '--streaming-units', "$StreamingUnits"
            ) | Out-Null
        }
        catch {
            $fallbackName = Get-ExistingTransformationName -Rg $ResourceGroup -Job $JobName
            if (-not $fallbackName) {
                throw
            }

            Write-Host "Detectada transformacion existente '$fallbackName'. Actualizando..."
            Invoke-Az @(
                'stream-analytics', 'transformation', 'update',
                '--resource-group', $ResourceGroup,
                '--job-name', $JobName,
                '--name', $fallbackName,
                '--saql', $queryForCli,
                '--streaming-units', "$StreamingUnits"
            ) | Out-Null
        }
    }
}

Write-Host "[1/7] Validando Azure CLI..."
Invoke-Az @('version') | Out-Null

Write-Host "[2/7] Seleccionando suscripcion..."
Invoke-Az @('account', 'set', '--subscription', $SubscriptionId) | Out-Null

Write-Host "[3/7] Asegurando job Stream Analytics..."
Set-JobState

Write-Host "[4/7] Asegurando input Event Hubs..."
Set-InputState

Write-Host "[5/7] Asegurando outputs ADLS..."
Set-OutputState -OutputName $RawOutputName -PathPattern 'raw/{date}/{time}'
Set-OutputState -OutputName $AggOutputName -PathPattern 'aggregates/{date}/{time}'

Write-Host "[6/7] Aplicando transformation/query..."
Set-TransformationState

if ($StartJob) {
    Write-Host "[7/7] Arrancando job..."
    Invoke-Az @('stream-analytics', 'job', 'start', '--resource-group', $ResourceGroup, '--name', $JobName, '--output-start-mode', 'JobStartTime') | Out-Null
}
else {
    Write-Host "[7/7] StartJob no indicado. Job creado/configurado pero no arrancado."
}

Write-Host ""
Write-Host "Stream Analytics configurado."
Write-Host "- Job: $JobName"
Write-Host "- Input: $InputName (EventHub: $EventHubNamespace/$EventHubName)"
Write-Host "- Outputs: $RawOutputName, $AggOutputName (Storage: $StorageAccountName / $FileSystemName)"
Write-Host "- Query: $QueryFilePath"
