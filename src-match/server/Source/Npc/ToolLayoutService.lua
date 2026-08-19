--!strict
-- Estado das janelas das ferramentas de autoria, por jogador. Hoje só a barra do dock; a
-- persistência de layout de janela entra aqui quando houver ferramenta que a use.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))
local Remotes = require(ServerScriptService:WaitForChild("Source"):WaitForChild("Util"):WaitForChild("Remotes"))
local SlotStorage = require(ServerScriptService:WaitForChild("Source"):WaitForChild("Util"):WaitForChild("SlotStorage"))

local ToolLayoutService = {}

-- Sem sufixo de Studio de propósito: o estado das abas atravessa Play -> Edit -> servidor
-- publicado. É preferência de ferramenta, não dado de jogo.
local STORE_NAME = "NpcDockState_v1"

-- Chaves de janela aceitas. O cliente manda a barra inteira e o que não estiver aqui é podado,
-- senão uma ferramenta removida deixaria lixo no registro para sempre.
local DOCK_KEYS: { [string]: boolean } = {
	routes = true,
}

-- s entre gravações do mesmo jogador; o cliente já faz debounce, isto é o teto do servidor.
local WRITE_GAP = 5

local store: SlotStorage.Store? = nil
local cache: { [number]: { [string]: boolean } } = {}
local lastWrite: { [number]: number } = {}

local function getStore(): SlotStorage.Store
	if not store then
		store = SlotStorage.new(STORE_NAME)
	end
	return store :: SlotStorage.Store
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

-- Mesma lista do Route Builder: quem edita rota é quem tem ferramenta.
local function isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return NpcConfig.BUILDER_ALLOWLIST[player.UserId] == true
end

local function prune(raw: any): { [string]: boolean }
	local dock: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return dock
	end
	for key, open in pairs(raw) do
		if DOCK_KEYS[key] and open == true then
			dock[key] = true
		end
	end
	return dock
end

local function load(player: Player): { [string]: boolean }
	local cached = cache[player.UserId]
	if cached then
		return cached
	end

	local ok, record = getStore():Load(keyFor(player))
	local dock = prune(if ok and type(record) == "table" then record.dock else nil)
	cache[player.UserId] = dock
	return dock
end

local function save(player: Player, dock: { [string]: boolean })
	local userId = player.UserId
	cache[userId] = dock

	local now = os.clock()
	if now - (lastWrite[userId] or -math.huge) < WRITE_GAP then
		return
	end
	lastWrite[userId] = now

	task.spawn(function()
		getStore():Save(keyFor(player), function()
			return { dock = dock }
		end)
	end)
end

local function onInvoke(player: Player, action: any, _name: any, payload: any): any
	if not isAuthorized(player) then
		return nil
	end

	if action == "dock_get" then
		return { dock = load(player) }
	elseif action == "dock_set" then
		save(player, prune(payload))
		return { ok = true }
	end

	return nil
end

function ToolLayoutService.Start()
	Remotes.Function("ToolLayout").OnServerInvoke = onInvoke

	Players.PlayerRemoving:Connect(function(player)
		local dock = cache[player.UserId]
		cache[player.UserId] = nil
		lastWrite[player.UserId] = nil

		-- Última escrita sem o teto de intervalo: o jogador já não volta a mandar nada.
		if dock then
			task.spawn(function()
				getStore():Save(keyFor(player), function()
					return { dock = dock }
				end)
			end)
		end
	end)
end

return ToolLayoutService
