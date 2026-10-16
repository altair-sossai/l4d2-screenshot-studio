param(
    [string]$Studio = 'E:\L4D2-Studio',
    [string]$Output = (Join-Path $PSScriptRoot '..\output'),
    [string]$FFmpeg = 'ffmpeg',
    [int]$Width = 1280,
    [int]$Height = 720,
    [int]$CardSize = 540,
    [int]$ThumbWidth = 320,
    [int]$ThumbHeight = 180,
    [int]$AvifCrf = 20,
    [int]$ThumbAvifCrf = 24,
    [int]$WebpQuality = 85,
    [int]$ThumbWebpQuality = 80,
    [int]$Parallel = 6,
    [string[]]$Skins = @(),
    [string]$ContactSheet = (Join-Path $PSScriptRoot '..\output\contact-sheet.jpg')
)
$ErrorActionPreference = 'Stop'
$Skins = @($Skins -split ',' | Where-Object { $_ })
Add-Type -AssemblyName System.Drawing

$source = Join-Path $Studio 'left4dead2\screenshots\skinshots'
$shots = [ordered]@{ hand = 1; ground = 2; ground2 = 3; ground3 = 4; third = 5; third2 = 6 }
$cardShots = @('hand', 'third', 'third2')
$cardCenter = @{ hand = 0.6; handMelee = 0.72 }
$skinsConfig = Get-Content (Join-Path $Studio 'left4dead2\addons\sourcemod\configs\weapon_skins.cfg') -Raw
$weapons = @{}
foreach ($match in [regex]::Matches($skinsConfig, '"([a-z0-9-]+)"[^\n]*\n\s*\{\s*\n\s*"weapon"\s*"(weapon_[a-z0-9_]+)"'))
{
    $weapons[$match.Groups[1].Value] = $match.Groups[2].Value
}

$found = @($shots.Keys | ForEach-Object { Get-ChildItem (Join-Path $source $_) -Filter *.jpg -ErrorAction SilentlyContinue | ForEach-Object BaseName }) | Sort-Object -Unique
if ($Skins.Count -gt 0) { $found = @($found | Where-Object { $_ -in $Skins }) }
if ($found.Count -eq 0) { throw "No screenshots in $source" }

$jobs = foreach ($skin in $found) {
    $folder = Join-Path $Output $skin
    New-Item -ItemType Directory -Force $folder | Out-Null
    foreach ($shot in $shots.Keys) {
        $file = Join-Path $source "$shot\$skin.jpg"
        if (-not (Test-Path $file)) { continue }

        $image = [System.Drawing.Image]::FromFile($file)
        $w = $image.Width; $h = $image.Height
        $image.Dispose()

        $ratio = $Width / $Height
        $cropWidth = [Math]::Min($w, [int]($h * $ratio))
        $cropHeight = [int]($cropWidth / $ratio)
        $side = [Math]::Min($w, $h)
        $key = if ($shot -eq 'hand' -and "$($weapons[$skin])" -like 'weapon_melee_*') { 'handMelee' } else { $shot }
        $center = if ($cardCenter.Contains($key)) { $cardCenter[$key] } else { 0.5 }

        [pscustomobject]@{
            File = $file
            Base = Join-Path $folder $shots[$shot]
            Full = "crop=${cropWidth}:${cropHeight}:$([int](($w - $cropWidth) / 2)):$([int](($h - $cropHeight) / 2)),scale=${Width}:${Height}:flags=lanczos"
            Card = if ($shot -in $cardShots) { "crop=${side}:${side}:$([int][Math]::Min($w - $side, [Math]::Max(0, $w * $center - $side / 2))):$([int](($h - $side) / 2)),scale=${CardSize}:${CardSize}:flags=lanczos" } else { $null }
            Thumb = "crop=${cropWidth}:${cropHeight}:$([int](($w - $cropWidth) / 2)):$([int](($h - $cropHeight) / 2)),scale=${ThumbWidth}:${ThumbHeight}:flags=lanczos"
        }
    }
}

$settings = @{ FFmpeg = $FFmpeg; AvifCrf = $AvifCrf; ThumbAvifCrf = $ThumbAvifCrf; WebpQuality = $WebpQuality; ThumbWebpQuality = $ThumbWebpQuality }
$failed = $jobs | ForEach-Object -ThrottleLimit $Parallel -Parallel {
    $job = $_
    $s = $using:settings
    $avif = @('-c:v', 'libaom-av1', '-still-picture', '1', '-cpu-used', '6', '-pix_fmt', 'yuv420p')
    $webp = @('-c:v', 'libwebp', '-compression_level', '6', '-preset', 'picture')
    $outputs = @(
        @{ Filter = $job.Full; Name = ''; Crf = $s.AvifCrf; Quality = $s.WebpQuality },
        @{ Filter = $job.Thumb; Name = '-thumb'; Crf = $s.ThumbAvifCrf; Quality = $s.ThumbWebpQuality }
    )
    if ($job.Card) { $outputs += @{ Filter = $job.Card; Name = '-card'; Crf = $s.ThumbAvifCrf; Quality = $s.ThumbWebpQuality } }

    $graph = "[0]split=$($outputs.Count * 2)" + (-join (0..($outputs.Count * 2 - 1) | ForEach-Object { "[s$_]" }))
    $maps = @()
    for ($i = 0; $i -lt $outputs.Count; $i++) {
        $o = $outputs[$i]
        $graph += ";[s$($i * 2)]$($o.Filter)[a$i];[s$($i * 2 + 1)]$($o.Filter)[w$i]"
        $maps += @('-map', "[a$i]") + $avif + @('-crf', $o.Crf, "$($job.Base)$($o.Name).avif")
        $maps += @('-map', "[w$i]") + $webp + @('-quality', $o.Quality, "$($job.Base)$($o.Name).webp")
    }

    & $s.FFmpeg -y -loglevel error -i $job.File -filter_complex $graph @maps
    if ($LASTEXITCODE -ne 0) { $job.File }
}
if ($failed) { throw "ffmpeg failed for: $($failed -join ', ')" }

$cell = 320; $cellHeight = 180; $label = 18
$sheet = New-Object System.Drawing.Bitmap ($cell * $shots.Count), (($cellHeight + $label) * $found.Count)
$graphics = [System.Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font 'Arial', 10, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $found.Count; $i++) {
    $top = $i * ($cellHeight + $label)
    $graphics.DrawString($found[$i], $font, [System.Drawing.Brushes]::Yellow, 4, $top + 2)
    $s = 0
    foreach ($shot in $shots.Keys) {
        $file = Join-Path $source "$shot\$($found[$i]).jpg"
        if (Test-Path $file) {
            $image = [System.Drawing.Image]::FromFile($file)
            $graphics.DrawImage($image, $s * $cell, $top + $label, $cell, $cellHeight)
            $image.Dispose()
        }
        $s++
    }
}
New-Item -ItemType Directory -Force (Split-Path $ContactSheet) | Out-Null
$sheet.Save([System.IO.Path]::GetFullPath($ContactSheet), [System.Drawing.Imaging.ImageFormat]::Jpeg)
$graphics.Dispose(); $sheet.Dispose()

"$($jobs.Count) photos for $($found.Count) skins in $Output"
"Each photo: $Width x $Height, a $ThumbWidth x $ThumbHeight thumbnail and, for photos 1, 5 and 6, a $CardSize px square card image; AVIF (crf $AvifCrf / $ThumbAvifCrf) and WebP (quality $WebpQuality / $ThumbWebpQuality)"
"Contact sheet: $ContactSheet"
