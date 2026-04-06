Param(
    [string]$EnvFile = ".env.local",
    [string]$OutHeader = "arduinos/secrets.local.h"
)

if (-not (Test-Path $EnvFile)) {
    Write-Error "No existe $EnvFile. Crea primero .env.local a partir de .env.local.example"
    exit 1
}

$kv = @{}
Get-Content $EnvFile | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith("#") -or -not $line.Contains("=")) { return }
    $parts = $line.Split("=", 2)
    $k = $parts[0].Trim()
    $v = $parts[1].Trim().Trim('"').Trim("'")
    if ($k) { $kv[$k] = $v }
}

$wifiSsid = $kv["WIFI_SSID"]
$wifiPass = $kv["WIFI_PASS"]
$mqttHost = $kv["MQTT_HOST"]

if (-not $wifiSsid -or -not $wifiPass -or -not $mqttHost) {
    Write-Error "Faltan WIFI_SSID, WIFI_PASS o MQTT_HOST en $EnvFile"
    exit 1
}

$header = @"
// Auto-generado desde $EnvFile
#ifndef WIFI_SSID_VALUE
#define WIFI_SSID_VALUE "$wifiSsid"
#endif

#ifndef WIFI_PASS_VALUE
#define WIFI_PASS_VALUE "$wifiPass"
#endif

#ifndef MQTT_HOST_VALUE
#define MQTT_HOST_VALUE "$mqttHost"
#endif
"@

$dir = Split-Path -Parent $OutHeader
if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir | Out-Null
}

Set-Content -Path $OutHeader -Value $header -Encoding UTF8
Write-Host "Generado: $OutHeader"
