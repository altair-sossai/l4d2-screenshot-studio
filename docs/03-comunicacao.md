# 3. Conversando com o jogo

O jogo é uma janela fechada: não tem API, não aceita chamadas de outro programa. Mesmo assim os scripts precisam mandar comandos para o plugin ("monte a cena X", "tire o print") e saber o que aconteceu. Este documento explica a solução adotada e por que outras não serviram.

---

## 3.1 A fila de comandos

A comunicação é feita por **dois arquivos de texto** dentro da cópia do jogo:

| Arquivo | Quem escreve | Quem lê | Para quê |
|---|---|---|---|
| `addons/sourcemod/data/skin_shots_queue.txt` | Scripts (`send.ps1`) | Plugin | Comandos a executar |
| `addons/sourcemod/data/skin_shots.log` | Plugin | Scripts e você | O que aconteceu |

### Como o script envia (`send.ps1`)

```powershell
$command = ($args -join ' ').Trim()
$queue = Join-Path $studio 'left4dead2\addons\sourcemod\data\skin_shots_queue.txt'
Add-Content -Path $queue -Value $command -Encoding ascii
```

Ele só **acrescenta uma linha** no fim do arquivo. Pode-se mandar vários comandos seguidos; eles se acumulam.

### Como o plugin lê (`Timer_Queue`)

No `OnPluginStart` o plugin cria um timer que roda **a cada 0,5 segundo**:

```sourcepawn
CreateTimer(0.5, Timer_Queue, _, TIMER_REPEAT);
```

A cada execução:

1. Se o arquivo não existe, não faz nada.
2. Lê **todas** as linhas não vazias para uma lista.
3. **Apaga o arquivo** (assim o mesmo comando nunca é executado duas vezes).
4. Para cada linha:
   - se começa com `client `, executa o resto **como o jogador** (`ClientCommand`);
   - senão, executa como **comando de servidor** (`ServerCommand`).
5. Escreve cada comando no log (`queue: ...`).

Isso significa que qualquer comando de servidor funciona pela fila, não só os do plugin: `map c5m1_waterfront`, `quit`, `condump`, `sm plugins reload l4d2_skin_shots`...

### Por que ler-e-apagar é seguro o bastante

Existe uma janela pequena em que o script pode acrescentar uma linha entre o plugin ler e apagar o arquivo, e essa linha se perderia. Na prática os scripts esperam o resultado de um comando antes de mandar o próximo, então isso não acontece. Para uma ferramenta local isso é suficiente; não vale a complexidade de um protocolo com confirmação.

---

## 3.2 O log

A função `Log` do plugin escreve no arquivo e também no console do servidor:

```sourcepawn
void Log(const char[] format, any ...)
{
    char message[512];
    VFormat(message, sizeof(message), format, 2);

    char time[16];
    FormatTime(time, sizeof(time), "%H:%M:%S");

    File file = OpenFile(LOG_FILE, "a");
    ...
    file.WriteLine("%s %s", time, message);
    ...
    PrintToServer("[skin_shots] %s", message);
}
```

Os scripts **esperam por linhas específicas do log** para saber que algo terminou, por exemplo `snap saved ...` depois de um print, `done` no fim de uma sequência, `loaded 7 scenes ...` depois que um mapa carregou.

Exemplo de log de uma sequência:

```text
15:34:45 run all: 1176 shots
15:34:47 1/1176 screenshots/skinshots/hand/abyss-uzi.jpg
15:34:49 2/1176 screenshots/skinshots/hand/akatsuki-uzi.jpg
...
hh:mm:ss done
```

---

## 3.3 Tirando o print

Quem tira o print é o **cliente**, com o comando de console `jpeg`. O plugin manda o jogador executar:

```sourcepawn
ClientCommand(host, "jpeg");
```

O jogo salva em `left4dead2/screenshots/` com um nome automático (`c5m1_waterfront0001.jpg`, `0002`...). O plugin então:

1. lista a pasta `screenshots`;
2. pega o `.jpg` com o **maior nome** (o mais novo, porque os números crescem);
3. confere se o arquivo já tem tamanho maior que zero (o jogo pode ainda estar gravando);
4. **move** o arquivo para o destino final, por exemplo `screenshots/skinshots/third/abyss-uzi.jpg`.

Se o arquivo ainda não apareceu, tenta de novo a cada 0,4 s, até 20 vezes (`MAX_SHOT_RETRIES`). Se não aparecer, escreve `missing screenshot for ...` no log e segue para a próxima.

A qualidade do JPEG é controlada pela cvar `jpeg_quality` (o plugin coloca 95).

---

## 3.4 Alternativas que não serviram

### Console do jogo

Digitar no console funciona, mas **com o console aberto o jogo pausa** em single player/listen server. Os prints saíam todos iguais, porque o mundo estava congelado. Além disso não é automatizável sem simular teclado.

### `ClientCommand` para mudar cvars do cliente

A primeira versão mudava cvars do cliente (`hidehud`, `crosshair`, etc.) mandando o jogador executar `ClientCommand(host, "hidehud 4")`. O jogo **bloqueia** a maioria das cvars vindas do servidor por esse caminho; só alguns comandos passam (`jpeg` passa). A solução foi usar `FindConVar(nome).SetString(valor)`: como servidor e cliente estão no mesmo processo, o plugin enxerga as cvars do cliente e consegue alterá-las diretamente. Veja `SetLocalCvar` no plugin.

### RCON

RCON exigiria configurar senha, porta e um cliente RCON. Para um jogo local, um arquivo de texto é mais simples e não abre nenhuma porta de rede.

---

## 3.5 Esperando sem travar

Os scripts precisam **esperar** o jogo: o mapa carregar, a cena assentar, o print ser gravado. Em vez de esperar um tempo fixo e torcer, o padrão usado é **esperar uma condição**:

```bash
# espera o mapa carregar (o plugin escreve isso no OnMapStart)
until tail -n +$n skin_shots.log | grep -q "loaded 7 scenes"; do sleep 2; done
```

```powershell
# calibrate.ps1: espera o print existir
for ($i = 0; $i -lt 40 -and -not (Test-Path $file); $i++) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path $file)) { throw "screenshot $name not saved" }
```

O único tempo fixo que sobra é o **tempo de assentamento** da cena (`settle`, 1,6 s no `skin_shots.cfg`): depois de trocar a arma ou o sobrevivente, o jogo precisa de alguns frames para carregar texturas e estabilizar a animação antes do print.

---

Próximo: [4. O plugin, parte por parte](04-plugin.md)
