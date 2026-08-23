-- Toca os efeitos do SfxConfig por chave. Sem peça o som sai em 2D, na cabeça de quem interagiu;
-- com peça sai preso nela e tem distância. Tudo local: som de interação não replica, e a instância
-- some sozinha.
local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SfxConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SfxConfig"))

local Sfx = {}

-- s até o Debris levar o Sound. Pelo Ended perderia o rabo do reverb, e sem teto uma chave que
-- falhasse em carregar deixaria a instância de pé para sempre.
local LIFETIME = 10

-- s entre dois disparos da MESMA chave: o hover corre a cada pixel, e sem isto viraria zumbido.
local GAP = 0.06

-- Teto do esticamento quando o chamador pede a duração: além disso a mudança de altura entrega mais
-- do que a sincronia esconde.
local FIT_MIN, FIT_MAX = 0.5, 2

-- studs de alcance quando a chave não diz o dela, e onde a atenuação começa. Queda LINEAR, como no
-- Code-Egg: a Inverse padrão da engine cai quase toda nos primeiros studs e o som some perto demais.
local RANGE = 50
local RANGE_MIN = 2

local lastAt = {}

local function build(entry, adornee)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. entry.Id
	sound.Volume = entry.Volume or 0.5
	sound.PlaybackSpeed = entry.Speed or 1
	sound.RollOffMaxDistance = entry.Range or RANGE
	sound.RollOffMinDistance = RANGE_MIN
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = adornee or SoundService
	return sound
end

-- Um disparo. Chave que não existe avisa uma vez e segue: som faltando não pode derrubar a interação
-- que o pediu.
function Sfx.Play(key, adornee, fit)
	local entry = SfxConfig[key]
	if not entry then
		if lastAt[key] == nil then
			lastAt[key] = 0
			warn("[Sfx] chave '" .. tostring(key) .. "' não existe no SfxConfig.")
		end
		return
	end

	local now = os.clock()
	if now - (lastAt[key] or -math.huge) < GAP then
		return
	end
	lastAt[key] = now

	local sound = build(entry, adornee)

	-- `fit` estica a gravação para durar o que o movimento dura: som que acaba antes da peça chegar
	-- entrega que os dois são coisas separadas. TimeLength só existe com o asset já carregado — é o
	-- que o preload garante; sem ele a chave toca no ritmo autorado.
	if fit and fit > 0 and sound.TimeLength > 0 then
		sound.PlaybackSpeed = math.clamp(sound.TimeLength / fit, FIT_MIN, FIT_MAX)
	end

	sound:Play()
	Debris:AddItem(sound, LIFETIME)
end

-- Som preso a um GESTO: quem chama guarda o retorno e o destrói ao soltar, sem Debris, porque o fim
-- é o gesto e não o relógio. `Looped` na chave decide se ele se repete enquanto dura ou toca uma vez
-- até o fim. Sem teto de intervalo: cada aperto tem que poder recomeçar do zero.
function Sfx.Hold(key, adornee)
	local entry = SfxConfig[key]
	if not entry then
		return nil
	end

	local sound = build(entry, adornee)
	sound.Looped = entry.Looped == true
	sound:Play()
	return sound
end

function Sfx.Start()
	-- Sem isto o primeiro disparo de cada chave sai mudo: o asset só começa a baixar no Play, e o
	-- clique já passou quando ele chega.
	local probes = {}
	for _, entry in pairs(SfxConfig) do
		local sound = Instance.new("Sound")
		sound.SoundId = "rbxassetid://" .. entry.Id
		table.insert(probes, sound)
	end

	pcall(function()
		ContentProvider:PreloadAsync(probes)
	end)

	for _, sound in ipairs(probes) do
		sound:Destroy()
	end
end

return Sfx
