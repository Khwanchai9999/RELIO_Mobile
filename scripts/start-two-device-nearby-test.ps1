[CmdletBinding()]
param(
    [switch]$Stop
)

$ErrorActionPreference = 'Stop'
$devices = @(
    @{ Name = 'Huawei Y9s'; Serial = 'YDVNW19B23003867' },
    @{ Name = 'Realme'; Serial = 'c821a16d' }
)

function Get-AdbPath {
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $localPropertiesPath = Join-Path $PSScriptRoot '..\android\local.properties'
    if (Test-Path -LiteralPath $localPropertiesPath) {
        $sdkLine = Get-Content -LiteralPath $localPropertiesPath |
            Where-Object { $_ -match '^sdk\.dir=' } |
            Select-Object -First 1
        if ($sdkLine) {
            $sdkPath = $sdkLine.Substring('sdk.dir='.Length).Replace('\\', '\')
            $candidate = Join-Path $sdkPath 'platform-tools\adb.exe'
            if (Test-Path -LiteralPath $candidate) { return $candidate }
        }
    }

    throw 'adb.exe was not found on PATH or under android/local.properties sdk.dir.'
}

$adbPath = Get-AdbPath
$root = Join-Path $env:LOCALAPPDATA 'RELIO\diagnostics\two-device-nearby'

if ($Stop) {
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Host 'No RELIO two-device capture directory exists.'
        exit 0
    }
    $pidFiles = Get-ChildItem -LiteralPath $root -Filter 'capture-pids.txt' -Recurse -File
    foreach ($pidFile in $pidFiles) {
        foreach ($line in Get-Content -LiteralPath $pidFile.FullName) {
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

$connected = @(& $adbPath devices -l | Select-Object -Skip 1 | Where-Object { $_ -match '\S+\s+device\b' })
foreach ($device in $devices) {
    $deviceLine = $connected | Where-Object { $_ -match ('^' + [regex]::Escape($device.Serial) + '\s') } | Select-Object -First 1
    if (-not $deviceLine) { throw "$($device.Name) ($($device.Serial)) is not connected and authorized in ADB." }
}

$sessionDirectory = Join-Path $root (Get-Date -Format 'yyyyMMdd-HHmmss')
New-Item -ItemType Directory -Path $sessionDirectory -Force | Out-Null
$capturePids = @()

foreach ($device in $devices) {
    Write-Host "`n$($device.Name) [$($device.Serial)]"
    Write-Host "Android API: $(& $adbPath -s $device.Serial shell getprop ro.build.version.sdk)"
    Write-Host "Model: $(& $adbPath -s $device.Serial shell getprop ro.product.model)"
    $package = @(& $adbPath -s $device.Serial shell dumpsys package com.relio.relio_mobile.test)
    $versionCode = $package | Select-String 'versionCode=' | Select-Object -First 1
    $versionName = $package | Select-String 'versionName=' | Select-Object -First 1
    Write-Host "Installed QA package: $versionName; $versionCode"
    Write-Host 'Permission grants:'
    $package | Select-String 'android.permission.(ACCESS_FINE_LOCATION|ACCESS_COARSE_LOCATION|BLUETOOTH|BLUETOOTH_SCAN|BLUETOOTH_CONNECT|BLUETOOTH_ADVERTISE|NEARBY_WIFI_DEVICES): granted=' | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
    Write-Host "Bluetooth radio: $(& $adbPath -s $device.Serial shell settings get global bluetooth_on)"
    Write-Host "Wi-Fi radio: $(& $adbPath -s $device.Serial shell settings get global wifi_on)"
    Write-Host "Location mode: $(& $adbPath -s $device.Serial shell settings get secure location_mode)"

    & $adbPath -s $device.Serial logcat -c
    if ($LASTEXITCODE -ne 0) { throw "Could not clear old logcat on $($device.Name)." }
    $safeName = ($device.Name -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    $stdoutPath = Join-Path $sessionDirectory "$safeName.log"
    $stderrPath = Join-Path $sessionDirectory "$safeName-adb-error.log"
    $capture = Start-Process -FilePath $adbPath -ArgumentList @(
        '-s', $device.Serial, 'logcat', '-v', 'threadtime', '-s',
        'flutter:V', 'nearby_connections:V', 'NearbyConnections:V', 'GoogleApiManager:W'
    ) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    $capturePids += $capture.Id
    Write-Host "Capturing to $stdoutPath"
}

Set-Content -LiteralPath (Join-Path $sessionDirectory 'capture-pids.txt') -Value $capturePids
Write-Host "`nBoth captures are running. Diagnostics: $sessionDirectory"
Write-Host 'Now touch the phones: enable Bluetooth and Wi-Fi; on Android 10/11 also enable Location; open RELIO and tap Nearby on both.'
Write-Host 'After discovery, connect/accept, send one text, then test SOS on/off and Rescue on/off. Stop capture with: .\scripts\start-two-device-nearby-test.ps1 -Stop'
