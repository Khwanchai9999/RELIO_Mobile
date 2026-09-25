[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$androidRoot = Join-Path $projectRoot 'android'
$keystorePath = Join-Path $androidRoot 'relio-test.keystore'
$propertiesPath = Join-Path $androidRoot 'key.properties'

if ((Test-Path -LiteralPath $keystorePath) -or (Test-Path -LiteralPath $propertiesPath)) {
    throw 'Test signing files already exist. Refusing to overwrite them.'
}

$keytoolCommand = Get-Command keytool -ErrorAction SilentlyContinue
$keytoolPath = $keytoolCommand.Source
if (-not $keytoolPath) {
    $androidStudioKeytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
    if (Test-Path -LiteralPath $androidStudioKeytool) {
        $keytoolPath = $androidStudioKeytool
    }
}
if (-not $keytoolPath) {
    throw 'keytool was not found. Install or configure a JDK before creating test signing.'
}

$randomBytes = [byte[]]::new(24)
[Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$password = [Convert]::ToHexString($randomBytes)

try {
    & $keytoolPath -genkeypair -v -noprompt `
        -keystore $keystorePath `
        -storepass $password `
        -keypass $password `
        -alias 'relio-test' `
        -keyalg RSA `
        -keysize 2048 `
        -validity 10000 `
        -dname 'CN=RELIO Test, OU=Mobile, O=RELIO, L=Bangkok, ST=Bangkok, C=TH'
    if ($LASTEXITCODE -ne 0) {
        throw 'keytool failed to create the test keystore.'
    }

    $properties = @"
storePassword=$password
keyPassword=$password
keyAlias=relio-test
storeFile=relio-test.keystore
"@
    [IO.File]::WriteAllText($propertiesPath, $properties.Trim() + [Environment]::NewLine)
    Write-Host 'Created ignored test signing files under android/. Back up the keystore and password securely.'
}
catch {
    Remove-Item -LiteralPath $keystorePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $propertiesPath -Force -ErrorAction SilentlyContinue
    throw
}
