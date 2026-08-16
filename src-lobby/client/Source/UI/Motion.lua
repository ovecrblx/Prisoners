-- Tweens compartilhados do menu: hover, press e fade de painel por transparência de descendente.
local Motion = {}

local TweenService = game:GetService("TweenService")

-- Presets de easing. Tempo em segundos.
Motion.Hover = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Motion.Press = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Motion.Release = TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
Motion.PanelIn = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
Motion.PanelOut = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
Motion.Fade = TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
Motion.Slide = TweenInfo.new(0.55, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)

-- Multiplicador de UIScale por estado, e do UIStroke no hover.
local HOVER_SCALE = 1.06
local PRESS_SCALE = 0.92
local HOVER_STROKE = 2.2
local HOVER_STROKE_FADE = 0.35

function Motion.Tween(object, info, goal)
	local tween = TweenService:Create(object, info, goal)
	tween:Play()
	return tween
end

function Motion.EnsureScale(object)
	local scale = object:FindFirstChild("MenuScale")
	if not scale or not scale:IsA("UIScale") then
		scale = Instance.new("UIScale")
		scale.Name = "MenuScale"
		scale.Parent = object
	end
	return scale
end

-- Propriedade já invisível não entra no fade: nada a animar e o painel tem centenas de descendentes.
local function addTarget(list, object, property)
	local original = object[property]
	if original < 1 then
		list[#list + 1] = { Object = object, Property = property, Original = original }
	end
end

function Motion.SnapshotFade(root)
	local list = {}
	local objects = root:GetDescendants()
	objects[#objects + 1] = root

	for _, object in ipairs(objects) do
		if object:IsA("GuiObject") then
			addTarget(list, object, "BackgroundTransparency")

			if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
				addTarget(list, object, "TextTransparency")
				addTarget(list, object, "TextStrokeTransparency")
			end
			if object:IsA("ImageLabel") or object:IsA("ImageButton") then
				addTarget(list, object, "ImageTransparency")
			end
			if object:IsA("ScrollingFrame") then
				addTarget(list, object, "ScrollBarImageTransparency")
			end
		elseif object:IsA("UIStroke") then
			addTarget(list, object, "Transparency")
		end
	end

	return list
end

-- alpha 1 = valor original do Studio, alpha 0 = totalmente transparente.
local function goalFor(target, alpha)
	return 1 - (1 - target.Original) * alpha
end

function Motion.SetFade(targets, alpha)
	for _, target in ipairs(targets) do
		target.Object[target.Property] = goalFor(target, alpha)
	end
end

function Motion.TweenFade(targets, alpha, info)
	for _, target in ipairs(targets) do
		Motion.Tween(target.Object, info, { [target.Property] = goalFor(target, alpha) })
	end
end

-- `visual` é o que escala e gira: um GuiObject ou uma lista deles. `buttons` são os
-- GuiButton que disparam o efeito. config.ClickButtons restringe o OnClick a um
-- subconjunto; sem ele, vale a lista toda.
function Motion.BindButton(visual, buttons, config)
	config = config or {}

	local visuals = visual
	if typeof(visuals) == "Instance" then
		visuals = { visuals }
	end

	local units = {}
	for _, object in ipairs(visuals) do
		units[#units + 1] = {
			Object = object,
			Scale = Motion.EnsureScale(object),
			Rotation = object.Rotation,
		}
	end

	local baseScale = config.Base or 1
	local hoverScale = baseScale * (config.Hover or HOVER_SCALE)
	local pressScale = baseScale * (config.PressScale or PRESS_SCALE)
	local hoverRotation = config.Rotation or 0

	local strokes = {}
	local strokeSource = config.Stroke
	if typeof(strokeSource) == "Instance" then
		strokeSource = { strokeSource }
	end
	if type(strokeSource) == "table" then
		for _, stroke in ipairs(strokeSource) do
			strokes[#strokes + 1] = {
				Object = stroke,
				Thickness = stroke.Thickness,
				Transparency = stroke.Transparency,
			}
		end
	end

	local hovering = false
	local pressing = false

	local function refresh()
		local goal = baseScale
		local info = Motion.Release

		if pressing then
			goal = pressScale
			info = Motion.Press
		elseif hovering then
			goal = hoverScale
			info = Motion.Hover
		end

		for _, unit in ipairs(units) do
			Motion.Tween(unit.Scale, info, { Scale = goal })

			if hoverRotation ~= 0 then
				Motion.Tween(unit.Object, info, { Rotation = unit.Rotation + (hovering and hoverRotation or 0) })
			end
		end

		for _, stroke in ipairs(strokes) do
			Motion.Tween(stroke.Object, info, {
				Thickness = hovering and stroke.Thickness * HOVER_STROKE or stroke.Thickness,
				Transparency = hovering and math.max(stroke.Transparency - HOVER_STROKE_FADE, 0) or stroke.Transparency,
			})
		end
	end

	for _, button in ipairs(buttons) do
		button.MouseEnter:Connect(function()
			hovering = true
			refresh()
		end)

		button.MouseLeave:Connect(function()
			hovering = false
			pressing = false
			refresh()
		end)

		button.MouseButton1Down:Connect(function()
			pressing = true
			refresh()
		end)

		button.MouseButton1Up:Connect(function()
			pressing = false
			refresh()
		end)
	end

	if config.OnClick then
		for _, button in ipairs(config.ClickButtons or buttons) do
			button.Activated:Connect(config.OnClick)
		end
	end

	return units
end

return Motion
