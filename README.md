# Prisoners

Projeto Roblox com Rojo. Toolchain gerenciada por [Aftman](https://github.com/LPGhatguy/aftman),
com versões **fixas** (`x.y.z`, nunca faixa) — o job `pin-check` do CI reprova qualquer faixa.

## Setup

```bash
git clone https://github.com/ovecrblx/Prisoners.git
cd Prisoners
aftman install          # instala rojo + selene nas versões do aftman.toml
```

## Rodar

São **dois places**, cada um com seu project file e sua árvore de fontes. Não existe
`default.project.json` — todo comando exige o project file explícito.

```bash
rojo serve lobby.project.json   # porta 34874
rojo serve match.project.json   # porta 34875
```

Os dois podem servir ao mesmo tempo (portas distintas): abra uma instância do Studio
por place e conecte cada uma na porta correspondente pelo plugin Rojo.

```bash
rojo build lobby.project.json -o lobby.rbxl
rojo build match.project.json -o match.rbxl
selene .                        # lint estático de Luau — varre as duas árvores
```

## Estrutura

```
.
├── .github/workflows/ci.yml   # lint (selene) + secret scan (gitleaks) + pin-check
├── aftman.toml                # rojo 7.7.0-rc.1 · selene 0.27.1
├── lobby.project.json         # place Lobby -> porta 34874
├── match.project.json         # place Match -> porta 34875
├── selene.toml                # std roblox; global_usage = deny
├── src-lobby/
│   ├── client/                # -> StarterPlayer.StarterPlayerScripts
│   │   ├── ClientLoader.client.lua
│   │   └── Source/            # controllers (ModuleScript com Init/Start)
│   ├── server/                # -> ServerScriptService
│   │   ├── Main.server.lua
│   │   └── Source/            # services (ModuleScript com Init/Start)
│   └── shared/                # -> ReplicatedStorage.Shared
└── src-match/                 # mesma forma, place independente
    ├── client/
    ├── server/
    └── shared/
```

Cada place é um DataModel próprio, então cada um carrega o **seu** boot — os loaders
estão duplicados de propósito, não são código compartilhado. `src-lobby/shared` e
`src-match/shared` também são independentes: o que os dois places precisam enxergar
igual tem que ser copiado ou movido para um pacote, nunca assumido como comum.

## Contrato dos módulos

Todo ModuleScript dentro de `Source/` pode exportar `Init` e/ou `Start`:

- **`Init`** roda em TODOS os módulos antes de qualquer `Start` — dependência entre
  serviços encontra o outro já inicializado.
- **`Start`** roda em `task.spawn`, então pode render (`task.wait`, laço) sem travar o boot.

Falha em qualquer um é isolada por `pcall` e derruba o atributo
`ServerScriptService.BootHealthy` — o boot segue, mas fica observável que quebrou.

## Teleporte de áreas (Lobby -> Match)

Pads no lobby juntam uma party e a mandam para um servidor reservado do place Match.

```
src-lobby/shared/TeleportConfig.lua              # PlaceId, pads, lotação, tempos, retries
src-lobby/server/Source/Teleport/
  ├── AreaTeleportService.lua                    # pads, party, contagem, orquestração
  └── MatchHandoff.lua                           # ReserveServer + MemoryStore + TeleportToPrivateServer

src-match/shared/TeleportConfig.lua              # espelho: MapName tem que bater
src-match/server/Source/Teleport/
  └── MatchBootstrap.lua                         # lê o payload por PrivateServerId
```

### Fluxo

1. Jogador pisa no pad -> entra na party (só com o pad em `waiting`).
2. Líder manda `Play` -> contagem de 30s (cai para 10s com todos prontos).
3. Durante a contagem, `ReserveServer` roda em paralelo — tira a latência do caminho crítico.
4. Timer zera -> payload vai para o MemoryStore, **chaveado pelo `privateServerId`**.
5. `TeleportToPrivateServer` leva o snapshot congelado da party.
6. No Match, `MatchBootstrap` lê `game.PrivateServerId` e busca a mesma chave.

### Por que o MemoryStore no meio

`TeleportData` passa pelo cliente, então é forjável: dá para se teleportar para o Match com um
payload inventado. O MemoryStore fecha isso — quem escreve é o servidor do lobby, sob uma chave
que o jogador não escolhe nem conhece. O `TeleportData` continua como fallback, mas chega
marcado `Trusted = false`; **cheque essa flag** antes de conceder qualquer coisa que valha
exploit.

### O que o place precisa ter

O `.rbxl` não é versionado, então os pads são montados no Studio:

```
workspace/
└── Tp/                  # TeleportConfig.PadsFolder
    ├── Party_1/         # PadPrefix .. i, até PadCount
    │   └── Gate         # BasePart de toque (GatePartName)
    ├── Party_2/
    └── Party_3/
```

Faltando a pasta, o serviço avisa e desliga em vez de derrubar o boot. Sem uma `Gate`, cai na
primeira `BasePart` do Model.

### Onde plugar a lógica do Prisoners

`buildPayload` em [AreaTeleportService.lua](src-lobby/server/Source/Teleport/AreaTeleportService.lua)
é o ponto de extensão: o que a partida precisa saber de cada jogador vira campo do dicionário.
Só JSON — `Color3`/`Vector3` cru faz o `SetAsync` falhar e derruba a partida no fallback.

## Persistência (ProfileStore)

```
src-lobby/server/Packages/ProfileStore.luau      # vendorizado, não editar
src-lobby/server/Source/Data/PlayerData.lua      # dono do schema
src-match/server/Packages/ProfileStore.luau      # mesma cópia
src-match/server/Source/Data/PlayerData.lua      # chaves próprias + campos compartilhados
```

`Packages/` fica **fora** de `Source/`, então o loader do boot não o varre — biblioteca não é
serviço. Vira `ServerScriptService.Packages.ProfileStore`.

[ProfileStore](https://madstudioroblox.github.io/ProfileStore/), não ProfileService: são módulos
diferentes, não versões do mesmo. O ProfileService segue funcionando mas está sem suporte; o
ProfileStore resolve conflito de session lock por MessagingService, que é exatamente o caminho
crítico aqui — cada teleporte Lobby -> Match é um handoff de lock.

### Um perfil, dois places

Mesmo store, mesma key `Player_<UserId>` nos dois lados: é **o mesmo registro**, não uma cópia
sincronizada. Por isso o Ouro ganho na partida já está lá quando o jogador volta ao lobby — e por
isso não existe TeleportData de volta (que o cliente forjaria).

O store é `ALT_Data_Prisoners` no Studio e `Data_Prisoners` em produção: teste nunca escreve em
dado de jogador real.

### A regra que mais dói

`Reconcile` **preenche** chave faltante, mas **nunca troca o tipo** de uma que já existe.

Se o Lobby gravar `Level` como tabela e o Match tratar `Level` como número, o perfil chega com
tabela e a aritmética estoura — em produção, só no perfil de quem já passou pelo lobby, nunca no
seu teste com perfil novo. Convenção para evitar:

- Campo só do Match ganha prefixo `Match` (`MatchLevel`, `MatchXP`).
- Campo compartilhado só existe com **mesmo nome e mesmo tipo** nos dois lados (`Gold`, `Wins`).
- `STORE_NAME` tem que ser idêntico nos dois arquivos. São árvores independentes: nada garante
  isso além de disciplina.

### Outras armadilhas já tratadas no código

- **NaN/infinito** em `Data` faz *todo* save futuro daquele perfil falhar. `isSafeNumber` barra
  na entrada — recuperar perfil envenenado não tem volta fácil.
- **Userdata** (`Vector3`, `Color3`, `Instance`) não serializa. Serialize antes (`Color3:ToHex()`).
- **`Flush`** grava na hora em vez de esperar o auto-save de 300s. Use em compra de DevProduct e
  no fim da partida.
- **`OnSessionEnd`** dá kick: outro servidor assumiu o perfil, e seguir jogando aqui gravaria em
  dados que já não salvam.

## Notas

- Branch principal: `main`
- `.rbxl`/`.rbxm` são **artefato**, nunca fonte — o place publicado é a fonte de GUI/Workspace.
- `servePort` 34874/34875 para não colidir entre si nem com outros projetos Rojo
  servindo em paralelo.
