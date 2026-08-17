-- Contador de diamante em MainGui.Frame_Dima.Dima.Value. Mostra o atributo Gold subindo
-- até o valor novo, e cresce no eixo X conforme o número de dígitos: o texto é TextScaled,
-- então sem isso o glifo encolhe em vez de a caixa acompanhar.
local DimaCounter = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Motion = require(script.Parent:WaitForChild("Motion"))

local ATTRIBUTE = "Gold"

-- Largura por caractere, em escala X do Dima: 0.15 é o que o place usa para um dígito.
local CHAR_SCALE = 0.15
local MAX_SCALE = 0.9

-- Contagem: duração em segundos e curva. Out desacelera no fim, então o número assenta
-- em vez de travar de repente no total.
local COUNT_TIME = 1.8
local COUNT_STYLE = Enum.EasingStyle.Quad
local COUNT_DIRECTION = Enum.EasingDirection.Out

local player
local value
local baseSize

local displayed = 0
local countFrom, countTarget, elapsed = 0, 0, 0
local digits = 0
local connection

local function draw(amount)
	local text = tostring(amount)
	value.Text = text

	-- Só redimensiona quando muda a quantidade de dígitos: durante a contagem isso
	-- aconteceria a cada frame.
	if #text ~= digits then
		digits = #text
		Motion.Tween(value, Motion.Hover, {
			Size = UDim2.new(math.min(CHAR_SCALE * digits, MAX_SCALE), baseSize.X.Offset, baseSize.Y.Scale, baseSize.Y.Offset),
		})
	end
end

local function step(delta)
	elapsed += delta

	local alpha = TweenService:GetValue(math.min(elapsed / COUNT_TIME, 1), COUNT_STYLE, COUNT_DIRECTION)
	displayed = math.floor(countFrom + (countTarget - countFrom) * alpha + 0.5)
	draw(displayed)

	if elapsed >= COUNT_TIME then
		displayed = countTarget
		draw(displayed)
		connection:Disconnect()
		connection = nil
	end
end

-- Saldo novo durante uma contagem parte do valor exibido, não do total antigo.
local function refresh()
	local target = math.floor(player:GetAttribute(ATTRIBUTE) or 0)
	if target == displayed and not connection then
		return
	end

	countFrom, countTarget, elapsed = displayed, target, 0

	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

function DimaCounter.Init()
	player = Players.LocalPlayer

	local mainGui = player:WaitForChild("PlayerGui"):WaitForChild("MainGui")
	value = mainGui:WaitForChild("Frame_Dima"):WaitForChild("Dima"):WaitForChild("Value")
	baseSize = value.Size

	draw(0)
	refresh()
	player:GetAttributeChangedSignal(ATTRIBUTE):Connect(refresh)
end

return DimaCounter
