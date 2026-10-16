# 13. O código do plugin, função por função

O [documento 4](04-plugin.md) explicou o plugin "de cima". Este aqui desce no código: cada função importante aparece **inteira**, como está no arquivo [`plugin/l4d2_skin_shots.sp`](../plugin/l4d2_skin_shots.sp), seguida de uma explicação linha a linha.

Sugestão de estudo: abra o arquivo do plugin ao lado e leia este documento na ordem. Ele segue a ordem em que as coisas acontecem quando você roda `sm_shots_run all`.

---

## 13.1 O cabeçalho

```sourcepawn
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
```

| Linha | O que faz |
|---|---|
| `#pragma semicolon 1` | Obriga `;` no fim de cada instrução. Sem isso o SourcePawn aceita código sem ponto e vírgula, o que esconde erros |
| `#pragma newdecls required` | Obriga a sintaxe nova de declarações (`int x`, `float y[3]`, `char s[64]`). A antiga (`new x`, `Float:y`) fica proibida |
| `#include <sourcemod>` | O básico: comandos, timers, arquivos, KeyValues, `ArrayList`, `StringMap`... |
| `#include <sdktools>` | Entidades: `CreateEntityByName`, `DispatchKeyValue`, `TeleportEntity`, `AcceptEntityInput`, `PrecacheModel`... |
| `#include <sdkhooks>` | Ganchos de entidade: `SDKHook(client, SDKHook_PostThinkPost, ...)` |

### Constantes

```sourcepawn
#define SKINS_CONFIG "configs/weapon_skins.cfg"
#define SHOTS_CONFIG "configs/skin_shots.cfg"
#define QUEUE_FILE "addons/sourcemod/data/skin_shots_queue.txt"
#define LOG_FILE "addons/sourcemod/data/skin_shots.log"
#define SCREENSHOTS_DIR "screenshots"
#define OUTPUT_DIR "screenshots/skinshots"
#define MAX_SHOT_RETRIES 20
#define EF_DIMLIGHT 4
#define EF_BONEMERGE 1
#define EF_BONEMERGE_FASTCULL 128
#define EF_PARENT_ANIMATES 512
#define DEFAULT_ACTOR_MODEL "models/survivors/survivor_mechanic.mdl"
#define PROP_NAME "skin_shots_prop"
```

Dois tipos de caminho aparecem aqui:

- `SKINS_CONFIG` e `SHOTS_CONFIG` são **relativos à pasta do SourceMod**. Eles passam por `BuildPath(Path_SM, ...)`, que transforma `configs/x.cfg` em `addons/sourcemod/configs/x.cfg`.
- `QUEUE_FILE`, `LOG_FILE`, `SCREENSHOTS_DIR` e `OUTPUT_DIR` são **relativos à pasta do jogo** (`left4dead2/`). As funções de arquivo do SourceMod (`OpenFile`, `FileExists`, `RenameFile`) usam essa pasta como base.

Os `EF_*` são bits da netprop `m_fEffects`. A Source Engine define vários; o plugin só precisa destes quatro, então define os números à mão.

---

## 13.2 `OnPluginStart`: tudo começa aqui

```sourcepawn
public void OnPluginStart()
{
    g_hModels = new ArrayList(sizeof(WeaponModels));
    g_hSkins = new ArrayList(sizeof(Skin));
    g_hJobs = new ArrayList(ByteCountToCells(96));
    g_hScenes = new StringMap();
    g_hSceneOrder = new ArrayList(ByteCountToCells(16));
    g_hAnimations = new StringMap();
    g_hFraming = new StringMap();

    RegServerCmd("sm_shots_run", Command_Run, "sm_shots_run <scene|all> [skin ids or weapon classes...]");
    RegServerCmd("sm_shots_show", Command_Show, "sm_shots_show <skin> <scene>");
    ...

    CreateTimer(0.5, Timer_Queue, _, TIMER_REPEAT);

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            OnClientPutInServer(client);
        }
    }
}
```

**As listas.** O argumento do `ArrayList` é o **tamanho de cada item em células** (uma célula = 4 bytes):

- `new ArrayList(sizeof(Skin))`: cada item é uma struct `Skin` inteira. `sizeof` de um `enum struct` já dá o tamanho em células.
- `new ArrayList(ByteCountToCells(96))`: cada item é um texto de até 96 caracteres. `ByteCountToCells` converte bytes em células.

**Os comandos.** `RegServerCmd` registra um comando de **servidor** (não de jogador). É o tipo certo aqui, porque os comandos chegam pela fila e são executados com `ServerCommand`. O terceiro argumento é o texto de ajuda que aparece no console.

**O timer da fila.** `CreateTimer(0.5, Timer_Queue, _, TIMER_REPEAT)` chama `Timer_Queue` a cada meio segundo, para sempre. O `_` é "valor padrão" para o argumento de dados (não precisamos passar nada).

**O laço no fim.** Quando o plugin é recarregado com o jogo aberto, o jogador já está no servidor e o `OnClientPutInServer` não vai ser chamado de novo. O laço chama manualmente para todos os jogadores conectados, garantindo que todos estejam enganchados. Isso resolveu um bug real (ver o [diário](10-problemas-e-solucoes.md)).

---

## 13.3 `Timer_Queue`: lendo os comandos

```sourcepawn
Action Timer_Queue(Handle timer)
{
    if (!FileExists(QUEUE_FILE))
    {
        return Plugin_Continue;
    }

    File file = OpenFile(QUEUE_FILE, "r");
    if (file == null)
    {
        return Plugin_Continue;
    }

    char line[512];
    ArrayList lines = new ArrayList(ByteCountToCells(sizeof(line)));
    while (file.ReadLine(line, sizeof(line)))
    {
        TrimString(line);
        if (line[0] != '\0')
        {
            lines.PushString(line);
        }
    }

    delete file;
    DeleteFile(QUEUE_FILE);

    for (int i = 0; i < lines.Length; i++)
    {
        lines.GetString(i, line, sizeof(line));
        Log("queue: %s", line);

        if (strncmp(line, "client ", 7) != 0)
        {
            ServerCommand("%s", line);
            continue;
        }

        int host = GetHost();
        if (host != -1)
        {
            ClientCommand(host, "%s", line[7]);
        }
    }

    delete lines;
    return Plugin_Continue;
}
```

Pontos para estudar:

- **`return Plugin_Continue`** num timer repetido significa "continue repetindo". `Plugin_Stop` pararia o timer.
- **Ler tudo antes de executar.** As linhas vão para uma lista, o arquivo é fechado e apagado, e só então os comandos rodam. Se um comando demorar ou criar outro arquivo de fila, não há conflito com o arquivo aberto.
- **`TrimString`** tira espaços e a quebra de linha (`\r\n` no Windows) do fim. Sem isso, o comando chegaria com um `\r` grudado e não seria reconhecido.
- **`delete file`** fecha o arquivo. Em SourcePawn, `delete` libera qualquer *handle* (arquivo, lista, mapa...) e coloca `null` na variável.
- **`strncmp(line, "client ", 7)`** compara só os 7 primeiros caracteres. Se a linha começa com `client `, o resto (`line[7]`, ou seja, o texto a partir do 8º caractere) vai para o jogador.
- **`ServerCommand("%s", line)`** em vez de `ServerCommand(line)`: o primeiro argumento é um formato. Se o comando tivesse um `%`, ele seria interpretado como formatação. Passar `"%s"` e o texto como argumento evita isso.

---

## 13.4 `LoadSkins`: lendo o `weapon_skins.cfg`

```sourcepawn
void LoadSkins()
{
    g_hModels.Clear();
    g_hSkins.Clear();

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), SKINS_CONFIG);

    KeyValues kv = new KeyValues("WeaponSkins");
    if (!kv.ImportFromFile(path))
    {
        Log("could not read %s", path);
        delete kv;
        return;
    }

    if (kv.JumpToKey("Weapons") && kv.GotoFirstSubKey())
    {
        do
        {
            WeaponModels models;
            kv.GetSectionName(models.weapon, sizeof(models.weapon));
            kv.GetString("view_model", models.viewModel, sizeof(models.viewModel));
            kv.GetString("world_model", models.worldModel, sizeof(models.worldModel));
            models.viewModelIndex = PrecacheModel(models.viewModel, true);
            models.worldModelIndex = PrecacheModel(models.worldModel, true);
            g_hModels.PushArray(models);
        }
        while (kv.GotoNextKey());

        kv.GoBack();
        kv.GoBack();
    }

    if (kv.JumpToKey("Skins") && kv.GotoFirstSubKey())
    {
        do
        {
            Skin skin;
            kv.GetSectionName(skin.id, sizeof(skin.id));
            kv.GetString("weapon", skin.weapon, sizeof(skin.weapon));
            skin.family = kv.GetNum("skin");
            g_hSkins.PushArray(skin);
        }
        while (kv.GotoNextKey());
    }

    delete kv;
    ...
}
```

### Navegando num KeyValues

O formato `"chave" { ... }` da Valve é lido pela classe `KeyValues`. Ela funciona como um **cursor** andando numa árvore:

```text
"WeaponSkins"                     ← o cursor começa aqui (raiz)
{
    "Weapons"                     ← JumpToKey("Weapons") entra aqui
    {
        "weapon_smg"              ← GotoFirstSubKey() vai para o primeiro filho
        { "view_model" "..." }    ← GetString("view_model") lê um valor do nó atual
        "weapon_pumpshotgun"      ← GotoNextKey() vai para o próximo irmão
        { ... }
    }                             ← GoBack() sobe um nível (para "Weapons")
}                                 ← GoBack() de novo (para a raiz)
```

- `JumpToKey("Weapons")` **desce** para a seção `Weapons`.
- `GotoFirstSubKey()` **desce** para o primeiro filho que seja uma seção (`weapon_smg`).
- `GetSectionName` lê o **nome** do nó atual (`"weapon_smg"`).
- `GetString("view_model", ...)` lê um **valor** dentro do nó atual.
- `GotoNextKey()` vai para o **próximo irmão**; devolve `false` quando acabou, o que encerra o `do ... while`.
- Os dois `GoBack()` sobem até a raiz, para depois conseguir fazer `JumpToKey("Skins")`.

`GotoFirstSubKey()` e `GotoNextKey()` sem argumento só andam por **seções**. Com `false` (`GotoFirstSubKey(false)`), andam também por **valores simples**, o que o plugin usa para ler as listas `animations` e `framing`.

### `PrecacheModel(modelo, true)`

Registra o modelo no jogo e devolve o índice. O `true` (*preload*) já carrega o modelo na memória agora, em vez de na primeira vez que for desenhado. Isso evita um "engasgo" e, mais importante para as fotos, evita a primeira foto sair com o modelo ainda carregando.

---

## 13.5 `LoadScenes`: lendo as cenas e o enquadramento

O trecho que lê uma cena:

```sourcepawn
Scene scene;
kv.GetVector("origin", scene.origin);
kv.GetVector("angles", scene.angles);
kv.GetVector("target_origin", scene.targetOrigin);
kv.GetVector("target_angles", scene.targetAngles);
char meleeAngles[64];
kv.GetString("melee_target_angles", meleeAngles, sizeof(meleeAngles));
scene.hasMeleeAngles = strlen(meleeAngles) > 0;
kv.GetVector("melee_target_angles", scene.meleeAngles);
scene.viewModel = kv.GetNum("viewmodel", 0) == 1;
scene.fov = kv.GetNum("fov", 0);
kv.GetString("type", scene.type, sizeof(scene.type), name);
g_hScenes.SetArray(name, scene, sizeof(scene));
```

- `GetVector` lê um texto `"x y z"` direto para um `float[3]`. Se a chave não existe, devolve `0 0 0`.
- Para saber se `melee_target_angles` **existe**, não dá para usar o vetor (zero é um valor válido). O plugin lê como texto e vê se está vazio.
- `kv.GetString("type", ..., name)`: o último argumento é o **valor padrão**. Uma cena sem `type` usa o próprio nome, então uma cena chamada `hand` é do tipo `hand` sem precisar escrever.
- `g_hScenes.SetArray(name, scene, sizeof(scene))` guarda a struct inteira no mapa, com o nome da cena como chave.

O trecho que lê o enquadramento de cada arma:

```sourcepawn
if (kv.JumpToKey("framing"))
{
    if (kv.GotoFirstSubKey(false))
    {
        do
        {
            char weapon[64];
            char key[96];
            char value[64];
            char parts[4][16];
            float framing[4];
            kv.GetSectionName(weapon, sizeof(weapon));
            kv.GetString(NULL_STRING, value, sizeof(value));
            framing[3] = -1.0;
            int count = ExplodeString(value, " ", parts, sizeof(parts), sizeof(parts[]));
            for (int i = 0; i < count; i++)
            {
                framing[i] = StringToFloat(parts[i]);
            }

            FormatEx(key, sizeof(key), "%s|%s", name, weapon);
            g_hFraming.SetArray(key, framing, sizeof(framing));
        }
        while (kv.GotoNextKey(false));

        kv.GoBack();
    }

    kv.GoBack();
}
```

- `GotoFirstSubKey(false)`: anda pelos **valores simples** (`"weapon_smg" "5.85 222.76 8 170"`), não só por seções.
- `GetString(NULL_STRING, ...)`: lê o valor **do próprio nó atual** (não de um filho).
- `ExplodeString(value, " ", parts, ...)` divide `"5.85 222.76 8 170"` em `["5.85", "222.76", "8", "170"]` e devolve quantas partes achou.
- `framing[3] = -1.0` antes de preencher: as cenas de chão têm só **3** números (não há sobrevivente para girar). O `-1` sinaliza "sem giro".
- A chave composta `"cena|arma"` (por exemplo `"third|weapon_smg"`) permite guardar tudo num único `StringMap`.

---

## 13.6 `Command_Run`: montando a lista de trabalhos

```sourcepawn
Action Command_Run(int args)
{
    ...
    LoadSkins();
    LoadScenes();

    char shots[128];
    GetCmdArg(1, shots, sizeof(shots));

    ArrayList filters = new ArrayList(ByteCountToCells(64));
    for (int i = 2; i <= args; i++)
    {
        char filter[64];
        GetCmdArg(i, filter, sizeof(filter));
        filters.PushString(filter);
    }

    g_hJobs.Clear();
    for (int s = 0; s < g_hSceneOrder.Length; s++)
    {
        char scene[16];
        g_hSceneOrder.GetString(s, scene, sizeof(scene));
        char wanted[24];
        FormatEx(wanted, sizeof(wanted), ",%s,", scene);
        char list[132];
        FormatEx(list, sizeof(list), ",%s,", shots);
        if (!StrEqual(shots, "all") && StrContains(list, wanted) == -1)
        {
            continue;
        }

        for (int i = 0; i < g_hSkins.Length; i++)
        {
            Skin skin;
            g_hSkins.GetArray(i, skin);
            if (filters.Length > 0 && filters.FindString(skin.id) == -1 && filters.FindString(skin.weapon) == -1)
            {
                continue;
            }

            char job[96];
            FormatEx(job, sizeof(job), "%s|%s", scene, skin.id);
            g_hJobs.PushString(job);
        }
    }

    delete filters;

    PrepareOutput();
    PrepareWorld();
    Log("run %s: %d shots", shots, g_hJobs.Length);

    g_iJob = -1;
    CreateTimer(1.0, Timer_NextJob, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}
```

- **`GetCmdArg(1, ...)`** lê o primeiro argumento do comando (`all`, `third` ou uma lista `ground,ground2`). Os seguintes (`2..args`) são filtros.
- **A lista de cenas com vírgulas.** Para saber se `ground` está em `ground,ground2,third`, o código procura `,ground,` dentro de `,ground,ground2,third,`. As vírgulas nas pontas evitam um falso positivo: sem elas, `ground` seria encontrado dentro de `ground2`.
- **Os filtros** aceitam tanto id de skin (`volcanic-uzi`) quanto classe de arma (`weapon_smg`): `FindString` procura nos dois.
- **A ordem dos laços** (cena por fora, skin por dentro) faz todas as skins de uma cena antes da próxima.
- **`g_iJob = -1`** e o primeiro timer em 1 segundo: o `Timer_NextJob` incrementa antes de usar, então começa no trabalho 0. O segundo de espera dá tempo para o `PrepareWorld` fazer efeito.

---

## 13.7 `SetupScene`: o coração

```sourcepawn
bool SetupScene(const char[] shot, int index)
{
    Scene scene;
    if (!g_hScenes.GetArray(shot, scene, sizeof(scene)))
    {
        Log("scene %s is not configured for this map", shot);
        return false;
    }

    int host = GetHost();
    if (host == -1)
    {
        Log("no host");
        return false;
    }

    Skin skin;
    g_hSkins.GetArray(index, skin);

    float angles[3];
    angles = scene.angles;
    int fov = scene.fov;

    char key[96];
    float framing[4];
    float actorAngles[3];
    actorAngles = scene.targetAngles;
    FormatEx(key, sizeof(key), "%s|%s", shot, skin.weapon);
    if (g_hFraming.GetArray(key, framing, sizeof(framing)))
    {
        angles[0] = framing[0];
        angles[1] = framing[1];
        fov = RoundToNearest(framing[2]);
        if (framing[3] >= 0.0)
        {
            actorAngles[1] = framing[3];
        }
    }

    SetEntityMoveType(host, StrEqual(scene.type, "third") ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
    TeleportEntity(host, scene.origin, angles, view_as<float>({ 0.0, 0.0, 0.0 }));
    SetLocalCvar("r_drawviewmodel", scene.viewModel ? "1" : "0");
    SetEntProp(host, Prop_Send, "m_iFOV", fov);

    RemoveProp();
    g_iActiveSkin = -1;

    if (StrEqual(scene.type, "hand"))
    {
        HideActor();
        GiveWeapon(host, skin.weapon);
        g_iActiveSkin = index;
        return true;
    }

    if (StrEqual(scene.type, "ground"))
    {
        HideActor();
        bool melee = StrContains(skin.weapon, "weapon_melee_") == 0 && scene.hasMeleeAngles;
        return SpawnProp(index, scene.targetOrigin, melee ? scene.meleeAngles : scene.targetAngles);
    }

    HideActor();
    return SpawnPosedSurvivor(index, scene.targetOrigin, actorAngles);
}
```

Passo a passo:

1. **Busca a cena** pelo nome. Se o mapa aberto não tem essa cena, registra e devolve `false` (o trabalho é pulado).
2. **Busca o host** (o jogador humano, a câmera).
3. **Copia ângulos e FOV da cena** para variáveis locais. `angles = scene.angles` copia o array inteiro (em SourcePawn, atribuir arrays de mesmo tamanho copia os valores).
4. **Aplica o enquadramento calibrado**, se houver um para `cena|arma`. O FOV vem como float e o jogo só aceita inteiro, por isso o `RoundToNearest`.
5. **Noclip só na terceira pessoa.** Lá a câmera pode precisar ficar "no ar" sem cair.
6. **`TeleportEntity(host, origem, ângulos, velocidade)`**: o último argumento `{0,0,0}` zera a velocidade, para a câmera não "escorregar" depois do teleporte. `view_as<float>({...})` diz ao compilador que o array literal é de floats.
7. **Viewmodel e FOV**: só a cena `hand` desenha a arma em primeira pessoa.
8. **Limpa a cena anterior** (`RemoveProp`) e desliga a skin da mão (`g_iActiveSkin = -1`).
9. **Monta o tipo de cena.** As armas melee no chão podem ter uma rotação própria (`melee_target_angles`), porque o modelo delas é "em pé" num eixo diferente das armas de fogo.

---

## 13.8 `SpawnProp` e `LowestPoint`: a arma no chão, sem afundar

```sourcepawn
bool SpawnProp(int index, const float origin[3], const float angles[3])
{
    ...
    int prop = CreateEntityByName("prop_dynamic_override");
    if (prop == -1)
    {
        return false;
    }

    DispatchKeyValue(prop, "model", models.worldModel);
    DispatchKeyValue(prop, "solid", "0");
    DispatchKeyValue(prop, "targetname", PROP_NAME);
    DispatchSpawn(prop);

    float resting[3];
    resting = origin;
    resting[2] = origin[2] - LowestPoint(prop, angles);
    TeleportEntity(prop, resting, angles, NULL_VECTOR);
    SetEntProp(prop, Prop_Send, "m_nSkin", skin.family);

    g_iProp = EntIndexToEntRef(prop);
    return true;
}
```

**Criar uma entidade em SourceMod tem sempre três tempos:**

1. `CreateEntityByName("classe")` cria a entidade "vazia" e devolve o índice (ou -1).
2. `DispatchKeyValue(entidade, "chave", "valor")` configura, como se fosse uma entidade colocada no mapa pelo editor (Hammer).
3. `DispatchSpawn(entidade)` "liga" a entidade com essas configurações. Algumas chaves só têm efeito se forem dadas **antes** do spawn (o modelo, por exemplo).

**O problema de afundar.** A origem de um modelo de arma fica no ponto da empunhadura, não no ponto mais baixo. Deitada no chão com a origem na altura do chão, parte da arma fica **abaixo** do chão (a guitarra era a pior). A função `LowestPoint` calcula quanto a arma desce abaixo da origem, e a arma é levantada exatamente isso:

```sourcepawn
float LowestPoint(int entity, const float angles[3])
{
    float mins[3];
    float maxs[3];
    GetEntPropVector(entity, Prop_Send, "m_vecMins", mins);
    GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);

    float front[3];
    float right[3];
    float up[3];
    GetAngleVectors(angles, front, right, up);

    float lowest = 0.0;
    for (int corner = 0; corner < 8; corner++)
    {
        float x = (corner & 1) != 0 ? maxs[0] : mins[0];
        float y = (corner & 2) != 0 ? maxs[1] : mins[1];
        float z = (corner & 4) != 0 ? maxs[2] : mins[2];
        float height = front[2] * x - right[2] * y + up[2] * z;
        if (corner == 0 || height < lowest)
        {
            lowest = height;
        }
    }

    return lowest;
}
```

Como funciona:

1. **A caixa do modelo.** `m_vecMins` e `m_vecMaxs` são os cantos da caixa que envolve o modelo, no sistema de coordenadas **do próprio modelo** (sem rotação).
2. **Os 8 cantos.** Uma caixa tem 8 cantos, combinando min/max em x, y e z. O truque com bits gera todos: para `corner` de 0 a 7, o bit 1 escolhe x, o bit 2 escolhe y, o bit 4 escolhe z.

   ```text
   corner  bits  x    y    z
     0     000   min  min  min
     1     001   max  min  min
     2     010   min  max  min
     3     011   max  max  min
     4     100   min  min  max
     ...
     7     111   max  max  max
   ```

3. **Girando cada canto.** `GetAngleVectors` dá os três eixos do modelo depois da rotação (frente, direita, cima) **no mundo**. Um ponto `(x, y, z)` do modelo fica, no mundo, em `frente·x − direita·y + cima·z`. (O sinal de menos é porque o eixo y do modelo aponta para a **esquerda**, e `GetAngleVectors` devolve a **direita**.) Só precisamos da altura, então só a componente `[2]` (z) de cada eixo.
4. **O mais baixo.** O menor valor de altura entre os 8 cantos é quanto o modelo desce abaixo da origem (um número negativo).
5. **Levantar.** `resting[2] = origin[2] - lowest`: se o modelo desce 6 unidades (`lowest = -6`), a origem sobe 6, e o ponto mais baixo encosta exatamente no chão.

---

## 13.9 `SpawnPosedSurvivor`: o manequim com a arma

O código e cada peça estão no [documento 7](07-terceira-pessoa.md#72-a-solução-um-manequim). O ponto extra para estudar aqui é a **ordem**:

```sourcepawn
DispatchSpawn(weapon);                                   // 1. a arma existe
SetEntProp(weapon, Prop_Send, "m_nSkin", skin.family);   // 2. pinta
TeleportEntity(weapon, origin, angles, NULL_VECTOR);     // 3. leva para perto do sobrevivente
SetVariantString("!activator");
AcceptEntityInput(weapon, "SetParent", survivor);        // 4. vira filha do sobrevivente
SetVariantString("weapon_bone");
AcceptEntityInput(weapon, "SetParentAttachment");        // 5. prende no ponto da mão
TeleportEntity(weapon, {0,0,0}, {0,0,0}, NULL_VECTOR);   // 6. zera a posição relativa
SetEntProp(weapon, Prop_Send, "m_fEffects", ... | EF_BONEMERGE | ...);  // 7. encaixa os ossos
```

- **Entradas (*inputs*)** são como mensagens para entidades: `AcceptEntityInput(entidade, "NomeDaEntrada", ativador)`. Algumas recebem um parâmetro, que é passado **antes** com `SetVariantString`.
- `"!activator"` é um nome especial: "a entidade que ativou esta entrada". Como passamos `survivor` como ativador, `SetParent !activator` significa "meu pai é o sobrevivente".
- **Depois de ter um pai, a posição passa a ser relativa ao pai.** Por isso o passo 6 usa `{0,0,0}`: "fique exatamente no ponto da mão, sem deslocamento".

---

## 13.10 `OnPostThinkPost`: reaplicando a skin todo frame

```sourcepawn
void OnPostThinkPost(int client)
{
    int effects = GetEntProp(client, Prop_Send, "m_fEffects");
    if (effects & EF_DIMLIGHT)
    {
        SetEntProp(client, Prop_Send, "m_fEffects", effects & ~EF_DIMLIGHT);
    }

    int index = client == GetHost() ? g_iActiveSkin : -1;
    if (index == -1)
    {
        return;
    }

    Skin skin;
    g_hSkins.GetArray(index, skin);

    WeaponModels models;
    if (!FindModels(skin.weapon, models))
    {
        return;
    }

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon > MaxClients && IsValidEntity(weapon))
    {
        if (GetEntProp(weapon, Prop_Send, "m_nModelIndex") != models.worldModelIndex)
        {
            SetEntityModel(weapon, models.worldModel);
        }

        if (HasEntProp(weapon, Prop_Send, "m_iWorldModelIndex"))
        {
            SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", models.worldModelIndex);
        }

        SetEntProp(weapon, Prop_Send, "m_nSkin", skin.family);
    }

    ...
    int viewModel = GetEntPropEnt(client, Prop_Send, "m_hViewModel");
    if (viewModel <= MaxClients || !IsValidEntity(viewModel))
    {
        return;
    }

    SetEntProp(viewModel, Prop_Send, "m_nModelIndex", models.viewModelIndex);
    SetEntProp(viewModel, Prop_Send, "m_nSkin", skin.family);
}
```

- **Operações de bits.** `effects & EF_DIMLIGHT` testa se o bit da lanterna está ligado. `effects & ~EF_DIMLIGHT` desliga **só esse bit**, mantendo os outros (`~` inverte todos os bits; o `&` com o inverso apaga o bit escolhido).
- **`GetEntPropEnt`** lê uma netprop que guarda uma **entidade** (um *handle* de entidade) e devolve o índice. `m_hActiveWeapon` é a arma na mão, `m_hViewModel` é o viewmodel do jogador.
- **`SetEntityModel` só quando precisa.** Trocar o modelo de verdade todo frame é caro e reinicia a animação. O código só troca se o índice atual for diferente.
- **`HasEntProp`** antes de mexer em `m_iWorldModelIndex`: nem toda classe de arma tem essa netprop. Escrever numa netprop que não existe derruba o plugin com erro.

---

## 13.11 `MoveNewestScreenshot`: achando o print certo

```sourcepawn
bool MoveNewestScreenshot(const char[] target)
{
    DirectoryListing dir = OpenDirectory(SCREENSHOTS_DIR);
    if (dir == null)
    {
        return false;
    }

    char name[PLATFORM_MAX_PATH];
    char found[PLATFORM_MAX_PATH];
    FileType type;
    while (dir.GetNext(name, sizeof(name), type))
    {
        if (type != FileType_File || StrContains(name, ".jpg", false) == -1)
        {
            continue;
        }

        if (found[0] == '\0' || strcmp(name, found) > 0)
        {
            strcopy(found, sizeof(found), name);
        }
    }

    delete dir;

    if (found[0] == '\0')
    {
        return false;
    }

    char source[PLATFORM_MAX_PATH];
    FormatEx(source, sizeof(source), "%s/%s", SCREENSHOTS_DIR, found);

    if (FileSize(source) <= 0)
    {
        return false;
    }

    if (FileExists(target))
    {
        DeleteFile(target);
    }

    return RenameFile(target, source);
}
```

- **O "mais novo" pelo nome.** O jogo numera os prints (`c5m1_waterfront0001.jpg`, `0002`...), com zeros à esquerda. Comparar os nomes como texto (`strcmp`) dá a mesma ordem dos números. O maior nome é o mais novo.
- **`StrContains(name, ".jpg", false)`**: o `false` torna a busca **sem diferenciar maiúsculas**.
- **`FileSize(source) <= 0`**: o jogo cria o arquivo e só depois escreve o conteúdo. Se pegarmos o arquivo vazio, o print sairia corrompido. Tamanho zero = "ainda não terminou", tenta de novo no próximo timer.
- **`RenameFile(destino, origem)`**: atenção à ordem dos argumentos, **destino primeiro**. Renomear para outra pasta move o arquivo.

### Limpando sobras antes de cada print (`ClearScreenshots`)

Se a pasta `screenshots` tiver um `.jpg` que sobrou de uma sequência interrompida, "o mais novo" pode ser esse arquivo velho, e ele vai parar no lugar da foto nova. Por isso o `TakeScreenshot` chama `ClearScreenshots` antes do `jpeg`: ela percorre a pasta com o mesmo `OpenDirectory`/`GetNext` e apaga todo `.jpg` solto. As fotos prontas ficam em `screenshots/skinshots`, uma subpasta, e não são tocadas (`FileType_File` ignora pastas).

---

## 13.12 Exercícios para fixar

1. Adicione um comando `sm_shots_list` que escreve no log o nome de todas as cenas carregadas. (Dica: percorra `g_hSceneOrder`.)
2. Faça o `PrepareWorld` também desligar a neblina (`fog_override 1`, `fog_enable 0`). Compare um print antes e depois.
3. Mude o `MAX_SHOT_RETRIES` para 2 e rode uma sequência. O que aparece no log? Por quê?
4. Na `LowestPoint`, troque `- right[2] * y` por `+ right[2] * y` e tire um print de chão da guitarra. O que acontece com a altura? (Isso mostra por que o sinal importa.)

---

Próximo: [14. O código da calibração](14-codigo-da-calibracao.md)
