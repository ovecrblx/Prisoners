-- Animação das cortinas de metal, local em cada cliente. O servidor só publica se estão
-- fechadas; a alavanca, a luz e o estiramento das barras são calculados aqui.
local CurtainController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local curtains = {}
local active = {}
local stepConnection
local step

-- Size cresce a partir do centro, então esticar sozinho subiria a barra junto. Compensar
-- metade do crescimento no CFrame prende o topo e joga tudo para baixo. A conta sai sempre da
-- pose guardada, nunca da anterior: incremental acumula erro e a barra escorrega.
local function applyBar(bar, height)
	bar.part.Size = Vector3.new(bar.size.X, height, bar.size.Z)
	bar.part.CFrame = bar.base * CFrame.new(0, (bar.size.Y - height) / 2, 0)
	bar.height = height
end

local function applyLever(entry, throw)
	entry.throw = throw

	local eased = TweenService:GetValue(math.clamp(throw, 0, 1), DoorConfig.LeverStyle, DoorConfig.LeverDirection)
	entry.lever:PivotTo(entry.off:Lerp(entry.on, eased))
end

local function applyLight(entry, light)
	entry.light = light

	if entry.indicator then
		entry.indicator.Color = DoorConfig.IndicatorOff:Lerp(DoorConfig.IndicatorOn, math.clamp(light, 0, 1))
	end
end

local function sameBars(entry, parts)
	if not entry.bars or #entry.bars ~= #parts then
		return false
	end

	for index, part in ipairs(parts) do
		if entry.bars[index].part ~= part then
			return false
		end
	end

	return true
end

-- As barras só se esticam aqui, então o servidor sempre as devolve recolhidas: o que o
-- streaming trouxer de volta serve de pose de referência.
local function resolve(entry)
	local lever = entry.model:FindFirstChild(DoorConfig.LeverName)
	local parts = DoorConfig.Curtains(entry.model)

	if not (lever and lever:IsA("BasePart")) or #parts == 0 then
		entry.bars = nil
		return false
	end

	if entry.lever == lever and sameBars(entry, parts) then
		return true
	end

	local rest = lever:GetPivot()
	entry.lever = lever
	entry.off = DoorConfig.LeverPose(rest, DoorConfig.LeverOffAngle)
	entry.on = DoorConfig.LeverPose(rest, DoorConfig.LeverOnAngle)
	entry.indicator = entry.model:FindFirstChild(DoorConfig.IndicatorName)
	entry.throw = 0
	entry.light = 0

	local bars = {}
	for index, part in ipairs(parts) do
		bars[index] = {
			part = part,
			base = part.CFrame,
			size = part.Size,
			height = part.Size.Y,
			delay = (index - 1) * DoorConfig.CurtainStagger,
		}
	end

	entry.bars = bars

	return true
end

local function targetHeight(closed)
	return closed and DoorConfig.CloseHeight or DoorConfig.OpenHeight
end

local function snap(entry)
	active[entry] = nil

	local goal = entry.closed and 1 or 0
	applyLever(entry, goal)
	applyLight(entry, goal)

	for _, bar in ipairs(entry.bars) do
		applyBar(bar, targetHeight(entry.closed))
	end
end

local function play(entry)
	entry.elapsed = 0
	entry.throwFrom = entry.throw
	entry.lightFrom = entry.light
	entry.goal = entry.closed and 1 or 0

	if entry.closed then
		entry.duration = DoorConfig.CurtainCloseTime
		entry.style = DoorConfig.CurtainCloseStyle
		entry.direction = DoorConfig.CurtainCloseDirection
	else
		entry.duration = DoorConfig.CurtainOpenTime
		entry.style = DoorConfig.CurtainOpenStyle
		entry.direction = DoorConfig.CurtainOpenDirection
	end

	entry.total = DoorConfig.LeverTime

	for _, bar in ipairs(entry.bars) do
		bar.from = bar.height
		bar.to = targetHeight(entry.closed)
		entry.total = math.max(entry.total, bar.delay + entry.duration)
	end

	-- Depois de `entry.total` fechar, que é a duração REAL do movimento: o escalonamento das barras
	-- estica o curso além do tempo de uma barra só.
	-- Dois sons, um por evento. A alavanca estala na `Right Root`, onde o jogador interage, no ritmo
	-- autorado — é impacto, não curso. A cortina sai da primeira barra e é esticada para caber no
	-- movimento. Fechar é descer, abrir é subir.
	local closing = entry.closed
	Sfx.Play(if closing then "LeverDown" else "LeverUp", entry.lever)
	Sfx.Play(if closing then "CurtainDown" else "CurtainUp", entry.bars[1].part, entry.total)

	active[entry] = true

	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

function step(delta)
	for entry in pairs(active) do
		entry.elapsed = math.min(entry.elapsed + delta, entry.total)

		local throw = math.clamp(entry.elapsed / DoorConfig.LeverTime, 0, 1)
		applyLever(entry, entry.throwFrom + (entry.goal - entry.throwFrom) * throw)

		-- A luz troca no meio do curso da alavanca, não no começo nem no fim.
		local switch = DoorConfig.LeverTime * DoorConfig.IndicatorSwitch
		local light = math.clamp((entry.elapsed - switch) / DoorConfig.IndicatorTime, 0, 1)
		applyLight(entry, entry.lightFrom + (entry.goal - entry.lightFrom) * light)

		for _, bar in ipairs(entry.bars) do
			local alpha = math.clamp((entry.elapsed - bar.delay) / entry.duration, 0, 1)
			local eased = TweenService:GetValue(alpha, entry.style, entry.direction)
			applyBar(bar, bar.from + (bar.to - bar.from) * eased)
		end

		if entry.elapsed >= entry.total then
			active[entry] = nil
		end
	end

	if not next(active) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function setState(entry, closed, animate)
	entry.closed = closed

	if not resolve(entry) then
		return
	end

	if animate then
		play(entry)
	else
		snap(entry)
	end
end

local function register(model)
	if curtains[model] then
		return
	end

	local entry = {
		model = model,
		closed = model:GetAttribute(DoorConfig.ClosedAttribute) == true,
		throw = 0,
		throwFrom = 0,
		light = 0,
		lightFrom = 0,
		goal = 0,
		elapsed = 0,
		total = 0,
		duration = DoorConfig.CurtainOpenTime,
		style = DoorConfig.CurtainOpenStyle,
		direction = DoorConfig.CurtainOpenDirection,
	}

	curtains[model] = entry

	-- Guardadas para o ChildRemoved soltar: modelo que sai e volta re-registra, e a conexão antiga
	-- duplicaria o setState a cada ciclo de streaming.
	entry.links = {
		model:GetAttributeChangedSignal(DoorConfig.ClosedAttribute):Connect(function()
			setState(entry, model:GetAttribute(DoorConfig.ClosedAttribute) == true, true)
		end),
		-- Com streaming as peças podem chegar depois do Model.
		model.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				setState(entry, entry.closed, false)
			end
		end),
	}

	setState(entry, entry.closed, false)
end

function CurtainController.Start()
	local folder = workspace

	for _, name in ipairs(DoorConfig.Folder) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[CurtainController] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	local function consider(child)
		if child:IsA("Model") and child.Name:sub(1, #DoorConfig.CurtainPrefix) == DoorConfig.CurtainPrefix then
			register(child)
		end
	end

	folder.ChildAdded:Connect(consider)

	folder.ChildRemoved:Connect(function(child)
		local entry = curtains[child]
		if entry then
			for _, link in ipairs(entry.links) do
				link:Disconnect()
			end
			active[entry] = nil
			curtains[child] = nil
		end
	end)

	for _, model in ipairs(folder:GetChildren()) do
		consider(model)
	end
end

return CurtainController
