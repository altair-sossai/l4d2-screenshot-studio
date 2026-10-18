# 8. Enquadramento automático

Este é o documento mais técnico. Ele explica como o [`scripts/calibrate.ps1`](../scripts/calibrate.ps1) descobre, sozinho, **para onde apontar a câmera, quanto dar de zoom e como girar o sobrevivente** para cada arma, de forma que a arma fique centralizada e ocupe a maior parte da foto.

---

## 8.1 O problema

Com a câmera fixa, as armas saíam pequenas, fora do centro, às vezes cortadas (uma katana é muito mais comprida que uma Magnum) e às vezes escondidas atrás do corpo. Ajustar à mão 15 armas × 2 cenas é trabalhoso e frágil: qualquer mudança na cena obriga a refazer tudo.

O plugin não enxerga a imagem. Ele sabe onde está o sobrevivente, mas **não sabe onde a arma aparece na tela**. As tentativas de calcular isso pela geometria (posição do osso da mão + caixa do modelo) erravam muito para as armas melee: o modelo da arma é encaixado pelo bonemerge de um jeito que o servidor não consegue reproduzir com precisão.

**A ideia que resolveu: em vez de calcular onde a arma está, olhar onde ela está.**

---

## 8.2 Achando a arma na imagem: a diferença de dois prints

Para uma cena qualquer:

1. tira um print **com** a arma (`cal_third_a.jpg`);
2. esconde só a arma (`sm_shots_weapon 0`, que manda a entrada `TurnOff` para o prop da arma);
3. tira outro print **sem** a arma (`cal_third_b.jpg`);
4. mostra a arma de novo (`sm_shots_weapon 1`).

Tudo que mudou entre os dois prints **é a arma**. Comparando pixel a pixel:

```text
diferença = |R_a - R_b| + |G_a - G_b| + |B_a - B_b|
mudou     = diferença > 60
```

O limiar 60 ignora o ruído de compressão do JPEG. O resultado é uma "máscara" da arma:

```text
  print com arma          print sem arma            máscara (mudou)
 ┌───────────────┐       ┌───────────────┐        ┌───────────────┐
 │      ___      │       │      ___      │        │               │
 │     (o.o)     │       │     (o.o)     │        │               │
 │   ==/|==█████ │   -   │     /|\       │   =    │   ==  =█████  │
 │      / \      │       │     / \       │        │               │
 └───────────────┘       └───────────────┘        └───────────────┘
```

### O cálculo em C#, dentro do PowerShell

Comparar 2 milhões de pixels num laço de PowerShell levaria minutos. O script compila um pequeno trecho em C# na hora (`Add-Type`) e usa `LockBits`, que dá acesso direto à memória da imagem:

```csharp
var da = a.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
var pa = new byte[da.Stride * h];
Marshal.Copy(da.Scan0, pa, 0, pa.Length);   // copia os pixels para um array
...
int i = y * stride + x * 3;                  // B, G, R de cada pixel
int diff = Math.Abs(pa[i] - pb[i]) + Math.Abs(pa[i+1] - pb[i+1]) + Math.Abs(pa[i+2] - pb[i+2]);
```

Assim a comparação leva milissegundos.

### Ficando só com a arma: a maior região conectada

A primeira versão pegava o retângulo que contém **todos** os pixels que mudaram. Isso deu errado de três jeitos diferentes, todos reais:

| O que também mudava | Por quê | Efeito |
|---|---|---|
| A **sombra** da arma na parede | Ao esconder a arma, a sombra também some | O retângulo crescia até a parede; a câmera se afastava |
| O **rosto** do sobrevivente | A expressão facial muda sozinha entre os prints (ver [documento 7](07-terceira-pessoa.md#74-o-rosto-deformado)) | O retângulo puxava para a cabeça |
| **Plantas** balançando ao vento | Com zoom aberto, vasos de uma sacada entravam no quadro | O cálculo divergia (FOV ia para 103!) |

As correções:

1. **Sombra:** antes de medir, o script manda `sm_shots_weapon noshadow` (entrada `DisableShadow` no prop da arma). A sombra só é desligada durante a calibração; nas fotos finais ela existe.
2. **Rosto e plantas:** em vez de "todos os pixels que mudaram", o script pega **a maior região conectada**:
   - divide a imagem em células de 8×8 pixels;
   - uma célula é "ativa" se tem pelo menos 4 pixels que mudaram;
   - junta células ativas vizinhas (até 2 células de distância, para não partir uma lâmina fina de katana em pedaços) com uma busca em profundidade;
   - fica com a região de **maior soma de pixels mudados**: a arma.

```text
células ativas:                     regiões:
 . . . . . . . . . .                 . . . . . . . . . .
 . . # . . . . . . .   ← rosto       . . A . . . . . . .   A = 3 pixels mudados
 . . . . . . . . . .                 . . . . . . . . . .
 . # # # # # # # . .   ← arma        . B B B B B B B . .   B = 840 pixels mudados  ← escolhida
 . . . . . . . . . #   ← planta      . . . . . . . . . C   C = 12 pixels mudados
```

O resultado é o **retângulo da arma em pixels**: `x1, y1, x2, y2`, mais a contagem de pixels.

---

## 8.3 Escolhendo o giro do sobrevivente

Para cada arma, o script testa o sobrevivente em vários giros (`ActorYaws`: 170, 190, 210, 230, 250, 270, 290 graus) com a câmera aberta, e mede **quantos pixels da arma aparecem** em cada um. Fica com o giro que mostra mais arma.

Por que isso funciona: quando a arma está de lado para a câmera e na frente do corpo, ela aparece inteira e grande. Quando está de ponta para a câmera ou escondida atrás do corpo, aparecem poucos pixels. Contar pixels é uma medida simples de "quão bem a arma aparece".

A faixa de giros foi escolhida para que **o rosto fique de costas ou de perfil** para a câmera em todos eles.

A segunda cena (`third2`) **reaproveita o giro** escolhido para a primeira e muda só o zoom. Uma versão anterior obrigava a segunda cena a usar um giro diferente, mas na faixa sem rosto os giros que sobravam eram de costas, com o corpo cobrindo a arma.

---

## 8.4 Apontando a câmera

Com o retângulo da arma em mãos, falta transformar "a arma está 300 pixels à esquerda e 120 abaixo do centro" em "gire a câmera X graus".

### Do pixel para uma direção

Na Source Engine, o FOV é definido como se a tela fosse 4:3. Numa tela 16:9 o jogo abre a imagem para os lados. Para um FOV `f`:

```text
tanH = tan(f/2) × (4/3)        ← meia-largura da tela, em "unidades de tangente"
tanV = tanH × (9/16)           ← meia-altura
```

Um pixel `(px, py)` numa tela `W × H` corresponde a:

```text
nx = (px - W/2) / (W/2) × tanH      ← quanto à direita do centro
ny = (H/2 - py) / (H/2) × tanV      ← quanto acima do centro
```

A direção 3D desse pixel é a frente da câmera, mais `nx` vezes a direita, mais `ny` vezes o cima. Com os ângulos atuais `pitch` (p) e `yaw` (y) da câmera:

```text
frente  = ( cos p · cos y,   cos p · sin y,   -sin p )
direita = ( sin y,          -cos y,            0     )
cima    = ( sin p · cos y,   sin p · sin y,    cos p )

d = frente + nx · direita + ny · cima
```

E os novos ângulos que apontam para o centro da arma:

```text
novo yaw   = atan2(d.y, d.x)
novo pitch = -atan2(d.z, √(d.x² + d.y²))       ← negativo porque pitch positivo olha para baixo
```

### O zoom

Queremos que a arma ocupe uma fração `fill` do quadro (0,88 nas cenas do chão, para a arma ficar grande com bordas estreitas; 0,6 da largura ou 0,65 da altura no close da terceira pessoa; 0,3 no plano aberto). Se agora ela ocupa `w/W` da largura, o fator de correção é:

```text
fator = max( (largura da arma / W) / fillLargura ,  (altura da arma / H) / fillAltura )
novo FOV = 2 · atan( tan(FOV atual / 2) · fator )
```

O `max` garante que a arma caiba nas duas direções (uma katana na diagonal é limitada pela altura, uma escopeta deitada pela largura).

> **Por que este cálculo de zoom não usa `tanH` e `tanV`.** A primeira versão calculava o zoom a partir do tamanho angular da arma, usando a conversão 4:3 → 16:9. O resultado saía sistematicamente errado (a arma ficava com metade do tamanho pedido), porque a conversão não batia exatamente com o jogo. A versão final usa só a **proporção** entre o tamanho medido e o desejado. Uma proporção não depende da conversão: qualquer erro de escala se cancela. O centro ainda usa a conversão, mas erros ali se corrigem sozinhos com as repetições (próxima seção).

O FOV final é limitado entre 4 e 60 graus, para nunca divergir para valores absurdos.

---

## 8.5 Repetir até convergir

O FOV novo é arredondado **para cima** (o lado mais aberto): o FOV do jogo é inteiro, e nos zooms fechados (FOV 8 a 15) um grau a menos aumenta a arma em 7 a 12%, o que com `fill` 0,88 poderia cortá-la. Uma correção só não basta: o FOV do jogo é inteiro, a conversão de pixels é aproximada e a arma não é um ponto. O script repete **medir → corrigir** 4 vezes (`Passes`). Cada repetição parte do resultado anterior, com a arma já maior e mais centralizada, então a medida fica mais precisa e o erro diminui.

```text
passo 1:  FOV 34, arma pequena no canto       → aponta e aproxima
passo 2:  FOV 12, arma quase no centro         → ajuste fino
passo 3:  FOV  9, arma centralizada            → quase nada muda
passo 4:  FOV  8                               → pronto
```

---

## 8.6 Salvando

O resultado de cada arma é uma linha no `skin_shots.cfg`, dentro da cena:

```text
"framing"
{
    "weapon_smg"   "5.85 222.76 8 170"      ← pitch, yaw, FOV, giro do sobrevivente
}
```

O script lê o arquivo, substitui o bloco `framing` da cena (mantendo as armas que não foram recalibradas), grava e copia para a pasta do jogo. Na próxima foto, o plugin lê o arquivo e usa os valores.

### Uma skin por arma basta

Todas as skins de uma arma usam a mesma malha combinada, só muda a textura. O script calibra com **a primeira skin de cada arma** do `weapon_skins.cfg` e o resultado vale para todas.

---

## 8.7 Parâmetros

```powershell
.\scripts\calibrate.ps1 `
    -Scenes third,third2 `             # cenas a calibrar
    -Weapons weapon_smg,weapon_melee_katana `   # só estas armas (padrão: todas)
    -FillWidth 0.6 -FillHeight 0.65 `  # quanto do quadro a arma ocupa (se a cena não tiver "fill")
    -Passes 4 `                        # repetições de medir/corrigir
    -ActorYaws 170,190,210,230,250,270,290   # giros do sobrevivente a testar
```

Quando os argumentos de lista são passados com `pwsh -File`, eles chegam como **um texto só** (`"weapon_smg,weapon_melee_katana"`). Por isso o script separa por vírgula logo no início:

```powershell
$Scenes = @($Scenes -split ',' | Where-Object { $_ })
$Weapons = @($Weapons -split ',' | Where-Object { $_ })
```

### Uma pegadinha do PowerShell

A primeira versão tinha uma função chamada `Measure`. No PowerShell, **apelidos têm prioridade sobre funções**, e `measure` é apelido de `Measure-Object`. A chamada ia para o comando errado e devolvia nada. A função foi renomeada para `Find-Weapon`.

---

## 8.8 Tempo

Para 14 armas × 2 cenas: cerca de 15 minutos. A primeira cena testa 7 giros (2 prints cada) mais 4 repetições (2 prints cada) por arma; a segunda só faz as repetições.

---

Próximo: [9. Tratamento das imagens](09-tratamento.md)
