-- Estado das cortinas de metal de workspace.Siland_Home.Doors. O servidor só sabe se estão
-- fechadas: publica no atributo da alavanca e cria o ProximityPrompt nela. Animar a alavanca, a
-- luz e o estiramento das cortinas é do cliente.
-- Uma alavanca por linha de CurtainLevers, cada uma com o próprio estado: o Model tem mais de uma,
-- e o atributo no Model faria as duas dividirem o mesmo aberto/fechado.
local CurtainService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))

-- A alavanca sobe e desce a cortina; os números do prompt saem do DoorConfig, o título não.
local PROMPT_TITLE = "Lever"

local function buildPrompt(curtain, parent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = PROMPT_TITLE
	prompt.UIOffset = DoorConfig.PromptOffset
	prompt.ClickablePrompt = DoorConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DoorConfig.PromptDistance
	prompt.Parent = parent

	prompt.Triggered:Connect(function()
		if os.clock() < curtain.readyAt then
			return
		end

		curtain.readyAt = os.clock() + curtain.cycle
		curtain.closed = not curtain.closed
		curtain.lever:SetAttribute(DoorConfig.ClosedAttribute, curtain.closed)
	end)
end

local function register(model)
	local built = 0

	for _, spec in ipairs(DoorConfig.CurtainLevers) do
		local rig = DoorConfig.CurtainRig(model, spec)
		if rig then
			local span = math.max(#rig.bars - 1, 0) * DoorConfig.CurtainStagger
			local curtain = {
				lever = rig.lever,
				closed = false,
				readyAt = 0,
				cycle = math.max(DoorConfig.CurtainCloseTime, DoorConfig.CurtainOpenTime) + span,
			}

			rig.lever:SetAttribute(DoorConfig.ClosedAttribute, false)
			buildPrompt(curtain, rig.lever)
			built += 1
		end
	end

	if built == 0 then
		warn("[CurtainService] " .. model:GetFullName() .. " sem alavanca completa; ignorada.")
	end
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
