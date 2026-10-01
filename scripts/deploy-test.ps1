[CmdletBinding()]
param(
    [string]$FirebaseAppId,
    [string]$Testers,
    [string]$Groups,
    [string]$ReleaseNotesPath,
    [switch]$NoUpload
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$currentRoot = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
if ($currentRoot -ne $projectRoot) {
    throw "Run this command from the active workspace: $projectRoot"
}
. (Join-Path $PSScriptRoot 'public-qa-config.ps1')
$publicQaUpdateConfig = Get-RelioPublicQaUpdateConfig
if (-not $env:JAVA_HOME) {
    $androidStudioJava = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    if (Test-Path -LiteralPath $androidStudioJava) {
        $env:JAVA_HOME = Split-Path (Split-Path $androidStudioJava -Parent) -Parent
    }
}

function Invoke-QualityStep {
    param([string]$Label, [string]$Command, [scriptblock]$Action)
    Write-Host "`n$Label"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE. Deployment stopped."
    }
}

Write-Host 'RELIO Test deployment pipeline'
Write-Host 'Quality gate runs before any APK upload.'
& "$PSScriptRoot\preflight.ps1" -RequireTestSigning

$pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$version = ([regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')).Groups[1].Value
$versionParts = $version.Split('+', 2)
$versionName = $versionParts[0]
$buildNumber = $versionParts[1]
$qaConfigPath = Join-Path $projectRoot 'android\app\src\qa\google-services.json'
$qaPackageName = 'com.relio.relio_mobile.test'
if (-not (Test-Path -LiteralPath $qaConfigPath)) {
    throw "QA Firebase config was not found: $qaConfigPath"
}
# อ่าน App ID จากไฟล์ QA ที่ลงทะเบียนกับ Firebase จริง และเช็ก package ซ้ำก่อน deploy
# เพื่อกันส่ง APK ผิดโปรเจกต์หรือผิด application identity
$qaFirebaseConfig = Get-Content -Raw -LiteralPath $qaConfigPath | ConvertFrom-Json
$qaClient = @($qaFirebaseConfig.client | Where-Object {
        $_.client_info.android_client_info.package_name -eq $qaPackageName
    }) | Select-Object -First 1
if (-not $qaClient) {
    throw "QA Firebase config does not target $qaPackageName."
}
$qaProjectId = [string]$qaFirebaseConfig.project_info.project_id
$qaAppIdFromConfig = [string]$qaClient.client_info.mobilesdk_app_id
if (-not $qaProjectId -or $qaAppIdFromConfig -notmatch '^1:\d+:android:[A-Za-z0-9_-]+$') {
    throw 'QA Firebase config is missing a valid project ID or Android App ID.'
}
$providedAppId = if ($FirebaseAppId) { $FirebaseAppId } else { $env:FIREBASE_APP_ID }
if ($providedAppId -and $providedAppId -ne $qaAppIdFromConfig) {
    throw "FIREBASE_APP_ID must match the QA config App ID for $qaPackageName."
}
$resolvedFirebaseAppId = if ($providedAppId) { $providedAppId } else { $qaAppIdFromConfig }
$defines = @(
    "--dart-define=RELIO_ENV=test",
    "--dart-define=RELIO_VERSION=$versionName",
    "--dart-define=RELIO_BUILD=$buildNumber",
    "--dart-define=RELIO_PUBLIC_UPDATE_MANIFEST_URL=$($publicQaUpdateConfig.ManifestUrl)",
    "--dart-define=RELIO_PUBLIC_UPDATE_OWNER=$($publicQaUpdateConfig.Owner)",
    "--dart-define=RELIO_PUBLIC_UPDATE_REPO=$($publicQaUpdateConfig.Repository)",
    "--dart-define=RELIO_PUBLIC_UPDATE_CHANNEL=$($publicQaUpdateConfig.Channel)"
)

if (($versionName -eq '0.8.5' -and [int]$buildNumber -lt 11) -or
    ($versionName -eq '0.8.6' -and [int]$buildNumber -lt 13) -or
    ($versionName -eq '0.9.0' -and [int]$buildNumber -lt 22) -or
    $versionName -notin @('0.8.5', '0.8.6', '0.9.0')) {
    throw "TEST deployment requires 0.8.5+11, 0.8.6+13-or-newer, or 0.9.0+22-or-newer; found $version."
}

# ขั้นนี้ตั้งใจรัน quality gate ก่อน build และ upload
# ถ้า format, analyze หรือ test ไม่ผ่าน จะหยุดทันทีเพื่อไม่ปล่อย APK ที่มีปัญหา
Invoke-QualityStep 'กำลังตรวจ dart format...' 'dart format' {
    & dart format --output=none --set-exit-if-changed .
}
Invoke-QualityStep 'กำลังตรวจ flutter analyze...' 'flutter analyze' {
    & flutter analyze --no-pub
}
Invoke-QualityStep 'กำลังรัน flutter test...' 'flutter test' {
    & flutter test --no-pub
}
Invoke-QualityStep 'กำลังตรวจ QA/PROD Firebase SDK isolation...' 'verify-qa-update-isolation.ps1' {
    & "$PSScriptRoot\verify-qa-update-isolation.ps1"
}

Invoke-QualityStep 'กำลังสร้าง RELIO Test APK...' 'flutter build apk' {
    & flutter build apk --no-pub --flavor qa --release @defines
}

$builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-release.apk'
if (-not (Test-Path -LiteralPath $builtApk)) {
    throw "Expected TEST APK was not created: $builtApk"
}

$localPropertiesPath = Join-Path $projectRoot 'android\local.properties'
$localSdkRoot = $null
if (Test-Path -LiteralPath $localPropertiesPath) {
    $sdkMatch = [regex]::Match(
        (Get-Content -Raw -LiteralPath $localPropertiesPath),
        '(?m)^sdk\.dir=(.+)$'
    )
    if ($sdkMatch.Success) {
        $localSdkRoot = [regex]::Unescape($sdkMatch.Groups[1].Value.Trim())
    }
}
$sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME, $localSdkRoot) |
    Where-Object { $_ } |
    Select-Object -Unique

$aapt2Path = $null
$aapt2Command = Get-Command aapt2 -ErrorAction SilentlyContinue
if ($aapt2Command) { $aapt2Path = $aapt2Command.Source }
if (-not $aapt2Path) {
    foreach ($sdkRoot in $sdkRoots) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Filter 'aapt2.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { $aapt2Path = $candidate.FullName; break }
    }
}
if (-not $aapt2Path) {
    throw 'aapt2 was not found; QA APK package/version verification cannot continue.'
}
$badging = & $aapt2Path dump badging $builtApk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'aapt2 could not inspect the QA APK.' }
$packageLine = $badging | Select-String '^package:' | Select-Object -First 1
if (-not $packageLine -or $packageLine.Line -notmatch "name='com\.relio\.relio_mobile\.test'" -or
    $packageLine.Line -notmatch "versionCode='$buildNumber'" -or
    $packageLine.Line -notmatch "versionName='$versionName'") {
    throw "QA APK metadata did not match package com.relio.relio_mobile.test version $version."
}
Write-Host "Verified QA package, versionName, and versionCode: com.relio.relio_mobile.test $version"

$apksignerPath = $null
$apksignerCommand = Get-Command apksigner -ErrorAction SilentlyContinue
if ($apksignerCommand) { $apksignerPath = $apksignerCommand.Source }
if (-not $apksignerPath) {
    foreach ($sdkRoot in $sdkRoots) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Filter 'apksigner.bat' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { $apksignerPath = $candidate.FullName; break }
    }
}
if (-not $apksignerPath) { throw 'apksigner was not found; QA signing verification cannot continue.' }
& $apksignerPath verify $builtApk
if ($LASTEXITCODE -ne 0) { throw 'QA APK signature verification failed.' }

$keyPropertiesPath = Join-Path $projectRoot 'android\key.properties'
$keyProperties = Get-Content -Raw -LiteralPath $keyPropertiesPath
$keyAliasMatch = [regex]::Match($keyProperties, '(?m)^keyAlias=(.+)$')
$storePasswordMatch = [regex]::Match($keyProperties, '(?m)^storePassword=(.+)$')
$keytoolPath = $null
$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
if ($keytoolCommand) { $keytoolPath = $keytoolCommand.Source }
if (-not $keytoolPath -and $env:JAVA_HOME) {
    $javaKeytool = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
    if (Test-Path -LiteralPath $javaKeytool) { $keytoolPath = $javaKeytool }
}
if (-not $keyAliasMatch.Success -or -not $storePasswordMatch.Success -or -not $keytoolPath) {
    throw 'TEST signing metadata could not be verified without exposing credentials.'
}
$keystorePath = Join-Path $projectRoot 'android\relio-test.keystore'
$keystoreCertificate = & $keytoolPath -list -v -alias $keyAliasMatch.Groups[1].Value.Trim() -keystore $keystorePath -storepass $storePasswordMatch.Groups[1].Value.Trim() 2>$null
$apkCertificate = & $apksignerPath verify --print-certs $builtApk 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Could not read the QA APK certificate.' }
$expectedFingerprint = [regex]::Match(($keystoreCertificate -join "`n"), '(?i)SHA256:\s*([0-9A-F:]+)').Groups[1].Value
$actualFingerprint = [regex]::Match(($apkCertificate -join "`n"), '(?i)SHA-256 digest:\s*([0-9A-F:]+)').Groups[1].Value
if (-not $expectedFingerprint -or -not $actualFingerprint -or
    $expectedFingerprint.Replace(':', '').ToUpperInvariant() -ne
    $actualFingerprint.Replace(':', '').ToUpperInvariant()) {
    throw 'QA APK certificate does not match the preserved TEST keystore.'
}
Write-Host 'Verified QA APK signature matches the preserved TEST keystore.'

$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$artifactName = "relio-test-$version.apk"
$artifactPath = Join-Path $distRoot $artifactName
Copy-Item -LiteralPath $builtApk -Destination $artifactPath -Force

$notesSource = if ($ReleaseNotesPath) {
    [IO.Path]::GetFullPath($ReleaseNotesPath)
} else {
    Join-Path $projectRoot "release_notes\$versionName-build-$buildNumber.md"
}
if (-not (Test-Path -LiteralPath $notesSource) -and -not $ReleaseNotesPath) {
    $notesSource = Join-Path $projectRoot "release_notes\$versionName.md"
}
$notesPath = Join-Path $distRoot "relio-test-$version-release-notes.txt"
if (Test-Path -LiteralPath $notesSource) {
    Copy-Item -LiteralPath $notesSource -Destination $notesPath -Force
} else {
    @(
        "RELIO Test v$versionName (build $buildNumber)",
        '',
        'Automated quality gate passed. Manual Android smoke testing remains required.'
    ) | Set-Content -LiteralPath $notesPath -Encoding utf8
}

Write-Host "`nTEST APK: $artifactPath"
if ($NoUpload) {
    Write-Host 'Firebase upload skipped by -NoUpload.'
    exit 0
}

$appId = $resolvedFirebaseAppId
$groupsValue = if ($Groups) { $Groups } else { $env:FIREBASE_GROUPS }
$testersValue = if ($Testers) { $Testers } else { $env:FIREBASE_TESTERS }
if (-not $groupsValue -and -not $testersValue) {
    $groupsValue = 'relio-testers'
    # ใช้ group มาตรฐานเมื่อไม่ได้ระบุ เพื่อไม่ต้องคัดลอก App ID หรือ alias ซ้ำทุกครั้ง
    Write-Host 'Firebase tester group defaulted to relio-testers.'
}
if ($groupsValue -and $groupsValue -ne 'relio-testers') {
    throw 'Only the authorized Firebase tester group relio-testers may be used.'
}
$firebase = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebase) {
    Write-Host 'FIREBASE LIVE DISTRIBUTION — DEFERRED'
    Write-Host 'QA APK is ready. Install the official Firebase CLI and authenticate before upload.'
    exit 0
}
if ($appId -notmatch '^1:\d+:android:[A-Za-z0-9_-]+$') {
    throw 'FIREBASE_APP_ID has an invalid Firebase Android App ID format.'
}

# Firebase CLI may print account details; capture them so logs never expose identity
# or credential material while still failing before any upload when login is absent.
$env:FIREBASE_CLI_DISABLE_UPDATE_CHECK = '1'
$loginOutput = & $firebase.Source login:list 2>&1
if ($LASTEXITCODE -ne 0 -or ($loginOutput -join "`n") -match 'No authorized accounts') {
    throw 'Firebase CLI is not authenticated. Complete firebase login before live QA upload.'
}

$projectsJson = & $firebase.Source projects:list --json 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Firebase CLI could not list projects for the authenticated account.'
}
try {
    $projectsText = $projectsJson -join "`n"
    $projectsJsonStart = $projectsText.IndexOf('{')
    if ($projectsJsonStart -lt 0) { throw 'No JSON object found.' }
    $projectsResponse = $projectsText.Substring($projectsJsonStart) | ConvertFrom-Json
} catch {
    throw 'Firebase CLI returned an unreadable project list.'
}
$projectItems = if ($projectsResponse.result) { $projectsResponse.result } else { $projectsResponse }
$matchingProject = @($projectItems | Where-Object {
        $_.projectId -eq $qaProjectId
    }) | Select-Object -First 1
if (-not $matchingProject) {
    throw "Authenticated Firebase account cannot be proven to access QA project $qaProjectId."
}

if ($groupsValue) {
    $groupsJson = & $firebase.Source appdistribution:groups:list --project $qaProjectId --json 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Firebase App Distribution groups could not be listed for project $qaProjectId."
    }
    try {
        $groupsText = $groupsJson -join "`n"
        $groupsJsonStart = $groupsText.IndexOf('{')
        if ($groupsJsonStart -lt 0) { throw 'No JSON object found.' }
        $groupsResponse = $groupsText.Substring($groupsJsonStart) | ConvertFrom-Json
    } catch {
        throw 'Firebase CLI returned an unreadable App Distribution group list.'
    }
    $groupItems = if ($groupsResponse.result.groups) {
        $groupsResponse.result.groups
    } elseif ($groupsResponse.groups) {
        $groupsResponse.groups
    } else {
        $groupsResponse.result
    }
    $matchingGroup = @($groupItems | Where-Object {
            $_.name -and $_.name.Split('/')[-1] -eq $groupsValue
        }) | Select-Object -First 1
    if (-not $matchingGroup) {
        Write-Host 'Creating the empty authorized tester group RELIO Testers...'
        & $firebase.Source appdistribution:groups:create 'RELIO Testers' $groupsValue --project $qaProjectId
        if ($LASTEXITCODE -ne 0) {
            throw 'Firebase App Distribution tester group creation failed.'
        }
        throw 'The relio-testers group is empty. Add an explicitly approved tester before upload.'
    }
    if ([int]$matchingGroup.testerCount -lt 1) {
        throw 'The relio-testers group is empty. Add an explicitly approved tester before upload.'
    }
}

$uploadArgs = @(
    'appdistribution:distribute',
    $artifactPath,
    '--app', $appId,
    '--release-notes-file', $notesPath
)
if ($groupsValue) { $uploadArgs += @('--groups', $groupsValue) }
if ($testersValue) { $uploadArgs += @('--testers', $testersValue) }

Write-Host 'Uploading approved TEST build to Firebase App Distribution...'
& $firebase.Source @uploadArgs
if ($LASTEXITCODE -ne 0) {
    throw "Firebase App Distribution upload failed with exit code $LASTEXITCODE."
}
Write-Host 'FIREBASE LIVE DISTRIBUTION — VERIFIED'
Write-Host 'Firebase CLI returned release links above when available (firebase_console_uri/testing_uri/binary_download_uri).'
