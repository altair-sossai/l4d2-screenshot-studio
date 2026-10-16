# 4. O plugin, parte por parte

Este documento é uma leitura guiada do arquivo [`plugin/l4d2_skin_shots.sp`](../plugin/l4d2_skin_shots.sp). A ideia é abrir o código ao lado e acompanhar.

O plugin é o "diretor de fotografia": ele não sabe nada de imagem, mas sabe montar a cena, trocar a arma, posicionar a câmera e mandar o jogo fotografar.

---

## 4.1 Visão geral do fluxo

```text
OnPluginStart ──▶ registra comandos, cria o timer da fila, engancha os jogadores já conectados
OnMapStart    ──▶ lê weapon_skins.cfg (LoadSkins) e skin_shots.cfg (LoadScenes)

sm_shots_run all
   │
   ├─ monta a lista de trabalhos: "cena|skin" para cada cena e cada skin
   ├─ PrepareOutput  (cria as pastas de saída)
   ├─ PrepareWorld   (para o diretor, tira zumbis, itens soltos, HUD...)
   └─ Timer_NextJob ─▶ SetupScene ─▶ espera "settle" ─▶ Timer_Shoot (jpeg)
            ▲                                                  │
            └──────── Timer_Collect (move o .jpg) ◀────────────┘
```

Cada foto é um **trabalho** (`job`), uma string no formato `cena|skin`, por exemplo `third|abyss-uzi`. A ordem é: todas as skins da primeira cena, depois todas da segunda, e assim por diante. Isso evita trocar o tipo de cena (mão, chão, terceira pessoa) a cada foto, o que deixa a sequência mais rápida e estável.

---

## 4.2 Estruturas de dados

### `WeaponModels` — os modelos de uma arma

```sourcepawn
enum struct WeaponModels
{
    char weapon[64];               // "weapon_smg"
    char viewModel[PLATFORM_MAX_PATH];   // "models/l4d2br/weapons/smg/v.mdl"
    char worldModel[PLATFORM_MAX_PATH];  // "models/l4d2br/weapons/smg/w.mdl"
    int viewModelIndex;            // índice no precache (para m_nModelIndex)
    int worldModelIndex;
}
```

### `Skin` — uma skin

```sourcepawn
enum struct Skin
{
    char id[64];      // "abyss-uzi"
    char weapon[64];  // "weapon_smg"
    int family;       // a família dentro do modelo combinado (m_nSkin)
}
```

### `Scene` — uma cena do `skin_shots.cfg`

```sourcepawn
enum struct Scene
{
    float origin[3];        // onde a câmera (o jogador) fica
    float angles[3];        // para onde a câmera olha
    float targetOrigin[3];  // onde fica a arma no chão / o sobrevivente
    float targetAngles[3];
    bool viewModel;         // desenhar a arma em primeira pessoa?
    int fov;                // zoom (0 = padrão)
    char type[16];          // hand, ground, third ou park
}
```

### Coleções globais

| Variável | Tipo | Conteúdo |
|---|---|---|
| `g_hModels` | `ArrayList` de `WeaponModels` | Uma entrada por arma |
| `g_hSkins` | `ArrayList` de `Skin` | Uma entrada por skin, na ordem do config |
| `g_hScenes` | `StringMap` nome → `Scene` | As cenas do mapa atual |
| `g_hSceneOrder` | `ArrayList` de nomes | A ordem das cenas (a do arquivo), sem `park` |
| `g_hAnimations` | `StringMap` arma → animação | Pose do sobrevivente para cada arma |
| `g_hFraming` | `StringMap` `"cena\|arma"` → 4 floats | Enquadramento calibrado: pitch, yaw, fov e giro do sobrevivente |
| `g_hJobs` | `ArrayList` de strings | Os trabalhos da sequência atual |

### `enum struct` e `ArrayList`

Em SourcePawn, um `enum struct` é guardado num `ArrayList` com `PushArray`/`GetArray`, e num `StringMap` com `SetArray`/`GetArray`. O tamanho de cada célula é o tamanho da struct (`new ArrayList(sizeof(Skin))`).

---

## 4.3 Carregando as skins (`LoadSkins`)

Lê o `configs/weapon_skins.cfg`, o mesmo arquivo que o servidor de verdade usa:

```text
"WeaponSkins"
{
    "Weapons"
    {
        "weapon_smg"
        {
            "view_model"    "models/l4d2br/weapons/smg/v.mdl"
            "world_model"   "models/l4d2br/weapons/smg/w.mdl"
            ...
        }
    }
    "Skins"
    {
        "abyss-uzi"
        {
            "weapon"   "weapon_smg"
            "skin"     "3"
            ...
        }
    }
}
```

Para cada arma, faz `PrecacheModel` dos dois modelos combinados e guarda o índice. **Precache** é registrar o modelo no jogo; só modelos registrados podem ser usados em `m_nModelIndex`. O índice devolvido é exatamente o número que vai na netprop.

---

## 4.4 Carregando as cenas (`LoadScenes`)

Lê o `configs/skin_shots.cfg`:

- valores globais: `settle` (tempo de assentamento) e `actor_model` (modelo do sobrevivente da terceira pessoa);
- a seção `animations` (arma → animação);
- a seção com o **nome do mapa atual** (`GetCurrentMap`), com uma subseção por cena;
- dentro de cada cena, a subseção opcional `framing` (enquadramento calibrado por arma).

O `skin_shots.cfg` é recarregado em todo `sm_shots_run` e `sm_shots_show`, então dá para editar o arquivo com o jogo aberto e testar na hora.

O formato completo está no [documento 5](05-cenas.md).

---

## 4.5 Preparando o mundo (`PrepareWorld`)

Antes de fotografar, o mapa precisa ficar "limpo e parado":

```sourcepawn
ServerCommand("sv_cheats 1; director_stop; z_common_limit 0; sb_stop 1; nb_stop 1; sv_infinite_ammo 1");
ServerCommand("nb_delete_all infected");
RemoveLooseItems();
```

| Comando | Efeito |
|---|---|
| `director_stop` | O "diretor" do L4D2 para de criar hordas e eventos |
| `z_common_limit 0` | Nenhum zumbi comum |
| `sb_stop 1` | Os bots sobreviventes ficam parados |
| `nb_stop 1` | Todos os "NextBots" (infectados) param |
| `nb_delete_all infected` | Remove os infectados que já existiam |
| `sv_infinite_ammo 1` | Arma sempre carregada, sem animação de recarga |
| `RemoveLooseItems()` | Remove armas e itens soltos no mapa (kit médico no chão, armas na mesa...) |

`RemoveLooseItems` percorre todas as entidades e remove as de classe `weapon_*` ou `upgrade_*` **sem dono** (`m_hOwnerEntity`). Armas na mão de alguém ficam.

Depois, ajusta cvars do cliente com `SetLocalCvar` (explicado no [documento 3](03-comunicacao.md#clientcommand-para-mudar-cvars-do-cliente)):

| Cvar | Valor | Por quê |
|---|---|---|
| `hidehud` | `4` | Esconde o HUD inteiro (vida, munição, retratos) |
| `cl_drawhud` | `0` | Reforço |
| `crosshair` | `0` | Sem mira |
| `cl_showfps`, `cl_showpos`, `net_graph` | `0` | Sem textos de diagnóstico na tela |
| `con_drawnotify` | `0` | Sem mensagens do console no canto da tela |
| `jpeg_quality` | `95` | Qualidade do print |
| `mat_motion_blur_enabled` | `0` | Sem borrão de movimento |
| `engine_no_focus_sleep` | `0` | O jogo continua rodando rápido mesmo sem foco na janela |

Por fim, **expulsa os bots sobreviventes extras**, deixando só um (o "ator"), que é estacionado longe da câmera (cena `park`). Bots andando pelo cenário estragariam as fotos.

---

## 4.6 Montando uma cena (`SetupScene`)

É o coração do plugin. Recebe o nome da cena e o índice da skin:

```text
1. Acha a cena e o jogador humano (o "host", que é a câmera)
2. Calcula ângulos e FOV: os da cena, ou os do enquadramento calibrado para esta arma
3. Coloca o host em noclip (terceira pessoa) ou caminhando (mão/chão)
4. Teleporta o host para a posição da câmera, com os ângulos calculados
5. Liga/desliga o desenho da arma em primeira pessoa (r_drawviewmodel)
6. Aplica o FOV (m_iFOV)
7. Remove o que a cena anterior criou (RemoveProp)
8. Conforme o tipo:
   hand   → estaciona o ator, dá a arma para o host, marca a skin ativa
   ground → estaciona o ator, cria a arma no chão (SpawnProp)
   third  → estaciona o ator, cria o sobrevivente com a arma (SpawnPosedSurvivor)
```

### O host é a câmera

Não existe uma "câmera" separada: **a câmera é o próprio jogador humano**. Mover a câmera é teleportar o jogador (`TeleportEntity`). Na terceira pessoa o jogador fica em **noclip** (atravessa paredes, não cai), porque o enquadramento calibrado pode colocar a câmera em qualquer ângulo.

### `m_iFOV` e `RoundToNearest`

O FOV do jogador é um **inteiro**. O enquadramento calibrado guarda floats, então o plugin arredonda. Para zooms muito fechados (FOV 5 a 10), 1 grau faz diferença visível no tamanho da arma; a calibração leva isso em conta medindo de novo depois de cada ajuste.

---

## 4.7 A cada frame (`OnPostThinkPost`)

O SDKHooks chama esta função **depois de cada "pensamento" do jogador**, ou seja, todo frame do servidor. Ela faz duas coisas:

1. **Apaga a lanterna.** Se o efeito `EF_DIMLIGHT` (lanterna ligada) estiver ativo, desliga. A luz da lanterna estragaria a iluminação.
2. **Reaplica a skin**, se houver uma skin ativa na mão do host:
   - na arma ativa (worldmodel): `SetEntityModel`, `m_iWorldModelIndex` e `m_nSkin`;
   - no viewmodel do jogador: `m_nModelIndex` e `m_nSkin`.

Por que todo frame? Porque o jogo **restaura** o modelo original da arma em vários momentos (ao sacar, ao trocar de arma, em animações). Reaplicar sempre é a forma mais simples de garantir que o print saia com a skin certa. O plugin de skins do servidor de verdade faz o mesmo.

---

## 4.8 A sequência de fotos (timers)

```sourcepawn
Timer_NextJob  → avança g_iJob, chama SetupScene, agenda Timer_Shoot depois de "settle" segundos
Timer_Shoot    → ClientCommand(host, "jpeg"), agenda Timer_Collect a cada 0,4 s
Timer_Collect  → tenta mover o print mais novo para screenshots/skinshots/<cena>/<skin>.jpg
                 conseguiu: agenda Timer_NextJob
                 não conseguiu 20 vezes: registra "missing screenshot" e segue
```

Todos os timers usam `TIMER_FLAG_NO_MAPCHANGE`: se o mapa mudar no meio, eles morrem junto em vez de rodar num mapa errado.

`sm_shots_stop` limpa a lista de trabalhos; o próximo `Timer_NextJob` vê que acabou e para. `sm_shots_quit` marca para fechar o jogo (`quit`) quando a sequência terminar, útil para rodar à noite.

---

## 4.9 Comandos de diagnóstico

| Comando | Para quê |
|---|---|
| `sm_shots_where` | Escreve no log a posição e os ângulos do host, o time, se está vivo, o estado do HUD (`m_iHideHUD`), o personagem e os viewmodels. Foi essencial para investigar os braços sumidos |
| `sm_shots_goto` | Teleporta a câmera para testar posições |
| `sm_shots_frame` | Gira a câmera e muda o zoom sem mover (usado pela calibração) |
| `sm_shots_turn` | Gira o sobrevivente da terceira pessoa (usado pela calibração) |
| `sm_shots_weapon` | Esconde/mostra a arma da terceira pessoa e desliga a sombra (usado pela calibração) |
| `sm_shots_cvar` | Lê ou muda uma cvar, inclusive do cliente |
| `sm_shots_unhook` | Desliga o `OnPostThinkPost`, para testar o jogo "puro" |

---

## 4.10 Compilando

```powershell
spcomp.exe plugin\l4d2_skin_shots.sp -i <pasta include do SourceMod> -o build\l4d2_skin_shots.smx
```

O `spcomp.exe` e a pasta `include` vêm no pacote do SourceMod (`addons/sourcemod/scripting`). Depois de compilar, copie o `.smx` para `addons/sourcemod/plugins` da cópia do jogo e recarregue sem fechar o jogo:

```powershell
.\scripts\send.ps1 sm plugins reload l4d2_skin_shots
```

### Uma pegadinha do SourcePawn

`forward` é palavra reservada da linguagem. Uma variável chamada `forward` (natural para "vetor para frente") não compila, com um erro pouco claro (`expected token: ";", but found "forward"`). Use outro nome, como `front`.

---

Próximo: [5. As cenas](05-cenas.md)
