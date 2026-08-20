--!strict
-- O grafo publicado pelo builder, pronto para ser percorrido: classifica cada nó em superfície ou
-- aéreo e monta o trajeto que a marcha anda — o tronco, ou um galho de uma bifurcação dele.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
local RouteData = require(Shared:WaitForChild("Npc"):WaitForChild("RouteData"))

local Npc = ServerScriptService:WaitForChild("Source"):WaitForChild("Npc")
local Movement = require(Npc:WaitForChild("Movement"))

local RouteRuntime = {}
RouteRuntime.Pure = {}

local graph: RouteData.Graph = {}
local aerialById: { [string]: boolean } = {}
local probedAt: { [string]: Vector3 } = {}
local neighbors: { [string]: { string } } = {}
local nodesByType: { [string]: { RouteData.Node } } = {}

-- Rodízio de trajetos, um por corpo. Contador e não sorteio: duas partidas iguais correm igual.
local variantSeed = 0

-- ================================================================== SUPERFÍCIE x AÉREO (por nó)

local function flatDistance(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- "Chegou" = perto em XZ E na mesma faixa de altura; em 3D um nó abaixo do corpo nunca conta.
local function reached(point: Vector3, from: Vector3, radius: number): boolean
	return flatDistance(point, from) <= radius and math.abs(point.Y - from.Y) <= NpcConfig.NAV_ARRIVE_Y
end

-- Δ Y sozinho não é régua: 11 studs em 11 de caminhada é rampa, 11 em zero é parede. Descer passa.
local function riseIsWalkable(rise: number, flat: number, maxRise: number, maxSlope: number): boolean
	if rise <= maxRise then
		return true
	end
	if flat <= 1e-3 then
		return false
	end
	return math.deg(math.atan(rise / flat)) <= maxSlope
end

local function footOf(agent: any): Vector3
	local root: BasePart = agent.RootPart
	return root.Position - Vector3.new(0, agent.Humanoid.HipHeight + root.Size.Y * 0.5, 0)
end

-- Não é mundo para as sondas: o desenho da rota, os corpos vivos e as portas (o NPC sabe abrir).
local function probeParams(): RaycastParams
	local exclude: { Instance } = {}
	for _, name in ipairs({ NpcConfig.NODE_FOLDER_NAME, NpcConfig.BODY_FOLDER }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	local doors: Instance? = Workspace
	for _, name in ipairs(DoorConfig.Folder) do
		doors = doors and doors:FindFirstChild(name)
	end
	if doors then
		table.insert(exclude, doors :: Instance)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

-- Dono único da classe do nó: duas sondas dariam duas opiniões. `rise` nil = sem chão embaixo.
local function aerialRise(rise: number?, maxRise: number): boolean
	if rise == nil then
		return true
	end
	return (rise :: number) > maxRise
end
RouteRuntime.Pure.IsAerial = aerialRise

local function groundRise(position: Vector3, params: RaycastParams): number?
	local origin = position + Vector3.new(0, NpcConfig.PROBE_UP, 0)
	local drop = Vector3.new(0, -(NpcConfig.PROBE_UP + NpcConfig.PROBE_DOWN), 0)
	local hit = Workspace:Raycast(origin, drop, params)
	if hit == nil then
		return nil
	end
	return position.Y - hit.Position.Y
end

-- Uma vez por SetGraph, nunca no tick da árvore: só nó novo ou movido paga raycast.
local function rebuildDerived()
	local params = probeParams()
	local freshAerial: { [string]: boolean } = {}
	local freshProbe: { [string]: Vector3 } = {}
	for id, node in pairs(graph) do
		if probedAt[id] == node.position and aerialById[id] ~= nil then
			freshAerial[id] = aerialById[id]
		else
			freshAerial[id] = aerialRise(groundRise(node.position, params), NpcConfig.NODE_SURFACE_MAX_RISE)
		end
		freshProbe[id] = node.position
	end

	local freshLinks: { [string]: { string } } = {}
	local freshByType: { [string]: { RouteData.Node } } = {}
	for id, node in pairs(graph) do
		local walkable: { string } = {}
		for _, other in ipairs(node.links) do
			local target = graph[other]
			if target and target.routeType == node.routeType and not freshAerial[other] then
				table.insert(walkable, other)
			end
		end
		table.sort(walkable)
		freshLinks[id] = walkable

		local bucket = freshByType[node.routeType]
		if bucket == nil then
			bucket = {}
			freshByType[node.routeType] = bucket
		end
		table.insert(bucket :: { RouteData.Node }, node)
	end

	aerialById = freshAerial
	probedAt = freshProbe
	neighbors = freshLinks
	nodesByType = freshByType
end

-- Cópia rasa: o builder muta a tabela dele in loco, e uma op desfeita deixaria aqui nó descartado.
function RouteRuntime.SetGraph(published: RouteData.Graph)
	graph = table.clone(published)
	rebuildDerived()
end

-- ===================================================================================== CONSULTAS

function RouteRuntime.IsAerial(id: string): boolean
	return aerialById[id] == true
end

function RouteRuntime.HasGraph(): boolean
	return next(graph) ~= nil
end

function RouteRuntime.Node(id: string): RouteData.Node?
	return graph[id]
end

-- Vizinhos andáveis: mesmo routeType, existentes no grafo e de superfície.
function RouteRuntime.Neighbors(id: string): { string }
	return neighbors[id] or {}
end

-- Lista derivada e CACHEADA: quem chama não pode mutá-la.
function RouteRuntime.NodesOfType(routeType: string): { RouteData.Node }?
	return nodesByType[routeType]
end

function RouteRuntime.HasRoutes(routeType: string): boolean
	local bucket = nodesByType[routeType]
	return bucket ~= nil and #bucket > 0
end

-- Nó de superfície COM vizinho andável, varrendo `types` na ordem dada; nó sem vizinho é beco.
function RouteRuntime.NearestNode(position: Vector3, types: { string }): string?
	for _, routeType in ipairs(types) do
		local best: string? = nil
		local bestDistance = math.huge
		for id, node in pairs(graph) do
			local walkable = neighbors[id]
			if node.routeType == routeType and not aerialById[id] and walkable and #walkable > 0 then
				local distance = (node.position - position).Magnitude
				if distance < bestDistance or (distance == bestDistance and best ~= nil and id < best) then
					best = id
					bestDistance = distance
				end
			end
		end
		if best then
			return best
		end
	end
	return nil
end

-- Caminho em ids, com o destino e sem a origem. Em largura: com sub-ponto espaçado igual, menos
-- saltos é menor distância.
function RouteRuntime.PathTo(fromId: string, toId: string): { string }?
	if fromId == toId then
		return {}
	end
	if graph[fromId] == nil or graph[toId] == nil then
		return nil
	end

	local previous: { [string]: string } = {}
	local seen: { [string]: boolean } = { [fromId] = true }
	local queue: { string } = { fromId }
	local head = 1

	while head <= #queue do
		local current = queue[head]
		head += 1
		for _, neighbor in ipairs(neighbors[current] or {}) do
			if not seen[neighbor] then
				seen[neighbor] = true
				previous[neighbor] = current
				if neighbor == toId then
					local path: { string } = {}
					local walk: string? = toId
					while walk and walk ~= fromId do
						table.insert(path, 1, walk)
						walk = previous[walk]
					end
					return path
				end
				table.insert(queue, neighbor)
			end
		end
	end

	return nil
end

-- Nó de SUPERFÍCIE mais próximo em XZ: em 3D um nó do andar de cima venceria um de chão ao lado.
function RouteRuntime.Pure.NearestSurfaceNode(
	nodes: { RouteData.Node },
	isAerial: (string) -> boolean,
	fromXZ: Vector3,
	maxRadius: number?
): (RouteData.Node?, number)
	local best: RouteData.Node? = nil
	local bestSquared = if maxRadius then maxRadius * maxRadius else math.huge
	for _, node in ipairs(nodes) do
		if not isAerial(node.id) then
			local dx = node.position.X - fromXZ.X
			local dz = node.position.Z - fromXZ.Z
			local squared = dx * dx + dz * dz
			if squared < bestSquared then
				bestSquared = squared
				best = node
			end
		end
	end
	return best, if best then math.sqrt(bestSquared) else math.huge
end

-- ================================================================================== TRAJETOS

local function nodeDistance(a: RouteData.Node, b: RouteData.Node): number
	return (a.position - b.position).Magnitude
end

-- O grafo é NÃO-DIRIGIDO: sem normalizar a ordem, "a|b" e "b|a" seriam proibições diferentes.
local function edgeKey(a: string, b: string): string
	return if a < b then a .. "|" .. b else b .. "|" .. a
end
RouteRuntime.Pure.EdgeKey = edgeKey

-- O teto absoluto mede o DESVIO sobre a linha reta: sobre o total, reprovaria toda viagem longa.
function RouteRuntime.Pure.AcceptVariant(
	length: number,
	directDistance: number,
	maxDetour: number,
	maxRatio: number
): boolean
	if length - directDistance > maxDetour then
		return false
	end
	return length <= math.max(directDistance, NpcConfig.NAV_RATIO_FLOOR) * maxRatio
end

-- Sem linha reta não há escolha a calibrar: contornar é a única opção, e teto apertado a recusaria.
function RouteRuntime.Pure.VariantLimits(directBlocked: boolean?): (number, number)
	if directBlocked then
		return NpcConfig.NAV_VARIANT_DETOUR_BLOCKED, NpcConfig.NAV_VARIANT_RATIO_BLOCKED
	end
	return NpcConfig.NAV_VARIANT_DETOUR_OPEN, NpcConfig.NAV_VARIANT_RATIO_OPEN
end

export type RideOptions = {
	entryMax: number, -- studs de caminhada até a rede
	entryBand: number?, -- studs além do nó mais próximo que ainda são entrada
	maxDetour: number, -- studs A MAIS que a linha reta
	maxRatio: number, -- fator sobre a linha reta
	banned: { [string]: boolean }?, -- arestas proibidas (edgeKey): é o que gera os galhos
	allow: ((RouteData.Node) -> boolean)?, -- que nós desta rede podem ser pisados
	exitId: string?, -- saída imposta; sem ela vence o nó mais perto do alvo
	chasing: boolean?, -- alvo que se mexe
	maxEntryRise: number?, -- subida que o corpo vence para ENTRAR na rede
	droppable: ((RouteData.Node) -> boolean)?, -- há céu aberto até este nó? (raycast do caller)
	dropTolerance: number?, -- descida acima disto paga a sonda de céu aberto
}

-- Corpo -> tronco -> destino numa busca só: Dijkstra multi-origem, com a perna de entrada já no
-- custo inicial. Devolve ids e comprimento; nil com 0 = nada ao alcance, nil com > 0 = fora do teto.
function RouteRuntime.Pure.RideGraph(
	net: RouteData.Graph,
	from: Vector3,
	target: Vector3,
	opts: RideOptions
): ({ string }?, number)
	local banned, allow = opts.banned, opts.allow
	local distance: { [string]: number } = {}
	local previous: { [string]: string } = {}
	local settled: { [string]: boolean } = {}

	-- A entrada é o nó MAIS PRÓXIMO mais uma banda estreita: semeando todo nó ao alcance, a rede fica
	-- acessível a pé inteira. Subida medida contra o CORPO, e descida longa só havendo céu aberto.
	local maxEntryRise = opts.maxEntryRise
	local droppable = opts.droppable
	local dropTolerance = opts.dropTolerance
	local entryBand = opts.entryBand or NpcConfig.NAV_ENTRY_BAND
	local nearest = math.huge
	local legs: { [string]: number } = {}
	for id, node in pairs(net) do
		local reachable = maxEntryRise == nil
			or riseIsWalkable(
				node.position.Y - from.Y,
				flatDistance(node.position, from),
				maxEntryRise :: number,
				NpcConfig.AGENT_MAX_CLIMB_SLOPE
			)
		if
			reachable
			and droppable ~= nil
			and dropTolerance ~= nil
			and (from.Y - node.position.Y) > (dropTolerance :: number)
		then
			reachable = (droppable :: (RouteData.Node) -> boolean)(node)
		end
		if reachable and (allow == nil or allow(node)) then
			local leg = (node.position - from).Magnitude
			if leg <= opts.entryMax then
				legs[id] = leg
				if leg < nearest then
					nearest = leg
				end
			end
		end
	end
	if nearest == math.huge then
		return nil, 0
	end
	for id, leg in pairs(legs) do
		if leg <= nearest + entryBand then
			distance[id] = leg
		end
	end

	while true do
		local currentId: string? = nil
		local currentDistance = math.huge
		for id, value in pairs(distance) do
			if not settled[id] and value < currentDistance then
				currentDistance = value
				currentId = id
			end
		end
		if currentId == nil then
			break
		end
		settled[currentId] = true

		local node = net[currentId]
		for _, neighbourId in ipairs(node.links) do
			local neighbour = net[neighbourId]
			local passable = neighbour ~= nil
				and not settled[neighbourId]
				and not (banned ~= nil and banned[edgeKey(currentId, neighbourId)])
				and (allow == nil or allow(neighbour :: RouteData.Node))
			if passable then
				local candidate = currentDistance + nodeDistance(node, neighbour :: RouteData.Node)
				if candidate < (distance[neighbourId] or math.huge) then
					distance[neighbourId] = candidate
					previous[neighbourId] = currentId
				end
			end
		end
	end

	-- A saída é o nó mais PERTO DO DESTINO, não o percurso mais curto: medido em linha reta, o mínimo
	-- sai no primeiro nó e corta reto. Entre andares o teto de razão sai de cena — não se sobe no ar.
	local direct = (target - from).Magnitude
	local crossFloor = math.abs(target.Y - from.Y) > NpcConfig.NAV_ARRIVE_Y
	local ratioCeiling = if crossFloor then math.huge else opts.maxRatio

	local bestId: string? = nil
	local bestRemaining = math.huge
	local bestTotal = math.huge
	local cheapest = math.huge

	if opts.exitId ~= nil then
		local value = distance[opts.exitId :: string]
		if value == nil then
			return nil, 0
		end
		local remaining = (target - net[opts.exitId :: string].position).Magnitude
		local total = value + remaining
		if not RouteRuntime.Pure.AcceptVariant(total, direct, opts.maxDetour, ratioCeiling) then
			return nil, total
		end
		bestId, bestTotal = opts.exitId, total
	else
		-- O melhor que PERCORRE ARESTA, à parte: sendo o vencedor absoluto a própria entrada, o percurso
		-- não usa traçado nenhum. Não vale contra alvo que se mexe — ali a recusa é ordem de soltar.
		local ridingId: string? = nil
		local ridingRemaining, ridingTotal = math.huge, math.huge
		for id, value in pairs(distance) do
			local remaining = (target - net[id].position).Magnitude
			local total = value + remaining
			if total < cheapest then
				cheapest = total
			end
			if RouteRuntime.Pure.AcceptVariant(total, direct, opts.maxDetour, ratioCeiling) then
				if remaining < bestRemaining or (remaining == bestRemaining and total < bestTotal) then
					bestRemaining = remaining
					bestTotal = total
					bestId = id
				end
				if previous[id] ~= nil then
					if remaining < ridingRemaining or (remaining == ridingRemaining and total < ridingTotal) then
						ridingRemaining = remaining
						ridingTotal = total
						ridingId = id
					end
				end
			end
		end
		if not opts.chasing and bestId ~= nil and previous[bestId :: string] == nil and ridingId ~= nil then
			bestId, bestTotal = ridingId, ridingTotal
		end
	end
	if bestId == nil then
		return nil, if cheapest < math.huge then cheapest else 0
	end

	local sequence = { bestId :: string }
	local walker = bestId :: string
	while previous[walker] do
		walker = previous[walker]
		table.insert(sequence, 1, walker)
	end

	-- Um nó não é percurso: sem predecessor, o eleito É a entrada. Com saída imposta, vale.
	if #sequence < 2 and opts.exitId == nil then
		return nil, bestTotal
	end
	return sequence, bestTotal
end

-- Entrada + saltos + saída. Sai MENOR que o percurso real: os tetos são tetos sobre a estimativa.
function RouteRuntime.Pure.PointsLength(points: { Vector3 }, from: Vector3, target: Vector3): number
	if #points == 0 then
		return (target - from).Magnitude
	end
	local total = (points[1] - from).Magnitude
	for index = 2, #points do
		total += (points[index] - points[index - 1]).Magnitude
	end
	total += (target - points[#points]).Magnitude
	return total
end

-- Pula os nós já alcançados; cursor além de `#points` é o trajeto esgotado sem gastar movimento.
function RouteRuntime.Pure.SkipReached(
	points: { Vector3 },
	cursor: number,
	from: Vector3,
	radius: number
): number
	local index = cursor
	while index <= #points and reached(points[index], from, radius) do
		index += 1
	end
	return index
end

-- Nós com OUTRA saída além do trecho percorrido. Não é "grau >= 3": num losango todo nó tem grau 2.
function RouteRuntime.Pure.Junctions(net: RouteData.Graph, sequence: { string }): { number }
	local out: { number } = {}
	for index = 1, #sequence - 1 do
		local node = net[sequence[index]]
		if node then
			local previousId = if index > 1 then sequence[index - 1] else nil
			local nextId = sequence[index + 1]
			for _, linkId in ipairs(node.links) do
				if linkId ~= previousId and linkId ~= nextId then
					table.insert(out, index)
					break
				end
			end
		end
	end
	return out
end

-- =============================================================================== PLANEJAMENTO

-- Vista da rede: que nós podem ser pisados e onde sair. Fora da vista não vira atalho por acaso.
export type Lane = {
	allow: ((RouteData.Node) -> boolean)?,
	exitId: string?,
}

function RouteRuntime.LaneOfTypes(types: { string }): Lane
	local wanted: { [string]: boolean } = {}
	for _, routeType in ipairs(types) do
		wanted[routeType] = true
	end
	return {
		allow = function(node: RouteData.Node): boolean
			return wanted[node.routeType] == true
		end,
	}
end

-- Raio livre não prova caminho, e aí os tetos ficam apertados; bloqueado é prova de geometria.
local function directIsBlocked(from: Vector3, target: Vector3): boolean
	local delta = target - from
	if delta.Magnitude < 1 then
		return false
	end
	return Workspace:Raycast(from + Vector3.new(0, NpcConfig.NAV_PROBE_EYE, 0), delta, probeParams()) ~= nil
end

-- Tronco e galhos, e devolve UM em posições, com `pick` em rodízio. nil = quem chamou anda direto.
function RouteRuntime.PlanVariant(
	from: Vector3,
	target: Vector3,
	pick: number,
	lane: Lane?,
	chasing: boolean?
): { Vector3 }?
	if next(graph) == nil then
		return nil
	end

	local params = probeParams()
	local dropCache: { [string]: boolean } = {}
	local maxDetour, maxRatio = RouteRuntime.Pure.VariantLimits(directIsBlocked(from, target))
	local ride: RideOptions = {
		entryMax = NpcConfig.NAV_ENTRY_MAX,
		maxDetour = maxDetour,
		maxRatio = maxRatio,
		allow = if lane then lane.allow else nil,
		exitId = if lane then lane.exitId else nil,
		chasing = chasing,
		maxEntryRise = NpcConfig.NAV_ENTRY_RISE,
		dropTolerance = NpcConfig.NAV_ARRIVE_Y,
		droppable = function(node: RouteData.Node): boolean
			local cached = dropCache[node.id]
			if cached ~= nil then
				return cached
			end
			local lift = from.Y + NpcConfig.NAV_DROP_PROBE_LIFT
			local origin = Vector3.new(node.position.X, lift, node.position.Z)
			local depth = lift - node.position.Y + NpcConfig.NAV_DROP_PROBE_MARGIN
			local hit = Workspace:Raycast(origin, Vector3.new(0, -depth, 0), params)
			local open = hit == nil or hit.Position.Y <= node.position.Y + NpcConfig.NAV_ARRIVE_Y
			dropCache[node.id] = open
			return open
		end,
	}

	local base = RouteRuntime.Pure.RideGraph(graph, from, target, ride)
	if base == nil then
		return nil
	end

	local sequences: { { string } } = {}
	local seen: { [string]: boolean } = {}
	local function offer(sequence: { string }?)
		if sequence == nil or #sequence == 0 then
			return
		end
		local key = table.concat(sequence, ">")
		if seen[key] then
			return
		end
		seen[key] = true
		table.insert(sequences, sequence)
	end

	offer(base)

	-- Proibir a aresta que deixa a bifurcação força o outro ramo desenhado; em fila não há galho.
	for _, index in ipairs(RouteRuntime.Pure.Junctions(graph, base :: { string })) do
		if #sequences >= NpcConfig.NAV_VARIANT_COUNT then
			break
		end
		local detour: RideOptions = table.clone(ride)
		detour.banned = { [edgeKey((base :: { string })[index], (base :: { string })[index + 1])] = true }
		local branch = RouteRuntime.Pure.RideGraph(graph, from, target, detour)
		offer(branch)
	end

	local points: { Vector3 } = {}
	for _, id in ipairs(sequences[((pick - 1) % #sequences) + 1]) do
		table.insert(points, graph[id].position)
	end
	return points
end

-- ===================================================================================== MARCHA

type MarchState = {
	points: { Vector3 },
	index: number,
	target: Vector3,
	expiresAt: number,
}

function RouteRuntime.ClearMarch(agent: any)
	agent.Blackboard.March = nil
end

-- Conduz o corpo pelo grafo, um nó por vez, e é o dono do destino enquanto devolve true; false diz
-- a quem chamou que o trecho é dele.
function RouteRuntime.March(agent: any, target: Vector3, now: number, lane: Lane?, chasing: boolean?): boolean
	local bb = agent.Blackboard
	local from = agent.RootPart.Position
	if reached(target, from, NpcConfig.NAV_DIRECT_RADIUS) then
		bb.March = nil
		return false
	end
	if now < ((bb.MarchRetryAt :: number?) or 0) then
		return false
	end

	local march = bb.March :: MarchState?
	if march ~= nil then
		local state = march :: MarchState
		local stale = now >= state.expiresAt
			or state.index > #state.points
			or (target - state.target).Magnitude > NpcConfig.NAV_REPLAN_DRIFT
		if stale then
			march = nil
			bb.March = nil
		end
	end

	if march == nil then
		local pick = bb.MarchPick :: number?
		if pick == nil then
			variantSeed += 1
			pick = variantSeed
			bb.MarchPick = pick
		end
		local points = RouteRuntime.PlanVariant(footOf(agent), target, pick :: number, lane, chasing)
		if points == nil then
			bb.MarchRetryAt = now + NpcConfig.NAV_PLAN_RETRY
			return false
		end
		march = {
			points = points :: { Vector3 },
			index = 1,
			target = target,
			expiresAt = now + NpcConfig.NAV_VARIANT_TTL,
		}
		bb.March = march
	end

	local current = march :: MarchState
	local entryIndex = current.index
	current.index = RouteRuntime.Pure.SkipReached(current.points, current.index, from, NpcConfig.ARRIVE_RADIUS)
	if current.index > entryIndex then
		current.expiresAt = now + NpcConfig.NAV_VARIANT_TTL
	end
	if current.index > #current.points then
		bb.March = nil
		return false
	end

	Movement.SetGoal(agent, current.points[current.index])
	local status = Movement.Status(agent)
	if status == "arrived" then
		current.index += 1
		current.expiresAt = now + NpcConfig.NAV_VARIANT_TTL
		if current.index > #current.points then
			bb.March = nil
			return false
		end
	elseif status == "stuck" then
		Movement.Stop(agent)
		bb.March = nil
		bb.MarchPick = ((bb.MarchPick :: number?) or 0) + 1
		bb.MarchRetryAt = now + NpcConfig.NAV_PLAN_RETRY
		return false
	end
	return true
end

return RouteRuntime
