[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$androidRoot = Join-Path $projectRoot 'android'
$gradle = Join-Path $androidRoot 'gradlew.bat'

if (-not (Test-Path -LiteralPath $gradle)) {
    throw "Gradle wrapper was not found: $gradle"
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

if ($qaDependencies -notmatch 'firebase-appdistribution') {
    throw 'QA runtime classpath does not contain the App Distribution SDK.'
}
if ($prodDependencies -match 'firebase-appdistribution(?!-api)') {
    throw 'PROD runtime classpath contains the full App Distribution SDK.'
}

Write-Host 'QA contains the full App Distribution SDK; PROD contains API-only support only.'
