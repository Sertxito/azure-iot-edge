Param(
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$IoTHubName,

    [Parameter(Mandatory = $true)]
    [string]$DeviceId,

    [Parameter(Mandatory = $true)]
    [string]$AcrName,

    [string]$Tag = "",
    [string]$BridgeRepo = "",
    [string]$DeciderRepo = "",
    [string]$DeploymentId = "",
    [int]$DeploymentPriority = 10,
    [ValidateSet("auto", "linux/amd64", "linux/arm64")]
    [string]$ImagePlatform = "auto",
    [string]$MqttBroker = "",
    [int]$MqttPort = 1883,
    [switch]$BridgeUseHostNetwork,
    [switch]$DeciderUseHostNetwork,
    [switch]$UseHostNetwork,

    [switch]$SkipBuild,
    [switch]$SkipApply
)

$ErrorActionPreference = "Stop"

function Invoke-AzJson {
    param([string]$Command)
    $raw = Invoke-Expression $Command
    if (-not $raw) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-RepoFromImage {
    param([string]$Image)
    if (-not $Image) { return $null }
    if ($Image -match '^[^/]+/(.+):[^:]+$') {
        return $matches[1]
    }
    return $null
}

if (-not $Tag) {
    $Tag = Get-Date -Format "yyyyMMdd-HHmmss"
}

if (-not $DeploymentId) {
    $DeploymentId = ("{0}-images-deployment" -f $DeviceId.ToLower())
}

# Platform auto-detection based on device id conventions.
if ($ImagePlatform -eq "auto") {
    if ($DeviceId -match '(?i)rasp|pi|arm') {
        $ImagePlatform = "linux/arm64"
    }
    else {
        $ImagePlatform = "linux/amd64"
    }
}

$root = Split-Path -Parent $PSScriptRoot
$contentDir = Join-Path $root "deployment"
if (-not (Test-Path $contentDir)) {
    New-Item -ItemType Directory -Path $contentDir | Out-Null
}

$contentPath = Join-Path $contentDir ("modules-content-{0}.json" -f $Tag)

Write-Host "[1/7] Validando Azure CLI..."
$null = (az version | Out-String)

Write-Host "[2/7] Seleccionando suscripcion..."
az account set --subscription $SubscriptionId

Write-Host "[3/7] Asegurando extension azure-iot..."
$extensions = Invoke-AzJson "az extension list --output json"
if (-not ($extensions | Where-Object { $_.name -eq "azure-iot" })) {
    az extension add --name azure-iot --yes | Out-Null
}

Write-Host "[3.1/7] Detectando repositorios de imagen..."
$existingDeployment = az iot edge deployment show --hub-name $IoTHubName --deployment-id $DeploymentId --output json 2>$null
if ($LASTEXITCODE -eq 0 -and $existingDeployment) {
    $depObj = $existingDeployment | ConvertFrom-Json
    $mods = $depObj.content.modulesContent.'$edgeAgent'.'properties.desired'.modules

    if (-not $BridgeRepo) {
        $BridgeRepo = Get-RepoFromImage $mods.'mqtt-bridge'.settings.image
    }
    if (-not $DeciderRepo) {
        $DeciderRepo = Get-RepoFromImage $mods.edgeDecider.settings.image
    }
}

if (-not $BridgeRepo) { $BridgeRepo = "mqtt-bridge" }
if (-not $DeciderRepo) { $DeciderRepo = "edge-decider" }

Write-Host "  - Plataforma objetivo: $ImagePlatform"
Write-Host "  - Bridge repo: $BridgeRepo"
Write-Host "  - Decider repo: $DeciderRepo"

$bridgeHostNetworkEnabled = $UseHostNetwork.IsPresent -or $BridgeUseHostNetwork.IsPresent
$deciderHostNetworkEnabled = $UseHostNetwork.IsPresent -or $DeciderUseHostNetwork.IsPresent

if (-not $MqttBroker) {
    if ($bridgeHostNetworkEnabled) {
        $MqttBroker = "localhost"
    }
    else {
        # Sensible default when bridge is not on host network.
        $MqttBroker = "host.docker.internal"
    }
}

Write-Host ("  - MQTT broker bridge: {0}:{1}" -f $MqttBroker, $MqttPort)
Write-Host "  - Bridge host network: $bridgeHostNetworkEnabled"
Write-Host "  - Decider host network: $deciderHostNetworkEnabled"

Write-Host "[4/7] Recuperando credenciales ACR (admin)..."
$acr = Invoke-AzJson "az acr show --name $AcrName --resource-group $ResourceGroup --output json"
$loginServer = $acr.loginServer
$cred = Invoke-AzJson "az acr credential show --name $AcrName --resource-group $ResourceGroup --output json"
$acrUser = $cred.username
$acrPass = $cred.passwords[0].value

if (-not $SkipBuild) {
    Write-Host "[5/7] Build imagen mqtt-bridge:$Tag ($ImagePlatform)..."
    az acr build --registry $AcrName --image "$BridgeRepo`:$Tag" --platform $ImagePlatform --file "bridge/mqtt/Dockerfile" "bridge/mqtt"

    Write-Host "[6/7] Build imagen edge-decider:$Tag ($ImagePlatform)..."
    az acr build --registry $AcrName --image "$DeciderRepo`:$Tag" --platform $ImagePlatform --file "Dockerfile" "."
}
else {
    Write-Host "[5/7] SkipBuild activo, no se generan imagenes."
}

Write-Host "[7/7] Generando modules content..."
$bridgeHostConfig = @{ RestartPolicy = @{ Name = "always" } }
if ($bridgeHostNetworkEnabled) {
    $bridgeHostConfig["NetworkMode"] = "host"
}
else {
    # Linux Docker compatibility for host.docker.internal.
    $bridgeHostConfig["ExtraHosts"] = @("host.docker.internal:host-gateway")
}
$bridgeCreateOptions = @{ HostConfig = $bridgeHostConfig } | ConvertTo-Json -Compress

$deciderHostConfig = @{ RestartPolicy = @{ Name = "always" } }
if ($deciderHostNetworkEnabled) {
    $deciderHostConfig["NetworkMode"] = "host"
}
$deciderCreateOptions = @{ HostConfig = $deciderHostConfig } | ConvertTo-Json -Compress

$modulesContent = @{
    modulesContent = @{
        '$edgeAgent' = @{
            'properties.desired' = @{
                schemaVersion = "1.1"
                runtime = @{
                    type = "docker"
                    settings = @{
                        minDockerVersion = "v1.25"
                        loggingOptions = ""
                        registryCredentials = @{
                            acr = @{
                                address = $loginServer
                                username = $acrUser
                                password = $acrPass
                            }
                        }
                    }
                }
                systemModules = @{
                    edgeAgent = @{
                        type = "docker"
                        settings = @{
                            image = "mcr.microsoft.com/azureiotedge-agent:1.5"
                            createOptions = "{}"
                        }
                    }
                    edgeHub = @{
                        type = "docker"
                        status = "running"
                        restartPolicy = "always"
                        settings = @{
                            image = "mcr.microsoft.com/azureiotedge-hub:1.5"
                            createOptions = "{}"
                        }
                    }
                }
                modules = @{
                    'mqtt-bridge' = @{
                        version = "1.0"
                        type = "docker"
                        status = "running"
                        restartPolicy = "always"
                        env = @{
                            MQTT_BROKER = @{ value = $MqttBroker }
                            MQTT_PORT = @{ value = "$MqttPort" }
                        }
                        settings = @{
                            image = "$loginServer/$BridgeRepo`:$Tag"
                            createOptions = $bridgeCreateOptions
                        }
                    }
                    edgeDecider = @{
                        version = "1.0"
                        type = "docker"
                        status = "running"
                        restartPolicy = "always"
                        settings = @{
                            image = "$loginServer/$DeciderRepo`:$Tag"
                            createOptions = $deciderCreateOptions
                        }
                    }
                }
            }
        }
        '$edgeHub' = @{
            'properties.desired' = @{
                schemaVersion = "1.1"
                routes = @{
                    BridgeToDecider = "FROM /messages/modules/mqtt-bridge/outputs/telemetry INTO BrokeredEndpoint(`"/modules/edgeDecider/inputs/input1`")"
                    BridgeToUpstream = "FROM /messages/modules/mqtt-bridge/outputs/telemetry INTO `$upstream"
                    DeciderToUpstream = "FROM /messages/modules/edgeDecider/outputs/* INTO `$upstream"
                }
                storeAndForwardConfiguration = @{
                    timeToLiveSecs = 7200
                }
            }
        }
    }
}

$modulesContent | ConvertTo-Json -Depth 30 | Set-Content -Path $contentPath -Encoding UTF8
Write-Host "Contenido generado en: $contentPath"

if (-not $SkipApply) {
    Write-Host "Aplicando deployment automatico (modo blue/green) para device $DeviceId..."
    $targetCondition = "deviceId = '$DeviceId'"

    $existing = az iot edge deployment list --hub-name $IoTHubName --query "[?id=='$DeploymentId'].id" -o tsv
    $activeDeploymentId = $DeploymentId
    $activePriority = $DeploymentPriority

    if ($existing) {
        # Evita dejar al device sin manifest: crea uno nuevo y solo despues elimina el anterior.
        $activeDeploymentId = "{0}-{1}" -f $DeploymentId, $Tag
        $activePriority = $DeploymentPriority + 1
        Write-Host "  - Deployment existente detectado: $DeploymentId"
        Write-Host "  - Creando nuevo deployment: $activeDeploymentId (priority=$activePriority)"

        az iot edge deployment create --hub-name $IoTHubName --deployment-id $activeDeploymentId --content $contentPath --target-condition $targetCondition --priority $activePriority --output none
        if ($LASTEXITCODE -ne 0) { throw "No se pudo crear deployment blue/green: $activeDeploymentId" }

        Write-Host "  - Eliminando deployment anterior: $DeploymentId"
        az iot edge deployment delete --hub-name $IoTHubName --deployment-id $DeploymentId --output none
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "No se pudo eliminar deployment anterior: $DeploymentId. Puedes retirarlo manualmente."
        }
    }
    else {
        Write-Host "  - Creando deployment inicial: $activeDeploymentId (priority=$activePriority)"
        az iot edge deployment create --hub-name $IoTHubName --deployment-id $activeDeploymentId --content $contentPath --target-condition $targetCondition --priority $activePriority --output none
        if ($LASTEXITCODE -ne 0) { throw "No se pudo crear deployment: $activeDeploymentId" }
    }

    Write-Host "Deployment aplicado: $activeDeploymentId"
}
else {
    Write-Host "SkipApply activo, no se aplica deployment."
}

Write-Host ""
Write-Host "Siguiente validacion en el edge:"
Write-Host "  iotedge list"
Write-Host "  iotedge logs mqtt-bridge --tail 100"
Write-Host "  iotedge logs edgeDecider --tail 100"
Write-Host ""
Write-Host "Tag desplegado: $Tag"
