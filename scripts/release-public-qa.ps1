[CmdletBinding()]
param(
    [switch]$NoDeploy
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$currentRoot = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
$projectId = 'relio-17dc0'
$expectedVersion = '0.8.6+12'
$expectedPackage = 'com.relio.relio_mobile.test'
$approvedBaseUrl = 'https://relio-17dc0.web.app/qa/'

if ($currentRoot -ne $projectRoot) {
    throw "Run this command from the active workspace: $projectRoot"
}

function Invoke-CheckedStep {
    param(
        [string]$Label,
        [scriptblock]$Action
    )
    Write-Host "`n$Label"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE. Public deployment stopped."
    }
}

function ConvertFrom-FirebaseJson {
    param([object[]]$Lines)
    $text = $Lines -join "`n"
    $start = $text.IndexOf('{')
    if ($start -lt 0) { throw 'Firebase CLI did not return a JSON object.' }
    return $text.Substring($start) | ConvertFrom-Json
}

function Get-Aapt2 {
    $command = Get-Command aapt2 -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $localProperties = Join-Path $projectRoot 'android\local.properties'
    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if (Test-Path -LiteralPath $localProperties) {
        $match = [regex]::Match(
            (Get-Content -Raw -LiteralPath $localProperties),
            '(?m)^sdk\.dir=(.+)$'
        )
        if ($match.Success) { $sdkRoots += [regex]::Unescape($match.Groups[1].Value.Trim()) }
    }
    foreach ($sdkRoot in ($sdkRoots | Where-Object { $_ } | Select-Object -Unique)) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Filter 'aapt2.exe' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw 'aapt2 was not found; package verification cannot continue.'
}

function Get-ApkSigner {
    $command = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $localProperties = Join-Path $projectRoot 'android\local.properties'
    $sdkRoots = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if (Test-Path -LiteralPath $localProperties) {
        $match = [regex]::Match(
            (Get-Content -Raw -LiteralPath $localProperties),
            '(?m)^sdk\.dir=(.+)$'
        )
        if ($match.Success) { $sdkRoots += [regex]::Unescape($match.Groups[1].Value.Trim()) }
    }
    foreach ($sdkRoot in ($sdkRoots | Where-Object { $_ } | Select-Object -Unique)) {
        $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Filter 'apksigner.bat' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw 'apksigner was not found; signing verification cannot continue.'
}

Write-Host 'RELIO public QA release pipeline v0.8.6+12'
& "$PSScriptRoot\preflight.ps1" -RequireTestSigning

$pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$version = ([regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')).Groups[1].Value
if ($version -ne $expectedVersion) {
    throw "Public QA release requires $expectedVersion; found $version."
}
$versionParts = $version.Split('+', 2)
$versionName = $versionParts[0]
$buildNumber = [int]$versionParts[1]
$defines = @(
    '--dart-define=RELIO_ENV=test',
    "--dart-define=RELIO_VERSION=$versionName",
    "--dart-define=RELIO_BUILD=$buildNumber",
    "--dart-define=RELIO_PUBLIC_UPDATE_BASE_URL=$approvedBaseUrl"
)

$qaConfig = Join-Path $projectRoot 'android\app\src\qa\google-services.json'
$config = Get-Content -Raw -LiteralPath $qaConfig | ConvertFrom-Json
$qaClient = @($config.client | Where-Object {
        $_.client_info.android_client_info.package_name -eq $expectedPackage
    }) | Select-Object -First 1
if (-not $qaClient -or $config.project_info.project_id -ne $projectId) {
    throw 'QA Firebase configuration does not match the approved project/package.'
}

Invoke-CheckedStep 'Checking dart format...' {
    & dart format --output=none --set-exit-if-changed .
}
Invoke-CheckedStep 'Running flutter analyze...' {
    & flutter analyze --no-pub
}
Invoke-CheckedStep 'Running flutter test...' {
    & flutter test --no-pub
}
Invoke-CheckedStep 'Checking QA/PROD update isolation...' {
    & "$PSScriptRoot\verify-qa-update-isolation.ps1"
}
Invoke-CheckedStep 'Building signed QA release APK...' {
    & flutter build apk --no-pub --flavor qa --release @defines
}

$builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-release.apk'
if (-not (Test-Path -LiteralPath $builtApk)) { throw "QA APK was not created: $builtApk" }
$aapt2 = Get-Aapt2
$badging = & $aapt2 dump badging $builtApk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'aapt2 could not inspect the QA APK.' }
$packageLine = $badging | Select-String '^package:' | Select-Object -First 1
if (-not $packageLine -or
    $packageLine.Line -notmatch "name='$expectedPackage'" -or
    $packageLine.Line -notmatch "versionCode='$buildNumber'" -or
    $packageLine.Line -notmatch "versionName='$versionName'") {
    throw 'QA APK package/version metadata did not match the public release.'
}

$apksigner = Get-ApkSigner
& $apksigner verify $builtApk
if ($LASTEXITCODE -ne 0) { throw 'QA APK signature verification failed.' }
$certificateOutput = & $apksigner verify --print-certs $builtApk 2>$null
if ($LASTEXITCODE -ne 0) { throw 'QA APK certificate could not be read.' }
$signingFingerprint = [regex]::Match(
    ($certificateOutput -join "`n"),
    '(?i)SHA-256 digest:\s*([0-9A-F:]+)'
).Groups[1].Value.Replace(':', '').ToLowerInvariant()
if ($signingFingerprint -notmatch '^[0-9a-f]{64}$') {
    throw 'QA APK signing fingerprint is invalid.'
}

$hostingRoot = Join-Path $projectRoot 'public_update'
$qaHostingRoot = Join-Path $hostingRoot 'qa'
New-Item -ItemType Directory -Path $qaHostingRoot -Force | Out-Null
Get-ChildItem -LiteralPath $qaHostingRoot -Filter '*.apk' -File -ErrorAction SilentlyContinue | Remove-Item -Force
$artifactName = "relio-test-$version.apk"
$hostingApk = Join-Path $qaHostingRoot $artifactName
Copy-Item -LiteralPath $builtApk -Destination $hostingApk -Force
$fileInfo = Get-Item -LiteralPath $hostingApk
$sha256 = (Get-FileHash -LiteralPath $hostingApk -Algorithm SHA256).Hash.ToLowerInvariant()
$apkUrl = "$approvedBaseUrl$artifactName"

$manifest = [ordered]@{
    schemaVersion = 1
    channel = 'qa-public'
    packageName = $expectedPackage
    versionName = $versionName
    versionCode = $buildNumber
    apkUrl = $apkUrl
    sha256 = $sha256
    sizeBytes = [int64]$fileInfo.Length
    signingCertSha256 = $signingFingerprint
    publishedAt = [DateTime]::UtcNow.ToString('o')
    releaseNotes = @(
        'เพิ่มช่องทางอัปเดต RELIO Test แบบสาธารณะผ่าน HTTPS',
        'ตรวจสอบ SHA-256, package name, versionCode และลายเซ็น QA ก่อนติดตั้ง',
        'ให้ Android Package Installer ขอการยืนยันจากผู้ใช้ทุกครั้ง'
    )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $qaHostingRoot 'latest.json') -Encoding utf8
$template = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'firebase_hosting\qa\index.template.html')
$page = $template.Replace('__VERSION_NAME__', $versionName).
    Replace('__BUILD_NUMBER__', [string]$buildNumber).
    Replace('__APK_URL__', $apkUrl).
    Replace('__SHA256__', $sha256).
    Replace('__SIZE_MB__', ('{0:N1}' -f ($fileInfo.Length / 1MB)))
$page | Set-Content -LiteralPath (Join-Path $qaHostingRoot 'index.html') -Encoding utf8

$firebase = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebase) { throw 'Firebase CLI is required for public Hosting deployment.' }
$env:FIREBASE_CLI_DISABLE_UPDATE_CHECK = '1'
$loginOutput = & $firebase.Source login:list 2>&1
if ($LASTEXITCODE -ne 0 -or ($loginOutput -join "`n") -match 'No authorized accounts') {
    throw 'Firebase CLI is not authenticated.'
}
$projects = ConvertFrom-FirebaseJson (& $firebase.Source projects:list --json 2>$null)
$projectItems = if ($projects.result) { @($projects.result) } else { @($projects) }
if (-not @($projectItems | Where-Object { $_.projectId -eq $projectId })) {
    throw "Authenticated Firebase account cannot access $projectId."
}
$sites = ConvertFrom-FirebaseJson (& $firebase.Source hosting:sites:list --project $projectId --json 2>$null)
$siteItems = if ($sites.result.sites) { @($sites.result.sites) } elseif ($sites.sites) { @($sites.sites) } else { @() }
$site = $siteItems | Where-Object { $_.name -eq "projects/$projectId/sites/$projectId" } | Select-Object -First 1
if (-not $site) { throw "Firebase Hosting site $projectId was not found." }
$publicBaseUrl = [string]$site.defaultUrl
if (-not $publicBaseUrl) { throw 'Firebase Hosting did not return a default URL.' }
$approvedUri = [Uri]$approvedBaseUrl
$expectedPublicBaseUrl = "$($approvedUri.Scheme)://$($approvedUri.Host)"
if ($publicBaseUrl.TrimEnd('/') -ne $expectedPublicBaseUrl) {
    throw "Unexpected Hosting URL: $publicBaseUrl"
}

if (-not $NoDeploy) {
    Invoke-CheckedStep 'Deploying only Firebase Hosting...' {
        & $firebase.Source deploy --only "hosting:$projectId" --project $projectId --non-interactive
    }
} else {
    Write-Host 'Firebase Hosting deployment skipped by -NoDeploy.'
}

if ($NoDeploy) {
    Write-Host "Prepared hosting directory: $qaHostingRoot"
    Write-Host "Manifest SHA-256: $sha256"
    exit 0
}

$manifestUrl = "$publicBaseUrl/qa/latest.json"
$remoteApkUrl = "$publicBaseUrl/qa/$artifactName"
$remoteManifestResponse = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing
if ($remoteManifestResponse.StatusCode -ne 200) { throw 'Public latest.json verification failed.' }
$remoteManifest = $remoteManifestResponse.Content | ConvertFrom-Json
if ($remoteManifest.packageName -ne $expectedPackage -or
    [int]$remoteManifest.versionCode -ne $buildNumber -or
    $remoteManifest.sha256 -ne $sha256 -or
    $remoteManifest.apkUrl -ne $remoteApkUrl) {
    throw 'Remote public manifest values do not match Build 12.'
}
$remotePage = Invoke-WebRequest -Uri "$publicBaseUrl/qa/" -UseBasicParsing
if ($remotePage.StatusCode -ne 200 -or $remotePage.Content -notmatch 'data-relio-public-qa-channel="true"') {
    throw 'Public download page verification failed.'
}
$remoteApkPath = Join-Path ([IO.Path]::GetTempPath()) "relio-public-qa-$buildNumber.apk"
try {
    Invoke-WebRequest -Uri $remoteApkUrl -OutFile $remoteApkPath -UseBasicParsing
    $remoteHash = (Get-FileHash -LiteralPath $remoteApkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($remoteHash -ne $sha256) { throw 'Remote APK SHA-256 does not match latest.json.' }
} finally {
    if (Test-Path -LiteralPath $remoteApkPath) { Remove-Item -LiteralPath $remoteApkPath -Force }
}

Write-Host "PUBLIC QA URL: $publicBaseUrl/qa/"
Write-Host "PUBLIC MANIFEST: $manifestUrl"
Write-Host "PUBLIC APK: $remoteApkUrl"
Write-Host "BUILD 12 SHA-256: $sha256"
Write-Host "BUILD 12 SIZE BYTES: $($fileInfo.Length)"
Write-Host "BUILD 12 SIGNING SHA-256: $signingFingerprint"
Write-Host 'PUBLIC QA HOSTING DEPLOYMENT — VERIFIED'
