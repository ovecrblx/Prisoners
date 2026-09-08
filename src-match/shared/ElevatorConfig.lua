-- Contrato do elevador de workspace.Siland_Home, lido pelo servidor e pelo cliente.
-- A CABINE é uma só no mundo: o servidor guarda o andar, o destino e o aberto, e não move peça
-- nenhuma — cada cliente desenha o curso a partir do instante publicado, então todas as telas a
-- mostram na mesma altura sem CFrame na rede.
-- A PORTA é de cada jogador: existe um Model só, e cada cliente o desenha no andar do SEU jogador.
-- É ela que tapa o poço, e é por isso que ela acompanha quem olha em vez de morar num andar.
-- Aberto é estado compartilhado, mas só vale no andar em que a cabine está: quem divide o andar com
-- ela vê a mesma porta abrir; quem está noutro andar vê a própria porta fechada e o visor ocupado.
local ElevatorConfig = {}

-- Estrutura esperada no place. `Floor` é a laje que o jogador pisa, e é ela que define a caixa da
-- cabine; `Control` é o painel, e cada peça dele com GuiButton é uma tecla — menos `Screen`, que é
-- visor. A porta é o Model do DoorConfig, e o `Screen` dela mostra o estado do andar em que ela está.
ElevatorConfig.Path = { "Siland_Home", "interactive" }
ElevatorConfig.ModelName = "Elevator"
ElevatorConfig.FloorName = "Floor"
ElevatorConfig.PanelName = "Control"
ElevatorConfig.ScreenName = "Screen"
ElevatorConfig.OpenName = "Open"
ElevatorConfig.CloseName = "Close"

-- Andares, do mais baixo para o mais alto. `Name` é o nome da tecla no painel, `Level` o número que o
-- visor mostra, e `Lift` os studs que a cabine sobe a partir da pose autorada. MEDIDO no place pelo
-- umbral de cada andar: F1 é a pose de fábrica, F0 está 15.810 abaixo e F2 16.000 acima — os dois
-- vãos NÃO são iguais.
ElevatorConfig.Floors = {
	{ Name = "F0", Level = 0, Lift = -15.810 },
	{ Name = "F1", Level = 1, Lift = 0 },
	{ Name = "F2", Level = 2, Lift = 16.000 },
}

ElevatorConfig.HomeName = "F1"

-- Caixa da cabine, medida a partir da laje: `RideHeight` é o pé-direito interno (MEDIDO 6.959 do topo
-- do piso à base do teto) e `RideSlack` os studs abaixo do piso que ainda contam como dentro, porque
-- o pivô do personagem desce enquanto ele agacha ou cai.
ElevatorConfig.RideHeight = 6.959
ElevatorConfig.RideSlack = 1.5

-- Alcance do raio que confirma o chão do passageiro. MEDIDO no rig do place: R15, HipHeight 1.937 e
-- HumanoidRootPart de 2 x 2 x 1, então o pivô fica 2.937 acima dos pés; dentro da cabine o salto bate
-- no teto com 1.933 de folga sobre a cabeça, e o pivô não passa de 4.870 acima da laje.
ElevatorConfig.RideProbe = 6

-- studs abaixo do plano de um andar que ainda contam como estar nele: personagem caído tem o pivô
-- mais baixo que o de pé.
ElevatorConfig.FloorSlack = 1

-- Curso: studs/s e o piso de duração, para o andar vizinho não virar um pulo.
ElevatorConfig.Speed = 8
ElevatorConfig.MinTravel = 0.6
ElevatorConfig.Style = Enum.EasingStyle.Quad
ElevatorConfig.Direction = Enum.EasingDirection.InOut

-- s de resfriamento DEPOIS de a folha terminar de fechar, antes de a porta aceitar comando de novo.
-- Abrir não cobra nada: quem acabou de ver a porta abrir pode fechá-la assim que ela para. É o
-- fechamento que precisa de descanso, senão o mesmo botão abre e fecha em sequência e a folha vira um
-- bate-e-volta. O estado é um só, então o resfriamento vale para qualquer jogador.
ElevatorConfig.DoorCooldown = 2

-- s entre o fim de um curso e o começo do próximo. Curso em andamento não é interrompido nem
-- enfileirado: o pedido é recusado.
ElevatorConfig.MoveCooldown = 3

-- s entre uma varredura e a seguinte: é ela que liga o painel ao entrar, desliga ao sair, e muda a
-- cabine de andar enquanto o jogador está fora.
ElevatorConfig.ScanInterval = 0.25

-- Tecla: studs que ela afunda pela face da SurfaceGui e os s de uma perna do curso — o retorno é a
-- mesma perna ao contrário.
ElevatorConfig.KeyDepth = 0.03
ElevatorConfig.KeyTravel = 0.07
ElevatorConfig.KeySound = "UiClick"

-- Visor. A fonte é PressStart2P, monoespaçada — MEDIDO, " 01", "▲01" e " --" ocupam os mesmos 84 px,
-- então o espaço no lugar da seta guarda a largura e o TextScaled não incha o texto parado.
ElevatorConfig.ScreenDigits = 2
ElevatorConfig.ScreenIdle = " %s"
ElevatorConfig.ScreenUp = "▲%s"
ElevatorConfig.ScreenDown = "▼%s"
ElevatorConfig.ScreenBusy = " --"

-- Estado publicado pelo servidor nos atributos do Model da cabine. `Floor` é o índice do andar em que
-- ela está, `Going` o destino enquanto viaja (0 parada), `StartedAt` o relógio de servidor em que o
-- curso começou, e `Open` se a porta está aberta NO ANDAR de `Floor` — aberto é compartilhado, mas só
-- vale ali. Atributo e não remote: quem entra no meio da partida recebe o retrato junto com o Model.
ElevatorConfig.FloorAttribute = "Floor"
ElevatorConfig.GoingAttribute = "Going"
ElevatorConfig.StartedAttribute = "StartedAt"
ElevatorConfig.OpenAttribute = "Open"

-- Cliente -> servidor, do painel de dentro: `GoAction` com o índice do andar, `OpenName` e
-- `CloseName` sem argumento. Chamar de fora é pelo prompt, que é do servidor e dispensa remote.
ElevatorConfig.Remote = "ElevatorCommand"
ElevatorConfig.GoAction = "Go"

-- A face nomeada na SurfaceGui, no espaço local da peça. Front é -Z, e não -Y: as teclas do painel
-- estão deitadas de lado na parede da cabine.
local FACE_AXIS = {
	[Enum.NormalId.Front] = -Vector3.zAxis,
	[Enum.NormalId.Back] = Vector3.zAxis,
	[Enum.NormalId.Right] = Vector3.xAxis,
	[Enum.NormalId.Left] = -Vector3.xAxis,
	[Enum.NormalId.Top] = Vector3.yAxis,
	[Enum.NormalId.Bottom] = -Vector3.yAxis,
}

function ElevatorConfig.FaceAxis(face)
	return FACE_AXIS[face] or -Vector3.zAxis
end

function ElevatorConfig.IndexOf(name)
	for index, floor in ipairs(ElevatorConfig.Floors) do
		if floor.Name == name then
			return index
		end
	end

	return nil
end

function ElevatorConfig.Home()
	return ElevatorConfig.IndexOf(ElevatorConfig.HomeName) or 1
end

-- Dentro da cabine é a caixa da própria laje esticada até o teto. Sai do CFrame dela, então a cabine
-- levantada leva a caixa junto e a conta não precisa saber em que andar ela está.
function ElevatorConfig.Inside(floorPart, position)
	local point = floorPart.CFrame:PointToObjectSpace(position)
	local half = floorPart.Size / 2
	local above = point.Y - half.Y

	return math.abs(point.X) <= half.X
		and math.abs(point.Z) <= half.Z
		and above >= -ElevatorConfig.RideSlack
		and above <= ElevatorConfig.RideHeight
end

-- Passageiro de verdade. A caixa sozinha aceita quem está parado no VÃO, com meio corpo no corredor,
-- e quem subiu no teto; e um recuo na planta para tirar o vão tiraria junto quem está encostado na
-- porta fechada, que é passageiro legítimo. Quem separa os três é o chão: `ground` é a peça da cabine
-- que o raio para baixo achou. MEDIDO com o pivô a 2.937 da laje — de pé no meio, no fundo e colado
-- na porta o raio acha `Floor`; parado no plano do vão acha `Front`; em cima do teto acha
-- `Roof_Door`; do corredor não acha nada.
function ElevatorConfig.Aboard(floorPart, position, ground)
	return ground == floorPart and ElevatorConfig.Inside(floorPart, position)
end

-- Em que andar está um Y do mundo. `homeTop` é o topo da laje da cabine na pose autorada, e o plano
-- de cada andar é ele mais o `Lift` — os andares e a cabine saem do mesmo número, e não de duas
-- listas que divergem em silêncio. Abaixo de todos cai no mais baixo: quem cai no poço não fica sem
-- andar.
function ElevatorConfig.FloorAt(homeTop, y)
	local best = 1

	for index, floor in ipairs(ElevatorConfig.Floors) do
		if y >= homeTop + floor.Lift - ElevatorConfig.FloorSlack then
			best = index
		end
	end

	return best
end

-- A caixa da cabine no andar em que ela ESTÁ, e não onde a laje está parada. O servidor não move
-- peça nenhuma, então a laje dele fica na pose autorada para sempre: quem sobe é a conta.
function ElevatorConfig.InsideAt(floorPart, position, lift)
	return ElevatorConfig.Inside(floorPart, position - Vector3.new(0, lift, 0))
end

function ElevatorConfig.Travel(from, to)
	return math.max(math.abs(to - from) / ElevatorConfig.Speed, ElevatorConfig.MinTravel)
end

-- Cabine em curso não aceita nada — nem porta, nem andar novo —, e parada ainda espera o instante em
-- que aquele comando volta a valer. `going ~= 0` é o que impede a subida de ser interrompida no meio:
-- o pedido é recusado, e não guardado para depois.
function ElevatorConfig.Accepts(state, now, readyAt)
	return state.going == 0 and now >= readyAt
end

-- s até a porta aceitar comando de jogador de novo, contados do início do movimento da folha. `run`
-- são os s que ela leva para correr.
function ElevatorConfig.DoorHold(run, open)
	return run + (if open then 0 else ElevatorConfig.DoorCooldown)
end

-- Fração do curso, tirada do relógio do servidor. Todo cliente parte do MESMO instante publicado e
-- desenha a cabine na mesma altura; um cronômetro que começasse na chegada do aviso poria a cabine
-- em alturas diferentes em cada tela, e quem recebesse o Model pelo streaming no meio da viagem a
-- veria recomeçar do andar de partida.
function ElevatorConfig.Progress(startedAt, now, duration)
	if duration <= 0 then
		return 1
	end

	return math.clamp((now - startedAt) / duration, 0, 1)
end

function ElevatorConfig.State(model)
	return {
		floor = model:GetAttribute(ElevatorConfig.FloorAttribute) or ElevatorConfig.Home(),
		going = model:GetAttribute(ElevatorConfig.GoingAttribute) or 0,
		startedAt = model:GetAttribute(ElevatorConfig.StartedAttribute) or 0,
		open = model:GetAttribute(ElevatorConfig.OpenAttribute) == true,
	}
end

-- A porta só obedece com a cabine PARADA no andar dela. É a porta que tapa o poço: obedecer com a
-- cabine longe abre um vão de 16 studs no andar de quem apertou, e o Model continua íntegro, sem
-- nada no console. Outro jogador DENTRO da cabine parada aqui não impede nada — quem espera do lado
-- de fora entra junto, como em elevador de verdade.
function ElevatorConfig.Operable(state, floorIndex)
	return state.going == 0 and state.floor == floorIndex
end

-- A que andar a porta DESTE cliente responde: ao do próprio jogador enquanto ele está fora, e ao da
-- cabine enquanto ele está dentro. Cada jogador tem a sua porta e só vê a sua — é ela que tapa o poço
-- no andar em que ele está, e é por isso que ela não é uma porta por andar.
-- É o andar do POSTO, e trocar de posto teleporta a porta, então ela troca sempre fechada de uma vez.
-- Por isso aqui é `state.floor` e nunca `state.going`: apontar para o destino no instante do pedido
-- trocaria o posto com a folha ainda aberta, e ela fecharia seca em vez de correr. Em curso o posto
-- fica no andar de partida e só vira o novo na chegada, quando ela já está fechada. A altura durante
-- o curso é `DoorLift`, que é outra conta.
function ElevatorConfig.DoorFloor(state, playerFloor, riding)
	if not riding then
		return playerFloor
	end

	return state.floor
end

-- A altura da porta. Fora da cabine ela fica parada no plano do andar dela; DENTRO, ela acompanha a
-- cabine stud a stud. O vão da frente da cabine é aberto, e o passageiro olha para essa porta o
-- caminho inteiro: pô-la de uma vez no destino o deixa subindo com um buraco na frente do nariz.
function ElevatorConfig.DoorLift(doorFloor, cabinLift, riding)
	if riding then
		return cabinLift
	end

	return ElevatorConfig.Floors[doorFloor].Lift
end

-- Aberto é estado COMPARTILHADO, mas só vale no andar em que a cabine está: dois jogadores parados no
-- mesmo andar da cabine veem a mesma porta abrir, e quem está noutro andar não vê nada.
function ElevatorConfig.DoorOpen(state, doorFloor)
	return state.open and ElevatorConfig.Operable(state, doorFloor)
end

local function heading(state)
	local here = ElevatorConfig.Floors[state.floor]
	local target = ElevatorConfig.Floors[state.going]
	return ElevatorConfig.ScreenText(state.going, if target.Lift > here.Lift then 1 else -1)
end

-- Visor de dentro da cabine: para onde ela vai, ou onde parou.
function ElevatorConfig.CabinText(state)
	if state.going == 0 then
		return ElevatorConfig.ScreenText(state.floor, 0)
	end

	return heading(state)
end

-- Visor da porta: o número só aparece com a cabine parada no andar dela. Em curso mostra para onde a
-- cabine vai, e com ela noutro andar mostra ocupado — porque é isso que a porta vai fazer se alguém
-- apertar. O jogador precisa saber POR QUE nada aconteceu.
function ElevatorConfig.DoorText(state, floorIndex)
	if state.going ~= 0 then
		return heading(state)
	end

	if not ElevatorConfig.Operable(state, floorIndex) then
		return ElevatorConfig.ScreenBusy
	end

	return ElevatorConfig.ScreenText(state.floor, 0)
end

-- Texto do visor: o andar mostrado e a seta do sentido. 0 é parado, e aí a seta vira espaço.
function ElevatorConfig.ScreenText(index, direction)
	local floor = ElevatorConfig.Floors[index]
	if not floor then
		return ""
	end

	local digits = string.format("%0" .. ElevatorConfig.ScreenDigits .. "d", floor.Level)
	local form = ElevatorConfig.ScreenIdle

	if direction > 0 then
		form = ElevatorConfig.ScreenUp
	elseif direction < 0 then
		form = ElevatorConfig.ScreenDown
	end

	return string.format(form, digits)
end

-- Laje, painel, visor e teclas, ou nada quando falta a laje ou o painel. Tecla é peça do painel com
-- GuiButton dentro, e TODOS os botões dela entram: `Open` e `Close` têm dois cada, e ligar só o
-- primeiro deixa metade da seta morta.
function ElevatorConfig.Rig(model)
	local floor = model:FindFirstChild(ElevatorConfig.FloorName)
	local panel = model:FindFirstChild(ElevatorConfig.PanelName)

	if not (floor and floor:IsA("BasePart") and panel) then
		return nil
	end

	local screen = panel:FindFirstChild(ElevatorConfig.ScreenName)
	local keys = {}

	for _, part in ipairs(panel:GetChildren()) do
		if part:IsA("BasePart") and part ~= screen then
			local buttons = {}

			for _, descendant in ipairs(part:GetDescendants()) do
				if descendant:IsA("GuiButton") then
					buttons[#buttons + 1] = descendant
				end
			end

			if #buttons > 0 then
				keys[#keys + 1] = { part = part, buttons = buttons }
			end
		end
	end

	return { floor = floor, panel = panel, screen = screen, keys = keys }
end

return ElevatorConfig
