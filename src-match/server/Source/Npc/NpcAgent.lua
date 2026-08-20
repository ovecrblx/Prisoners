--!strict
-- Um corpo de NPC vivo. Recebe o Model já posicionado, parentado e ANCORADO; daqui em diante é
-- dono da física, das conexões e de uma morte só.
local ServerScriptService = game:GetService("ServerScriptService")

local Source = ServerScriptService:WaitForChild("Source")
local CollisionService = require(Source:WaitForChild("World"):WaitForChild("CollisionService"))

local NpcAgent = {}
NpcAgent.__index = NpcAgent

export type Agent = {
	Id: string,
	Class: string,
	Character: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Blackboard: { [string]: any },
	IsAlive: (self: Agent) -> boolean,
	Destroy: (self: Agent) -> (),
}

function NpcAgent.new(character: Model, class: string, id: string, onDestroyed: ((Agent) -> ())?): Agent?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		warn(string.format("[NpcAgent] %s sem Humanoid ou HumanoidRootPart; corpo descartado.", id))
		character:Destroy()
		return nil
	end

	local self = setmetatable({
		Id = id,
		Class = class,
		Character = character,
		Humanoid = humanoid,
		RootPart = root,
		-- Memória da árvore, server-only e com a vida do corpo: nada aqui replica.
		Blackboard = {},
		_connections = {},
		_onDestroyed = onDestroyed,
		_dead = false,
	}, NpcAgent) :: any

	if character.PrimaryPart == nil then
		character.PrimaryPart = root
	end

	-- Grupo ANTES de soltar a física: um frame no grupo errado é um frame empurrando o jogador.
	local group = CollisionService.Groups.Character
	local function assign(instance: Instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = group
		end
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		assign(descendant)
	end
	self:_bind(character.DescendantAdded:Connect(assign))

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	-- Servidor dono da simulação: sem isto a posição do corpo vira o que o cliente reportar.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	self:_bind(humanoid.Died:Connect(function()
		self:Destroy()
	end))
	self:_bind(character.Destroying:Connect(function()
		self:Destroy()
	end))

	return self :: Agent
end

function NpcAgent._bind(self: any, connection: RBXScriptConnection): RBXScriptConnection
	table.insert(self._connections, connection)
	return connection
end

function NpcAgent.IsAlive(self: any): boolean
	return not self._dead and self.Character.Parent ~= nil and self.Humanoid.Health > 0
end

-- Idempotente por `_dead`: Died, Destroying e Despawn chegam todos aqui.
function NpcAgent.Destroy(self: any)
	if self._dead then
		return
	end
	self._dead = true

	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)

	if self.Character.Parent ~= nil then
		self.Character:Destroy()
	end

	local callback = self._onDestroyed
	self._onDestroyed = nil
	if callback then
		callback(self)
	end
end

return NpcAgent
