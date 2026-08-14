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

## Notas

- Branch principal: `main`
- `.rbxl`/`.rbxm` são **artefato**, nunca fonte — o place publicado é a fonte de GUI/Workspace.
- `servePort` 34874/34875 para não colidir entre si nem com outros projetos Rojo
  servindo em paralelo.
