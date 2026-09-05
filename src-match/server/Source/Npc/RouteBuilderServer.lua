--!strict
-- RouteBuilderServer (servidor / Npc) — despachante da ferramenta in-game de autoria de rotas:
-- recebe as ops do cliente, valida tudo, mantém o grafo de trabalho, publica pro runtime e
-- persiste por slots (RouteStorage). O cliente é controle remoto: nada dele entra sem validação.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
local RouteData = require(Shared:WaitForChild("Npc"):WaitForChild("RouteData"))

local Source = ServerScriptService:WaitForChild("Source")
local Remotes = require(Source:WaitForChild("Util"):WaitForChild("Remotes"))
local RouteStorage = require(Source:WaitForChild("Npc"):WaitForChild("RouteStorage"))

local RouteBuilderServer = {}
RouteBuilderServer.Pure = {}

-- Chave da retenção que este módulo põe em NpcService; ligar e soltar usam a MESMA string.
local SUSPEND_KEY = "RouteBuilder"

-- Níveis de desfazer; snapshot inteiro do grafo por edição.
local UNDO_DEPTH = 20

local workingGraph: RouteData.Graph = {}
local undoStack: { RouteData.Graph } = {}

local opWindow: { [Player]: { count: number, windowStart: number } } = {}
local lastSaveAt: { [Player]: number } = {}

-- Conjunto, não booleano: a retenção só cai quando o ÚLTIMO autor fecha.
local buildersOpen: { [Player]: boolean } = {}

-- =========================================================== DEPENDÊNCIAS OPCIONAIS (gameplay)

-- Módulo irmão que pode não existir neste place: ausência degrada em silêncio, nunca estoura.
local moduleCache: { [string]: any } = {}
local moduleTried: { [string]: boolean } = {}

local function optionalModule(folderName: string, moduleName: string): any
	local key = folderName .. "/" .. moduleName
	if moduleTried[key] then
		return moduleCache[key]
	end
	moduleTried[key] = true
	local folder = Source:FindFirstChild(folderName)
	local mod = folder and folder:FindFirstChild(moduleName)
	if mod and mod:IsA("ModuleScript") then
		local ok, result = pcall(require, mod)
		if ok then
			moduleCache[key] = result
		end
	end
	return moduleCache[key]
end

local function getNpcService(): any
	return optionalModule("Npc", "NpcService")
end

local function getRouteRuntime(): any
	return optionalModule("Npc", "RouteRuntime")
end

local function getMatchManager(): any
	return optionalModule("Services", "MatchManagerService")
end

-- Um sinal só governa as duas retenções: NPC e relógio da partida saem do MESMO conjunto.
local function refreshSuspendHold()
	local held = next(buildersOpen) ~= nil
	local npc = getNpcService()
	if npc and type(npc.SetSuspendHold) == "function" then
		pcall(npc.SetSuspendHold, SUSPEND_KEY, held)
	end
	local match = getMatchManager()
	if match and type(match.SetDayHold) == "function" then
		pcall(match.SetDayHold, SUSPEND_KEY, held)
	end
end

local function setBuilderOpen(player: Player, open: boolean)
	if open then
		buildersOpen[player] = true
	else
		buildersOpen[player] = nil
	end
	refreshSuspendHold()
end

local function isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return NpcConfig.BUILDER_ALLOWLIST[player.UserId] == true
end

local function withinRate(player: Player): boolean
	local now = os.clock()
	local window = opWindow[player]
	if not window or now - window.windowStart >= 1 then
		opWindow[player] = { count = 1, windowStart = now }
		return true
	end
	window.count += 1
	return window.count <= NpcConfig.BUILDER_MAX_OPS_PER_SECOND
end

-- ==================================================================================== VISUAIS

local visualsEvent: RemoteEvent? = nil

-- Geração do desenho: o cliente ignora payload de geração menor que a última desenhada.
local visualsVersion = 0

function RouteBuilderServer.Pure.VisualPayload(
	graph: RouteData.Graph,
	orphans: { [string]: boolean },
	isAerial: (string) -> boolean
): { { [string]: any } }
	local entries = {}
	for _, node in pairs(graph) do
		table.insert(entries, {
			id = node.id,
			position = node.position,
			routeType = node.routeType,
			links = table.clone(node.links),
			senseRadius = node.senseRadius,
			order = node.order,
			aerial = isAerial(node.id) == true,
			orphan = orphans[node.id] == true,
		})
	end
	return entries
end

-- Sem RouteRuntime a sonda de altura não existe e todo nó sai classificado como superfície.
local function aerialProbe(): (string) -> boolean
	local runtime = getRouteRuntime()
	if runtime and type(runtime.IsAerial) == "function" then
		local probe = runtime.IsAerial
		return function(id: string): boolean
			local ok, result = pcall(probe, id)
			return ok and result == true
		end
	end
	return function(_id: string): boolean
		return false
	end
end

local function visualPayload(): { { [string]: any } }
	return RouteBuilderServer.Pure.VisualPayload(workingGraph, RouteData.OrphanNodes(workingGraph), aerialProbe())
end

-- Custo proporcional a quem olha, e o dado da rede completa só sai pra quem passa em isAuthorized.
local function pushVisuals()
	visualsVersion += 1
	local event = visualsEvent
	if not event then
		return
	end
	local payload: { { [string]: any } }? = nil
	for _, player in ipairs(Players:GetPlayers()) do
		if isAuthorized(player) then
			if payload == nil then
				payload = visualPayload()
			end
			event:FireClient(player, { version = visualsVersion, nodes = payload })
		end
	end
end

-- ==================================================================================== MUTAÇÕES
-- Nó é IMUTÁVEL: RouteRuntime guarda a mesma tabela publicada, então toda edição clona antes de escrever.

local function snapshot()
	local copy: RouteData.Graph = {}
	for id, node in pairs(workingGraph) do
		local cloned = table.clone(node)
		cloned.links = table.clone(node.links)
		copy[id] = cloned
	end
	table.insert(undoStack, copy)
	if #undoStack > UNDO_DEPTH then
		table.remove(undoStack, 1)
	end
end

-- Op que snapshota e desiste tem que largar o nível: senão o primeiro Ctrl-Z não faz nada.
local function dropSnapshot()
	table.remove(undoStack)
end

-- Contrato: publish() SEMPRE antes de pushVisuals() — SetGraph recalcula a classe superfície/aéreo que o payload lê.
local function publish()
	local runtime = getRouteRuntime()
	if runtime and type(runtime.SetGraph) == "function" then
		pcall(runtime.SetGraph, workingGraph)
	end
end

-- ================================================================== PLACAR AO VIVO E AUTOSAVE

-- Quem está com a JANELA aberta. Distinto de `buildersOpen`: soltar o NPC não fecha o placar.
local statsWatchers: { [Player]: boolean } = {}
local statsEvent: RemoteEvent? = nil

local function pushStats(reason: string?)
	local event = statsEvent
	if not event or next(statsWatchers) == nil then
		return
	end
	local stats = RouteData.Stats(workingGraph)
	local orphans = 0
	for _ in pairs(RouteData.OrphanNodes(workingGraph)) do
		orphans += 1
	end

	local mainMinX, mainMaxX = math.huge, -math.huge
	local mainMinZ, mainMaxZ = math.huge, -math.huge
	for _, node in pairs(workingGraph) do
		if node.routeType == RouteData.RouteType.Main then
			mainMinX, mainMaxX = math.min(mainMinX, node.position.X), math.max(mainMaxX, node.position.X)
			mainMinZ, mainMaxZ = math.min(mainMinZ, node.position.Z), math.max(mainMaxZ, node.position.Z)
		end
	end
	local hasMain = mainMinX < math.huge
	local payload = {
		total = stats.total,
		components = stats.components,
		largest = stats.largest,
		largestType = stats.largestType,
		byType = stats.byType,
		orphans = orphans,
		maxTotal = NpcConfig.MAX_NODES_PER_SLOT,
		maxComponents = NpcConfig.MAX_ROUTES_PER_SLOT,
		maxLargest = NpcConfig.MAX_NODES_PER_ROUTE,
		mainSpanX = if hasMain then mainMaxX - mainMinX else 0,
		mainSpanZ = if hasMain then mainMaxZ - mainMinZ else 0,
		mapSpanX = NpcConfig.MAP_BOUNDS.size.X,
		mapSpanZ = NpcConfig.MAP_BOUNDS.size.Z,
		reason = reason,
	}
	for player in pairs(statsWatchers) do
		event:FireClient(player, payload)
	end
end

local autosaveDirty = false
local autosaveBusy = false
local autosaveLoop: thread? = nil

-- YIELDA (DataStore): só de dentro de thread própria, nunca do despachante de remote.
local function autosaveNow()
	if autosaveBusy or not autosaveDirty then
		return
	end
	autosaveBusy = true
	autosaveDirty = false
	local ok, err = RouteStorage.SaveAuto(workingGraph)
	autosaveBusy = false
	if not ok then
		-- Continua SUJO: falha não pode consumir a marca de "há coisa nova pra gravar".
		autosaveDirty = true
		warn(string.format("[RouteBuilder] autosave falhou (%s); tentará de novo.", tostring(err)))
	end
end

local function startAutosaveLoop()
	if autosaveLoop then
		return
	end
	autosaveLoop = task.spawn(function()
		while next(statsWatchers) ~= nil do
			task.wait(NpcConfig.BUILDER_AUTOSAVE_INTERVAL)
			autosaveNow()
		end
		autosaveLoop = nil
	end)
end

-- Instala um grafo do armazém (slot ou autosave); o snapshot faz carregar por engano ser um Ctrl-Z.
local function adoptGraph(graph: RouteData.Graph, dropped: number): { [string]: any }
	snapshot()
	workingGraph = graph
	publish()
	pushVisuals()
	pushStats()
	local count = 0
	for _ in pairs(workingGraph) do
		count += 1
	end
	return { ok = true, nodes = count, dropped = dropped }
end

local function nextOrderFor(routeType: string): number
	local highest = 0
	for _, node in pairs(workingGraph) do
		if node.routeType == routeType and node.order > highest then
			highest = node.order
		end
	end
	return highest + 1
end

local function totalNodes(): number
	local count = 0
	for _ in pairs(workingGraph) do
		count += 1
	end
	return count
end

local function applyAdd(payload: any): (boolean, string?)
	if typeof(payload.position) ~= "Vector3" or not RouteData.IsValidType(payload.routeType) then
		return false, "payload de Add malformado"
	end
	if totalNodes() >= NpcConfig.MAX_NODES_PER_SLOT then
		return false, string.format("teto de %d nós no slot atingido", NpcConfig.MAX_NODES_PER_SLOT)
	end
	local node: RouteData.Node = {
		id = HttpService:GenerateGUID(false),
		position = payload.position,
		routeType = payload.routeType,
		order = nextOrderFor(payload.routeType),
		waitTime = if type(payload.waitTime) == "number" then math.clamp(payload.waitTime, 0, 60) else 0,
		lookDirection = if typeof(payload.lookDirection) == "Vector3" then payload.lookDirection else nil,
		links = {},
		roomTag = if type(payload.roomTag) == "string" and #payload.roomTag <= 64 then payload.roomTag else nil,
	}
	local ok, reason = RouteData.ValidateNode(node, NpcConfig.MAP_BOUNDS)
	if not ok then
		return false, reason
	end
	snapshot()
	workingGraph[node.id] = node
	return true, nil
end

-- TRILHA: fileira ligada por UM gesto. Lote e não N Adds: um rate-limit, um snapshot e um push pro gesto inteiro.
local function applyAddTrail(payload: any): (boolean, string?)
	if type(payload.positions) ~= "table" or not RouteData.IsValidType(payload.routeType) then
		return false, "payload de AddTrail malformado"
	end
	local positions = payload.positions :: { any }
	if #positions == 0 then
		return false, "trilha vazia"
	end

	-- `fromId` opcional: a origem já é nó do grafo, não entra em `positions`, e pode ser de outro tipo — é a aresta que prende uma rede de classe à malha Main.
	local anchorId: string? = nil
	if payload.fromId ~= nil then
		local candidate = type(payload.fromId) == "string" and workingGraph[payload.fromId]
		if not candidate then
			return false, "nó de origem inexistente"
		end
		anchorId = (candidate :: RouteData.Node).id
	end

	local room = NpcConfig.MAX_NODES_PER_SLOT - totalNodes()
	if room <= 0 then
		return false, string.format("teto de %d nós no slot atingido", NpcConfig.MAX_NODES_PER_SLOT)
	end

	snapshot()

	local created: { RouteData.Node } = {}
	local dropped = 0
	for _, position in ipairs(positions) do
		if #created >= math.min(room, NpcConfig.BUILDER_MAX_TRAIL_NODES) then
			break
		end
		if typeof(position) ~= "Vector3" then
			dropped += 1
		else
			local node: RouteData.Node = {
				id = HttpService:GenerateGUID(false),
				position = position,
				routeType = payload.routeType,
				order = nextOrderFor(payload.routeType),
				waitTime = 0,
				lookDirection = nil,
				links = {},
				roomTag = nil,
			}
			local ok = RouteData.ValidateNode(node, NpcConfig.MAP_BOUNDS)
			if ok then
				workingGraph[node.id] = node
				table.insert(created, node)
			else
				dropped += 1
			end
		end
	end

	if #created == 0 then
		dropSnapshot()
		return false, "nenhuma posição da trilha passou na validação"
	end

	RouteData.LinkChain(created)

	if anchorId then
		local anchor = workingGraph[anchorId :: string] :: RouteData.Node
		local cloned = table.clone(anchor)
		cloned.links = table.clone(anchor.links)
		workingGraph[cloned.id] = cloned
		RouteData.LinkChain({ cloned, created[1] })
	end

	if dropped > 0 then
		warn(string.format(
			"[RouteBuilder] trilha: %d nó(s) criado(s), %d descartado(s) (fora dos bounds ou payload inválido).",
			#created,
			dropped
		))
	end
	return true, nil
end

-- MOVER com corrente: `chain` é a QUANTIDADE de pontos que acompanham; a queda mora em RouteData.ChainFactors, que o cliente usa na prévia.
local function applyMove(payload: any): (boolean, string?)
	local node = type(payload.id) == "string" and workingGraph[payload.id]
	if not node then
		return false, "nó inexistente"
	end
	if typeof(payload.position) ~= "Vector3" or not RouteData.WithinBounds(payload.position, NpcConfig.MAP_BOUNDS) then
		return false, "posição inválida"
	end
	local chain = if type(payload.chain) == "number"
		then math.clamp(math.floor(payload.chain), 0, NpcConfig.BUILDER_MOVE_CHAIN_MAX)
		else 0

	snapshot()
	local origin = (node :: RouteData.Node).id
	local delta = payload.position - (node :: RouteData.Node).position
	local factorById = RouteData.ChainFactors(workingGraph, origin, chain)

	for id, factor in pairs(factorById) do
		local current = workingGraph[id] :: RouteData.Node
		local target = if id == origin then payload.position else current.position + delta * factor
		-- Vizinho que sairia do mapa apenas FICA: recusar a op vetaria o nó de fato arrastado.
		if RouteData.WithinBounds(target, NpcConfig.MAP_BOUNDS) then
			local moved = table.clone(current)
			moved.links = table.clone(current.links)
			moved.position = target
			workingGraph[id] = moved
		end
	end
	return true, nil
end

local function applyDelete(payload: any): (boolean, string?)
	local node = type(payload.id) == "string" and workingGraph[payload.id]
	if not node then
		return false, "nó inexistente"
	end
	snapshot()
	workingGraph[(node :: RouteData.Node).id] = nil
	for id, other in pairs(workingGraph) do
		local kept = {}
		local changed = false
		for _, linkId in ipairs(other.links) do
			if linkId ~= payload.id then
				table.insert(kept, linkId)
			else
				changed = true
			end
		end
		if changed then
			local cloned = table.clone(other)
			cloned.links = kept
			workingGraph[id] = cloned
		end
	end
	return true, nil
end

-- Tira `targetId` dos links de `node` (devolvendo um clone) e diz se tirou.
local function withoutLink(node: RouteData.Node, targetId: string): (RouteData.Node, boolean)
	local cloned = table.clone(node)
	local kept: { string } = {}
	local removed = false
	for _, linkId in ipairs(node.links) do
		if linkId ~= targetId then
			table.insert(kept, linkId)
		else
			removed = true
		end
	end
	cloned.links = kept
	return cloned, removed
end

-- Alterna: existe -> remove; não existe -> cria. Escreve os DOIS sentidos — mão única é travessia que falha pela metade.
local function applyLink(payload: any): (boolean, string?)
	local from = type(payload.fromId) == "string" and workingGraph[payload.fromId]
	local to = type(payload.toId) == "string" and workingGraph[payload.toId]
	if not from or not to or payload.fromId == payload.toId then
		return false, "par de nós inválido"
	end
	snapshot()

	local clonedFrom, hadLink = withoutLink(from :: RouteData.Node, payload.toId)
	local clonedTo = (withoutLink(to :: RouteData.Node, payload.fromId))
	if not hadLink then
		table.insert(clonedFrom.links, payload.toId)
		table.insert(clonedTo.links, payload.fromId)
	end
	workingGraph[clonedFrom.id] = clonedFrom
	workingGraph[clonedTo.id] = clonedTo
	return true, nil
end

-- ÁREA DE ESCUTA do nó, válida em qualquer tipo de rota. RECUSA fora de faixa, nunca clamp.
local function applySetSense(payload: any): (boolean, string?)
	local node = type(payload.id) == "string" and workingGraph[payload.id]
	if not node then
		return false, "nó inexistente"
	end
	local radius = payload.radius
	if radius ~= nil then
		-- `radius ~= radius` pega NaN, que atravessaria as comparações de faixa.
		if type(radius) ~= "number" or radius ~= radius then
			return false, "raio não é número"
		end
		if radius < RouteData.SENSE_MIN or radius > RouteData.SENSE_MAX then
			return false, string.format("raio fora de %d..%d studs", RouteData.SENSE_MIN, RouteData.SENSE_MAX)
		end
	end
	snapshot()
	local cloned = table.clone(node :: RouteData.Node)
	cloned.links = table.clone((node :: RouteData.Node).links)
	cloned.senseRadius = radius -- nil LIMPA: volta a valer NpcConfig.NODE_SENSE_RADIUS
	workingGraph[cloned.id] = cloned
	return true, nil
end

-- SUBDIVIDIR: o cliente manda FRAÇÃO, nunca posição — o servidor interpola entre o que já tem.

-- studs; ponto mais perto que isto de uma ponta é recusado. Em studs e não em fração: um clamp de fração quebraria a divisão em partes iguais.
local SUBDIVIDE_MIN_GAP = 0.25

-- Filtra e deduplica. `budget` é o que ainda cabe no gesto; `length` converte a guarda em fração.
local function sanitizeFractions(raw: any, budget: number, length: number): { number }
	local out: { number } = {}
	if type(raw) ~= "table" or length < 0.01 then
		return out
	end
	local margin = SUBDIVIDE_MIN_GAP / length
	local seen: { [number]: boolean } = {}
	for _, value in ipairs(raw :: { any }) do
		if #out >= budget then
			break
		end
		if type(value) == "number" and value == value and value > margin and value < 1 - margin then
			-- Arredonda pro milésimo SÓ pra deduplicar; o valor gravado é o original.
			local key = math.floor(value * 1000 + 0.5)
			if not seen[key] then
				seen[key] = true
				table.insert(out, value)
			end
		end
	end
	return out
end

local function applySubdivide(payload: any): (boolean, string?)
	local edges = payload.edges
	if type(edges) ~= "table" or #(edges :: { any }) == 0 then
		return false, "payload de Subdivide sem arestas"
	end

	local budget = NpcConfig.BUILDER_MAX_TRAIL_NODES
	local applied = 0
	local snapped = false

	for _, entry in ipairs(edges :: { any }) do
		if budget <= 0 then
			break
		end
		if type(entry) == "table" and type(entry.fromId) == "string" and type(entry.toId) == "string" then
			-- Lê do grafo A CADA aresta: linhas vizinhas compartilham nó, e um clone velho partiria a junção.
			local a = workingGraph[entry.fromId]
			local b = workingGraph[entry.toId]
			local sameType = a ~= nil and b ~= nil and (a :: RouteData.Node).routeType == (b :: RouteData.Node).routeType
			local room = NpcConfig.MAX_NODES_PER_SLOT - totalNodes()
			if sameType and entry.fromId ~= entry.toId and room > 0 then
				local length = ((b :: RouteData.Node).position - (a :: RouteData.Node).position).Magnitude
				local fractions = sanitizeFractions(entry.fractions, math.min(budget, room), length)
				if #fractions > 0 then
					if not snapped then
						snapshot()
						snapped = true
					end
					local clonedA = table.clone(a :: RouteData.Node)
					clonedA.links = table.clone((a :: RouteData.Node).links)
					local clonedB = table.clone(b :: RouteData.Node)
					clonedB.links = table.clone((b :: RouteData.Node).links)

					local ids: { string } = {}
					for _ = 1, #fractions do
						table.insert(ids, HttpService:GenerateGUID(false))
					end
					local created = RouteData.SplitEdge(clonedA, clonedB, fractions, ids)

					workingGraph[clonedA.id] = clonedA
					workingGraph[clonedB.id] = clonedB
					local order = nextOrderFor(clonedA.routeType)
					for index, node in ipairs(created) do
						node.order = order + index
						workingGraph[node.id] = node
					end
					budget -= #created
					applied += #created
				end
			end
		end
	end

	if applied == 0 then
		return false, "nenhuma aresta utilizável no gesto"
	end
	return true, nil
end

local function applyClear(payload: any): (boolean, string?)
	snapshot()
	if RouteData.IsValidType(payload.routeType) then
		for id, node in pairs(workingGraph) do
			if node.routeType == payload.routeType then
				workingGraph[id] = nil
			end
		end
	else
		workingGraph = {}
	end
	return true, nil
end

local function applyUndo(): (boolean, string?)
	local previous = table.remove(undoStack)
	if not previous then
		return false, "nada a desfazer"
	end
	workingGraph = previous
	return true, nil
end

local OPS: { [string]: (any) -> (boolean, string?) } = {
	Add = applyAdd,
	AddTrail = applyAddTrail,
	Move = applyMove,
	Delete = applyDelete,
	Link = applyLink,
	SetSense = applySetSense,
	Subdivide = applySubdivide,
	Clear = applyClear,
	Undo = function(_payload)
		return applyUndo()
	end,
}

-- ==================================================================================== REMOTES

function RouteBuilderServer.Init()
	statsEvent = Remotes.Event("RouteBuilderStats")
	visualsEvent = Remotes.Event("RouteBuilderVisuals")

	local opEvent = Remotes.Event("RouteBuilderOp")
	opEvent.OnServerEvent:Connect(function(player: Player, payload: any)
		if not isAuthorized(player) then
			return -- silêncio: quem não está na allowlist não recebe nem dica de que a API existe
		end
		if not withinRate(player) then
			return
		end
		if type(payload) ~= "table" or type(payload.op) ~= "string" then
			return
		end

		-- Abrir/fechar a janela não é edição: sem snapshot e sem republicar o grafo.
		if payload.op == "SetOpen" then
			local open = payload.open == true
			setBuilderOpen(player, open)
			if open then
				statsWatchers[player] = true
				startAutosaveLoop()
				pushStats()
			else
				statsWatchers[player] = nil
				task.spawn(autosaveNow)
			end
			return
		end

		local handler = OPS[payload.op]
		if not handler then
			return
		end
		local ok, reason = handler(payload)

		-- Guarda de teto DEPOIS de aplicar, e desfaz quando estoura: prever o efeito sobre o número de PEÇAS exigiria simular o gesto. `Undo` fica de fora.
		if ok and payload.op ~= "Undo" then
			local violation = RouteStorage.CapViolation(workingGraph)
			if violation then
				applyUndo()
				-- Republicar é obrigatório: sem isto o runtime fica com a edição recusada.
				publish()
				pushVisuals()
				warn(string.format(
					"[RouteBuilder] op %s de %s desfeita: %s", payload.op, player.Name, violation))
				pushStats(violation)
				return
			end
		end

		if ok then
			publish()
			pushVisuals()
			pushStats()
			autosaveDirty = true
		elseif reason then
			warn(string.format("[RouteBuilder] op %s de %s rejeitada: %s", payload.op, player.Name, reason))
			pushStats(reason)
		end
	end)

	local query = Remotes.Function("RouteBuilderQuery")
	query.OnServerInvoke = function(player: Player, payload: any)
		if type(payload) ~= "table" or type(payload.op) ~= "string" then
			return { ok = false, reason = "payload inválido" }
		end
		if payload.op == "IsAuthorized" then
			return { ok = true, authorized = isAuthorized(player) }
		end
		if not isAuthorized(player) then
			return { ok = false, reason = "não autorizado" }
		end

		if payload.op == "GetVisuals" then
			return { ok = true, version = visualsVersion, nodes = visualPayload() }
		end

		if payload.op == "ListSlots" then
			local ok, namesOrErr = RouteStorage.List()
			if not ok then
				return { ok = false, reason = namesOrErr }
			end
			local _okCur, current = RouteStorage.GetCurrent()
			return { ok = true, names = namesOrErr, current = current }
		end

		if payload.op == "Save" then
			local now = os.clock()
			if now - (lastSaveAt[player] or -math.huge) < NpcConfig.BUILDER_SAVE_MIN_INTERVAL then
				return { ok = false, reason = "aguarde antes de salvar de novo" }
			end
			lastSaveAt[player] = now
			local ok, reason = RouteStorage.Save(payload.name, workingGraph)
			-- Só depois de gravar: carimbar antes apontaria pra um slot que a recusa nunca criou.
			if ok then
				local clean = RouteStorage.NormalizeName(payload.name)
				RouteStorage.SetCurrent(clean)
			end
			return { ok = ok, reason = reason }
		end

		if payload.op == "Load" then
			local ok, graphOrErr, dropped = RouteStorage.Load(payload.name)
			if not ok then
				return { ok = false, reason = graphOrErr }
			end
			local clean = RouteStorage.NormalizeName(payload.name)
			RouteStorage.SetCurrent(clean)
			return adoptGraph(graphOrErr :: RouteData.Graph, dropped)
		end

		if payload.op == "LoadAuto" then
			local ok, graphOrErr, dropped = RouteStorage.LoadAuto()
			if not ok then
				return { ok = false, reason = graphOrErr }
			end
			return adoptGraph(graphOrErr :: RouteData.Graph, dropped)
		end

		if payload.op == "DeleteSlot" then
			local ok, reason = RouteStorage.Delete(payload.name)
			-- Apagar o slot que estava na mesa esquece a marca, senão o próximo SALVAR o ressuscitaria.
			if ok then
				local clean = RouteStorage.NormalizeName(payload.name)
				local _okCur, current = RouteStorage.GetCurrent()
				if clean ~= nil and current == clean then
					RouteStorage.SetCurrent(nil)
				end
			end
			return { ok = ok, reason = reason }
		end

		-- Solta a retenção DESTE autor sem fechar a janela: ver a rota sendo percorrida não pode custar o modo e a seleção.
		if payload.op == "SetNpcPaused" then
			setBuilderOpen(player, payload.paused == true)
			return { ok = true, paused = payload.paused == true }
		end

		-- O corpo do NPC, atrás do mesmo isAuthorized: a câmera de depuração precisa do Model.
		if payload.op == "NpcModel" then
			local npc = getNpcService()
			local agents: any = nil
			if npc and type(npc.GetActiveAgents) == "function" then
				local okAgents, result = pcall(npc.GetActiveAgents)
				agents = if okAgents and type(result) == "table" then result else nil
			end
			if agents == nil then
				return { ok = false, reason = "sem NPC no mundo" }
			end

			local wanted = payload.agentId
			if type(wanted) == "string" then
				local agent = agents[wanted]
				local character = agent and (agent :: any).Character
				if character ~= nil and character.Parent ~= nil then
					return { ok = true, model = character, agentId = wanted }
				end
			end

			-- Degradação determinística pelo menor Id: a ordem de pairs não é estável entre sessões.
			local best: any = nil
			for _, agent in pairs(agents) do
				local character = (agent :: any).Character
				if character ~= nil and character.Parent ~= nil then
					if best == nil or (agent :: any).Id < (best :: any).Id then
						best = agent
					end
				end
			end
			if best then
				return { ok = true, model = (best :: any).Character, agentId = (best :: any).Id }
			end
			return { ok = false, reason = "sem NPC no mundo" }
		end

		return { ok = false, reason = "op desconhecida" }
	end

	-- Autor que cai da conexão nunca manda SetOpen(false), e a retenção seguraria os NPCs pra sempre; as tabelas por Player saem junto pra não reter a instância.
	-- Shutdown espera este retorno: sem ele as edições dos últimos BUILDER_AUTOSAVE_INTERVAL s morrem
	-- com o servidor. Espera a gravação em curso, se houver, e faz a que ficou suja.
	game:BindToClose(function()
		while autosaveBusy do
			task.wait(0.1)
		end
		autosaveNow()
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		opWindow[player] = nil
		lastSaveAt[player] = nil
		statsWatchers[player] = nil
		if buildersOpen[player] then
			setBuilderOpen(player, false)
		end
		task.spawn(autosaveNow)
	end)
end

function RouteBuilderServer.Start()
	-- Autoload do slot configurado; task.spawn porque DataStore YIELDA e o boot não espera.
	local slot = NpcConfig.ROUTE_AUTOLOAD_NAME
	if type(slot) == "string" and #slot > 0 then
		task.spawn(function()
			local function adopt(loaded: RouteData.Graph): number
				workingGraph = loaded
				publish()
				pushVisuals()
				local count = 0
				for _ in pairs(workingGraph) do
					count += 1
				end
				return count
			end

			local ok, graphOrErr = RouteStorage.Load(slot)
			if ok then
				local count = adopt(graphOrErr :: RouteData.Graph)
				if count > 0 then
					print(string.format("[RouteBuilder] slot '%s' carregado no boot: %d nó(s).", slot, count))
				end
				return
			end

			print(string.format("[RouteBuilder] autoload do slot '%s' indisponível (%s).", slot, tostring(graphOrErr)))

			local okList, names = RouteStorage.List()
			local saved = if okList and typeof(names) == "table" then names :: { string } else {}
			if #saved == 0 then
				print("[RouteBuilder] nenhum slot salvo: os NPCs vão navegar só por pathfinding até você salvar um.")
				return
			end

			-- Um único slot salvo não é ambíguo; com dois ou mais, adivinhar seria pior que listar.
			if #saved == 1 then
				local only = saved[1]
				local okOnly, onlyGraph = RouteStorage.Load(only)
				if okOnly then
					local count = adopt(onlyGraph :: RouteData.Graph)
					print(string.format(
						"[RouteBuilder] único slot salvo ('%s') adotado no boot: %d nó(s)."
							.. " Salve como '%s' (ou mude NpcConfig.ROUTE_AUTOLOAD_NAME) pra fixar a escolha.",
						only,
						count,
						slot
					))
					return
				end
				print(string.format("[RouteBuilder] slot '%s' também não abriu (%s).", only, tostring(onlyGraph)))
				return
			end

			print(string.format(
				"[RouteBuilder] slots salvos: %s — carregue um pela GUI, ou renomeie/salve como '%s'"
					.. " (ou mude NpcConfig.ROUTE_AUTOLOAD_NAME) pra ele valer desde o boot.",
				table.concat(saved, ", "),
				slot
			))
		end)
	end
end

return RouteBuilderServer
