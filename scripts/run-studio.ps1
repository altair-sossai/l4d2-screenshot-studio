param(
    [string]$Studio = 'E:\L4D2-Studio',
    [string]$Map = 'c5m1_waterfront',
    [int]$Width = 1920,
    [int]$Height = 1080
)
$ErrorActionPreference = 'Stop'

if (Get-Process left4dead2 -ErrorAction SilentlyContinue) { throw 'Left 4 Dead 2 is already running. Close it first.' }

$queue = Join-Path $Studio 'left4dead2\addons\sourcemod\data\skin_shots_queue.txt'
if (Test-Path $queue) { Remove-Item $queue -Force }

$arguments = @('-novid', '-insecure', '-windowed', '-noborder', '-w', $Width, '-h', $Height, '+sv_lan', '1', '+sv_cheats', '1', '+map', $Map)
Start-Process -FilePath (Join-Path $Studio 'left4dead2.exe') -ArgumentList $arguments -WorkingDirectory $Studio
"Started $Map at ${Width}x$Height"