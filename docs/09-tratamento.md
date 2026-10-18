# 9. Tratamento das imagens

Os prints saem do jogo na resolução da janela do estúdio (1600×900, padrão do `run-studio.ps1`), JPEG com qualidade 95, em:

```text
left4dead2/screenshots/skinshots/
├── hand/<skin>.jpg
├── ground/<skin>.jpg
├── ground2/<skin>.jpg
├── ground3/<skin>.jpg
├── third/<skin>.jpg
├── third2/<skin>.jpg
└── test/            ← prints avulsos (sm_shots_snap) e da calibração
```

Um print desses tem ~500 KB. Para um site, isso é pesado demais: uma página com 196 skins seria impossível. O [`scripts/process-shots.ps1`](../scripts/process-shots.ps1) transforma cada print em versões pequenas, em formatos modernos.

---

## 9.1 As versões de cada foto

As seis fotos de cada skin são numeradas na ordem em que aparecem no site:

| Nº | Cena |
|---|---|
| 1 | `hand` (primeira pessoa) |
| 2, 3, 4 | `ground`, `ground2`, `ground3` (no chão) |
| 5, 6 | `third`, `third2` (terceira pessoa) |

E cada foto vira até três arquivos, cada um para um uso no site:

| Arquivo | Tamanho | Para quê | Peso médio (AVIF) |
|---|---|---|---|
| `N.avif` / `N.webp` | a do print (1600×900), sem reduzir | A imagem grande da janela de detalhes e o zoom | ~75 KB |
| `N-thumb.avif` / `N-thumb.webp` | 320×180 | As miniaturas embaixo da imagem grande | ~6 KB |
| `N-card.avif` / `N-card.webp` | 540×540 | O card da loja, quando o mouse passa por cima (só fotos 1, 5 e 6) | ~15 KB |

```text
skin-shots/
└── volcanic-uzi/
    ├── 1.avif   1.webp   1-thumb.avif   1-thumb.webp   1-card.avif   1-card.webp
    ├── 2.avif   2.webp   2-thumb.avif   2-thumb.webp
    ├── ...
    └── 6.avif   6.webp   6-thumb.avif   6-thumb.webp   6-card.avif   6-card.webp
```

Por que três tamanhos? Porque **cada um é baixado num momento diferente**:

- ao abrir a loja, nenhuma foto é baixada (o card mostra a imagem da Workshop, como antes);
- ao passar o mouse num card, baixa só os 3 `-card` daquela skin (~45 KB);
- ao abrir os detalhes, baixa a foto 1 grande e as 6 miniaturas (~80 KB);
- cada miniatura clicada baixa a sua versão grande.

### O card é quadrado

O card da loja é quadrado e as fotos são 16:9. Cortar sempre no centro funcionaria para as fotos de terceira pessoa (a calibração centralizou a arma), mas não para a primeira pessoa: a arma fica à direita da tela. Por isso o recorte quadrado tem um centro por tipo:

```powershell
$cardCenter = @{ hand = 0.6; handMelee = 0.72 }
```

O número é a posição horizontal do centro do recorte (0 = borda esquerda, 1 = direita). As armas melee ficam ainda mais à direita na primeira pessoa, por isso têm um valor próprio. O script descobre se a skin é melee lendo o `weapon_skins.cfg`.

As miniaturas e a imagem grande **não** são quadradas: mostram a foto inteira em 16:9, porque numa miniatura quadrada a escopeta e a katana ficavam cortadas.

---

## 9.2 Comprimir ao máximo sem perder qualidade

### Formato: AVIF, com WebP de reserva

| Formato | Suporte | Tamanho para a mesma qualidade |
|---|---|---|
| JPEG | Todos | Referência |
| **WebP** | Todos os navegadores atuais | ~30% menor que JPEG |
| **AVIF** | Chrome, Firefox, Safari 16+, Edge | ~50% menor que JPEG |

O site detecta se o navegador abre AVIF (carregando uma imagem AVIF minúscula embutida no código) e usa AVIF; senão, WebP. Por isso cada arquivo existe nos dois formatos.

### Como a qualidade foi escolhida (medindo, não no olho)

"Sem perder qualidade" precisa de um número. A medida usada foi o **SSIM** (*structural similarity*): compara a imagem comprimida com a original e dá 1,0 para idênticas. Acima de ~0,98 a diferença é praticamente invisível.

O teste: 5 fotos variadas, cada uma comprimida em várias qualidades, medindo tamanho e SSIM com o `ffmpeg`:

```bash
ffmpeg -i comprimida.avif -i original.png -lavfi ssim -f null -
```

| Formato e qualidade | Tamanho médio | SSIM médio |
|---|---|---|
| WebP 75 | 50 KB | 0,972 |
| WebP 80 | 63 KB | 0,978 |
| **WebP 85** | **80 KB** | **0,983** |
| WebP 90 | 112 KB | 0,988 |
| AVIF crf 30 | 25 KB | 0,970 |
| AVIF crf 25 | 33 KB | 0,977 |
| **AVIF crf 20** | **42 KB** | **0,982** |

Leitura da tabela:

- **AVIF crf 20 tem a mesma qualidade que WebP 85 com metade do tamanho.** No AVIF, `crf` menor = mais qualidade.
- Subir o WebP de 85 para 90 aumenta 40% o tamanho para ganhar pouco SSIM: é o ponto em que comprimir menos deixa de valer a pena.
- As miniaturas usam um pouco menos de qualidade (AVIF crf 24, WebP 80), porque em tamanho pequeno os defeitos de compressão não aparecem.

### Velocidade do codificador

O AVIF é lento de codificar. O `libaom` tem o parâmetro `-cpu-used` (0 = mais lento e melhor, 8 = mais rápido):

| `-cpu-used` | Tempo por foto | Tamanho | SSIM |
|---|---|---|---|
| 4 | 0,9 s | 30,0 KB | 0,9860 |
| **6** | **0,3 s** | **30,4 KB** | **0,9857** |
| 8 | 0,3 s | 30,4 KB | 0,9857 |

Com 6, a perda é desprezível e fica 3× mais rápido. Mesmo assim são 1.176 fotos × 6 arquivos, então o script codifica **6 fotos em paralelo** (`ForEach-Object -Parallel`). As 196 skins levam ~6 minutos.

### Outras escolhas que ajudam

- **Redimensionar com `lanczos`**: o melhor filtro de redução do `ffmpeg`, mantém o detalhe da pintura da arma.
- **`yuv420p`**: o formato de cor que todo navegador decodifica. Ele guarda a cor em resolução menor que o brilho, algo que o olho quase não percebe.
- **Um `ffmpeg` por foto, várias saídas**: o comando lê o JPEG uma vez, divide (`split`) e gera todas as versões. Ler e decodificar o JPEG 6 vezes seria desperdício.

---

### A imagem grande em resolução cheia (18/10/2026)

No zoom do site a imagem grande de 1280×720 com crf 20 pixelava. Comparando um recorte ampliado do cabo da Magnum no chão:

| Versão | Tamanho |
|---|---|
| 1280×720, AVIF crf 20 (antes) | 21 KB, borrada no zoom |
| 1600×900 (sem reduzir), AVIF crf 14 | 35 KB, praticamente igual ao print |
| 1600×900, AVIF crf 10 | 45 KB, sem ganho visível sobre o crf 14 |

A imagem grande passou a sair **na resolução do print, sem reduzir, com AVIF crf 14 e WebP 90**. Na média das 1.176 fotos ficou em ~75 KB. O que ainda aparece no zoom mais fechado é a própria textura da skin (no máximo 1024 px), que nenhuma compressão melhora.

## 9.3 O comando do `ffmpeg` por dentro

Para cada foto o script monta um *filter graph* assim (exemplo da foto 1, que tem as três versões):

```text
[0]split=6[s0][s1][s2][s3][s4][s5];
[s0]crop=1600:900:0:0[a0];                                    ← grande, AVIF (resolução do print)
[s1]crop=1600:900:0:0[w0];                                    ← grande, WebP
[s2]crop=1600:900:0:0,scale=320:180:flags=lanczos[a1];        ← miniatura, AVIF
[s3]crop=1600:900:0:0,scale=320:180:flags=lanczos[w1];        ← miniatura, WebP
[s4]crop=900:900:510:0,scale=540:540:flags=lanczos[a2];       ← card, AVIF
[s5]crop=900:900:510:0,scale=540:540:flags=lanczos[w2]        ← card, WebP
```

E cada saída é mapeada para um arquivo com seu codificador:

```text
-map [a0] -c:v libaom-av1 -still-picture 1 -cpu-used 6 -pix_fmt yuv420p -crf 14 1.avif
-map [w0] -c:v libwebp -compression_level 6 -preset picture -quality 90     1.webp
...
```

- `split=6` duplica a imagem decodificada em 6 cópias.
- `crop=L:A:X:Y` recorta (largura, altura, posição). `510` é o X do recorte quadrado com centro em 0,6: `1600 × 0,6 − 900 / 2 = 510`.
- A imagem grande não passa por `scale`: ela sai na resolução do print (`-Width`/`-Height` do `process-shots.ps1` ainda reduzem, se precisar).
- `-still-picture 1` diz ao AVIF que é uma imagem, não um vídeo.
- `-compression_level 6` é o esforço máximo do WebP (mais lento, arquivo menor, mesma qualidade).

---

## 9.4 Folha de revisão

No fim, o script monta uma **folha de revisão** (*contact sheet*): uma imagem grande com uma linha por skin e uma coluna por foto, com o nome da skin. Com ela dá para revisar as 196 skins × 6 fotos de uma vez, procurando algo estranho (uma arma sem skin, um print preto, um bot no meio da cena).

---

## 9.5 Ferramentas de revisão e diagnóstico

Na pasta [`tools/`](../tools) ficam scripts pequenos usados durante o desenvolvimento. Eles não fazem parte do fluxo normal, mas foram essenciais para investigar problemas:

| Script | Uso | Exemplo de quando ajudou |
|---|---|---|
| `sheet.ps1` | Junta vários prints numa folha, com o nome de cada um | Comparar o mesmo tipo de foto para as 14 armas lado a lado |
| `diffimg.ps1` | Gera uma imagem mostrando em branco os pixels que mudaram entre dois prints | Descobrir que o **rosto** e a **sombra** entravam na medição da calibração |
| `crop.ps1` | Recorta a mesma região de vários prints e põe lado a lado | Ver de perto o rosto deformado em dois prints seguidos |
| `soften-materials.js` | Varre os `.vmt` das skins e limita o reflexo do ambiente a 10% e o brilho especular a 10 onde a textura não tem máscara. `dry` só lista, `apply` grava | As cores das 98 skins que saíam apagadas (veja o [diário](10-problemas-e-solucoes.md#as-cores-das-skins-apareciam-apagadas)) |

```powershell
.\tools\sheet.ps1 -Folder 'E:\L4D2-Studio\left4dead2\screenshots\skinshots\test' -Pattern 'check_*.jpg' -Out folha.jpg -Cols 4
.\tools\diffimg.ps1 -A com_arma.jpg -B sem_arma.jpg -Out diferenca.jpg
.\tools\crop.ps1 -Files a.jpg,b.jpg -X 650 -Y 0 -W 450 -H 400 -Out rostos.jpg
node tools\soften-materials.js <pasta materials/models/l4d2br/weapons> <weapon_skins.cfg> dry
```

---

## 9.6 Publicando no site

As fotos do servidor L4D2 Zone ficam no repositório `l4d2-zone-server-assets`, na pasta `assets/skin-shots`, e vão para o Azure Blob Storage pelo pipeline daquele repositório. Dois cuidados:

- **Subir só o que mudou.** O pipeline compara o MD5 de cada arquivo com o `Content-MD5` do blob e envia só os diferentes. Sem isso, cada push reenviaria as 7 mil imagens.
- **Cache longo + versão na URL.** As fotos são servidas com `Cache-Control: max-age=31536000, immutable` (um ano), então o navegador nunca as baixa de novo. Quando as fotos de uma skin forem refeitas, o site muda a versão na URL (`1.avif?v=2`, campo `shots` do `skins.json`), e o navegador trata como um arquivo novo.

---

Próximo: [10. Diário de problemas](10-problemas-e-solucoes.md)
