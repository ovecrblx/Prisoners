---
description: Varredura de regressão — audita os invariantes do CLAUDE.md direto no código, sem depender de teste existir
---

Varredura periódica de regressão. Alvo (opcional, senão varre tudo): $ARGUMENTS

**Por que esta varredura existe, e por que ela NÃO é a bateria.** A bateria só pega defeito que
alguém já transformou em teste. O buraco que sobra é o pior: decisão de desenho tomada, corrigida, e
**nunca codificada** — ninguém escreveu o teste, então a reintrodução é silenciosa e o verde
continua verde. Esta varredura ataca por outro lado: lê os invariantes declarados em `CLAUDE.md` e
procura violações **direto no código**, sem depender de teste nenhum.

## Execute

**1. Leia `CLAUDE.md`, seção "Invariantes"**, e extraia a lista. Ela mudou desde a última varredura —
não trabalhe de memória.

**2. Para cada invariante, faça uma busca CONCRETA de violação.** Não leia "com atenção": busque por
padrão. O que isso significa aqui:

| invariante | o que procurar |
|---|---|
| places sem import cruzado | `src-match` citado dentro de `src-lobby/`, e o contrário |
| constante duplicada em sincronia | `STORE_NAME` nos dois `PlayerData.lua`, `MapName` nos dois `TeleportConfig.lua` — comparar o literal |
| sem userdata em `profile.Data` | `Vector3`, `Color3`, `CFrame`, `Instance`, `Enum` em qualquer atribuição a `.Data` |
| número seguro entra no perfil | escrita em `.Data` que não passou por `isSafeNumber` |
| API corrente | `ReserveServer(` cru, `TeleportToPrivateServer`, `ProfileService`, `Humanoid:LoadAnimation` |
| prompt é desenhado pelo cliente | `ProximityPrompt` novo sem `Style = Enum.ProximityPromptStyle.Custom` |
| payload do cliente é suspeito | uso de `TeleportData` sem checar `Trusted` |
| `Packages/` não é serviço | ModuleScript com `Init`/`Start` dentro de `server/Packages/` |
| nome de instância é do place | `FindFirstChild`/`WaitForChild` com nome que não bate a caixa do que está publicado — confirmar pelo MCP do Studio, não de memória |

A varredura roda **na thread principal**, um invariante por vez. Não abra subagente: neste projeto o
trabalho é feito à vista, e o custo de ler o repo inteiro em série cabe.

**3. Refute cada achado antes de reportar.** Uso legítimo se parece com violação. Achado que não
sobrevive à refutação não entra no relatório. Falso positivo repetido ensina a ignorar a varredura, e
aí ela morre.

**4. O ACHADO MAIS IMPORTANTE: invariante sem teste.** Para cada invariante do `CLAUDE.md`, procure
em `src-match/server/Tests/` e `src-lobby/server/Tests/` o teste que o guarda. Liste os que **não têm
nenhum**. Essa lista é a superfície por onde a próxima regressão silenciosa vai entrar — vale mais
que qualquer violação encontrada, porque violação você conserta e some, buraco fica.

**5. Rode as duas baterias, o `selene .` e os dois `rojo build`**, para o relatório fechar com o
estado real, não com o presumido.

**6. Relate nesta ordem:**
   1. invariantes **sem teste** (o buraco);
   2. violações confirmadas, com `arquivo:linha`;
   3. baterias, lint e builds;
   4. o que você NÃO conseguiu verificar, e por quê.

Não corrija nada sem perguntar — varredura relata; consertar é decisão de quem lê. Exceção: violação
que seja claramente erro de digitação, sem escolha de desenho envolvida.
