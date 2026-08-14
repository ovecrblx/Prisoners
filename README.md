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

```bash
rojo serve              # porta 34874 — conecte pelo plugin Rojo no Studio
rojo build -o build.rbxl
selene .                # lint estático de Luau
```

## Estrutura

```
.
├── .github/workflows/ci.yml   # lint (selene) + secret scan (gitleaks) + pin-check
├── aftman.toml                # rojo 7.7.0-rc.1 · selene 0.27.1
├── default.project.json       # mapa filesystem -> DataModel
├── selene.toml                # std roblox; global_usage = deny
└── src/
    ├── client/                # -> StarterPlayer.StarterPlayerScripts
    │   ├── ClientLoader.client.lua
    │   └── Source/            # controllers (ModuleScript com Init/Start)
    ├── server/                # -> ServerScriptService
    │   ├── Main.server.lua
    │   └── Source/            # services (ModuleScript com Init/Start)
    └── shared/                # -> ReplicatedStorage.Shared
```

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
- `servePort` é 34874 para não colidir com outros projetos Rojo servindo em paralelo.
