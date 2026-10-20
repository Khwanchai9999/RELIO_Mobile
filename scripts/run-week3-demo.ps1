[CmdletBinding()]
param(
    [string]$DeviceSerial = 'YDVNW19B23003867'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}
if ($DeviceSerial -ne 'YDVNW19B23003867') {
    throw 'Week 3 source demo is restricted to the authorized Huawei device.'
}

$adbPath = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adbPath)) {
    throw 'Android platform-tools adb.exe was not found in the configured SDK path.'
}
$deviceState = & $adbPath -s $DeviceSerial get-state 2>$null
if ($LASTEXITCODE -ne 0 -or $deviceState -ne 'device') {
    throw 'Huawei is not authorized and ready in ADB; refusing to target another device.'
}

# โหลด QA config ที่ถูก ignore และอนุญาตเฉพาะ RELIO-QA โดยไม่พิมพ์ค่า secret
. (Join-Path $PSScriptRoot 'import-qa-local-env.ps1')
. (Join-Path $PSScriptRoot 'public-qa-config.ps1')
$updateConfig = Get-RelioPublicQaUpdateConfig
if ([string]$env:RELIO_SUPABASE_QA_URL -ne 'https://zeuiqspvqiplusiugcto.supabase.co' -or
    [string]::IsNullOrWhiteSpace($env:RELIO_SUPABASE_QA_ANON_KEY)) {
    throw 'QA runtime configuration did not resolve to the approved RELIO-QA project.'
}

$flutterArgs = @(
    'run', '--flavor', 'qa', '--device-id', $DeviceSerial,
    '--dart-define=RELIO_ENV=test',
    "--dart-define=RELIO_PUBLIC_UPDATE_MANIFEST_URL=$($updateConfig.ManifestUrl)",
    "--dart-define=RELIO_PUBLIC_UPDATE_OWNER=$($updateConfig.Owner)",
    "--dart-define=RELIO_PUBLIC_UPDATE_REPO=$($updateConfig.Repository)",
    "--dart-define=RELIO_PUBLIC_UPDATE_CHANNEL=$($updateConfig.Channel)",
    "--dart-define=SUPABASE_URL=$($env:RELIO_SUPABASE_QA_URL)",
    "--dart-define=SUPABASE_ANON_KEY=$($env:RELIO_SUPABASE_QA_ANON_KEY)"
)

& flutter @flutterArgs
if ($LASTEXITCODE -ne 0) {
    throw "flutter run failed with exit code $LASTEXITCODE."
}
