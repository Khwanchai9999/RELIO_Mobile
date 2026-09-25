[CmdletBinding()]
param(
    [switch]$RequireTestSigning,
    [switch]$RequireFirebase,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$currentRoot = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')

if ($currentRoot -ne $projectRoot) {
    throw "Run this command from the active workspace: $projectRoot"
}

foreach ($tool in @('dart', 'flutter')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool was not found on PATH: $tool"
    }
}

$javaPath = $null
$javaCommand = Get-Command java -ErrorAction SilentlyContinue
if ($javaCommand) {
    $javaPath = $javaCommand.Source
}
if (-not $javaPath -and $env:JAVA_HOME) {
    $javaHomeJava = Join-Path $env:JAVA_HOME 'bin\java.exe'
    if (Test-Path -LiteralPath $javaHomeJava) {
        $javaPath = $javaHomeJava
    }
}
if (-not $javaPath) {
    $androidStudioJava = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    if (Test-Path -LiteralPath $androidStudioJava) {
        $javaPath = $androidStudioJava
    }
}
if (-not $javaPath) {
    throw 'Required tool was not found. Install Java or configure JAVA_HOME.'
}
if (-not $env:JAVA_HOME) {
    $env:JAVA_HOME = Split-Path (Split-Path $javaPath -Parent) -Parent
}

$pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')
if (-not $versionMatch.Success) {
    throw 'Could not read version from pubspec.yaml.'
}
$version = $versionMatch.Groups[1].Value
$versionParts = $version.Split('+', 2)
if (($versionParts.Count -ne 2) -or ($versionParts[1] -as [int] -eq $null)) {
    throw "Version must include a numeric build number: $version"
}

$appGradle = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'android\app\build.gradle.kts')
if ($appGradle -notmatch 'com\.relio\.relio_mobile') {
    throw 'Production application ID was not found in android/app/build.gradle.kts.'
}
if ($appGradle -notmatch 'applicationIdSuffix\s*=\s*"\.test"') {
    throw 'The TEST flavor application ID suffix is not configured.'
}

$keyPropertiesPath = Join-Path $projectRoot 'android\key.properties'
$keystorePath = Join-Path $projectRoot 'android\relio-test.keystore'
if ($RequireTestSigning) {
    if (-not (Test-Path -LiteralPath $keyPropertiesPath)) {
        throw 'android/key.properties is missing. Run scripts/setup-test-signing.ps1.'
    }
    if (-not (Test-Path -LiteralPath $keystorePath)) {
        throw 'android/relio-test.keystore is missing. Restore the backed-up TEST key.'
    }
    $keyProperties = Get-Content -Raw -LiteralPath $keyPropertiesPath
    if ($keyProperties -match 'CHANGE_ME') {
        throw 'android/key.properties still contains placeholder credentials.'
    }
}

$firebase = Get-Command firebase -ErrorAction SilentlyContinue
$firebaseAppId = $env:FIREBASE_APP_ID
$firebaseTargets = $env:FIREBASE_GROUPS
if (-not $firebaseTargets) { $firebaseTargets = $env:FIREBASE_TESTERS }
if ($RequireFirebase -and (-not $firebase -or -not $firebaseAppId -or -not $firebaseTargets)) {
    throw 'Firebase upload requires the CLI, FIREBASE_APP_ID, and FIREBASE_GROUPS or FIREBASE_TESTERS.'
}

if (-not $Quiet) {
    Write-Host "Workspace: $projectRoot"
    Write-Host "Version: $version"
    Write-Host "Production ID: com.relio.relio_mobile"
    Write-Host "TEST ID: com.relio.relio_mobile.test"
    Write-Host "Firebase CLI: $(if ($firebase) { 'available' } else { 'not configured' })"
}
