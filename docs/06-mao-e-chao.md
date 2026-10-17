# 6. Primeira pessoa e chão

As duas cenas mais simples: a arma na mão de quem está jogando (`hand`) e a arma caída no chão (`ground`).

---

## 6.1 Como as skins chegam ao jogo

O estúdio usa o mesmo esquema do servidor L4D2 Zone:

- Para cada arma existe **um modelo combinado** de viewmodel e um de worldmodel:
  ```text
  models/l4d2br/weapons/smg/v.mdl   ← viewmodel com uma família por skin de SMG
  models/l4d2br/weapons/smg/w.mdl   ← worldmodel com uma família por skin de SMG
  ```
- Cada **família** aponta para os materiais de uma skin:
  ```text
  materials/models/l4d2br/weapons/smg_<id da workshop>/...
  ```
- O `weapon_skins.cfg` diz, para cada skin, a arma e o número da família. Nas armas de fogo, as primeiras famílias são as do modelo original do jogo (`stock_skins`), e as skins vêm depois delas; veja os [conceitos básicos](01-conceitos-basicos.md#famílias-de-skin-m_nskin).

Mostrar uma skin é, portanto, **trocar o modelo pelo combinado e escolher a família** (`m_nSkin`). Nenhum arquivo é trocado em disco durante as fotos.

---

## 6.2 A arma na mão (`hand`)

### Dando a arma (`GiveWeapon`)

```sourcepawn
void GiveWeapon(int client, const char[] weapon)
{
    // "weapon_melee_katana" → "katana", "weapon_smg" → "smg"
    ...
    // slot 1 = pistolas e melee, slot 0 = armas principais
    int slot = (melee ou pistola) ? 1 : 0;

    // tira a arma que já estava nesse slot
    RemovePlayerItem(client, current);
    RemoveEntity(current);

    // usa o comando de cheat "give"
    CheatCommand(client, "give", item);

    // se não veio e é melee, cria na mão (ver 6.3)
    if (given == -1 && melee) given = CreateMelee(client, item);

    // deixa a arma ativa e manda o jogador "sacar" ela
    SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", given);
    FakeClientCommand(client, "use %s", classname);
}
```

`CheatCommand` tira a flag `FCVAR_CHEAT` do comando, executa como o jogador (`FakeClientCommand`) e devolve a flag. Assim o `give` funciona sem depender do estado de `sv_cheats`.

### Aplicando a skin

Depois de dar a arma, o `SetupScene` marca `g_iActiveSkin = index`. A partir daí, **todo frame**, o `OnPostThinkPost` (ver [documento 4](04-plugin.md#47-a-cada-frame-onpostthinkpost)) troca:

```sourcepawn
// a arma em si (o que outros jogadores veriam)
SetEntityModel(weapon, models.worldModel);
SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", models.worldModelIndex);
SetEntProp(weapon, Prop_Send, "m_nSkin", skin.family);

// o viewmodel (o que você vê na tela)
SetEntProp(viewModel, Prop_Send, "m_nModelIndex", models.viewModelIndex);
SetEntProp(viewModel, Prop_Send, "m_nSkin", skin.family);
```

### Os braços

Os braços **não** fazem parte do viewmodel da arma: o cliente cola um modelo de braço por cima (ver [documento 1](01-conceitos-basicos.md#os-braços-em-primeira-pessoa)). O plugin não precisa fazer nada para eles aparecerem. Se eles **não** aparecem, o problema está no jogo (configuração gráfica, cutscene), não no plugin. Esse foi um dos problemas mais trabalhosos do projeto: veja o [diário](10-problemas-e-solucoes.md#os-braços-sumiram-da-primeira-pessoa).

---

## 6.3 Armas melee que o mapa não permite

Cada campanha do L4D2 tem uma **lista de armas melee permitidas** no arquivo de missão (`missions/campaign5.txt`, chave `meleeweapons`). O comando `give katana` simplesmente **não funciona** num mapa cuja campanha não lista a katana. Em The Parish, 5 das armas melee com skin não estavam na lista.

Tentativas que **não** funcionaram:

| Tentativa | Resultado |
|---|---|
| Plugin `l4d2_melee_spawn_control` (muda a lista de melee em tempo de execução) | Falhou no Windows: a assinatura de função que ele procura na memória (`KeyValues::FindKey`) estava desatualizada para o binário do jogo |
| Arquivo de missão solto (`left4dead2/missions/campaign5.txt` com todas as melee) | Ignorado pelo jogo |
| O mesmo arquivo em `update/missions/` (pasta de maior prioridade) | Também ignorado |

> Lição: arquivos de teste como esses ficam esquecidos e confundem investigações futuras. No fim do projeto eles foram removidos da cópia do jogo.

### A solução: criar a melee direto (`CreateMelee`)

O `give` passa pela checagem da missão, mas **criar a entidade diretamente não passa**:

```sourcepawn
int CreateMelee(int client, const char[] script)
{
    int melee = CreateEntityByName("weapon_melee");
    DispatchKeyValue(melee, "melee_script_name", script);   // "katana", "cricket_bat"...
    DispatchSpawn(melee);
    TeleportEntity(melee, origem do jogador, ...);
    EquipPlayerWeapon(client, melee);                        // coloca na mão
    return GetPlayerWeaponSlot(client, 1);
}
```

Toda arma melee do L4D2 é a mesma classe `weapon_melee`; o que muda é a chave `melee_script_name`, que aponta para o script da arma (`scripts/melee/katana.txt`). O plugin tenta o `give` primeiro e só usa `CreateMelee` se o `give` falhar.

---

## 6.4 A arma no chão (`ground`, `ground2`, `ground3`)

Aqui não há jogador segurando nada. O plugin cria um **`prop_dynamic_override`** com o worldmodel combinado:

```sourcepawn
int prop = CreateEntityByName("prop_dynamic_override");
DispatchKeyValue(prop, "model", models.worldModel);
DispatchKeyValue(prop, "solid", "0");                 // sem colisão
DispatchKeyValue(prop, "targetname", PROP_NAME);      // "skin_shots_prop", para achar e remover depois
DispatchSpawn(prop);

float resting[3];
resting = origin;
resting[2] = origin[2] - LowestPoint(prop, angles);   // levanta até o ponto mais baixo encostar no chão
TeleportEntity(prop, resting, angles, NULL_VECTOR);
SetEntProp(prop, Prop_Send, "m_nSkin", skin.family);
```

São três fotos de chão por skin: cano para a esquerda, cano para a direita (mostrando o outro lado) e uma na diagonal, levemente inclinada. As rotações e o motivo de as armas melee terem rotação própria estão no [documento 5](05-cenas.md#ângulos-da-arma-no-chão). A conta do `LowestPoint` está explicada linha a linha no [documento 13](13-codigo-do-plugin.md#138-spawnprop-e-lowestpoint-a-arma-no-chão-sem-afundar).

As três cenas de chão também passam pela **calibração automática** (como a terceira pessoa), que centraliza a arma e ajusta o zoom para cada tipo de arma. Sem ela, a escopeta, que é comprida, saía encostada na borda do quadro.

- **`prop_dynamic_override`** em vez de `prop_dynamic`: o `_override` aceita qualquer modelo, inclusive os que não foram feitos para serem props (o `prop_dynamic` comum recusa modelos sem a configuração de prop).
- **Sem física:** a arma não cai nem rola. Ela fica exatamente na posição e rotação do config, igual em todas as fotos.
- **`targetname`**: todas as entidades criadas pelo plugin têm o nome `skin_shots_prop`. O `RemoveProp` remove tudo que tiver esse nome, além das referências guardadas. Isso resolveu um bug real: props duplicados que sobravam de cenas anteriores (veja o [diário](10-problemas-e-solucoes.md)).

### Por que a câmera é a mesma da mão

As cenas de chão usam a mesma posição da `hand`, olhando para baixo (pitch ~45 a 50). A arma fica a uns 50 unidades à frente, no chão do cais. Mesma luz, mesmo lugar, só muda o que se olha; a direção exata e o zoom vêm da calibração.

---

Próximo: [7. Terceira pessoa](07-terceira-pessoa.md)
