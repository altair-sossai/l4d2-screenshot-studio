# L4D2 Screenshot Studio

🌐 **English** | [Português](README.md) | [Español](README.es.md)

Automatic photo studio for **Left 4 Dead 2** weapon skins.

On its own, and always the same way, it takes six photos of each skin:

| Photo | What it shows |
|---|---|
| `hand` | First person, holding the weapon (what the player sees on screen) |
| `ground` | The weapon lying on the ground, barrel to the left |
| `ground2` | The weapon lying on the ground, barrel to the right, showing the other side |
| `ground3` | The weapon on the ground diagonally, slightly tilted, in a more natural position |
| `third` | A survivor holding the weapon, close-up on the weapon |
| `third2` | The same survivor, in a wider shot |

It was built to photograph the **196 skins** in the L4D2 Zone server shop, but it works for any set of skins that follows the same configuration format.

> This repository is also **study material**. Every decision, every problem found and every solution is explained in the documents in the [`docs/`](docs) folder (in Portuguese). If you want to understand *how* and *why* everything works, start with the [reading guide](#reading-guide).

---

## How it works, in one sentence

A **SourceMod plugin** runs inside a local game server, builds each scene (positions the camera, puts the weapon in the hand, on the ground or in a survivor's hand, applies the skin) and tells the game itself to take a screenshot. **PowerShell scripts** outside send commands to the plugin, calibrate the framing and process the images.

```text
  ┌────────────────────────────┐           queue file           ┌──────────────────────────────────────┐
  │ PowerShell (your terminal) │ ─────────────────────────────▶ │  Left 4 Dead 2 ("studio" copy)       │
  │                            │  skin_shots_queue.txt          │                                      │
  │  send.ps1                  │                                │  SourceMod + l4d2_skin_shots plugin  │
  │  calibrate.ps1             │ ◀───────────────────────────── │   - builds the scene                 │
  │  process-shots.ps1         │  screenshots/skinshots/*.jpg   │   - applies the skin                 │
  └────────────────────────────┘  skin_shots.log                │   - takes the screenshot (jpeg)      │
                                                                └──────────────────────────────────────┘
```

---

## Repository layout

```text
l4d2-screenshot-studio/
├── README.md                      ← this README in Portuguese (the main one)
├── README.en.md, README.es.md     ← this README in English and Spanish
├── plugin/
│   └── l4d2_skin_shots.sp         ← SourceMod plugin (the "director of photography")
├── config/
│   └── skin_shots.cfg             ← scenes: camera, weapon position, survivor position, framing
├── scripts/
│   ├── install-studio.ps1         ← installs Metamod, SourceMod, the plugin and the skins in the game copy
│   ├── run-studio.ps1             ← opens the game copy on the right map, at the right resolution
│   ├── send.ps1                   ← sends a command to the plugin
│   ├── calibrate.ps1              ← automatically calibrates the framing of each weapon
│   └── process-shots.ps1          ← generates the photos in AVIF and WebP (large, thumbnail and card) and the review sheet
├── tools/
│   ├── sheet.ps1                  ← joins several screenshots in one sheet (for a quick review)
│   ├── diffimg.ps1                ← shows the difference between two screenshots (diagnostics)
│   └── crop.ps1                   ← crops the same region of several screenshots (diagnostics)
└── docs/                          ← the study documentation, in Portuguese (read in order)
```

---

## Reading guide

The documents (in Portuguese) were written to be read in order. Each one builds on what the previous one explained.

| # | Document | Subject |
|---|---|---|
| 1 | [Basic concepts](docs/01-conceitos-basicos.md) | Source Engine, SourceMod, entities, models, skins/families, viewmodel vs worldmodel |
| 2 | [The studio: a copy of the game](docs/02-estudio.md) | Why a separate copy, `-insecure`, what is installed, how to open it |
| 3 | [Talking to the game](docs/03-comunicacao.md) | The command queue, the log, why we do not use RCON or the console |
| 4 | [The plugin, part by part](docs/04-plugin.md) | Guided reading of `l4d2_skin_shots.sp` |
| 5 | [The scenes](docs/05-cenas.md) | `skin_shots.cfg`, coordinates, angles, FOV and how to find a good position |
| 6 | [First person and ground](docs/06-mao-e-chao.md) | Swapping the weapon model in the hand, restricted melee weapons, weapon on the ground |
| 7 | [Third person](docs/07-terceira-pessoa.md) | "Mannequin" survivor, frozen animation, weapon attached to the hand bone |
| 8 | [Automatic framing](docs/08-enquadramento-automatico.md) | The calibration: image difference, camera math, convergence |
| 9 | [Image processing](docs/09-tratamento.md) | 16:9 crop, compression, review sheet |
| 10 | [Problem log](docs/10-problemas-e-solucoes.md) | Every real problem that came up and how each one was solved |
| 11 | [Complete step by step](docs/11-passo-a-passo.md) | From zero to the finished photos |
| 12 | [Glossary](docs/12-glossario.md) | Terms used in the documents |
| 13 | [The plugin code](docs/13-codigo-do-plugin.md) | Every plugin function, in full, explained line by line, with exercises |
| 14 | [The calibration code](docs/14-codigo-da-calibracao.md) | `calibrate.ps1` and the embedded C#, part by part, with exercises |

---

## Prerequisites

| Item | Where to get it | Notes |
|---|---|---|
| Windows + **PowerShell 7** (`pwsh`) | `winget install Microsoft.PowerShell` | Use `pwsh`, not Windows PowerShell 5.1: `calibrate.ps1` and `process-shots.ps1` use features that only exist in 7 (`-Encoding utf8NoBOM`, `ForEach-Object -Parallel`) |
| **Left 4 Dead 2** from Steam | Steam | Steam must be running to open the game copy |
| ~15 GB free | | For the **copy** of the game folder (the "studio"). Never use the folder you play with |
| **Metamod:Source** and **SourceMod**, stable version for **Windows** | [metamodsource.net](https://www.metamodsource.net/downloads.php) and [sourcemod.net](https://www.sourcemod.net/downloads.php) | SourceMod **1.11 or newer** (the plugin uses `GetCmdArgInt`/`GetCmdArgFloat`). Extract both `.zip` files into the **same folder**, so that `addons\metamod` and `addons\sourcemod` sit side by side. The compiler (`spcomp.exe`) comes in the SourceMod package |
| **ffmpeg** with `libaom-av1` and `libwebp` | `winget install Gyan.FFmpeg` | Only for `process-shots.ps1`. Check with `ffmpeg -encoders`. No other image tool is used |
| The **skins** | You | A `weapon_skins.cfg` and a folder with `models\l4d2br\...` and `materials\models\l4d2br\...` (format in the [step by step](docs/11-passo-a-passo.md#preparando-as-suas-skins)). This repository does not include skins |

---

## Paths you may need to adjust

All scripts assume the game copy is at **`E:\L4D2-Studio`**. If yours is somewhere else (`<studio folder>`):

| Script | How to point it at your copy |
|---|---|
| `send.ps1`, `calibrate.ps1` | Environment variable: `$env:L4D2_STUDIO = '<studio folder>'` (lasts for the terminal session) |
| `install-studio.ps1`, `run-studio.ps1`, `process-shots.ps1` | Parameter `-Studio '<studio folder>'` (these do **not** read the environment variable) |
| `tools\sheet.ps1` | Parameter `-Folder '<studio folder>\left4dead2\screenshots\skinshots\test'` |

---

## Quick start

```powershell
# 0. Only if the game copy is not at E:\L4D2-Studio
$env:L4D2_STUDIO = '<studio folder>'

# 1. Compiles the plugin and installs Metamod, SourceMod, the plugin, the configs and the skins in the game copy
.\scripts\install-studio.ps1 -Studio '<studio folder>' -SourceMod '<folder with addons\metamod and addons\sourcemod>' -SkinsConfig '<weapon_skins.cfg>' -Assets '<skins folder>'

# 2. Opens the game copy on The Parish (c5m1_waterfront). Then wait for the opening cutscene to end (~3 min)
.\scripts\run-studio.ps1 -Studio '<studio folder>'

# 3. (Once, and again for every new weapon) calibrates the third-person framing
.\scripts\calibrate.ps1

# 4. Takes the six photos of every skin
.\scripts\send.ps1 sm_shots_run all

# 5. Crops, compresses and builds the review sheet
.\scripts\process-shots.ps1 -Studio '<studio folder>'
```

The details of each step, how to prepare your own skins and what to do when something goes wrong are in the [complete step by step](docs/11-passo-a-passo.md) (in Portuguese).

---

## Where the files go

| What | Where |
|---|---|
| Compiled plugin | `build\l4d2_skin_shots.smx` (generated by `install-studio.ps1`, not in git) |
| Plugin command queue and log | `<studio folder>\left4dead2\addons\sourcemod\data\skin_shots_queue.txt` and `skin_shots.log` |
| Original screenshots (JPEG) | `<studio folder>\left4dead2\screenshots\skinshots\<scene>\<skin>.jpg` (and `test\` for one-off and calibration screenshots) |
| Processed photos (AVIF and WebP) | `output\<skin>\1.avif` ... `6.webp`, with `-thumb` and `-card` (not in git; change with `-Output`) |
| Review sheet | `output\contact-sheet.jpg` (change with `-ContactSheet`) |
| Calibrated framing | Written by `calibrate.ps1` straight into the repository's `config\skin_shots.cfg` and copied to the game copy |

The processed photo numbers follow the scene order: 1 `hand`, 2 `ground`, 3 `ground2`, 4 `ground3`, 5 `third`, 6 `third2`.

---

## Plugin commands

All of them are sent with `.\scripts\send.ps1 <command>`.

| Command | What it does |
|---|---|
| `sm_shots_run <scene\|all> [skins or weapons...]` | Takes the photos. The scene can be a comma-separated list (`ground,ground2`). Without a filter, does every skin; the filter accepts skin ids and weapon classes (`weapon_smg`). Does every skin of a scene before moving to the next one |
| `sm_shots_show <skin> <scene>` | Builds a scene without taking a photo (to check it on screen) |
| `sm_shots_snap <name>` | Takes a one-off screenshot to `screenshots/skinshots/test/<name>.jpg` |
| `sm_shots_frame <pitch> <yaw> <fov>` | Turns the camera and changes the zoom, without moving |
| `sm_shots_turn <yaw>` | Turns the third-person survivor |
| `sm_shots_pose <pitch> <yaw> <roll>` | Rotates the ground weapon (to test positions) |
| `sm_shots_weapon <0\|1\|noshadow>` | Hides or shows the third-person weapon (or the ground one), or turns its shadow off |
| `sm_shots_where` | Writes the player's position, angles and state to the log |
| `sm_shots_goto <x> <y> <z> <pitch> <yaw> <roll>` | Teleports the camera |
| `sm_shots_cvar <name> [value]` | Reads or changes a game cvar |
| `sm_shots_unhook` | Stops the changes the plugin makes every frame (diagnostics) |
| `sm_shots_stop` | Stops a running sequence |
| `sm_shots_quit` | Closes the game when the sequence ends |
| `client <command>` | Runs a command as if the player had typed it in the console |

---

## Credits

- Skins: each skin belongs to its author on the Steam Workshop. This repository does not distribute skins.
- [SourceMod](https://www.sourcemod.net) and [Metamod:Source](https://www.metamodsource.net).
- Made for the **L4D2 Zone** server.
