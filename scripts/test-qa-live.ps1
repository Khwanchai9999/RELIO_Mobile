[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
if ([IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\') -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}
. (Join-Path $PSScriptRoot 'import-qa-local-env.ps1')
$qaRef = $env:RELIO_SUPABASE_QA_PROJECT_REF
$qaUrl = $env:RELIO_SUPABASE_QA_URL.TrimEnd('/')
$anonKey = $env:RELIO_SUPABASE_QA_ANON_KEY
$serviceKey = $env:RELIO_SUPABASE_QA_SERVICE_ROLE_KEY
$allowlist = Get-Content -Raw (Join-Path $projectRoot 'supabase\qa-project-allowlist.json') | ConvertFrom-Json
if ($allowlist.qaProjectRef -ne $qaRef -or $qaRef -ne 'zeuiqspvqiplusiugcto' -or
    $qaUrl -ne "https://$qaRef.supabase.co") {
    throw 'QA test target does not match the verified project allowlist.'
}
$projectOutput = & npx --yes supabase projects list --output-format json
if ($LASTEXITCODE -ne 0) { throw 'Authenticated Supabase project verification failed.' }
$projectListing = ($projectOutput -join "`n") | ConvertFrom-Json
$matches = @($projectListing.projects | Where-Object {
    $_.ref -eq $qaRef -and $_.name -eq 'RELIO-QA' -and
    $_.region -eq 'ap-southeast-1' -and $_.status -eq 'ACTIVE_HEALTHY'
})
if ($matches.Count -ne 1) { throw 'Exact RELIO-QA identity/status verification failed.' }
if ([string]::IsNullOrWhiteSpace($anonKey) -or [string]::IsNullOrWhiteSpace($serviceKey)) {
    throw 'Required local QA credentials are not configured.'
}

function Invoke-QaApi {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Token,
        [object]$Body = $null,
        [string]$Prefer = ''
    )
    $headers = @{
        apikey = $anonKey
        Authorization = "Bearer $Token"
        Accept = 'application/json'
    }
    if ($Prefer) { $headers.Prefer = $Prefer }
    $request = @{
        Method = $Method
        Uri = "$qaUrl$Path"
        Headers = $headers
        TimeoutSec = 30
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 12 -Compress
    }
    try {
        $data = Invoke-RestMethod @request
        return [PSCustomObject]@{ Status = 200; Data = $data }
    } catch {
        $status = 0
        if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
        return [PSCustomObject]@{ Status = $status; Data = $null }
    }
}

function Assert-Qa {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
    Write-Output "PASS $Message"
}

function Assert-Denied {
    param($Response, [string]$Message)
    $denied = $Response.Status -ge 400 -and $Response.Status -lt 500
    if ($Response.Status -eq 200 -and $null -ne $Response.Data) {
        $denied = @($Response.Data).Count -eq 0
    }
    Assert-Qa -Condition $denied -Message $Message
}

$identities = @(
    @{ Label = 'User A'; Email = $env:RELIO_QA_USER_EMAIL; Password = $env:RELIO_QA_USER_PASSWORD; Role = 'user' },
    @{ Label = 'User B'; Email = $env:RELIO_QA_USER_B_EMAIL; Password = $env:RELIO_QA_USER_B_PASSWORD; Role = 'user' },
    @{ Label = 'Rescuer'; Email = $env:RELIO_QA_RESCUER_EMAIL; Password = $env:RELIO_QA_RESCUER_PASSWORD; Role = 'rescuer' },
    @{ Label = 'QA Admin'; Email = $env:RELIO_QA_ADMIN_EMAIL; Password = $env:RELIO_QA_ADMIN_PASSWORD; Role = 'admin' }
)
$sessions = @{}
foreach ($identity in $identities) {
    $login = Invoke-QaApi -Method Post -Path '/auth/v1/token?grant_type=password' -Token $anonKey `
        -Body @{ email = $identity.Email; password = $identity.Password }
    if ($login.Status -ne 200 -or [string]::IsNullOrWhiteSpace([string]$login.Data.access_token)) {
        throw "QA login failed for $($identity.Label); response details and credentials are suppressed."
    }
    $sessions[$identity.Label] = @{ Token = [string]$login.Data.access_token; Id = [string]$login.Data.user.id }
    $profile = Invoke-QaApi -Method Get -Path "/rest/v1/profiles?select=id,role&id=eq.$($sessions[$identity.Label].Id)" `
        -Token $sessions[$identity.Label].Token
    $rows = @($profile.Data)
    Assert-Qa -Condition ($profile.Status -eq 200 -and $rows.Count -eq 1 -and $rows[0].role -eq $identity.Role) `
        -Message "$($identity.Label) authenticated and has expected own profile role"
}

$a = $sessions['User A']
$b = $sessions['User B']
$third = $sessions['Rescuer']
$admin = $sessions['QA Admin']

$ownUpdate = Invoke-QaApi -Method Patch -Path "/rest/v1/profiles?id=eq.$($a.Id)" -Token $a.Token `
    -Body @{ display_name = 'RELIO Test User A'; updated_at = [DateTime]::UtcNow.ToString('o') } -Prefer 'return=representation'
Assert-Qa -Condition ($ownUpdate.Status -eq 200) -Message 'User A can update an allowed own-profile field'
$selfPromote = Invoke-QaApi -Method Patch -Path "/rest/v1/profiles?id=eq.$($a.Id)" -Token $a.Token `
    -Body @{ role = 'admin' } -Prefer 'return=representation'
Assert-Denied -Response $selfPromote -Message 'User A cannot self-promote to admin'
$crossProfile = Invoke-QaApi -Method Patch -Path "/rest/v1/profiles?id=eq.$($b.Id)" -Token $a.Token `
    -Body @{ display_name = 'unauthorized' } -Prefer 'return=representation'
if ($crossProfile.Status -notin @(200, 204, 403)) { throw 'Unexpected status during cross-profile update test.' }
$bProfile = Invoke-QaApi -Method Get -Path "/rest/v1/profiles?select=id,role,display_name&id=eq.$($b.Id)" -Token $admin.Token
Assert-Qa -Condition (@($bProfile.Data).Count -eq 1 -and $bProfile.Data[0].display_name -eq 'RELIO Test User B') `
    -Message 'User A cannot modify User B profile'
$privateProfile = Invoke-QaApi -Method Get -Path "/rest/v1/profiles?select=id&id=eq.$($b.Id)" -Token $a.Token
Assert-Qa -Condition (@($privateProfile.Data).Count -eq 0) -Message 'User A cannot read User B private profile'

$conversationResponse = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/create_or_get_direct_conversation' -Token $a.Token `
    -Body @{ target_user_id = $b.Id }
if ($conversationResponse.Status -ne 200) { throw 'Direct conversation creation failed.' }
$conversation = @($conversationResponse.Data)[0]
$conversationId = [string]$conversation.conversation_id
if (-not $conversationId) { throw 'Direct conversation RPC returned no stable conversation identity.' }
$repeatResponse = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/create_or_get_direct_conversation' -Token $b.Token `
    -Body @{ target_user_id = $a.Id }
$repeat = @($repeatResponse.Data)[0]
Assert-Qa -Condition ($repeatResponse.Status -eq 200 -and $repeat.conversation_id -eq $conversationId) `
    -Message 'Direct conversation get/create is canonical and idempotent A↔B'
$conversationRead = Invoke-QaApi -Method Get -Path "/rest/v1/conversations?select=id&id=eq.$conversationId" -Token $a.Token
Assert-Qa -Condition (@($conversationRead.Data).Count -eq 1) -Message 'A/B members can read their direct conversation'
$thirdConversation = Invoke-QaApi -Method Get -Path "/rest/v1/conversations?select=id&id=eq.$conversationId" -Token $third.Token
Assert-Qa -Condition (@($thirdConversation.Data).Count -eq 0) -Message 'Third user cannot read the A/B conversation'

function New-QaMessage {
    param([string]$Id, [string]$SenderId, [string]$Token, [string]$Content)
    return Invoke-QaApi -Method Post -Path '/rest/v1/messages?select=id,conversation_id,sender_id,content,created_at' `
        -Token $Token -Body @{
            id = $Id
            conversation_id = $conversationId
            sender_id = $SenderId
            message_type = 'text'
            content = $Content
            is_outgoing = $false
        } -Prefer 'return=representation'
}

$m1 = [guid]::NewGuid().ToString()
$sendA = New-QaMessage -Id $m1 -SenderId $a.Id -Token $a.Token -Content 'QA controlled A to B message'
if ($sendA.Status -ne 200 -or @($sendA.Data).Count -ne 1 -or -not $sendA.Data[0].created_at) {
    throw 'A→B message insert did not return one server-timestamped message.'
}
$readByB = Invoke-QaApi -Method Get -Path "/rest/v1/messages?select=id,content,created_at&id=eq.$m1" -Token $b.Token
Assert-Qa -Condition (@($readByB.Data).Count -eq 1 -and $readByB.Data[0].content -eq 'QA controlled A to B message') `
    -Message 'User B reads the single A→B Cloud message'
$duplicate = New-QaMessage -Id $m1 -SenderId $a.Id -Token $a.Token -Content 'QA controlled A to B message'
Assert-Denied -Response $duplicate -Message 'Duplicate message UUID is rejected'
$conflict = New-QaMessage -Id $m1 -SenderId $a.Id -Token $a.Token -Content 'conflicting content'
Assert-Denied -Response $conflict -Message 'Conflicting content under an existing message UUID is rejected'
$spoof = New-QaMessage -Id ([guid]::NewGuid().ToString()) -SenderId $b.Id -Token $a.Token -Content 'spoof'
Assert-Denied -Response $spoof -Message 'Sender spoofing is denied'
$thirdRead = Invoke-QaApi -Method Get -Path "/rest/v1/messages?select=id&id=eq.$m1" -Token $third.Token
Assert-Qa -Condition (@($thirdRead.Data).Count -eq 0) -Message 'Third user cannot read A/B messages'
$thirdInsert = New-QaMessage -Id ([guid]::NewGuid().ToString()) -SenderId $third.Id -Token $third.Token -Content 'unauthorized'
Assert-Denied -Response $thirdInsert -Message 'Third user cannot insert into the A/B conversation'
$immutable = Invoke-QaApi -Method Patch -Path "/rest/v1/messages?id=eq.$m1" -Token $a.Token -Body @{ content = 'mutated' }
Assert-Denied -Response $immutable -Message 'Message content is immutable after insert'

$m2 = [guid]::NewGuid().ToString()
$sendB = New-QaMessage -Id $m2 -SenderId $b.Id -Token $b.Token -Content 'QA controlled B to A reply'
$readByA = Invoke-QaApi -Method Get -Path "/rest/v1/messages?select=id,content&id=eq.$m2" -Token $a.Token
Assert-Qa -Condition ($sendB.Status -eq 200 -and @($readByA.Data).Count -eq 1) `
    -Message 'User A receives the single B→A Cloud message'

$receipt = Invoke-QaApi -Method Post -Path '/rest/v1/message_receipts?select=message_id,reader_id,read_at' -Token $b.Token `
    -Body @{ message_id = $m1; reader_id = $b.Id } -Prefer 'return=representation'
if ($receipt.Status -ne 200 -or @($receipt.Data).Count -ne 1 -or -not $receipt.Data[0].read_at) {
    throw 'B read receipt was not accepted with a server timestamp.'
}
$receiptSeen = Invoke-QaApi -Method Get -Path "/rest/v1/message_receipts?select=message_id,reader_id,read_at&message_id=eq.$m1" -Token $a.Token
Assert-Qa -Condition (@($receiptSeen.Data).Count -eq 1 -and $receiptSeen.Data[0].reader_id -eq $b.Id) `
    -Message 'A observes B read receipt'
$thirdReceipt = Invoke-QaApi -Method Get -Path "/rest/v1/message_receipts?select=message_id&message_id=eq.$m1" -Token $third.Token
Assert-Qa -Condition (@($thirdReceipt.Data).Count -eq 0) -Message 'Third user cannot read A/B receipts'
$forgedReceipt = Invoke-QaApi -Method Post -Path '/rest/v1/message_receipts' -Token $third.Token `
    -Body @{ message_id = $m2; reader_id = $b.Id } -Prefer 'return=minimal'
Assert-Denied -Response $forgedReceipt -Message 'Third user cannot forge a B read receipt'

$pageIds = [Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt 5; $i++) {
    $id = [guid]::NewGuid().ToString()
    $created = New-QaMessage -Id $id -SenderId $a.Id -Token $a.Token -Content "QA page fixture $i"
    if ($created.Status -ne 200) { throw 'Could not create controlled pagination fixture.' }
    $pageIds.Add($id)
}
$currentMessageIds = @($m1, $m2) + $pageIds.ToArray()
$messageFilter = [Uri]::EscapeDataString('(' + ($currentMessageIds -join ',') + ')')
$pageOne = Invoke-QaApi -Method Get -Path "/rest/v1/messages?select=id,created_at&id=in.$messageFilter&order=created_at.asc,id.asc&limit=3&offset=0" -Token $a.Token
$pageTwo = Invoke-QaApi -Method Get -Path "/rest/v1/messages?select=id,created_at&id=in.$messageFilter&order=created_at.asc,id.asc&limit=3&offset=3" -Token $a.Token
$pageThree = Invoke-QaApi -Method Get -Path "/rest/v1/messages?select=id,created_at&id=in.$messageFilter&order=created_at.asc,id.asc&limit=3&offset=6" -Token $a.Token
$firstIds = @($pageOne.Data | ForEach-Object { [string]$_.id })
$secondIds = @($pageTwo.Data | ForEach-Object { [string]$_.id })
$thirdIds = @($pageThree.Data | ForEach-Object { [string]$_.id })
Assert-Qa -Condition ($firstIds.Count -eq 3 -and $secondIds.Count -eq 3 -and $thirdIds.Count -eq 1 -and (@($firstIds + $secondIds + $thirdIds | Select-Object -Unique).Count -eq 7)) `
    -Message 'Cloud message pagination returns bounded distinct ordered pages'

$receiptIds = @($m2) + $pageIds.ToArray()
foreach ($id in $receiptIds) {
    $newReceipt = Invoke-QaApi -Method Post -Path '/rest/v1/message_receipts?select=message_id,reader_id,read_at' -Token $b.Token `
        -Body @{ message_id = $id; reader_id = $b.Id } -Prefer 'return=representation'
    if ($newReceipt.Status -ne 200) { throw 'Could not create controlled receipt-cursor fixture.' }
}
$cursor = @{ target_conversation_id = $conversationId; after_read_at = $null; after_message_id = $null; after_reader_id = $null; page_size = 2 }
$receiptRows = [Collections.Generic.List[object]]::new()
for ($page = 0; $page -lt 1000; $page++) {
    $cursorResponse = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/fetch_conversation_read_receipts' -Token $a.Token -Body $cursor
    if ($cursorResponse.Status -ne 200) { throw 'Read-receipt cursor RPC failed.' }
    $rows = @($cursorResponse.Data)
    foreach ($row in $rows) { $receiptRows.Add($row) }
    if ($rows.Count -lt 2) { break }
    $last = $rows[-1]
    $lastReadAt = if ($last.read_at -is [DateTime]) {
        $last.read_at.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    } else {
        [string]$last.read_at
    }
    $cursor.after_read_at = $lastReadAt
    $cursor.after_message_id = [string]$last.message_id
    $cursor.after_reader_id = [string]$last.reader_id
    if ($page -eq 999) { throw 'Receipt cursor did not terminate within the QA safety bound.' }
}
if ($receiptRows.Count -ne @($receiptRows | ForEach-Object { "$($_.message_id):$($_.reader_id)" } | Select-Object -Unique).Count) {
    throw 'Receipt cursor pagination returned a duplicate tuple.'
}
$observedReceiptIds = @($receiptRows | ForEach-Object { [string]$_.message_id } | Select-Object -Unique)
$expectedReceiptIds = @($currentMessageIds | ForEach-Object { [string]$_ })
$missingReceiptIds = @($expectedReceiptIds | Where-Object { $observedReceiptIds -notcontains $_ })
$orderedTimes = @($receiptRows | ForEach-Object {
    if ($_.read_at -is [DateTime]) { $_.read_at.ToUniversalTime().Ticks } else { [DateTimeOffset]::Parse([string]$_.read_at).UtcDateTime.Ticks }
})
$isOrdered = $true
for ($i = 1; $i -lt $orderedTimes.Count; $i++) { if ($orderedTimes[$i] -lt $orderedTimes[$i - 1]) { $isOrdered = $false } }
Assert-Qa -Condition ($missingReceiptIds.Count -eq 0 -and $isOrdered -and $receiptRows.Count -ge 7) `
    -Message 'Bounded receipt cursor pages cover every current QA receipt in server order without duplicates'
$firstReadAt = $receiptRows[0].read_at
if ($firstReadAt -is [DateTime]) {
    $firstReadAt = $firstReadAt.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
}
$partialCursor = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/fetch_conversation_read_receipts' -Token $a.Token `
    -Body @{ target_conversation_id = $conversationId; after_read_at = [string]$firstReadAt; after_message_id = $null; after_reader_id = $null; page_size = 2 }
Assert-Denied -Response $partialCursor -Message 'Partial receipt cursor tuple is rejected'
$unboundedCursor = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/fetch_conversation_read_receipts' -Token $a.Token `
    -Body @{ target_conversation_id = $conversationId; after_read_at = $null; after_message_id = $null; after_reader_id = $null; page_size = 1000 }
Assert-Denied -Response $unboundedCursor -Message 'Oversized receipt cursor page is rejected'

$attachmentId = [guid]::NewGuid().ToString()
$attachment = Invoke-QaApi -Method Post -Path '/rest/v1/attachments?select=id' -Token $a.Token `
    -Body @{ id = $attachmentId; message_id = $m1; owner_user_id = $a.Id; storage_path = "users/$($a.Id)/qa-rsl-$attachmentId.png"; media_type = 'image'; mime_type = 'image/png'; file_name = 'qa-fixture.png'; byte_size = 0 } `
    -Prefer 'return=representation'
if ($attachment.Status -ne 200) { throw 'A/B member could not create controlled attachment metadata.' }
$thirdAttachment = Invoke-QaApi -Method Get -Path "/rest/v1/attachments?select=id&id=eq.$attachmentId" -Token $third.Token
Assert-Qa -Condition (@($thirdAttachment.Data).Count -eq 0) -Message 'Third user cannot read A/B attachment metadata'

function Invoke-QaStorage {
    param([string]$Method, [string]$ObjectPath, [string]$Token, [string]$Content = '')
    $headers = @{ apikey = $anonKey; Authorization = "Bearer $Token" }
    $request = @{
        UseBasicParsing = $true
        Method = $Method
        Uri = "$qaUrl$ObjectPath"
        Headers = $headers
        TimeoutSec = 30
        ErrorAction = 'Stop'
    }
    if ($Method -eq 'POST') {
        $request.ContentType = 'text/plain'
        $request.Body = $Content
    } elseif ($Method -eq 'DELETE') {
        $request.ContentType = 'application/json'
        $request.Body = ConvertTo-Json -InputObject @{ prefixes = @($Content) } -Compress
    }
    try {
        $response = Invoke-WebRequest @request
        return [int]$response.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

$storageName = "users/$($a.Id)/qa-live-$([guid]::NewGuid().ToString('N')).txt"
$storagePath = "/storage/v1/object/relio-media/$storageName"
$storageUploadStatus = Invoke-QaStorage -Method POST -ObjectPath $storagePath -Token $a.Token -Content 'RELIO QA storage policy fixture'
if ($storageUploadStatus -notin @(200, 201)) { throw 'User A could not upload a controlled private-storage fixture.' }
$storageOwnerReadStatus = Invoke-QaStorage -Method GET -ObjectPath $storagePath -Token $a.Token
Assert-Qa -Condition ($storageOwnerReadStatus -eq 200) -Message 'Storage owner can retrieve its private QA object'
$storageThirdReadStatus = Invoke-QaStorage -Method GET -ObjectPath $storagePath -Token $third.Token
Assert-Qa -Condition ($storageThirdReadStatus -in @(400, 403, 404)) -Message 'Third user is denied private QA object access'
$storageCleanupStatus = Invoke-QaStorage -Method DELETE -ObjectPath '/storage/v1/object/relio-media' -Token $serviceKey -Content $storageName
if ($storageCleanupStatus -notin @(200, 204)) {
    Write-Warning 'The disposable private-storage fixture could not be removed; it remains under the RELIO-QA-only test path.'
}

$report = Invoke-QaApi -Method Post -Path '/rest/v1/user_reports?select=id' -Token $a.Token `
    -Body @{ reporter_id = $a.Id; issue_code = 'technical'; state = 'open' } -Prefer 'return=representation'
if ($report.Status -ne 200 -or @($report.Data).Count -ne 1) { throw 'User A could not create a controlled QA report fixture.' }
$reportId = [string]$report.Data[0].id
$userAdminRpc = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/admin_set_report_state' -Token $a.Token `
    -Body @{ target_report_id = $reportId; next_state = 'reviewing' }
Assert-Denied -Response $userAdminRpc -Message 'Normal user cannot invoke audited Admin report-state RPC'
$adminRpc = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/admin_set_report_state' -Token $admin.Token `
    -Body @{ target_report_id = $reportId; next_state = 'reviewing' }
Assert-Qa -Condition ($adminRpc.Status -eq 200) -Message 'QA Admin report-state RPC succeeds'
$audit = Invoke-QaApi -Method Get -Path "/rest/v1/admin_audit_logs?select=id,action,target_id&target_id=eq.$reportId" -Token $admin.Token
Assert-Qa -Condition (@($audit.Data | Where-Object { $_.action -eq 'report_status_changed' }).Count -eq 1) `
    -Message 'Admin report-state action creates an audit row'
$normalAudit = Invoke-QaApi -Method Get -Path '/rest/v1/admin_audit_logs?select=id&limit=1' -Token $a.Token
Assert-Qa -Condition (@($normalAudit.Data).Count -eq 0) -Message 'Normal user cannot read Admin audit rows'
$normalAdminCounts = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/admin_dashboard_counts' -Token $a.Token -Body @{}
Assert-Denied -Response $normalAdminCounts -Message 'Normal user cannot invoke Admin dashboard RPC'
$adminCounts = Invoke-QaApi -Method Post -Path '/rest/v1/rpc/admin_dashboard_counts' -Token $admin.Token -Body @{}
Assert-Qa -Condition ($adminCounts.Status -eq 200) -Message 'QA Admin can invoke Admin dashboard RPC'

$deviceId = "qa-live-$([guid]::NewGuid().ToString('N'))"
$pushToken = Invoke-QaApi -Method Post -Path '/rest/v1/device_push_tokens?select=id,owner_user_id' -Token $a.Token `
    -Body @{ owner_user_id = $a.Id; device_id = $deviceId; token = "QA-NOT-A-REAL-FCM-TOKEN-$deviceId"; platform = 'android' } `
    -Prefer 'return=representation'
if ($pushToken.Status -ne 200 -or @($pushToken.Data).Count -ne 1) { throw 'User A could not register its own QA push-token fixture.' }
$forgedPushToken = Invoke-QaApi -Method Post -Path '/rest/v1/device_push_tokens' -Token $a.Token `
    -Body @{ owner_user_id = $b.Id; device_id = $deviceId; token = "QA-FORGED-$deviceId"; platform = 'android' } -Prefer 'return=minimal'
Assert-Denied -Response $forgedPushToken -Message 'User A cannot assign a push token to User B'
$bReadsPushToken = Invoke-QaApi -Method Get -Path "/rest/v1/device_push_tokens?select=id&id=eq.$($pushToken.Data[0].id)" -Token $b.Token
Assert-Qa -Condition (@($bReadsPushToken.Data).Count -eq 0) -Message 'User B cannot read User A push-token row'
$adminReadsPushToken = Invoke-QaApi -Method Get -Path "/rest/v1/device_push_tokens?select=token&id=eq.$($pushToken.Data[0].id)" -Token $admin.Token
Assert-Qa -Condition (@($adminReadsPushToken.Data).Count -eq 0) -Message 'Admin client cannot retrieve raw push tokens'
$pushTokenCleanup = Invoke-QaApi -Method Delete -Path "/rest/v1/device_push_tokens?device_id=eq.$deviceId" `
    -Token $a.Token -Prefer 'return=minimal'
Assert-Qa -Condition ($pushTokenCleanup.Status -in @(200, 204)) `
    -Message 'Synthetic QA push-token fixture is removed after ownership checks'

$sortedUserIds = @([string]$a.Id, [string]$b.Id)
[Array]::Sort($sortedUserIds, [StringComparer]::Ordinal)
$directKey = $sortedUserIds -join ':'
$directKeyRead = Invoke-QaApi -Method Get -Path "/rest/v1/conversations?select=id&direct_key=eq.$([Uri]::EscapeDataString($directKey))" -Token $serviceKey
Assert-Qa -Condition (@($directKeyRead.Data).Count -eq 1) -Message 'Database contains one canonical A/B direct conversation'

Write-Output 'RELIO-QA live RLS and Cloud REST checks completed. Fixture rows are isolated to the disposable RELIO-QA project.'
