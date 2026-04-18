param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$StorageAccountName,

  [Parameter(Mandatory = $false)]
  [string]$ContainerName = "iot-historical",

  [Parameter(Mandatory = $false)]
  [string]$Prefix = "aggregates/",

  [Parameter(Mandatory = $false)]
  [int]$SasHours = 24,

  [Parameter(Mandatory = $false)]
  [string[]]$AllowedOrigins = @("*"),

  [Parameter(Mandatory = $false)]
  [switch]$SkipConfigUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-AzCli {
  $null = az version --output none 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Azure CLI no disponible o no responde. Instala/actualiza Azure CLI y ejecuta az login."
  }
}

function Ensure-Subscription([string]$SubId) {
  az account set --subscription $SubId --only-show-errors | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "No se pudo seleccionar la suscripcion '$SubId'. Revisa permisos y az login."
  }
}

function Configure-Cors([string]$AccountName, [string[]]$Origins) {
  $originCsv = ($Origins -join ",")

  az storage cors add `
    --account-name $AccountName `
    --services b `
    --methods GET HEAD OPTIONS `
    --origins $originCsv `
    --allowed-headers "*" `
    --exposed-headers "*" `
    --max-age 3600 `
    --only-show-errors | Out-Null

  if ($LASTEXITCODE -ne 0) {
    throw "Error configurando CORS en la cuenta '$AccountName'."
  }
}

function New-ContainerSas([string]$AccountName, [string]$Container, [int]$Hours) {
  $expiry = (Get-Date).ToUniversalTime().AddHours($Hours).ToString("yyyy-MM-ddTHH:mmZ")

  $sas = az storage container generate-sas `
    --as-user `
    --auth-mode login `
    --account-name $AccountName `
    --name $Container `
    --permissions rl `
    --expiry $expiry `
    --https-only `
    --only-show-errors `
    --output tsv

  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sas)) {
    throw "No se pudo generar SAS para el contenedor '$Container'."
  }

  return $sas.Trim()
}

function Update-BlobConfig([string]$ConfigPath, [string]$AccountName, [string]$Container, [string]$PrefixPath, [string]$SasToken) {
  if (-not (Test-Path $ConfigPath)) {
    throw "No existe el archivo de configuracion: $ConfigPath"
  }

  $raw = Get-Content -Raw -Path $ConfigPath

  $raw = [regex]::Replace($raw, 'enabled:\s*(true|false)', 'enabled: true')
  $raw = [regex]::Replace($raw, 'baseUrl:\s*"[^"]*"', ('baseUrl: "https://{0}.blob.core.windows.net"' -f $AccountName))
  $raw = [regex]::Replace($raw, 'container:\s*"[^"]*"', ('container: "{0}"' -f $Container))
  $raw = [regex]::Replace($raw, 'prefix:\s*"[^"]*"', ('prefix: "{0}"' -f $PrefixPath))
  $raw = [regex]::Replace($raw, 'sasToken:\s*"[^"]*"', ('sasToken: "{0}"' -f $SasToken))
  $raw = [regex]::Replace($raw, 'maxBlobs:\s*\d+', 'maxBlobs: 12')
  if ($raw -match 'refreshMs:\s*\d+') {
    $raw = [regex]::Replace($raw, 'refreshMs:\s*\d+', 'refreshMs: 45000')
  } else {
    $raw = $raw -replace 'maxBlobs:\s*12', "maxBlobs: 12,`r`n  refreshMs: 45000"
  }

  Set-Content -Path $ConfigPath -Value $raw -Encoding UTF8
}

Assert-AzCli
Ensure-Subscription -SubId $SubscriptionId

Write-Host "[1/3] Configurando CORS para Blob..." -ForegroundColor Cyan
Configure-Cors -AccountName $StorageAccountName -Origins $AllowedOrigins

Write-Host "[2/3] Generando SAS de lectura/listado..." -ForegroundColor Cyan
$sasToken = New-ContainerSas -AccountName $StorageAccountName -Container $ContainerName -Hours $SasHours

if (-not $SkipConfigUpdate) {
  Write-Host "[3/3] Actualizando docs/blob-config.js..." -ForegroundColor Cyan
  $configPath = Join-Path (Split-Path $PSScriptRoot -Parent) "docs/blob-config.js"
  Update-BlobConfig -ConfigPath $configPath -AccountName $StorageAccountName -Container $ContainerName -PrefixPath $Prefix -SasToken $sasToken
} else {
  Write-Host "[3/3] Skip de actualizacion de docs/blob-config.js solicitado." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Completado." -ForegroundColor Green
Write-Host "SAS generado (copia de respaldo):" -ForegroundColor Gray
Write-Host $sasToken
Write-Host ""
Write-Host "Abre docs/ayuntamiento-landing.html y recarga la pagina." -ForegroundColor Gray
