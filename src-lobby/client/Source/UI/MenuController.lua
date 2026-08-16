-- Menu do lobby: os tiles de MainGui.Frame_Home abrem Frame_Class e Frame_Shop.
-- Fecha pelo Frame_Close do painel ou clicando no fundo escurecido.
-- Frame_Dima recebe só hover/press: o painel de compra de diamante ainda não existe.
local MenuController = {}

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Motion = require(script.Parent:WaitForChild("Motion"))

-- Tile em Frame_Home -> painel irmão em MainGui. Scroller recebe o stagger dos cards.
-- AnchorPoint/Position sobrescrevem o Studio enquanto o painel está aberto; Slide é o
-- deslocamento em escala X de onde ele entra e para onde sai; HideHome tira o Frame_Home
-- da tela antes de abrir.
local PANELS = {
	{
		Tile = "Class",
		Panel = "Frame_Class",
		Scroller = "Hud_List",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.01, 0, 0.5, 0),
		Slide = -0.05,
		HideHome = true,
	},
	{ Tile = "Shop", Panel = "Frame_Shop", Scroller = "Hud" },
}

-- Frame_Home está em ZIndex 2 e o ScreenGui usa ZIndexBehavior Sibling: o painel sobe acima dele.
local PANEL_ZINDEX = 60
local BACKDROP_ZINDEX = 55
local BACKDROP_TRANSPARENCY = 0.45
local BLUR_SIZE = 16

-- Escala e inclinação (graus) de entrada/saída do painel; atraso entre cards, em segundos.
local PANEL_START_SCALE = 0.86
local PANEL_EXIT_SCALE = 0.92
local PANEL_TILT = 4
local CARD_START_SCALE = 0.78
local CARD_STAGGER = 0.07
local CARD_INFO_TIME = 0.5

local CLOSE_HOVER_SCALE = 1.12
local CLOSE_HOVER_ROTATION = 90
local DIMA_HOVER_SCALE = 1.09

-- Folga em pixels além da borda esquerda no ponto de descanso do Frame_Home fora da tela.
local HOME_MARGIN = 24

local mainGui
local backdrop
local blur
local home
local homeBase
local homeVisible = true
local active = nil
local pending = nil
local sequence = 0

local function setChrome(visible)
	if visible then
		backdrop.Visible = true
		blur.Enabled = true
		Motion.Tween(backdrop, Motion.Fade, { BackgroundTransparency = BACKDROP_TRANSPARENCY })
		Motion.Tween(blur, Motion.Fade, { Size = BLUR_SIZE })
		return
	end

	Motion.Tween(backdrop, Motion.PanelOut, { BackgroundTransparency = 1 })
	Motion.Tween(blur, Motion.PanelOut, { Size = 0 })

	task.delay(Motion.PanelOut.Time, function()
		if not active and not pending then
			backdrop.Visible = false
			blur.Enabled = false
		end
	end)
end

-- AbsoluteSize é a largura real: o Frame_Home tem UIAspectRatioConstraint, o Size em escala não serve.
local function setHome(visible)
	if homeVisible == visible then
		return 0
	end
	homeVisible = visible

	local goal = homeBase
	if not visible then
		goal = UDim2.new(0, -(home.AbsoluteSize.X + HOME_MARGIN), homeBase.Y.Scale, homeBase.Y.Offset)
	end

	Motion.Tween(home, Motion.Slide, { Position = goal })
	return Motion.Slide.Time
end

local function playCards(entry)
	for index, card in ipairs(entry.Cards) do
		local info = TweenInfo.new(
			CARD_INFO_TIME,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out,
			0,
			false,
			index * CARD_STAGGER
		)

		card.Scale = CARD_START_SCALE
		Motion.Tween(card, info, { Scale = 1 })
	end
end

local function open(entry)
	active = entry
	entry.Token = entry.Token + 1

	entry.Panel.ZIndex = PANEL_ZINDEX
	entry.Panel.AnchorPoint = entry.AnchorPoint
	entry.Panel.Position = entry.Start
	entry.Panel.Rotation = -PANEL_TILT
	entry.Scale.Scale = PANEL_START_SCALE
	Motion.SetFade(entry.Fade, 0)

	if entry.Scroller then
		entry.Scroller.CanvasPosition = Vector2.new()
	end

	entry.Panel.Visible = true

	Motion.Tween(entry.Scale, Motion.PanelIn, { Scale = 1 })
	Motion.Tween(entry.Panel, Motion.PanelIn, { Position = entry.Position, Rotation = 0 })
	Motion.TweenFade(entry.Fade, 1, Motion.Fade)
	playCards(entry)
end

local function close(entry)
	entry.Token = entry.Token + 1
	local token = entry.Token

	if active == entry then
		active = nil
	end

	Motion.Tween(entry.Scale, Motion.PanelOut, { Scale = PANEL_EXIT_SCALE })
	Motion.Tween(entry.Panel, Motion.PanelOut, { Position = entry.Start, Rotation = PANEL_TILT })
	Motion.TweenFade(entry.Fade, 0, Motion.PanelOut)

	task.delay(Motion.PanelOut.Time, function()
		if entry.Token == token then
			entry.Panel.Visible = false
			entry.Panel.ZIndex = entry.BaseZIndex
		end
	end)
end

-- `sequence` invalida abertura ainda pendente pelo slide do Frame_Home.
local function toggle(entry)
	local current = active or pending

	sequence = sequence + 1
	local token = sequence
	pending = nil

	if current == entry then
		if active == entry then
			close(entry)
		end
		setChrome(false)

		task.delay(Motion.PanelOut.Time, function()
			if sequence == token then
				setHome(true)
			end
		end)
		return
	end

	if active then
		close(active)
	end

	setChrome(true)
	local slideTime = setHome(not entry.HideHome)

	if slideTime <= 0 then
		open(entry)
		return
	end

	pending = entry
	task.delay(slideTime, function()
		if sequence == token then
			pending = nil
			open(entry)
		end
	end)
end

local function collectButtons(root)
	local buttons = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			buttons[#buttons + 1] = descendant
		end
	end
	return buttons
end

local function strokeOf(container)
	local background = container:FindFirstChild("Background")
	return background and background:FindFirstChild("UIStroke")
end

local function collectStrokes(root)
	local strokes = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("UIStroke") then
			strokes[#strokes + 1] = descendant
		end
	end
	return strokes
end

local function buildEntry(panel, config)
	local anchorPoint = config.AnchorPoint or panel.AnchorPoint
	local position = config.Position or panel.Position
	local slide = config.Slide or 0

	local entry = {
		Panel = panel,
		Scale = Motion.EnsureScale(panel),
		Fade = Motion.SnapshotFade(panel),
		Scroller = config.Scroller and panel:FindFirstChild(config.Scroller),
		HideHome = config.HideHome or false,
		BaseZIndex = panel.ZIndex,
		AnchorPoint = anchorPoint,
		Position = position,
		Start = UDim2.new(position.X.Scale + slide, position.X.Offset, position.Y.Scale, position.Y.Offset),
		Cards = {},
		Token = 0,
	}

	if entry.Scroller then
		for _, card in ipairs(entry.Scroller:GetChildren()) do
			if card:IsA("GuiObject") then
				entry.Cards[#entry.Cards + 1] = Motion.EnsureScale(card)
			end
		end
	end

	local closeFrame = panel:FindFirstChild("Frame_Close")
	if closeFrame then
		Motion.BindButton(closeFrame, collectButtons(closeFrame), {
			Hover = CLOSE_HOVER_SCALE,
			Rotation = CLOSE_HOVER_ROTATION,
			Stroke = strokeOf(closeFrame),
			OnClick = function()
				if active == entry then
					toggle(entry)
				end
			end,
		})
	end

	panel.Visible = false
	panel.Rotation = 0
	panel.AnchorPoint = anchorPoint
	panel.Position = position
	entry.Scale.Scale = PANEL_START_SCALE
	Motion.SetFade(entry.Fade, 0)

	return entry
end

function MenuController.Init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	mainGui = playerGui:WaitForChild("MainGui")
	home = mainGui:WaitForChild("Frame_Home")
	homeBase = home.Position

	backdrop = Instance.new("TextButton")
	backdrop.Name = "MenuBackdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = BACKDROP_ZINDEX
	backdrop.Visible = false
	backdrop.Parent = mainGui

	blur = Instance.new("BlurEffect")
	blur.Name = "MenuBlur"
	blur.Size = 0
	blur.Enabled = false
	blur.Parent = Lighting

	backdrop.Activated:Connect(function()
		local current = active or pending
		if current then
			toggle(current)
		end
	end)

	local wired = {}

	for _, config in ipairs(PANELS) do
		local tile = home:WaitForChild(config.Tile)
		local panel = mainGui:WaitForChild(config.Panel)
		local entry = buildEntry(panel, config)

		wired[tile] = true
		Motion.BindButton(tile, collectButtons(tile), {
			Stroke = strokeOf(tile),
			OnClick = function()
				toggle(entry)
			end,
		})
	end

	-- Tile sem painel ainda responde ao hover/press, senão parece travado.
	for _, tile in ipairs(home:GetChildren()) do
		if tile:IsA("GuiObject") and not wired[tile] then
			Motion.BindButton(tile, collectButtons(tile), { Stroke = strokeOf(tile) })
		end
	end

	-- Contador de diamante: escala os próprios botões, não o Dima nem o Frame_Dima.
	local dima = mainGui:WaitForChild("Frame_Dima"):WaitForChild("Dima")
	local dimaButtons = collectButtons(dima)
	Motion.BindButton(dimaButtons, dimaButtons, {
		Hover = DIMA_HOVER_SCALE,
		Stroke = collectStrokes(dima),
		ClickButtons = { dima:WaitForChild("HitBox") },
	})
end

return MenuController
