-- Animação das portas, local em cada cliente. O servidor só publica o quanto a porta está
-- aberta; o giro das folhas e das maçanetas é calculado aqui e não replica para ninguém.
local DoorController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local doors = {}
local active = {}
local stepConnection

local function resolveKnob(model, hinge)
	local part = DoorConfig.KnobOf(model, hinge)
	if not part then
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

local function sameLeaves(door, hinges)
	if not door.leaves or #door.leaves ~= #hinges then
		return false
	end

	for index, hinge in ipairs(hinges) do
		if door.leaves[index].part ~= hinge then
			return false
		end
	end

	return true
end

-- As folhas só se movem aqui, então o servidor sempre as devolve fechadas: o que o streaming
-- trouxer de volta serve de referência para a pose e para o sinal de cada folha.
local function resolve(door)
	local hinges = DoorConfig.Hinges(door.model)

	if #hinges == 0 then
		door.leaves = nil
		return false
	end

	if sameLeaves(door, hinges) then
		return true
	end

	local normal = DoorConfig.Normal(hinges)
	local leaves, knob = {}, false

	for index, hinge in ipairs(hinges) do
		local leaf = {
			part = hinge,
			closed = hinge.CFrame,
			pivot = hinge:GetPivot().Position,
			sign = DoorConfig.LeafSign(hinge, normal),
			knob = resolveKnob(door.model, hinge),
		}

		knob = knob or leaf.knob ~= nil
		leaves[index] = leaf
	end

	door.leaves = leaves
	door.hasKnob = knob
	door.angle = 0

	return true
end

local function applyLeaves(door, state)
	for _, leaf in ipairs(door.leaves) do
		local angle = math.rad(leaf.sign * state)
		local rotation = CFrame.new(leaf.pivot) * CFrame.Angles(0, angle, 0) * CFrame.new(-leaf.pivot)
		leaf.part.CFrame = rotation * leaf.closed
	end

	door.angle = state
end

-- C0 vive no espaço da folha, então ela pode estar em qualquer ângulo que a maçaneta gira
-- sempre sobre o próprio eixo. O ângulo é o mesmo para todas: folhas opostas já estão giradas
-- entre si, e o espelho no mundo sai daí.
local function applyKnobs(door, angle)
	for _, leaf in ipairs(door.leaves) do
		local knob = leaf.knob
		if knob then
			local turn = CFrame.new(knob.pivot)
				* CFrame.fromAxisAngle(knob.axis, math.rad(angle))
				* CFrame.new(-knob.pivot)
			knob.joint.C0 = turn * knob.rest
		end
	end
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
		applyLeaves(door, door.from + (door.target - door.from) * eased)

		if door.hasKnob then
			applyKnobs(door, knobAngle(door))
		end

		if door.elapsed >= door.total then
			active[door] = nil
			if door.hasKnob then
				applyKnobs(door, 0)
			end
		end
	end

	if not next(active) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

-- O som sai preso numa peça da folha, não em 2D: porta que abre do outro lado da sala tem que soar
-- do outro lado da sala.
local function voice(door)
	local part = door.model.PrimaryPart or door.model:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end

	if door.target ~= 0 then
		Sfx.Play("DoorOpen", part)
	else
		Sfx.Play(if door.dual then "DualDoorClose" else "DoorClose", part)
	end
end

local function play(door)
	voice(door)
	door.from = door.angle
	door.elapsed = 0
	door.lead = door.hasKnob and DoorConfig.KnobTurn or 0
	door.total = DoorConfig.Total(door.hasKnob, door.duration)
	active[door] = true

	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

local function snap(door)
	active[door] = nil
	applyLeaves(door, door.target)

	if door.hasKnob then
		applyKnobs(door, 0)
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
	-- Cortina usa a mesma convenção de nome, mas estica em vez de girar: é do CurtainController.
	if doors[model] or model.Name:sub(1, #DoorConfig.CurtainPrefix) == DoorConfig.CurtainPrefix then
		return
	end

	local door = {
		model = model,
		dual = model.Name:sub(1, #DoorConfig.DualPrefix) == DoorConfig.DualPrefix,
		angle = 0,
		from = 0,
		target = 0,
		elapsed = 0,
		lead = 0,
		total = 0,
		hasKnob = false,
		duration = DoorConfig.Swing(model),
		knobAngle = DoorConfig.Number(model, "KnobAngle", DoorConfig.KnobAngle),
	}

	doors[model] = door

	-- Guardadas para o ChildRemoved soltar: modelo que sai e volta re-registra, e a conexão antiga
	-- duplicaria o setState a cada ciclo de streaming.
	door.links = {
		model:GetAttributeChangedSignal(DoorConfig.StateAttribute):Connect(function()
			setState(door, targetOf(model), true)
		end),
		-- Com streaming as folhas podem chegar depois do Model.
		model.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				setState(door, targetOf(model), false)
			end
		end),
	}

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
			for _, link in ipairs(door.links) do
				link:Disconnect()
			end
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
