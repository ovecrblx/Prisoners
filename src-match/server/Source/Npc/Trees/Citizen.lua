--!strict
-- Comportamento do cidadão: ronda a rede de rotas dele e, ao decidir sentar, chega ao assento pela
-- marcha do grafo — só o último trecho sai do traçado. Todo estado por corpo mora no blackboard,
-- então uma árvore só atende todos os cidadãos.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))

local Npc = ServerScriptService:WaitForChild("Source"):WaitForChild("Npc")
local BehaviourTree = require(Npc:WaitForChild("BehaviourTree"))
local Movement = require(Npc:WaitForChild("Movement"))
local RouteRuntime = require(Npc:WaitForChild("RouteRuntime"))
local Seats = require(Npc:WaitForChild("Seats"))

local Citizen = {}

local function board(agent: any): any
	local data = agent.Blackboard
	if data.visitedAt == nil then
		data.visitedAt = {}
		data.skipUntil = {}
		data.seatReadyAt = 0
		data.restUntil = 0
	end
	return data
end

local function preference(agent: any): { string }
	return NpcConfig.ROUTE_PREFERENCE[agent.Class] or { "Main" }
end

-- Vista da rede que esta classe pode pisar; a marcha não sai dela por atalho.
local function lane(agent: any): RouteRuntime.Lane
	local data = board(agent)
	if data.lane == nil then
		data.lane = RouteRuntime.LaneOfTypes(preference(agent))
	end
	return data.lane
end

local function restSpan(): number
	local low, high = NpcConfig.SEAT_REST_MIN, NpcConfig.SEAT_REST_MAX
	if high <= low then
		return low
	end
	return low + math.random() * (high - low)
end

-- Assentos em carência, como conjunto: quem falhou uma vez volta a valer depois do prazo.
local function activeSkips(data: any, now: number): { [Instance]: boolean }
	local skips: { [Instance]: boolean } = {}
	for seat, until_ in pairs(data.skipUntil) do
		if now < until_ then
			skips[seat] = true
		else
			data.skipUntil[seat] = nil
		end
	end
	return skips
end

-- Vizinho menos visitado, evitando voltar por onde veio quando há para onde ir. `options` já vem
-- ordenado, então o empate é estável.
local function wander(fromId: string, avoidId: string?, visitedAt: { [string]: number }): string?
	local options = RouteRuntime.Neighbors(fromId)
	if #options == 0 then
		return nil
	end
	local best: string? = nil
	local bestVisit = math.huge
	for _, id in ipairs(options) do
		if #options == 1 or id ~= avoidId then
			local visit = visitedAt[id] or -math.huge
			if visit < bestVisit then
				best = id
				bestVisit = visit
			end
		end
	end
	return best or options[1]
end

-- Ancora o corpo num nó quando ele ainda não tem um, ou perdeu o que tinha.
local function anchor(agent: any, data: any): boolean
	local node = if data.nodeId then RouteRuntime.Node(data.nodeId) else nil
	if node and not RouteRuntime.IsAerial(node.id) then
		return true
	end
	data.nodeId = RouteRuntime.NearestNode(agent.RootPart.Position, preference(agent))
	data.fromId = nil
	return data.nodeId ~= nil
end

-- Um passo da ronda: anda até `data.nodeId` e, ao chegar, escolhe o vizinho menos visitado.
local function advance(agent: any, data: any, now: number): string?
	local node = RouteRuntime.Node(data.nodeId)
	if not node then
		return nil
	end

	Movement.SetGoal(agent, node.position)

	local status = Movement.Status(agent)
	if status ~= "arrived" and status ~= "stuck" then
		return nil
	end

	data.visitedAt[node.id] = now
	local reached = if status == "arrived" then node.id else nil

	local nextId = wander(node.id, data.fromId, data.visitedAt)
	if nextId then
		data.fromId = node.id
		data.nodeId = nextId
	else
		-- Beco: solta o nó e espera, para a reeleição não acontecer a 5Hz.
		Movement.Stop(agent)
		data.waitUntil = now + 1
		data.nodeId = nil
		data.fromId = nil
	end

	if status == "arrived" and node.waitTime > 0 then
		data.waitUntil = now + node.waitTime
	end
	return reached
end

function Citizen.Build(): BehaviourTree.Node
	local seated = BehaviourTree.Condition("sentado", function(agent: any): boolean
		return Seats.IsSeated(agent)
	end)

	local rest = BehaviourTree.Action("descansar", function(agent: any): BehaviourTree.Status
		local data = board(agent)
		local now = os.clock()

		-- Sentada que a árvore não agendou também vira descanso. O toque desligado deixou isso raro,
		-- mas o ramo fica: nunca durante a carência, senão levantar rearmaria o descanso no tick
		-- seguinte e o corpo nunca sairia.
		local seat = Seats.SeatOf(agent)
		if seat and data.restSeat ~= seat and now >= data.seatReadyAt then
			data.restSeat = seat
			data.restUntil = now + restSpan()
		end

		if data.restUntil > now then
			data.state = "descansando"
			return "Running"
		end

		-- Levantar é REPETIDO até o corpo sair de fato: a solda destruída não zera o estado sentado
		-- sozinha. A carência é carimbada uma vez só, na transição.
		Seats.Stand(agent)
		if data.restSeat ~= nil then
			data.restSeat = nil
			data.seat = nil
			RouteRuntime.ClearMarch(agent)
			data.seatReadyAt = now + NpcConfig.SEAT_COOLDOWN
		end
		data.state = "levantando"
		return "Running"
	end)

	-- Só escolhe o assento; quem traça o caminho até ele é a marcha, em goSit.
	local wantsSeat = BehaviourTree.Condition("quer assento", function(agent: any): boolean
		local data = board(agent)
		local now = os.clock()
		if now < data.seatReadyAt then
			return false
		end
		if data.seat and Seats.IsFree(data.seat) then
			return true
		end

		local seat = Seats.Nearest(agent.RootPart.Position, NpcConfig.SEAT_SENSE_RADIUS, activeSkips(data, now))
		if not seat then
			return false
		end
		data.seat = seat
		RouteRuntime.ClearMarch(agent)
		return true
	end)

	local goSit = BehaviourTree.Action("ir ao assento", function(agent: any): BehaviourTree.Status
		local data = board(agent)
		local now = os.clock()
		local seat = data.seat
		if not seat or seat.Parent == nil then
			data.seat = nil
			return "Failure"
		end

		-- A marcha é dona do trajeto enquanto devolve true: ela conduz PELO GRAFO e só larga o corpo
		-- perto do alvo, ou quando não há rota que sirva.
		if RouteRuntime.March(agent, seat.Position, now, lane(agent)) then
			data.state = "indo ao assento pela rota"
			return "Running"
		end

		-- Largou longe = assento não servido pela rota. Ir reto daqui é atravessar o mapa.
		local gap = (seat.Position - agent.RootPart.Position).Magnitude
		if gap > NpcConfig.NAV_DIRECT_RADIUS + NpcConfig.SEAT_ANCHOR_RADIUS then
			data.skipUntil[seat] = now + NpcConfig.SEAT_COOLDOWN
			data.seat = nil
			Movement.Stop(agent)
			return "Failure"
		end

		-- Último trecho, e só ele sai da rota.
		data.state = "indo sentar"
		Movement.SetGoal(agent, seat.Position)

		local status = Movement.Status(agent)
		if status == "arrived" then
			Movement.Stop(agent)
			if Seats.Sit(agent, seat) then
				data.restSeat = seat
				data.restUntil = now + restSpan()
				data.state = "sentando"
				return "Success"
			end
		elseif status ~= "stuck" then
			return "Running"
		end

		Movement.Stop(agent)
		data.skipUntil[seat] = now + NpcConfig.SEAT_COOLDOWN
		data.seat = nil
		return "Failure"
	end)

	local patrol = BehaviourTree.Action("patrulhar", function(agent: any): BehaviourTree.Status
		local data = board(agent)
		local now = os.clock()

		if data.waitUntil and now < data.waitUntil then
			data.state = "parado no nó"
			return "Running"
		end
		data.waitUntil = nil
		data.state = "patrulhando"

		if not anchor(agent, data) then
			Movement.Stop(agent)
			data.state = "sem rota"
			return "Running"
		end

		advance(agent, data, now)
		return "Running"
	end)

	return BehaviourTree.Selector("cidadão", {
		BehaviourTree.Sequence("descanso", { seated, rest }),
		BehaviourTree.Sequence("assento", { wantsSeat, goSit }),
		patrol,
	})
end

return Citizen
