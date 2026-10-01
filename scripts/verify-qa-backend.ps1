[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$currentRoot = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\')
if ($currentRoot -ne $projectRoot) {
    throw "Run this command from the project root: $projectRoot"
}

$qaRef = $env:RELIO_SUPABASE_QA_PROJECT_REF
$prodRef = $env:RELIO_SUPABASE_PROD_PROJECT_REF
$accessToken = $env:SUPABASE_ACCESS_TOKEN
$allowlistPath = Join-Path $projectRoot 'supabase\qa-project-allowlist.json'
if (-not (Test-Path -LiteralPath $allowlistPath)) {
    throw 'The reviewed QA project allowlist is missing; no network request was made.'
}
$allowlist = Get-Content -Raw -LiteralPath $allowlistPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($qaRef) -or [string]::IsNullOrWhiteSpace($prodRef)) {
    throw 'Set both verified RELIO_SUPABASE_QA_PROJECT_REF and RELIO_SUPABASE_PROD_PROJECT_REF; no network request was made.'
}
if ($qaRef -notmatch '^[a-z0-9-]{10,40}$' -or $prodRef -notmatch '^[a-z0-9-]{10,40}$' -or $qaRef -eq $prodRef) {
    throw 'QA/PROD project refs are malformed or identical; refusing all checks.'
}
if ([string]::IsNullOrWhiteSpace([string]$allowlist.qaProjectRef) -or $qaRef -ne [string]$allowlist.qaProjectRef) {
    throw 'Configured QA ref does not match the independently reviewed allowlist; refusing all checks.'
}
if ([string]::IsNullOrWhiteSpace($accessToken)) {
    throw 'SUPABASE_ACCESS_TOKEN is required for read-only Management API checks; no credential was read from disk.'
}

# ส่ง Management API token ไป Supabase เท่านั้น และไม่แสดงหรือบันทึกค่าลง output
$headers = @{ Authorization = "Bearer $accessToken"; Accept = 'application/json' }
function Invoke-ManagementGet {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        return Invoke-RestMethod -Method Get -Uri "https://api.supabase.com/v1$Path" -Headers $headers -TimeoutSec 30
    } catch {
        throw "Supabase read-only request failed for $Path (response details suppressed). Check token scope and network access."
    }
}

Write-Host "Checking verified QA Supabase project $qaRef (PROD ref is distinct)."
$projects = @(Invoke-ManagementGet -Path '/projects')
$qaProject = @($projects | Where-Object { $_.ref -eq $qaRef -or $_.id -eq $qaRef } | Select-Object -First 1)[0]
$prodProject = @($projects | Where-Object { $_.ref -eq $prodRef -or $_.id -eq $prodRef } | Select-Object -First 1)[0]
if ($null -eq $qaProject) { throw 'The allowlisted QA ref is not visible to this Supabase account.' }
if ($null -eq $prodProject) { throw 'The configured PROD ref is not visible; refusing to claim QA/PROD separation.' }
if ($qaProject.status -and $qaProject.status -notin @('ACTIVE_HEALTHY', 'ACTIVE')) {
    throw "QA Supabase project is not active (status $($qaProject.status))."
}
Write-Host "Verified Supabase account identity: QA=$qaRef; PROD=$prodRef; QA status=$($qaProject.status)."

$localVersions = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'supabase\migrations') -Filter '*.sql' -File |
    ForEach-Object { [regex]::Match($_.Name, '^(\d+)_').Groups[1].Value } |
    Where-Object { $_ } | Sort-Object -Unique)
if ($localVersions.Count -eq 0) { throw 'No local SQL migrations were found.' }
$remoteMigrations = Invoke-ManagementGet -Path "/projects/$qaRef/database/migrations"
if ($remoteMigrations -is [System.Collections.IDictionary] -and $remoteMigrations.Contains('migrations')) {
    $remoteMigrations = $remoteMigrations.migrations
}
$remoteVersions = @($remoteMigrations | ForEach-Object { [string]$_.version } | Where-Object { $_ } | Sort-Object -Unique)
$missingVersions = @($localVersions | Where-Object { $remoteVersions -notcontains $_ })
if ($missingVersions.Count -gt 0) {
    throw "QA migration history is incomplete. Missing local versions: $($missingVersions -join ', '). No migration was applied."
}
Write-Host "Verified all $($localVersions.Count) local migration versions are recorded on QA."

$openApi = Invoke-ManagementGet -Path "/projects/$qaRef/database/openapi?schema=public"
$paths = @($openApi.paths.PSObject.Properties.Name)
$requiredPaths = @(
    '/profiles', '/devices', '/conversations', '/conversation_members', '/messages',
    '/message_receipts', '/device_push_tokens', '/rescue_status', '/user_reports', '/admin_audit_logs',
    '/rpc/create_or_get_direct_conversation', '/rpc/list_my_direct_conversations',
    '/rpc/fetch_conversation_read_receipts', '/rpc/admin_dashboard_counts',
    '/rpc/admin_set_user_role', '/rpc/admin_set_sos_state',
    '/rpc/admin_set_report_state'
)
$missingPaths = @($requiredPaths | Where-Object { $paths -notcontains $_ })
if ($missingPaths.Count -gt 0) {
    throw "QA PostgREST schema is missing required resources: $($missingPaths -join ', ')."
}
Write-Host "Verified required QA REST tables and RPCs ($($requiredPaths.Count) paths)."

$qaBaseUrl = "https://$qaRef.supabase.co"
try {
    $health = Invoke-WebRequest -UseBasicParsing -Uri "$qaBaseUrl/auth/v1/health" -TimeoutSec 20
} catch {
    throw 'QA Supabase Auth health endpoint did not return a successful response.'
}
if ([int]$health.StatusCode -ne 200) { throw 'QA Supabase Auth health endpoint is not healthy.' }
Write-Host 'QA Supabase Auth health endpoint returned HTTP 200.'

$anonKey = $env:RELIO_SUPABASE_QA_ANON_KEY
$identitySpecs = @(
    @{ Label = 'User A'; Email = $env:RELIO_QA_USER_EMAIL; Password = $env:RELIO_QA_USER_PASSWORD; Role = 'user' },
    @{ Label = 'User B'; Email = $env:RELIO_QA_USER_B_EMAIL; Password = $env:RELIO_QA_USER_B_PASSWORD; Role = 'user' },
    @{ Label = 'Rescuer'; Email = $env:RELIO_QA_RESCUER_EMAIL; Password = $env:RELIO_QA_RESCUER_PASSWORD; Role = 'rescuer' },
    @{ Label = 'QA Admin'; Email = $env:RELIO_QA_ADMIN_EMAIL; Password = $env:RELIO_QA_ADMIN_PASSWORD; Role = 'admin' }
)
if ([string]::IsNullOrWhiteSpace($anonKey) -or @($identitySpecs | Where-Object {
            [string]::IsNullOrWhiteSpace($_.Email) -or [string]::IsNullOrWhiteSpace($_.Password)
        }).Count -gt 0) {
    throw 'Set the QA anon key and all four QA login identities in the process environment; no credential values are read from files.'
}

$contexts = @{}
foreach ($identity in $identitySpecs) {
    try {
        $session = Invoke-RestMethod -Method Post `
            -Uri "$qaBaseUrl/auth/v1/token?grant_type=password" `
            -Headers @{ apikey = $anonKey; Accept = 'application/json' } `
            -ContentType 'application/json' `
            -Body (ConvertTo-Json -InputObject @{ email = $identity.Email; password = $identity.Password } -Compress) `
            -TimeoutSec 30
    } catch {
        throw "QA login failed for $($identity.Label); response details and credentials are suppressed."
    }
    if ([string]::IsNullOrWhiteSpace([string]$session.access_token) -or
        [string]::IsNullOrWhiteSpace([string]$session.user.id)) {
        throw "QA login response was incomplete for $($identity.Label); no token was printed."
    }
    $contexts[$identity.Label] = @{ Token = [string]$session.access_token; UserId = [string]$session.user.id; Role = $identity.Role }
}

function Invoke-QaRead {
    param([string]$Label, [string]$Path, [string]$Token)
    try {
        return Invoke-RestMethod -Method Get -Uri "$qaBaseUrl/rest/v1$Path" `
            -Headers @{ apikey = $anonKey; Authorization = "Bearer $Token"; Accept = 'application/json' } `
            -TimeoutSec 30
    } catch {
        throw "QA read-only RLS check failed for $Label (response details suppressed)."
    }
}

foreach ($identity in $identitySpecs) {
    $context = $contexts[$identity.Label]
    $profile = @(Invoke-QaRead -Label "$($identity.Label) own profile" `
        -Path "/profiles?select=id,role&id=eq.$($context.UserId)" -Token $context.Token)
    if ($profile.Count -ne 1 -or $profile[0].id -ne $context.UserId -or $profile[0].role -ne $identity.Role) {
        throw "QA profile/RLS identity did not match the expected role for $($identity.Label)."
    }
}
Write-Host 'Verified login and own-profile role for User A, User B, Rescuer, and QA Admin.'

$userA = $contexts['User A']
$userB = $contexts['User B']
$privatePeerProfile = @(Invoke-QaRead -Label 'User A privacy boundary' `
    -Path "/profiles?select=id&id=eq.$($userB.UserId)" -Token $userA.Token)
if ($privatePeerProfile.Count -ne 0) { throw 'User A could read User B private profile data.' }
$privateAdminAudit = @(Invoke-QaRead -Label 'normal-user admin-audit boundary' `
    -Path '/admin_audit_logs?select=id&limit=1' -Token $userA.Token)
if ($privateAdminAudit.Count -ne 0) { throw 'A normal QA user could read admin audit rows.' }
$adminAudit = @(Invoke-QaRead -Label 'QA Admin audit access' `
    -Path '/admin_audit_logs?select=id&limit=1' -Token $contexts['QA Admin'].Token)
Write-Host 'Verified normal-user privacy/audit filtering and QA Admin audit read access.'

try {
    Invoke-RestMethod -Method Post -Uri "$qaBaseUrl/rest/v1/rpc/admin_dashboard_counts" `
        -Headers @{ apikey = $anonKey; Authorization = "Bearer $($userA.Token)"; Accept = 'application/json' } `
        -ContentType 'application/json' -Body '{}' -TimeoutSec 30 | Out-Null
    throw 'A normal QA user unexpectedly invoked the admin dashboard RPC.'
} catch {
    if ($_.Exception.Message -like 'A normal QA user unexpectedly*') { throw }
    $response = $_.Exception.Response
    if ($null -eq $response -or [int]$response.StatusCode -notin @(401, 403)) {
        throw 'Normal-user admin RPC denial was not confirmed (response details suppressed).'
    }
}
try {
    Invoke-RestMethod -Method Post -Uri "$qaBaseUrl/rest/v1/rpc/admin_dashboard_counts" `
        -Headers @{ apikey = $anonKey; Authorization = "Bearer $($contexts['QA Admin'].Token)"; Accept = 'application/json' } `
        -ContentType 'application/json' -Body '{}' -TimeoutSec 30 | Out-Null
} catch {
    throw 'QA Admin could not invoke the protected dashboard RPC (response details suppressed).'
}
Write-Host 'Verified normal-user denial and QA Admin access for admin_dashboard_counts.'

# ใช้ GET ตรวจ endpoint โดยไม่ส่ง webhook secret หรือข้อมูลข้อความ
try {
    $functionResponse = Invoke-WebRequest -UseBasicParsing -Uri "$qaBaseUrl/functions/v1/send-message-push" -TimeoutSec 20
    $functionStatus = [int]$functionResponse.StatusCode
} catch {
    $functionResponse = $_.Exception.Response
    if ($null -eq $functionResponse) { throw 'QA push function endpoint could not be reached.' }
    $functionStatus = [int]$functionResponse.StatusCode
}
if ($functionStatus -notin @(401, 405)) {
    throw "QA push function returned HTTP $functionStatus to a credential-free GET; expected gateway auth or method rejection."
}
Write-Host "QA push function endpoint is deployed/reachable (expected HTTP $functionStatus for credential-free GET)."

$manifestUrl = 'https://relio-17dc0.web.app/qa/latest.json'
try {
    $manifestResponse = Invoke-WebRequest -UseBasicParsing -Uri $manifestUrl -TimeoutSec 20
    $manifest = $manifestResponse.Content | ConvertFrom-Json
} catch {
    throw 'Public QA manifest could not be read (response details suppressed).'
}
if ([int]$manifestResponse.StatusCode -ne 200 -or
    $manifest.channel -ne 'qa-public' -or
    $manifest.packageName -ne 'com.relio.relio_mobile.test' -or
    $manifest.versionName -ne '0.9.0' -or
    [int]$manifest.versionCode -ne 23 -or
    $manifest.apkUrl -notmatch '^https://github\.com/Khwanchai9999/RELIO-Android-Updates/releases/download/') {
    throw 'Public QA manifest failed the expected Build 23, channel, package, or approved-origin validation.'
}
Write-Host "Public QA manifest is valid and currently advertises $($manifest.versionName)+$($manifest.versionCode)."
Write-Warning 'This read-only health check does not prove user-level RLS behavior, push delivery, or physical-device receipt; those require their dedicated QA checks.'
