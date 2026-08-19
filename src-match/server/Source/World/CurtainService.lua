-- Estado das cortinas de metal de workspace.Siland_Home.Doors. O servidor só sabe se estão
-- fechadas: publica no atributo do Model e cria o ProximityPrompt na alavanca. Animar a
-- alavanca, a luz e o estiramento das cortinas é do cliente.
local CurtainService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))

local function buildPrompt(curtain, parent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = ""
	prompt.UIOffset = DoorConfig.PromptOffset
	prompt.ClickablePrompt = DoorConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DoorConfig.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = parent

	prompt.Triggered:Connect(function()
		if os.clock() < curtain.readyAt then
			return
		end

		curtain.readyAt = os.clock() + curtain.cycle
		curtain.closed = not curtain.closed
		curtain.model:SetAttribute(DoorConfig.ClosedAttribute, curtain.closed)
	end)
end

local function register(model)
	local lever = model:FindFirstChild(DoorConfig.LeverName)
	if not (lever and lever:IsA("BasePart")) then
		warn("[CurtainService] " .. model:GetFullName() .. " sem " .. DoorConfig.LeverName .. "; ignorada.")
		return
	end

	local span = math.max(#DoorConfig.Curtains(model) - 1, 0) * DoorConfig.CurtainStagger

	local curtain = {
		model = model,
		closed = false,
		readyAt = 0,
		cycle = math.max(DoorConfig.CurtainCloseTime, DoorConfig.CurtainOpenTime) + span,
	}

	model:SetAttribute(DoorConfig.ClosedAttribute, false)
	buildPrompt(curtain, lever)
end

function CurtainService.Start()
	local folder = workspace

	for _, name in ipairs(DoorConfig.Folder) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[CurtainService] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and model.Name:sub(1, #DoorConfig.CurtainPrefix) == DoorConfig.CurtainPrefix then
			register(model)
		end
	end
end

return CurtainService
