# 10. Diário de problemas

Tudo o que deu errado durante a construção do estúdio, na ordem em que apareceu, com o sintoma, a investigação, a causa e a solução. É o documento mais útil para aprender: quase nenhum problema tinha a causa que parecia ter.

Cada problema segue o formato:

> **Sintoma** → **Investigação** → **Causa** → **Solução** → **Lição**

---

## Comunicação e ambiente

### O script de envio não funcionava com `pwsh -File`

- **Sintoma:** `send.ps1 sm_shots_show x hand` dava erro de parâmetro.
- **Causa:** o script usava um parâmetro `Mandatory` com `ValueFromRemainingArguments`. Com `pwsh -File`, os argumentos chegam de um jeito que esse tipo de parâmetro não aceita bem.
- **Solução:** usar a variável automática `$args` e juntar tudo: `$command = ($args -join ' ').Trim()`.
- **Lição:** para scripts que só repassam texto, `$args` é o mais simples e robusto.

### O HUD e a lanterna apareciam nas fotos

- **Sintoma:** vida, munição, retratos dos sobreviventes e o círculo da lanterna nos prints.
- **Investigação:** o plugin mandava `ClientCommand(host, "hidehud 4")`. No console, o comando funcionava; vindo do plugin, não.
- **Causa:** o jogo **bloqueia cvars vindas do servidor** por `ClientCommand`. Só alguns comandos passam. Além disso, `cl_drawhud 0` não esconde o painel dos sobreviventes.
- **Solução:** alterar as cvars direto, com `FindConVar(nome).SetString(valor)` (servidor e cliente estão no mesmo processo), e usar `hidehud 4`. A lanterna é desligada todo frame tirando o efeito `EF_DIMLIGHT` do jogador.
- **Lição:** num listen server o plugin enxerga as cvars do cliente diretamente.

### Depois de recarregar o plugin, nada era aplicado no jogador

- **Sintoma:** depois de `sm plugins reload`, a skin não aparecia na mão.
- **Causa:** o gancho `PostThinkPost` é colocado em `OnClientPutInServer`, que só roda quando o jogador entra. Recarregando o plugin com o jogador já dentro, ninguém era enganchado.
- **Solução:** no `OnPluginStart`, enganchar todos os jogadores já conectados.

### Todos os prints saíam iguais

- **Sintoma:** prints de skins diferentes idênticos.
- **Causa:** o **console estava aberto**. Em jogo local, console aberto pausa o jogo: o mundo não atualizava entre um print e outro. E com a janela sem foco, o jogo "dorme" entre frames.
- **Solução:** fechar o console (`hideconsole`) e `engine_no_focus_sleep 0`.

---

## Primeira pessoa e chão

### Cinco armas melee não apareciam na mão

- **Sintoma:** `give katana` (e mais quatro) não fazia nada em The Parish.
- **Investigação:** as que funcionavam eram exatamente as listadas em `meleeweapons` no arquivo de missão da campanha.
- **Causa:** o L4D2 só permite `give` de armas melee que a campanha libera.
- **Tentativas que falharam:** plugin `l4d2_melee_spawn_control` (assinatura de memória desatualizada no Windows); arquivo de missão solto em `missions/` e depois em `update/missions/` (ignorados).
- **Solução:** criar a entidade direto: `weapon_melee` com `melee_script_name`, e `EquipPlayerWeapon` (ver [documento 6](06-mao-e-chao.md#63-armas-melee-que-o-mapa-não-permite)).
- **Lição:** checagens de regra de jogo costumam estar no comando, não na entidade. Criar a entidade direto pula a regra.

### Kit médico no chão aparecendo nas fotos

- **Sintoma:** um kit médico e outros itens do mapa no meio da foto do chão.
- **Solução:** `RemoveLooseItems`: remove toda entidade `weapon_*`/`upgrade_*` sem dono.

---

## Terceira pessoa

### O bot não obedecia a rotação

- **Sintoma:** o bot sobrevivente olhava para cima ou para outro lado, mesmo teleportado com o ângulo certo e com `sb_stop 1`.
- **Causa:** a IA e a animação do jogador sobrescrevem os ângulos a cada frame.
- **Solução:** trocar o bot por um **manequim** (`prop_dynamic_override` com o modelo do sobrevivente e animação congelada). Ver [documento 7](07-terceira-pessoa.md).

### A arma não ficava na mão do manequim

- **Sintoma:** a arma aparecia nos pés do sobrevivente, ou na mão mas torta.
- **Solução:** `SetParent` + `SetParentAttachment weapon_bone` + posição relativa zero + `EF_BONEMERGE | EF_BONEMERGE_FASTCULL | EF_PARENT_ANIMATES`.

### Manequins duplicados e um "rosto torto" a mais

- **Sintoma:** às vezes aparecia um segundo sobrevivente sobreposto, com o rosto distorcido.
- **Causa:** sobras de cenas anteriores. Quando o plugin era recarregado, as referências guardadas se perdiam e o `RemoveProp` não sabia que aqueles props existiam.
- **Solução:** todo prop criado recebe o nome `skin_shots_prop`, e o `RemoveProp` remove **tudo** com esse nome, além das referências. `OnPluginEnd` também chama `RemoveProp`.
- **Lição:** marque tudo o que você cria, para poder limpar mesmo depois de perder o rastro.

### O rosto do sobrevivente deformava

- **Sintoma:** boca aberta e torta em alguns prints, mesmo com o corpo congelado.
- **Investigação:** dois prints seguidos da mesma cena, sem mexer em nada, eram idênticos; mas entre um print com arma e outro sem arma, o rosto mudava. Recortando o rosto dos dois (`tools/crop.ps1`), as expressões eram diferentes e ambas estranhas.
- **Causas prováveis:** animação facial independente da do corpo, mais uma config de terceiros na cópia que altera os olhos (`r_eyesize 0`, `r_eyemove 0`) e arquivos de expressão soltos.
- **Solução adotada:** girar o sobrevivente para o rosto ficar de costas ou de perfil e enquadrar a arma. O rosto sai do foco da foto.

### O corpo ficava na frente da arma

- **Sintoma:** em escopetas, a coronha passava por trás do tronco; em alguns ângulos o corpo cobria metade da arma.
- **Solução:** escolher o giro do sobrevivente **por arma**, testando vários e ficando com o que mostra mais pixels da arma (ver [documento 8](08-enquadramento-automatico.md#83-escolhendo-o-giro-do-sobrevivente)).

---

## Enquadramento automático

### O centro calculado pela geometria errava para as melee

- **Sintoma:** com a câmera apontada para o "centro da arma" calculado pelo osso da mão e pela caixa do modelo, armas de fogo ficavam boas, mas frigideira e katana saíam fora do quadro.
- **Causa:** o bonemerge encaixa a malha de um jeito que o servidor não reproduz exatamente; para melee o erro era grande.
- **Solução:** abandonar a geometria e **medir na imagem** (diferença de prints com e sem a arma).
- **Lição:** quando dá para medir o resultado, medir costuma ser mais confiável que prever.

### A sombra da arma entrava na medida

- **Sintoma:** a câmera mirava entre a arma e a parede e se afastava demais.
- **Causa:** ao esconder a arma, a **sombra dela na parede** também sumia, e a diferença incluía a sombra.
- **Solução:** `DisableShadow` no prop da arma durante a calibração.

### O rosto entrava na medida

- **Sintoma:** o retângulo da arma esticava até a cabeça.
- **Causa:** a expressão facial mudava entre o print com e sem arma (problema anterior).
- **Solução:** usar só a **maior região conectada** de pixels que mudaram.

### Plantas ao vento faziam a calibração divergir

- **Sintoma:** numa cena com zoom aberto, o FOV calculado foi para 103 graus.
- **Causa:** vasos de plantas numa sacada balançavam e apareciam como diferença.
- **Solução:** a mesma da maior região conectada, mais um limite de FOV entre 4 e 60.

### O zoom calculado era metade do pedido

- **Sintoma:** pedindo que a arma ocupasse 70% da largura, ela ocupava ~45%.
- **Causa:** a conversão entre FOV 4:3 e a tela 16:9 não batia exatamente com o jogo.
- **Solução:** calcular o zoom pela **proporção** entre tamanho medido e desejado (um erro de escala se cancela) e repetir 4 vezes.

### O close de 95% quebrava a medição

- **Sintoma:** com a arma ocupando quase todo o quadro, a calibração se perdia.
- **Causa:** com a arma encostando nas bordas, qualquer erro a corta e a medição seguinte fica sem referência.
- **Solução:** close em 60% e plano aberto em 30%.

---

## Os braços sumiram da primeira pessoa

O problema mais demorado do projeto. Vale ler com calma, porque mostra como isolar uma causa quando nada óbvio funciona.

- **Sintoma:** na foto `hand`, a arma aparecia flutuando, **sem mão e sem braço**. Os primeiros prints, horas antes, tinham braços.
- **Investigação, em ordem:**

| # | Hipótese | Teste | Resultado |
|---|---|---|---|
| 1 | É a skin (modelo combinado sem braços) | Arma original do jogo, sem skin (`give rifle`) | Sem braço também → não é a skin |
| 2 | É o HUD escondido | `hidehud 0`, `cl_drawhud 1` | Sem braço |
| 3 | São os addons da Workshop copiados junto | Tirar `addons/workshop` da cópia e reiniciar | Sem braço (mas era bom tirar mesmo) |
| 4 | É a cutscene de abertura do mapa | Notar visão inclinada e barco no cais; esperar a cutscene acabar | Visão normal, **ainda sem braço** |
| 5 | É o jogador num estado estranho | `sm_shots_where` mostrando time, vida, personagem, modelo, viewmodels | Tudo normal: Nick, vivo, time 2 |
| 6 | São os arquivos de missão de teste | Eles foram criados logo antes do sumiço. Remover e recarregar | Sem braço |
| 7 | É o plugin mexendo todo frame | `sm_shots_unhook` e `give smg` novo | Sem braço → não é o plugin |
| 8 | São cvars de viewmodel | `cl_viewmodelfovsurvivor`, `cl_viewmodelsclonedasworld`, com e sem trocar de arma | Sem braço |
| 9 | Onde o jogo define o braço? | Procurar `v_arms_gambler` nos VPKs | Está nos scripts de arma, bloco `CharacterViewmodelAddon` → é desenhado pelo cliente |
| 10 | O que difere do jogo de verdade? | Comparar a árvore de arquivos e as configs da cópia com a do jogo real | Iguais, exceto addons e `video.txt` (configurações gráficas) |
| 11 | É a configuração gráfica | Usar o `video.txt` do jogo real e reiniciar | **Braço apareceu** |
| 12 | Qual configuração? | Voltar tudo ao alto, menos `gpu_level` 3 → 0 | **Braço apareceu** |
| 13 | Dá para manter quase tudo? | `gpu_level 2` | **Braço apareceu** |

- **Causa:** com o **nível de shader mais alto** (`setting.gpu_level 3` no `video.txt`), os braços em primeira pessoa não são desenhados nesta instalação. A configuração tinha sido alterada com o jogo aberto, e só passou a valer por completo quando o jogo foi reiniciado. Por isso os primeiros prints tinham braço e os seguintes não.
- **Solução:** `setting.gpu_level 2` no `video.txt` da cópia.
- **Lições:**
  - **Mude uma coisa de cada vez** e confira o resultado. A tabela acima só chegou na causa porque cada teste isolava uma hipótese.
  - Quando "funcionava antes", procure **o que mudou** entre o antes e o depois, inclusive coisas que só valem depois de reiniciar.
  - **Compare com uma referência que funciona** (aqui, o jogo de verdade). Comparar listas de arquivos e conteúdo de configs eliminou quase tudo de uma vez.
  - Teste o **caso mais simples possível** (arma original, sem plugin) antes de desconfiar do próprio código.

---

## Ferramentas

### `forward` não compila em SourcePawn

`forward` é palavra reservada. Erro: `expected token: ";", but found "forward"`. Renomeie a variável.

### Uma função PowerShell que não era chamada

Uma função chamada `Measure` nunca rodava: `measure` é **apelido** de `Measure-Object`, e apelidos têm prioridade sobre funções. Renomeada para `Find-Weapon`.

### Listas passadas com `pwsh -File`

`-Weapons a,b` chega como um texto só. O script separa por vírgula.

### `Add-Type` com `System.Drawing` no PowerShell 7

Compilar C# que usa `Bitmap` exige referenciar os assemblies certos do .NET moderno (`System.Drawing.Common`, `System.Private.Windows.GdiPlus`...). O script busca os assemblies já carregados por `Add-Type -AssemblyName System.Drawing` e passa os caminhos deles.

---

Próximo: [11. Passo a passo completo](11-passo-a-passo.md)
