# L4D2 Screenshot Studio

🌐 [English](README.en.md) | [Português](README.md) | **Español**

Estudio automático de fotos para skins de armas de **Left 4 Dead 2**.

Toma, solo y siempre de la misma manera, seis fotos de cada skin:

| Foto | Qué muestra |
|---|---|
| `hand` | Primera persona, sosteniendo el arma (lo que el jugador ve en pantalla) |
| `ground` | El arma tirada en el suelo, con el cañón hacia la izquierda |
| `ground2` | El arma tirada en el suelo, con el cañón hacia la derecha, mostrando el otro lado |
| `ground3` | El arma en el suelo en diagonal, levemente inclinada, en una posición más natural |
| `third` | Un superviviente sosteniendo el arma, en primer plano del arma |
| `third2` | El mismo superviviente, en un plano más abierto |

Fue construido para fotografiar las **196 skins** de la tienda del servidor L4D2 Zone, pero funciona con cualquier conjunto de skins que siga el mismo formato de configuración.

> Este repositorio también es **material de estudio**. Cada decisión, cada problema encontrado y cada solución está explicada en los documentos de la carpeta [`docs/`](docs) (en portugués). Si quieres entender *cómo* y *por qué* funciona todo, empieza por la [guía de lectura](#guía-de-lectura).

---

## Cómo funciona, en una frase

Un **plugin de SourceMod** corre dentro de un servidor local del juego, arma cada escena (posiciona la cámara, pone el arma en la mano, en el suelo o en la mano de un superviviente, aplica la skin) y le pide al propio juego que tome un screenshot. **Scripts de PowerShell** desde afuera envían comandos al plugin, calibran el encuadre y procesan las imágenes.

```text
  ┌────────────────────────────┐        archivo de cola         ┌──────────────────────────────────────┐
  │  PowerShell (tu terminal)  │ ─────────────────────────────▶ │  Left 4 Dead 2 (copia "estudio")     │
  │                            │  skin_shots_queue.txt          │                                      │
  │  send.ps1                  │                                │  SourceMod + plugin l4d2_skin_shots  │
  │  calibrate.ps1             │ ◀───────────────────────────── │   - arma la escena                   │
  │  process-shots.ps1         │  screenshots/skinshots/*.jpg   │   - aplica la skin                   │
  └────────────────────────────┘  skin_shots.log                │   - toma el screenshot (jpeg)        │
                                                                └──────────────────────────────────────┘
```

---

## Estructura del repositorio

```text
l4d2-screenshot-studio/
├── README.md                      ← este README en portugués (el principal)
├── README.en.md, README.es.md     ← este README en inglés y en español
├── plugin/
│   └── l4d2_skin_shots.sp         ← plugin de SourceMod (el "director de fotografía")
├── config/
│   └── skin_shots.cfg             ← escenas: cámara, posición del arma, del superviviente, encuadre
├── scripts/
│   ├── install-studio.ps1         ← instala Metamod, SourceMod, el plugin y las skins en la copia del juego
│   ├── run-studio.ps1             ← abre la copia del juego en el mapa correcto, a la resolución correcta
│   ├── send.ps1                   ← envía un comando al plugin
│   ├── calibrate.ps1              ← calibra automáticamente el encuadre de cada arma
│   └── process-shots.ps1          ← genera las fotos en AVIF y WebP (grande, miniatura y card) y la hoja de revisión
├── tools/
│   ├── sheet.ps1                  ← junta varios screenshots en una hoja (para revisar rápido)
│   ├── diffimg.ps1                ← muestra la diferencia entre dos screenshots (diagnóstico)
│   └── crop.ps1                   ← recorta la misma región de varios screenshots (diagnóstico)
└── docs/                          ← la documentación de estudio, en portugués (léela en orden)
```

---

## Guía de lectura

Los documentos (en portugués) se escribieron para leerse en orden. Cada uno parte de lo que explicó el anterior.

| # | Documento | Tema |
|---|---|---|
| 1 | [Conceptos básicos](docs/01-conceitos-basicos.md) | Source Engine, SourceMod, entidades, modelos, skins/familias, viewmodel vs worldmodel |
| 2 | [El estudio: una copia del juego](docs/02-estudio.md) | Por qué una copia separada, `-insecure`, qué se instala, cómo abrirla |
| 3 | [Hablando con el juego](docs/03-comunicacao.md) | La cola de comandos, el log, por qué no usamos RCON ni la consola |
| 4 | [El plugin, parte por parte](docs/04-plugin.md) | Lectura guiada de `l4d2_skin_shots.sp` |
| 5 | [Las escenas](docs/05-cenas.md) | El `skin_shots.cfg`, coordenadas, ángulos, FOV y cómo encontrar una buena posición |
| 6 | [Primera persona y suelo](docs/06-mao-e-chao.md) | Cambiar el modelo del arma en la mano, armas melee restringidas, arma en el suelo |
| 7 | [Tercera persona](docs/07-terceira-pessoa.md) | Superviviente "maniquí", animación congelada, arma sujeta al hueso de la mano |
| 8 | [Encuadre automático](docs/08-enquadramento-automatico.md) | La calibración: diferencia de imágenes, matemática de cámara, convergencia |
| 9 | [Procesamiento de las imágenes](docs/09-tratamento.md) | Recorte 16:9, compresión, hoja de revisión |
| 10 | [Diario de problemas](docs/10-problemas-e-solucoes.md) | Todos los problemas reales que aparecieron y cómo se resolvió cada uno |
| 11 | [Paso a paso completo](docs/11-passo-a-passo.md) | De cero hasta las fotos listas |
| 12 | [Glosario](docs/12-glossario.md) | Términos usados en los documentos |
| 13 | [El código del plugin](docs/13-codigo-do-plugin.md) | Cada función del plugin, completa, explicada línea por línea, con ejercicios |
| 14 | [El código de la calibración](docs/14-codigo-da-calibracao.md) | El `calibrate.ps1` y el C# embebido, parte por parte, con ejercicios |

---

## Requisitos previos

| Ítem | Dónde conseguirlo | Observación |
|---|---|---|
| Windows + **PowerShell 7** (`pwsh`) | `winget install Microsoft.PowerShell` | Usa `pwsh`, no Windows PowerShell 5.1: `calibrate.ps1` y `process-shots.ps1` usan recursos que solo existen en la 7 (`-Encoding utf8NoBOM`, `ForEach-Object -Parallel`) |
| **Left 4 Dead 2** de Steam | Steam | Steam tiene que estar abierto para abrir la copia del juego |
| ~15 GB libres | | Para la **copia** de la carpeta del juego (el "estudio"). Nunca uses la carpeta con la que juegas |
| **Metamod:Source** y **SourceMod**, versión estable para **Windows** | [metamodsource.net](https://www.metamodsource.net/downloads.php) y [sourcemod.net](https://www.sourcemod.net/downloads.php) | SourceMod **1.11 o más nuevo** (el plugin usa `GetCmdArgInt`/`GetCmdArgFloat`). Extrae los dos `.zip` en la **misma carpeta**, para que `addons\metamod` y `addons\sourcemod` queden lado a lado. El compilador (`spcomp.exe`) viene en el paquete de SourceMod |
| **ffmpeg** con `libaom-av1` y `libwebp` | `winget install Gyan.FFmpeg` | Solo para `process-shots.ps1`. Compruébalo con `ffmpeg -encoders`. No se usa ninguna otra herramienta de imagen |
| Las **skins** | Tú | Un `weapon_skins.cfg` y una carpeta con `models\l4d2br\...` y `materials\models\l4d2br\...` (formato en el [paso a paso](docs/11-passo-a-passo.md#preparando-as-suas-skins)). Este repositorio no incluye skins |

---

## Rutas que quizás tengas que ajustar

Todos los scripts asumen que la copia del juego está en **`E:\L4D2-Studio`**. Si la tuya está en otro lugar (`<carpeta del estudio>`):

| Script | Cómo apuntarlo a tu copia |
|---|---|
| `send.ps1`, `calibrate.ps1` | Variable de entorno: `$env:L4D2_STUDIO = '<carpeta del estudio>'` (vale para la sesión de la terminal) |
| `install-studio.ps1`, `run-studio.ps1`, `process-shots.ps1` | Parámetro `-Studio '<carpeta del estudio>'` (estos **no** leen la variable de entorno) |
| `tools\sheet.ps1` | Parámetro `-Folder '<carpeta del estudio>\left4dead2\screenshots\skinshots\test'` |

---

## Uso rápido

```powershell
# 0. Solo si la copia del juego no está en E:\L4D2-Studio
$env:L4D2_STUDIO = '<carpeta del estudio>'

# 1. Compila el plugin e instala Metamod, SourceMod, el plugin, las configs y las skins en la copia del juego
.\scripts\install-studio.ps1 -Studio '<carpeta del estudio>' -SourceMod '<carpeta con addons\metamod y addons\sourcemod>' -SkinsConfig '<weapon_skins.cfg>' -Assets '<carpeta de las skins>'

# 2. Abre la copia del juego en The Parish (c5m1_waterfront). Después espera a que termine la cinemática de apertura (~3 min)
.\scripts\run-studio.ps1 -Studio '<carpeta del estudio>'

# 3. (Una vez, y de nuevo con cada arma nueva) calibra el encuadre de la tercera persona
.\scripts\calibrate.ps1

# 4. Toma las seis fotos de todas las skins
.\scripts\send.ps1 sm_shots_run all

# 5. Recorta, comprime y arma la hoja de revisión
.\scripts\process-shots.ps1 -Studio '<carpeta del estudio>'
```

Los detalles de cada paso, cómo preparar tus propias skins y qué hacer cuando algo sale mal están en el [paso a paso completo](docs/11-passo-a-passo.md) (en portugués).

---

## Dónde quedan los archivos

| Qué | Dónde |
|---|---|
| Plugin compilado | `build\l4d2_skin_shots.smx` (generado por `install-studio.ps1`, fuera de git) |
| Cola de comandos y log del plugin | `<carpeta del estudio>\left4dead2\addons\sourcemod\data\skin_shots_queue.txt` y `skin_shots.log` |
| Screenshots originales (JPEG) | `<carpeta del estudio>\left4dead2\screenshots\skinshots\<escena>\<skin>.jpg` (y `test\` para los screenshots sueltos y los de la calibración) |
| Fotos procesadas (AVIF y WebP) | `output\<skin>\1.avif` ... `6.webp`, con `-thumb` y `-card` (fuera de git; cámbialo con `-Output`) |
| Hoja de revisión | `output\contact-sheet.jpg` (cámbialo con `-ContactSheet`) |
| Encuadre calibrado | Lo escribe `calibrate.ps1` directamente en el `config\skin_shots.cfg` del repositorio y lo copia a la copia del juego |

Los números de las fotos procesadas siguen el orden de las escenas: 1 `hand`, 2 `ground`, 3 `ground2`, 4 `ground3`, 5 `third`, 6 `third2`.

---

## Comandos del plugin

Todos se envían con `.\scripts\send.ps1 <comando>`.

| Comando | Qué hace |
|---|---|
| `sm_shots_run <escena\|all> [skins o armas...]` | Toma las fotos. La escena puede ser una lista separada por comas (`ground,ground2`). Sin filtro, hace todas las skins; el filtro acepta ids de skin y clases de arma (`weapon_smg`). Hace todas las skins de una escena antes de pasar a la siguiente |
| `sm_shots_show <skin> <escena>` | Arma una escena sin fotografiar (para revisarla en pantalla) |
| `sm_shots_snap <nombre>` | Toma un screenshot suelto en `screenshots/skinshots/test/<nombre>.jpg` |
| `sm_shots_frame <pitch> <yaw> <fov>` | Gira la cámara y cambia el zoom, sin moverla |
| `sm_shots_turn <yaw>` | Gira al superviviente de la tercera persona |
| `sm_shots_pose <pitch> <yaw> <roll>` | Gira el arma del suelo (para probar posiciones) |
| `sm_shots_weapon <0\|1\|noshadow>` | Oculta o muestra el arma de la tercera persona (o la del suelo), o le apaga la sombra |
| `sm_shots_where` | Escribe en el log la posición, los ángulos y el estado del jugador |
| `sm_shots_goto <x> <y> <z> <pitch> <yaw> <roll>` | Teletransporta la cámara |
| `sm_shots_cvar <nombre> [valor]` | Lee o cambia una cvar del juego |
| `sm_shots_unhook` | Detiene los cambios que el plugin hace en cada frame (diagnóstico) |
| `sm_shots_stop` | Interrumpe una secuencia en curso |
| `sm_shots_quit` | Cierra el juego cuando termine la secuencia |
| `client <comando>` | Ejecuta un comando como si el jugador lo hubiera escrito en la consola |

---

## Créditos

- Skins: cada skin pertenece a su autor en Steam Workshop. Este repositorio no distribuye skins.
- [SourceMod](https://www.sourcemod.net) y [Metamod:Source](https://www.metamodsource.net).
- Hecho para el servidor **L4D2 Zone**.
