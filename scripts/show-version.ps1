[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$pubspec = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
$match = [regex]::Match($pubspec, '(?m)^version:\s+([^\s#]+)')
if (-not $match.Success) { throw 'Could not read version from pubspec.yaml.' }

$versionParts = $match.Groups[1].Value.Split('+', 2)
Write-Output "versionName=$($versionParts[0])"
Write-Output "buildNumber=$($versionParts[1])"
Write-Output 'productionApplicationId=com.relio.relio_mobile'
Write-Output 'testApplicationId=com.relio.relio_mobile.test'
