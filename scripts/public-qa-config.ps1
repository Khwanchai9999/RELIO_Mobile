function Get-RelioPublicQaUpdateConfig {
    $config = [pscustomobject]@{
        ManifestUrl = 'https://relio-17dc0.web.app/qa/latest.json'
        Owner = 'Khwanchai9999'
        Repository = 'RELIO-Android-Updates'
        Channel = 'qa-public'
        FirebaseProjectId = 'relio-17dc0'
        PackageName = 'com.relio.relio_mobile.test'
        SigningCertSha256 = 'a5b3b13122d6a8cdbef9f933b4c6fdcc292ba7345649f9f5fe8632deaff62b1d'
    }

    $manifestUri = $null
    if (-not [Uri]::TryCreate($config.ManifestUrl, [UriKind]::Absolute, [ref]$manifestUri) -or
        $manifestUri.Scheme -ne 'https' -or
        $manifestUri.Host -ne 'relio-17dc0.web.app' -or
        $manifestUri.AbsolutePath -ne '/qa/latest.json' -or
        $manifestUri.Query -or
        $manifestUri.Fragment -or
        $config.Owner -ne 'Khwanchai9999' -or
        $config.Repository -ne 'RELIO-Android-Updates' -or
        $config.Channel -ne 'qa-public' -or
        $config.FirebaseProjectId -ne 'relio-17dc0' -or
        $config.PackageName -ne 'com.relio.relio_mobile.test' -or
        $config.SigningCertSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Canonical public QA updater configuration is invalid.'
    }

    return $config
}
