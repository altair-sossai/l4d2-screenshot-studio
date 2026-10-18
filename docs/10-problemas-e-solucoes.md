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

### Um print de outra cena no lugar certo

- **Sintoma:** a foto de primeira pessoa do machado `red-black-axe` saiu com uma escopeta no chão.
- **Investigação:** o print era de uma sequência anterior, interrompida. O plugin pega "o `.jpg` mais novo da pasta `screenshots`"; um print que sobrou de antes estava lá e foi pego no lugar do novo.
- **Solução:** `ClearScreenshots()`: antes de cada `jpeg`, apaga qualquer `.jpg` solto na pasta `screenshots` (as fotos prontas ficam em `screenshots/skinshots`, que não é tocada).
- **Lição:** "o arquivo mais novo" só é confiável se você garantir que a pasta começa vazia.

### Um galão vermelho no cais

- **Sintoma:** depois de reabrir o jogo, um galão de gasolina vermelho apareceu no cais, no canto da foto de primeira pessoa.
- **Causa:** o mapa às vezes cria itens de cenário que dá para carregar (galão, botijão, caixa de fogos) como `prop_physics`, não como `weapon_*`, então o `RemoveLooseItems` não os via.
- **Solução:** `IsCarryable` remove também os `prop_physics` cujo modelo é de galão, botijão, cilindro de oxigênio ou caixa de fogos.

### Braços esticados no taco de críquete

- **Sintoma:** nas fotos refeitas, o taco de críquete aparecia com os dois braços do personagem esticados em "barbatanas" pontudas. Nas fotos da sequência principal, o mesmo taco estava normal.
- **Investigação, em ordem:** com o taco original do jogo (sem skin, sem o plugin mexendo) o defeito continuava, então não era a skin. Recarregar o mapa e reabrir o jogo não mudavam nada. Ao comparar com as fotos boas, a arma aparecia **maior** nelas: o campo de visão da arma em primeira pessoa (`cl_viewmodelfovsurvivor`) era diferente.
- **Causa:** a cópia do jogo veio com uma config de terceiros que define `cl_viewmodelfovsurvivor 120` e tem teclas para alternar esse valor. Cada sessão do estúdio começava com um valor diferente, e com valores altos a animação do taco mostra partes dos braços que normalmente ficam fora da tela.
- **Solução:** o `PrepareWorld` fixa `cl_viewmodelfovsurvivor 50`, o mesmo das fotos boas. As fotos não dependem mais da config de quem joga.
- **Lição:** tudo que afeta a imagem precisa ser definido pelo próprio estúdio. Se uma configuração vem "de fora" (do usuário, da cópia do jogo), cedo ou tarde ela muda.

### A primeira foto de uma sequência saía com a câmera virada

- **Sintoma:** na primeira skin de algumas sequências, a câmera estava girada uns 40 graus, mostrando o prédio em vez do rio.
- **Causa:** o `PrepareWorld` tira bots e itens e muda várias cvars no mesmo instante; a primeira cena era montada antes de o jogo terminar de aplicar tudo.
- **Solução:** a primeira foto espera 3 segundos depois do `PrepareWorld` (antes era 1).

### Recarregar o mapa sumia com os braços

- **Sintoma:** depois do comando `map` (recarregar o mapa com o jogo aberto), as fotos de primeira pessoa saíam sem braço nenhum, mesmo depois da cena de abertura.
- **Solução:** para tirar fotos de primeira pessoa, fechar e abrir o jogo de novo (`quit` e `run-studio.ps1`) em vez de recarregar o mapa. Numa sessão nova, depois da cena de abertura, os braços aparecem.

### A câmera saía torta na primeira pessoa de algumas armas brancas

- **Sintoma:** na sequência completa, as fotos de mão do taco de críquete e do taco de golfe saíam com o horizonte inclinado, às vezes sem a arma na tela. Com `sm_shots_show` ou numa sequência curta, saíam retas.
- **Causa:** a animação de sacar essas armas mexe e gira a câmera. Na sequência, cada arma entra logo depois de outra arma branca (o taco de críquete depois do taco de beisebol, o de golfe depois da guitarra), e com 1,6 s de espera o print pegava a animação no meio. Reproduzido duas vezes seguidas com a mesma ordem.
- **Solução:** `settle` por cena no `skin_shots.cfg`; a `hand` espera 4 s, e as outras cenas continuam com 1,6 s.

### Os braços sumiram depois de mudar a resolução pelo menu

- **Sintoma:** depois de trocar a resolução do estúdio pelo menu do jogo, as fotos de mão saíam sem braço.
- **Causa:** ao salvar a resolução, o jogo regravou o `cfg\video.txt` com `"setting.gpu_level" "3"` (detalhe de shader máximo), o mesmo problema da seção [Os braços sumiram da primeira pessoa](#os-braços-sumiram-da-primeira-pessoa).
- **Solução:** com o jogo fechado, voltar para `"2"` no `video.txt`. O `install-studio.ps1` já faz isso, mas só quando roda.

### A escopeta saía fora do quadro no chão

- **Sintoma:** com câmera e zoom fixos, a escopeta (comprida) encostava na borda e ficava torta no quadro, enquanto a Magnum ficava pequena no meio.
- **Causa:** um único enquadramento para armas de tamanhos muito diferentes, e a origem do modelo (empunhadura) longe do centro da arma.
- **Solução:** passar as cenas de chão pela mesma **calibração automática** da terceira pessoa (centro e zoom por arma).

### As melee apontavam para a câmera e as fotos de chão saíam iguais

- **Sintoma:** com as rotações das armas de fogo, a katana e a guitarra ficavam "em pé" no quadro, e as fotos de cano para a esquerda e para a direita eram quase idênticas.
- **Causa:** os modelos de melee têm o comprimento no eixo z; os de armas de fogo, no eixo x. A mesma rotação deixa cada tipo apontando para um lado diferente.
- **Solução:** uma rotação própria para melee em cada cena de chão (`melee_target_angles`), 90 graus a mais no yaw.

### Partes das melee afundavam no chão

- **Sintoma:** a guitarra aparecia com o braço "entrando" no chão; outras melee também ficavam parcialmente enterradas.
- **Causa:** o plugin colocava a **origem** do modelo na altura do chão. A origem fica na empunhadura; com a arma deitada ou inclinada, partes ficam abaixo dela.
- **Solução:** `LowestPoint` gira os 8 cantos da caixa do modelo, acha o mais baixo e levanta a arma exatamente essa distância.
- **Lição:** "colocar no chão" é sobre o ponto mais baixo do objeto, não sobre a origem dele.

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

## As cores das skins apareciam apagadas

- **Sintoma:** várias skins (a Magnum Exodus, a Asiimov Chrome, a Darkdread e muitas outras) apareciam nas fotos quase prateadas ou esbranquiçadas, bem diferentes da imagem da Workshop.
- **Investigação:**
  1. A textura da Exodus no servidor era idêntica byte a byte à do addon original da Workshop. Não era erro na conversão.
  2. Decodificando a textura (DXT5) com um script, o canal alfa estava em 100% na imagem inteira.
  3. No material, `$basealphaenvmapmask 1` usa esse alfa como máscara do **reflexo do ambiente** (`$envmap`). Alfa 100% em tudo = a arma inteira é um espelho do céu do mapa.
  4. Uma varredura em todas as 196 skins achou o mesmo padrão em 99 delas, em duas formas: reflexo do ambiente sem nenhuma máscara (comum nas escopetas e nas MAC-10, que herdaram o material da arma cromada original) e **brilho especular** (`$phongboost` de 45 a 200) em texturas sem máscara de brilho.
- **Causa:** os autores copiam o material da arma original do jogo, que foi feito para uma textura com máscaras cuidadosas no canal alfa. A textura nova vem sem essas máscaras, e o reflexo e o brilho que eram sutis passam a cobrir a arma toda e "lavam" a pintura.
- **Solução:** [`tools/soften-materials.js`](../tools/soften-materials.js) aplica uma regra em todos os materiais com textura própria:
  - reflexo do ambiente no máximo 10% (`$envmaptint "[0.1 0.1 0.1]"`, ou o tint do autor reduzido na mesma proporção quando era maior que 20%);
  - brilho especular no máximo 10 onde a textura não tem máscara que o segure (brilho efetivo = `$phongboost` × alfa médio ≥ 20).
  - Ficam de fora as skins holográficas (o reflexo colorido é o efeito delas) e a Puro, em que o brilho branco é o visual que o autor mostra na Workshop.
- **Como o valor foi escolhido:** 20% e 10% foram testados lado a lado com a imagem da Workshop; 10% ficou mais fiel. A mudança é só no `.vmt` (algumas dezenas de bytes): as texturas, que são o peso do download, não mudam.
- **Lição:** quando uma imagem "não bate" com a referência, confira primeiro se o arquivo é o mesmo, depois **como** ele é desenhado. Aqui a textura estava certa; o problema era a receita de desenho (o material).

## Sequências sobrepostas e fotos vazias

- **Sintoma:** ao refazer as fotos de 99 skins, várias fotos saíram faltando ("missing screenshot") e outras mostravam só a parede, sem o sobrevivente.
- **Causa, em duas partes:**
  1. O comando com as 99 skins passou de 512 caracteres, o tamanho da linha que o plugin lê da fila. Ele foi cortado em pedaços e nada rodou.
  2. Ao mandar em lotes, o script esperava o `done` lendo o log **a partir da última linha antiga**, que já era o `done` do lote anterior. Os lotes foram disparados um por cima do outro, e cada `sm_shots_run` novo deixava os timers do anterior rodando. Várias cadeias de timers fotografavam ao mesmo tempo, apagavam o print uma da outra e tiravam fotos antes de a cena estar montada.
- **Solução:** o `sm_shots_run` agora recusa uma sequência nova enquanto outra está rodando (`busy` no log). Os lotes têm no máximo 12 skins e a espera lê o log a partir da **primeira linha nova** (`wc -l` + 1).
- **Lição:** conferir só a data dos arquivos não basta; as fotos vazias tinham data nova. Olhar as imagens (folha de revisão) pegou o que a checagem automática deixou passar.

---

## Ferramentas

### `forward` não compila em SourcePawn

`forward` é palavra reservada. Erro: `expected token: ";", but found "forward"`. Renomeie a variável.

### Uma função PowerShell que não era chamada

Uma função chamada `Measure` nunca rodava: `measure` é **apelido** de `Measure-Object`, e apelidos têm prioridade sobre funções. Renomeada para `Find-Weapon`.

### A MP5 ficou sem calibração

- **Sintoma:** todas as armas saíam bem enquadradas, menos a MP5, torta e fora do centro.
- **Investigação:** o `skin_shots.cfg` não tinha nenhuma linha de `framing` para `weapon_smg_mp5`. A calibração nem tinha tentado essa arma.
- **Causa:** a expressão regular que lê o `weapon_skins.cfg` procurava nomes de arma com `weapon_[a-z_]+`: só letras e `_`. O nome `weapon_smg_mp5` tem um **dígito**, então a MP5 nunca entrava na lista.
- **Solução:** `weapon_[a-z0-9_]+`.
- **Lição:** quando um item "some" de um processo em lote, verifique primeiro se ele chegou a entrar na lista. Expressões regulares escritas olhando só para alguns exemplos costumam deixar casos de fora.

### Duas skins de MP5 saíam idênticas no chão

- **Sintoma:** `navy-blue-mp5` e `olive-drab-mp5` apareciam iguais (e iguais à MP5 original) no chão e na terceira pessoa, mas diferentes na mão.
- **Investigação:** a skin aplicada em outra MP5 (`rarity-mp5`) aparecia no chão normalmente, então o plugin estava certo. Abrindo os materiais da skin: o `mp5_1.vmt` (primeira pessoa) aponta para a textura da skin, mas o `w_smg_mp5.vmt` (modelo do mundo) aponta para a textura **original** do jogo.
- **Causa:** o autor dessas 8 skins só pintou a arma em primeira pessoa. No jogo, os outros jogadores também veem a MP5 original.
- **Solução:** nenhuma no estúdio: a foto mostra a verdade. Vale avisar na loja que essas skins só mudam a visão em primeira pessoa.
- **Lição:** antes de corrigir o "bug", confirme se o comportamento não é do próprio conteúdo. Uma comparação com um caso que funciona (outra skin da mesma arma) separou rápido as duas hipóteses.

### Listas passadas com `pwsh -File`

`-Weapons a,b` chega como um texto só. O script separa por vírgula.

### `Add-Type` com `System.Drawing` no PowerShell 7

Compilar C# que usa `Bitmap` exige referenciar os assemblies certos do .NET moderno (`System.Drawing.Common`, `System.Private.Windows.GdiPlus`...). O script busca os assemblies já carregados por `Add-Type -AssemblyName System.Drawing` e passa os caminhos deles.

---

Próximo: [11. Passo a passo completo](11-passo-a-passo.md)
