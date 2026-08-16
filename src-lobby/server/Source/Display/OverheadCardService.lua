-- Anexa o cartão (BillboardAccessory) ao personagem. Não preenche Image, Class nem Leaderboard —
-- use GetCard(character) para isso.
local OverheadCardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))

local warnedTemplate = false

local function getTemplate()
	local folder = ReplicatedStorage:FindFirstChild(Config.TemplateFolder)
	local sub = folder and folder:FindFirstChild(Config.TemplateSubfolder)
	local template = sub and sub:FindFirstChild(Config.TemplateName)

	if not template and not warnedTemplate then
		warnedTemplate = true
		warn(string.format("[OverheadCardService] Template ausente: ReplicatedStorage.%s.%s.%s", Config.TemplateFolder, Config.TemplateSubfolder, Config.TemplateName))
	end

	return template
end

-- Em R15 o AddAccessory solda por RigidConstraint; o controller do cliente só dirige Weld.
local function rebindAsWeld(accessory)
	local handle = accessory:FindFirstChild(Config.HandleName)
	if not handle or handle:FindFirstChild(Config.WeldName) then
		return
	end

	local character = accessory.Parent
	local head = character and character:FindFirstChild("Head")
	local handleAtt = handle:FindFirstChild(Config.HatAttachmentName)
	local headAtt = head and head:FindFirstChild(Config.HatAttachmentName)

	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("RigidConstraint") then
			if not (head and handleAtt and headAtt) then
				local a0, a1 = child.Attachment0, child.Attachment1
				if a0 and a1 then
					local fromHandle = (a0.Parent == handle)
					handleAtt = fromHandle and a0 or a1
					headAtt = fromHandle and a1 or a0
					head = headAtt.Parent
				end
			end
			child:Destroy()
		end
	end

	if not (head and handleAtt and headAtt) then
		return
	end

	local weld = Instance.new("Weld")
	weld.Name = Config.WeldName
	weld.Part0 = handle
	weld.Part1 = head
	weld.C0 = handleAtt.CFrame
	weld.C1 = headAtt.CFrame
	weld.Parent = handle
end

local function attach(character)
	if character:FindFirstChild(Config.AccessoryName) then
		return
	end

	local humanoid = character:FindFirstChildWhichIsA("Humanoid") or character:WaitForChild("Humanoid", 10)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 10)
	if not (humanoid and head) then
		return
	end

	if not character.Parent then
		return
	end

	local template = getTemplate()
	if not template then
		return
	end

	local accessory = template:Clone()
	accessory.Name = Config.AccessoryName
	humanoid:AddAccessory(accessory)

	rebindAsWeld(accessory)
end

-- nil enquanto o anexo não terminou.
function OverheadCardService.GetCard(character)
	local accessory = character and character:FindFirstChild(Config.AccessoryName)
	local handle = accessory and accessory:FindFirstChild(Config.HandleName)
	local surface = handle and handle:FindFirstChildWhichIsA("SurfaceGui")
	return surface and surface:FindFirstChild(Config.CardName) or nil
end

function OverheadCardService.Start()
	local function track(player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(attach, character)
		end)

		if player.Character then
			task.spawn(attach, player.Character)
		end
	end

	Players.PlayerAdded:Connect(track)

	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
end

return OverheadCardService
