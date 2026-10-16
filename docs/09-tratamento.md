# 9. Tratamento das imagens

Os prints saem do jogo em 1920×1080, JPEG com qualidade 95, em:

```text
left4dead2/screenshots/skinshots/
├── hand/<skin>.jpg
├── ground/<skin>.jpg
├── third/<skin>.jpg
├── third2/<skin>.jpg
└── test/            ← prints avulsos (sm_shots_snap) e da calibração
```

O [`scripts/process-shots.ps1`](../scripts/process-shots.ps1) transforma isso no formato final.

---

## 9.1 O que o script faz

Para cada skin e cada cena:

1. **Recorte 16:9 central.** Calcula o maior retângulo 16:9 que cabe na imagem e centraliza. Como o jogo já roda em 1920×1080 (16:9), na prática não corta nada; o recorte existe para o caso de rodar o estúdio em outra resolução.
2. **Redimensiona** para 1280×720, com interpolação bicúbica de alta qualidade (`HighQualityBicubic`).
3. **Comprime** em JPEG com qualidade 82. Uma foto de 1920×1080 a 95 tem ~500 KB; a de 1280×720 a 82 fica em ~150 KB, sem diferença visível num site.
4. **Salva** em `<saída>/<skin>/<cena>.jpg`, uma pasta por skin:
   ```text
   skin-shots/
   ├── abyss-uzi/
   │   ├── hand.jpg
   │   ├── ground.jpg
   │   ├── third.jpg
   │   └── third2.jpg
   └── ...
   ```

No fim, monta uma **folha de revisão** (*contact sheet*): uma imagem grande com uma linha por skin e uma coluna por cena, em miniatura, com o nome da skin. Com ela dá para revisar as 196 skins × 4 fotos de uma vez, procurando algo estranho (uma arma sem skin, um print preto, um bot no meio da cena).

---

## 9.2 Por que `System.Drawing`

O PowerShell 7 roda sobre .NET, e o `System.Drawing` está disponível no Windows sem instalar nada. Para recortar, redimensionar e salvar JPEG com qualidade escolhida, basta:

```powershell
Add-Type -AssemblyName System.Drawing

$codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object MimeType -eq 'image/jpeg'
$parameters = New-Object System.Drawing.Imaging.EncoderParameters 1
$parameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 82L

$bitmap = New-Object System.Drawing.Bitmap 1280, 720
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.InterpolationMode = 'HighQualityBicubic'
$graphics.DrawImage($image, $destino, $origemRecortada, 'Pixel')
$bitmap.Save($arquivo, $codec, $parameters)
```

Sempre faça `Dispose()` das imagens e dos `Graphics`: o `System.Drawing` usa recursos do Windows (GDI+) que não são liberados sozinhos rapidamente, e com centenas de imagens a memória acaba.

---

## 9.3 Ferramentas de revisão e diagnóstico

Na pasta [`tools/`](../tools) ficam scripts pequenos usados durante o desenvolvimento. Eles não fazem parte do fluxo normal, mas foram essenciais para investigar problemas:

| Script | Uso | Exemplo de quando ajudou |
|---|---|---|
| `sheet.ps1` | Junta vários prints numa folha, com o nome de cada um | Comparar o mesmo tipo de foto para as 14 armas lado a lado |
| `diffimg.ps1` | Gera uma imagem mostrando em branco os pixels que mudaram entre dois prints | Descobrir que o **rosto** e a **sombra** entravam na medição da calibração |
| `crop.ps1` | Recorta a mesma região de vários prints e põe lado a lado | Ver de perto o rosto deformado em dois prints seguidos |

```powershell
.\tools\sheet.ps1 -Pattern 'check_*.jpg' -Out folha.jpg -Cols 4
.\tools\diffimg.ps1 -A com_arma.jpg -B sem_arma.jpg -Out diferenca.jpg
.\tools\crop.ps1 -Files a.jpg,b.jpg -X 650 -Y 0 -W 450 -H 400 -Out rostos.jpg
```

---

Próximo: [10. Diário de problemas](10-problemas-e-solucoes.md)
