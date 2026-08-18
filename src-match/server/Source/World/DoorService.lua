-- Estado das portas de workspace.Siland_Home.Doors. O servidor só sabe o quanto cada porta
-- está aberta: publica no atributo do Model e tira as folhas da colisão e das consultas
-- enquanto não estão fechadas. Animar é do cliente.
local DoorService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))
local CollisionService = require(script.Parent:WaitForChild("CollisionService"))

local nearDoors = {}

local function setBlocking(door, blocking)
	for _, leaf in ipairs(door.solid) do
		if leaf.collide then
			leaf.part.CanCollide = blocking
		end
		if leaf.query then
			leaf.part.CanQuery = blocking
		end
	end
end

local scheduleAutoClose
local setState

function setState(door, state)
	door.state = state
	door.token += 1
	local token = door.token

	door.model:SetAttribute(DoorConfig.StateAttribute, state)

	if state ~= 0 then
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
	if door.state == 0 or door.autoClose <= 0 then
		return
	end

	task.delay(door.cycle + door.autoClose, function()
		if door.token == token then
			setState(door, 0)
		end
	end)
end

local function openFrom(door, position)
	setState(door, DoorConfig.SideOf(door.hinges, door.normal, position) * door.openAngle)
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

		if door.state ~= 0 then
			setState(door, 0)
			return
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		openFrom(door, root and root.Position or door.center)
	end)
end

local function nearest(door)
	local closest, best

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if root then
			local distance = (root.Position - door.center).Magnitude
			if not best or distance < best then
				closest, best = root, distance
			end
		end
	end

	return closest, best
end

local function scan(door)
	if os.clock() < door.readyAt then
		return
	end

	local root, distance = nearest(door)

	if door.state == 0 then
		if root and distance <= DoorConfig.OpenRadius then
			door.readyAt = os.clock() + door.cycle
			openFrom(door, root.Position)
		end
	elseif not root or distance > DoorConfig.CloseRadius then
		door.readyAt = os.clock() + door.cycle
		setState(door, 0)
	end
end

local function register(model)
	local hinges = DoorConfig.Hinges(model)
	if #hinges == 0 then
		return
	end

	local solid, center, knob = {}, Vector3.zero, nil

	for _, hinge in ipairs(hinges) do
		solid[#solid + 1] = { part = hinge, collide = hinge.CanCollide, query = hinge.CanQuery }
		center += hinge.Position
		knob = knob or DoorConfig.KnobOf(model, hinge)
	end

	-- Barreira do vão: só entra no grupo. A colisão dela é do place, e a porta não mexe.
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name == DoorConfig.BlockName then
			child.CollisionGroup = CollisionService.Groups.Block
		end
	end

	local door = {
		model = model,
		hinges = hinges,
		normal = DoorConfig.Normal(hinges),
		center = center / #hinges,
		solid = solid,
		state = 0,
		token = 0,
		readyAt = 0,
		cycle = DoorConfig.Total(knob ~= nil, DoorConfig.Swing(model)),
		openAngle = math.abs(DoorConfig.Number(model, "OpenAngle", DoorConfig.OpenAngle)),
		autoClose = math.max(DoorConfig.Number(model, "AutoClose", DoorConfig.AutoClose), 0),
	}

	model:SetAttribute(DoorConfig.StateAttribute, 0)

	if model.Name:sub(1, #DoorConfig.DualPrefix) == DoorConfig.DualPrefix then
		nearDoors[#nearDoors + 1] = door
	else
		buildPrompt(door, knob or hinges[1])
	end
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

	if #nearDoors == 0 then
		return
	end

	task.spawn(function()
		while true do
			task.wait(DoorConfig.ScanInterval)
			for _, door in ipairs(nearDoors) do
				scan(door)
			end
		end
	end)
end

return DoorService
