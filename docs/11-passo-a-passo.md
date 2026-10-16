# 11. Passo a passo completo

Do zero até as fotos prontas. Cada passo diz o que fazer, o que esperar e como saber se deu certo.

---

## Passo 0: o que você precisa

| Item | Onde conseguir |
|---|---|
| Windows + PowerShell 7 (`pwsh`) | `winget install Microsoft.PowerShell` |
| Left 4 Dead 2 instalado pela Steam | Steam |
| Metamod:Source e SourceMod para L4D2 (Windows) | [metamodsource.net](https://www.metamodsource.net) e [sourcemod.net](https://www.sourcemod.net). Extraia os dois na **mesma pasta**, para ficar `addons\metamod` e `addons\sourcemod` lado a lado |
| As skins | Um `weapon_skins.cfg` (formato no [documento 4](04-plugin.md#43-carregando-as-skins-loadskins)) e uma pasta com `models\l4d2br\...` e `materials\models\l4d2br\...` |
| ~15 GB livres | Para a cópia do jogo |

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

---

## Passo 3: abrir o estúdio

```powershell
.\scripts\run-studio.ps1
```

O jogo abre em janela, já carregando The Parish. Espere:

1. o mapa carregar;
2. **a cutscene de abertura terminar** (o barco vai embora e a visão fica normal, uns 2 a 3 minutos).

Para confirmar que o plugin está vivo:

```powershell
.\scripts\send.ps1 sm_shots_where
Get-Content 'E:\L4D2-Studio\left4dead2\addons\sourcemod\data\skin_shots.log' -Tail 3
```

Deve aparecer uma linha `where origin ... team 2 alive 1 observer 0`.

> Não clique na janela do jogo nem abra o console enquanto o estúdio trabalha: console aberto pausa o jogo.

---

## Passo 4: conferir uma cena

```powershell
.\scripts\send.ps1 sm_shots_show volcanic-uzi hand
.\scripts\send.ps1 sm_shots_snap teste
```

Abra `E:\L4D2-Studio\left4dead2\screenshots\skinshots\test\teste.jpg`. Você deve ver a arma com a skin, **com a mão e o braço**, sem HUD.

Faça o mesmo com `ground`, `third` e `third2`.

---

## Passo 5: calibrar o enquadramento (uma vez)

```powershell
.\scripts\calibrate.ps1
```

Leva ~15 minutos. Ele escreve uma linha por arma e por cena:

```text
third weapon_smg (volcanic-uzi): 5.85 222.76 8 actor 170
...
framing saved to ...\config\skin_shots.cfg
```

Só precisa rodar de novo se:

- uma **arma nova** for adicionada (rode só ela: `-Weapons weapon_nova`);
- a **cena** mudar (outra posição, outro mapa, outra pose).

Skins novas de armas que já existem **não** precisam de calibração.

---

## Passo 6: tirar as fotos

```powershell
.\scripts\send.ps1 sm_shots_run all
```

Para 196 skins × 4 cenas = 784 fotos, leva ~30 minutos. Acompanhe pelo log:

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

Só uma cena:

```powershell
.\scripts\send.ps1 sm_shots_run third
```

Para fechar o jogo sozinho no fim (bom para rodar à noite):

```powershell
.\scripts\send.ps1 sm_shots_quit
```

---

## Passo 7: tratar as imagens

```powershell
.\scripts\process-shots.ps1
```

Gera, para cada skin, as seis fotos em AVIF e WebP em `output\<skin>\` (grande 1280×720, miniatura 320×180 e, para as fotos 1, 5 e 6, o quadrado de 540 px do card) e a folha de revisão `output\contact-sheet.jpg`. Precisa do `ffmpeg` no PATH (`winget install Gyan.FFmpeg`) e leva ~6 minutos para 196 skins. Abra a folha e confira linha por linha. Os formatos e a escolha da compressão estão no [documento 9](09-tratamento.md).

Para refazer só algumas skins: `.\scripts\process-shots.ps1 -Skins volcanic-uzi,old-katana`.

> Ao fotografar a primeira pessoa, abra o jogo de novo (em vez de recarregar o mapa com `map`) e espere a cena de abertura terminar. Depois de um `map`, os braços podem não aparecer (veja o [diário](10-problemas-e-solucoes.md#recarregar-o-mapa-sumia-com-os-braços)).

---

## Resumo dos tempos

| Etapa | Tempo |
|---|---|
| Copiar o jogo | 5 a 10 min |
| Instalar | 1 min |
| Abrir + cutscene | 3 min |
| Calibrar (uma vez) | 15 min |
| 784 fotos | 30 min |
| Tratar (AVIF e WebP) | 6 min |

---

Próximo: [12. Glossário](12-glossario.md)
