# 5. As cenas

Todas as posições, ângulos e ajustes ficam em [`config/skin_shots.cfg`](../config/skin_shots.cfg). O plugin não tem nenhuma coordenada no código: trocar de mapa ou de ângulo é só editar este arquivo.

---

## 5.1 Formato do arquivo

```text
"SkinShots"
{
    "settle"        "1.6"                                      ← segundos de espera antes de cada print (uma cena pode ter o próprio, a "hand" usa 4.0)
    "actor_model"   "models/survivors/survivor_mechanic.mdl"   ← sobrevivente da terceira pessoa (Ellis)

    "animations"                                               ← pose do sobrevivente para cada arma
    {
        "weapon_smg"            "Idle_Standing_SMG"
        "weapon_pumpshotgun"    "Idle_Standing_PumpShotgun"
        "weapon_pistol_magnum"  "Idle_Standing_pistol"
        "weapon_melee_katana"   "Idle_Standing_axe"
        ...
    }

    "c5m1_waterfront"                                          ← nome do mapa
    {
        "hand"   { ... }                                       ← uma seção por cena
        "ground"  { ... }
        "ground2" { ... }
        "ground3" { ... }
        "third"  { ... }
        "third2" { ... }
        "park"   { ... }
    }
}
```

O plugin só usa a seção do **mapa que está aberto**. Dá para ter cenas para vários mapas no mesmo arquivo.

---

## 5.2 Campos de uma cena

| Campo | Exemplo | Significado |
|---|---|---|
| `type` | `third` | Tipo: `hand`, `ground`, `third` ou `park`. Se omitido, usa o nome da cena. Duas cenas podem ter o mesmo tipo (`third` e `third2`) |
| `origin` | `"864.4 702.6 -481.9"` | Posição dos **pés** do jogador-câmera. O olho fica ~64 unidades acima |
| `angles` | `"10 231 0"` | Para onde a câmera olha: pitch, yaw, roll |
| `viewmodel` | `"1"` | Desenhar a arma em primeira pessoa (só faz sentido em `hand`) |
| `fov` | `"34"` | Zoom. 0 ou ausente = FOV padrão do jogo |
| `target_origin` | `"770 598 -482"` | Onde fica a arma no chão (`ground`) ou o sobrevivente (`third`) |
| `target_angles` | `"0 111 0"` | Rotação da arma no chão ou do sobrevivente |
| `melee_target_angles` | `"0 0 90"` | Só no chão: rotação usada para armas **melee**, que são modeladas num eixo diferente das armas de fogo |
| `fill` | `"0.3"` | Só para a calibração: quanto do quadro a arma deve ocupar (ver [documento 8](08-enquadramento-automatico.md)) |
| `framing` | seção | Enquadramento calibrado por arma (gerado pelo `calibrate.ps1`) |

### A cena `park`

`park` não vira foto. É o lugar onde o bot sobrevivente que sobra (o "ator") fica estacionado, longe da câmera e fora de todos os enquadramentos. O plugin não consegue simplesmente remover todos os bots: um time de sobreviventes sem ninguém faz o jogo reagir (reiniciar, criar bots novos). Então deixa um, parado e escondido.

### A seção `framing`

```text
"framing"
{
    "weapon_smg"            "5.85 222.76 8 170"
    "weapon_melee_katana"   "4.46 217.14 13 170"
    ...
}
```

Os quatro números são: **pitch**, **yaw** e **FOV** da câmera, e o **yaw do sobrevivente**. Nas cenas de chão não há sobrevivente, então são só os três primeiros. Quando existe uma linha para a arma da skin, ela **substitui** o `angles`, o `fov` e o yaw do `target_angles` da cena. Essa seção é escrita pelo `calibrate.ps1`; não é para editar à mão (mas pode, se quiser ajustar fino uma arma).

---

## 5.3 As cenas usadas em The Parish

| Cena | Tipo | Ideia |
|---|---|---|
| `hand` | `hand` | No cais, olhando para o rio e o barco a vapor, segurando a arma |
| `ground` | `ground` | A mesma posição, olhando bem para baixo (pitch 50), com a arma deitada no chão, cano para a esquerda |
| `ground2` | `ground` | A mesma arma deitada com o cano para a direita e o **outro lado** virado para cima |
| `ground3` | `ground` | A arma na diagonal e levemente inclinada, numa posição mais "natural", vista em perspectiva |
| `third` | `third` | O sobrevivente em pé perto de um muro de concreto iluminado pelo sol; close na arma |
| `third2` | `third` | Mesmo lugar e mesma pose, plano mais aberto (`fill 0.3`) |
| `park` | `park` | Atrás da câmera, fora de todos os quadros |

Todas as cenas usam **a mesma posição de câmera** (`864.4 702.6 -481.9`) e mudam só a direção, o zoom e o que é colocado na frente. Isso simplifica muito: a câmera nunca precisa atravessar o mapa, e a iluminação é a mesma em todas as fotos.

### Por que The Parish

O primeiro mapa testado foi outro, mas a luz de fim de tarde com neblina de The Parish deixa as armas mais bonitas, e o muro de concreto bate sol de lado, ótimo para destacar a arma na terceira pessoa. A escolha do mapa é estética: qualquer mapa serve, desde que se encontre posições boas.

---

## 5.4 Como achar uma boa posição

1. Abra o estúdio no mapa desejado e ande até um lugar bonito (a câmera é você).
2. Mire do jeito que a foto deveria sair.
3. Rode:
   ```powershell
   .\scripts\send.ps1 sm_shots_where
   ```
4. No log aparece a posição e os ângulos atuais:
   ```text
   where origin "864.4 702.6 -481.9" angles "5.0 -42.0 0.0" team 2 alive 1 observer 0
   ```
5. Copie para o `skin_shots.cfg` e teste uma skin:
   ```powershell
   .\scripts\send.ps1 sm_shots_show volcanic-uzi hand
   .\scripts\send.ps1 sm_shots_snap teste_mao
   ```
6. Abra `screenshots/skinshots/test/teste_mao.jpg`, ajuste e repita.

Para posicionar a arma no chão ou o sobrevivente, o processo é igual: fique em pé no ponto, rode `sm_shots_where` e use a posição dos pés como `target_origin`.

> Dica: `cl_showpos 1` no console mostra a posição e os ângulos na tela enquanto você anda (o plugin desliga isso nas fotos).

### Ângulos da arma no chão

A arma de chão é um `prop_dynamic` com o worldmodel. O worldmodel das armas é modelado "em pé", como se estivesse na mão. Para deitar a arma de lado no chão, o `target_angles` usa **roll 90**: `"0 270 90"`. O yaw (270) escolhe para que lado o cano aponta.

As três fotos de chão usam estas rotações:

| Cena | Armas de fogo | Melee | Por quê |
|---|---|---|---|
| `ground` | `0 270 90` | `0 0 90` | Cano para a esquerda |
| `ground2` | `0 90 -90` | `0 180 -90` | Cano para a direita. O **roll negativo** vira a arma para o outro lado; só girar o yaw mostraria o mesmo lado espelhado |
| `ground3` | `0 225 80` | `0 315 90` | Diagonal. O roll 80 (em vez de 90) inclina um pouco, mostrando o topo da arma |

**Por que a melee tem rotação própria.** Os modelos de melee do L4D2 têm o comprimento ao longo do eixo **z** (a lâmina "para cima"), enquanto as armas de fogo têm o cano ao longo do eixo **x**. Com a mesma rotação das armas de fogo, a katana ficava apontada para a câmera e as três fotos saíam quase iguais. Somar 90 graus ao yaw deixa a melee atravessada no quadro, como as armas de fogo.

Para testar uma rotação sem editar o arquivo:

```powershell
.\scripts\send.ps1 sm_shots_show floral-guitar ground
.\scripts\send.ps1 sm_shots_pose 0 315 90
.\scripts\send.ps1 sm_shots_snap teste_guitarra
```

### Encostando a arma no chão

A origem de um modelo de arma fica na empunhadura, não no ponto mais baixo. Deitada, parte da arma ficava **abaixo do chão** (a guitarra era a pior). O plugin calcula o ponto mais baixo da arma já girada e a levanta exatamente o necessário, então o `target_origin` deve ser a **altura do chão** (a mesma altura dos pés do `sm_shots_where`). O código dessa conta está explicado no [documento 13](13-codigo-do-plugin.md#138-spawnprop-e-lowestpoint-a-arma-no-chão-sem-afundar).

---

## 5.5 Animações (pose do sobrevivente)

O sobrevivente da terceira pessoa é um modelo com uma animação congelada. Cada tipo de arma precisa de uma pose que faça sentido:

| Arma | Animação | Observação |
|---|---|---|
| SMG, SMG silenciada, MP5 | `Idle_Standing_SMG` | Arma à frente, duas mãos |
| Escopetas de bomba | `Idle_Standing_PumpShotgun` | |
| Magnum | `Idle_Standing_pistol` | Uma mão estendida |
| Katana, machado | `Idle_Standing_axe` | Lâmina à frente, na diagonal |
| Taco de beisebol, de críquete, de golfe | `Idle_Standing_axe` | A pose própria do taco (`idle_standing_bat`) apoia no ombro, **atrás da cabeça**; a do machado deixa à frente |
| Facão, pé de cabra, frigideira | `Idle_Standing_fry_pan` | |
| Guitarra | `Idle_Standing_guitar` | |

Os nomes das animações vêm do próprio modelo do sobrevivente. Uma forma de descobrir os disponíveis é abrir o modelo no HLMV (Half-Life Model Viewer) ou procurar `Idle_Standing` dentro do `.mdl`.

---

Próximo: [6. Primeira pessoa e chão](06-mao-e-chao.md)
