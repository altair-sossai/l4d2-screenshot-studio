# 2. O estúdio: uma cópia do jogo

O estúdio não roda no jogo que você usa para jogar. Ele roda numa **cópia completa da pasta do Left 4 Dead 2**, por padrão em `E:\L4D2-Studio`. Este documento explica por quê, o que vai dentro dela e como ela é aberta.

---

## 2.1 Por que uma cópia separada

Três motivos:

1. **SourceMod em servidor local.** O plugin precisa de Metamod e SourceMod instalados dentro de `left4dead2/addons`. Num jogo que você usa para jogar online, isso é sujeira: arquivos extras, plugins carregando em toda partida local.
2. **Anti-cheat e arquivos verificados.** O servidor L4D2 Zone usa um anti-cheat no cliente que confere arquivos do jogo. Colocar centenas de skins soltas e DLLs do SourceMod na pasta do jogo de verdade é pedir para dar conflito. Na cópia, isso não importa.
3. **Liberdade para quebrar.** A cópia pode ser aberta com `-insecure`, pode ter configurações gráficas próprias, addons desligados, arquivos de teste... sem afetar o seu jogo.

> **Cuidado com o que vem junto na cópia.** Quando se copia a pasta do jogo, vem *tudo*: addons da Workshop, configs (`cfg/autoexec.cfg`, configs de terceiros), `video.txt` com as configurações gráficas. Dois problemas sérios do projeto vieram disso, veja o [diário de problemas](10-problemas-e-solucoes.md): addons da Workshop carregando junto e uma configuração gráfica que escondia os braços.

---

## 2.2 O que é `-insecure`

O L4D2 usa a **VAC** (Valve Anti-Cheat). Rodar Metamod/SourceMod num servidor local VAC-seguro não é o uso pretendido. A opção de linha de comando `-insecure` abre o jogo **sem VAC**, o que é o certo para um ambiente de testes local e evita qualquer problema com a sua conta.

Com `-insecure` você não consegue entrar em servidores VAC. Tudo bem: a cópia do estúdio nunca é usada para jogar.

---

## 2.3 O que é instalado na cópia (`install-studio.ps1`)

```text
E:\L4D2-Studio\left4dead2\
├── addons\
│   ├── metamod.vdf                  ← diz para o jogo carregar o Metamod
│   ├── metamod\
│   │   ├── bin\*.dll                ← Metamod:Source (Windows)
│   │   └── sourcemod.vdf            ← diz para o Metamod carregar o SourceMod
│   └── sourcemod\
│       ├── bin\*.dll                ← núcleo do SourceMod
│       ├── extensions\              ← só sdktools, sdkhooks e bintools
│       ├── gamedata\                ← assinaturas/offsets do jogo
│       ├── translations\
│       ├── configs\
│       │   ├── core.cfg, languages.cfg, databases.cfg
│       │   ├── weapon_skins.cfg     ← a lista de armas e skins (do servidor)
│       │   └── skin_shots.cfg       ← as cenas do estúdio
│       └── plugins\
│           └── l4d2_skin_shots.smx  ← o plugin do estúdio (e nenhum outro)
├── models\l4d2br\                   ← modelos combinados das skins
└── materials\models\l4d2br\         ← materiais e texturas de todas as skins
```

Pontos de atenção:

- **Só o plugin do estúdio** vai para `plugins`. Nenhum plugin do servidor de verdade (anti-cheat, ranking, etc.) é carregado. Menos coisa rodando, menos surpresa.
- **Só as extensões necessárias.** Extensões a mais (por exemplo `dhooks`) só entram se algum plugin precisar.
- As **skins** são copiadas soltas para `models\l4d2br` e `materials\models\l4d2br`. Arquivos soltos na pasta `left4dead2` têm prioridade sobre os arquivos de dentro dos VPKs do jogo, então o jogo os encontra sem precisar empacotar nada.
- O script **apaga e recopia** `models\l4d2br` e `materials\models\l4d2br` a cada execução, para nunca sobrar skin velha.

---

## 2.4 Abrindo a cópia (`run-studio.ps1`)

```powershell
.\scripts\run-studio.ps1 -Map c5m1_waterfront
```

O script executa:

```text
left4dead2.exe -novid -insecure -windowed -noborder -w 1920 -h 1080 +sv_lan 1 +sv_cheats 1 +map c5m1_waterfront
```

| Opção | Para quê |
|---|---|
| `-novid` | Pula o vídeo de abertura da Valve |
| `-insecure` | Sem VAC (seção 2.2) |
| `-windowed -noborder` | Janela sem borda: o print sai exatamente do tamanho pedido |
| `-w 1920 -h 1080` | Resolução fixa: todos os prints têm o mesmo tamanho |
| `+sv_lan 1` | Servidor local, sem anunciar na internet |
| `+sv_cheats 1` | Libera comandos de teste (`give`, `noclip`, `director_stop`...) |
| `+map c5m1_waterfront` | Já entra direto no mapa das fotos |

Antes de abrir, o script:

- **recusa abrir** se já houver um `left4dead2.exe` rodando (não dá para ter duas instâncias, e pode ser o seu jogo de verdade aberto);
- **apaga a fila de comandos** antiga, para o plugin não executar comandos esquecidos de uma sessão anterior.

### A cena de abertura do mapa

The Parish (`c5m1_waterfront`) começa com uma **cutscene**: os sobreviventes chegam de barco, e a câmera é controlada pelo mapa. Durante a cutscene o barco está no cais, a visão fica inclinada e os braços em primeira pessoa não aparecem. **Espere a cutscene terminar antes de rodar qualquer coisa**: o barco vai embora e a visão volta ao normal. O [passo a passo](11-passo-a-passo.md) mostra como saber que ela terminou.

---

## 2.5 Configurações gráficas

O estúdio usa as configurações gráficas salvas em `left4dead2\cfg\video.txt` **da cópia**. Elas valem por completo só quando o jogo é aberto. Alterar a qualidade com o jogo aberto aplica parte das mudanças na hora; outras só no próximo início.

Foi exatamente assim que um problema ficou escondido por um tempo: as fotos estavam boas, o jogo foi reiniciado, e a partir daí uma configuração gráfica passou a valer e os braços sumiram. Veja o [diário de problemas](10-problemas-e-solucoes.md#os-braços-sumiram-da-primeira-pessoa).

---

## 2.6 Desligando o que não deve estar lá

Depois de copiar o jogo, confira:

| O quê | Onde | Por quê |
|---|---|---|
| Addons da Workshop | `left4dead2\addons\workshop\*.vpk` | Podem trocar modelos de armas, braços, sobreviventes, sons. Tire a pasta da cópia |
| Addons soltos | `left4dead2\addons\*.vpk` | Mesma coisa |
| Configs de terceiros | `left4dead2\cfg\autoexec.cfg` | Podem mexer em HUD, FOV da arma, olhos (`r_eyesize`), etc. |
| Arquivos soltos de mods | `left4dead2\models`, `materials`, `expressions`, `scripts` | Arquivos soltos têm prioridade sobre os VPKs do jogo |

---

Próximo: [3. Conversando com o jogo](03-comunicacao.md)
