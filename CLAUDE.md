# Prisoners

Projeto Roblox com Rojo. Dois places: **Lobby** e **Match**.

## Regras de código

### Documentação oficial primeiro

Consultar a doc oficial (`create.roblox.com/docs`) antes de usar qualquer API. Não escrever de
memória — o risco é função inventada, recurso descontinuado, ou prática que compromete a
arquitetura. As três passam no lint e no build; só aparecem em runtime ou em escala.

Vale também para biblioteca de terceiros: verificar o estado atual antes de vendorizar.

**Toda entrega fecha com o contraponto.** Não basta a API existir. Dizer se é a corrente ou a
substituída (`ReserveServer` -> `ReserveServerAsync`, `LoadAnimation` no `Humanoid` -> no
`Animator`, ProfileService -> ProfileStore), e comparar o que o código faz com a orientação de
performance da própria Roblox, citando a linha que sustenta. Divergiu, justificar; sem justificativa,
mudar o código.

Página de referência sem descrição é comum — aconteceu com `SpringConstraint.Coils`,
`Constraint.Visible` e pai `nil` em `Instance`. Aí dizer que não está documentado e medir no
runtime, nunca preencher de memória.

**A doc atrasa em mudança recente de engine.** Já aconteceu neste projeto: a página do `Humanoid`
diz que `AddAccessory` conecta o Handle "using a Weld", e em R15 o runtime cria
`AccessoryRigidConstraint`. Quando doc e comportamento observado divergem, quem manda é o runtime.
Havendo MCP do Studio conectado, confirmar lá em vez de assumir.

### Comentários enxutos

Cabeçalho curto dizendo **o que** o módulo é, mais rótulo de unidade ou contrato em bloco de
configuração. Nada no corpo da lógica.

Não comentar: justificativa de decisão, narrativa do que está acontecendo, histórico de bug antigo
ou do que foi trocado. Isso vive na mensagem de commit e no README.

Escrever assim de primeira, não escrever denso e enxugar depois. Alvo: comentário perto de 3% das
linhas, não 25%.

### Antes de dar por pronto

```bash
selene .                              # 0 errors obrigatório
rojo build lobby.project.json -o /tmp/l.rbxl
rojo build match.project.json -o /tmp/m.rbxl
```

## Arquitetura

### Dois places independentes

Não existe `default.project.json` — todo comando exige o project file explícito.

```bash
rojo serve lobby.project.json   # porta 34874
rojo serve match.project.json   # porta 34875
```

`src-lobby/` e `src-match/` são árvores separadas, **sem import cruzado**. Constante que precisa
bater nos dois lados (`STORE_NAME`, `MapName`) é duplicada por necessidade — nada garante a
igualdade além de disciplina. Divergiu, quebra em silêncio.

### Contrato dos módulos

Todo ModuleScript em `Source/` pode exportar `Init` e/ou `Start`:

- `Init` roda em série, em todos, antes de qualquer `Start`.
- `Start` roda em `task.spawn`, então pode render sem travar o boot.

Falha é isolada por `pcall` e derruba `ServerScriptService.BootHealthy`.

`Packages/` fica **fora** de `Source/` — o loader varre `Source/` recursivamente, e biblioteca não
é serviço.

### Perfil compartilhado entre os places

Mesmo store e mesma key (`Player_<UserId>`): é o mesmo registro, um servidor de cada vez. Não é
cópia sincronizada. Gravar `Shifts`/`Dima` no Match já é o handoff de volta.

`Reconcile` preenche chave faltante mas **nunca troca o tipo** de uma existente. Campo exclusivo do
Match leva prefixo `Match`; campo compartilhado só existe com mesmo nome e mesmo tipo dos dois
lados. Errar isso estoura em produção, só no perfil de quem já passou pelo outro place.

Sem userdata em `Data` (`Vector3`, `Color3`, `CFrame`, `Instance`): não serializa, e um só desses
faz todo save futuro daquele perfil falhar.

### Handoff Lobby -> Match

Payload vai pelo MemoryStore, chaveado pelo `privateServerId` que `ReserveServerAsync` devolve —
não pelo accessCode. `TeleportData` passa pelo cliente e é forjável; existe só como fallback, e
chega marcado `Trusted = false`.

APIs correntes: `ReserveServerAsync`, `TeleportAsync` + `TeleportOptions`, `GetHashMap`.
Descontinuadas, não usar: `ReserveServer`, `TeleportToPrivateServer`.

### Código vendorizado

`src-*/server/Packages/` é upstream intocado, e está no `exclude` do `selene.toml`. Ao atualizar,
trocar o arquivo inteiro — nunca editar in loco.

## O place não está no repo

`.rbxl` é artefato, nunca fonte. GUI, pads e templates vivem no place publicado:

- `StarterGui.MainGui.Frame_Party.Frame_Play.{Play_Button, Exit_Button}`
- `workspace.Tp.Party_N.Model.{gate, spawn, billboardPart/...}` — nomes **minúsculos**
- `ReplicatedStorage.Client.GUI.BillboardAccessory`

Nomes de instância são case-sensitive e não têm cobertura de teste. Havendo MCP do Studio
conectado, **inspecionar a hierarquia real** em vez de assumir nome ou caminho.

## Convenções

- Branch principal: `main`
- Commits em Conventional Commits, assunto em inglês; corpo em português explica o **porquê**
- Toolchain pinada em versão exata no `aftman.toml` — o job `pin-check` do CI reprova faixa
