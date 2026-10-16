param(
    [string[]]$Scenes = @('third', 'third2'),
    [string[]]$Weapons = @(),
    [double]$FillWidth = 0.6,
    [double]$FillHeight = 0.65,
    [int]$Passes = 4,
    [int[]]$ActorYaws = @(170, 190, 210, 230, 250, 270, 290),
    [string]$Studio = $(if ($env:L4D2_STUDIO) { $env:L4D2_STUDIO } else { 'E:\L4D2-Studio' })
)
$ErrorActionPreference = 'Stop'
$Scenes = @($Scenes -split ',' | Where-Object { $_ })
$Weapons = @($Weapons -split ',' | Where-Object { $_ })

Add-Type -AssemblyName System.Drawing
$references = @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Rectangle].Assembly.Location) + @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -in @('System.Private.Windows.GdiPlus', 'System.Private.Windows.Core', 'System.Runtime.InteropServices') } | ForEach-Object Location)
Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class ShotDiff
{
    public static int[] Box(string withWeapon, string withoutWeapon, int threshold)
    {
        using (var a = new Bitmap(withWeapon))
        using (var b = new Bitmap(withoutWeapon))
        {
            int w = a.Width, h = a.Height;
            var rect = new Rectangle(0, 0, w, h);
            var da = a.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            var db = b.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            var pa = new byte[da.Stride * h];
            var pb = new byte[db.Stride * h];
            Marshal.Copy(da.Scan0, pa, 0, pa.Length);
            Marshal.Copy(db.Scan0, pb, 0, pb.Length);
            a.UnlockBits(da);
            b.UnlockBits(db);

            const int cell = 8;
            int cw = (w + cell - 1) / cell, ch = (h + cell - 1) / cell;
            var cells = new int[cw * ch];
            for (int y = 0; y < h; y++)
            {
                int line = y * da.Stride;
                for (int x = 0; x < w; x++)
                {
                    int i = line + x * 3;
                    int diff = Math.Abs(pa[i] - pb[i]) + Math.Abs(pa[i + 1] - pb[i + 1]) + Math.Abs(pa[i + 2] - pb[i + 2]);
                    if (diff > threshold)
                    {
                        cells[(y / cell) * cw + x / cell]++;
                    }
                }
            }

            var label = new int[cw * ch];
            var stack = new int[cw * ch];
            int top = 0;
            int bestCount = 0, bx1 = -1, by1 = -1, bx2 = -1, by2 = -1, next = 0;
            for (int start = 0; start < cells.Length; start++)
            {
                if (cells[start] < 4 || label[start] != 0)
                {
                    continue;
                }

                next++;
                int count = 0, x1 = int.MaxValue, y1 = int.MaxValue, x2 = -1, y2 = -1;
                label[start] = next;
                stack[top++] = start;
                while (top > 0)
                {
                    int c = stack[--top];
                    int cx = c % cw, cy = c / cw;
                    count += cells[c];
                    x1 = Math.Min(x1, cx); x2 = Math.Max(x2, cx); y1 = Math.Min(y1, cy); y2 = Math.Max(y2, cy);
                    for (int dy = -2; dy <= 2; dy++)
                    {
                        for (int dx = -2; dx <= 2; dx++)
                        {
                            int nx = cx + dx, ny = cy + dy;
                            if (nx < 0 || ny < 0 || nx >= cw || ny >= ch)
                            {
                                continue;
                            }

                            int n = ny * cw + nx;
                            if (cells[n] >= 4 && label[n] == 0)
                            {
                                label[n] = next;
                                stack[top++] = n;
                            }
                        }
                    }
                }

                if (count > bestCount)
                {
                    bestCount = count; bx1 = x1; by1 = y1; bx2 = x2; by2 = y2;
                }
            }

            if (bestCount == 0)
            {
                return new[] { -1, -1, -1, -1, w, h, 0 };
            }

            return new[] { bx1 * cell, by1 * cell, Math.Min(w - 1, bx2 * cell + cell - 1), Math.Min(h - 1, by2 * cell + cell - 1), w, h, bestCount };
        }
    }
}
'@

function Send([string]$command)
{
    $queue = Join-Path $Studio 'left4dead2\addons\sourcemod\data\skin_shots_queue.txt'
    Add-Content -Path $queue -Value $command -Encoding ascii
}

function Snap([string]$name)
{
    $file = Join-Path $Studio "left4dead2\screenshots\skinshots\test\$name.jpg"
    Remove-Item $file -ErrorAction SilentlyContinue
    Send "sm_shots_snap $name"
    for ($i = 0; $i -lt 40 -and -not (Test-Path $file); $i++) { Start-Sleep -Milliseconds 250 }
    if (-not (Test-Path $file)) { throw "screenshot $name not saved" }
    Start-Sleep -Milliseconds 300
    $file
}

function Find-Weapon([string]$tag)
{
    $with = Snap "cal_${tag}_a"
    Send 'sm_shots_weapon 0'
    Start-Sleep -Milliseconds 800
    $without = Snap "cal_${tag}_b"
    Send 'sm_shots_weapon 1'
    Start-Sleep -Milliseconds 500
    [ShotDiff]::Box($with, $without, 60)
}

function Solve([double]$pitch, [double]$yaw, [double]$fov, [int[]]$box)
{
    $rad = [Math]::PI / 180
    $tanH = [Math]::Tan($fov * $rad / 2) * 4 / 3
    $tanV = $tanH * 9 / 16
    $w = $box[4]; $h = $box[5]
    $nx = (($box[0] + $box[2]) / 2 - $w / 2) / ($w / 2) * $tanH
    $ny = ($h / 2 - ($box[1] + $box[3]) / 2) / ($h / 2) * $tanV

    $cp = [Math]::Cos($pitch * $rad); $sp = [Math]::Sin($pitch * $rad)
    $cy = [Math]::Cos($yaw * $rad); $sy = [Math]::Sin($yaw * $rad)
    $dx = $cp * $cy + $nx * $sy + $ny * $sp * $cy
    $dy = $cp * $sy - $nx * $cy + $ny * $sp * $sy
    $dz = -$sp + $ny * $cp

    $newYaw = [Math]::Atan2($dy, $dx) / $rad
    $newPitch = -[Math]::Atan2($dz, [Math]::Sqrt($dx * $dx + $dy * $dy)) / $rad

    $fill = [Math]::Max(($box[2] - $box[0]) / $w / $fillWidth, ($box[3] - $box[1]) / $h / $fillHeight)
    $newFov = [Math]::Round(2 * [Math]::Atan([Math]::Tan($fov * $rad / 2) * $fill) / $rad)

    [Math]::Round($newPitch, 2), [Math]::Round(($newYaw + 360) % 360, 2), [Math]::Min(60, [Math]::Max(4, $newFov))
}

$skinsConfig = Get-Content (Join-Path $Studio 'left4dead2\addons\sourcemod\configs\weapon_skins.cfg') -Raw
$samples = [ordered]@{}
foreach ($match in [regex]::Matches($skinsConfig, '"([a-z0-9-]+)"[^\n]*\n\s*\{\s*\n\s*"weapon"\s*"(weapon_[a-z0-9_]+)"'))
{
    $weapon = $match.Groups[2].Value
    if (-not $samples.Contains($weapon)) { $samples[$weapon] = $match.Groups[1].Value }
}
if ($Weapons.Count -gt 0) { $samples.Keys.Where({ $_ -notin $Weapons }) | ForEach-Object { $samples.Remove($_) } }

$configPath = Join-Path $PSScriptRoot '..\config\skin_shots.cfg'
$installed = Join-Path $Studio 'left4dead2\addons\sourcemod\configs\skin_shots.cfg'
$config = Get-Content $configPath -Raw
Copy-Item $configPath $installed -Force
$chosen = @{}
$firstFraming = [regex]::Match($config, '(?s)\n\t\t"third"\r?\n\t\t\{[^}]*?"framing"\s*\{(.*?)\}').Groups[1].Value
foreach ($entry in [regex]::Matches($firstFraming, '"(weapon_[a-z0-9_]+)"\s*"[-\d.]+ [-\d.]+ [-\d.]+ ([-\d.]+)"'))
{
    $chosen[$entry.Groups[1].Value] = [int]$entry.Groups[2].Value
}

foreach ($scene in $Scenes)
{
    $block = [regex]::Match($config, "(?s)\n\t\t""$scene""\r?\n\t\t\{.*?\n\t\t\}")
    if (-not $block.Success) { throw "scene $scene not found in skin_shots.cfg" }
    $angles = [regex]::Match($block.Value, '"angles"\s*"([-\d.]+) ([-\d.]+)').Groups
    $basePitch = [double]$angles[1].Value; $baseYaw = [double]$angles[2].Value
    $baseFov = [double][regex]::Match($block.Value, '"fov"\s*"(\d+)"').Groups[1].Value
    $sceneFill = [regex]::Match($block.Value, '"fill"\s*"([\d.]+)"')
    $fillWidth = if ($sceneFill.Success) { [double]$sceneFill.Groups[1].Value } else { $FillWidth }
    $fillHeight = if ($sceneFill.Success) { [double]$sceneFill.Groups[1].Value } else { $FillHeight }

    $results = [ordered]@{}
    $existing = [regex]::Match($block.Value, '(?s)"framing"\s*\{(.*?)\}').Groups[1].Value
    foreach ($entry in [regex]::Matches($existing, '"(weapon_[a-z0-9_]+)"\s*"([-\d. ]+)"'))
    {
        $results[$entry.Groups[1].Value] = $entry.Groups[2].Value
    }

    foreach ($weapon in $samples.Keys)
    {
        $pitch = $basePitch; $yaw = $baseYaw; $fov = $baseFov
        Send "sm_shots_show $($samples[$weapon]) $scene"
        Start-Sleep -Seconds 3
        Send "sm_shots_weapon noshadow"
        Send "sm_shots_frame $pitch $yaw $fov"

        $isThird = [regex]::Match($block.Value, '"type"\s*"third"').Success
        $candidates = @()
        if ($isThird -and ($scene -eq 'third' -or -not $chosen.Contains($weapon)))
        {
            $candidates = $ActorYaws
        }
        elseif ($isThird)
        {
            $candidates = @($chosen[$weapon])
        }

        $actorYaw = -1; $best = -1
        foreach ($candidate in $candidates)
        {
            Send "sm_shots_turn $candidate"
            Start-Sleep -Milliseconds 600
            $box = Find-Weapon "$scene"
            if ($box[6] -gt $best) { $best = $box[6]; $actorYaw = $candidate }
        }

        if ($isThird)
        {
            Send "sm_shots_turn $actorYaw"
            $chosen[$weapon] = $actorYaw
        }

        for ($pass = 0; $pass -lt $Passes; $pass++)
        {
            Send "sm_shots_frame $pitch $yaw $fov"
            Start-Sleep -Milliseconds 800
            $box = Find-Weapon "$scene"
            if ($box[0] -lt 0) { Write-Warning "$scene $weapon`: weapon not found on screen"; break }
            $pitch, $yaw, $fov = Solve $pitch $yaw $fov $box
        }
        $results[$weapon] = if ($isThird) { "$pitch $yaw $fov $actorYaw" } else { "$pitch $yaw $fov" }
        "$scene $weapon ($($samples[$weapon])): $pitch $yaw $fov actor $actorYaw"
    }

    $framing = "`n`t`t`t""framing""`n`t`t`t{`n" + (($results.Keys | ForEach-Object { "`t`t`t`t""$_""`t""$($results[$_])""" }) -join "`n") + "`n`t`t`t}"
    $body = [regex]::Replace($block.Value, '(?s)\r?\n\t\t\t"framing"\r?\n\t\t\t\{.*?\n\t\t\t\}', '')
    $body = $body -replace '\r?\n\t\t\}$', "$framing`n`t`t}"
    $config = $config.Replace($block.Value, $body)
}

Set-Content -Path $configPath -Value $config.TrimEnd() -Encoding utf8NoBOM
Copy-Item $configPath $installed -Force
"framing saved to $configPath"
