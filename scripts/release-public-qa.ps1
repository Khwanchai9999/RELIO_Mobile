[CmdletBinding()]
param(
    [switch]$NoDeploy,
    [switch]$NoUpload,
    [switch]$DryRun,
    [switch]$ReuseExistingArtifact,
    [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
if ($env:RELIO_QA_PUBLISH_INTERNAL -ne '1') {
    & (Join-Path $PSScriptRoot 'publish-qa.ps1') @PSBoundParameters
    return
}
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$validator = Join-Path $projectRoot 'tool\validate_public_qa_manifest.dart'
$currentRoot = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
. (Join-Path $PSScriptRoot 'public-qa-config.ps1')
$publicQaUpdateConfig = Get-RelioPublicQaUpdateConfig
$projectId = $publicQaUpdateConfig.FirebaseProjectId
$expectedPackage = $publicQaUpdateConfig.PackageName
$githubRepositoryName = $publicQaUpdateConfig.Repository
$expectedQaAppId = '1:789862464099:android:a26ab040a4fdbe1a899656'

if ($currentRoot -ne $projectRoot) {
    throw "Run this command from the active workspace: $projectRoot"
}
if ($NoUpload -and -not $NoDeploy) {
    throw '-NoUpload requires -NoDeploy so Hosting cannot publish a manifest for an unuploaded APK.'
}

function Invoke-CheckedStep {
    param(
        [string]$Label,
        [scriptblock]$Action
    )
    Write-Host "`n$Label"
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed with exit code $LASTEXITCODE. Public release stopped."
    }
}

function ConvertFrom-CliJson {
    param([object[]]$Lines)
    $text = $Lines -join "`n"
    $start = $text.IndexOf('{')
    if ($start -lt 0) { throw 'CLI did not return a JSON object.' }
    return $text.Substring($start) | ConvertFrom-Json
}

function Invoke-FirebaseCli {
    param([string[]]$Arguments)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $firebase.Source @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) { throw "Firebase CLI command failed: firebase $($Arguments -join ' ')." }
    return ,$output
}

function Get-SdkTool {
    param(
        [string]$CommandName,
        [string]$FileName,
        [string]$FailureMessage
    )
    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
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
        $candidate = Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'build-tools') -Filter $FileName -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw $FailureMessage
}

function Get-KeytoolPath {
    $command = Get-Command keytool -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME 'bin\keytool.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'keytool was not found; the preserved QA signing identity cannot be verified.'
}

function Get-ApkMetadata {
    param(
        [string]$ApkPath,
        [string]$Aapt2Path,
        [string]$ApkSignerPath
    )
    $badging = & $Aapt2Path dump badging $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "aapt2 could not inspect $ApkPath." }
    $packageLine = $badging | Select-String '^package:' | Select-Object -First 1
    if (-not $packageLine) { throw "APK metadata was missing from $ApkPath." }
    $packageMatch = [regex]::Match($packageLine.Line, "name='([^']+)'")
    $versionNameMatch = [regex]::Match($packageLine.Line, "versionName='([^']+)'")
    $versionCodeMatch = [regex]::Match($packageLine.Line, "versionCode='([^']+)'")
    if (-not $packageMatch.Success -or -not $versionNameMatch.Success -or -not $versionCodeMatch.Success) {
        throw "APK package/version metadata was incomplete: $ApkPath"
    }
    $null = & $ApkSignerPath verify $ApkPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed: $ApkPath" }
    $certificateOutput = & $ApkSignerPath verify --print-certs $ApkPath 2>$null
    if ($LASTEXITCODE -ne 0) { throw "APK certificate could not be read: $ApkPath" }
    $fingerprint = [regex]::Match(
        ($certificateOutput -join "`n"),
        '(?i)SHA-256 digest:\s*([0-9A-F:]+)'
    ).Groups[1].Value.Replace(':', '').ToLowerInvariant()
    if ($fingerprint -notmatch '^[0-9a-f]{64}$') {
        throw "APK signing fingerprint is invalid: $ApkPath"
    }
    return [pscustomobject]@{
        PackageName = $packageMatch.Groups[1].Value
        VersionName = $versionNameMatch.Groups[1].Value
        VersionCode = [int]$versionCodeMatch.Groups[1].Value
        SigningFingerprint = $fingerprint
    }
}

function Get-ReleaseApiObject {
    param([string]$Repository, [string]$Tag)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # gh uses stderr for expected HTTP 404 responses; keep that status
        # inspectable in Windows PowerShell 5.1 instead of terminating early.
        $ErrorActionPreference = 'Continue'
        $output = & $gh.Source api "repos/$Repository/releases/tags/$Tag" 2>&1
        $apiExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($apiExitCode -ne 0) {
        if (($output -join "`n") -match 'Not Found|404') { return $null }
        throw "Could not inspect GitHub release $Tag."
    }
    return (($output -join "`n") | ConvertFrom-Json)
}

function Test-RemoteApk {
    param(
        [string]$Url,
        [string]$ExpectedOwner,
        [string]$ExpectedHash,
        [int64]$ExpectedSize,
        [string]$ExpectedPackage,
        [string]$ExpectedVersionName,
        [int]$ExpectedVersionCode,
        [string]$ExpectedSigner,
        [string]$Aapt2Path,
        [string]$ApkSignerPath
    )
    $expectedAssetPattern = '^https://github\.com/' + [regex]::Escape($ExpectedOwner) + '/RELIO-Android-Updates/releases/download/[^/]+/relio-test-' +
        [regex]::Escape($ExpectedVersionName) + '(?:\+|%2[Bb])' + $ExpectedVersionCode + '\.apk$'
    if ($Url -notmatch $expectedAssetPattern) {
        throw "GitHub asset URL is not an exact approved release URL: $Url"
    }
    $downloadPath = Join-Path ([IO.Path]::GetTempPath()) "relio-public-qa-$PID.apk"
    try {
        Invoke-WebRequest -Uri $Url -OutFile $downloadPath -UseBasicParsing -MaximumRedirection 5
        $file = Get-Item -LiteralPath $downloadPath
        $hash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($file.Length -ne $ExpectedSize -or $hash -ne $ExpectedHash) {
            throw 'Remote GitHub APK size or SHA-256 did not match the verified local artifact.'
        }
        $metadata = Get-ApkMetadata -ApkPath $downloadPath -Aapt2Path $Aapt2Path -ApkSignerPath $ApkSignerPath
        if ($metadata.PackageName -ne $ExpectedPackage -or
            $metadata.VersionName -ne $ExpectedVersionName -or
            $metadata.VersionCode -ne $ExpectedVersionCode -or
            $metadata.SigningFingerprint -ne $ExpectedSigner) {
            throw "Remote GitHub APK package, version, or signer did not match Build $ExpectedVersionCode."
        }
    } finally {
        if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force }
    }
}

$pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$version = ([regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')).Groups[1].Value
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\+\d+$') { throw "Could not parse pubspec version '$version'." }
$versionParts = $version.Split('+', 2)
$versionName = $versionParts[0]
$buildNumber = [int]$versionParts[1]
$artifactName = "relio-test-$version.apk"
$releaseTag = "qa-v$versionName-b$buildNumber"
$releaseTitle = "RELIO Test v$versionName Build $buildNumber"

if ((git branch --show-current) -ne 'main') { throw 'Public QA publishing requires branch main.' }
$sourceStatus = git status --porcelain
if (-not [string]::IsNullOrWhiteSpace(($sourceStatus -join "`n"))) { throw 'Public QA publishing requires a clean source tree.' }
$sourceCommit = (git rev-parse HEAD).Trim()
$originCommit = (git rev-parse origin/main).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -ne $originCommit) { throw 'Public QA publishing requires HEAD to equal origin/main.' }
& "$PSScriptRoot\preflight.ps1" -RequireTestSigning

$qaConfig = Join-Path $projectRoot 'android\app\src\qa\google-services.json'
$config = Get-Content -Raw -LiteralPath $qaConfig | ConvertFrom-Json
$qaClient = @($config.client | Where-Object {
        $_.client_info.android_client_info.package_name -eq $expectedPackage
    }) | Select-Object -First 1
$qaAppId = [string]$qaClient.client_info.mobilesdk_app_id
if (-not $qaClient -or $config.project_info.project_id -ne $projectId -or
    $qaAppId -ne $expectedQaAppId) {
    throw 'QA Firebase configuration does not match the approved project/package/App ID.'
}
Write-Host "Verified QA Firebase project $projectId and App ID $qaAppId for $expectedPackage."

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh -and (Test-Path -LiteralPath 'C:\Program Files\GitHub CLI\gh.exe')) { $gh = Get-Item 'C:\Program Files\GitHub CLI\gh.exe' }
if (-not $gh) {
    $ghWhere = where.exe gh 2>$null | Select-Object -First 1
    if ($ghWhere -and (Test-Path -LiteralPath $ghWhere)) { $gh = [pscustomobject]@{ Source = $ghWhere } }
}
if (-not $gh) { throw 'GitHub CLI is required but was not found.' }
$null = & $gh.Source auth status 2>&1
if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not authenticated. Run gh auth login, then rerun this pipeline.' }
$githubOwner = (& $gh.Source api user --jq .login 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or $githubOwner -notmatch '^[A-Za-z0-9-]+$') {
    throw 'Could not determine the authenticated GitHub owner without exposing credentials.'
}
if ($githubOwner -ne $publicQaUpdateConfig.Owner) {
    throw 'Authenticated GitHub owner does not match the canonical public QA updater configuration.'
}
$githubRepository = "$githubOwner/$githubRepositoryName"
$githubReleaseBaseUrl = "https://github.com/$githubOwner/$githubRepositoryName/releases/download/"
$apkUrl = "$githubReleaseBaseUrl$releaseTag/$artifactName"
Write-Host "Verified authenticated GitHub owner: $githubOwner"

$firebase = Get-Command firebase -ErrorAction SilentlyContinue
if (-not $firebase) {
    $firebaseWhere = where.exe firebase 2>$null | Where-Object { $_ -match '\.(cmd|exe)$' } | Select-Object -First 1
    if ($firebaseWhere -and (Test-Path -LiteralPath $firebaseWhere)) { $firebase = [pscustomobject]@{ Source = $firebaseWhere } }
}
if (-not $firebase -and $env:APPDATA) {
    $firebaseGlobal = Join-Path $env:APPDATA 'npm\firebase.cmd'
    if (Test-Path -LiteralPath $firebaseGlobal) { $firebase = [pscustomobject]@{ Source = $firebaseGlobal } }
}
if (-not $firebase) { throw 'Firebase CLI is required for Hosting metadata deployment.' }
$env:FIREBASE_CLI_DISABLE_UPDATE_CHECK = '1'
$loginOutput = Invoke-FirebaseCli -Arguments @('login:list')
if (($loginOutput -join "`n") -match 'No authorized accounts') {
    throw 'Firebase CLI is not authenticated.'
}
$projects = ConvertFrom-CliJson (Invoke-FirebaseCli -Arguments @('projects:list', '--json'))
$projectItems = if ($projects.result) { @($projects.result) } else { @($projects) }
if (-not @($projectItems | Where-Object { $_.projectId -eq $projectId })) {
    throw "Authenticated Firebase account cannot access $projectId."
}
$sites = ConvertFrom-CliJson (Invoke-FirebaseCli -Arguments @('hosting:sites:list', '--project', $projectId, '--json'))
$siteItems = if ($sites.result.sites) { @($sites.result.sites) } elseif ($sites.sites) { @($sites.sites) } else { @() }
$site = $siteItems | Where-Object { $_.name -eq "projects/$projectId/sites/$projectId" } | Select-Object -First 1
if (-not $site) { throw "Firebase Hosting site $projectId was not found." }
$publicBaseUrl = [string]$site.defaultUrl
if (-not $publicBaseUrl) { throw 'Firebase Hosting did not return a default URL.' }
if ($publicBaseUrl.TrimEnd('/') -ne 'https://relio-17dc0.web.app') {
    throw "Unexpected Firebase Hosting URL: $publicBaseUrl"
}
Write-Host "Verified Firebase project identity and Hosting site: $publicBaseUrl"

try {
    $liveResponse = Invoke-WebRequest -Uri $publicQaUpdateConfig.ManifestUrl -UseBasicParsing
} catch {
    throw 'Could not read the current public QA manifest; refusing to publish without a monotonic-version check.'
}
if ($liveResponse.StatusCode -ne 200) { throw 'Current public QA manifest did not return HTTP 200.' }
$liveManifest = $liveResponse.Content | ConvertFrom-Json
if ($liveManifest.channel -ne $publicQaUpdateConfig.Channel -or $liveManifest.packageName -ne $expectedPackage -or
    [int]$liveManifest.versionCode -le 0) { throw 'Current public QA manifest failed channel/package/version validation.' }
if ($buildNumber -lt [int]$liveManifest.versionCode) { throw 'Refusing to publish a downgrade over the current public QA version.' }
if ($buildNumber -eq [int]$liveManifest.versionCode -and -not ($ReuseExistingArtifact -or $DryRun)) {
    throw 'The requested version is already live; use -ReuseExistingArtifact only for exact-release verification.'
}

$defines = @(
    '--dart-define=RELIO_ENV=test',
    "--dart-define=RELIO_VERSION=$versionName",
    "--dart-define=RELIO_BUILD=$buildNumber",
    "--dart-define=RELIO_PUBLIC_UPDATE_MANIFEST_URL=$($publicQaUpdateConfig.ManifestUrl)",
    "--dart-define=RELIO_PUBLIC_UPDATE_OWNER=$($publicQaUpdateConfig.Owner)",
    "--dart-define=RELIO_PUBLIC_UPDATE_REPO=$($publicQaUpdateConfig.Repository)",
    "--dart-define=RELIO_PUBLIC_UPDATE_CHANNEL=$($publicQaUpdateConfig.Channel)"
)

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
if ($ReuseExistingArtifact -or $DryRun) {
    $builtApk = Join-Path $projectRoot "dist\$artifactName"
    if (-not (Test-Path -LiteralPath $builtApk)) { throw "Requested existing QA artifact was not found: $builtApk" }
} else {
    Invoke-CheckedStep 'Building fresh signed QA release APK...' {
        & flutter build apk --no-pub --flavor qa --release @defines
    }
    $builtApk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-qa-release.apk'
    if (-not (Test-Path -LiteralPath $builtApk)) { throw "QA APK was not created: $builtApk" }
}
$aapt2 = Get-SdkTool -CommandName 'aapt2' -FileName 'aapt2.exe' -FailureMessage 'aapt2 was not found; package verification cannot continue.'
$apksigner = Get-SdkTool -CommandName 'apksigner' -FileName 'apksigner.bat' -FailureMessage 'apksigner was not found; signing verification cannot continue.'
$metadata = Get-ApkMetadata -ApkPath $builtApk -Aapt2Path $aapt2 -ApkSignerPath $apksigner
if ($metadata.PackageName -ne $expectedPackage -or
    $metadata.VersionName -ne $versionName -or
    $metadata.VersionCode -ne $buildNumber) {
    throw "QA APK package/version metadata did not match Build $buildNumber."
}

$keyPropertiesPath = Join-Path $projectRoot 'android\key.properties'
$keyProperties = Get-Content -Raw -LiteralPath $keyPropertiesPath
$keyAlias = [regex]::Match($keyProperties, '(?m)^keyAlias=(.+)$').Groups[1].Value.Trim()
$storePassword = [regex]::Match($keyProperties, '(?m)^storePassword=(.+)$').Groups[1].Value.Trim()
if (-not $keyAlias -or -not $storePassword) { throw 'QA signing metadata could not be verified without exposing credentials.' }
$keytool = Get-KeytoolPath
$keystorePath = Join-Path $projectRoot 'android\relio-test.keystore'
$keystoreCertificate = & $keytool -list -v -alias $keyAlias -keystore $keystorePath -storepass $storePassword 2>$null
if ($LASTEXITCODE -ne 0) { throw 'QA signing key could not be verified.' }
$keystoreFingerprint = [regex]::Match(($keystoreCertificate -join "`n"), '(?i)SHA256:\s*([0-9A-F:]+)').Groups[1].Value.Replace(':', '').ToLowerInvariant()
if ($metadata.SigningFingerprint -ne $publicQaUpdateConfig.SigningCertSha256 -or
    $keystoreFingerprint -ne $publicQaUpdateConfig.SigningCertSha256) {
    throw 'QA APK certificate does not match the preserved TEST signing identity.'
}
Write-Host "Verified QA package/version/signing identity: $expectedPackage $version ($($metadata.SigningFingerprint))"

$sourceHash = (Get-FileHash -LiteralPath $builtApk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ExpectedSha256 -and $sourceHash -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Artifact SHA-256 did not match the explicitly expected digest.' }
if ($DryRun) {
    $tempManifest = Join-Path ([IO.Path]::GetTempPath()) "relio-qa-dry-run-$PID.json"
    try {
        [IO.File]::WriteAllText($tempManifest, $liveResponse.Content, [Text.UTF8Encoding]::new($false))
        $dryInstalledBuilds = @(
            [Math]::Max(1, [int]$liveManifest.versionCode - 2),
            [Math]::Max(1, [int]$liveManifest.versionCode - 1),
            [int]$liveManifest.versionCode
        )
        Invoke-CheckedStep 'Validating the live manifest with the production updater parser...' {
            & dart run $validator $tempManifest $liveManifest.versionName $liveManifest.versionCode $liveManifest.apkUrl $liveManifest.sha256 $liveManifest.sizeBytes $liveManifest.signingCertSha256 @dryInstalledBuilds
        }
    } finally {
        if (Test-Path -LiteralPath $tempManifest) { Remove-Item -LiteralPath $tempManifest -Force }
    }

    $dryRelease = Get-ReleaseApiObject -Repository "$($publicQaUpdateConfig.Owner)/$githubRepositoryName" -Tag $releaseTag
    if ($dryRelease) {
        if ($dryRelease.name -ne $releaseTitle -or $dryRelease.draft -eq $true -or $dryRelease.prerelease -eq $true) {
            throw 'The existing GitHub release tag conflicts with the planned public QA release.'
        }
        $dryAsset = @($dryRelease.assets | Where-Object { $_.name -eq $artifactName }) | Select-Object -First 1
        if ($dryAsset) {
            Test-RemoteApk -Url $dryAsset.browser_download_url -ExpectedOwner $publicQaUpdateConfig.Owner -ExpectedHash $sourceHash -ExpectedSize (Get-Item -LiteralPath $builtApk).Length -ExpectedPackage $expectedPackage -ExpectedVersionName $versionName -ExpectedVersionCode $buildNumber -ExpectedSigner $metadata.SigningFingerprint -Aapt2Path $aapt2 -ApkSignerPath $apksigner
        } elseif ([int]$liveManifest.versionCode -eq $buildNumber) {
            throw "Build $buildNumber is live but its GitHub release APK asset is missing."
        }
    } elseif ([int]$liveManifest.versionCode -eq $buildNumber) {
        throw "Build $buildNumber is live without a matching GitHub release; dry-run cannot verify the published state."
    }

    Write-Host "DRY RUN VERIFIED: source=$sourceCommit live=$($liveManifest.versionName)+$($liveManifest.versionCode) planned=$version tag=$releaseTag APK=$artifactName SHA-256=$sourceHash"
    Write-Host 'GitHub release state: VERIFIED; Firebase deployment skipped; no remote mutation performed.'
    return
}

$releaseRoot = Join-Path $projectRoot 'dist\public-qa'
$hostingRoot = Join-Path $projectRoot 'public_update\hosting'
$qaHostingRoot = Join-Path $hostingRoot 'qa'
New-Item -ItemType Directory -Path $releaseRoot, $qaHostingRoot -Force | Out-Null
$releaseApk = Join-Path $releaseRoot $artifactName
Copy-Item -LiteralPath $builtApk -Destination $releaseApk -Force
$fileInfo = Get-Item -LiteralPath $releaseApk
$sha256 = (Get-FileHash -LiteralPath $releaseApk -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = Join-Path $releaseRoot 'SHA256SUMS.txt'
"$sha256 *$artifactName" | Set-Content -LiteralPath $checksumPath -Encoding ascii

if (-not $NoUpload) {
    $repoOutput = & $gh.Source api "repos/$githubRepository" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Creating public metadata/APK repository $githubRepository..."
        & $gh.Source repo create $githubRepository --public --description 'RELIO Android QA release assets only; no application source or secrets.' --disable-issues --disable-wiki
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the public GitHub release repository.' }
        $repoOutput = & $gh.Source api "repos/$githubRepository" 2>&1
    }
    $repo = ($repoOutput -join "`n") | ConvertFrom-Json
    if ($repo.private -eq $true -or $repo.name -ne $githubRepositoryName) {
        throw 'The GitHub release repository is not the expected public repository.'
    }
    $readmeOutput = & $gh.Source api "repos/$githubRepository/contents/README.md" 2>&1
    $readmeExists = $LASTEXITCODE -eq 0
    if (-not $readmeExists -and ($readmeOutput -join "`n") -notmatch 'empty|404|Not Found') {
        throw 'Could not inspect the public release repository README state.'
    }
    if (-not $readmeExists) {
        $seedReadme = @(
            '# RELIO Android Updates',
            '',
            'Public RELIO Test Android QA release metadata and signed APK assets only.',
            'This repository intentionally contains no RELIO application source or secrets.'
        ) -join "`n"
        $seedContent = [Convert]::ToBase64String(
            [Text.Encoding]::UTF8.GetBytes($seedReadme)
        )
        Write-Host 'Initializing the empty public release repository with metadata-only README...'
        & $gh.Source api --method PUT "repos/$githubRepository/contents/README.md" `
            --field message='chore: initialize Android update metadata repository' `
            --field content=$seedContent
        if ($LASTEXITCODE -ne 0) {
            throw 'Could not initialize the empty GitHub release repository.'
        }
    }

    $release = Get-ReleaseApiObject -Repository $githubRepository -Tag $releaseTag
    if ([int]$liveManifest.versionCode -eq $buildNumber -and -not $release) {
        throw 'The same version is live but its immutable GitHub release is missing; refusing to recreate or overwrite it.'
    }
    if (-not $release) {
        $notesPath = Join-Path $projectRoot "release_notes\$versionName-build-$buildNumber.md"
        if (-not (Test-Path -LiteralPath $notesPath)) {
            $notesPath = Join-Path $projectRoot "release_notes\$versionName.md"
        }
        if (-not (Test-Path -LiteralPath $notesPath)) { throw "Release notes were not found: $notesPath" }
        Write-Host "Creating immutable GitHub release $releaseTag..."
        & $gh.Source release create $releaseTag $releaseApk --repo $githubRepository --title $releaseTitle --notes-file $notesPath
        if ($LASTEXITCODE -ne 0) { throw 'GitHub release creation failed. Firebase Hosting was not deployed.' }
        $release = Get-ReleaseApiObject -Repository $githubRepository -Tag $releaseTag
    } elseif ($release.name -ne $releaseTitle -or $release.draft -eq $true -or $release.prerelease -eq $true) {
        throw 'An existing GitHub release has the wrong title or is not a public stable release; refusing to mutate it.'
    }

    $existingApk = @($release.assets | Where-Object { $_.name -eq $artifactName }) | Select-Object -First 1
    if ($existingApk) {
        Test-RemoteApk -Url $existingApk.browser_download_url -ExpectedOwner $publicQaUpdateConfig.Owner -ExpectedHash $sha256 -ExpectedSize $fileInfo.Length -ExpectedPackage $expectedPackage -ExpectedVersionName $versionName -ExpectedVersionCode $buildNumber -ExpectedSigner $metadata.SigningFingerprint -Aapt2Path $aapt2 -ApkSignerPath $apksigner
        Write-Host "Existing GitHub APK asset matches the newly verified Build $buildNumber; it was not replaced."
    } else {
        & $gh.Source release upload $releaseTag $releaseApk --repo $githubRepository
        if ($LASTEXITCODE -ne 0) { throw 'GitHub APK upload failed. Firebase Hosting was not deployed.' }
    }
    $release = Get-ReleaseApiObject -Repository $githubRepository -Tag $releaseTag
    $finalAsset = @($release.assets | Where-Object { $_.name -eq $artifactName }) | Select-Object -First 1
    if (-not $finalAsset) { throw 'GitHub release did not expose the expected APK asset.' }
    Test-RemoteApk -Url $finalAsset.browser_download_url -ExpectedOwner $publicQaUpdateConfig.Owner -ExpectedHash $sha256 -ExpectedSize $fileInfo.Length -ExpectedPackage $expectedPackage -ExpectedVersionName $versionName -ExpectedVersionCode $buildNumber -ExpectedSigner $metadata.SigningFingerprint -Aapt2Path $aapt2 -ApkSignerPath $apksigner
    Write-Host 'Verified the public GitHub APK asset before generating the Hosting manifest.'
} else {
    Write-Host 'GitHub release upload skipped by -NoUpload.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    channel = $publicQaUpdateConfig.Channel
    packageName = $expectedPackage
    versionName = $versionName
    versionCode = $buildNumber
    apkUrl = $apkUrl
    sha256 = $sha256
    sizeBytes = [int64]$fileInfo.Length
    signingCertSha256 = $publicQaUpdateConfig.SigningCertSha256
    publishedAt = [DateTime]::UtcNow.ToString('o')
    releaseNotes = @(
        "RELIO Test v$versionName Build $buildNumber",
        "ทดสอบการอัปเดตจาก Build $($buildNumber - 1) ผ่านระบบ Public QA Update",
        'ไม่มีการล้างข้อมูลในเครื่อง',
        'ใช้สำหรับตรวจสอบการดาวน์โหลดและติดตั้งอัปเดตจากภายใน RELIO'
    )
}
$manifestJson = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $qaHostingRoot 'latest.json'), $manifestJson, [Text.UTF8Encoding]::new($false))
$validator = Join-Path $projectRoot 'tool\validate_public_qa_manifest.dart'
$installedBuilds = @([Math]::Max(1, [int]$liveManifest.versionCode - 1), [int]$liveManifest.versionCode, $buildNumber)
Invoke-CheckedStep 'Validating generated manifest with the production updater parser...' {
    & dart run $validator (Join-Path $qaHostingRoot 'latest.json') $versionName $buildNumber $apkUrl $sha256 $fileInfo.Length $publicQaUpdateConfig.SigningCertSha256 @installedBuilds
}
$template = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'firebase_hosting\qa\index.template.html')
$page = $template.Replace('__VERSION_NAME__', $versionName).
    Replace('__BUILD_NUMBER__', [string]$buildNumber).
    Replace('__APK_URL__', $apkUrl).
    Replace('__SHA256__', $sha256).
    Replace('__SIZE_MB__', ('{0:N1}' -f ($fileInfo.Length / 1MB)))
[IO.File]::WriteAllText((Join-Path $qaHostingRoot 'index.html'), $page, [Text.UTF8Encoding]::new($false))
$hostingApks = @(Get-ChildItem -LiteralPath $hostingRoot -Filter '*.apk' -File -Recurse -ErrorAction SilentlyContinue)
if ($hostingApks.Count -gt 0) { throw 'Firebase Hosting staging contains an APK; Hosting must contain metadata/page only.' }

if ($NoDeploy) {
    Write-Host "Prepared Firebase Hosting metadata only: $qaHostingRoot"
    Write-Host "GitHub APK URL: $apkUrl"
    Write-Host "Build $buildNumber SHA-256: $sha256"
    exit 0
}

Invoke-CheckedStep 'Deploying Firebase Hosting metadata only...' {
    & $firebase.Source deploy --only "hosting:$projectId" --project $projectId --non-interactive
}

$manifestUrl = "$publicBaseUrl/qa/latest.json"
$remoteManifestResponse = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing
if ($remoteManifestResponse.StatusCode -ne 200) { throw 'Public latest.json verification failed.' }
$remoteManifest = $remoteManifestResponse.Content | ConvertFrom-Json
if ($remoteManifest.packageName -ne $expectedPackage -or
    [int]$remoteManifest.versionCode -ne $buildNumber -or
    $remoteManifest.sha256 -ne $sha256 -or
    $remoteManifest.apkUrl -ne $apkUrl) {
    throw "Remote public manifest values do not match Build $buildNumber or the exact GitHub asset URL."
}
$liveManifestPath = Join-Path ([IO.Path]::GetTempPath()) "relio-live-manifest-$PID.json"
try {
    [IO.File]::WriteAllText($liveManifestPath, $remoteManifestResponse.Content, [Text.UTF8Encoding]::new($false))
    Invoke-CheckedStep 'Validating live manifest with the production updater parser...' {
        & dart run $validator $liveManifestPath $versionName $buildNumber $apkUrl $sha256 $fileInfo.Length $publicQaUpdateConfig.SigningCertSha256 @installedBuilds
    }
} finally {
    if (Test-Path -LiteralPath $liveManifestPath) { Remove-Item -LiteralPath $liveManifestPath -Force }
}
$remotePage = Invoke-WebRequest -Uri "$publicBaseUrl/qa/" -UseBasicParsing
if ($remotePage.StatusCode -ne 200 -or $remotePage.Content -notmatch 'data-relio-public-qa-channel="true"' -or
    $remotePage.Content -notmatch [regex]::Escape($apkUrl)) {
    throw 'Public download page verification failed.'
}
Test-RemoteApk -Url $apkUrl -ExpectedOwner $publicQaUpdateConfig.Owner -ExpectedHash $sha256 -ExpectedSize $fileInfo.Length -ExpectedPackage $expectedPackage -ExpectedVersionName $versionName -ExpectedVersionCode $buildNumber -ExpectedSigner $metadata.SigningFingerprint -Aapt2Path $aapt2 -ApkSignerPath $apksigner

Write-Host "PUBLIC QA PAGE: $publicBaseUrl/qa/"
Write-Host "PUBLIC MANIFEST: $manifestUrl"
Write-Host "PUBLIC GITHUB APK: $apkUrl"
Write-Host "BUILD $buildNumber SHA-256: $sha256"
Write-Host "BUILD $buildNumber SIZE BYTES: $($fileInfo.Length)"
Write-Host "BUILD $buildNumber SIGNING SHA-256: $($metadata.SigningFingerprint)"
Write-Host 'HYBRID PUBLIC QA RELEASE — VERIFIED'
