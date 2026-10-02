[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$configPath = Join-Path $projectRoot '.env.qa.local'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Local QA config is missing; no account credentials are available.'
}
$values = @{}
foreach ($line in Get-Content -LiteralPath $configPath) {
    if ($line -match '^(RELIO_SUPABASE_QA_PROJECT_REF|RELIO_QA_USER_EMAIL|RELIO_QA_USER_PASSWORD|RELIO_QA_USER_B_EMAIL|RELIO_QA_USER_B_PASSWORD)=(.*)$') {
        $values[$Matches[1]] = $Matches[2]
    }
}
if ($values['RELIO_SUPABASE_QA_PROJECT_REF'] -ne 'zeuiqspvqiplusiugcto' -or
    @('RELIO_QA_USER_EMAIL', 'RELIO_QA_USER_PASSWORD', 'RELIO_QA_USER_B_EMAIL', 'RELIO_QA_USER_B_PASSWORD' |
        Where-Object { -not $values.ContainsKey($_) }).Count -gt 0) {
    throw 'Local QA test-user entries are incomplete or target another project.'
}
Write-Output 'RELIO-QA Test User A'
Write-Output "Email: $($values['RELIO_QA_USER_EMAIL'])"
Write-Output "Password: $($values['RELIO_QA_USER_PASSWORD'])"
Write-Output ''
Write-Output 'RELIO-QA Test User B'
Write-Output "Email: $($values['RELIO_QA_USER_B_EMAIL'])"
Write-Output "Password: $($values['RELIO_QA_USER_B_PASSWORD'])"
