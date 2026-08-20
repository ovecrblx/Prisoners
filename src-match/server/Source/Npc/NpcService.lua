--!strict
-- Nasce, repõe e faz pensar os corpos de NPC. Elenco fixo por classe (NpcConfig.SPAWN), id estável
-- pela vida do corpo; a reposição é reação ao Destroy, não varredura. Uma conexão só tica todas as
-- árvores.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
local ShiftConfig = require(Shared:WaitForChild("ShiftConfig"))

local Source = ServerScriptService:WaitForChild("Source")
local Npc = Source:WaitForChild("Npc")
local DoorService = require(Source:WaitForChild("World"):WaitForChild("DoorService"))
local NpcAgent = require(Npc:WaitForChild("NpcAgent"))
local NpcAnimator = require(Npc:WaitForChild("NpcAnimator"))
local BehaviourTree = require(Npc:WaitForChild("BehaviourTree"))
local Movement = require(Npc:WaitForChild("Movement"))

local NpcService = {}

local activeAgents: { [string]: NpcAgent.Agent } = {}
-- Ids que DEVEM existir; só quem está aqui é reposto. Despawn tira daqui antes de destruir.
local wanted: { [string]: string } = {}
local warned: { [string]: boolean } = {}

-- Uma árvore por classe, partilhada: todo estado por corpo mora no blackboard do agente.
local trees: { [string]: BehaviourTree.Node? } = {}
local treeTried: { [string]: boolean } = {}
local roots: { [string]: BehaviourTree.Node } = {}

-- Retenções por chave; qualquer uma segura o pensamento e o corpo. O Route Builder põe a dele
-- enquanto a janela está aberta.
local holds: { [string]: boolean } = {}
local ticker: RBXScriptConnection? = nil

local onAgentDestroyed: (NpcAgent.Agent) -> ()

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

-- FindFirstChild e nunca WaitForChild: sem ReplicatedStorage.Client, a espera pendura o boot.
local function descend(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in ipairs(path) do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function bodyTemplate(class: string): Model?
	local folder = descend(ReplicatedStorage, NpcConfig.BODY_SOURCE)
	local template = folder and folder:FindFirstChild(class)
	if template and template:IsA("Model") then
		return template
	end
	warnOnce(
		"body:" .. class,
		string.format(
			"[NpcService] corpo de %s ausente em ReplicatedStorage.%s; a classe não nasce.",
			class,
			table.concat(NpcConfig.BODY_SOURCE, ".")
		)
	)
	return nil
end

local function spawnMarker(class: string): BasePart?
	local folder = descend(Workspace, NpcConfig.SPAWN_FOLDER)
	local marker = folder and folder:FindFirstChild(class)
	if marker and marker:IsA("BasePart") then
		return marker
	end
	warnOnce(
		"marker:" .. class,
		string.format(
			"[NpcService] marcador de %s ausente em workspace.%s; a classe não nasce.",
			class,
			table.concat(NpcConfig.SPAWN_FOLDER, ".")
		)
	)
	return nil
end

local function bodiesFolder(): Folder
	local folder = Workspace:FindFirstChild(NpcConfig.BODY_FOLDER)
	if not folder then
		local created = Instance.new("Folder")
		created.Name = NpcConfig.BODY_FOLDER
		created.Parent = Workspace
		return created
	end
	return folder :: Folder
end

-- Marcador autorado no ar: o corpo assenta no primeiro sólido abaixo. A folga sai da distância
-- MEDIDA entre o pivô do corpo e a sola dele, então vale com o pivô no HumanoidRootPart ou já no pé.
local function groundPivot(class: string, marker: BasePart, character: Model): CFrame
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { marker, bodiesFolder() }
	params.RespectCanCollide = true

	local drop = Vector3.new(0, -NpcConfig.SPAWN_GROUND_RANGE, 0)
	local hit = Workspace:Raycast(marker.Position, drop, params)
	if not hit then
		warnOnce(
			"ground:" .. class,
			string.format(
				"[NpcService] sem chão sob o marcador de %s em %d studs; nascendo no marcador.",
				class,
				NpcConfig.SPAWN_GROUND_RANGE
			)
		)
		return marker.CFrame
	end

	local bounds, size = character:GetBoundingBox()
	local sole = character:GetPivot().Position.Y - (bounds.Position.Y - size.Y / 2)
	return marker.CFrame.Rotation + hit.Position + Vector3.new(0, sole, 0)
end

-- Classe sem arquivo em Trees/ nasce sem árvore: fica de pé e não pensa, em vez de derrubar o spawn.
local function treeFor(class: string): BehaviourTree.Node?
	if treeTried[class] then
		return trees[class]
	end
	treeTried[class] = true
	local folder = Npc:FindFirstChild("Trees")
	local module = folder and folder:FindFirstChild(class)
	if not module or not module:IsA("ModuleScript") then
		trees[class] = nil
		warnOnce("tree:" .. class, string.format("[NpcService] %s sem árvore em Npc.Trees; só fica de pé.", class))
		return nil
	end
	local ok, built = pcall(function()
		return (require(module) :: any).Build()
	end)
	if not ok then
		warnOnce("tree:" .. class, string.format("[NpcService] árvore de %s falhou: %s", class, tostring(built)))
		return nil
	end
	trees[class] = built
	return built
end

function NpcService.Spawn(class: string, id: string?): NpcAgent.Agent?
	local agentId = id or class
	if activeAgents[agentId] then
		warn(string.format("[NpcService] id %s já está vivo; spawn ignorado.", agentId))
		return nil
	end

	local template = bodyTemplate(class)
	local marker = spawnMarker(class)
	if not template or not marker then
		return nil
	end

	local character = (template :: Model):Clone()
	character.Name = agentId

	-- Animate é LocalScript: em Model do workspace não roda, e replica ~60 filhos por corpo.
	local animate = character:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	-- Ancorar ANTES de pivotar: rig de constraint teleportado solto espalha os membros.
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	character:PivotTo(groundPivot(class, (marker :: BasePart), character))
	character.Parent = bodiesFolder()

	local agent = NpcAgent.new(character, class, agentId, onAgentDestroyed)
	if not agent then
		return nil
	end

	-- O catálogo sai do TEMPLATE: o Animate do clone foi destruído acima.
	NpcAnimator.Attach(agent, template :: Model)

	-- O NPC não aperta prompt: a porta passa a reconhecer o corpo dele por aproximação.
	DoorService.Watch(agent.RootPart)

	activeAgents[agentId] = agent
	wanted[agentId] = class

	local root = treeFor(class)
	if root then
		roots[agentId] = root
	end
	return agent
end

function NpcService.Despawn(id: string)
	wanted[id] = nil
	local agent = activeAgents[id]
	if agent then
		agent:Destroy()
	end
end

-- Retenção por chave: qualquer uma segura o pensamento e para os corpos onde estão.
function NpcService.SetSuspendHold(key: string, active: boolean)
	if active then
		holds[key] = true
	else
		holds[key] = nil
	end
	if next(holds) ~= nil then
		for _, agent in pairs(activeAgents) do
			Movement.Stop(agent)
		end
	end
end

function NpcService.IsSuspended(): boolean
	return next(holds) ~= nil
end

-- Cópia: entregar o índice interno deixaria o chamador mutá-lo por fora.
function NpcService.GetActiveAgents(): { [string]: NpcAgent.Agent }
	return table.clone(activeAgents)
end

function NpcService.GetTreeRoot(id: string): BehaviourTree.Node?
	return roots[id]
end

onAgentDestroyed = function(agent: NpcAgent.Agent)
	Movement.Forget(agent)
	NpcAnimator.Forget(agent)
	DoorService.Unwatch(agent.RootPart)
	if activeAgents[agent.Id] ~= agent then
		return
	end
	activeAgents[agent.Id] = nil
	roots[agent.Id] = nil

	local class = wanted[agent.Id]
	if not class or not ShiftConfig.IsLive() then
		return
	end

	task.delay(NpcConfig.SPAWN_RESPAWN_DELAY, function()
		if wanted[agent.Id] == class and activeAgents[agent.Id] == nil then
			NpcService.Spawn(class, agent.Id)
		end
	end)
end

-- UMA conexão para todas as árvores, com acumulador próprio: o dt do Heartbeat é o do frame, e a
-- árvore pensa a 5Hz.
local function startTicking()
	if ticker then
		return
	end
	local last = os.clock()
	ticker = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < NpcConfig.TICK_INTERVAL then
			return
		end
		local dt = now - last
		last = now
		if next(holds) ~= nil then
			return
		end
		for id, agent in pairs(activeAgents) do
			local root = roots[id]
			if root and agent:IsAlive() then
				local ok, err = pcall(BehaviourTree.Run, root, agent, dt)
				if not ok then
					warnOnce("tick:" .. id, string.format("[NpcService] árvore de %s estourou: %s", id, tostring(err)))
				end
			end
		end
	end)
end

function NpcService.Start()
	if not ShiftConfig.HasOwner() then
		warnOnce(
			"shift",
			string.format(
				"[NpcService] ninguém publica '%s'; assumindo turno %d em andamento.",
				ShiftConfig.LiveAttribute,
				ShiftConfig.GetNumber()
			)
		)
	end
	if not ShiftConfig.IsLive() then
		return
	end

	-- Ordem de Classes, nunca `pairs` sobre SPAWN: id por índice tem que sair igual entre sessões.
	for _, class in ipairs(NpcConfig.Classes) do
		for index = 1, NpcConfig.SPAWN[class] or 0 do
			NpcService.Spawn(class, string.format("%s%d", class, index))
		end
	end

	startTicking()
end

return NpcService
