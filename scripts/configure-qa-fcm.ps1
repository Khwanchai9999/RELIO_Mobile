[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}

$qaRef = 'zeuiqspvqiplusiugcto'
$allowlist = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'supabase\qa-project-allowlist.json') | ConvertFrom-Json
if ($allowlist.qaProjectRef -ne $qaRef -or
    (Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'supabase\.temp\project-ref')).Trim() -ne $qaRef) {
    throw 'The allowlist or linked Supabase project does not match RELIO-QA.'
}

$projectsOutput = & npx --yes supabase projects list --output-format json
if ($LASTEXITCODE -ne 0) { throw 'Authenticated Supabase project verification failed.' }
$projects = ($projectsOutput -join "`n") | ConvertFrom-Json
$qaProjects = @($projects.projects | Where-Object {
        $_.ref -eq $qaRef -and $_.name -eq 'RELIO-QA' -and
        $_.region -eq 'ap-southeast-1' -and $_.status -eq 'ACTIVE_HEALTHY'
    })
if ($qaProjects.Count -ne 1) { throw 'Exact RELIO-QA identity/status verification failed.' }

. (Join-Path $PSScriptRoot 'import-qa-local-env.ps1')
if ($env:RELIO_SUPABASE_QA_URL -ne "https://$qaRef.supabase.co" -or
    [string]::IsNullOrWhiteSpace($env:RELIO_SUPABASE_QA_SERVICE_ROLE_KEY)) {
    throw 'Required QA-only local service credentials are unavailable.'
}

$localQaDirectory = Join-Path $projectRoot '.qa-local'
if (-not (Test-Path -LiteralPath $localQaDirectory)) {
    New-Item -ItemType Directory -Path $localQaDirectory | Out-Null
}
$directoryAcl = Get-Acl -LiteralPath $localQaDirectory
$directoryAcl.SetAccessRuleProtection($true, $false)
$currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$directoryAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        $currentSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow
    )))
Set-Acl -LiteralPath $localQaDirectory -AclObject $directoryAcl

$serviceAccountPath = Join-Path $localQaDirectory 'relio-qa-fcm-service-account.json'
if (-not (Test-Path -LiteralPath $serviceAccountPath)) {
    throw 'The dedicated QA FCM service-account JSON is missing from .qa-local.'
}
$serviceAccount = Get-Content -Raw -LiteralPath $serviceAccountPath | ConvertFrom-Json
if ($serviceAccount.project_id -ne 'relio-17dc0' -or
    [string]$serviceAccount.client_email -notmatch '^relio-qa-fcm-sender@relio-17dc0\.iam\.gserviceaccount\.com$' -or
    [string]::IsNullOrWhiteSpace([string]$serviceAccount.private_key)) {
    throw 'The local FCM service identity is not the dedicated least-privilege RELIO QA sender.'
}

$configPath = Join-Path $projectRoot '.env.qa.local'
$configLines = [Collections.Generic.List[string]]::new()
$webhookSecret = $env:RELIO_QA_DATABASE_WEBHOOK_SECRET
if ([string]::IsNullOrWhiteSpace($webhookSecret)) {
    $randomBytes = New-Object 'byte[]' 48
    $randomGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $randomGenerator.GetBytes($randomBytes) }
    finally { $randomGenerator.Dispose() }
    $webhookSecret = [Convert]::ToBase64String($randomBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}
$webhookConfigLine = "RELIO_QA_DATABASE_WEBHOOK_SECRET=$webhookSecret"
$replacedWebhook = $false
foreach ($line in Get-Content -LiteralPath $configPath) {
    if ($line -match '^RELIO_QA_DATABASE_WEBHOOK_SECRET=') {
        if (-not $replacedWebhook) { $configLines.Add($webhookConfigLine); $replacedWebhook = $true }
    } else {
        $configLines.Add($line)
    }
}
if (-not $replacedWebhook) { $configLines.Add($webhookConfigLine) }
[IO.File]::WriteAllText($configPath, (($configLines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$configAcl = Get-Acl -LiteralPath $configPath
$configAcl.SetAccessRuleProtection($true, $false)
$configAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
        $currentSid,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow
    )))
Set-Acl -LiteralPath $configPath -AclObject $configAcl
$env:RELIO_QA_DATABASE_WEBHOOK_SECRET = $webhookSecret

$tempEnvPath = Join-Path $localQaDirectory 'edge-secrets.env'
$tempSqlPath = Join-Path $localQaDirectory 'vault-webhook-secrets.sql'
try {
    $serviceAccountJson = Get-Content -Raw -LiteralPath $serviceAccountPath | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress
    if ($serviceAccountJson.Contains("'")) { throw 'FCM service-account JSON contains an unsupported dotenv quote.' }
    $edgeValues = @(
        "SUPABASE_URL='$($env:RELIO_SUPABASE_QA_URL)'",
        "SUPABASE_SERVICE_ROLE_KEY='$($env:RELIO_SUPABASE_QA_SERVICE_ROLE_KEY)'",
        "DATABASE_WEBHOOK_SECRET='$webhookSecret'",
        "FCM_SERVICE_ACCOUNT_JSON='$serviceAccountJson'",
        "FCM_PROJECT_ID='relio-17dc0'"
    )
    [IO.File]::WriteAllText($tempEnvPath, (($edgeValues -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    $tempEnvAcl = Get-Acl -LiteralPath $tempEnvPath
    $tempEnvAcl.SetAccessRuleProtection($true, $false)
    $tempEnvAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
            $currentSid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow
        )))
    Set-Acl -LiteralPath $tempEnvPath -AclObject $tempEnvAcl

    $url = "https://$qaRef.supabase.co/functions/v1/send-message-push"
    $sqlUrl = $url.Replace("'", "''")
    $sqlSecret = $webhookSecret.Replace("'", "''")
    $sql = @"
do `$`$
declare
  url_id uuid;
  secret_id uuid;
begin
  select id into url_id from vault.secrets
    where name = 'relio_message_push_webhook_url'
    order by created_at desc limit 1;
  if url_id is null then
    perform vault.create_secret('$sqlUrl', 'relio_message_push_webhook_url', 'RELIO QA message push endpoint', null);
  else
    perform vault.update_secret(url_id, '$sqlUrl', 'relio_message_push_webhook_url', 'RELIO QA message push endpoint', null);
  end if;

  select id into secret_id from vault.secrets
    where name = 'relio_message_push_webhook_secret'
    order by created_at desc limit 1;
  if secret_id is null then
    perform vault.create_secret('$sqlSecret', 'relio_message_push_webhook_secret', 'RELIO QA database webhook authorization', null);
  else
    perform vault.update_secret(secret_id, '$sqlSecret', 'relio_message_push_webhook_secret', 'RELIO QA database webhook authorization', null);
  end if;
end
`$`$;
"@
    [IO.File]::WriteAllText($tempSqlPath, $sql, [Text.UTF8Encoding]::new($false))
    foreach ($path in @($tempSqlPath)) {
        $fileAcl = Get-Acl -LiteralPath $path
        $fileAcl.SetAccessRuleProtection($true, $false)
        $fileAcl.SetAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
                $currentSid,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            )))
        Set-Acl -LiteralPath $path -AclObject $fileAcl
    }

    Write-Host 'Setting QA-only Edge Function secrets from an ACL-protected temporary env file...'
    & npx --yes supabase secrets set --env-file $tempEnvPath --project-ref $qaRef
    if ($LASTEXITCODE -ne 0) { throw 'Setting RELIO-QA Edge Function secrets failed.' }

    Write-Host 'Updating only the two named RELIO-QA Vault webhook secrets...'
    & npx --yes supabase db query --linked --project-ref $qaRef --file $tempSqlPath --output-format json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'RELIO-QA webhook Vault configuration failed.' }

    Write-Host 'Deploying only send-message-push to the verified RELIO-QA project...'
    & npx --yes supabase functions deploy send-message-push --no-verify-jwt --use-api --project-ref $qaRef
    if ($LASTEXITCODE -ne 0) { throw 'RELIO-QA push Edge Function deployment failed.' }
} finally {
    foreach ($path in @($tempEnvPath, $tempSqlPath)) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}

Write-Host 'Configured RELIO-QA push secrets, Vault webhook settings, and send-message-push deployment without printing secret values.'
