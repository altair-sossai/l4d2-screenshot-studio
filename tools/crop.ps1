param([string[]]$Files, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Out)
Add-Type -AssemblyName System.Drawing
$Files = $Files -split ','
$sheet = New-Object System.Drawing.Bitmap ($W * $Files.Count), $H
$g = [System.Drawing.Graphics]::FromImage($sheet)
for ($i = 0; $i -lt $Files.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile($Files[$i])
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle ($i * $W), 0, $W, $H), (New-Object System.Drawing.Rectangle $X, $Y, $W, $H), 'Pixel')
    $img.Dispose()
}
$sheet.Save($Out, [System.Drawing.Imaging.ImageFormat]::Jpeg)
