--!strict
-- Modelo de dados das rotas autoradas: tipos, validação, serialização e as contas de grafo que
-- builder e armazém precisam responder igual. Rota é grafo, não lista: `order` dá o circuito de
-- patrulha, `links` (não-dirigidos) dão desvio e variação. Uma "rota" é um componente conexo de
-- nós do mesmo routeType. Cor é só representação (NpcConfig.NODE_COLORS); a lógica usa o enum.
local RouteData = {}

-- Main é a malha compartilhada por toda classe; os demais são as redes próprias de cada uma.
RouteData.RouteType = table.freeze({
	Main = "Main",
	Citizen = "Citizen",
	Medic = "Medic",
	Guard = "Guard",
	Detective = "Detective",
})

function RouteData.IsValidType(routeType: any): boolean
	return type(routeType) == "string" and RouteData.RouteType[routeType] ~= nil
end

-- `position` é Vector3 em memória; a serialização abre em {x,y,z}. `waitTime` em segundos.
-- `senseRadius` (studs) é a área de escuta opcional do nó; nil = padrão (NpcConfig).
export type Node = {
	id: string,
	position: Vector3,
	routeType: string,
	order: number,
	waitTime: number,
	lookDirection: Vector3?,
	links: { string },
	roomTag: string?,
	senseRadius: number?,
}

export type Graph = { [string]: Node }

RouteData.SCHEMA_VERSION = 1

-- Faixa do raio de escuta. Mora aqui (e não em NpcConfig) porque ValidateNode é pura de propósito.
RouteData.SENSE_MIN = 5
RouteData.SENSE_MAX = 200

-- ===================================================================================== VALIDAÇÃO

function RouteData.WithinBounds(position: Vector3, bounds: { center: Vector3, size: Vector3 }): boolean
	local half = bounds.size / 2
	local delta = position - bounds.center
	return math.abs(delta.X) <= half.X and math.abs(delta.Y) <= half.Y and math.abs(delta.Z) <= half.Z
end

-- Valida um nó vindo de fora (cliente ou DataStore). Não confere links (o alvo pode ainda não
-- existir durante a edição) — quem fecha o grafo é quem o consome.
function RouteData.ValidateNode(node: any, bounds: { center: Vector3, size: Vector3 }): (boolean, string?)
	if type(node) ~= "table" then
		return false, "nó não é tabela"
	end
	if type(node.id) ~= "string" or #node.id == 0 or #node.id > 64 then
		return false, "id ausente ou fora do tamanho (1..64)"
	end
	if typeof(node.position) ~= "Vector3" then
		return false, "position não é Vector3"
	end
	if not RouteData.WithinBounds(node.position, bounds) then
		return false, "posição fora dos bounds do mapa"
	end
	if not RouteData.IsValidType(node.routeType) then
		return false, "routeType inválido: " .. tostring(node.routeType)
	end
	if type(node.order) ~= "number" or node.order ~= node.order or node.order < 0 or node.order > 1e6 then
		return false, "order fora de 0..1e6"
	end
	if type(node.waitTime) ~= "number" or node.waitTime < 0 or node.waitTime > 60 then
		return false, "waitTime fora de 0..60s"
	end
	if node.lookDirection ~= nil and typeof(node.lookDirection) ~= "Vector3" then
		return false, "lookDirection não é Vector3"
	end
	if node.senseRadius ~= nil then
		if type(node.senseRadius) ~= "number" or node.senseRadius ~= node.senseRadius then
			return false, "senseRadius não é número"
		end
		if node.senseRadius < RouteData.SENSE_MIN or node.senseRadius > RouteData.SENSE_MAX then
			return false, string.format("senseRadius fora de %d..%d studs", RouteData.SENSE_MIN, RouteData.SENSE_MAX)
		end
	end
	if type(node.links) ~= "table" then
		return false, "links ausente"
	end
	for _, linkId in ipairs(node.links) do
		if type(linkId) ~= "string" then
			return false, "link com id não-string"
		end
	end
	if node.roomTag ~= nil and (type(node.roomTag) ~= "string" or #node.roomTag > 64) then
		return false, "roomTag inválida"
	end
	return true, nil
end

-- Liga uma fileira de nós em sequência, nos DOIS sentidos: o grafo é não-dirigido, e uma trilha
-- ligada só na ida seria invisível de volta sem aparecer no desenho. Idempotente por par.
function RouteData.LinkChain(nodes: { Node })
	local function connect(a: Node, b: Node)
		for _, id in ipairs(a.links) do
			if id == b.id then
				return
			end
		end
		table.insert(a.links, b.id)
	end
	for index = 2, #nodes do
		connect(nodes[index - 1], nodes[index])
		connect(nodes[index], nodes[index - 1])
	end
end

-- Desfaz a ligação A-B nos dois sentidos e emenda uma fileira de pontos novos entre eles, um por
-- fração, devolvendo os criados em ordem. `a` e `b` são MUTADOS — o caller passa clones. Sem
-- desfazer A-B os novos virariam triângulo e a busca pularia o trecho recém-detalhado; as frações
-- são ordenadas porque o arrasto pode ter corrido de B pra A.
function RouteData.SplitEdge(a: Node, b: Node, fractions: { number }, ids: { string }): { Node }
	local function drop(node: Node, targetId: string)
		local kept: { string } = {}
		for _, id in ipairs(node.links) do
			if id ~= targetId then
				table.insert(kept, id)
			end
		end
		node.links = kept
	end
	drop(a, b.id)
	drop(b, a.id)

	local sorted = table.clone(fractions)
	table.sort(sorted)

	local chain: { Node } = { a }
	local created: { Node } = {}
	for index, fraction in ipairs(sorted) do
		local id = ids[index]
		if id then
			local middle: Node = {
				id = id,
				position = a.position:Lerp(b.position, math.clamp(fraction, 0, 1)),
				routeType = a.routeType,
				order = a.order,
				waitTime = 0,
				links = {},
				roomTag = a.roomTag,
			}
			table.insert(chain, middle)
			table.insert(created, middle)
		end
	end
	table.insert(chain, b)
	RouteData.LinkChain(chain)
	return created
end

-- Fatores da corrente do Mover: id -> fração do deslocamento que o nó acompanha (origem = 1).
-- `count` é a quantidade exata de pontos além da origem; a queda é por salto de grafo (BFS), com
-- desempate por distância e id para a prévia do cliente e a aplicação do servidor concordarem.
function RouteData.ChainFactors(graph: Graph, originId: string, count: number): { [string]: number }
	local factors: { [string]: number } = {}
	local origin = graph[originId]
	if origin == nil then
		return factors
	end
	factors[originId] = 1

	local wanted = math.max(math.floor(count), 0)
	if wanted == 0 then
		return factors
	end

	local hopById: { [string]: number } = { [originId] = 0 }
	local candidates: { string } = {}
	local frontier: { string } = { originId }
	while #frontier > 0 do
		local nextFrontier: { string } = {}
		for _, id in ipairs(frontier) do
			local node = graph[id]
			if node then
				for _, neighbourId in ipairs(node.links) do
					if graph[neighbourId] and hopById[neighbourId] == nil then
						hopById[neighbourId] = hopById[id] + 1
						table.insert(candidates, neighbourId)
						table.insert(nextFrontier, neighbourId)
					end
				end
			end
		end
		frontier = nextFrontier
	end

	table.sort(candidates, function(a, b)
		if hopById[a] ~= hopById[b] then
			return hopById[a] < hopById[b]
		end
		local distanceA = (graph[a].position - origin.position).Magnitude
		local distanceB = (graph[b].position - origin.position).Magnitude
		if distanceA ~= distanceB then
			return distanceA < distanceB
		end
		return a < b
	end)
	local taken = math.min(wanted, #candidates)
	if taken == 0 then
		return factors
	end

	-- A queda se estica até o salto mais distante que entrou, senão o fim da corrente andaria
	-- quase tanto quanto a origem e o trecho viraria translação rígida.
	local maxHop = 0
	for index = 1, taken do
		maxHop = math.max(maxHop, hopById[candidates[index]])
	end
	for index = 1, taken do
		local id = candidates[index]
		factors[id] = 1 - hopById[id] / (maxHop + 1)
	end
	return factors
end

-- ===================================================================== GEOMETRIA DO DESENHO
-- Têm dois donos: o servidor monta os visuais, o cliente faz cabo e haste acompanharem o arrasto.

function RouteData.CableGeometry(a: Vector3, b: Vector3, thickness: number): (CFrame?, Vector3?)
	local span = (b - a).Magnitude
	if span < 0.1 then
		return nil, nil
	end
	return CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), Vector3.new(span, thickness, thickness)
end

function RouteData.StemGeometry(ground: Vector3, lift: number): CFrame
	return CFrame.new(ground + Vector3.new(0, lift / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

-- ============================================================================ COMPONENTES (rotas)

-- Componentes conexos de nós do MESMO routeType, cada um ordenado por `order` (desempate por id).
-- Link cruzando tipo não junta componente — a malha Main não "vaza" pra rede de classe.
function RouteData.ConnectedComponents(graph: Graph): { { string } }
	local neighbors: { [string]: { string } } = {}
	local function link(a: string, b: string)
		neighbors[a] = neighbors[a] or {}
		table.insert(neighbors[a], b)
	end
	for id, node in pairs(graph) do
		neighbors[id] = neighbors[id] or {}
		for _, other in ipairs(node.links) do
			local otherNode = graph[other]
			if otherNode and otherNode.routeType == node.routeType then
				link(id, other)
				link(other, id)
			end
		end
	end

	local roots: { string } = {}
	for id in pairs(graph) do
		table.insert(roots, id)
	end
	table.sort(roots)

	local seen: { [string]: boolean } = {}
	local components: { { string } } = {}
	for _, root in ipairs(roots) do
		if not seen[root] then
			seen[root] = true
			local queue = { root }
			local component = { root }
			while #queue > 0 do
				local current = table.remove(queue, 1) :: string
				for _, neighbor in ipairs(neighbors[current] or {}) do
					if not seen[neighbor] then
						seen[neighbor] = true
						table.insert(queue, neighbor)
						table.insert(component, neighbor)
					end
				end
			end
			table.sort(component, function(a, b)
				local na, nb = graph[a], graph[b]
				if na.order ~= nb.order then
					return na.order < nb.order
				end
				return a < b
			end)
			table.insert(components, component)
		end
	end
	return components
end

-- ================================================================================ CONTAS DO GRAFO

export type Stats = {
	total: number,
	components: number,
	largest: number,
	largestType: string?,
	byType: { [string]: number },
}

-- As contas que os tetos consultam. Um dono só: o que a edição aceitou, o Save grava.
function RouteData.Stats(graph: Graph): Stats
	local byType: { [string]: number } = {}
	local total = 0
	for _, node in pairs(graph) do
		total += 1
		byType[node.routeType] = (byType[node.routeType] or 0) + 1
	end

	local components = RouteData.ConnectedComponents(graph)
	local largest = 0
	local largestType: string? = nil
	for _, component in ipairs(components) do
		if #component > largest then
			largest = #component
			local first = graph[component[1]]
			largestType = if first then first.routeType else nil
		end
	end

	return {
		total = total,
		components = #components,
		largest = largest,
		largestType = largestType,
		byType = byType,
	}
end

-- Nós que o desenho denuncia: malha Main partida em mais de um componente marca todos menos o
-- maior (pedaço solto é travessia que não acontece, e costuma nascer de apagar nó no meio de
-- corredor). Rede de classe separada da Main é legítima — cada classe pode ter rotas próprias.
function RouteData.OrphanNodes(graph: Graph): { [string]: boolean }
	local flagged: { [string]: boolean } = {}
	local components = RouteData.ConnectedComponents(graph)

	local mainIndexes: { number } = {}
	local biggestMain, biggestMainSize = 0, -1

	for index, component in ipairs(components) do
		local first = graph[component[1]]
		if first ~= nil and first.routeType == RouteData.RouteType.Main then
			table.insert(mainIndexes, index)
			if #component > biggestMainSize then
				biggestMain, biggestMainSize = index, #component
			end
		end
	end

	if #mainIndexes > 1 then
		for _, index in ipairs(mainIndexes) do
			if index ~= biggestMain then
				for _, id in ipairs(components[index]) do
					flagged[id] = true
				end
			end
		end
	end

	return flagged
end

-- ==================================================================================== SERIALIZAÇÃO

local function packVector(v: Vector3): { x: number, y: number, z: number }
	return { x = v.X, y = v.Y, z = v.Z }
end

local function unpackVector(t: any): Vector3?
	if type(t) ~= "table" or type(t.x) ~= "number" or type(t.y) ~= "number" or type(t.z) ~= "number" then
		return nil
	end
	return Vector3.new(t.x, t.y, t.z)
end

-- Grafo -> tabela pura para UpdateAsync. Determinístico na forma (lista ordenada por id).
function RouteData.Serialize(graph: Graph): { [string]: any }
	local nodes: { { [string]: any } } = {}
	local ids: { string } = {}
	for id in pairs(graph) do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local node = graph[id]
		table.insert(nodes, {
			id = node.id,
			position = packVector(node.position),
			routeType = node.routeType,
			order = node.order,
			waitTime = node.waitTime,
			lookDirection = if node.lookDirection then packVector(node.lookDirection :: Vector3) else nil,
			links = table.clone(node.links),
			roomTag = node.roomTag,
			senseRadius = node.senseRadius,
		})
	end
	return {
		schemaVersion = RouteData.SCHEMA_VERSION,
		nodes = nodes,
	}
end

-- Passos de migração: [versãoDe] = função(registro) -> registro na versão seguinte.
local migrations: { [number]: (any) -> any } = {}

-- Registro do DataStore -> Grafo. Tolerante por nó: entrada malformada é descartada com
-- contagem, nunca derruba o load inteiro. Devolve (graph, descartados).
function RouteData.Deserialize(record: any, bounds: { center: Vector3, size: Vector3 }): (Graph, number)
	local graph: Graph = {}
	if type(record) ~= "table" then
		return graph, 0
	end

	local version = if type(record.schemaVersion) == "number" then record.schemaVersion else 1
	-- Versão futura não tem migração pra trás: vazio é mais honesto que ler no chute.
	if version > RouteData.SCHEMA_VERSION then
		return graph, 0
	end
	while version < RouteData.SCHEMA_VERSION do
		local step = migrations[version]
		if not step then
			return graph, 0
		end
		record = step(record)
		version += 1
	end

	local dropped = 0
	if type(record.nodes) ~= "table" then
		return graph, 0
	end
	for _, raw in ipairs(record.nodes) do
		local candidate = if type(raw) == "table" then table.clone(raw) else nil
		local position = candidate and unpackVector(candidate.position)
		if candidate and position then
			candidate.position = position
			candidate.lookDirection = unpackVector(candidate.lookDirection)
			candidate.links = if type(candidate.links) == "table" then candidate.links else {}
			candidate.waitTime = if type(candidate.waitTime) == "number" then candidate.waitTime else 0
			candidate.senseRadius = if type(candidate.senseRadius) == "number" then candidate.senseRadius else nil
			local ok = RouteData.ValidateNode(candidate, bounds)
			if ok and graph[candidate.id] == nil then
				graph[candidate.id] = candidate :: any
			else
				dropped += 1
			end
		else
			dropped += 1
		end
	end
	return graph, dropped
end

return RouteData
