[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$configPath = Join-Path $projectRoot '.env.qa.local'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Local QA config is missing; run scripts/configure-qa-local.ps1 first.'
}

$allowedNames = @(
    'RELIO_SUPABASE_QA_PROJECT_REF', 'RELIO_SUPABASE_QA_URL',
    'RELIO_SUPABASE_QA_ANON_KEY', 'RELIO_SUPABASE_QA_SERVICE_ROLE_KEY',
    'RELIO_QA_DATABASE_WEBHOOK_SECRET',
    'RELIO_QA_USER_EMAIL', 'RELIO_QA_USER_PASSWORD',
    'RELIO_QA_USER_B_EMAIL', 'RELIO_QA_USER_B_PASSWORD',
    'RELIO_QA_RESCUER_EMAIL', 'RELIO_QA_RESCUER_PASSWORD',
    'RELIO_QA_ADMIN_EMAIL', 'RELIO_QA_ADMIN_PASSWORD'
)
foreach ($line in Get-Content -LiteralPath $configPath) {
    if ($line -notmatch '^([A-Z0-9_]+)=(.*)$') { throw 'Local QA config contains an invalid line.' }
    $name = $Matches[1]
    if ($name -notin $allowedNames) { throw 'Local QA config contains an unsupported variable name.' }
    [Environment]::SetEnvironmentVariable($name, $Matches[2], 'Process')
}

if ($env:RELIO_SUPABASE_QA_PROJECT_REF -ne 'zeuiqspvqiplusiugcto') {
    throw 'Imported local QA config does not target the verified RELIO-QA project.'
}
$env:VITE_SUPABASE_URL = $env:RELIO_SUPABASE_QA_URL
$env:VITE_SUPABASE_ANON_KEY = $env:RELIO_SUPABASE_QA_ANON_KEY
$env:SUPABASE_URL = $env:RELIO_SUPABASE_QA_URL
$env:SUPABASE_ANON_KEY = $env:RELIO_SUPABASE_QA_ANON_KEY
