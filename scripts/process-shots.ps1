param(
    [string]$Studio = 'E:\L4D2-Studio',
    [string]$Output = (Join-Path $PSScriptRoot '..\output'),
    [int]$Width = 1280,
    [int]$Height = 720,
    [long]$Quality = 82,
    [string]$ContactSheet = (Join-Path $PSScriptRoot '..\output\contact-sheet.jpg')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$source = Join-Path $Studio 'left4dead2\screenshots\skinshots'
$shots = 'hand', 'ground', 'ground2', 'ground3', 'third', 'third2'
$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$parameters = New-Object System.Drawing.Imaging.EncoderParameters 1
$parameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality

$skins = @($shots | ForEach-Object { Get-ChildItem (Join-Path $source $_) -Filter *.jpg -ErrorAction SilentlyContinue | ForEach-Object BaseName }) | Sort-Object -Unique
if ($skins.Count -eq 0) { throw "No screenshots in $source" }

$written = 0
foreach ($skin in $skins) {
    $folder = Join-Path $Output $skin
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($shot in $shots) {
        $file = Join-Path $source "$shot\$skin.jpg"
        if (-not (Test-Path $file)) { continue }
        $image = [System.Drawing.Image]::FromFile($file)
        $ratio = $Width / $Height
        $cropWidth = [Math]::Min($image.Width, [int]($image.Height * $ratio))
        $cropHeight = [int]($cropWidth / $ratio)
        $x = [int](($image.Width - $cropWidth) / 2)
        $y = [int](($image.Height - $cropHeight) / 2)
        $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = 'HighQualityBicubic'
        $graphics.DrawImage($image, (New-Object System.Drawing.Rectangle 0, 0, $Width, $Height), (New-Object System.Drawing.Rectangle $x, $y, $cropWidth, $cropHeight), 'Pixel')
        $bitmap.Save((Join-Path $folder "$shot.jpg"), $codec, $parameters)
        $graphics.Dispose(); $bitmap.Dispose(); $image.Dispose()
        $written++
    }
}

$cell = 320; $cellHeight = 180; $label = 18
$sheet = New-Object System.Drawing.Bitmap ($cell * $shots.Count), (($cellHeight + $label) * $skins.Count)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font 'Arial', 10, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $skins.Count; $i++) {
    $top = $i * ($cellHeight + $label)
    $graphics.DrawString($skins[$i], $font, [System.Drawing.Brushes]::Yellow, 4, $top + 2)
    for ($s = 0; $s -lt $shots.Count; $s++) {
        $file = Join-Path $Output "$($skins[$i])\$($shots[$s]).jpg"
        if (-not (Test-Path $file)) { continue }
        $image = [System.Drawing.Image]::FromFile($file)
        $graphics.DrawImage($image, $s * $cell, $top + $label, $cell, $cellHeight)
        $image.Dispose()
    }
}
$sheet.Save($ContactSheet, $codec, $parameters)
$graphics.Dispose(); $sheet.Dispose()

"$written images for $($skins.Count) skins in $Output"
"Contact sheet: $ContactSheet"