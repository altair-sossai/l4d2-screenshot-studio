# 1. Conceitos básicos

Antes de entrar no código, vale entender as peças do jogo com que o estúdio mexe. Este documento não tem nada específico do estúdio: é o vocabulário que os próximos usam o tempo todo.

---

## 1.1 Source Engine, servidor e cliente

O Left 4 Dead 2 roda na **Source Engine**, da Valve. Toda partida tem duas metades:

- O **servidor** decide o que existe no mundo: onde cada jogador está, que arma ele segura, quem está vivo. Ele é a "verdade" do jogo.
- O **cliente** é o seu jogo desenhando a tela. Ele recebe do servidor o estado do mundo e só desenha.

Quando você cria um jogo local (single player ou "listen server"), as duas metades rodam **no mesmo processo** (`left4dead2.exe`). É isso que o estúdio usa: o servidor e o cliente estão na mesma máquina, e quem tira o print é o cliente.

Por que isso importa? Porque o **plugin roda no servidor**. Ele consegue mover coisas, criar coisas, trocar o modelo de uma arma. Mas ele **não desenha nada** e não lê pixels. Toda vez que o estúdio precisa "ver" a imagem, quem faz isso são os scripts PowerShell, depois que o jogo salva o print em disco.

---

## 1.2 Entidades

Tudo que existe no mapa é uma **entidade**: o jogador, a arma na mão dele, a arma caída no chão, uma porta, uma luz, uma câmera de cutscene. Cada entidade tem:

- uma **classe** (`classname`), por exemplo `weapon_smg`, `prop_dynamic`, `point_viewcontrol`;
- um **índice** (um número, do 1 ao ~2048);
- **propriedades** (`netprops` e `datamaps`), como posição (`m_vecOrigin`), modelo (`m_nModelIndex`), família de textura (`m_nSkin`).

As **netprops** são as propriedades que o servidor envia para o cliente. Se o plugin muda uma netprop, o cliente recebe a mudança e desenha diferente. É assim que o plugin troca a aparência de uma arma.

Os índices de 1 até `MaxClients` (geralmente 1 a 32) são reservados para jogadores. No código você vai ver muito `entity > MaxClients`: é o jeito de dizer "isto é uma entidade do mundo, não um jogador".

### Referências de entidade

Um índice pode ser reaproveitado: se a arma 300 é removida, outra entidade pode nascer com o índice 300. Para guardar "esta entidade específica", o SourceMod usa **referências** (`EntIndexToEntRef` / `EntRefToEntIndex`). Uma referência deixa de valer quando a entidade original some, e aí `EntRefToEntIndex` devolve `INVALID_ENT_REFERENCE`. O plugin guarda o sobrevivente "manequim", a arma dele e a arma do chão assim.

---

## 1.3 Modelos, materiais e texturas

- **Modelo** (`.mdl`, com `.vvd` e `.vtx`): a malha 3D, os ossos e as animações.
- **Material** (`.vmt`): um arquivo de texto que diz como pintar a malha (qual textura, brilho, reflexo...).
- **Textura** (`.vtf`): a imagem em si.

Uma **skin de arma** da Workshop normalmente é um conjunto de materiais e texturas (às vezes também um modelo) que substitui a aparência de uma arma.

### Famílias de skin (`m_nSkin`)

Um modelo pode ter várias **famílias de textura** (`$texturegroup` no código fonte do modelo). A família 0 usa um conjunto de materiais, a família 1 outro, e assim por diante. Trocar a netprop `m_nSkin` de uma entidade troca a família, ou seja, troca a pintura sem trocar a malha.

O servidor L4D2 Zone junta **todas as skins de uma arma num único modelo combinado**: o modelo `models/l4d2br/weapons/smg/v.mdl` tem uma família para cada skin de SMG. Para mostrar a skin número 7, basta usar o modelo combinado e colocar `m_nSkin = 7`. O estúdio usa exatamente o mesmo mecanismo, lendo a lista de skins do arquivo `weapon_skins.cfg` do servidor.

Em toda arma com skin (as seis armas de fogo e as nove armas brancas), as **primeiras famílias** do modelo combinado são as do modelo **original** do jogo, e as skins vêm depois delas. Quantas são está em `stock_skins`, no `weapon_skins.cfg`: 2 na SMG, na SMG com silenciador, nas escopetas, no taco de críquete e no pé de cabra; 3 na Magnum; 1 na MP5 e nas outras armas brancas. É isso que deixa o servidor usar o modelo combinado até em quem está sem skin. Para o estúdio não muda nada: o número da família de cada skin já vem certo no campo `"skin"` do cfg, e o `stock_skins` é ignorado.

> Consequência importante para o enquadramento: como **todas as skins de uma arma compartilham a mesma malha**, elas têm o mesmo tamanho e formato. Por isso o enquadramento é calibrado **uma vez por arma**, não uma vez por skin. Veja o [documento 8](08-enquadramento-automatico.md).

---

## 1.4 Viewmodel x worldmodel

Toda arma tem **dois modelos**:

| | Viewmodel (`v_*.mdl`) | Worldmodel (`w_*.mdl`) |
|---|---|---|
| Quem vê | Só o dono da arma, em primeira pessoa | Todo mundo, no mundo 3D |
| Onde aparece | "Grudado" na câmera, desenhado por cima do mundo | Na mão do personagem, ou caído no chão |
| Detalhe | Alto (fica perto da tela) | Menor |
| Entidade | `predicted_viewmodel` (uma por jogador) | a própria arma (`weapon_*`) ou um `prop_dynamic` |

No estúdio:

- a foto `hand` usa o **viewmodel**;
- as fotos `ground`, `third` e `third2` usam o **worldmodel**.

### Os braços em primeira pessoa

No L4D2 atual, o viewmodel da arma **não tem braços**. Os braços são um modelo separado (`models/weapons/arms/v_arms_<sobrevivente>.mdl`), colado no viewmodel pelo próprio cliente. Qual braço usar está escrito no script da arma (`scripts/weapon_*.txt`), no bloco `CharacterViewmodelAddon`:

```text
"CharacterViewmodelAddon"
{
    "Coach"     "models/weapons/arms/v_arms_coach_new.mdl"
    "Mechanic"  "models/weapons/arms/v_arms_mechanic_new.mdl"
    "Producer"  "models/weapons/arms/v_arms_producer_new.mdl"
    "Gambler"   "models/weapons/arms/v_arms_gambler_new.mdl"
    ...
}
```

Isso explica um dos problemas mais difíceis do projeto (os braços sumiram da foto `hand`), contado no [diário de problemas](10-problemas-e-solucoes.md).

---

## 1.5 Ossos, attachments e bonemerge

Um modelo de personagem tem um **esqueleto** (ossos). Alguns pontos do esqueleto têm nome e servem de "gancho": são os **attachments**. Os sobreviventes do L4D2 têm um attachment chamado `weapon_bone`, que é onde a arma fica presa na mão.

**Bonemerge** (`EF_BONEMERGE`) é um efeito que faz uma entidade filha copiar a posição dos ossos da entidade pai que tenham o mesmo nome. É assim que a arma acompanha a mão do personagem em qualquer animação: a arma tem um osso com o mesmo nome do osso da mão, e o bonemerge "cola" um no outro.

O estúdio usa isso na terceira pessoa: cria um sobrevivente, cria a arma, prende a arma no `weapon_bone` e liga o bonemerge. Detalhes no [documento 7](07-terceira-pessoa.md).

---

## 1.6 Ângulos e coordenadas

- **Posição** é um vetor `x y z` em unidades do jogo. 1 unidade ≈ 1,9 cm. Um sobrevivente tem ~72 unidades de altura.
- **Ângulos** são `pitch yaw roll`:
  - `pitch`: para cima ou para baixo. **Positivo olha para baixo** (cuidado, é o contrário do que parece natural).
  - `yaw`: girar para os lados, de 0 a 360 graus. 0 aponta para +X, 90 para +Y.
  - `roll`: inclinar a cabeça de lado. Quase sempre 0.
- O **olho** do jogador fica ~64 unidades acima dos pés (`m_vecViewOffset`).

### FOV

**FOV** (*field of view*, campo de visão) é o quanto a câmera enxerga, em graus. FOV menor é zoom. O plugin controla o FOV do jogador pela netprop `m_iFOV` (0 = FOV padrão). Na Source Engine o valor de FOV é medido como se a tela fosse 4:3; numa tela 16:9 o jogo abre a imagem para os lados. O [documento 8](08-enquadramento-automatico.md) mostra como isso entra na conta.

---

## 1.7 SourceMod e Metamod

- **Metamod:Source** é uma camada que se instala no servidor do jogo e permite carregar plugins de código nativo.
- **SourceMod** é um desses plugins nativos. Ele cria um ambiente onde se escreve plugins numa linguagem própria, a **SourcePawn** (`.sp`), compilada para `.smx` com o `spcomp`.

Um plugin SourceMod pode:

- registrar comandos de console (`RegServerCmd`);
- reagir a eventos (`OnMapStart`, `OnClientPutInServer`...);
- criar timers (`CreateTimer`);
- ler e escrever netprops (`GetEntProp`, `SetEntProp`, `GetEntPropVector`...);
- criar e destruir entidades (`CreateEntityByName`, `DispatchSpawn`, `RemoveEntity`);
- enviar entradas para entidades (`AcceptEntityInput`, como "SetParent", "TurnOff").

As extensões **SDKTools** e **SDKHooks** dão acesso a coisas mais baixas, como `TeleportEntity` e o gancho `PostThinkPost` (rodar código logo depois que o jogador "pensa", todo frame).

---

## 1.8 Cvars e comandos

**Cvars** (*console variables*) são configurações do jogo, como `r_drawviewmodel` (desenhar ou não a arma em primeira pessoa) ou `hidehud` (esconder partes do HUD). Algumas são do servidor, outras do cliente.

Algumas cvars e comandos são marcados como **cheat** (`FCVAR_CHEAT`) e só funcionam com `sv_cheats 1`. O plugin liga `sv_cheats` e, quando precisa usar um comando de cheat como `give`, tira a marca de cheat por um instante (função `CheatCommand`).

---

Próximo: [2. O estúdio: uma cópia do jogo](02-estudio.md)
