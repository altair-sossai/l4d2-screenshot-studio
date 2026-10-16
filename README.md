# L4D2 Screenshot Studio

Estúdio automático de fotos para skins de armas do **Left 4 Dead 2**.

Ele tira, sozinho e sempre do mesmo jeito, quatro fotos de cada skin:

| Foto | O que mostra |
|---|---|
| `hand` | Primeira pessoa, segurando a arma (o que o jogador vê na tela) |
| `ground` | A arma caída no chão, vista de cima |
| `third` | Um sobrevivente segurando a arma, em close na arma |
| `third2` | O mesmo sobrevivente, num plano mais aberto |

Foi construído para fotografar as **196 skins** da loja do servidor L4D2 Zone, mas funciona para qualquer conjunto de skins que siga o mesmo formato de configuração.

> Este repositório é também um **material de estudo**. Cada decisão, cada problema encontrado e cada solução está explicada nos documentos da pasta [`docs/`](docs). Se você quer entender *como* e *por que* tudo funciona, comece pelo [guia de leitura](#guia-de-leitura).

---

## Como funciona, em uma frase

Um **plugin SourceMod** roda dentro de um servidor local do jogo, monta cada cena (posiciona a câmera, coloca a arma na mão, no chão ou na mão de um sobrevivente, aplica a skin) e manda o próprio jogo tirar um screenshot. **Scripts PowerShell** do lado de fora enviam comandos para o plugin, calibram o enquadramento e tratam as imagens.

```text
  ┌────────────────────────────┐        arquivo de fila         ┌────────────────────────────────────┐
  │  PowerShell (seu terminal) │ ─────────────────────────────▶ │  Left 4 Dead 2 (cópia "estúdio")    │
  │                            │  skin_shots_queue.txt          │                                    │
  │  send.ps1                  │                                │  SourceMod + plugin l4d2_skin_shots │
  │  calibrate.ps1             │ ◀───────────────────────────── │   - monta a cena                   │
  │  process-shots.ps1         │  screenshots/skinshots/*.jpg   │   - aplica a skin                  │
  └────────────────────────────┘  skin_shots.log                │   - tira o screenshot (jpeg)       │
                                                                └────────────────────────────────────┘
```

---

## Estrutura do repositório

```text
l4d2-screenshot-studio/
├── README.md                      ← você está aqui
├── plugin/
│   └── l4d2_skin_shots.sp         ← plugin SourceMod (o "diretor de fotografia")
├── config/
│   └── skin_shots.cfg             ← cenas: câmera, posição da arma, do sobrevivente, enquadramento
├── scripts/
│   ├── install-studio.ps1         ← instala Metamod, SourceMod, plugin e skins na cópia do jogo
│   ├── run-studio.ps1             ← abre a cópia do jogo no mapa certo, na resolução certa
│   ├── send.ps1                   ← envia um comando para o plugin
│   ├── calibrate.ps1              ← calibra automaticamente o enquadramento de cada arma
│   └── process-shots.ps1          ← recorta, comprime e monta a folha de revisão
├── tools/
│   ├── sheet.ps1                  ← junta vários prints numa folha (para revisar rápido)
│   ├── diffimg.ps1                ← mostra a diferença entre dois prints (diagnóstico)
│   └── crop.ps1                   ← recorta a mesma região de vários prints (diagnóstico)
└── docs/                          ← a documentação para estudo (leia na ordem)
```

---

## Guia de leitura

Os documentos foram escritos para serem lidos em ordem. Cada um parte do que o anterior explicou.

| # | Documento | Assunto |
|---|---|---|
| 1 | [Conceitos básicos](docs/01-conceitos-basicos.md) | Source Engine, SourceMod, entidades, modelos, skins/famílias, viewmodel x worldmodel |
| 2 | [O estúdio: uma cópia do jogo](docs/02-estudio.md) | Por que uma cópia separada, `-insecure`, o que é instalado, como abrir |
| 3 | [Conversando com o jogo](docs/03-comunicacao.md) | A fila de comandos, o log, por que não usamos RCON nem o console |
| 4 | [O plugin, parte por parte](docs/04-plugin.md) | Leitura guiada do `l4d2_skin_shots.sp` |
| 5 | [As cenas](docs/05-cenas.md) | O `skin_shots.cfg`, coordenadas, ângulos, FOV e como achar uma boa posição |
| 6 | [Primeira pessoa e chão](docs/06-mao-e-chao.md) | Trocar o modelo da arma na mão, armas melee restritas, arma no chão |
| 7 | [Terceira pessoa](docs/07-terceira-pessoa.md) | Sobrevivente "manequim", animação congelada, arma presa no osso da mão |
| 8 | [Enquadramento automático](docs/08-enquadramento-automatico.md) | A calibração: diferença de imagens, matemática de câmera, convergência |
| 9 | [Tratamento das imagens](docs/09-tratamento.md) | Recorte 16:9, compressão, folha de revisão |
| 10 | [Diário de problemas](docs/10-problemas-e-solucoes.md) | Todos os problemas reais que apareceram e como cada um foi resolvido |
| 11 | [Passo a passo completo](docs/11-passo-a-passo.md) | Do zero até as fotos prontas |
| 12 | [Glossário](docs/12-glossario.md) | Termos usados nos documentos |

---

## Uso rápido

> Pré-requisitos: Windows, PowerShell 7 (`pwsh`), uma **cópia** da pasta do Left 4 Dead 2 (não use a pasta que você joga) e as skins no formato descrito em [docs/06](docs/06-mao-e-chao.md).

```powershell
# 1. Compila o plugin e instala Metamod, SourceMod, o plugin, as configs e as skins na cópia do jogo
.\scripts\install-studio.ps1 -Studio E:\L4D2-Studio -SourceMod <pasta do SourceMod> -SkinsConfig <weapon_skins.cfg> -Assets <pasta das skins>

# 2. Abre a cópia do jogo em The Parish e espera a cutscene de abertura terminar (~3 min)
.\scripts\run-studio.ps1

# 3. (Uma vez) calibra o enquadramento de cada arma na terceira pessoa
.\scripts\calibrate.ps1

# 4. Tira todas as fotos de todas as skins
.\scripts\send.ps1 sm_shots_run all

# 5. Recorta, comprime e monta a folha de revisão
.\scripts\process-shots.ps1
```

Os detalhes de cada passo estão no [passo a passo completo](docs/11-passo-a-passo.md).

---

## Comandos do plugin

Todos são enviados com `.\scripts\send.ps1 <comando>`.

| Comando | O que faz |
|---|---|
| `sm_shots_run <cena\|all> [skins ou armas...]` | Tira as fotos. Sem filtro, faz todas as skins. Faz todas as skins de uma cena antes de passar para a próxima |
| `sm_shots_show <skin> <cena>` | Monta uma cena sem fotografar (para conferir na tela) |
| `sm_shots_snap <nome>` | Tira um print avulso para `screenshots/skinshots/test/<nome>.jpg` |
| `sm_shots_frame <pitch> <yaw> <fov>` | Gira a câmera e muda o zoom, sem mover |
| `sm_shots_turn <yaw>` | Gira o sobrevivente da terceira pessoa |
| `sm_shots_weapon <0\|1\|noshadow>` | Esconde ou mostra a arma da terceira pessoa, ou desliga a sombra dela |
| `sm_shots_where` | Escreve no log a posição, os ângulos e o estado do jogador |
| `sm_shots_goto <x> <y> <z> <pitch> <yaw> <roll>` | Teleporta a câmera |
| `sm_shots_cvar <nome> [valor]` | Lê ou altera uma cvar do jogo |
| `sm_shots_unhook` | Para as alterações que o plugin faz a cada frame (diagnóstico) |
| `sm_shots_stop` | Interrompe uma sequência em andamento |
| `sm_shots_quit` | Fecha o jogo quando a sequência terminar |
| `client <comando>` | Executa um comando como se o jogador tivesse digitado no console |

---

## Créditos

- Skins: cada skin pertence ao seu autor na Steam Workshop. Este repositório não distribui skins.
- [SourceMod](https://www.sourcemod.net) e [Metamod:Source](https://www.metamodsource.net).
- Feito para o servidor **L4D2 Zone**.
