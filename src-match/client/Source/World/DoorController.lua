-- Animação das portas, local em cada cliente. O servidor só publica o ângulo alvo da folha; o
-- giro dela e da maçaneta é calculado aqui e não replica para ninguém.
local DoorController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))

local doors = {}
local active = {}
local stepConnection

local function resolveKnob(model, hinge)
	local part = model:FindFirstChild(DoorConfig.KnobName)
	if not (part and part:IsA("BasePart")) then
		return nil
	end

	local joint
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("JointInstance") and descendant.Part0 == hinge and descendant.Part1 == part then
			joint = descendant
			break
		end
	end

	if not joint then
		return nil
	end

	return {
		joint = joint,
		rest = joint.C0,
		pivot = (hinge.CFrame:Inverse() * part:GetPivot()).Position,
		axis = DoorConfig.FaceAxis(hinge),
	}
end

-- A folha só se move aqui, então o servidor sempre a devolve fechada: o que o streaming
-- trouxer de volta serve de referência.
local function resolve(door)
	local hinge = door.model:FindFirstChild(DoorConfig.HingeName)
	if not (hinge and hinge:IsA("BasePart")) then
		door.part = nil
		return false
	end

	if door.part ~= hinge then
		door.part = hinge
		door.closed = hinge.CFrame
		door.pivot = hinge:GetPivot().Position
		door.knob = resolveKnob(door.model, hinge)
		door.angle = 0
	end

	return true
end

local function applyLeaf(door, angle)
	local rotation = CFrame.new(door.pivot) * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(-door.pivot)
	door.part.CFrame = rotation * door.closed
	door.angle = angle
end

-- C0 vive no espaço do Root, então a folha pode estar em qualquer ângulo que a maçaneta gira
-- sempre sobre o próprio eixo.
local function applyKnob(door, angle)
	local knob = door.knob
	local turn = CFrame.new(knob.pivot) * CFrame.fromAxisAngle(knob.axis, math.rad(angle)) * CFrame.new(-knob.pivot)
	knob.joint.C0 = turn * knob.rest
end

local function knobAngle(door)
	if door.elapsed < DoorConfig.KnobTurn then
		local rise = door.elapsed / DoorConfig.KnobTurn
		return door.knobAngle * TweenService:GetValue(rise, DoorConfig.Easing, DoorConfig.EasingDirection)
	end

	local back = math.clamp((door.elapsed - DoorConfig.KnobTurn) / DoorConfig.KnobReturn, 0, 1)
	return door.knobAngle * (1 - TweenService:GetValue(back, DoorConfig.Easing, DoorConfig.EasingDirection))
end

local function step(delta)
	for door in pairs(active) do
		door.elapsed = math.min(door.elapsed + delta, door.total)

		local leaf = door.duration > 0 and math.clamp((door.elapsed - door.lead) / door.duration, 0, 1) or 1
		local eased = TweenService:GetValue(leaf, DoorConfig.Easing, DoorConfig.EasingDirection)
		applyLeaf(door, door.from + (door.target - door.from) * eased)

		if door.knob then
			applyKnob(door, knobAngle(door))
		end

		if door.elapsed >= door.total then
			active[door] = nil
			if door.knob then
				applyKnob(door, 0)
			end
		end
	end

	if not next(active) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function play(door)
	door.from = door.angle
	door.elapsed = 0
	door.lead = door.knob and DoorConfig.KnobTurn or 0
	door.total = DoorConfig.Total(door.knob ~= nil, door.duration)
	active[door] = true

	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

local function snap(door)
	active[door] = nil
	applyLeaf(door, door.target)

	if door.knob then
		applyKnob(door, 0)
	end
end

local function setState(door, target, animate)
	door.target = target

	if not resolve(door) then
		return
	end

	if animate then
		play(door)
	else
		snap(door)
	end
end

local function targetOf(model)
	local value = model:GetAttribute(DoorConfig.StateAttribute)
	return type(value) == "number" and value or 0
end

local function register(model)
	if doors[model] then
		return
	end

	local door = {
		model = model,
		angle = 0,
		from = 0,
		target = 0,
		elapsed = 0,
		lead = 0,
		total = 0,
		duration = DoorConfig.Swing(model),
		knobAngle = DoorConfig.Number(model, "KnobAngle", DoorConfig.KnobAngle),
	}

	doors[model] = door

	model:GetAttributeChangedSignal(DoorConfig.StateAttribute):Connect(function()
		setState(door, targetOf(model), true)
	end)

	model.ChildAdded:Connect(function(child)
		if child.Name == DoorConfig.HingeName or child.Name == DoorConfig.KnobName then
			setState(door, targetOf(model), false)
		end
	end)

	setState(door, targetOf(model), false)
end

function DoorController.Start()
	local folder = workspace

	for _, name in ipairs(DoorConfig.Folder) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[DoorController] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			register(child)
		end
	end)

	folder.ChildRemoved:Connect(function(child)
		local door = doors[child]
		if door then
			active[door] = nil
			doors[child] = nil
		end
	end)

	for _, model in ipairs(folder:GetChildren()) do
		if model:IsA("Model") then
			register(model)
		end
	end
end

return DoorController
