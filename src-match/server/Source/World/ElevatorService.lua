-- Estado da porta do elevador de workspace.Siland_Home.Doors. O servidor só sabe se ela está
-- aberta: publica no atributo do Model, tira as folhas da colisão e das consultas enquanto não
-- está fechada, e põe o prompt no botão de chamada. Correr as folhas é do cliente.
-- Botão e não folha: quem chama o elevador aperta a parede, e a folha corre para longe da mão —
-- prompt preso nela sairia de baixo do cursor no meio do curso.
local ElevatorService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))

local ANCHOR_NAME = "PromptAnchor"

local function setBlocking(elevator, blocking)
	for _, leaf in ipairs(elevator.solid) do
		if leaf.collide then
			leaf.part.CanCollide = blocking
		end
		if leaf.query then
			leaf.part.CanQuery = blocking
		end
	end
end

local setState

function setState(elevator, open)
	elevator.open = open
	elevator.token += 1
	local token = elevator.token

	elevator.model:SetAttribute(DoorConfig.ElevatorAttribute, open)

	if open then
		setBlocking(elevator, false)

		if elevator.autoClose > 0 then
			task.delay(elevator.cycle + elevator.autoClose, function()
				if elevator.token == token then
					setState(elevator, false)
				end
			end)
		end
	else
		task.delay(elevator.cycle, function()
			if elevator.token == token then
				setBlocking(elevator, true)
			end
		end)
	end
end

local function buildPrompt(elevator, call, center)
	local mark = Instance.new("Attachment")
	mark.Name = ANCHOR_NAME
	mark.Position = DoorConfig.CallAnchor(call, center)
	mark.Parent = call

	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = DoorConfig.ElevatorTitle
	prompt.UIOffset = DoorConfig.PromptOffset
	prompt.ClickablePrompt = DoorConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DoorConfig.PromptDistance
	prompt.Parent = mark

	prompt.Triggered:Connect(function()
		if os.clock() < elevator.readyAt then
			return
		end

		elevator.readyAt = os.clock() + elevator.cycle
		setState(elevator, not elevator.open)
	end)
end

local function register(model)
	local rig = DoorConfig.SlideRig(model)
	if not rig then
		warn("[ElevatorService] " .. model:GetFullName() .. " sem duas folhas e o bolso; ignorado.")
		return
	end

	local call = model:FindFirstChild(DoorConfig.ElevatorCall)
	if not (call and call:IsA("BasePart")) then
		warn("[ElevatorService] " .. model:GetFullName() .. " sem o botão " .. DoorConfig.ElevatorCall .. ".")
		return
	end

	local solid, center = {}, Vector3.zero

	for _, leaf in ipairs(rig.leaves) do
		solid[#solid + 1] = { part = leaf.part, collide = leaf.part.CanCollide, query = leaf.part.CanQuery }
		center += leaf.part.Position
	end

	local elevator = {
		model = model,
		solid = solid,
		open = false,
		token = 0,
		readyAt = 0,
		cycle = math.max(DoorConfig.ElevatorOpenTime, DoorConfig.ElevatorCloseTime),
		autoClose = math.max(DoorConfig.Number(model, "AutoClose", DoorConfig.ElevatorAutoClose), 0),
	}

	model:SetAttribute(DoorConfig.ElevatorAttribute, false)
	buildPrompt(elevator, call, center / #rig.leaves)
end

function ElevatorService.Start()
	local folder = workspace

	for _, name in ipairs(DoorConfig.Folder) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[ElevatorService] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") and DoorConfig.Kind(model) == "elevator" then
			register(model)
		end
	end
end

return ElevatorService
