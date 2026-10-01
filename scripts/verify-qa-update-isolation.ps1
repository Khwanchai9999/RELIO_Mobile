[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$androidRoot = Join-Path $projectRoot 'android'
$gradle = Join-Path $androidRoot 'gradlew.bat'
$qaConfig = Join-Path $projectRoot 'android\app\src\qa\google-services.json'
$appGradle = Join-Path $projectRoot 'android\app\build.gradle.kts'
$settingsGradle = Join-Path $projectRoot 'android\settings.gradle.kts'
$mainManifest = Join-Path $projectRoot 'android\app\src\main\AndroidManifest.xml'
$qaManifest = Join-Path $projectRoot 'android\app\src\qa\AndroidManifest.xml'

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
if ((Get-Content -Raw -LiteralPath $qaManifest) -notmatch 'android\.permission\.REQUEST_INSTALL_PACKAGES' -or
    (Get-Content -Raw -LiteralPath $mainManifest) -match 'android\.permission\.REQUEST_INSTALL_PACKAGES') {
    throw 'REQUEST_INSTALL_PACKAGES must be declared by QA only, never by the shared manifest.'
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

$apkCandidates = @(
    @{ Flavor = 'qa'; Variant = 'debug'; Path = (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-debug.apk') },
    @{ Flavor = 'qa'; Variant = 'release'; Path = (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-release.apk') },
    @{ Flavor = 'prod'; Variant = 'debug'; Path = (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-prod-debug.apk') },
    @{ Flavor = 'prod'; Variant = 'release'; Path = (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-prod-release.apk') },
    @{ Flavor = 'dev'; Variant = 'debug'; Path = (Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-dev-debug.apk') }
)
$availableApks = @($apkCandidates | Where-Object { Test-Path -LiteralPath $_.Path })
if ($availableApks.Count -gt 0) {
    $aaptCommand = Get-Command aapt2 -ErrorAction SilentlyContinue
    $aapt2Path = if ($aaptCommand) { $aaptCommand.Source } else { $null }
    if (-not $aapt2Path) {
        $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
        $localProperties = Join-Path $androidRoot 'local.properties'
        if (Test-Path -LiteralPath $localProperties) {
            $sdkMatch = [regex]::Match((Get-Content -Raw -LiteralPath $localProperties), '(?m)^sdk\.dir=(.+)$')
            if ($sdkMatch.Success) { $sdkRoots += [regex]::Unescape($sdkMatch.Groups[1].Value.Trim()) }
        }
        foreach ($sdkRoot in ($sdkRoots | Where-Object { $_ } | Select-Object -Unique)) {
            $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Filter 'aapt2.exe' -File -Recurse -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -First 1
            if ($candidate) { $aapt2Path = $candidate.FullName; break }
        }
    }
    if (-not $aapt2Path) { throw 'aapt2 is required to verify permissions in existing flavor APKs.' }

    foreach ($apk in $availableApks) {
        $permissions = (& $aapt2Path dump permissions $apk.Path 2>&1) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "Could not inspect permissions for $($apk.Flavor) $($apk.Variant)." }
        $hasInstallPermission = $permissions -match 'android\.permission\.REQUEST_INSTALL_PACKAGES'
        if (($apk.Flavor -eq 'qa') -ne $hasInstallPermission) {
            throw "REQUEST_INSTALL_PACKAGES isolation failed in the $($apk.Flavor) $($apk.Variant) APK."
        }
    }
}

Write-Host 'QA contains the full App Distribution SDK and QA-only installer permission; PROD contains API-only support and no installer permission.'
