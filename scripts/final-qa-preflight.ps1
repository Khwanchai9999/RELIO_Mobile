[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$qaEnvLoader = Join-Path $PSScriptRoot 'import-qa-local-env.ps1'
if (Test-Path -LiteralPath $qaEnvLoader) { . $qaEnvLoader }
$adminRoot = Join-Path (Split-Path -Parent $projectRoot) 'RELIO_Admin'
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}
if ((git -C $projectRoot rev-parse --show-toplevel).Trim().Replace('/', '\') -ne $projectRoot) {
    throw 'The active directory is not the Mobile Git root.'
}
if ((git -C $projectRoot remote get-url origin).Trim() -ne 'https://github.com/Khwanchai9999/RELIO_Mobile.git') {
    throw 'The Mobile origin must remain the separate RELIO_Mobile source repository.'
}
if (-not (Test-Path -LiteralPath (Join-Path $adminRoot '.git'))) {
    throw "The separate Admin Git root was not found: $adminRoot"
}
if ((git -C $adminRoot rev-parse --show-toplevel).Trim().Replace('/', '\') -ne $adminRoot) {
    throw 'The separate Admin checkout is not its own Git root.'
}
$adminChanges = @(git -C $adminRoot status --porcelain --untracked-files=all)
if ($adminChanges.Count -gt 0) {
    throw 'The separate Admin repository must be clean before final QA preflight.'
}

$allowedUntracked = @(
    'huawei-build16-to17-ota.txt',
    'huawei-build17-install-stage.txt'
)
$unexpectedChanges = @(git -C $projectRoot status --porcelain | Where-Object {
        $line = $_
        if ($line.Length -lt 4) { return $true }
        $path = $line.Substring(3).Trim('"')
        -not ($line.StartsWith('?? ') -and $allowedUntracked -contains $path)
    })
if ($unexpectedChanges.Count -gt 0) {
    throw "Commit or discard intended Mobile changes before final preflight: $($unexpectedChanges -join '; ')"
}

$proxyNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy')
$savedProxyValues = @{}
$staleLocalProxy = $false
foreach ($name in $proxyNames) {
    $value = [Environment]::GetEnvironmentVariable($name, 'Process')
    $savedProxyValues[$name] = $value
    if ($value -and $value -match '^https?://(?:localhost|127\.0\.0\.1):(?<port>\d+)$') {
        $client = [Net.Sockets.TcpClient]::new()
        try { $client.Connect('127.0.0.1', [int]$Matches.port) }
        catch { $staleLocalProxy = $true }
        finally { $client.Dispose() }
    }
}
try {
    if ($staleLocalProxy) {
        foreach ($name in $proxyNames) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
        Write-Host 'Using direct access for this read-only GitHub ref check because the configured loopback proxy is unreachable.'
    }
    $remoteMain = git -C $projectRoot ls-remote origin refs/heads/main
    if ($LASTEXITCODE -ne 0) { throw 'Could not verify the source repository remote main ref.' }
} finally {
    foreach ($name in $proxyNames) { [Environment]::SetEnvironmentVariable($name, $savedProxyValues[$name], 'Process') }
}
$remoteHead = ([string]$remoteMain -split '\s+')[0]
$localHead = (git -C $projectRoot rev-parse HEAD).Trim()
if (-not $remoteHead -or $remoteHead -ne $localHead) {
    throw 'The verified Mobile source commit is not the exact current origin/main commit.'
}

$qaRef = $env:RELIO_SUPABASE_QA_PROJECT_REF
$qaAllowlist = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'supabase\qa-project-allowlist.json') | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($qaRef) -or $qaRef -ne [string]$qaAllowlist.qaProjectRef) {
    throw 'The QA Supabase ref is missing or not independently allowlisted.'
}
$expectedAdminSupabaseUrl = "https://$qaRef.supabase.co"
if ($env:VITE_SUPABASE_URL -ne $expectedAdminSupabaseUrl -or
    [string]::IsNullOrWhiteSpace($env:VITE_SUPABASE_ANON_KEY)) {
    throw 'Admin build must have the verified QA Supabase URL and public anon key in the process environment.'
}

$pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')
if (-not $versionMatch.Success -or $versionMatch.Groups[1].Value -ne '0.9.0+26') {
    throw 'Final preflight is scoped to the verified Build 26 candidate (0.9.0+26); refusing an implicit version change.'
}
$releaseNotesPath = Join-Path $projectRoot 'release_notes\0.9.0-build-26.md'
if (-not (Test-Path -LiteralPath $releaseNotesPath) -or
    (Get-Content -Raw -LiteralPath $releaseNotesPath) -notmatch '(?i)Build 26' -or
    (Get-Content -Raw -LiteralPath $releaseNotesPath) -notmatch '(?i)not been uploaded') {
    throw 'Build 26 release notes are missing or do not preserve its unpublished status.'
}

Write-Host 'Checking Firebase QA/PROD SDK isolation...'
& (Join-Path $PSScriptRoot 'verify-qa-update-isolation.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Firebase QA/PROD isolation check failed.' }

Write-Host 'Checking the local QA artifact through the canonical read-only release pipeline...'
& (Join-Path $PSScriptRoot 'publish-qa.ps1') -DryRun -ReuseExistingArtifact
if ($LASTEXITCODE -ne 0) { throw 'Canonical public QA release dry-run failed.' }

Write-Host 'Checking live QA backend, migration history, schema, and public metadata...'
& (Join-Path $PSScriptRoot 'verify-qa-backend.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Live QA backend health check failed.' }

$adminUrl = $env:RELIO_ADMIN_QA_URL
if ([string]::IsNullOrWhiteSpace($adminUrl)) {
    throw 'RELIO_ADMIN_QA_URL must identify the deployed QA Admin site.'
}
$adminUri = $null
if (-not [Uri]::TryCreate($adminUrl, [UriKind]::Absolute, [ref]$adminUri) -or
    $adminUri.Scheme -ne 'https' -or $adminUri.IsLoopback) {
    throw 'RELIO_ADMIN_QA_URL must be a deployed HTTPS origin.'
}
try {
    $adminResponse = Invoke-WebRequest -UseBasicParsing -Uri $adminUri.AbsoluteUri -TimeoutSec 30
} catch {
    throw 'Deployed QA Admin did not return a successful response.'
}
if ([int]$adminResponse.StatusCode -ne 200) { throw 'Deployed QA Admin did not return HTTP 200.' }
Write-Host "Deployed Admin QA page returned HTTP 200: $($adminUri.Host)."

Write-Host 'Checking FCM Edge Function unit suite...'
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'Node.js is required for the FCM logic tests.' }
& $node.Source --test (Join-Path $projectRoot 'supabase\functions\send-message-push\logic.test.mjs')
if ($LASTEXITCODE -ne 0) { throw 'FCM logic tests failed.' }

Write-Host 'Checking Admin tests, lint, and production build...'
if (-not (Test-Path -LiteralPath (Join-Path $adminRoot 'node_modules'))) {
    throw 'Admin dependencies are not installed; refusing an implicit package install.'
}
Push-Location $adminRoot
try {
    npm test
    if ($LASTEXITCODE -ne 0) { throw 'Admin tests failed.' }
    npm run lint
    if ($LASTEXITCODE -ne 0) { throw 'Admin lint failed.' }
    npm run build
    if ($LASTEXITCODE -ne 0) { throw 'Admin production build failed.' }
} finally {
    Pop-Location
}

Write-Host 'FINAL QA PREFLIGHT PASSED. This script is read-only with respect to cloud services; it does not upload, deploy, seed, or install an APK.'
