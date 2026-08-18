-- Visual dos ProximityPrompt em Style Custom. Reproduz o desenho padrão da engine sem o
-- backplate escuro atrás da tecla; medidas, cores, fontes e tempos são os mesmos.
local PromptDisplay = {}

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SCREEN_GUI_NAME = "ProximityPrompts"

-- Medidas do prompt padrão, em pixels.
local PROMPT_SIZE = 72
local ROUND_SIZE = 48
local ROUND_TRANSPARENCY = 0.5
local PROGRESS_SIZE = 58
local PROGRESS_FUZZ = 0.01

local KEY_IMAGE = "rbxasset://textures/ui/Controls/key_single.png"
local KEY_IMAGE_SIZE = UDim2.fromOffset(28, 30)
local TOUCH_IMAGE = "rbxasset://textures/ui/Controls/TouchTapIcon.png"
local TOUCH_IMAGE_SIZE = UDim2.fromOffset(25, 31)
local GAMEPAD_IMAGE_SIZE = UDim2.fromOffset(24, 24)
local GLYPH_IMAGE_SIZE = UDim2.fromOffset(36, 36)
local PROGRESS_IMAGE = "rbxasset://textures/ui/Controls/RadialFill.png"

local CONTENT_COLOR = Color3.new(1, 1, 1)
local ROUND_COLOR = Color3.fromRGB(75, 75, 75)
local TEXT_SIZE = 14
local HOLD_SCALE = 1.33
local HOLD_SCALE_TOUCH = 1.6

local TWEEN_QUICK = TweenInfo.new(0.06, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
local TWEEN_FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_RELEASE = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT_TIME = 0.2

local KEY_IMAGES = {
	[Enum.KeyCode.Backspace] = "rbxasset://textures/ui/Controls/backspace.png",
	[Enum.KeyCode.Return] = "rbxasset://textures/ui/Controls/return.png",
	[Enum.KeyCode.LeftShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.RightShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.Tab] = "rbxasset://textures/ui/Controls/tab.png",
}

local GLYPH_IMAGES = {
	["'"] = "rbxasset://textures/ui/Controls/apostrophe.png",
	[","] = "rbxasset://textures/ui/Controls/comma.png",
	["`"] = "rbxasset://textures/ui/Controls/graveaccent.png",
	["."] = "rbxasset://textures/ui/Controls/period.png",
	[" "] = "rbxasset://textures/ui/Controls/spacebar.png",
}

local KEY_TEXT = {
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.PageUp] = "PgUp",
	[Enum.KeyCode.PageDown] = "PgDn",
	[Enum.KeyCode.Home] = "Home",
	[Enum.KeyCode.End] = "End",
	[Enum.KeyCode.Insert] = "Ins",
	[Enum.KeyCode.Delete] = "Del",
}

local KEY_TEXT_SIZE = {
	[Enum.KeyCode.LeftControl] = 12,
	[Enum.KeyCode.RightControl] = 12,
	[Enum.KeyCode.LeftAlt] = 12,
	[Enum.KeyCode.RightAlt] = 12,
	[Enum.KeyCode.F10] = 12,
	[Enum.KeyCode.F11] = 12,
	[Enum.KeyCode.F12] = 12,
	[Enum.KeyCode.PageUp] = 8,
	[Enum.KeyCode.PageDown] = 8,
	[Enum.KeyCode.Home] = 8,
	[Enum.KeyCode.End] = 10,
	[Enum.KeyCode.Insert] = 10,
	[Enum.KeyCode.Delete] = 10,
}

local function screenGui()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild(SCREEN_GUI_NAME)

	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = SCREEN_GUI_NAME
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.Parent = playerGui
	end

	return gui
end

local function fadeImage(image, fadeOut, fadeIn)
	table.insert(fadeOut, TweenService:Create(image, TWEEN_QUICK, { ImageTransparency = 1 }))
	table.insert(fadeIn, TweenService:Create(image, TWEEN_QUICK, { ImageTransparency = 0 }))
end

local function createProgressGradient(parent, leftSide, fadeOut, fadeIn)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(0.5, 1)
	frame.Position = UDim2.fromScale(leftSide and 0 or 0.5, 0)
	frame.BackgroundTransparency = 1
	frame.ClipsDescendants = true
	frame.Visible = false
	frame.Parent = parent

	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(2, 1)
	image.Position = UDim2.fromScale(leftSide and 0 or -1, 0)
	image.Image = PROGRESS_IMAGE
	image.Parent = frame

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.5 + PROGRESS_FUZZ, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = leftSide and 180 or 0
	gradient.Parent = image

	fadeImage(image, fadeOut, fadeIn)

	return gradient, frame
end

local function createProgressBar(fadeOut, fadeIn)
	local bar = Instance.new("Frame")
	bar.Name = "CircularProgressBar"
	bar.Size = UDim2.fromOffset(PROGRESS_SIZE, PROGRESS_SIZE)
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.BackgroundTransparency = 1

	local leftGradient, leftFrame = createProgressGradient(bar, true, fadeOut, fadeIn)
	local rightGradient, rightFrame = createProgressGradient(bar, false, fadeOut, fadeIn)

	local progress = Instance.new("NumberValue")
	progress.Name = "Progress"
	progress.Parent = bar

	progress.Changed:Connect(function(value)
		local angle = math.clamp(value * 360, 0, 360)
		leftFrame.Visible = value > 0.5
		leftGradient.Rotation = math.clamp(angle, 180, 360)
		rightFrame.Visible = value > PROGRESS_FUZZ
		rightGradient.Rotation = math.clamp(angle, 0, 180)
	end)

	return bar, progress
end

local function createKeyboardFace(prompt, parent, fadeOut, fadeIn)
	local cap = Instance.new("ImageLabel")
	cap.Name = "ButtonImage"
	cap.BackgroundTransparency = 1
	cap.ImageTransparency = 1
	cap.Size = KEY_IMAGE_SIZE
	cap.AnchorPoint = Vector2.new(0.5, 0.5)
	cap.Position = UDim2.fromScale(0.5, 0.5)
	cap.Image = KEY_IMAGE
	cap.Parent = parent
	fadeImage(cap, fadeOut, fadeIn)

	local text = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	local glyph = KEY_IMAGES[prompt.KeyboardKeyCode] or GLYPH_IMAGES[text]

	if glyph then
		local icon = Instance.new("ImageLabel")
		icon.Name = "ButtonGlyph"
		icon.BackgroundTransparency = 1
		icon.ImageTransparency = 1
		icon.Size = GLYPH_IMAGE_SIZE
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Image = glyph
		icon.Parent = parent
		fadeImage(icon, fadeOut, fadeIn)
		return
	end

	text = KEY_TEXT[prompt.KeyboardKeyCode] or text

	if text == nil or text == "" then
		warn("[PromptDisplay] tecla sem visual: " .. tostring(prompt.KeyboardKeyCode))
		return
	end

	local label = Instance.new("TextLabel")
	label.Name = "ButtonText"
	label.AutoLocalize = false
	label.Position = UDim2.fromOffset(0, -1)
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = KEY_TEXT_SIZE[prompt.KeyboardKeyCode] or TEXT_SIZE
	label.BackgroundTransparency = 1
	label.TextTransparency = 1
	label.TextColor3 = CONTENT_COLOR
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Text = text
	label.Parent = parent

	table.insert(fadeOut, TweenService:Create(label, TWEEN_QUICK, { TextTransparency = 1 }))
	table.insert(fadeIn, TweenService:Create(label, TWEEN_QUICK, { TextTransparency = 0 }))
end

local function createFace(prompt, inputType, parent, fadeOut, fadeIn)
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local image = UserInputService:GetImageForKeyCode(prompt.GamepadKeyCode)
		if not image then
			return
		end

		local icon = Instance.new("ImageLabel")
		icon.Name = "ButtonImage"
		icon.BackgroundTransparency = 1
		icon.ImageTransparency = 1
		icon.Size = GAMEPAD_IMAGE_SIZE
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Image = image
		icon.Parent = parent
		fadeImage(icon, fadeOut, fadeIn)
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		local icon = Instance.new("ImageLabel")
		icon.Name = "ButtonImage"
		icon.BackgroundTransparency = 1
		icon.ImageTransparency = 1
		icon.Size = TOUCH_IMAGE_SIZE
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Image = TOUCH_IMAGE
		icon.Parent = parent
		fadeImage(icon, fadeOut, fadeIn)
	else
		createKeyboardFace(prompt, parent, fadeOut, fadeIn)
	end
end

-- Sem o visual da engine, o toque e o clique também perdem o alvo dela.
local function bindInput(prompt, inputType, promptUI)
	if inputType ~= Enum.ProximityPromptInputType.Touch and not prompt.ClickablePrompt then
		return
	end

	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.TextTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Selectable = false
	button.Parent = promptUI

	local held = false

	button.InputBegan:Connect(function(input)
		local touching = input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1

		if touching and input.UserInputState ~= Enum.UserInputState.Change then
			held = true
			prompt:InputHoldBegin()
		end
	end)

	button.InputEnded:Connect(function(input)
		local touching = input.UserInputType == Enum.UserInputType.Touch
			or input.UserInputType == Enum.UserInputType.MouseButton1

		if touching and held then
			held = false
			prompt:InputHoldEnd()
		end
	end)

	promptUI.Active = true
end

local function createPrompt(prompt, inputType, gui)
	local fadeOut, fadeIn = {}, {}
	local holdBegin, holdEnd = {}, {}

	local promptUI = Instance.new("BillboardGui")
	promptUI.Name = "Prompt"
	promptUI.AlwaysOnTop = true
	promptUI.Size = UDim2.fromOffset(PROMPT_SIZE, PROMPT_SIZE)
	promptUI.SizeOffset = Vector2.new(prompt.UIOffset.X / PROMPT_SIZE, prompt.UIOffset.Y / PROMPT_SIZE)

	local inputFrame = Instance.new("Frame")
	inputFrame.Name = "InputFrame"
	inputFrame.Size = UDim2.fromScale(1, 1)
	inputFrame.BackgroundTransparency = 1
	inputFrame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	inputFrame.Parent = promptUI

	local face = Instance.new("Frame")
	face.Size = UDim2.fromScale(1, 1)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.BackgroundTransparency = 1
	face.Parent = inputFrame

	local scale = Instance.new("UIScale")
	scale.Parent = face

	local zoom = inputType == Enum.ProximityPromptInputType.Touch and HOLD_SCALE_TOUCH or HOLD_SCALE
	table.insert(holdBegin, TweenService:Create(scale, TWEEN_FAST, { Scale = zoom }))
	table.insert(holdEnd, TweenService:Create(scale, TWEEN_FAST, { Scale = 1 }))

	local round = Instance.new("Frame")
	round.Name = "RoundFrame"
	round.Size = UDim2.fromOffset(ROUND_SIZE, ROUND_SIZE)
	round.AnchorPoint = Vector2.new(0.5, 0.5)
	round.Position = UDim2.fromScale(0.5, 0.5)
	round.BackgroundColor3 = ROUND_COLOR
	round.BackgroundTransparency = 1
	round.Parent = face

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = round

	table.insert(fadeOut, TweenService:Create(round, TWEEN_QUICK, { BackgroundTransparency = 1 }))
	table.insert(fadeIn, TweenService:Create(round, TWEEN_QUICK, { BackgroundTransparency = ROUND_TRANSPARENCY }))

	createFace(prompt, inputType, face, fadeOut, fadeIn)
	bindInput(prompt, inputType, promptUI)

	local holdBeganConnection, holdEndedConnection

	if prompt.HoldDuration > 0 then
		local bar, progress = createProgressBar(fadeOut, fadeIn)
		bar.Parent = face

		local fill = TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		table.insert(holdBegin, TweenService:Create(progress, fill, { Value = 1 }))
		table.insert(holdEnd, TweenService:Create(progress, TWEEN_RELEASE, { Value = 0 }))

		holdBeganConnection = prompt.PromptButtonHoldBegan:Connect(function()
			for _, tween in ipairs(holdBegin) do
				tween:Play()
			end
		end)

		holdEndedConnection = prompt.PromptButtonHoldEnded:Connect(function()
			for _, tween in ipairs(holdEnd) do
				tween:Play()
			end
		end)
	end

	local triggeredConnection = prompt.Triggered:Connect(function()
		for _, tween in ipairs(fadeOut) do
			tween:Play()
		end
	end)

	local triggerEndedConnection = prompt.TriggerEnded:Connect(function()
		for _, tween in ipairs(fadeIn) do
			tween:Play()
		end
	end)

	promptUI.Adornee = prompt.Parent
	promptUI.Parent = gui

	local ancestryConnection = prompt.AncestryChanged:Connect(function()
		promptUI.Adornee = prompt.Parent
	end)

	for _, tween in ipairs(fadeIn) do
		tween:Play()
	end

	return function()
		if holdBeganConnection then
			holdBeganConnection:Disconnect()
			holdEndedConnection:Disconnect()
		end

		triggeredConnection:Disconnect()
		triggerEndedConnection:Disconnect()
		ancestryConnection:Disconnect()

		for _, tween in ipairs(fadeOut) do
			tween:Play()
		end

		task.delay(FADE_OUT_TIME, function()
			promptUI:Destroy()
		end)
	end
end

function PromptDisplay.Start()
	if not Players.LocalPlayer then
		return
	end

	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end

		local cleanup = createPrompt(prompt, inputType, screenGui())

		local done = Instance.new("BindableEvent")
		local hidden = prompt.PromptHidden:Connect(function()
			done:Fire()
		end)
		local destroying = prompt.Destroying:Connect(function()
			done:Fire()
		end)

		done.Event:Wait()
		hidden:Disconnect()
		destroying:Disconnect()
		done:Destroy()

		cleanup()
	end)
end

return PromptDisplay
