# 11. Passo a passo completo

Do zero até as fotos prontas. Cada passo diz o que fazer, o que esperar e como saber se deu certo.

---

## Passo 0: o que você precisa

| Item | Onde conseguir |
|---|---|
| Windows + PowerShell 7 (`pwsh`) | `winget install Microsoft.PowerShell`. Rode todos os scripts no `pwsh`: o `calibrate.ps1` e o `process-shots.ps1` não funcionam no Windows PowerShell 5.1 |
| Left 4 Dead 2 instalado pela Steam | Steam. A Steam precisa estar aberta quando a cópia for aberta |
| Metamod:Source e SourceMod para L4D2, versão estável para **Windows** | [metamodsource.net](https://www.metamodsource.net/downloads.php) e [sourcemod.net](https://www.sourcemod.net/downloads.php). SourceMod **1.11 ou mais novo**: o plugin usa `GetCmdArgInt` e `GetCmdArgFloat`, que não existem no 1.10. Extraia os dois `.zip` na **mesma pasta**, para ficar `addons\metamod` e `addons\sourcemod` lado a lado |
| ffmpeg com os codificadores `libaom-av1` e `libwebp` | `winget install Gyan.FFmpeg`. Confira com `ffmpeg -encoders`. Se não estiver no PATH, passe o caminho com `process-shots.ps1 -FFmpeg <caminho do ffmpeg.exe>` |
| As skins | Um `weapon_skins.cfg` e uma pasta com `models\l4d2br\...` e `materials\models\l4d2br\...` (ver [Preparando as suas skins](#preparando-as-suas-skins)) |
| ~15 GB livres | Para a cópia do jogo |

A pasta que você passa em `-SourceMod` deve ficar assim (é isso que o `install-studio.ps1` confere e copia):

```text
<pasta do SourceMod>\
└── addons\
    ├── metamod.vdf                      ← do Metamod
    ├── metamod\
    │   ├── bin\*.dll                    ← do Metamod
    │   └── sourcemod.vdf                ← do SourceMod
    └── sourcemod\
        ├── bin\  extensions\  gamedata\  translations\  configs\
        └── scripting\
            ├── spcomp.exe               ← compilador usado para gerar o .smx
            └── include\
```

> **Scripts bloqueados?** Se o PowerShell recusar rodar os `.ps1` (arquivos baixados da internet vêm marcados), desbloqueie a pasta com `Get-ChildItem -Recurse | Unblock-File` ou ajuste a política só para o seu usuário: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.

---

## Preparando as suas skins

O estúdio não cria skins: ele fotografa skins já empacotadas no formato do servidor L4D2 Zone, explicado no [documento 6](06-mao-e-chao.md#61-como-as-skins-chegam-ao-jogo). Você precisa de duas coisas.

### O `weapon_skins.cfg`

```text
"WeaponSkins"
{
    "Weapons"
    {
        "weapon_smg"                                   ← classe da arma
        {
            "view_model"    "models/l4d2br/weapons/smg/v.mdl"   ← modelo combinado da primeira pessoa
            "world_model"   "models/l4d2br/weapons/smg/w.mdl"   ← modelo combinado do mundo
        }
    }
    "Skins"
    {
        "minha-skin-uzi"                               ← id da skin: vira o nome dos arquivos
        {
            "weapon"   "weapon_smg"                    ← tem de existir em "Weapons"
            "skin"     "1"                             ← família (m_nSkin) dentro do modelo combinado
        }
    }
}
```

Regras que os scripts exigem (o `calibrate.ps1` e o `process-shots.ps1` leem o arquivo com uma expressão regular, não com um leitor de KeyValues):

- o **id** da skin só pode ter letras minúsculas, números e hífen (`[a-z0-9-]`);
- `"weapon"` tem de ser a **primeira chave** dentro do bloco da skin, logo depois do `{`;
- o nome da skin fica numa linha e o `{` na linha seguinte, como no exemplo.

Uma skin fora dessas regras ainda é fotografada pelo plugin, mas a calibração não a usa como amostra da arma e o tratamento não sabe se ela é melee (o recorte do card da primeira pessoa fica no lugar das armas de fogo).

### A pasta das skins (`-Assets`)

O `install-studio.ps1` exige uma pasta `models` dentro dela, mas copia **somente** estas duas subpastas, e ignora em silêncio as que não existirem:

```text
<pasta das skins>\
├── models\l4d2br\...
└── materials\models\l4d2br\...
```

Se os seus modelos e materiais estiverem em outra subpasta, copie-a à mão para `<pasta do estúdio>\left4dead2\`, mantendo os mesmos caminhos relativos, depois de rodar o script. Os caminhos de `view_model` e `world_model` no `weapon_skins.cfg` têm de bater com onde os arquivos ficaram.

### Armas que o `skin_shots.cfg` ainda não conhece

O [`config/skin_shots.cfg`](../config/skin_shots.cfg) do repositório tem enquadramento (`framing`) e pose (`animations`) para as armas que o L4D2 Zone usa: SMG, SMG silenciada, MP5, as duas escopetas de bomba, Magnum e nove armas melee. Para uma arma fora dessa lista:

- as fotos de chão e de terceira pessoa saem com o ângulo e o zoom da cena, sem ajuste por arma, até você rodar a calibração para ela (passo 5);
- na terceira pessoa o sobrevivente usa a pose `Idle_Standing_SMG`, a padrão do plugin. Para outra pose, acrescente a arma na seção `animations` (ver [documento 5](05-cenas.md#55-animações-pose-do-sobrevivente)).

---

## Passo 1: copiar o jogo

Feche o Left 4 Dead 2 e copie a pasta inteira do jogo:

```powershell
Copy-Item 'C:\Program Files (x86)\Steam\steamapps\common\Left 4 Dead 2' 'E:\L4D2-Studio' -Recurse
```

Depois, **limpe a cópia** (ver [documento 2](02-estudio.md#26-desligando-o-que-não-deve-estar-lá)):

```powershell
Move-Item 'E:\L4D2-Studio\left4dead2\addons\workshop' 'E:\workshop-da-copia'
```

> Nunca use a pasta do jogo que você joga como estúdio.

### Se a cópia não estiver em `E:\L4D2-Studio`

`E:\L4D2-Studio` é só o padrão dos scripts. Para usar outra pasta:

```powershell
$env:L4D2_STUDIO = '<pasta do estúdio>'   # lida pelo send.ps1 e pelo calibrate.ps1 (vale para esta sessão do terminal)
```

e passe `-Studio '<pasta do estúdio>'` para o `install-studio.ps1`, o `run-studio.ps1` e o `process-shots.ps1`, que **não** leem a variável. Nos comandos abaixo, troque `E:\L4D2-Studio` pela sua pasta.

---

## Passo 2: instalar o estúdio na cópia

```powershell
.\scripts\install-studio.ps1 `
    -Studio 'E:\L4D2-Studio' `
    -SourceMod 'D:\downloads\sourcemod-l4d2' `
    -SkinsConfig 'D:\skins\weapon_skins.cfg' `
    -Assets 'D:\skins\assets'
```

O script:

1. compila o plugin com o `spcomp.exe` do SourceMod (gera `build\l4d2_skin_shots.smx`);
2. copia Metamod, SourceMod (só o necessário), o plugin e as configs;
3. copia as skins;
4. avisa se ainda houver addons da Workshop na cópia;
5. se o nível de shader estiver no máximo (`gpu_level 3`), baixa para 2, porque no máximo **os braços em primeira pessoa não são desenhados** (ver o [diário](10-problemas-e-solucoes.md#os-braços-sumiram-da-primeira-pessoa)).

Deu certo se terminar com `Studio ready at E:\L4D2-Studio`.

Rode o script de novo (com o jogo fechado) sempre que mudar o `weapon_skins.cfg`, os arquivos das skins ou o plugin: ele recompila e recopia tudo. O plugin lê os configs **da cópia do jogo**, não os do repositório. Se você editar o `config\skin_shots.cfg` à mão, copie-o para `E:\L4D2-Studio\left4dead2\addons\sourcemod\configs\` (ou rode o `install-studio.ps1` de novo); a calibração já faz essa cópia sozinha.

---

## Passo 3: abrir o estúdio

```powershell
.\scripts\run-studio.ps1
```

Com a Steam aberta, o jogo abre em janela sem borda, em 1600×900 (mude com `-Width` e `-Height`; mantenha 16:9 e, se mudar, rode a calibração de novo; ao mudar a resolução pelo menu do jogo, confira se o `video.txt` não voltou para `"setting.gpu_level" "3"`, que esconde os braços), já carregando The Parish (`c5m1_waterfront`, o único mapa com cenas no `skin_shots.cfg`). O script não espera o jogo: ele só o abre. Espere:

1. o mapa carregar;
2. **a cutscene de abertura terminar** (o barco vai embora e a visão fica normal, uns 2 a 3 minutos).

Para confirmar que o plugin está vivo:

```powershell
.\scripts\send.ps1 sm_shots_where
Get-Content 'E:\L4D2-Studio\left4dead2\addons\sourcemod\data\skin_shots.log' -Tail 3
```

Deve aparecer uma linha `where origin ... team 2 alive 1 observer 0`. Mais acima no mesmo log, ao carregar o mapa, o plugin escreve `loaded <n> weapons and <n> skins` e `loaded 7 scenes for c5m1_waterfront` (as seis cenas de foto mais a `park`). Se o log nem existir, veja [Quando algo dá errado](#quando-algo-dá-errado).

> Não clique na janela do jogo nem abra o console enquanto o estúdio trabalha: console aberto pausa o jogo.

---

## Passo 4: conferir uma cena

```powershell
.\scripts\send.ps1 sm_shots_show volcanic-uzi hand
.\scripts\send.ps1 sm_shots_snap teste
```

Troque `volcanic-uzi` (uma skin do L4D2 Zone) pelo id de uma skin do **seu** `weapon_skins.cfg`. Abra `E:\L4D2-Studio\left4dead2\screenshots\skinshots\test\teste.jpg`. Você deve ver a arma com a skin, **com a mão e o braço**, sem HUD.

Faça o mesmo com `ground`, `ground2`, `ground3`, `third` e `third2`.

---

## Passo 5: calibrar o enquadramento (uma vez)

```powershell
.\scripts\calibrate.ps1
```

Com o jogo aberto e a cutscene terminada. Por padrão calibra só `third` e `third2`, usando a primeira skin de cada arma do `weapon_skins.cfg` instalado na cópia. Leva ~15 minutos. Ele escreve uma linha por arma e por cena:

```text
third weapon_smg (volcanic-uzi): 5.85 222.76 8 actor 170
...
framing saved to ...\config\skin_shots.cfg
```

O resultado é gravado **no `config\skin_shots.cfg` do repositório** (o `git` vai mostrar o arquivo alterado) e copiado para a cópia do jogo. Não edite esse arquivo enquanto a calibração roda, e mantenha a indentação com **tabs**: o script acha as cenas por expressão regular contando os tabs.

As cenas de chão também podem ser calibradas, e uma arma nova precisa delas:

```powershell
.\scripts\calibrate.ps1 -Scenes ground,ground2,ground3 -Weapons weapon_nova
.\scripts\calibrate.ps1 -Weapons weapon_nova
```

A cena `hand` não é calibrada: ela usa o mesmo ângulo para todas as armas.

Só precisa rodar de novo se:

- uma **arma nova** for adicionada (rode só ela, com `-Weapons`);
- a **cena** mudar (outra posição, outro mapa, outra pose);
- a **resolução** ou a proporção da janela mudar.

Skins novas de armas que já existem **não** precisam de calibração.

---

## Passo 6: tirar as fotos

```powershell
.\scripts\send.ps1 sm_shots_run all
```

São seis fotos por skin (196 skins × 6 cenas = 1.176 fotos no L4D2 Zone). Cada foto leva uns 2 a 3 segundos (o `settle` de 1,6 s mais a gravação; ~4,6 s na primeira pessoa, que espera 4 s), então conte com perto de uma hora para esse volume. Antes de cada print o plugin apaga os `.jpg` soltos em `E:\L4D2-Studio\left4dead2\screenshots\` (os da subpasta `skinshots` ficam). Acompanhe pelo log:

```powershell
Get-Content 'E:\L4D2-Studio\left4dead2\addons\sourcemod\data\skin_shots.log' -Tail 1 -Wait
```

Termina com `done`. Procure problemas:

```powershell
Select-String -Path 'E:\L4D2-Studio\left4dead2\addons\sourcemod\data\skin_shots.log' -Pattern 'missing|skipped|could not'
```

Só algumas skins ou armas:

```powershell
.\scripts\send.ps1 sm_shots_run all volcanic-uzi weapon_melee_katana
```

Só uma cena, ou algumas separadas por vírgula:

```powershell
.\scripts\send.ps1 sm_shots_run third
.\scripts\send.ps1 sm_shots_run ground,ground2,ground3
```

Para interromper: `.\scripts\send.ps1 sm_shots_stop`.

Para fechar o jogo sozinho no fim (bom para rodar à noite):

```powershell
.\scripts\send.ps1 sm_shots_quit
```

---

## Passo 7: tratar as imagens

```powershell
.\scripts\process-shots.ps1
```

Gera, para cada skin, as seis fotos em AVIF e WebP em `output\<skin>\` (grande na resolução do print, miniatura 320×180 e, para as fotos 1, 5 e 6, o quadrado de 540 px do card) e a folha de revisão `output\contact-sheet.jpg`. Precisa do `ffmpeg` com `libaom-av1` e `libwebp` no PATH (`winget install Gyan.FFmpeg`, ou `-FFmpeg <caminho>`) e leva ~6 minutos para 196 skins. Lê os prints de `<pasta do estúdio>\left4dead2\screenshots\skinshots` (passe `-Studio` se a cópia não estiver em `E:\L4D2-Studio`) e não precisa do jogo aberto. Outros parâmetros: `-Output` e `-ContactSheet` (destino), `-Parallel` (fotos codificadas ao mesmo tempo, padrão 6) e os tamanhos e qualidades descritos no [documento 9](09-tratamento.md). Abra a folha e confira linha por linha. Os formatos e a escolha da compressão estão no [documento 9](09-tratamento.md).

Para refazer só algumas skins: `.\scripts\process-shots.ps1 -Skins volcanic-uzi,old-katana`.

> Ao fotografar a primeira pessoa, abra o jogo de novo (em vez de recarregar o mapa com `map`) e espere a cena de abertura terminar. Depois de um `map`, os braços podem não aparecer (veja o [diário](10-problemas-e-solucoes.md#recarregar-o-mapa-sumia-com-os-braços)).

---

## Resumo dos tempos

| Etapa | Tempo |
|---|---|
| Copiar o jogo | 5 a 10 min |
| Instalar | 1 min |
| Abrir + cutscene | 3 min |
| Calibrar `third` e `third2` (uma vez) | 15 min |
| 1.176 fotos | perto de 1 h (estimativa: 2 a 3 s por foto) |
| Tratar (AVIF e WebP) | 6 min |

---

## O que refazer quando algo muda

| Mudou | Refaça |
|---|---|
| `weapon_skins.cfg` ou os arquivos das skins | `install-studio.ps1` (jogo fechado), abrir o estúdio, `sm_shots_run` só das skins novas, `process-shots.ps1 -Skins ...` |
| Arma nova | Tudo acima, mais a calibração dessa arma (passo 5) |
| `config\skin_shots.cfg` editado à mão | Copiar para a cópia do jogo (ver passo 2). O plugin relê o arquivo a cada `sm_shots_run` e `sm_shots_show`, sem reabrir o jogo |
| Plugin (`.sp`) | `install-studio.ps1` com o jogo fechado, ou compilar e recarregar sem fechar (ver [documento 4](04-plugin.md#410-compilando)) |

---

## Quando algo dá errado

Primeiro, o log: `E:\L4D2-Studio\left4dead2\addons\sourcemod\data\skin_shots.log`. Ele nunca é apagado, então leia o fim (`-Tail`).

| Mensagem ou sintoma | Causa | O que fazer |
|---|---|---|
| `No game copy at ...` | `-Studio` não aponta para a pasta com `left4dead2.exe` | Corrija o caminho |
| `No SourceMod at ...` | A pasta de `-SourceMod` não tem `addons\sourcemod\bin` | Extraia Metamod e SourceMod na mesma pasta (passo 0) |
| `Plugin did not compile` | Erro do `spcomp`, mostrado logo acima | SourceMod 1.11 ou mais novo, com a pasta `scripting\include` completa |
| `Left 4 Dead 2 is already running` | Já existe um `left4dead2.exe` aberto (pode ser o seu jogo de verdade) | Feche o jogo antes |
| O `send.ps1` responde `queued:`, mas o log não muda (ou nem existe) | O plugin não carregou, ou o `send.ps1` escreve em outra pasta | Confira `$env:L4D2_STUDIO`; veja `addons\sourcemod\logs\` da cópia; antes de fotografar, no console do jogo, `meta list` e `sm plugins list` devem mostrar o SourceMod e o `L4D2 Skin Shots` |
| `could not read ...weapon_skins.cfg` / `...skin_shots.cfg` | Config ausente na cópia | Rode o `install-studio.ps1` de novo |
| `no scenes for map ...` / `scene ... is not configured for this map` | O mapa aberto não tem seção no `skin_shots.cfg`, ou a cena não existe nele | Abra pelo `run-studio.ps1` (The Parish) ou crie as cenas do seu mapa ([documento 5](05-cenas.md)) |
| `no host` | Ainda não há jogador no jogo (mapa carregando) | Espere o mapa e a cutscene |
| `unknown skin ...` / `skipped ...` | O id não está no `weapon_skins.cfg` **da cópia**, ou a cena falhou (veja a linha anterior) | Confira o id; rode o `install-studio.ps1` depois de editar o config |
| `no models for weapon_...` | A arma da skin não está na seção `Weapons` | Acrescente `view_model` e `world_model` dela |
| `could not give ...` | O jogo não entregou a arma na cena `hand` | Confira a classe da arma (`weapon_...`) |
| `missing screenshot for ...` | O print não apareceu em 8 s (20 tentativas de 0,4 s), por exemplo com o jogo pausado pelo console aberto | Feche o console e rode de novo só as skins afetadas |
| Arma sem mão e sem braço na `hand` | Cutscene ainda rodando, mapa recarregado com `map` ou `gpu_level 3` | Veja o [diário](10-problemas-e-solucoes.md#os-braços-sumiram-da-primeira-pessoa) |
| Fotos todas iguais | Jogo pausado com o console aberto | Não abra o console durante a sequência |
| Modelos, braços ou HUD diferentes do jogo original | Addons da Workshop ou configs copiados junto | Limpe a cópia ([documento 2](02-estudio.md#26-desligando-o-que-não-deve-estar-lá)) |
| `screenshot cal_... not saved` (calibração) | O plugin não respondeu em 10 s | Jogo aberto, cutscene terminada, `$env:L4D2_STUDIO` certo |
| `scene ... not found in skin_shots.cfg` (calibração) | Nome de cena errado em `-Scenes`, ou a indentação com tabs foi perdida | Confira o nome e os tabs |
| `weapon not found on screen` (calibração) | A arma está fora do quadro com o ângulo e o zoom da cena | Ajuste `angles`/`fov` da cena e calibre de novo |
| `No screenshots in ...` (tratamento) | `-Studio` errado, ou nenhuma foto tirada ainda | Passe `-Studio` |
| `ffmpeg failed for: ...` (tratamento) | `ffmpeg` sem `libaom-av1` ou `libwebp` | Instale um build completo (`ffmpeg -encoders` deve listar os dois) |

---

Próximo: [12. Glossário](12-glossario.md)
