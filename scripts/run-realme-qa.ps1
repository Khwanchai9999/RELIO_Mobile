[CmdletBinding()]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Serial, [switch]$NoLaunch, [switch]$BuildOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location $projectRoot
try {
    . (Join-Path $PSScriptRoot 'import-qa-local-env.ps1')
    . (Join-Path $PSScriptRoot 'public-qa-config.ps1')
    $config = Get-RelioPublicQaUpdateConfig
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\sdk'
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    $signer = Join-Path $sdk 'build-tools\36.0.0\apksigner.bat'
    $env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
    $devices = & $adb devices
    if (-not ($devices -match "^$([regex]::Escape($Serial))\s+device$")) { throw 'Authorized target device is unavailable.' }
    $versionLine = Get-Content -LiteralPath 'pubspec.yaml' | Where-Object { $_ -match '^version:\s*(\S+)\+(\d+)\s*$' } | Select-Object -First 1
    if ($versionLine -notmatch '^version:\s*(\S+)\+(\d+)\s*$') { throw 'Project version is unavailable.' }
    $versionName = $Matches[1]
    $buildNumber = $Matches[2]
    $defines = @(
        '--dart-define=RELIO_ENV=test', "--dart-define=RELIO_VERSION=$versionName", "--dart-define=RELIO_BUILD=$buildNumber",
        "--dart-define=RELIO_PUBLIC_UPDATE_MANIFEST_URL=$($config.ManifestUrl)",
        "--dart-define=RELIO_PUBLIC_UPDATE_OWNER=$($config.Owner)",
        "--dart-define=RELIO_PUBLIC_UPDATE_REPO=$($config.Repository)",
        "--dart-define=RELIO_PUBLIC_UPDATE_CHANNEL=$($config.Channel)",
        "--dart-define=SUPABASE_URL=$env:RELIO_SUPABASE_QA_URL",
        "--dart-define=SUPABASE_ANON_KEY=$env:RELIO_SUPABASE_QA_ANON_KEY"
    )
    & flutter build apk --debug --flavor qa --no-pub @defines
    if ($LASTEXITCODE -ne 0) { throw 'QA debug build failed.' }
    # QA Debug บน Realme ใช้ Android debug certificate เดิม ไม่ใช่ QA Release key
    # เพราะติดตั้งแบบ -r ได้เฉพาะเมื่อ signer ตรงกับแอปที่มีอยู่
    $binary = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-debug.apk'
    $certificate = & $signer verify --print-certs $binary
    if ($LASTEXITCODE -ne 0) { throw 'QA debug APK signature verification failed.' }
    $builtFingerprint = [regex]::Match(($certificate -join "`n"), '(?i)Signer #1 certificate SHA-256 digest:\s*([0-9A-F]+)').Groups[1].Value
    if (-not $builtFingerprint) { throw 'QA debug APK signer fingerprint is unavailable.' }
    Write-Host "Verified Gradle QA Debug signer: $builtFingerprint"
    if ($BuildOnly) { return }

    $installedPaths = & $adb -s $Serial shell pm path 'com.relio.relio_mobile.test'
    $installedBase = [regex]::Match(($installedPaths -join "`n"), '(?m)^package:(.+/base\.apk)\s*$').Groups[1].Value.Trim()
    if (-not $installedBase) { throw 'Existing QA installation was not found; this script only performs data-preserving updates.' }

    $installedApk = Join-Path $env:TEMP ("relio-installed-qa-debug-$([guid]::NewGuid().ToString('N')).apk")
    try {
        & $adb -s $Serial pull $installedBase $installedApk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not safely inspect the installed QA APK signer.' }
        $installedCertificate = & $signer verify --print-certs $installedApk
        if ($LASTEXITCODE -ne 0) { throw 'Installed QA APK signature verification failed.' }
        $installedFingerprint = [regex]::Match(($installedCertificate -join "`n"), '(?i)Signer #1 certificate SHA-256 digest:\s*([0-9A-F]+)').Groups[1].Value
        if (-not $installedFingerprint -or $builtFingerprint -ne $installedFingerprint) {
            throw 'QA debug signer does not match the installed app. No installation attempted.'
        }
        Write-Host 'Installed and candidate QA Debug signers match.'
        & $adb -s $Serial install -r $binary
        if ($LASTEXITCODE -ne 0) { throw 'Data-preserving QA installation failed. No uninstall attempted.' }
    } finally {
        if (Test-Path -LiteralPath $installedApk) { Remove-Item -LiteralPath $installedApk -Force }
    }
    if ($NoLaunch) { return }
    & flutter run -d $Serial --debug --flavor qa --no-pub --use-application-binary $binary @defines
} finally {
    Pop-Location
}
