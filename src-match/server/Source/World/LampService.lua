-- Estado das teclas de luz de workspace.Siland_Home.interactive. O servidor só publica se a tecla
-- está ligada e cria o ProximityPrompt nela; a lâmpada, o giro da tecla e o som são do cliente.
local LampService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LampConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LampConfig"))

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

local switches = {}

local function buildPrompt(entry, parent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = LampConfig.PromptTitle
	prompt.UIOffset = LampConfig.PromptOffset
	prompt.ClickablePrompt = LampConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = LampConfig.PromptDistance
	prompt.Parent = parent

	prompt.Triggered:Connect(function()
		if os.clock() < entry.readyAt then
			return
		end

		entry.readyAt = os.clock() + LampConfig.ButtonTime
		entry.on = not entry.on
		entry.model:SetAttribute(LampConfig.OnAttribute, entry.on)
	end)
end

local function register(model)
	if switches[model] or not LampConfig.Suffix(model.Name, LampConfig.SwitchPrefix) then
		return
	end

	local button = model:FindFirstChild(LampConfig.ButtonName)
	if not (button and button:IsA("BasePart")) then
		warn("[LampService] " .. model:GetFullName() .. " sem " .. LampConfig.ButtonName .. "; ignorada.")
		return
	end

	local entry = { model = model, on = LampConfig.StartOn, readyAt = 0 }
	switches[model] = entry

	model:SetAttribute(LampConfig.OnAttribute, entry.on)
	buildPrompt(entry, button)
end

function LampService.Start()
	local folder = LampConfig.Folder(LampConfig.SwitchFolder, FOLDER_WAIT)
	if not folder then
		warn("[LampService] workspace." .. table.concat(LampConfig.SwitchFolder, ".") .. " não encontrado.")
		return
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			register(model)
		end
	end
end

return LampService
