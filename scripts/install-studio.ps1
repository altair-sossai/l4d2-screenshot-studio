param(
    [string]$Studio = 'E:\L4D2-Studio',
    [Parameter(Mandatory)][string]$SourceMod,
    [Parameter(Mandatory)][string]$SkinsConfig,
    [Parameter(Mandatory)][string]$Assets
)
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path "$PSScriptRoot\..").Path
$game = Join-Path $Studio 'left4dead2'
if (-not (Test-Path (Join-Path $Studio 'left4dead2.exe'))) { throw "No game copy at $Studio" }
if (-not (Test-Path (Join-Path $SourceMod 'addons\sourcemod\bin'))) { throw "No SourceMod at $SourceMod (expected addons\sourcemod and addons\metamod inside it)" }
if (-not (Test-Path $SkinsConfig)) { throw "No weapon_skins.cfg at $SkinsConfig" }
if (-not (Test-Path (Join-Path $Assets 'models'))) { throw "No skin assets at $Assets (expected models and materials inside it)" }

$compiler = Join-Path $SourceMod 'addons\sourcemod\scripting\spcomp.exe'
$include = Join-Path $SourceMod 'addons\sourcemod\scripting\include'
$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force $build | Out-Null
& $compiler (Join-Path $root 'plugin\l4d2_skin_shots.sp') "-i$include" "-o$(Join-Path $build 'l4d2_skin_shots.smx')"
if ($LASTEXITCODE -ne 0) { throw 'Plugin did not compile' }

$addons = Join-Path $game 'addons'
$sm = Join-Path $addons 'sourcemod'
$sourceSm = Join-Path $SourceMod 'addons\sourcemod'

New-Item -ItemType Directory -Force (Join-Path $addons 'metamod\bin'), "$sm\bin", "$sm\extensions", "$sm\plugins", "$sm\data", "$sm\logs", "$sm\configs" | Out-Null

Copy-Item (Join-Path $SourceMod 'addons\metamod.vdf') $addons -Force
Copy-Item (Join-Path $SourceMod 'addons\metamod\bin\*.dll') (Join-Path $addons 'metamod\bin') -Force
Copy-Item (Join-Path $SourceMod 'addons\metamod\sourcemod.vdf') (Join-Path $addons 'metamod') -Force

Copy-Item "$sourceSm\bin\*.dll" "$sm\bin" -Force
Copy-Item "$sourceSm\extensions\sdktools.ext.2.l4d2.dll", "$sourceSm\extensions\sdkhooks.ext.2.l4d2.dll", "$sourceSm\extensions\bintools.ext.dll" "$sm\extensions" -Force
Copy-Item "$sourceSm\gamedata" $sm -Recurse -Force
Copy-Item "$sourceSm\translations" $sm -Recurse -Force
foreach ($f in 'core.cfg', 'languages.cfg', 'databases.cfg') { Copy-Item "$sourceSm\configs\$f" "$sm\configs" -Force }
Copy-Item $SkinsConfig (Join-Path $sm 'configs\weapon_skins.cfg') -Force
Copy-Item (Join-Path $root 'config\skin_shots.cfg') "$sm\configs" -Force
Copy-Item (Join-Path $build 'l4d2_skin_shots.smx') "$sm\plugins" -Force

foreach ($sub in 'models\l4d2br', 'materials\models\l4d2br') {
    $source = Join-Path $Assets $sub
    if (-not (Test-Path $source)) { continue }
    $target = Join-Path $game $sub
    if (Test-Path $target) { Remove-Item $target -Recurse -Force }
    New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
    Copy-Item $source $target -Recurse -Force
}

$workshop = Join-Path $addons 'workshop'
if (Test-Path $workshop) { Write-Warning "Workshop addons found at $workshop. They load in the studio too; move them out of the copy." }

$video = Join-Path $game 'cfg\video.txt'
if ((Test-Path $video) -and (Select-String -Path $video -Pattern '"setting.gpu_level"\s+"3"' -Quiet)) {
    (Get-Content $video -Raw) -replace '("setting.gpu_level"\s+)"3"', '$1"2"' | Set-Content $video -NoNewline
    Write-Warning 'Shader detail lowered from 3 to 2 in cfg\video.txt: at 3 the first-person arms are not drawn.'
}

"Studio ready at $Studio"
