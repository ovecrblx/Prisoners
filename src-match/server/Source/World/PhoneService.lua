-- Quem está no telefone de workspace.Siland_Home.interactive.Phone, e só isso. O aparelho é um só
-- na sala, então o servidor guarda o dono da chamada e apaga o prompt enquanto ela dura; o fone
-- subindo ao rosto e a câmera são de cada cliente.
-- Desligar é do cliente porque o gatilho é andar, que só ele vê no quadro do gesto — mas quem
-- escreve o estado é sempre daqui, e pedido de quem não atendeu não passa.
local PhoneService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))
local PhoneConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PhoneConfig"))

local model
local prompt
local user
local links = {}

local function publish(player)
	user = player
	model:SetAttribute(PhoneConfig.UserAttribute, if player then player.UserId else 0)

	if prompt then
		prompt.Enabled = player == nil
	end
end

local function release(player)
	if user ~= player then
		return
	end

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)
	publish(nil)
end

local function answer(player)
	if user then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	publish(player)
	table.insert(links, humanoid.Died:Connect(function()
		release(player)
	end))
	table.insert(links, player.CharacterRemoving:Connect(function()
		release(player)
	end))
end

function PhoneService.Init()
	Remotes.Event(PhoneConfig.HangUpRemote).OnServerEvent:Connect(release)

	Players.PlayerRemoving:Connect(release)
end

function PhoneService.Start()
	local folder = PhoneConfig.Folder(PhoneConfig.ModelWait)
	model = folder and folder:WaitForChild(PhoneConfig.ModelName, PhoneConfig.ModelWait)
	if not model then
		warn("[PhoneService] workspace." .. table.concat(PhoneConfig.Path, ".") .. "." .. PhoneConfig.ModelName .. " não encontrado.")
		return
	end

	local base = model:WaitForChild(PhoneConfig.BaseName, PhoneConfig.ModelWait)
	if not (base and base:IsA("BasePart")) then
		warn("[PhoneService] " .. model:GetFullName() .. " sem " .. PhoneConfig.BaseName .. "; sem prompt.")
		return
	end

	publish(nil)

	prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.UIOffset = PhoneConfig.PromptOffset
	prompt.ClickablePrompt = PhoneConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PhoneConfig.PromptDistance
	prompt.Parent = base

	prompt.Triggered:Connect(answer)
end

return PhoneService
