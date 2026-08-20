-- Contrato das portas, lido pelo servidor e pelo cliente. O servidor publica o estado e usa
-- os tempos para saber quando o giro acabou; o cliente usa os mesmos tempos para animar.
local DoorConfig = {}

-- Estrutura esperada no place: gira o Part `Root`, ou `<Lado> Root` quando a porta tem mais de
-- uma folha, e o que estiver soldado nele vai junto; o `PivotOffset` dele é a dobradiça.
-- `Animate` (ou `<Lado> Animate`) soldado nela é a maçaneta. Model sem folha não é porta.
-- Model cujo nome começa com DualPrefix abre por aproximação, sem prompt.
DoorConfig.Folder = { "Siland_Home", "Doors" }
DoorConfig.HingeName = "Root"
DoorConfig.KnobName = "Animate"
DoorConfig.BlockName = "Collide"
DoorConfig.DualPrefix = "Dual_Door"

-- Cortina de metal: as folhas não giram, esticam para baixo. `Right Root` é a alavanca que
-- as aciona, e as outras `<Lado> Root` do Model são as cortinas.
DoorConfig.CurtainPrefix = "Curtain"
DoorConfig.LeverName = "Right Root"
DoorConfig.IndicatorName = "Indicator"
DoorConfig.ClosedAttribute = "Closed"

-- Estado publicado pelo servidor: módulo do ângulo com o sinal do lado de quem abriu, 0
-- fechada. Cada folha deriva o próprio sinal, então porta dupla cabe numa escrita só.
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

-- Aproximação: studs para abrir, studs para fechar e intervalo da varredura em segundos.
-- O raio de fechar é maior para a porta não piscar com o jogador parado na borda.
DoorConfig.OpenRadius = 12
DoorConfig.CloseRadius = 16
DoorConfig.ScanInterval = 0.2

-- Porta de prompt aberta por NPC: ele não aperta botão, então a aproximação dele vale por um.
-- Raio menor que o de cima porque aqui abrir cedo demais entrega a sala antes de alguém chegar.
DoorConfig.NpcOpenRadius = 7
DoorConfig.NpcCloseRadius = 11

DoorConfig.Easing = Enum.EasingStyle.Quad
DoorConfig.EasingDirection = Enum.EasingDirection.Out

-- Alavanca: orientação em graus de cada estado, e a cor do Indicator que acompanha. Vira com
-- passada, e a luz troca quando ela cruza o meio do curso.
DoorConfig.LeverOff = Vector3.new(-45, 90, 90)
DoorConfig.LeverOn = Vector3.new(-45, -90, -90)
DoorConfig.IndicatorOff = Color3.fromRGB(255, 89, 89)
DoorConfig.IndicatorOn = Color3.fromRGB(75, 151, 75)
DoorConfig.LeverTime = 0.28
DoorConfig.LeverStyle = Enum.EasingStyle.Back
DoorConfig.LeverDirection = Enum.EasingDirection.Out
DoorConfig.IndicatorSwitch = 0.45
DoorConfig.IndicatorTime = 0.18

-- Cortina: descer é chapa pesada batendo no chão, subir é motor puxando. Stagger em segundos
-- entre uma cortina e a seguinte, para o par não andar colado.
DoorConfig.CurtainCloseTime = 1.1
DoorConfig.CurtainCloseStyle = Enum.EasingStyle.Bounce
DoorConfig.CurtainCloseDirection = Enum.EasingDirection.Out
DoorConfig.CurtainOpenTime = 0.9
DoorConfig.CurtainOpenStyle = Enum.EasingStyle.Quint
DoorConfig.CurtainOpenDirection = Enum.EasingDirection.InOut
DoorConfig.CurtainStagger = 0.09

-- Size.Y da cortina em cada estado. O topo fica parado; o que cresce é a barra para baixo.
DoorConfig.CloseHeight = 3.85
DoorConfig.OpenHeight = 1

-- Style Custom: a engine não desenha nada, nem o fundo escuro atrás da tecla. Quem desenha é
-- o PromptDisplay do cliente. Clicável só no toque: no PC o alvo de clique cobre o prompt
-- inteiro e engole o arrasto do mouse, travando a câmera de quem mira nele.
DoorConfig.PromptDistance = 10
DoorConfig.PromptOffset = Vector2.new(0, 50)
DoorConfig.PromptClickable = false

function DoorConfig.Number(model, name, default)
	local value = model:GetAttribute(name)
	return type(value) == "number" and value or default
end

function DoorConfig.Swing(model)
	return math.max(DoorConfig.Number(model, "Duration", DoorConfig.Duration), 0)
end

-- Segundos do ciclo inteiro, maçaneta incluída. Os dois lados chamam daqui para não divergir.
function DoorConfig.Total(hasKnob, duration)
	local lead = hasKnob and DoorConfig.KnobTurn or 0
	return math.max(lead + duration, hasKnob and DoorConfig.KnobTurn + DoorConfig.KnobReturn or 0)
end

-- Eixo mais fino da folha: é a normal da face, e é sobre ele que a maçaneta gira.
function DoorConfig.FaceAxis(part)
	local size = part.Size
	if size.X <= size.Y and size.X <= size.Z then
		return Vector3.xAxis
	elseif size.Y <= size.Z then
		return Vector3.yAxis
	end
	return Vector3.zAxis
end

-- Ordenadas por nome: servidor e cliente precisam eleger a mesma folha de referência.
function DoorConfig.Hinges(model)
	local suffix = " " .. DoorConfig.HingeName
	local hinges = {}

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and (child.Name == DoorConfig.HingeName or child.Name:sub(-#suffix) == suffix) then
			hinges[#hinges + 1] = child
		end
	end

	table.sort(hinges, function(a, b)
		return a.Name < b.Name
	end)

	return hinges
end

function DoorConfig.KnobOf(model, hinge)
	local prefix = hinge.Name:sub(1, #hinge.Name - #DoorConfig.HingeName)
	local knob = model:FindFirstChild(prefix .. DoorConfig.KnobName)
	return knob and knob:IsA("BasePart") and knob or nil
end

-- Numa porta dupla as folhas estão viradas uma contra a outra, então a normal de cada uma
-- aponta para lados opostos e o lado do jogador sairia invertido numa delas. A referência é
-- sempre a primeira folha. Ler com a porta fechada: no cliente a folha gira.
function DoorConfig.Normal(hinges)
	return hinges[1].CFrame:VectorToWorldSpace(DoorConfig.FaceAxis(hinges[1]))
end

function DoorConfig.LeafSign(hinge, normal)
	local arm = hinge.Position - hinge:GetPivot().Position
	return Vector3.new(0, 1, 0):Cross(arm):Dot(normal) >= 0 and -1 or 1
end

-- Cortinas do Model: as folhas que não são a alavanca. Ordem vem de Hinges, então o stagger
-- cai sempre na mesma sequência.
function DoorConfig.Curtains(model)
	local parts = {}

	for _, part in ipairs(DoorConfig.Hinges(model)) do
		if part.Name ~= DoorConfig.LeverName then
			parts[#parts + 1] = part
		end
	end

	return parts
end

function DoorConfig.LeverPose(pivot, orientation)
	local rotation = CFrame.fromOrientation(math.rad(orientation.X), math.rad(orientation.Y), math.rad(orientation.Z))
	return CFrame.new(pivot) * rotation
end

function DoorConfig.SideOf(hinges, normal, position)
	return (position - hinges[1].Position):Dot(normal) >= 0 and 1 or -1
end

return DoorConfig
