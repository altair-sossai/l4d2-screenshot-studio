$ErrorActionPreference = 'Stop'

$studio = if ($env:L4D2_STUDIO) { $env:L4D2_STUDIO } else { 'E:\L4D2-Studio' }
$command = ($args -join ' ').Trim()
if (-not $command) { throw 'Usage: send.ps1 <command>' }

$queue = Join-Path $studio 'left4dead2\addons\sourcemod\data\skin_shots_queue.txt'
Add-Content -Path $queue -Value $command -Encoding ascii
"queued: $command"