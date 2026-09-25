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
$defines = @(
    "--dart-define=RELIO_ENV=test",
    "--dart-define=RELIO_VERSION=$versionName",
    "--dart-define=RELIO_BUILD=$buildNumber"
)

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

Invoke-QualityStep 'กำลังสร้าง RELIO Test APK...' 'flutter build apk' {
    & flutter build apk --no-pub --flavor qa --release @defines
}

$builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-release.apk'
if (-not (Test-Path -LiteralPath $builtApk)) {
    throw "Expected TEST APK was not created: $builtApk"
}

$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$artifactName = "relio-test-$version.apk"
$artifactPath = Join-Path $distRoot $artifactName
Copy-Item -LiteralPath $builtApk -Destination $artifactPath -Force

$notesSource = if ($ReleaseNotesPath) {
    [IO.Path]::GetFullPath($ReleaseNotesPath)
} else {
    Join-Path $projectRoot "release_notes\$versionName.md"
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

$appId = if ($FirebaseAppId) { $FirebaseAppId } else { $env:FIREBASE_APP_ID }
$groupsValue = if ($Groups) { $Groups } else { $env:FIREBASE_GROUPS }
$testersValue = if ($Testers) { $Testers } else { $env:FIREBASE_TESTERS }
$firebase = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebase -or -not $appId -or (-not $groupsValue -and -not $testersValue)) {
    Write-Host 'FIREBASE LIVE DISTRIBUTION — DEFERRED'
    Write-Host 'Set up Firebase CLI authentication, FIREBASE_APP_ID, and FIREBASE_GROUPS or FIREBASE_TESTERS to upload.'
    exit 0
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
