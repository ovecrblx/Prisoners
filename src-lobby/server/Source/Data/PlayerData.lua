-- Persistência do jogador (Lobby). Dono do schema.
-- Mesmo store e key do Match: é o mesmo perfil, um servidor de cada vez.
local PlayerData = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local Store

-- Precisa ser igual ao de src-match/server/Source/Data/PlayerData.lua.
local STORE_NAME = RunService:IsStudio() and "ALT_Data_Prisoners" or "Data_Prisoners"

-- Sem userdata (Vector3, Color3, CFrame, Instance): não serializa.
-- Campo com prefixo Match pertence ao outro place; Reconcile não troca o tipo de chave existente.
local TEMPLATE = {
	Dima = 0,
	Shifts = 0,
	BestShifts = 0,
	FirstJoin = 0,
	LastSeen = 0,
	Classes = {},
	EquippedClass = "",
}

local Profiles = {}

-- Atributo é o canal de leitura do cliente; Classes vai como lista separada por vírgula
-- porque atributo não guarda tabela.
local function publish(player, profile)
	player:SetAttribute("Dima", profile.Data.Dima or 0)
	player:SetAttribute("OwnedClasses", table.concat(profile.Data.Classes or {}, ","))
	player:SetAttribute("EquippedClass", profile.Data.EquippedClass or "")
end

local function ownsClass(data, classId)
	for _, owned in ipairs(data.Classes or {}) do
		if owned == classId then
			return true
		end
	end
	return false
end

-- Concessão da classe padrão, no load do perfil. Quem já a tem não recebe de novo, e quem já tem
-- outra equipada fica com a dele: o padrão só preenche o vazio.
local function grantDefaultClass(data)
	local entry = ClassConfig.Default()
	if not entry then
		return
	end

	if not ownsClass(data, entry.Id) then
		table.insert(data.Classes, entry.Id)
	end

	if data.EquippedClass == "" then
		data.EquippedClass = entry.Id
	end
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
	grantDefaultClass(profile.Data)

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

function PlayerData.GetDima(player)
	local profile = Profiles[player]
	return profile and profile.Data.Dima or 0
end

-- false = não creditou. Checar antes de entregar o item da compra.
function PlayerData.AddDima(player, amount)
	if not isSafeNumber(amount) then
		warn("[PlayerData] AddDima recusado: valor inválido (" .. tostring(amount) .. ")")
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Dima += amount
	publish(player, profile)
	return true
end

-- false = não debitou, e nesse caso nada foi cobrado. Checar antes de entregar o item.
function PlayerData.SpendDima(player, amount)
	if not isSafeNumber(amount) or amount < 0 then
		warn("[PlayerData] SpendDima recusado: valor inválido (" .. tostring(amount) .. ")")
		return false
	end

	local profile = Profiles[player]
	if not profile or profile.Data.Dima < amount then
		return false
	end

	profile.Data.Dima -= amount
	publish(player, profile)
	return true
end

function PlayerData.OwnsClass(player, classId)
	local profile = Profiles[player]
	return profile ~= nil and ownsClass(profile.Data, classId)
end

function PlayerData.GetEquippedClass(player)
	local profile = Profiles[player]
	return profile and profile.Data.EquippedClass or ""
end

function PlayerData.AddClass(player, classId)
	local profile = Profiles[player]
	if not profile or type(classId) ~= "string" or ownsClass(profile.Data, classId) then
		return false
	end

	table.insert(profile.Data.Classes, classId)
	publish(player, profile)
	return true
end

-- String vazia desequipa. Classe não possuída é recusada, e trocar pelo que já está equipado
-- devolve false: o retorno é o que decide gravar, e reescrever o mesmo valor é escrita à toa.
function PlayerData.SetEquippedClass(player, classId)
	local profile = Profiles[player]
	if not profile or type(classId) ~= "string" then
		return false
	end
	if classId ~= "" and not ownsClass(profile.Data, classId) then
		return false
	end
	if profile.Data.EquippedClass == classId then
		return false
	end

	profile.Data.EquippedClass = classId
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
