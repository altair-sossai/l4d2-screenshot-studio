# 12. Glossário

| Termo | Significado |
|---|---|
| **Attachment** | Ponto com nome no esqueleto de um modelo, usado como gancho. `weapon_bone` é o ponto da mão dos sobreviventes |
| **Bonemerge** (`EF_BONEMERGE`) | Efeito que faz uma entidade filha copiar os ossos de mesmo nome da entidade pai. Encaixa a arma na mão |
| **Calibração** | O processo do `calibrate.ps1` que descobre, por arma, giro do sobrevivente, direção da câmera e zoom |
| **Cena** | Uma configuração de foto no `skin_shots.cfg` (`hand`, `ground`, `third`, `third2`) |
| **Cliente** | A parte do jogo que desenha a tela. No estúdio, roda no mesmo processo que o servidor |
| **Contact sheet** (folha de revisão) | Imagem com miniaturas de várias fotos, para revisar tudo de uma vez |
| **Cutscene de abertura** | A cena controlada pelo mapa no início de The Parish. Enquanto ela roda, a visão fica inclinada e os braços somem |
| **Cvar** | Variável de configuração do console (`hidehud`, `r_drawviewmodel`...) |
| **Diretor** (*director*) | A IA do L4D2 que cria hordas e eventos. Parado com `director_stop` |
| **Entidade** | Qualquer coisa que existe no mapa: jogador, arma, prop, luz, câmera |
| **Família** (`m_nSkin`) | Conjunto de materiais alternativo de um modelo. Trocar a família troca a pintura |
| **FOV** | Campo de visão em graus. Menor = mais zoom. No jogador: `m_iFOV` |
| **`gpu_level`** | Nível de detalhe de shader no `video.txt`. Em 3, os braços em primeira pessoa não aparecem nesta instalação |
| **Host** | O jogador humano no servidor local. No estúdio, ele é a câmera |
| **Listen server** | Servidor rodando dentro do próprio jogo de quem joga (o contrário de servidor dedicado) |
| **Manequim** | O sobrevivente da terceira pessoa: um `prop_dynamic_override` com o modelo do sobrevivente e animação congelada |
| **Maior região conectada** | Técnica da calibração: dos pixels que mudaram, ficar só com o maior grupo contíguo (a arma), ignorando rosto e plantas |
| **Melee** | Arma de corpo a corpo (katana, machado, frigideira...). Todas são a classe `weapon_melee`, diferenciadas por `melee_script_name` |
| **Metamod:Source** | Camada que permite carregar plugins nativos no servidor do jogo. O SourceMod roda em cima dele |
| **Modelo combinado** | Um modelo por arma com uma família para cada skin (`models/l4d2br/weapons/<arma>/v.mdl` e `w.mdl`) |
| **Netprop** | Propriedade de entidade que o servidor envia ao cliente. Mudar uma netprop muda o que o cliente desenha |
| **Noclip** | Modo de movimento que atravessa paredes e não cai. Usado na câmera da terceira pessoa |
| **`OnPostThinkPost`** | Gancho do SDKHooks chamado depois de cada "pensamento" do jogador, todo frame |
| **Pitch / Yaw / Roll** | Ângulos: para cima/baixo (positivo olha para baixo), para os lados, inclinação lateral |
| **Precache** | Registrar um modelo no jogo antes de usar. Devolve o índice usado em `m_nModelIndex` |
| **`prop_dynamic_override`** | Entidade de objeto de cena que aceita qualquer modelo e pode tocar animações |
| **Referência de entidade** | Identificador que deixa de valer se a entidade for removida (`EntIndexToEntRef`) |
| **Settle** | Tempo de espera depois de montar uma cena e antes do print, para o jogo estabilizar |
| **SourceMod** | Plataforma de plugins para servidores Source. Plugins em SourcePawn (`.sp` → `.smx`) |
| **SourcePawn** | A linguagem dos plugins do SourceMod |
| **`spcomp`** | O compilador de SourcePawn |
| **Viewmodel** | Modelo da arma em primeira pessoa, só visto pelo dono |
| **VPK** | Pacote de arquivos do jogo. Arquivos soltos na pasta têm prioridade sobre os de dentro dos VPKs |
| **Worldmodel** | Modelo da arma no mundo: na mão de outros personagens ou no chão |
| **`-insecure`** | Opção que abre o jogo sem VAC. Usada no estúdio por ter SourceMod |

---

Próximo: [13. O código do plugin](13-codigo-do-plugin.md)
