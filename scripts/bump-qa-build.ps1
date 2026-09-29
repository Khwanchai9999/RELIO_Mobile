[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 2147483647)]
    [int]$NextBuildNumber
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$pubspec = Get-Content -Raw -LiteralPath $pubspecPath
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')
if (-not $versionMatch.Success) {
    throw 'Could not read version from pubspec.yaml.'
}

$currentVersion = $versionMatch.Groups[1].Value
$versionParts = $currentVersion.Split('+', 2)
if ($versionParts.Count -ne 2 -or ($versionParts[1] -as [int] -eq $null)) {
    throw "Version must include a numeric build number: $currentVersion"
}
$currentBuildNumber = [int]$versionParts[1]
$proposedVersion = "$($versionParts[0])+$NextBuildNumber"
Write-Host "Current version:  $currentVersion"
Write-Host "Proposed version: $proposedVersion"

if ($NextBuildNumber -le $currentBuildNumber) {
    throw "Next build number must be greater than $currentBuildNumber."
}
if (-not $PSCmdlet.ShouldProcess($pubspecPath, "Set version to $proposedVersion")) {
    return
}

# แก้เฉพาะ version ใน pubspec เพื่อให้การ bump Build 12 ต้องเรียกใช้โดยตั้งใจ
$updatedPubspec = [regex]::Replace(
    $pubspec,
    '(?m)^version:\s+[^\s#]+',
    "version: $proposedVersion",
    1
)
[IO.File]::WriteAllText($pubspecPath, $updatedPubspec, [Text.UTF8Encoding]::new($false))
Write-Host "Updated $pubspecPath to $proposedVersion"
