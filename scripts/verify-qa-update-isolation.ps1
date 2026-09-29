[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$androidRoot = Join-Path $projectRoot 'android'
$gradle = Join-Path $androidRoot 'gradlew.bat'
$qaConfig = Join-Path $projectRoot 'android\app\src\qa\google-services.json'
$appGradle = Join-Path $projectRoot 'android\app\build.gradle.kts'
$settingsGradle = Join-Path $projectRoot 'android\settings.gradle.kts'

if (-not (Test-Path -LiteralPath $gradle)) {
    throw "Gradle wrapper was not found: $gradle"
}
if (-not $env:JAVA_HOME) {
    $androidStudioJava = 'C:\Program Files\Android\Android Studio\jbr\bin\java.exe'
    if (Test-Path -LiteralPath $androidStudioJava) {
        $env:JAVA_HOME = Split-Path (Split-Path $androidStudioJava -Parent) -Parent
    }
}
if (-not $env:JAVA_HOME -and -not (Get-Command java -ErrorAction SilentlyContinue)) {
    throw 'Java was not found. Configure JAVA_HOME or install Android Studio.'
}
if (-not (Test-Path -LiteralPath $qaConfig)) {
    throw "QA Firebase config was not found: $qaConfig"
}
if ((Get-Content -Raw -LiteralPath $appGradle) -notmatch 'com\.google\.gms\.google-services') {
    throw 'The app module does not apply the Google Services Gradle plugin.'
}
if ((Get-Content -Raw -LiteralPath $settingsGradle) -notmatch 'com\.google\.gms\.google-services') {
    throw 'The Android settings file does not declare the Google Services Gradle plugin.'
}

$qaFirebaseConfig = Get-Content -Raw -LiteralPath $qaConfig | ConvertFrom-Json
$qaPackageNames = @($qaFirebaseConfig.client | ForEach-Object {
        $_.client_info.android_client_info.package_name
    })
if ($qaPackageNames -notcontains 'com.relio.relio_mobile.test') {
    throw 'QA google-services.json does not target com.relio.relio_mobile.test.'
}

function Get-ConfigurationDependencies {
    param([string]$Configuration)

    Push-Location $androidRoot
    try {
        $output = & $gradle ':app:dependencies' "--configuration=$Configuration" '--no-daemon' '--console=plain' 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Gradle dependency inspection failed for $Configuration with exit code $LASTEXITCODE."
        }
        return ($output -join "`n")
    } finally {
        Pop-Location
    }
}

Write-Host 'Checking Firebase App Distribution variant isolation...'
$qaDependencies = Get-ConfigurationDependencies 'qaReleaseRuntimeClasspath'
$prodDependencies = Get-ConfigurationDependencies 'prodReleaseRuntimeClasspath'

if ($qaDependencies -notmatch 'com\.google\.firebase:firebase-appdistribution:') {
    throw 'QA runtime classpath does not contain the App Distribution SDK.'
}
if ($prodDependencies -match 'com\.google\.firebase:firebase-appdistribution:') {
    throw 'PROD runtime classpath contains the full App Distribution SDK.'
}

Write-Host 'QA contains the full App Distribution SDK; PROD contains API-only support only.'
