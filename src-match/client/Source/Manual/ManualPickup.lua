-- O exemplar parado na mesa, montado no cliente a partir do mesmo template da réplica de mão e com
-- ProximityPrompt local. Cada um coleta a sua: o exemplar some só para quem pegou e volta quando o
-- caderno é devolvido, então a mesa continua servindo quem ainda não passou por ela. Nada disso
-- existe no servidor — quem avisa que pegou é o ManualController.
local ManualPickup = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ManualView = require(script.Parent:WaitForChild("ManualView"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ManualConfig = require(Shared:WaitForChild("ManualConfig"))
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))

local PROMPT_NAME = "ManualPrompt"

local model
local handler

local function pivot()
	local angles = ManualConfig.PickupAngles
	return CFrame.new(ManualConfig.PickupPosition)
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

-- Mesmo estilo dos outros recursos do jogo: Custom, sem texto, desenhado pelo PromptDisplay. Os
-- números saem do DoorConfig porque são os do projeto — uma segunda cópia deles é como divergem.
local function buildPrompt(parent)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
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
		if handler then
			handler()
		end
	end)
end

function ManualPickup.Bind(callback)
	handler = callback
end

function ManualPickup.Show()
	if model then
		return
	end
	local template = ManualView.Template()
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Name = ManualConfig.ModelName
	local handle = clone:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		clone:Destroy()
		warn("[Manual] template sem Handle")
		return
	end

	ManualView.Dress(clone, handle)
	-- Só o Handle ancora: o resto do livro pende dos Motor6D dele, e ancorar página por página
	-- prenderia cada uma onde o PivotTo a deixou, fora da junta.
	handle.Anchored = true
	clone:PivotTo(pivot())
	buildPrompt(handle)

	-- Direto no workspace, fora das pastas do cenário: o exemplar é local e não depende do que o
	-- streaming traz.
	clone.Parent = workspace
	model = clone
end

function ManualPickup.Hide()
	if not model then
		return
	end
	model:Destroy()
	model = nil
end

return ManualPickup
