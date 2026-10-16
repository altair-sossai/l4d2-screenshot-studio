param(
    [string]$Pattern = '*.jpg',
    [string]$Out = 'sheet.jpg',
    [int]$Cols = 2,
    [string]$Folder = 'E:\L4D2-Studio\left4dead2\screenshots\skinshots\test'
)
Add-Type -AssemblyName System.Drawing
$files = Get-ChildItem $Folder -Filter $Pattern | Sort-Object Name
$w = 640; $h = 360
$rows = [Math]::Ceiling($files.Count / $Cols)
$sheet = New-Object System.Drawing.Bitmap ($w * $Cols), ($h * $rows)
$g = [System.Drawing.Graphics]::FromImage($sheet)
$font = New-Object System.Drawing.Font 'Arial', 12, ([System.Drawing.FontStyle]::Bold)
for ($i = 0; $i -lt $files.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile($files[$i].FullName)
    $x = ($i % $Cols) * $w; $y = [Math]::Floor($i / $Cols) * $h
    $g.DrawImage($img, $x, $y, $w, $h)
    $g.DrawString($files[$i].BaseName, $font, [System.Drawing.Brushes]::Yellow, $x + 4, $y + 4)
    $img.Dispose()
}
$sheet.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Jpeg)
$g.Dispose(); $sheet.Dispose()
