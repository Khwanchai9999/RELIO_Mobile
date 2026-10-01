[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\')
$qaRef = $env:RELIO_SUPABASE_QA_PROJECT_REF
$prodRef = $env:RELIO_SUPABASE_PROD_PROJECT_REF
$serviceKey = $env:RELIO_SUPABASE_QA_SERVICE_ROLE_KEY
$allowlistPath = Join-Path $projectRoot 'supabase\qa-project-allowlist.json'

if ([string]::IsNullOrWhiteSpace($qaRef) -or [string]::IsNullOrWhiteSpace($prodRef)) {
    throw 'Set both verified RELIO_SUPABASE_QA_PROJECT_REF and RELIO_SUPABASE_PROD_PROJECT_REF before seeding.'
}
if ($qaRef -notmatch '^[a-z0-9-]{10,40}$' -or $prodRef -notmatch '^[a-z0-9-]{10,40}$') {
    throw 'Supabase project refs have an invalid format; refusing to select a backend.'
}
if ($qaRef -eq $prodRef) {
    throw 'QA and PROD Supabase project refs must differ; refusing any mutation.'
}
if (-not (Test-Path -LiteralPath $allowlistPath)) {
    throw 'The reviewed Supabase QA project allowlist is missing; refusing to select a target.'
}
$allowlist = Get-Content -Raw -LiteralPath $allowlistPath | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace([string]$allowlist.qaProjectRef) -or
    $qaRef -ne [string]$allowlist.qaProjectRef) {
    throw 'Configured QA ref does not match the reviewed project allowlist; no request was made.'
}
if ($DryRun) {
    Write-Output "QA seed guard passed for configured QA ref '$qaRef'; no network request was made."
    return
}
if ([string]::IsNullOrWhiteSpace($serviceKey)) {
    throw 'RELIO_SUPABASE_QA_SERVICE_ROLE_KEY is required in the process environment; no secret file is read.'
}

$requiredNames = @(
    'RELIO_QA_USER_EMAIL', 'RELIO_QA_USER_PASSWORD',
    'RELIO_QA_USER_B_EMAIL', 'RELIO_QA_USER_B_PASSWORD',
    'RELIO_QA_RESCUER_EMAIL', 'RELIO_QA_RESCUER_PASSWORD',
    'RELIO_QA_ADMIN_EMAIL', 'RELIO_QA_ADMIN_PASSWORD'
)
foreach ($name in $requiredNames) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
        throw "Required QA seed value '$name' is missing; no backend request was made."
    }
}

$baseUrl = "https://$qaRef.supabase.co"
$headers = @{ apikey = $serviceKey; Authorization = "Bearer $serviceKey" }
$users = @(
    @{ email = $env:RELIO_QA_USER_EMAIL; password = $env:RELIO_QA_USER_PASSWORD; role = 'user'; name = 'RELIO QA User' },
    @{ email = $env:RELIO_QA_USER_B_EMAIL; password = $env:RELIO_QA_USER_B_PASSWORD; role = 'user'; name = 'RELIO QA User B' },
    @{ email = $env:RELIO_QA_RESCUER_EMAIL; password = $env:RELIO_QA_RESCUER_PASSWORD; role = 'rescuer'; name = 'RELIO QA Rescuer' },
    @{ email = $env:RELIO_QA_ADMIN_EMAIL; password = $env:RELIO_QA_ADMIN_PASSWORD; role = 'admin'; name = 'RELIO QA Admin' }
)
if (($users.email | Sort-Object -Unique).Count -ne 4) {
    throw 'The four QA identities must use distinct email addresses.'
}

function Invoke-QaRequest {
    param([string]$Method, [string]$Path, [object]$Body)
    $request = @{ Uri = "$baseUrl$Path"; Method = $Method; Headers = $headers; ErrorAction = 'Stop' }
    if ($null -ne $Body) {
        $request.ContentType = 'application/json'
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 8 -Compress
    }
    try { return Invoke-RestMethod @request }
    catch { throw "QA Supabase request failed (HTTP operation $Method $Path). Response details are suppressed to protect credentials." }
}

foreach ($user in $users) {
    $headers.Remove('Prefer')
    $page = 1
    $authUser = $null
    do {
        $list = Invoke-QaRequest -Method Get -Path "/auth/v1/admin/users?page=$page&per_page=1000" -Body $null
        $authUser = @($list.users | Where-Object { $_.email -eq $user.email } | Select-Object -First 1)[0]
        $page++
    } while ($null -eq $authUser -and $page -le 20 -and @($list.users).Count -eq 1000)

    if ($null -eq $authUser) {
        $authUser = Invoke-QaRequest -Method Post -Path '/auth/v1/admin/users' -Body @{
            email = $user.email
            password = $user.password
            email_confirm = $true
            user_metadata = @{ display_name = $user.name }
        }
        Write-Output "Created QA identity for role '$($user.role)'."
    } else {
        Write-Output "Reusing existing QA identity for role '$($user.role)'; password left unchanged."
    }
    if ([string]::IsNullOrWhiteSpace($authUser.id)) {
        throw "Supabase did not return an Auth user id for role '$($user.role)'."
    }
    $headers.Prefer = 'resolution=merge-duplicates,return=minimal'
    Invoke-QaRequest -Method Post -Path '/rest/v1/profiles?on_conflict=id' -Body @{
        id = $authUser.id
        display_name = $user.name
        role = $user.role
    } | Out-Null
    Write-Output "Ensured QA profile role '$($user.role)'."
}

Write-Output "QA identities are ready in configured project '$qaRef'. No passwords or key material were printed."
