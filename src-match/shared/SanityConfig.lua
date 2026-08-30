--!strict
-- Sanidade do jogador: a escala, os níveis e o que o cartão do HUD mostra em cada um. Quem move o
-- número é o SanityService; aqui mora só o contrato que os dois lados leem.
local SanityConfig = {}

-- Atributo no Player com a sanidade corrente, escrito só pelo servidor.
SanityConfig.Attribute = "Sanity"

SanityConfig.Min = 0
SanityConfig.Max = 100
SanityConfig.Start = 100

-- Níveis do mais alto para o mais baixo. `Min` é o piso: vale o primeiro nível cujo piso o valor
-- alcança. Icon vai para Sanity.Ico, Title para Sanity.Value e Color para Sanity.Background.
SanityConfig.Levels = {
	{
		Id = "normal",
		Min = 60,
		Title = "Lucid",
		Icon = "rbxassetid://109289051599631",
		Color = Color3.fromRGB(65, 100, 255),
	},
	{
		Id = "mid",
		Min = 30,
		Title = "Disturbed",
		Icon = "rbxassetid://132006151131580",
		Color = Color3.fromRGB(232, 51, 35),
	},
	{
		Id = "low",
		Min = 0,
		Title = "Psychotic",
		Icon = "rbxassetid://87358988782936",
		Color = Color3.fromRGB(102, 41, 255),
	},
}

function SanityConfig.Clamp(value: number): number
	return math.clamp(value, SanityConfig.Min, SanityConfig.Max)
end

function SanityConfig.Level(value: number)
	for _, level in ipairs(SanityConfig.Levels) do
		if value >= level.Min then
			return level
		end
	end
	return SanityConfig.Levels[#SanityConfig.Levels]
end

-- Valor de quem lê antes de o serviço publicar: começar cheio erra menos que começar em zero, que
-- mostraria o pior nível no primeiro quadro de todo mundo.
function SanityConfig.Read(player: Player): number
	local value = player:GetAttribute(SanityConfig.Attribute)
	if type(value) == "number" then
		return value
	end
	return SanityConfig.Start
end

return SanityConfig
