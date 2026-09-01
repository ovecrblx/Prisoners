-- HUD de toque: a MobileGui publicada só liga em aparelho de toque, sem mouse e sem teclado. Dentro
-- dela cada uso tem o próprio Frame — Flashlight, Manual, Right, Left —, todos apagados até o item
-- pedir.
-- O par On/Off de um painel é a AÇÃO, não o estado: com a lanterna apagada aparece On, e acesa
-- aparece Off. Por isso o item nasce com Off escondido — ele nasce desligado, e o que se pode fazer
-- com ele é ligar.
-- Nada aqui sabe o que é lanterna ou caderno; quem liga o toque à ação é o controlador do item, e o
-- que chega a ele é o valor absoluto — ligar ou desligar —, nunca um "alterna": dois toques rápidos
-- convergem em vez de depender da ordem.
-- Nome de instância é lido sem caixa de propósito: a GUI é publicada à mão e não tem teste.
local MobileHud = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local GUI_NAME = "MobileGui"
local GUI_TIMEOUT = 10 -- segundos esperando a GUI publicada no PlayerGui
local ON_NAME = "On"
local OFF_NAME = "Off"

local player = Players.LocalPlayer

local gui
local panels = {}

-- Toque sem mouse e sem teclado. O emulador do Studio move as três de uma vez, então o que vale no
-- aparelho vale no teste.
local function isMobile()
	return UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
		and not UserInputService.KeyboardEnabled
end

local function deepFind(root, name)
	local wanted = string.lower(name)
	for _, item in ipairs(root:GetDescendants()) do
		if string.lower(item.Name) == wanted then
			return item
		end
	end
	return nil
end

-- O Frame do uso pode ser o próprio botão ou trazer um dentro: o place é que decide, e os dois
-- desenhos valem.
local function buttonOf(object)
	if object:IsA("GuiButton") then
		return object
	end
	return object:FindFirstChildWhichIsA("GuiButton", true)
end

local function panelOf(name)
	local entry = panels[name]
	if not entry then
		entry = { visible = false, on = false }
		panels[name] = entry
	end
	return entry
end

local function paint(entry)
	if not (entry.frame and entry.frame.Parent) then
		return
	end
	entry.frame.Visible = entry.visible
	if entry.onButton then
		entry.onButton.Visible = not entry.on
	end
	if entry.offButton then
		entry.offButton.Visible = entry.on
	end
end

-- Reencontra a GUI e repõe o estado de cada painel. Roda de novo a cada respawn: com ResetOnSpawn a
-- MobileGui é destruída e reclonada, e os Frames de antes viram cascas soltas.
local function bind(entry)
	local name = entry.name
	for _, link in ipairs(entry.links or {}) do
		link:Disconnect()
	end
	entry.links = {}

	local frame = gui and deepFind(gui, name)
	entry.frame = frame
	entry.onButton = nil
	entry.offButton = nil

	if not frame then
		warn("[MobileHud] " .. GUI_NAME .. " sem " .. name .. "; esse toque fica sem botão")
		return
	end

	local wantsPair = entry.tapped ~= nil
	local onFrame = wantsPair and deepFind(frame, ON_NAME)
	local offFrame = wantsPair and deepFind(frame, OFF_NAME)
	entry.onButton = onFrame and buttonOf(onFrame) or nil
	entry.offButton = offFrame and buttonOf(offFrame) or nil

	-- Activated e não InputBegan: ele vale para toque, clique e gamepad de uma vez só.
	if entry.onButton then
		table.insert(entry.links, entry.onButton.Activated:Connect(function()
			entry.tapped(true)
		end))
	end
	if entry.offButton then
		table.insert(entry.links, entry.offButton.Activated:Connect(function()
			entry.tapped(false)
		end))
	end

	if entry.pressed then
		local button = buttonOf(frame)
		if button then
			table.insert(entry.links, button.Activated:Connect(function()
				entry.pressed()
			end))
		end
	end

	paint(entry)
end

-- Sem espera aqui: a GUI é procurada como está. Quem espera é o Start, uma vez, e o ChildAdded do
-- PlayerGui cobre a cópia nova do respawn.
local function adopt(found)
	gui = found
	if not gui then
		return nil
	end

	-- Fora do toque a GUI existe e fica desligada: o mouse já tem tecla para tudo o que ela faz.
	gui.Enabled = isMobile()
	for _, entry in pairs(panels) do
		bind(entry)
	end
	return gui
end

local function ensure()
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	return adopt(playerGui and playerGui:FindFirstChild(GUI_NAME))
end

local Panel = {}
Panel.__index = Panel

function Panel:Show()
	local entry = panelOf(self.name)
	entry.visible = true
	ensure()
	paint(entry)
end

function Panel:Hide()
	local entry = panelOf(self.name)
	entry.visible = false
	ensure()
	paint(entry)
end

-- O estado do item, não o do botão: quem escolhe qual dos dois aparece é o paint.
function Panel:SetOn(on)
	local entry = panelOf(self.name)
	entry.on = on == true
	ensure()
	paint(entry)
end

-- `tapped` recebe o valor que o toque pede: On manda true, Off manda false. `pressed` é do painel
-- sem par, como as setas de página — o Frame inteiro é um botão só.
function MobileHud.Panel(name, tapped, pressed)
	local entry = panelOf(name)
	entry.name = name
	entry.tapped = tapped
	entry.pressed = pressed
	if ensure() then
		bind(entry)
	end
	return setmetatable({ name = name }, Panel)
end

function MobileHud.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	adopt(playerGui:WaitForChild(GUI_NAME, GUI_TIMEOUT))
	if not gui then
		warn("[MobileHud] " .. GUI_NAME .. " não apareceu no PlayerGui; o toque fica sem HUD")
	end

	-- O aparelho muda em partida: teclado pareado num tablet, e o botão do emulador no Studio. Medir
	-- só no boot deixaria a GUI ligada para quem já tem teclado, ou apagada para quem acabou de o
	-- desligar.
	for _, name in ipairs({ "TouchEnabled", "MouseEnabled", "KeyboardEnabled" }) do
		UserInputService:GetPropertyChangedSignal(name):Connect(function()
			if gui and gui.Parent then
				gui.Enabled = isMobile()
			end
		end)
	end

	-- ResetOnSpawn destrói e reclona a GUI: sem readotar, os Frames de antes viram cascas soltas e
	-- nenhum toque chega.
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == GUI_NAME then
			adopt(child)
		end
	end)
end

return MobileHud
