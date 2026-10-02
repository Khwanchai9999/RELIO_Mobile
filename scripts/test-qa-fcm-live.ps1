[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$qaRef = 'zeuiqspvqiplusiugcto'
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}
. (Join-Path $PSScriptRoot 'import-qa-local-env.ps1')
if ($env:RELIO_SUPABASE_QA_PROJECT_REF -ne $qaRef -or
    $env:RELIO_QA_DATABASE_WEBHOOK_SECRET.Length -lt 32 -or
    $env:RELIO_SUPABASE_QA_URL -ne "https://$qaRef.supabase.co") {
    throw 'Local QA configuration is incomplete or points outside RELIO-QA.'
}
$allowlist = Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'supabase\qa-project-allowlist.json') | ConvertFrom-Json
if ($allowlist.qaProjectRef -ne $qaRef -or
    (Get-Content -Raw -LiteralPath (Join-Path $projectRoot 'supabase\.temp\project-ref')).Trim() -ne $qaRef) {
    throw 'The QA allowlist or linked project does not match the verified RELIO-QA ref.'
}
$projectOutput = & npx --yes supabase projects list --output-format json
if ($LASTEXITCODE -ne 0) { throw 'Authenticated Supabase project verification failed.' }
$projects = ($projectOutput -join "`n") | ConvertFrom-Json
if (@($projects.projects | Where-Object {
            $_.ref -eq $qaRef -and $_.name -eq 'RELIO-QA' -and
            $_.region -eq 'ap-southeast-1' -and $_.status -eq 'ACTIVE_HEALTHY'
        }).Count -ne 1) {
    throw 'Exact active RELIO-QA identity verification failed.'
}

$baseUrl = $env:RELIO_SUPABASE_QA_URL.TrimEnd('/')
$anonKey = $env:RELIO_SUPABASE_QA_ANON_KEY
$functionUrl = "$baseUrl/functions/v1/send-message-push"
$webhookSecret = $env:RELIO_QA_DATABASE_WEBHOOK_SECRET
function Invoke-WebhookProbe {
    param([string]$Body, [string]$HeaderSecret)

    $headers = @{ apikey = $anonKey }
    if ($null -ne $HeaderSecret) { $headers['x-relio-webhook-secret'] = $HeaderSecret }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $functionUrl `
            -Headers $headers -ContentType 'application/json' -Body $Body -TimeoutSec 30
        return [pscustomobject]@{ Status = [int]$response.StatusCode; Content = [string]$response.Content }
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response) { throw 'QA push function could not be reached.' }
        $status = [int]$response.StatusCode
        $content = ''
        try {
            $reader = [IO.StreamReader]::new($response.GetResponseStream())
            try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } catch { }
        return [pscustomobject]@{ Status = $status; Content = $content }
    }
}

$probe = Invoke-WebhookProbe -Body '{}' -HeaderSecret $null
if ($probe.Status -ne 401) { throw "Unauthenticated push webhook request returned HTTP $($probe.Status), expected 401." }
Write-Output 'PASS unauthenticated push webhook request is rejected'
$probe = Invoke-WebhookProbe -Body '{}' -HeaderSecret 'invalid-relio-webhook-secret'
if ($probe.Status -ne 401) { throw "Invalid-secret push webhook request returned HTTP $($probe.Status), expected 401." }
Write-Output 'PASS incorrect webhook secret is rejected'
$probe = Invoke-WebhookProbe -Body '{"type":"UPDATE","record":{}}' -HeaderSecret $webhookSecret
if ($probe.Status -ne 400) { throw "Malformed signed push event returned HTTP $($probe.Status), expected 400." }
Write-Output 'PASS malformed authenticated event is rejected'

$identities = @(
    @{ Label = 'User A'; Email = $env:RELIO_QA_USER_EMAIL; Password = $env:RELIO_QA_USER_PASSWORD },
    @{ Label = 'User B'; Email = $env:RELIO_QA_USER_B_EMAIL; Password = $env:RELIO_QA_USER_B_PASSWORD },
    @{ Label = 'Rescuer'; Email = $env:RELIO_QA_RESCUER_EMAIL; Password = $env:RELIO_QA_RESCUER_PASSWORD }
)
$sessions = @{}
foreach ($identity in $identities) {
    try {
        $session = Invoke-RestMethod -Method Post -Uri "$baseUrl/auth/v1/token?grant_type=password" `
            -Headers @{ apikey = $anonKey } -ContentType 'application/json' `
            -Body (ConvertTo-Json -Compress @{ email = $identity.Email; password = $identity.Password }) -TimeoutSec 30
    } catch { throw "QA authentication failed for $($identity.Label); details suppressed." }
    if (-not $session.access_token -or -not $session.user.id) { throw "QA session incomplete for $($identity.Label)." }
    $sessions[$identity.Label] = $session
}

$userA = $sessions['User A']
$userB = $sessions['User B']
$rescuer = $sessions['Rescuer']
$userAHeaders = @{ apikey = $anonKey; Authorization = "Bearer $($userA.access_token)"; Accept = 'application/json' }
$userBHeaders = @{ apikey = $anonKey; Authorization = "Bearer $($userB.access_token)"; Accept = 'application/json' }
$rescuerHeaders = @{ apikey = $anonKey; Authorization = "Bearer $($rescuer.access_token)"; Accept = 'application/json' }

$conversation = Invoke-RestMethod -Method Post -Uri "$baseUrl/rest/v1/rpc/create_or_get_direct_conversation" `
    -Headers $userAHeaders -ContentType 'application/json' `
    -Body (ConvertTo-Json -Compress @{ target_user_id = [string]$userB.user.id }) -TimeoutSec 30
$conversationId = [string]@($conversation)[0].conversation_id
if (-not $conversationId) { throw 'Could not resolve the canonical A/B QA conversation.' }

$recipientTokens = @(Invoke-RestMethod -Method Get `
    -Uri "$baseUrl/rest/v1/device_push_tokens?select=id&owner_user_id=eq.$($userA.user.id)" `
    -Headers $userAHeaders -TimeoutSec 30)
if ($recipientTokens.Count -eq 1 -and $recipientTokens[0] -is [array]) {
    $recipientTokens = @($recipientTokens[0])
}
if ($recipientTokens.Count -ne 0) {
    throw 'User A has a registered device token; refusing a live push to avoid contacting a device during this QA gate.'
}
Write-Output 'PASS no registered QA device token; no phone delivery will be attempted'

$messageId = [guid]::NewGuid().ToString()
$eventBody = ConvertTo-Json -Compress @{
    type = 'INSERT'
    schema = 'public'
    table = 'messages'
    record = @{
        id = $messageId
        conversation_id = $conversationId
        sender_id = [string]$userB.user.id
    }
}
$outsiderBody = ConvertTo-Json -Compress @{
    type = 'INSERT'
    record = @{
        id = [guid]::NewGuid().ToString()
        conversation_id = $conversationId
        sender_id = [string]$rescuer.user.id
    }
}
$probe = Invoke-WebhookProbe -Body $outsiderBody -HeaderSecret $webhookSecret
if ($probe.Status -ne 403) { throw "Non-member sender event returned HTTP $($probe.Status), expected 403." }
Write-Output 'PASS non-member sender event is denied'

$first = Invoke-WebhookProbe -Body $eventBody -HeaderSecret $webhookSecret
if ($first.Status -ne 200) { throw "Valid QA message event returned HTTP $($first.Status); FCM authorization/delivery path did not pass." }
$firstBody = $first.Content | ConvertFrom-Json
if (-not $firstBody.ok -or [int]$firstBody.deliveredRecipients -ne 1) {
    throw "Valid QA message event was not accepted for exactly one recipient ($($first.Content))."
}
Write-Output 'PASS valid signed message event accepted; server FCM credentials initialized without device delivery'

$messagePayload = @{
    id = $messageId
    conversation_id = $conversationId
    sender_id = [string]$userB.user.id
    message_type = 'text'
    content = 'RELIO QA FCM integration fixture'
    delivery_status = 'synced'
    is_outgoing = $true
}
Invoke-RestMethod -Method Post -Uri "$baseUrl/rest/v1/messages" `
    -Headers ($userBHeaders + @{ Prefer = 'return=minimal' }) -ContentType 'application/json' `
    -Body (ConvertTo-Json -Compress $messagePayload) -TimeoutSec 30 | Out-Null

$second = Invoke-WebhookProbe -Body $eventBody -HeaderSecret $webhookSecret
if ($second.Status -ne 200) { throw "Duplicate webhook event returned HTTP $($second.Status), expected idempotent HTTP 200." }
$secondBody = $second.Content | ConvertFrom-Json
if ([int]$secondBody.deliveredRecipients -ne 0) {
    throw 'Duplicate webhook event was not suppressed by the recipient/event idempotency ledger.'
}
Write-Output 'PASS duplicate webhook event is idempotently suppressed'

$ledgerSql = "select count(*)::int as rows from public.push_delivery_dedup where event_id='$messageId'::uuid and recipient_id='$($userA.user.id)'::uuid"
$ledgerOutput = & npx --yes supabase db query --linked --project-ref $qaRef --output-format json $ledgerSql
if ($LASTEXITCODE -ne 0) { throw 'Read-only QA push idempotency ledger query failed.' }
$ledgerText = $ledgerOutput -join "`n"
$ledgerStart = $ledgerText.IndexOf([char]'{')
$ledgerEnd = $ledgerText.LastIndexOf([char]'}')
if ($ledgerStart -lt 0 -or $ledgerEnd -lt $ledgerStart) { throw 'QA push ledger query returned invalid JSON.' }
$ledger = $ledgerText.Substring($ledgerStart, $ledgerEnd - $ledgerStart + 1) | ConvertFrom-Json
if ([int]$ledger.rows[0].rows -ne 1) { throw 'Expected exactly one QA recipient/event idempotency row.' }
Write-Output 'PASS server-side event/recipient idempotency ledger contains one row'
Write-Output 'RELIO-QA live push authorization, FCM send, retry/idempotency checks passed.'
