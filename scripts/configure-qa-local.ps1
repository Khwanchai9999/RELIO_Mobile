[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}

$allowlistPath = Join-Path $projectRoot 'supabase\qa-project-allowlist.json'
$configPath = Join-Path $projectRoot '.env.qa.local'
$allowlist = Get-Content -Raw -LiteralPath $allowlistPath | ConvertFrom-Json
$qaRef = [string]$allowlist.qaProjectRef
if ($qaRef -ne 'zeuiqspvqiplusiugcto') {
    throw 'The QA allowlist no longer matches the independently verified RELIO-QA project.'
}

$projectOutput = & npx --yes supabase projects list --output-format json
if ($LASTEXITCODE -ne 0) { throw 'Authenticated Supabase project listing failed.' }
$projectListing = ($projectOutput -join "`n") | ConvertFrom-Json
$matchingProjects = @($projectListing.projects | Where-Object {
    $_.ref -eq $qaRef -and $_.name -eq 'RELIO-QA' -and
    $_.region -eq 'ap-southeast-1' -and $_.status -eq 'ACTIVE_HEALTHY'
})
if ($matchingProjects.Count -ne 1) {
    throw 'Exact RELIO-QA identity/status verification failed; no credentials were retrieved.'
}

$prior = @{}
if (Test-Path -LiteralPath $configPath) {
    foreach ($line in Get-Content -LiteralPath $configPath) {
        if ($line -match '^([A-Z0-9_]+)=(.*)$') { $prior[$Matches[1]] = $Matches[2] }
    }
    if ($prior['RELIO_SUPABASE_QA_PROJECT_REF'] -ne $qaRef) {
        throw 'Existing QA local config targets another project; refusing to overwrite it.'
    }
}

$keyOutput = & npx --yes supabase projects api-keys --project-ref $qaRef --reveal --output-format json
if ($LASTEXITCODE -ne 0) { throw 'Authenticated QA API-key retrieval failed.' }
$keyDocument = ($keyOutput -join "`n") | ConvertFrom-Json
$keyRows = @($keyDocument.keys)
$anonKey = [string](@($keyRows | Where-Object { $_.name -eq 'anon' -and $_.type -eq 'legacy' } | Select-Object -First 1)[0].api_key)
$serviceKey = [string](@($keyRows | Where-Object { $_.name -eq 'service_role' -and $_.type -eq 'legacy' } | Select-Object -First 1)[0].api_key)
if ([string]::IsNullOrWhiteSpace($anonKey) -or [string]::IsNullOrWhiteSpace($serviceKey)) {
    throw 'Expected legacy public and service-role keys are unavailable; no file was written.'
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
$identities = @(
    @{ Key = 'RELIO_QA_USER'; Local = 'USER'; Email = "relio-qa-user-a-$suffix@example.invalid"; Role = 'user' },
    @{ Key = 'RELIO_QA_USER_B'; Local = 'USER_B'; Email = "relio-qa-user-b-$suffix@example.invalid"; Role = 'user' },
    @{ Key = 'RELIO_QA_RESCUER'; Local = 'RESCUER'; Email = "relio-qa-rescuer-$suffix@example.invalid"; Role = 'rescuer' },
    @{ Key = 'RELIO_QA_ADMIN'; Local = 'ADMIN'; Email = "relio-qa-admin-$suffix@example.invalid"; Role = 'admin' }
)
foreach ($identity in $identities) {
    $emailName = $identity.Key + '_EMAIL'
    $passwordName = $identity.Key + '_PASSWORD'
    if ($prior.ContainsKey($emailName) -and $prior.ContainsKey($passwordName)) {
        $identity.Email = $prior[$emailName]
        $identity.Password = $prior[$passwordName]
    } elseif ($prior.ContainsKey($emailName) -or $prior.ContainsKey($passwordName)) {
        throw "Existing local config has an incomplete identity pair: $($identity.Key)."
    } else {
        $identity.Password = [guid]::NewGuid().ToString('N') + 'Aa1!'
    }
}

$lines = [Collections.Generic.List[string]]::new()
$lines.Add("RELIO_SUPABASE_QA_PROJECT_REF=$qaRef")
$lines.Add("RELIO_SUPABASE_QA_URL=https://$qaRef.supabase.co")
$lines.Add("RELIO_SUPABASE_QA_ANON_KEY=$anonKey")
$lines.Add("RELIO_SUPABASE_QA_SERVICE_ROLE_KEY=$serviceKey")
foreach ($identity in $identities) {
    $lines.Add("$($identity.Key)_EMAIL=$($identity.Email)")
    $lines.Add("$($identity.Key)_PASSWORD=$($identity.Password)")
}

[IO.File]::WriteAllText($configPath, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$acl = Get-Acl -LiteralPath $configPath
$acl.SetAccessRuleProtection($true, $false)
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$ownerRule = New-Object Security.AccessControl.FileSystemAccessRule(
    $currentSid,
    [Security.AccessControl.FileSystemRights]::FullControl,
    [Security.AccessControl.AccessControlType]::Allow
)
$acl.SetAccessRule($ownerRule)
Set-Acl -LiteralPath $configPath -AclObject $acl

Write-Output "Created or refreshed ACL-restricted local QA config for RELIO-QA ($qaRef)."
