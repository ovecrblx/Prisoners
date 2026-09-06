-- Animação da porta do elevador, local em cada cliente. O servidor só publica se ela está aberta;
-- o curso das folhas é calculado aqui e não replica para ninguém.
-- As duas folhas correm para o MESMO bolso, e cada uma tem o seu curso: a de trás anda quase o
-- dobro da da frente. A fração do curso é a mesma nas duas, então elas partem e param juntas e
-- param empilhadas, em vez de uma empurrar a outra.
local ElevatorController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))

local elevators = {}
local active = {}
local stepConnection
local step

local function apply(entry, alpha)
	entry.alpha = alpha

	for _, leaf in ipairs(entry.leaves) do
		leaf.part.CFrame = leaf.closed + entry.axis * (leaf.travel * alpha)
	end
end

local function sameLeaves(entry, leaves)
	if not entry.leaves or #entry.leaves ~= #leaves then
		return false
	end

	for index, leaf in ipairs(leaves) do
		if entry.leaves[index].part ~= leaf.part then
			return false
		end
	end

	return true
end

-- As folhas só se movem aqui, então o servidor sempre as devolve fechadas: o que o streaming
-- trouxer de volta serve de pose de referência. Só re-guarda quando a peça é outra — re-guardar no
-- meio do curso congelaria a pose animada como se fosse a fechada.
local function resolve(entry)
	local rig = DoorConfig.SlideRig(entry.model)

	if not rig then
		entry.leaves = nil
		return false
	end

	if sameLeaves(entry, rig.leaves) then
		return true
	end

	local leaves = {}
	for index, leaf in ipairs(rig.leaves) do
		leaves[index] = { part = leaf.part, travel = leaf.travel, closed = leaf.part.CFrame }
	end

	entry.axis = rig.axis
	entry.leaves = leaves
	entry.alpha = 0

	return true
end

function step(delta)
	for entry in pairs(active) do
		entry.elapsed = math.min(entry.elapsed + delta, entry.duration)

		local raw = entry.duration > 0 and entry.elapsed / entry.duration or 1
		local eased = TweenService:GetValue(raw, DoorConfig.ElevatorStyle, DoorConfig.ElevatorDirection)
		apply(entry, entry.from + (entry.goal - entry.from) * eased)

		if entry.elapsed >= entry.duration then
			active[entry] = nil
		end
	end

	if not next(active) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function play(entry)
	entry.from = entry.alpha
	entry.goal = entry.open and 1 or 0
	entry.elapsed = 0
	entry.duration = entry.open and DoorConfig.ElevatorOpenTime or DoorConfig.ElevatorCloseTime
	active[entry] = true

	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

local function setState(entry, open, animate)
	entry.open = open

	if not resolve(entry) then
		return
	end

	if animate then
		play(entry)
	else
		active[entry] = nil
		apply(entry, open and 1 or 0)
	end
end

local function published(model)
	return model:GetAttribute(DoorConfig.ElevatorAttribute) == true
end

local function register(model)
	if elevators[model] then
		return
	end

	local entry = {
		model = model,
		open = false,
		alpha = 0,
		from = 0,
		goal = 0,
		elapsed = 0,
		duration = DoorConfig.ElevatorOpenTime,
	}

	elevators[model] = entry

	-- Guardadas para o ChildRemoved soltar: modelo que sai e volta re-registra, e a conexão antiga
	-- duplicaria o setState a cada ciclo de streaming.
	-- Com streaming as folhas podem chegar depois do Model.
	entry.links = {
		model:GetAttributeChangedSignal(DoorConfig.ElevatorAttribute):Connect(function()
			setState(entry, published(model), true)
		end),
		model.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				setState(entry, published(model), false)
			end
		end),
	}

	setState(entry, published(model), false)
end

function ElevatorController.Start()
	local folder = workspace

	for _, name in ipairs(DoorConfig.Folder) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[ElevatorController] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	local function consider(child)
		if child:IsA("Model") and DoorConfig.Kind(child) == "elevator" then
			register(child)
		end
	end

	folder.ChildAdded:Connect(consider)

	folder.ChildRemoved:Connect(function(child)
		local entry = elevators[child]
		if entry then
			for _, link in ipairs(entry.links) do
				link:Disconnect()
			end
			active[entry] = nil
			elevators[child] = nil
		end
	end)

	for _, model in ipairs(folder:GetChildren()) do
		consider(model)
	end
end

return ElevatorController
