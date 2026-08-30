-- Turno e relógio no HUD: Frame_Shift.Shift.Value conta os turnos, e Frame_Hud.Timer mostra a noite
-- passando dentro do turno corrente — Value a hora da marca em que o ciclo está, Pointer o ângulo e
-- Background_01 a cor, esses dois contínuos entre marcas.
-- Nada aqui pergunta ao servidor. O prazo do turno é attribute do workspace e o relógio é o do
-- servidor, então cada cliente conta sozinho e todos contam a mesma hora.
local ShiftHud = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClockConfig = require(Shared:WaitForChild("ClockConfig"))
local ShiftConfig = require(Shared:WaitForChild("ShiftConfig"))

-- Caminho no place: PlayerGui.MainGui.{Frame_Shift.Shift.Value, Frame_Hud.Timer.*}.
local GUI_NAME = "MainGui"
local SHIFT_FRAME_NAME = "Frame_Shift"
local SHIFT_CARD_NAME = "Shift"
local HUD_NAME = "Frame_Hud"
local TIMER_NAME = "Timer"
local VALUE_NAME = "Value"
local POINTER_NAME = "Pointer"
local BACKGROUND_NAME = "Background_01"

local WAIT_TIMEOUT = 20

local function resolve(player)
	local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
	local gui = playerGui and playerGui:WaitForChild(GUI_NAME, WAIT_TIMEOUT)
	local hud = gui and gui:WaitForChild(HUD_NAME, WAIT_TIMEOUT)
	local timer = hud and hud:WaitForChild(TIMER_NAME, WAIT_TIMEOUT)
	if not timer then
		warn("[ShiftHud] " .. GUI_NAME .. "." .. HUD_NAME .. "." .. TIMER_NAME .. " não encontrado.")
		return nil
	end

	local frame = gui and gui:FindFirstChild(SHIFT_FRAME_NAME)
	local card = frame and frame:FindFirstChild(SHIFT_CARD_NAME)

	return {
		hour = timer:FindFirstChild(VALUE_NAME),
		pointer = timer:FindFirstChild(POINTER_NAME),
		background = timer:FindFirstChild(BACKGROUND_NAME),
		shift = card and card:FindFirstChild(VALUE_NAME),
	}
end

-- Última marca já alcançada pela hora corrente. É ela que o texto mostra: as horas entre duas
-- marcas existem no ponteiro e na cor, não no mostrador.
local function markAt(cycle, hour)
	local index = 1
	for position, mark in ipairs(cycle) do
		if hour < mark.Hour then
			break
		end
		index = position
	end
	return index
end

local function sample(cycle, endHour, progress)
	local hour = cycle[1].Hour + (endHour - cycle[1].Hour) * progress

	local index = markAt(cycle, hour)
	local mark = cycle[index]
	local following = cycle[index + 1]
	if not following then
		return hour, mark.Hour, mark.Color
	end

	local span = following.Hour - mark.Hour
	local alpha = if span > 0 then math.clamp((hour - mark.Hour) / span, 0, 1) else 0
	return hour, mark.Hour, mark.Color:Lerp(following.Color, alpha)
end

local function apply(parts, cycle, endHour)
	local hour, marked, color = sample(cycle, endHour, ShiftConfig.Progress())

	if parts.hour then
		local text = ClockConfig.Format(marked)
		if parts.hour.Text ~= text then
			parts.hour.Text = text
		end
	end
	if parts.pointer then
		parts.pointer.Rotation = ClockConfig.PointerOffsetAngle + hour * ClockConfig.DegreesPerHour
	end
	if parts.background then
		parts.background.BackgroundColor3 = color
	end
end

local function applyShift(parts)
	if parts.shift then
		parts.shift.Text = string.format(ClockConfig.ShiftFormat, ShiftConfig.GetNumber())
	end
end

function ShiftHud.Start()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local parts = resolve(player)
	if not parts then
		return
	end

	local cycle, endHour = ClockConfig.Cycle()
	if #cycle < 2 or endHour <= cycle[1].Hour then
		warn("[ShiftHud] ClockConfig precisa de duas marcas ou mais e de EndHour depois delas.")
		return
	end

	applyShift(parts)
	workspace:GetAttributeChangedSignal(ShiftConfig.NumberAttribute):Connect(function()
		applyShift(parts)
		apply(parts, cycle, endHour)
	end)

	apply(parts, cycle, endHour)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < ClockConfig.UpdateInterval then
			return
		end
		elapsed = 0
		apply(parts, cycle, endHour)
	end)
end

return ShiftHud
