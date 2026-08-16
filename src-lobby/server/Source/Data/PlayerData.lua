-- Persistência do jogador (Lobby). Dono do schema.
-- Mesmo store e key do Match: é o mesmo perfil, um servidor de cada vez.
local PlayerData = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local Store

-- Precisa ser igual ao de src-match/server/Source/Data/PlayerData.lua.
local STORE_NAME = RunService:IsStudio() and "ALT_Data_Prisoners" or "Data_Prisoners"

-- Sem userdata (Vector3, Color3, CFrame, Instance): não serializa.
-- Campo com prefixo Match pertence ao outro place; Reconcile não troca o tipo de chave existente.
local TEMPLATE = {
	Gold = 0,
	Wins = 0,
	FirstJoin = 0,
	LastSeen = 0,
}

local Profiles = {}

local function publish(player, profile)
	player:SetAttribute("Gold", profile.Data.Gold or 0)
end

local function isSafeNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function onPlayerAdded(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player:IsDescendantOf(Players) == false
		end,
	})

	if not profile then
		player:Kick("Não foi possível carregar os teus dados. Tenta entrar de novo.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Os teus dados foram abertos noutro servidor. Volta a entrar.")
	end)

	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		return
	end

	local now = os.time()
	if profile.Data.FirstJoin == 0 then
		profile.Data.FirstJoin = now
	end
	profile.Data.LastSeen = now

	Profiles[player] = profile
	publish(player, profile)
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if not profile then
		return
	end

	profile.Data.LastSeen = os.time()
	Profiles[player] = nil
	profile:EndSession()
end

-- nil enquanto o load não terminou.
function PlayerData.Get(player)
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

function PlayerData.GetGold(player)
	local profile = Profiles[player]
	return profile and profile.Data.Gold or 0
end

-- false = não creditou. Checar antes de entregar o item da compra.
function PlayerData.AddGold(player, amount)
	if not isSafeNumber(amount) then
		warn("[PlayerData] AddGold recusado: valor inválido (" .. tostring(amount) .. ")")
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Gold += amount
	publish(player, profile)
	return true
end

-- Grava fora do auto-save de 300s. Usar em DevProduct e concessão paga.
function PlayerData.Flush(player)
	local profile = Profiles[player]
	if profile then
		profile:Save()
	end
end

function PlayerData.Init()
	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		warn(string.format("[PlayerData] DataStore falhou (%s / %s): %s", tostring(storeName), tostring(profileKey), tostring(message)))
	end)

	Store = ProfileStore.New(STORE_NAME, TEMPLATE)
end

function PlayerData.Start()
	if not Store then
		warn("[PlayerData] Store não inicializado — Init não rodou.")
		return
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerData
