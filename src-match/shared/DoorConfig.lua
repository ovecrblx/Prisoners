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

-- Cortina de metal: as folhas não giram, esticam para baixo. Cada alavanca do Model traz o
-- indicador dela e as cortinas que move, e tem estado próprio — o atributo é escrito NA ALAVANCA,
-- não no Model, senão as duas dividiriam o mesmo aberto/fechado.
-- Cortina fora de toda lista fica parada, e alavanca sem as peças dela sai de cena sem levar as
-- outras junto.
DoorConfig.CurtainPrefix = "Curtain"
DoorConfig.ClosedAttribute = "Closed"
DoorConfig.CurtainLevers = {
	{ lever = "Right Root", indicator = "Indicator", bars = { "Center Root" } },
	{ lever = "Back Root", indicator = "Indicator_2", bars = { "Left Root" } },
}

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

-- Alavanca: giro em graus SOMADO à pose em que ela foi publicada, em torno do eixo local do Part.
-- 0 é a pose do cenário. Orientação absoluta reconstruía a rotação inteira e desalinhava a alavanca
-- da placa. Y é a dobradiça: aponta na horizontal, e o braço sai do pivô ao longo do X local, então o
-- giro joga a ponta para cima e para baixo. Sinal invertido troca qual lado é o ligado.
-- A cor do Indicator acompanha, e troca quando ela cruza o meio do curso.
DoorConfig.LeverAxis = Vector3.yAxis
DoorConfig.LeverOffAngle = 0
DoorConfig.LeverOnAngle = 90
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

-- Elevador: as folhas não giram, correm de lado e param uma atrás da outra no mesmo bolso. Quem
-- nomeia o bolso é `Pocket` — as folhas se chamam pelo lado de quem olha do corredor, e a geometria
-- sozinha não sabe qual lado é a esquerda. `Travel` é a fração do curso pleno, o que tiraria a folha
-- inteira do vão, e é o que deixa a nesga de fora. O prompt fica no botão de chamada e não na folha.
-- Só a FOLHA mora aqui: a cabine, os andares, o painel e o estado são do ElevatorConfig. O andar da
-- cabine e o aberto são do servidor; a altura e o andar da porta, de cada cliente.
DoorConfig.ElevatorPrefix = "Door_Elevator"
DoorConfig.ElevatorPocket = "Left Root"
DoorConfig.ElevatorCall = "Call"
DoorConfig.ElevatorTravel = 0.9
DoorConfig.ElevatorOpenTime = 1.1
DoorConfig.ElevatorCloseTime = 1.1
DoorConfig.ElevatorStyle = Enum.EasingStyle.Quint
DoorConfig.ElevatorDirection = Enum.EasingDirection.InOut
DoorConfig.ElevatorAutoClose = 0
DoorConfig.ElevatorTitle = "Elevator"

-- Style Custom: a engine não desenha nada, nem o fundo escuro atrás da tecla. Quem desenha é
-- o PromptDisplay do cliente. Clicável só no toque: no PC o alvo de clique cobre o prompt
-- inteiro e engole o arrasto do mouse, travando a câmera de quem mira nele.
DoorConfig.PromptDistance = 10
DoorConfig.PromptOffset = Vector2.new(0, 50)
DoorConfig.PromptClickable = false
DoorConfig.PromptTitle = "Door"

-- Studs que a âncora do prompt avança para fora da face da folha. A engine só mostra o prompt com
-- caminho livre da câmera até ele, e a maçaneta tem o miolo DENTRO da porta: ancorado ali, o
-- prompt fica tapado pela própria folha. Fora da face, cada lado enxerga o seu.
DoorConfig.PromptDepth = 0.4

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

-- As peças de uma alavanca, ou nada quando falta a alavanca ou alguma cortina dela. A ordem das
-- cortinas é a da lista, então o stagger cai sempre na mesma sequência. Indicador é opcional.
function DoorConfig.CurtainRig(model, spec)
	local lever = model:FindFirstChild(spec.lever)
	if not (lever and lever:IsA("BasePart")) then
		return nil
	end

	local bars = {}
	for _, name in ipairs(spec.bars) do
		local bar = model:FindFirstChild(name)
		if not (bar and bar:IsA("BasePart")) then
			return nil
		end
		bars[#bars + 1] = bar
	end

	local indicator = spec.indicator and model:FindFirstChild(spec.indicator)

	return {
		lever = lever,
		indicator = if indicator and indicator:IsA("BasePart") then indicator else nil,
		bars = bars,
	}
end

function DoorConfig.LeverPose(rest, degrees)
	return rest * CFrame.fromAxisAngle(DoorConfig.LeverAxis, math.rad(degrees))
end

function DoorConfig.SideOf(hinges, normal, position)
	return (position - hinges[1].Position):Dot(normal) >= 0 and 1 or -1
end

-- Três famílias moram na mesma pasta, e cada uma tem o seu par serviço/controlador. Quem decide é
-- o nome, e a decisão mora aqui: espalhada pelos quatro módulos, um deles esquece a família nova e
-- o Model entra na lógica errada em silêncio — a porta do elevador girando como folha de dobradiça.
function DoorConfig.Kind(model)
	local name = model.Name

	if name:sub(1, #DoorConfig.CurtainPrefix) == DoorConfig.CurtainPrefix then
		return "curtain"
	elseif name:sub(1, #DoorConfig.ElevatorPrefix) == DoorConfig.ElevatorPrefix then
		return "elevator"
	end

	return "door"
end

-- Eixo horizontal em que a folha corre: perpendicular à normal da face e ao pé-direito. Sai do
-- mundo, então a porta virada em qualquer ângulo continua correndo de lado. Folha deitada não tem
-- esse eixo, e aí não há por onde correr.
function DoorConfig.SlideAxis(leaf)
	local side = Vector3.new(0, 1, 0):Cross(leaf.CFrame:VectorToWorldSpace(DoorConfig.FaceAxis(leaf)))
	return if side.Magnitude > 1e-3 then side.Unit else nil
end

-- Meia-extensão da folha ao longo de um eixo do mundo.
function DoorConfig.HalfSpan(leaf, axis)
	local cf, size = leaf.CFrame, leaf.Size
	return (
		math.abs(axis:Dot(cf.RightVector)) * size.X
		+ math.abs(axis:Dot(cf.UpVector)) * size.Y
		+ math.abs(axis:Dot(cf.LookVector)) * size.Z
	) / 2
end

-- Folhas do elevador com o curso de cada uma, da mais curta para a mais longa — a do bolso primeiro.
-- O curso pleno é o que leva a borda de trás da folha até a borda do vão do lado do bolso, então
-- cada folha anda o quanto precisa e elas param empilhadas em vez de uma empurrar a outra.
-- `axis` já aponta PARA o bolso: o sinal vem de onde a folha nomeada está, não de eixo escrito à mão.
function DoorConfig.SlideRig(model)
	local hinges = DoorConfig.Hinges(model)
	local pocket = model:FindFirstChild(DoorConfig.ElevatorPocket)
	local axis = pocket and pocket:IsA("BasePart") and DoorConfig.SlideAxis(pocket) or nil

	if #hinges < 2 or not axis or not table.find(hinges, pocket) then
		return nil
	end

	local sum = 0
	for _, leaf in ipairs(hinges) do
		if leaf ~= pocket then
			sum += axis:Dot(leaf.Position)
		end
	end

	if axis:Dot(pocket.Position) < sum / (#hinges - 1) then
		axis = -axis
	end

	local edge
	for _, leaf in ipairs(hinges) do
		local reach = axis:Dot(leaf.Position) + DoorConfig.HalfSpan(leaf, axis)
		edge = if edge then math.max(edge, reach) else reach
	end

	local leaves = {}
	for _, leaf in ipairs(hinges) do
		local back = axis:Dot(leaf.Position) - DoorConfig.HalfSpan(leaf, axis)
		leaves[#leaves + 1] = { part = leaf, travel = (edge - back) * DoorConfig.ElevatorTravel }
	end

	table.sort(leaves, function(a, b)
		return a.travel < b.travel
	end)

	return { axis = axis, leaves = leaves }
end

-- Âncora do prompt no botão de chamada, no LOCAL dele: à frente da face que olha para longe das
-- folhas. O miolo do botão fica rente à parede, e a engine só mostra o prompt com caminho livre da
-- câmera até ele.
function DoorConfig.CallAnchor(call, center)
	local face = DoorConfig.FaceAxis(call)
	local away = call.CFrame:VectorToWorldSpace(face):Dot(call.Position - center) >= 0
	local reach = math.abs(face:Dot(call.Size)) / 2 + DoorConfig.PromptDepth
	return face * (if away then reach else -reach)
end

return DoorConfig
