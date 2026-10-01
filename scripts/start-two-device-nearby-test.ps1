[CmdletBinding()]
param(
    [switch]$Stop,
    [int[]]$DeviceIndex
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$localPropertiesPath = Join-Path $projectRoot 'android\local.properties'

function Get-AdbPath {
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath $localPropertiesPath) {
        $match = [regex]::Match((Get-Content -Raw -LiteralPath $localPropertiesPath), '(?m)^sdk\.dir=(.+)$')
        if ($match.Success) {
            $sdkPath = [regex]::Unescape($match.Groups[1].Value.Trim())
            $candidate = Join-Path $sdkPath 'platform-tools\adb.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }
    throw 'adb.exe was not found on PATH or under android/local.properties sdk.dir.'
}

function Invoke-AdbText {
    param([string[]]$Arguments)
    $output = & $adbPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { return '' }
    return ($output -join "`n").Trim()
}

function Get-DeviceSnapshot {
    param([string]$Serial, [int]$Index)
    $model = Invoke-AdbText @('-s', $Serial, 'shell', 'getprop', 'ro.product.model')
    $manufacturer = Invoke-AdbText @('-s', $Serial, 'shell', 'getprop', 'ro.product.manufacturer')
    $sdk = Invoke-AdbText @('-s', $Serial, 'shell', 'getprop', 'ro.build.version.sdk')
    $android = Invoke-AdbText @('-s', $Serial, 'shell', 'getprop', 'ro.build.version.release')
    $package = Invoke-AdbText @('-s', $Serial, 'shell', 'dumpsys', 'package', 'com.relio.relio_mobile.test')
    $installed = $package -match 'versionCode='
    $versionCode = [regex]::Match($package, 'versionCode=(\d+)').Groups[1].Value
    $versionName = [regex]::Match($package, 'versionName=([^\s]+)').Groups[1].Value
    $permissionMatches = [regex]::Matches($package, '(?m)^\s*(android\.permission\.(?:ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|BLUETOOTH|BLUETOOTH_SCAN|BLUETOOTH_CONNECT|BLUETOOTH_ADVERTISE|NEARBY_WIFI_DEVICES)):\s+granted=(true|false)')
    $permissions = @($permissionMatches | ForEach-Object { "$($_.Groups[1].Value)=$($_.Groups[2].Value)" })
    [pscustomobject]@{
        Index = $Index
        Serial = $Serial
        Manufacturer = if ($manufacturer) { $manufacturer } else { 'unknown' }
        Model = if ($model) { $model } else { 'unknown' }
        Android = if ($android) { $android } else { 'unknown' }
        Api = if ($sdk) { $sdk } else { 'unknown' }
        Installed = $installed
        Version = if ($installed) { "$versionName+$versionCode" } else { 'not installed' }
        Bluetooth = Invoke-AdbText @('-s', $Serial, 'shell', 'settings', 'get', 'global', 'bluetooth_on')
        WiFi = Invoke-AdbText @('-s', $Serial, 'shell', 'settings', 'get', 'global', 'wifi_on')
        Location = Invoke-AdbText @('-s', $Serial, 'shell', 'settings', 'get', 'secure', 'location_mode')
        Permissions = $permissions
    }
}

$adbPath = Get-AdbPath
$captureRoot = Join-Path $env:LOCALAPPDATA 'RELIO\diagnostics\two-device-nearby'
if ($Stop) {
    if (-not (Test-Path -LiteralPath $captureRoot)) { Write-Host 'No RELIO two-device capture directory exists.'; exit 0 }
    foreach ($pidFile in (Get-ChildItem -LiteralPath $captureRoot -Filter 'capture-pids.txt' -Recurse -File)) {
        foreach ($line in (Get-Content -LiteralPath $pidFile.FullName)) {
            $captureProcessId = 0
            if ([int]::TryParse($line, [ref]$captureProcessId)) {
                $captureProcess = Get-Process -Id $captureProcessId -ErrorAction SilentlyContinue
                if ($captureProcess -and $captureProcess.Path -eq $adbPath) {
                    Stop-Process -Id $captureProcessId
                    Write-Host "Stopped log capture process $captureProcessId."
                }
            }
        }
    }
    exit 0
}

$lines = @(& $adbPath devices -l | Select-Object -Skip 1 | Where-Object { $_ -match '^\S+\s+device\b' })
$snapshots = @()
for ($index = 0; $index -lt $lines.Count; $index++) {
    $serial = ($lines[$index] -split '\s+')[0]
    $snapshots += Get-DeviceSnapshot -Serial $serial -Index ($index + 1)
}
if ($snapshots.Count -eq 0) { Write-Host 'No authorized Android device is connected. Connect a device and run this helper again.'; exit 0 }

foreach ($device in $snapshots) {
    Write-Host "`nDEVICE $($device.Index)"
    Write-Host "Serial       : $($device.Serial)"
    Write-Host "Manufacturer : $($device.Manufacturer)"
    Write-Host "Model        : $($device.Model)"
    Write-Host "Android      : $($device.Android) / API $($device.Api)"
    Write-Host "RELIO        : $($device.Version)"
    Write-Host "Package      : com.relio.relio_mobile.test"
    Write-Host "Bluetooth    : $($device.Bluetooth)"
    Write-Host "Wi-Fi        : $($device.WiFi)"
    Write-Host "Location     : $($device.Location)"
    Write-Host "Permissions  : $(if ($device.Permissions.Count) { $device.Permissions -join ', ' } else { 'unavailable' })"
}
if ($snapshots.Count -eq 1) { Write-Host "`n1 device available; connect one more device to start two-device capture."; exit 0 }

if (-not $DeviceIndex) { $DeviceIndex = @(1, 2) }
if ($DeviceIndex.Count -ne 2 -or @($DeviceIndex | Where-Object { $_ -lt 1 -or $_ -gt $snapshots.Count }).Count -gt 0 -or $DeviceIndex[0] -eq $DeviceIndex[1]) {
    throw "Choose two different device indexes between 1 and $($snapshots.Count)."
}
$selected = @($snapshots | Where-Object { $_.Index -in $DeviceIndex })
$sessionDirectory = Join-Path $captureRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Path $sessionDirectory -Force | Out-Null
$capturePids = @()
foreach ($device in $selected) {
    $safeName = ($device.Serial -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    $stdoutPath = Join-Path $sessionDirectory "$safeName.log"
    $stderrPath = Join-Path $sessionDirectory "$safeName-adb-error.log"
    $capture = Start-Process -FilePath $adbPath -ArgumentList @(
        '-s', $device.Serial, 'logcat', '-T', '1', '-v', 'threadtime', '-s',
        'flutter:V', 'nearby_connections:V', 'NearbyConnections:V', 'GoogleApiManager:W'
    ) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $capturePids += $capture.Id
    Write-Host "Capturing DEVICE $($device.Index) to $stdoutPath"
}
Set-Content -LiteralPath (Join-Path $sessionDirectory 'capture-pids.txt') -Value $capturePids
Write-Host "`nBoth captures are running. Diagnostics: $sessionDirectory"
Write-Host 'Open RELIO on both phones, test discovery, connect, send text, then test SOS and Rescue. Stop capture with: .\scripts\start-two-device-nearby-test.ps1 -Stop'
