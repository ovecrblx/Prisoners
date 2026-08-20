--!strict
-- Painel de IA (servidor): publica a árvore de um NPC e o status de cada nó no tick, só para quem
-- passa na allowlist do builder. O traço da árvore custa, então liga com o primeiro espectador e
-- desliga com o último.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))

local Source = ServerScriptService:WaitForChild("Source")
local Remotes = require(Source:WaitForChild("Util"):WaitForChild("Remotes"))
local Npc = Source:WaitForChild("Npc")
local BehaviourTree = require(Npc:WaitForChild("BehaviourTree"))
local NpcService = require(Npc:WaitForChild("NpcService"))

local BrainMonitor = {}

-- Campos do blackboard que sobem ao painel. Lista fechada: o resto é referência de Instance ou
-- tabela viva, que não atravessa remote.
local BOARD_TEXT = { "state", "nodeId", "fromId" }

local watchers: { [Player]: string } = {}
local snapshotEvent: RemoteEvent? = nil
local pumping = false

local function isAuthorized(player: Player): boolean
	return RunService:IsStudio() or NpcConfig.BUILDER_ALLOWLIST[player.UserId] == true
end

local function agentList(): { { [string]: any } }
	local list: { { [string]: any } } = {}
	for id, agent in pairs(NpcService.GetActiveAgents()) do
		table.insert(list, {
			id = id,
			class = agent.Class,
			state = tostring(agent.Blackboard.state or ""),
			alive = agent:IsAlive(),
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function boardOf(agent: any): { [string]: any }
	local data = agent.Blackboard
	local out: { [string]: any } = {}
	for _, key in ipairs(BOARD_TEXT) do
		local value = data[key]
		if value ~= nil then
			out[key] = tostring(value)
		end
	end
	out.seat = if typeof(data.seat) == "Instance" then (data.seat :: Instance).Name else ""
	local rest = if type(data.restUntil) == "number" then data.restUntil - os.clock() else 0
	out.rest = math.max(math.floor(rest * 10) / 10, 0)
	return out
end

-- Uma varredura por intervalo, e o payload é montado UMA vez por agente observado, não por
-- espectador: dois autores olhando o mesmo NPC custam um envio a mais, não um retrato a mais.
local function push()
	local event = snapshotEvent
	if not event then
		return
	end

	local cache: { [string]: any } = {}
	for player, agentId in pairs(watchers) do
		if player.Parent == nil then
			watchers[player] = nil
		else
			local payload = cache[agentId]
			if payload == nil then
				local agent = NpcService.GetActiveAgents()[agentId]
				if agent then
					payload = {
						agentId = agentId,
						board = boardOf(agent),
						status = agent.Blackboard.__trace or {},
					}
				else
					payload = { agentId = agentId, gone = true }
				end
				cache[agentId] = payload
			end
			event:FireClient(player, payload)
		end
	end
end

-- Rechama a si mesma ao morrer: sem isso, um Watch que chegasse entre a última condição do laço e a
-- baixa da marca veria a bomba ainda marcada como viva e o painel congelaria com o traço ligado.
local refreshTracing: () -> ()

refreshTracing = function()
	local watching = next(watchers) ~= nil
	BehaviourTree.SetTracing(watching)
	if watching and not pumping then
		pumping = true
		task.spawn(function()
			while next(watchers) ~= nil do
				task.wait(NpcConfig.BRAIN_PUSH_INTERVAL)
				push()
			end
			pumping = false
			if next(watchers) ~= nil then
				refreshTracing()
			end
		end)
	end
end

local function onInvoke(player: Player, payload: any): any
	if type(payload) ~= "table" or not isAuthorized(player) then
		return { ok = false, reason = "sem permissão" }
	end

	if payload.op == "IsAuthorized" then
		return { ok = true }
	elseif payload.op == "List" then
		return { ok = true, agents = agentList() }
	elseif payload.op == "Tree" then
		local root = if type(payload.agentId) == "string" then NpcService.GetTreeRoot(payload.agentId) else nil
		if not root then
			return { ok = false, reason = "sem árvore" }
		end
		return { ok = true, tree = BehaviourTree.Describe(root) }
	elseif payload.op == "Watch" then
		if type(payload.agentId) == "string" then
			watchers[player] = payload.agentId
		else
			watchers[player] = nil
		end
		refreshTracing()
		return { ok = true }
	end

	return { ok = false, reason = "op desconhecida" }
end

function BrainMonitor.Start()
	snapshotEvent = Remotes.Event("NpcBrainSnapshot")
	Remotes.Function("NpcBrain").OnServerInvoke = onInvoke

	Players.PlayerRemoving:Connect(function(player)
		watchers[player] = nil
		refreshTracing()
	end)
end

return BrainMonitor
