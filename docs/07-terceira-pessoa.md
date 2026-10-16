# 7. Terceira pessoa

A foto `third` (e `third2`) mostra **um sobrevivente segurando a arma**, visto de fora. Parece simples, mas foi a parte que mais mudou ao longo do projeto. Este documento conta a solução final e por que as mais óbvias não funcionaram.

---

## 7.1 Primeira ideia: usar um bot

O jeito óbvio é pegar um bot sobrevivente, dar a arma para ele e fotografar. Problemas:

- **Bots ignoram rotação.** Dá para teleportar o bot com um ângulo, mas no frame seguinte a IA vira ele para onde quiser. Mesmo com `sb_stop 1`, ele olhava para cima ou para outro lado.
- **A pose muda.** Bots respiram, olham em volta, trocam de animação. Duas fotos seguidas nunca saíam iguais.
- **O rosto.** O rosto dos sobreviventes tem animação facial (piscar, expressões). Num frame qualquer ele pode estar com a boca aberta ou torta.

Conclusão: para fotos **idênticas**, um bot é imprevisível demais.

---

## 7.2 A solução: um "manequim"

Em vez de um jogador, o plugin cria **um modelo de sobrevivente como objeto de cena** (`prop_dynamic_override`), toca uma animação de "parado segurando a arma" e **congela** a animação. Depois cria a arma e **prende na mão** do manequim.

### O sobrevivente (`SpawnPosedSurvivor`)

```sourcepawn
int survivor = CreateEntityByName("prop_dynamic_override");
DispatchKeyValue(survivor, "model", g_sActorModel);      // models/survivors/survivor_mechanic.mdl (Ellis)
DispatchKeyValue(survivor, "solid", "0");
DispatchKeyValue(survivor, "targetname", PROP_NAME);
DispatchKeyValue(survivor, "DefaultAnim", animation);    // ex.: "Idle_Standing_SMG"
DispatchSpawn(survivor);
TeleportEntity(survivor, origin, angles, NULL_VECTOR);

SetVariantString(animation);
AcceptEntityInput(survivor, "SetAnimation");

// congela: velocidade 0 e sempre o primeiro frame
SetEntPropFloat(survivor, Prop_Send, "m_flPlaybackRate", 0.0);
SetEntPropFloat(survivor, Prop_Send, "m_flCycle", 0.0);
```

- `DefaultAnim` + a entrada `SetAnimation`: garantem que a animação certa está tocando.
- `m_flPlaybackRate = 0`: a animação não avança.
- `m_flCycle = 0`: e fica sempre no mesmo ponto (o início).

Resultado: **a mesma pose, exatamente, em todas as fotos**.

### A arma na mão

```sourcepawn
int weapon = CreateEntityByName("prop_dynamic_override");
DispatchKeyValue(weapon, "model", models.worldModel);
DispatchKeyValue(weapon, "effects", "129");               // EF_BONEMERGE | EF_BONEMERGE_FASTCULL
DispatchSpawn(weapon);
SetEntProp(weapon, Prop_Send, "m_nSkin", skin.family);

// pendura no sobrevivente, no ponto "weapon_bone" (a mão)
SetVariantString("!activator");
AcceptEntityInput(weapon, "SetParent", survivor);
SetVariantString("weapon_bone");
AcceptEntityInput(weapon, "SetParentAttachment");
TeleportEntity(weapon, {0,0,0}, {0,0,0}, NULL_VECTOR);   // posição relativa zero = exatamente no attachment

// cola os ossos da arma nos ossos do sobrevivente
SetEntProp(weapon, Prop_Send, "m_fEffects",
    GetEntProp(weapon, Prop_Send, "m_fEffects") | EF_BONEMERGE | EF_BONEMERGE_FASTCULL | EF_PARENT_ANIMATES);
```

O que cada peça faz:

| Peça | Função |
|---|---|
| `SetParent` | A arma passa a se mover junto com o sobrevivente |
| `SetParentAttachment weapon_bone` | Em vez de presa no centro do corpo, fica presa no ponto da mão |
| `EF_BONEMERGE` (1) | Os ossos da arma copiam os ossos de mesmo nome do sobrevivente: a arma se encaixa na mão do jeito que o jogo encaixa |
| `EF_BONEMERGE_FASTCULL` (128) | Otimização de desenho para bonemerge |
| `EF_PARENT_ANIMATES` (512) | Avisa que o pai é animado, para a posição acompanhar a animação |

Sem o `SetParentAttachment`, a arma aparecia nos pés do sobrevivente. Sem o bonemerge, ficava presa na mão mas com o ângulo errado.

---

## 7.3 Escolhendo de que lado fotografar

A câmera é fixa (cena `third`), mas o **sobrevivente pode girar** (`target_angles`, e por arma no `framing`). Girar o sobrevivente muda tudo:

- de frente, o rosto aparece (e o rosto às vezes sai deformado, ver 7.4);
- de um lado, o corpo fica **na frente** da arma;
- do outro lado, a arma fica na frente do corpo, contra o muro.

O ângulo bom depende da arma: uma escopeta segurada à frente do peito pede um ângulo, uma katana na diagonal pede outro. Por isso o giro do sobrevivente também é **calibrado por arma**, automaticamente, procurando o giro em que **mais pixels da arma aparecem** (ver [documento 8](08-enquadramento-automatico.md#83-escolhendo-o-giro-do-sobrevivente)).

Os giros testados ficam numa faixa em que **o rosto fica de costas ou de perfil para a câmera** (`ActorYaws`, de 170 a 290 graus nesta cena).

---

## 7.4 O rosto deformado

Mesmo com a animação do corpo congelada, **o rosto mudava sozinho**: em alguns prints aparecia com a boca aberta e torta. Ao comparar dois prints da mesma cena (com e sem a arma), o rosto aparecia como diferença, junto com a arma.

Causas prováveis encontradas na investigação:

- a animação facial (flexes) dos sobreviventes roda à parte da animação do corpo e não para com `m_flPlaybackRate = 0`;
- a cópia do jogo veio com uma config de terceiros que muda os olhos (`r_eyesize 0`, `r_eyemove 0`) e arquivos de expressão soltos (`expressions/`, `models/survivors/*.pre`).

A solução adotada foi **não depender do rosto**: o enquadramento é focado na arma e o sobrevivente é girado para o rosto não ficar de frente. As fotos finais mostram o braço, a mão e a arma, e o rosto fica fora do quadro ou de perfil.

---

## 7.5 Por que não `thirdpersonshoulder`

O L4D2 tem uma câmera de terceira pessoa embutida (`thirdpersonshoulder`). Ela foi descartada porque:

- a câmera fica presa atrás do ombro do jogador, sem controle de ângulo;
- o próprio jogador teria que ser o modelo, e a pose dele muda com o movimento;
- o HUD e a mira de terceira pessoa entram no print.

Com o manequim, câmera e modelo são independentes.

---

Próximo: [8. Enquadramento automático](08-enquadramento-automatico.md)
