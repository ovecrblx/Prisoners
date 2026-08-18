-- Contrato das portas, lido pelo servidor e pelo cliente. O servidor publica o estado e usa
-- os tempos para saber quando o giro acabou; o cliente usa os mesmos tempos para animar.
local DoorConfig = {}

-- Estrutura esperada no place: gira só o `Root`, e o que estiver soldado nele vai junto; o
-- `PivotOffset` dele é a dobradiça. `Animate` soldado no `Root` é a maçaneta. Model sem
-- `Root` não é porta ainda.
DoorConfig.Folder = { "Siland_Home", "Doors" }
DoorConfig.HingeName = "Root"
DoorConfig.KnobName = "Animate"
-- Estado publicado pelo servidor: ângulo alvo da folha em graus, 0 fechada. O sinal é o lado,
-- decidido por quem abriu, então vai junto com o estado numa escrita só.
DoorConfig.StateAttribute = "Angle"

-- Padrão de cada porta, sobrescrito por atributo de mesmo nome no Model. OpenAngle é módulo:
-- a porta sempre foge do jogador. AutoClose em segundos; 0 deixa a porta aberta.
DoorConfig.OpenAngle = 90
DoorConfig.Duration = 0.6
DoorConfig.AutoClose = 0
DoorConfig.KnobAngle = 35

-- Maçaneta: sobe até o ângulo, e volta ao repouso enquanto a folha ainda gira.
DoorConfig.KnobTurn = 0.18
DoorConfig.KnobReturn = 0.32

DoorConfig.Easing = Enum.EasingStyle.Quad
DoorConfig.EasingDirection = Enum.EasingDirection.Out

-- Style Custom: a engine não desenha nada, nem o fundo escuro atrás da tecla. Quem desenha é
-- o PromptDisplay do cliente.
-- Clicável só no toque: no PC o alvo de clique cobre o prompt inteiro e engole o arrasto do
-- mouse, travando a câmera de quem mira nele.
DoorConfig.PromptDistance = 10
DoorConfig.PromptOffset = Vector2.new(-60, 60)
DoorConfig.PromptClickable = false

function DoorConfig.Number(model, name, default)
	local value = model:GetAttribute(name)
	return type(value) == "number" and value or default
end

-- Eixo mais fino da folha: é a normal da face. Diz de que lado o jogador está, e é sobre ele
-- que a maçaneta gira.
function DoorConfig.FaceAxis(part)
	local size = part.Size
	if size.X <= size.Y and size.X <= size.Z then
		return Vector3.xAxis
	elseif size.Y <= size.Z then
		return Vector3.yAxis
	end
	return Vector3.zAxis
end

function DoorConfig.Swing(model)
	return math.max(DoorConfig.Number(model, "Duration", DoorConfig.Duration), 0)
end

-- Segundos do ciclo inteiro, maçaneta incluída. Os dois lados chamam daqui para não divergir.
function DoorConfig.Total(hasKnob, duration)
	local lead = hasKnob and DoorConfig.KnobTurn or 0
	return math.max(lead + duration, hasKnob and DoorConfig.KnobTurn + DoorConfig.KnobReturn or 0)
end

return DoorConfig
