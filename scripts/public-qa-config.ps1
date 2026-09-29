function Get-RelioPublicQaUpdateConfig {
    $config = [pscustomobject]@{
        ManifestUrl = 'https://relio-17dc0.web.app/qa/latest.json'
        Owner = 'Khwanchai9999'
        Repository = 'RELIO-Android-Updates'
        Channel = 'qa-public'
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
        $config.Channel -ne 'qa-public') {
        throw 'Canonical public QA updater configuration is invalid.'
    }

    return $config
}
