# 14. O código da calibração, parte por parte

O [documento 8](08-enquadramento-automatico.md) explicou a ideia e a matemática. Este documento percorre o código de [`scripts/calibrate.ps1`](../scripts/calibrate.ps1), mostrando cada trecho de verdade com a explicação.

O script tem três camadas:

```text
┌──────────────────────────────────────────────────────────────┐
│ PowerShell: laço principal (cenas → armas → giros → passos)   │
│   ├─ Send / Snap / Find-Weapon : conversa com o jogo          │
│   └─ Solve                     : matemática da câmera         │
├──────────────────────────────────────────────────────────────┤
│ C# (compilado na hora com Add-Type): ShotDiff.Box             │
│   └─ compara dois prints e acha a arma (maior região)         │
└──────────────────────────────────────────────────────────────┘
```

---

## 14.1 Parâmetros e preparação

```powershell
param(
    [string[]]$Scenes = @('third', 'third2'),
    [string[]]$Weapons = @(),
    [double]$FillWidth = 0.6,
    [double]$FillHeight = 0.65,
    [int]$Passes = 4,
    [int[]]$ActorYaws = @(170, 190, 210, 230, 250, 270, 290),
    [string]$Studio = $(if ($env:L4D2_STUDIO) { $env:L4D2_STUDIO } else { 'E:\L4D2-Studio' })
)
$ErrorActionPreference = 'Stop'
$Scenes = @($Scenes -split ',' | Where-Object { $_ })
$Weapons = @($Weapons -split ',' | Where-Object { $_ })
```

- **`param(...)`** declara os parâmetros do script. Cada um tem tipo e valor padrão. Rodar `.\calibrate.ps1 -Scenes ground` troca só esse.
- **`$Studio`** tem um padrão calculado: usa a variável de ambiente `L4D2_STUDIO` se existir, senão `E:\L4D2-Studio`. Assim cada pessoa pode apontar para a sua cópia sem editar o script.
- **`$ErrorActionPreference = 'Stop'`**: qualquer erro de comando interrompe o script. Sem isso o PowerShell só avisa e continua, e você descobre o problema 15 minutos depois.
- **`-split ','`**: com `pwsh -File script.ps1 -Weapons a,b`, a lista chega como **um texto** `"a,b"`. O split transforma em `@('a','b')`. `Where-Object { $_ }` remove itens vazios.

---

## 14.2 Compilando C# dentro do PowerShell

```powershell
Add-Type -AssemblyName System.Drawing
$references = @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Rectangle].Assembly.Location) +
    @([AppDomain]::CurrentDomain.GetAssemblies() |
      Where-Object { $_.GetName().Name -in @('System.Private.Windows.GdiPlus', 'System.Private.Windows.Core', 'System.Runtime.InteropServices') } |
      ForEach-Object Location)
Add-Type -ReferencedAssemblies $references -TypeDefinition @'
using System;
...
public static class ShotDiff { ... }
'@
```

- **`Add-Type -TypeDefinition`** compila código C# na hora e deixa a classe disponível no PowerShell como `[ShotDiff]`.
- **Por que C#?** O laço de pixels roda ~2 milhões de vezes por imagem. Em PowerShell puro isso leva minutos; em C# compilado, milissegundos.
- **As referências.** No .NET moderno (PowerShell 7), a classe `Bitmap` está espalhada em vários assemblies. O compilador precisa saber de todos. O truque é carregar `System.Drawing` primeiro (`Add-Type -AssemblyName`) e então pegar o caminho dos assemblies já carregados (`.Assembly.Location`). Sem isso, o erro é `The type 'IImage' is defined in an assembly that is not referenced`.
- **`@' ... '@`** é uma *here-string* literal: tudo entre as marcas é texto puro, sem o PowerShell interpretar `$` ou aspas. Perfeito para colar código C#.

---

## 14.3 `ShotDiff.Box`: achando a arma

### Lendo os pixels rápido

```csharp
using (var a = new Bitmap(withWeapon))
using (var b = new Bitmap(withoutWeapon))
{
    int w = a.Width, h = a.Height;
    var rect = new Rectangle(0, 0, w, h);
    var da = a.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var db = b.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
    var pa = new byte[da.Stride * h];
    var pb = new byte[db.Stride * h];
    Marshal.Copy(da.Scan0, pa, 0, pa.Length);
    Marshal.Copy(db.Scan0, pb, 0, pb.Length);
    a.UnlockBits(da);
    b.UnlockBits(db);
```

- **`using (...)`** garante que as imagens sejam liberadas no fim, mesmo se der erro.
- **`LockBits`** "trava" a imagem na memória e devolve onde os pixels estão (`Scan0`). É muito mais rápido que `GetPixel(x, y)`, que faz várias checagens a cada chamada.
- **`Format24bppRgb`**: 3 bytes por pixel, na ordem **B, G, R** (azul primeiro, é o formato do Windows).
- **`Stride`**: o número de bytes de **uma linha**. Pode ser maior que `largura × 3`, porque o Windows alinha cada linha em múltiplos de 4 bytes. Por isso o índice de um pixel é `y * Stride + x * 3`, nunca `(y * w + x) * 3`.
- **`Marshal.Copy`** copia os bytes da memória da imagem para um array comum, fácil de percorrer.

### Contando mudanças por célula

```csharp
const int cell = 8;
int cw = (w + cell - 1) / cell, ch = (h + cell - 1) / cell;
var cells = new int[cw * ch];
for (int y = 0; y < h; y++)
{
    int line = y * da.Stride;
    for (int x = 0; x < w; x++)
    {
        int i = line + x * 3;
        int diff = Math.Abs(pa[i] - pb[i]) + Math.Abs(pa[i + 1] - pb[i + 1]) + Math.Abs(pa[i + 2] - pb[i + 2]);
        if (diff > threshold)
        {
            cells[(y / cell) * cw + x / cell]++;
        }
    }
}
```

- A imagem é dividida numa grade de células de 8×8 pixels. `cw` e `ch` são quantas células cabem na largura e altura. O `+ cell - 1` arredonda **para cima** (uma imagem de 1920 px tem 240 células; uma de 1921 teria 241).
- Para cada pixel, soma a diferença absoluta dos três canais. Se passar do limiar (60), o pixel "mudou", e a célula dele ganha +1.
- `(y / cell) * cw + x / cell` transforma a posição do pixel na posição da célula num array de uma dimensão (linha da célula × largura + coluna da célula). Divisão de inteiros em C# descarta a parte decimal, que é exatamente o "em qual célula cai".

### A maior região conectada (busca em profundidade)

```csharp
var label = new int[cw * ch];
var stack = new int[cw * ch];
int top = 0;
int bestCount = 0, bx1 = -1, by1 = -1, bx2 = -1, by2 = -1, next = 0;
for (int start = 0; start < cells.Length; start++)
{
    if (cells[start] < 4 || label[start] != 0)
    {
        continue;
    }

    next++;
    int count = 0, x1 = int.MaxValue, y1 = int.MaxValue, x2 = -1, y2 = -1;
    label[start] = next;
    stack[top++] = start;
    while (top > 0)
    {
        int c = stack[--top];
        int cx = c % cw, cy = c / cw;
        count += cells[c];
        x1 = Math.Min(x1, cx); x2 = Math.Max(x2, cx); y1 = Math.Min(y1, cy); y2 = Math.Max(y2, cy);
        for (int dy = -2; dy <= 2; dy++)
        {
            for (int dx = -2; dx <= 2; dx++)
            {
                int nx = cx + dx, ny = cy + dy;
                if (nx < 0 || ny < 0 || nx >= cw || ny >= ch)
                {
                    continue;
                }

                int n = ny * cw + nx;
                if (cells[n] >= 4 && label[n] == 0)
                {
                    label[n] = next;
                    stack[top++] = n;
                }
            }
        }
    }

    if (count > bestCount)
    {
        bestCount = count; bx1 = x1; by1 = y1; bx2 = x2; by2 = y2;
    }
}
```

É o algoritmo clássico de **rotulação de componentes conectados**, o mesmo do "balde de tinta" de um editor de imagem:

1. Percorre as células. Uma célula é **ativa** se teve 4 ou mais pixels mudados.
2. Ao achar uma célula ativa ainda **sem rótulo**, começa uma região nova (`next++`).
3. Usa uma **pilha** para visitar as vizinhas: tira uma célula da pilha, soma os pixels dela, atualiza o retângulo da região (`x1..x2`, `y1..y2`) e empilha as vizinhas ativas sem rótulo, já rotulando.
4. **Vizinhança de 5×5** (`dx`, `dy` de −2 a 2): considera vizinhas até 2 células de distância. Uma lâmina fina de katana, vista de lado, pode ter buracos de uma célula; com vizinhança grande, ela continua sendo uma região só.
5. Quando a pilha esvazia, a região acabou. Se ela tem mais pixels mudados que a melhor até agora, vira a melhor.

Por que uma pilha (array + `top`) e não recursão? Uma região grande pode ter milhares de células; recursão profunda estoura a pilha de chamadas. Uma pilha explícita não tem esse limite.

### O resultado

```csharp
if (bestCount == 0)
{
    return new[] { -1, -1, -1, -1, w, h, 0 };
}

return new[] { bx1 * cell, by1 * cell, Math.Min(w - 1, bx2 * cell + cell - 1), Math.Min(h - 1, by2 * cell + cell - 1), w, h, bestCount };
```

Devolve um array de 7 inteiros: o retângulo da arma em **pixels** (as coordenadas de célula multiplicadas por 8), o tamanho da imagem e quantos pixels mudaram. `-1` no primeiro valor significa "não achei arma nenhuma".

---

## 14.4 Conversando com o jogo

```powershell
function Send([string]$command)
{
    $queue = Join-Path $Studio 'left4dead2\addons\sourcemod\data\skin_shots_queue.txt'
    Add-Content -Path $queue -Value $command -Encoding ascii
}

function Snap([string]$name)
{
    $file = Join-Path $Studio "left4dead2\screenshots\skinshots\test\$name.jpg"
    Remove-Item $file -ErrorAction SilentlyContinue
    Send "sm_shots_snap $name"
    for ($i = 0; $i -lt 40 -and -not (Test-Path $file); $i++) { Start-Sleep -Milliseconds 250 }
    if (-not (Test-Path $file)) { throw "screenshot $name not saved" }
    Start-Sleep -Milliseconds 300
    $file
}

function Find-Weapon([string]$tag)
{
    $with = Snap "cal_${tag}_a"
    Send 'sm_shots_weapon 0'
    Start-Sleep -Milliseconds 800
    $without = Snap "cal_${tag}_b"
    Send 'sm_shots_weapon 1'
    Start-Sleep -Milliseconds 500
    [ShotDiff]::Box($with, $without, 60)
}
```

- **`Snap` apaga o arquivo antes.** Assim, "o arquivo existe" significa com certeza "o print novo chegou", e não "sobrou um de antes".
- **Espera com limite**: até 40 × 250 ms = 10 s. Se não chegar, `throw` interrompe o script com uma mensagem clara.
- **Os 300 ms extras** depois de o arquivo aparecer dão tempo para o plugin terminar de mover o arquivo.
- **A última linha de uma função PowerShell é o retorno.** `$file` sozinho na linha devolve o caminho. Cuidado: **qualquer** valor solto numa função vira parte do retorno, por isso os comandos com saída (como `Send`, que usa `Add-Content`) não devolvem nada.
- **`Find-Weapon`** tira os dois prints (com e sem arma), espera a arma reaparecer e chama o C#. `[ShotDiff]::Box(...)` é a sintaxe do PowerShell para chamar um método estático de uma classe .NET.
- **O nome `Find-Weapon`** segue o padrão Verbo-Substantivo do PowerShell. A primeira versão se chamava `Measure`, que é um **apelido** de `Measure-Object`; apelidos têm prioridade sobre funções, e a função nunca era chamada.

---

## 14.5 `Solve`: a matemática da câmera em código

```powershell
function Solve([double]$pitch, [double]$yaw, [double]$fov, [int[]]$box)
{
    $rad = [Math]::PI / 180
    $tanH = [Math]::Tan($fov * $rad / 2) * 4 / 3
    $tanV = $tanH * 9 / 16
    $w = $box[4]; $h = $box[5]
    $nx = (($box[0] + $box[2]) / 2 - $w / 2) / ($w / 2) * $tanH
    $ny = ($h / 2 - ($box[1] + $box[3]) / 2) / ($h / 2) * $tanV

    $cp = [Math]::Cos($pitch * $rad); $sp = [Math]::Sin($pitch * $rad)
    $cy = [Math]::Cos($yaw * $rad); $sy = [Math]::Sin($yaw * $rad)
    $dx = $cp * $cy + $nx * $sy + $ny * $sp * $cy
    $dy = $cp * $sy - $nx * $cy + $ny * $sp * $sy
    $dz = -$sp + $ny * $cp

    $newYaw = [Math]::Atan2($dy, $dx) / $rad
    $newPitch = -[Math]::Atan2($dz, [Math]::Sqrt($dx * $dx + $dy * $dy)) / $rad

    $fill = [Math]::Max(($box[2] - $box[0]) / $w / $fillWidth, ($box[3] - $box[1]) / $h / $fillHeight)
    $newFov = [Math]::Ceiling(2 * [Math]::Atan([Math]::Tan($fov * $rad / 2) * $fill) / $rad - 0.05)

    [Math]::Round($newPitch, 2), [Math]::Round(($newYaw + 360) % 360, 2), [Math]::Min(60, [Math]::Max(4, $newFov))
}
```

Linha a linha:

| Código | Significado |
|---|---|
| `$rad = PI / 180` | Fator de graus para radianos (as funções trigonométricas usam radianos) |
| `$tanH`, `$tanV` | Meia-largura e meia-altura da tela em "unidades de tangente", para o FOV atual |
| `($box[0] + $box[2]) / 2` | Centro horizontal da arma, em pixels |
| `- $w / 2` e `/ ($w / 2)` | Transforma em −1 (borda esquerda) a +1 (borda direita), com 0 no centro |
| `* $tanH` | Converte em tangente: `nx` |
| `$ny` | Mesma coisa na vertical, mas invertido (`$h / 2 - ...`): na imagem o y cresce para baixo, no mundo "cima" é positivo |
| `$cp, $sp, $cy, $sy` | Seno e cosseno do pitch e do yaw atuais, calculados uma vez |
| `$dx, $dy, $dz` | A direção 3D até o centro da arma: `frente + nx·direita + ny·cima`, já expandida componente a componente |
| `Atan2($dy, $dx)` | O yaw que aponta para essa direção. `Atan2` (e não `Atan`) acerta o quadrante |
| `-Atan2($dz, √(dx²+dy²))` | O pitch: ângulo da direção com o plano horizontal, negativo porque pitch positivo olha para baixo |
| `$fill` | Quantas vezes a arma está maior (>1) ou menor (<1) do que o desejado, na direção mais restritiva |
| `$newFov` | FOV que deixa a arma do tamanho certo: escala a tangente do meio-FOV pela proporção |
| `($newYaw + 360) % 360` | Normaliza o yaw para 0..360 (o `Atan2` devolve −180..180) |
| `Min(60, Max(4, ...))` | Trava o FOV entre 4 e 60 graus, para nunca divergir |

A última linha devolve **três valores**, e quem chama recebe nas três variáveis ao mesmo tempo:

```powershell
$pitch, $yaw, $fov = Solve $pitch $yaw $fov $box
```

### Lendo as variáveis de fora

`Solve` usa `$fillWidth` e `$fillHeight` sem recebê-los como parâmetro. Em PowerShell, uma função enxerga as variáveis do **escopo de quem chamou**. O laço principal define essas duas para cada cena, e a `Solve` as lê. É prático, mas esconde dependências; num código maior, valeria passar como parâmetro.

---

## 14.6 O laço principal

```powershell
foreach ($scene in $Scenes)
{
    $block = [regex]::Match($config, "(?s)\n\t\t""$scene""\r?\n\t\t\{.*?\n\t\t\}")
    ...
    foreach ($weapon in $samples.Keys)
    {
        $pitch = $basePitch; $yaw = $baseYaw; $fov = $baseFov
        Send "sm_shots_show $($samples[$weapon]) $scene"
        Start-Sleep -Seconds 3
        Send "sm_shots_weapon noshadow"
        Send "sm_shots_frame $pitch $yaw $fov"

        $isThird = [regex]::Match($block.Value, '"type"\s*"third"').Success
        $candidates = @()
        if ($isThird -and ($scene -eq 'third' -or -not $chosen.Contains($weapon)))
        {
            $candidates = $ActorYaws
        }
        elseif ($isThird)
        {
            $candidates = @($chosen[$weapon])
        }

        $actorYaw = -1; $best = -1
        foreach ($candidate in $candidates)
        {
            Send "sm_shots_turn $candidate"
            Start-Sleep -Milliseconds 600
            $box = Find-Weapon "$scene"
            if ($box[6] -gt $best) { $best = $box[6]; $actorYaw = $candidate }
        }

        if ($isThird)
        {
            Send "sm_shots_turn $actorYaw"
            $chosen[$weapon] = $actorYaw
        }

        for ($pass = 0; $pass -lt $Passes; $pass++)
        {
            Send "sm_shots_frame $pitch $yaw $fov"
            Start-Sleep -Milliseconds 800
            $box = Find-Weapon "$scene"
            if ($box[0] -lt 0) { Write-Warning "$scene $weapon`: weapon not found on screen"; break }
            $pitch, $yaw, $fov = Solve $pitch $yaw $fov $box
        }
        $results[$weapon] = if ($isThird) { "$pitch $yaw $fov $actorYaw" } else { "$pitch $yaw $fov" }
    }
    ...
}
```

### A expressão regular da cena

```text
(?s)\n\t\t"third"\r?\n\t\t\{.*?\n\t\t\}
```

| Parte | Significado |
|---|---|
| `(?s)` | O `.` passa a casar também quebra de linha (modo *single line*) |
| `\n\t\t"third"` | Uma linha com dois tabs e `"third"`: o nome da cena, no nível certo de indentação |
| `\r?\n` | Quebra de linha do Windows (`\r\n`) ou Unix (`\n`) |
| `\t\t\{` | A chave que abre a cena |
| `.*?` | Qualquer coisa, **o mínimo possível** (o `?` torna "preguiçoso") |
| `\n\t\t\}` | A primeira chave de fechamento **com dois tabs**: o fim desta cena |

O "preguiçoso" e a indentação juntos fazem a busca parar no fim da cena certa, sem engolir as cenas seguintes nem parar no fim de um bloco interno (o `framing` fecha com **três** tabs).

> Usar regex num arquivo estruturado é frágil (depende da indentação exata). Funciona aqui porque o próprio script escreve o arquivo sempre do mesmo jeito. Um leitor de KeyValues de verdade seria mais robusto.

### Por que os `Start-Sleep`

| Espera | Motivo |
|---|---|
| 3 s depois de `sm_shots_show` | O plugin lê a fila a cada 0,5 s, cria o prop/manequim, e o jogo precisa carregar as texturas |
| 600 ms depois de girar | O cliente interpola a rotação por alguns frames |
| 800 ms depois de mudar o enquadramento | A câmera e o FOV mudam suavemente; esperar estabilizar |
| 800 ms depois de esconder a arma | O `TurnOff` precisa chegar ao cliente antes do próximo print |

### Escolhendo o giro, só na terceira pessoa

- Cenas de **chão** não têm sobrevivente: `$candidates` fica vazio, o laço de giros não roda e o resultado tem só 3 números.
- A cena **`third`** sempre procura o melhor giro e guarda em `$chosen`.
- As outras cenas de terceira pessoa (`third2`) **reaproveitam** o giro escolhido.

---

## 14.7 Gravando no arquivo

```powershell
$framing = "`n`t`t`t""framing""`n`t`t`t{`n" +
    (($results.Keys | ForEach-Object { "`t`t`t`t""$_""`t""$($results[$_])""" }) -join "`n") +
    "`n`t`t`t}"
$body = [regex]::Replace($block.Value, '(?s)\r?\n\t\t\t"framing"\r?\n\t\t\t\{.*?\n\t\t\t\}', '')
$body = $body -replace '\r?\n\t\t\}$', "$framing`n`t`t}"
$config = $config.Replace($block.Value, $body)
```

1. **Monta o bloco novo.** No PowerShell, a crase é o caractere de escape: `` `n `` é quebra de linha, `` `t `` é tab, e `""` dentro de aspas duplas é uma aspa literal.
2. **Remove o bloco `framing` antigo** da cena, se houver (de novo, pela indentação de três tabs).
3. **Insere o novo** logo antes do `}` que fecha a cena (o `$` na regex significa "no fim do texto").
4. **Troca o bloco da cena** no arquivo inteiro.

No fim, grava sem BOM (`utf8NoBOM`, o leitor de KeyValues do jogo não gosta de BOM) e copia para a pasta do jogo.

---

## 14.8 Exercícios para fixar

1. Rode `.\tools\diffimg.ps1` com um par `cal_third_a.jpg`/`cal_third_b.jpg` e veja a máscara. Depois mude o limiar de 60 para 20 dentro do `diffimg.ps1`. O que aparece de ruído?
2. No C#, troque a vizinhança de `-2..2` para `-1..1` e calibre só a katana (`-Weapons weapon_melee_katana`). O retângulo encontrado muda? Por quê?
3. Coloque `-Passes 1` e compare o enquadramento com o de 4 passos.
4. Mude `-FillWidth 0.9` e veja o que acontece com armas compridas como a katana.

---

Voltar ao [início](../README.md).
