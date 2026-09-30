[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw "Run this check with Windows PowerShell 5.1; found $($PSVersionTable.PSVersion)."
}

$scripts = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File | Sort-Object Name)
foreach ($script in $scripts) {
    $bytes = [IO.File]::ReadAllBytes($script.FullName)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    if ($text -match '[^\x00-\x7F]' -and -not $hasBom) {
        throw "Non-ASCII PowerShell source must use UTF-8 with BOM: $($script.Name)"
    }

    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $script.FullName,
        [ref]$tokens,
        [ref]$errors
    ) | Out-Null
    if ($errors.Count -gt 0) {
        $details = ($errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; '
        throw "Windows PowerShell parser errors in $($script.Name): $details"
    }
}

Write-Host "Windows PowerShell 5.1 parsed $($scripts.Count) scripts successfully."
