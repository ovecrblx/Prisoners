---
description: Fecha uma correção como regressão — teste com os números medidos, bateria, lint e os dois builds
---

Fecha a última correção como **regressão permanente**. O argumento (se houver) nomeia o defeito:
$ARGUMENTS

Execute nesta ordem, sem pular:

1. **Nomeie o defeito em uma frase**, do jeito que ele apareceu na TELA, não no código.
   Exemplo bom: "gaveta abre e fecha instantânea, sem curso". Exemplo ruim: "DescendantAdded
   chamava setState com animate=false". Se não souber como apareceu, pergunte antes de escrever
   o teste.

2. **Escreva o teste na spec do módulo dono da regra**, e ponha o nome dela em `SPEC_NAMES`.
   - place errado é teste que não roda: Match vai em `src-match/server/Tests/`, Lobby em
     `src-lobby/server/Tests/`. São árvores independentes, sem import cruzado.
   - o **nome** descreve o defeito, não a funcionalidade;
   - um comentário conta **o que acontecia sem a correção**, e o custo em jogo;
   - os **números vêm da medição real** (Play, console, sonda MCP) — nada inventado. Sem números
     medidos, diga isso em vez de fabricar valores plausíveis.
   Modelo em `CLAUDE.md`, seção "Como se escreve um teste de regressão aqui".

3. **Prove que o teste PEGA o defeito.** Reverta mentalmente a correção e aponte por qual asserção
   ele falharia. Teste que passaria com e sem o conserto não é regressão — é enfeite. Se não
   conseguir apontar a asserção, o teste está errado; refaça.

4. **Rode a bateria do place que você tocou** (datamodel Edit, não precisa de Play):
   ```lua
   local T = game.ServerScriptService.Tests:Clone(); T.Parent = game.ServerScriptService
   print(require(T).RunAll().summary); T:Destroy()
   ```
   Falha em massa logo após editar módulo = suspeite do **cache de `require` do Edit** antes do
   código. O runner já usa `requireFresh` nas specs e oferece `t:freshRequire` para os módulos de
   produção; se você usou `require` cru numa spec, é por ali. Nunca "conserte" código com base numa
   bateria que você não provou estar fresca.

5. **Rode `selene .`** — linha de base **0 erros / 0 avisos**, nos dois places. Aviso novo é
   regressão, não estilo.

6. **Rode os dois builds.** Um place pode quebrar pelo que o outro mudou em arquivo compartilhado
   de nome, e o lint não vê isso:
   ```bash
   rojo build lobby.project.json -o /tmp/l.rbxl
   rojo build match.project.json -o /tmp/m.rbxl
   ```

7. **Se a decisão atravessa arquivos, registre em `CLAUDE.md`**, na seção "Invariantes", com o dono
   único da regra. Comentário no arquivo certo não alcança quem escreve o arquivo novo.

8. **Relate**: defeito, arquivo:linha do teste, asserção que o pega, resultado da bateria, do lint e
   dos dois builds. Se algum passo não pôde ser cumprido, diga qual e por quê — não declare fechado.

Não commite a menos que seja pedido.
