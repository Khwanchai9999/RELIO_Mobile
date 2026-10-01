[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = Join-Path $projectRoot 'assets\branding\relio-logo-master.png'
$resourceRoot = Join-Path $projectRoot 'android\app\src\main\res'
if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Brand source was not found: $sourcePath"
}

Add-Type -AssemblyName System.Drawing
$source = [Drawing.Bitmap]::new($sourcePath)
try {
    if ($source.Width -ne $source.Height) {
        throw 'The RELIO master logo must be square to preserve its composition.'
    }
    $background = [Drawing.Color]::FromArgb(255, 5, 20, 43)
    $legacySizes = @{
        'mipmap-mdpi' = 48
        'mipmap-hdpi' = 72
        'mipmap-xhdpi' = 96
        'mipmap-xxhdpi' = 144
        'mipmap-xxxhdpi' = 192
    }
    foreach ($entry in $legacySizes.GetEnumerator()) {
        $directory = Join-Path $resourceRoot $entry.Key
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $bitmap = [Drawing.Bitmap]::new($entry.Value, $entry.Value)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear($background)
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
                $inset = [int][Math]::Round($entry.Value * 0.06)
                $graphics.DrawImage($source, $inset, $inset, $entry.Value - 2 * $inset, $entry.Value - 2 * $inset)
            } finally { $graphics.Dispose() }
            $bitmap.Save((Join-Path $directory 'ic_launcher.png'), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
    }

    $adaptiveSizes = @{
        'mipmap-mdpi' = 108
        'mipmap-hdpi' = 162
        'mipmap-xhdpi' = 216
        'mipmap-xxhdpi' = 324
        'mipmap-xxxhdpi' = 432
    }
    foreach ($entry in $adaptiveSizes.GetEnumerator()) {
        $directory = Join-Path $resourceRoot $entry.Key
        $bitmap = [Drawing.Bitmap]::new($entry.Value, $entry.Value, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.Clear([Drawing.Color]::Transparent)
                $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
                $side = [int][Math]::Round($entry.Value * 0.68)
                $inset = [int][Math]::Floor(($entry.Value - $side) / 2)
                $graphics.DrawImage($source, $inset, $inset, $side, $side)
            } finally { $graphics.Dispose() }
            $bitmap.Save((Join-Path $directory 'ic_launcher_foreground.png'), [Drawing.Imaging.ImageFormat]::Png)
        } finally { $bitmap.Dispose() }
    }

    $splash = [Drawing.Bitmap]::new(512, 512)
    try {
        $graphics = [Drawing.Graphics]::FromImage($splash)
        try {
            $graphics.Clear($background)
            $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
            $graphics.DrawImage($source, 56, 56, 400, 400)
        } finally { $graphics.Dispose() }
        $splashPath = Join-Path $resourceRoot 'drawable-nodpi\relio_splash.png'
        New-Item -ItemType Directory -Path (Split-Path $splashPath) -Force | Out-Null
        $splash.Save($splashPath, [Drawing.Imaging.ImageFormat]::Png)
    } finally { $splash.Dispose() }
} finally {
    $source.Dispose()
}

Write-Host 'Generated RELIO legacy/adaptive launcher icons and Android splash from the supplied master artwork.'
