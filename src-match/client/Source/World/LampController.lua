-- Lâmpadas e teclas de luz, animadas em cada cliente. O servidor só publica se a tecla está ligada;
-- o brilho do bulbo, o Beam, o SpotLight e o giro da tecla saem daqui. O sufixo do nome casa
-- `Lamp_<sala>` e `Light_Part_<sala>` com `Switch_<sala>`, e uma tecla acende tudo do mesmo sufixo.
-- Duas peças por grupo, com papéis diferentes: o bulbo do `Lamp_` tem cor a escurecer, e o
-- `Light_Part_` é só a luz solta da sala — nele acende e apaga o que está dentro.
-- A cor é do cenário, não daqui: cada bulbo guarda a que tinha ao ser registrado, e acender e
-- apagar só multiplicam essa cor pela fração do estado. Vale igual para o Ambient do Lighting.
-- Névoa e ambiente são do prédio, não de um grupo: saem da fração de PointLight apagados, e é a
-- mesma conta para os dois — apagar levanta o Haze do Atmosphere e escurece o Ambient.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local LampConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LampConfig"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local LampController = {}

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

local BULB_TWEEN = TweenInfo.new(LampConfig.BulbTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BUTTON_TWEEN = TweenInfo.new(LampConfig.ButtonTime, LampConfig.ButtonStyle, LampConfig.ButtonDirection)
local HAZE_TWEEN = TweenInfo.new(LampConfig.HazeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AMBIENT_TWEEN = TweenInfo.new(LampConfig.AmbientTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local groups = {}
local watched = {}
local hazeTween
local ambientTween
local ambientBase

local function group(suffix)
	local entry = groups[suffix]

	if not entry then
		entry = { on = LampConfig.StartOn, bulbs = {}, lights = {}, buttons = {} }
		groups[suffix] = entry
	end

	return entry
end

-- Clareia ou escurece sem trocar a cor: os três canais andam juntos, então matiz e saturação ficam.
local function shade(color, scale)
	return Color3.new(
		math.min(color.R * scale, 1),
		math.min(color.G * scale, 1),
		math.min(color.B * scale, 1)
	)
end

-- O Beam, as luzes e a poeira são lidos na hora: o streaming pode devolvê-los depois do bulbo, e uma
-- lista guardada no registro ficaria velha.
-- Apagar corta o que ia nascer; partícula já no ar vive o próprio Lifetime, e some junto com o
-- facho em vez de sumir com ele.
local function applyBulb(bulb, on, animate)
	local scale = if on then LampConfig.BulbOnScale else LampConfig.BulbOffScale
	local color = shade(bulb.base, scale)

	if animate then
		TweenService:Create(bulb.part, BULB_TWEEN, { Color = color }):Play()
	else
		bulb.part.Color = color
	end

	for _, item in ipairs(bulb.part:GetChildren()) do
		if item:IsA("Beam") or item:IsA("Light") or item:IsA("ParticleEmitter") then
			item.Enabled = on
		end
	end
end

-- Light_Part não tem bulbo nem cor a escurecer: é peça invisível, e o que acende é o que mora
-- dentro dela.
local function applyLight(part, on)
	for _, item in ipairs(part:GetChildren()) do
		if item:IsA("Beam") or item:IsA("Light") or item:IsA("ParticleEmitter") then
			item.Enabled = on
		end
	end
end

-- Quanto do prédio está no escuro, de 0 a 1: cada PointLight de `Light_Part_` vale a mesma fatia.
-- Contado no Enabled das peças, não no estado dos grupos: assim o que o streaming ainda não trouxe
-- simplesmente não vota, em vez de contar como aceso.
local function darkRatio()
	local total, dark = 0, 0

	for _, entry in pairs(groups) do
		for _, part in ipairs(entry.lights) do
			for _, item in ipairs(part:GetChildren()) do
				if item:IsA("PointLight") then
					total += 1
					if not item.Enabled then
						dark += 1
					end
				end
			end
		end
	end

	return if total > 0 then dark / total else 0
end

-- Névoa e ambiente saem da mesma fração e andam em sentidos opostos: apagar as salas levanta o Haze
-- e escurece o Ambient. Nada disto é de um grupo — é do prédio inteiro.
-- O Ambient de partida é lido na primeira passagem, antes de qualquer escrita nossa: é dele que sai
-- o teto, e reler depois pegaria a cor já escurecida.
-- O percurso anterior é cancelado: dois vivos na mesma propriedade brigam pelo valor.
local function refreshAmbience(animate)
	local ratio = darkRatio()
	ambientBase = ambientBase or Lighting.Ambient

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local haze = LampConfig.HazeMax * ratio
	local lift = LampConfig.AmbientOnScale + (LampConfig.AmbientOffScale - LampConfig.AmbientOnScale) * ratio
	local ambient = shade(ambientBase, lift)

	if hazeTween then
		hazeTween:Cancel()
		hazeTween = nil
	end
	if ambientTween then
		ambientTween:Cancel()
		ambientTween = nil
	end

	if animate then
		if atmosphere then
			hazeTween = TweenService:Create(atmosphere, HAZE_TWEEN, { Haze = haze })
			hazeTween:Play()
		end
		ambientTween = TweenService:Create(Lighting, AMBIENT_TWEEN, { Ambient = ambient })
		ambientTween:Play()
	else
		if atmosphere then
			atmosphere.Haze = haze
		end
		Lighting.Ambient = ambient
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

	for _, part in ipairs(entry.lights) do
		applyLight(part, on)
	end

	for _, button in ipairs(entry.buttons) do
		applyButton(button, on, animate)

		if changed and animate then
			Sfx.Play(if on then "SwitchOn" else "SwitchOff", button.part)
		end
	end

	refreshAmbience(animate)
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

	-- A pasta reanuncia o que já está registrado, e bulbo que o streaming levou e trouxe é peça nova;
	-- a mesma varredura solta as peças mortas, senão a lista cresceria um cadáver por ciclo.
	for index = #entry.bulbs, 1, -1 do
		local bulb = entry.bulbs[index]
		if bulb.part == part then
			return
		end
		if bulb.part.Parent == nil then
			table.remove(entry.bulbs, index)
		end
	end

	-- A cor de agora é a do cenário: nada a escreveu ainda, e é dela que sai o aceso e o apagado.
	local bulb = { part = part, base = part.Color }
	table.insert(entry.bulbs, bulb)
	applyBulb(bulb, entry.on, false)
end

local function registerLight(part)
	local suffix = LampConfig.Suffix(part.Name, LampConfig.LightPrefix)
	if not (part:IsA("BasePart") and suffix) then
		return
	end

	local entry = group(suffix)

	for index = #entry.lights, 1, -1 do
		local light = entry.lights[index]
		if light == part then
			return
		end
		if light.Parent == nil then
			table.remove(entry.lights, index)
		end
	end

	table.insert(entry.lights, part)
	applyLight(part, entry.on)
	-- Peça nova muda o total da conta, e ela pode chegar sem tecla nenhuma trocar de estado.
	refreshAmbience(false)
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

	for index = #entry.buttons, 1, -1 do
		local button = entry.buttons[index]
		if button.part == part then
			return
		end
		if button.part.Parent == nil then
			table.remove(entry.buttons, index)
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
		-- Modelo destruído sai do mapa, senão a chave morta ficaria para sempre.
		model.Destroying:Once(function()
			watched[model] = nil
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
	local function consider(item)
		if item.Name == LampConfig.BulbName then
			registerBulb(item)
		elseif LampConfig.Suffix(item.Name, LampConfig.LightPrefix) then
			registerLight(item)
		end
	end

	for _, item in ipairs(lighting:GetDescendants()) do
		consider(item)
	end

	lighting.DescendantAdded:Connect(consider)

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
