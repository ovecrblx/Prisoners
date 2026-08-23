-- Lâmpadas e teclas de luz, animadas em cada cliente. O servidor só publica se a tecla está ligada;
-- a cor do bulbo, o Beam, o SpotLight e o giro da tecla saem daqui. O sufixo do nome casa `Lamp_<n>`
-- com `Switch_<n>`, e uma tecla acende todas as lâmpadas do mesmo sufixo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LampConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LampConfig"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local LampController = {}

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

local BULB_TWEEN = TweenInfo.new(LampConfig.BulbTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BUTTON_TWEEN = TweenInfo.new(LampConfig.ButtonTime, LampConfig.ButtonStyle, LampConfig.ButtonDirection)

local groups = {}
local watched = {}

local function group(suffix)
	local entry = groups[suffix]

	if not entry then
		entry = { on = LampConfig.StartOn, bulbs = {}, buttons = {} }
		groups[suffix] = entry
	end

	return entry
end

-- O Beam e as luzes são lidos na hora: o streaming pode devolvê-los depois do bulbo, e uma lista
-- guardada no registro ficaria velha.
local function applyBulb(bulb, on, animate)
	local color = if on then LampConfig.BulbOn else LampConfig.BulbOff

	if animate then
		TweenService:Create(bulb, BULB_TWEEN, { Color = color }):Play()
	else
		bulb.Color = color
	end

	for _, item in ipairs(bulb:GetChildren()) do
		if item:IsA("Beam") or item:IsA("Light") then
			item.Enabled = on
		end
	end
end

local function applyButton(button, on, animate)
	local pose = if on then button.on else button.off

	if animate then
		TweenService:Create(button.part, BUTTON_TWEEN, { CFrame = pose }):Play()
	else
		button.part.CFrame = pose
	end
end

local function setState(suffix, on, animate)
	local entry = group(suffix)
	local changed = entry.on ~= on
	entry.on = on

	for _, bulb in ipairs(entry.bulbs) do
		applyBulb(bulb, on, animate)
	end

	for _, button in ipairs(entry.buttons) do
		applyButton(button, on, animate)

		if changed and animate then
			Sfx.Play(if on then "SwitchOn" else "SwitchOff", button.part)
		end
	end
end

-- Atributo ainda não publicado conta como o estado de partida: o cliente pode registrar a tecla
-- antes do servidor escrever nela, e ler nil como desligado apagaria a sala por um quadro.
local function published(model)
	local value = model:GetAttribute(LampConfig.OnAttribute)
	return if value == nil then LampConfig.StartOn else value == true
end

local function registerBulb(part)
	local model = part.Parent
	local suffix = model and LampConfig.Suffix(model.Name, LampConfig.LampPrefix)
	if not (part:IsA("BasePart") and suffix) then
		return
	end

	local entry = group(suffix)

	-- A pasta reanuncia o que já está registrado, e bulbo que o streaming levou e trouxe é peça nova.
	for _, bulb in ipairs(entry.bulbs) do
		if bulb == part then
			return
		end
	end

	table.insert(entry.bulbs, part)
	applyBulb(part, entry.on, false)
end

-- As duas poses saem do pivô de repouso, medido uma vez, e o giro é somado a ele. Medir de novo a
-- cada troca leria a pose já girada e a tecla iria embora somando ângulo.
local function registerSwitch(part)
	local model = part.Parent
	local suffix = model and LampConfig.Suffix(model.Name, LampConfig.SwitchPrefix)
	if not (part:IsA("BasePart") and suffix) then
		return
	end

	local entry = group(suffix)

	for _, button in ipairs(entry.buttons) do
		if button.part == part then
			return
		end
	end

	local rest = part:GetPivot()
	local offset = part.PivotOffset:Inverse()

	table.insert(entry.buttons, {
		part = part,
		off = LampConfig.Pose(rest, LampConfig.ButtonOffAngle) * offset,
		on = LampConfig.Pose(rest, LampConfig.ButtonOnAngle) * offset,
	})

	if not watched[model] then
		watched[model] = model:GetAttributeChangedSignal(LampConfig.OnAttribute):Connect(function()
			setState(suffix, published(model), true)
		end)
	end

	setState(suffix, published(model), false)
end

function LampController.Start()
	local lighting = LampConfig.Folder(LampConfig.LampFolder, FOLDER_WAIT)
	local interactive = LampConfig.Folder(LampConfig.SwitchFolder, FOLDER_WAIT)

	if not (lighting and interactive) then
		warn("[Lamp] pasta do cenário não encontrada.")
		return
	end

	-- Com streaming a pasta chega antes do conteúdo, e ele pode ir e voltar. Evento, não varredura.
	for _, item in ipairs(lighting:GetDescendants()) do
		if item.Name == LampConfig.BulbName then
			registerBulb(item)
		end
	end

	lighting.DescendantAdded:Connect(function(item)
		if item.Name == LampConfig.BulbName then
			registerBulb(item)
		end
	end)

	for _, item in ipairs(interactive:GetDescendants()) do
		if item.Name == LampConfig.ButtonName then
			registerSwitch(item)
		end
	end

	interactive.DescendantAdded:Connect(function(item)
		if item.Name == LampConfig.ButtonName then
			registerSwitch(item)
		end
	end)
end

return LampController
