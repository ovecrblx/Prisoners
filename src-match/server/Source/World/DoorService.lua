-- Estado das portas de workspace.Siland_Home.Doors. O servidor só sabe o ângulo alvo de cada
-- porta: publica no atributo do Model, cria o ProximityPrompt e tira a folha da colisão e das
-- consultas enquanto ela não está fechada. Animar é do cliente.
local DoorService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))

local function setBlocking(door, blocking)
	if door.solid then
		door.hinge.CanCollide = blocking
	end
	if door.queryable then
		door.hinge.CanQuery = blocking
	end
end

-- Sinal do giro que afasta a folha de quem abriu. A folha só se move no cliente, então aqui
-- ela está sempre fechada e a normal é a da porta fechada.
local function swingSign(door, player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return 1
	end

	local hinge = door.hinge
	local normal = hinge.CFrame:VectorToWorldSpace(DoorConfig.FaceAxis(hinge))
	local motion = Vector3.new(0, 1, 0):Cross(hinge.Position - door.pivot):Dot(normal)
	local side = (root.Position - hinge.Position):Dot(normal)

	return motion * side > 0 and -1 or 1
end

local scheduleAutoClose
local setAngle

function setAngle(door, angle)
	door.angle = angle
	door.token += 1
	local token = door.token

	door.model:SetAttribute(DoorConfig.StateAttribute, angle)

	if angle ~= 0 then
		setBlocking(door, false)
	else
		task.delay(door.cycle, function()
			if door.token == token then
				setBlocking(door, true)
			end
		end)
	end

	scheduleAutoClose(door, token)
end

function scheduleAutoClose(door, token)
	if door.angle == 0 or door.autoClose <= 0 then
		return
	end

	task.delay(door.cycle + door.autoClose, function()
		if door.token == token then
			setAngle(door, 0)
		end
	end)
end

local function buildPrompt(door, parent)
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

	prompt.Triggered:Connect(function(player)
		if os.clock() < door.readyAt then
			return
		end

		door.readyAt = os.clock() + door.cycle
		setAngle(door, door.angle ~= 0 and 0 or swingSign(door, player) * door.openAngle)
	end)
end

local function register(model)
	local hinge = model:FindFirstChild(DoorConfig.HingeName)
	if not (hinge and hinge:IsA("BasePart")) then
		return
	end

	local knob = model:FindFirstChild(DoorConfig.KnobName)

	local door = {
		model = model,
		hinge = hinge,
		pivot = hinge:GetPivot().Position,
		solid = hinge.CanCollide,
		queryable = hinge.CanQuery,
		angle = 0,
		token = 0,
		readyAt = 0,
		cycle = DoorConfig.Total(knob ~= nil, DoorConfig.Swing(model)),
		openAngle = math.abs(DoorConfig.Number(model, "OpenAngle", DoorConfig.OpenAngle)),
		autoClose = math.max(DoorConfig.Number(model, "AutoClose", DoorConfig.AutoClose), 0),
	}

	model:SetAttribute(DoorConfig.StateAttribute, 0)
	buildPrompt(door, knob and knob:IsA("BasePart") and knob or hinge)
end

function DoorService.Start()
	local folder = workspace

	for _, name in ipairs(DoorConfig.Folder) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[DoorService] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			register(model)
		end
	end
end

return DoorService
