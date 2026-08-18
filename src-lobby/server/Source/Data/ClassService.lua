-- Compra, equipa e desequipa classe. O cliente só pede: preço, saldo e posse são conferidos
-- aqui, e o resultado volta pelos atributos que o PlayerData publica.
-- Remote em ReplicatedStorage.Remotes.ClassAction: (action, classId).
local ClassService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local EVENT_NAME = "ClassAction"

-- Segundos entre ações aceitas por jogador.
local DEBOUNCE = 0.3

local ActionEvent
local lastAction = setmetatable({}, { __mode = "k" })

local function buy(player, entry)
	if PlayerData.OwnsClass(player, entry.Id) then
		return
	end
	if not PlayerData.SpendDima(player, entry.Price) then
		return
	end

	PlayerData.AddClass(player, entry.Id)

	if PlayerData.GetEquippedClass(player) == "" then
		PlayerData.SetEquippedClass(player, entry.Id)
	end

	PlayerData.Flush(player)
end

local function onAction(player, action, classId)
	if type(action) ~= "string" then
		return
	end

	local now = os.clock()
	if now - (lastAction[player] or 0) < DEBOUNCE then
		return
	end
	lastAction[player] = now

	if action == "Unequip" then
		if PlayerData.SetEquippedClass(player, "") then
			PlayerData.Flush(player)
		end
		return
	end

	local entry = type(classId) == "string" and ClassConfig.Get(classId)
	if not entry then
		return
	end

	if action == "Buy" then
		buy(player, entry)
	elseif action == "Equip" then
		if PlayerData.SetEquippedClass(player, entry.Id) then
			PlayerData.Flush(player)
		end
	end
end

function ClassService.Init()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	ActionEvent = remotes:FindFirstChild(EVENT_NAME)
	if not ActionEvent then
		ActionEvent = Instance.new("RemoteEvent")
		ActionEvent.Name = EVENT_NAME
		ActionEvent.Parent = remotes
	end
end

function ClassService.Start()
	ActionEvent.OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ClassService
