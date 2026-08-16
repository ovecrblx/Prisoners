-- Persistência do jogador (Match). O schema é do Lobby.
-- Gold e Wins são campos compartilhados: gravar aqui é o handoff de volta.
local PlayerData = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local Store

-- Precisa ser igual ao de src-lobby/server/Source/Data/PlayerData.lua.
local STORE_NAME = RunService:IsStudio() and "ALT_Data_Prisoners" or "Data_Prisoners"

-- Só o que este place possui. Prefixo Match evita colidir com chave do Lobby.
local TEMPLATE = {
	MatchLevel = 1,
	MatchXP = 0,
}

local Profiles = {}

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

	Profiles[player] = profile
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if not profile then
		return
	end

	Profiles[player] = nil
	profile:EndSession()
end

function PlayerData.Get(player)
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

function PlayerData.AddWins(player, amount)
	if not isSafeNumber(amount) or amount <= 0 then
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Wins = (profile.Data.Wins or 0) + amount
	return true
end

function PlayerData.AddGold(player, amount)
	if not isSafeNumber(amount) then
		warn("[PlayerData] AddGold recusado: valor inválido (" .. tostring(amount) .. ")")
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Gold = (profile.Data.Gold or 0) + amount
	return true
end

function PlayerData.AddXP(player, amount)
	if not isSafeNumber(amount) or amount <= 0 then
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.MatchXP += amount
	return true
end

-- Grava fora do auto-save de 300s. Chamar no fim da partida.
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
