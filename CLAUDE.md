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

### O laço obrigatório de toda mudança

1. **Implementa.**
2. **Teste de regressão, se a correção nasceu de Play.** Não é opcional e não é "depois".
3. **Bateria verde**, no place que você tocou. Roda no datamodel **Edit**, sem precisar de Play:
   ```lua
   local T = game.ServerScriptService.Tests:Clone(); T.Parent = game.ServerScriptService
   print(require(T).RunAll().summary); T:Destroy()
   ```
4. **`selene .`** — linha de base **0 erros / 0 avisos**, nos dois places. Aviso novo é regressão.
5. **Os dois builds**, sempre os dois: um place quebra pelo que o outro mudou, e o lint não vê.
   ```bash
   rojo build lobby.project.json -o /tmp/l.rbxl
   rojo build match.project.json -o /tmp/m.rbxl
   ```
6. **Contraponto** (API corrente + orientação de performance), como manda a seção acima.
7. **Commit só quando pedido.**

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

## Testes de regressão

Duas baterias, uma por place, irmãs de `Source/` e não filhas — o `LoadModules(Source)` do boot não
as varre, então elas ficam inertes no servidor de produção até alguém pedir `RunAll`.

```
src-match/server/Tests/     # ServerScriptService.Tests
src-lobby/server/Tests/     # ServerScriptService.Tests
```

### Como se escreve um teste de regressão aqui

Ele codifica a **FALHA**, não a funcionalidade — com os números MEDIDOS dentro.

```lua
t:test("gaveta cuja caixa não se chama Root ainda acha o trilho", function()
    -- MEDIDO NO PLACE: em Storage_1 as quatro peças se chamam MeshPart; só em Storage_2/3/4 a
    -- caixa se chama Root. Procurar por nome deixaria as seis gavetas de Storage_1 sem prompt e
    -- sem curso — e o erro é mudo, porque os outros três armários continuam funcionando.
    local model = fakeDrawer({ box = Vector3.new(1.426, 0.981, 3.063), faceAt = 1.549 })
    local rig = StorageConfig.Rig(model)
    t:assertEqual(rig.depth, 3.063, "o trilho é o eixo mais longo da caixa")
    t:assertNear(rig.out.Z, 1, 1e-6, "e aponta para a frente, onde estão frente e puxador")
end)
```

Três exigências: **nome descreve o defeito**, **comentário conta o que aconteceu sem a correção**,
**números vêm da medição real**. Assim o teste vermelho, daqui a seis meses, conta a história
inteira para quem não estava lá — inclusive para mim, sem memória desta sessão.

Ferramentas do `Context`: `assert`, `assertEqual`, `assertNear`, `fail`, `stub`, `stubAll`,
`freshRequire`, `test`, `knownFailure`.

`t:freshRequire` e não `require` cru: o Studio cacheia por instância de ModuleScript pela sessão de
Edit inteira, e a bateria ficaria verde sobre código que não é o do disco.

`t:knownFailure` para bug conhecido e ainda **não** corrigido: documenta o problema em código
executável em vez de num comentário que ninguém lê. Se um dia passar, o runner grita pedindo que
vire `t:test` — senão ele deixa de proteger contra a regressão.

### Escrever o teste NÃO depende de o usuário pedir

`/regressao` é reforço, não mecanismo. O passo 2 do laço é **obrigatório por padrão**: correção
nascida de Play sai com teste no mesmo turno, pedido ou não. Conserto entregue sem teste e sem dizer
por quê é regressão silenciosa aberta — o defeito volta e a bateria continua verde, porque nada o
observa.

Quando não der para testar (precisa de mundo vivo, de física, de rede), **diga isso em voz alta** no
relatório e registre o invariante abaixo. Buraco declarado é dívida; buraco silencioso é armadilha.

`/varredura` é o backstop periódico: audita os invariantes direto no código e lista quais **não têm
teste guardando**. Rode antes de publicar e depois de refactor grande.

### O limite honesto

Teste de unidade não olha o vão entre dois módulos internamente corretos. Contra isso valem teste de
contrato — dois donos da mesma pergunta têm que responder igual — e observação em Play. E o ponto
cego mais caro é ferramenta de diagnóstico sem teste.

## Invariantes

Decisão que atravessa arquivos mora aqui, com **dono único**: comentário no arquivo certo não alcança
quem escreve o arquivo novo. Cada linha é alvo da `/varredura`, e a coluna do teste diz se ela tem
guarda executável ou só disciplina.

| invariante | dono | teste |
|---|---|---|
| `src-lobby` e `src-match` não se importam | os dois `*.project.json` | — |
| `STORE_NAME` idêntico nos dois places | `PlayerData.lua` de cada lado | — |
| `TeleportConfig.MapName` idêntico nos dois places | `TeleportConfig.lua` de cada lado | — |
| sem userdata em `profile.Data` | `PlayerData.lua` | — |
| número que entra no perfil passa por `isSafeNumber` | `PlayerData.lua` | — |
| `TeleportData` chega `Trusted = false` e é checado antes de conceder | `MatchBootstrap.lua` | — |
| prompt do cenário é `Style = Custom`; quem desenha é o cliente | `PromptDisplay.lua` | — |
| `Packages/` fica fora de `Source/` | os dois `Main.server.lua` | — |
| gaveta é de um jogador por vez, e quem escreve o dono é o servidor | `StorageService.lua` | — |
| `Open` da gaveta acompanha o `User`: sem dono, fechada | `StorageService.lua` | — |
| sair da gaveta é gatilho do cliente, mas quem fecha é o servidor | `StorageService.lua` | — |
| a câmera da gaveta fica do lado da boca e acima da borda | `CaseConfig.lua` | `CaseFitSpec` |
| dica de tecla de cena que dura usa `KeyHint.Pin`, não `Show` | `KeyHint.lua` | — |
