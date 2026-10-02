[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}
. (Join-Path $PSScriptRoot 'import-qa-local-env.ps1')
$adminRoot = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $projectRoot) 'RELIO_Admin')).TrimEnd('\')
if (-not (Test-Path -LiteralPath (Join-Path $adminRoot '.git'))) {
    throw 'The separate RELIO_Admin Git root is missing.'
}
$examplePath = Join-Path $adminRoot '.env.example'
if (-not (Test-Path -LiteralPath $examplePath)) { throw 'Admin .env.example is missing.' }
$exampleNames = @(Get-Content -LiteralPath $examplePath | ForEach-Object {
    if ($_ -match '^([A-Z0-9_]+)=') { $Matches[1] }
})
if ($exampleNames -notcontains 'VITE_SUPABASE_URL' -or $exampleNames -notcontains 'VITE_SUPABASE_ANON_KEY') {
    throw 'Admin .env.example must document only the browser-safe QA variable names.'
}

$envPath = Join-Path $adminRoot '.env.local'
$values = [ordered]@{}
if (Test-Path -LiteralPath $envPath) {
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ($line -match '^([A-Z0-9_]+)=(.*)$') { $values[$Matches[1]] = $Matches[2] }
    }
}
$values['VITE_SUPABASE_URL'] = $env:RELIO_SUPABASE_QA_URL
$values['VITE_SUPABASE_ANON_KEY'] = $env:RELIO_SUPABASE_QA_ANON_KEY
$content = foreach ($name in $values.Keys) { "$name=$($values[$name])" }
[IO.File]::WriteAllText($envPath, (($content -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$acl = Get-Acl -LiteralPath $envPath
$acl.SetAccessRuleProtection($true, $false)
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$ownerRule = New-Object Security.AccessControl.FileSystemAccessRule(
    $currentSid,
    [Security.AccessControl.FileSystemRights]::FullControl,
    [Security.AccessControl.AccessControlType]::Allow
)
$acl.SetAccessRule($ownerRule)
Set-Acl -LiteralPath $envPath -AclObject $acl
Write-Output "Configured ACL-restricted Admin browser-safe values for RELIO-QA ($env:RELIO_SUPABASE_QA_PROJECT_REF); no privileged key was copied."
