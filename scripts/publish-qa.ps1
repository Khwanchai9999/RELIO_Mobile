[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$ReuseExistingArtifact,
    [string]$ExpectedSha256
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}

$arguments = @{}
if ($DryRun) { $arguments.DryRun = $true }
if ($ReuseExistingArtifact) { $arguments.ReuseExistingArtifact = $true }
if ($ExpectedSha256) { $arguments.ExpectedSha256 = $ExpectedSha256 }

$proxyNames = @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy')
$savedProxyValues = @{}
foreach ($name in $proxyNames) { $savedProxyValues[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$savedInternalFlag = $env:RELIO_QA_PUBLISH_INTERNAL
$staleLocalProxy = $false
foreach ($name in $proxyNames) {
    $value = $savedProxyValues[$name]
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
        Write-Host 'Using direct network access for this publisher process because its configured loopback proxy is unreachable.'
    }
    $env:RELIO_QA_PUBLISH_INTERNAL = '1'
    & (Join-Path $PSScriptRoot 'release-public-qa.ps1') @arguments
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "QA publish failed with exit code $LASTEXITCODE." }
} finally {
    foreach ($name in $proxyNames) { [Environment]::SetEnvironmentVariable($name, $savedProxyValues[$name], 'Process') }
    [Environment]::SetEnvironmentVariable('RELIO_QA_PUBLISH_INTERNAL', $savedInternalFlag, 'Process')
}
