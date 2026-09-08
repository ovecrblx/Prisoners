-- ElevatorRideSpec — a cabine: onde cada andar fica, quem está dentro dela, o que o visor diz e
-- quais peças do painel são tecla.
--
-- O QUE ESTA SPEC PROTEGE. O elevador inteiro é de cliente, e por isso NADA aqui tem guarda de
-- servidor: se a conta do andar errar, a cabine para dentro da laje e o erro é mudo — o jogador
-- atravessa o chão e ninguém vê nada no console. Os números vêm todos da medição do place.
--
-- A ARMADILHA MAIOR É O VÃO ENTRE OS ANDARES. F0 está 15.810 abaixo de F1 e F2 está 16.000 acima:
-- um passo único de 16 studs, a simplificação óbvia, encalha a cabine 0.190 stud fora do piso de F0.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ElevatorConfig = t:freshRequire(ReplicatedStorage.Shared.ElevatorConfig)
	local DoorConfig = t:freshRequire(ReplicatedStorage.Shared.DoorConfig)

	-- MEDIDO NO PLACE, em interactive.Elevator: a laje `Floor` tem 9.000 x 0.175 x 6.900 e o topo dela
	-- fica em Y 2.184; o pé-direito interno é 6.958. O painel `Control` traz `F0`, `F1`, `F2`, `Open`,
	-- `Close`, o visor `Screen` e a peça sem GUI que é o corpo do painel.
	local FLOOR_SIZE = Vector3.new(9.000, 0.175, 6.900)
	local FLOOR_TOP = 2.184
	local FLOOR_CENTER = Vector3.new(-15.570, 2.097, 70.240)

	local function fakeKey(panel, name, buttons)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.new(0.250, 0.250, 0.100)
		part.CanQuery = false
		part.Parent = panel

		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.Parent = part

		for index = 1, buttons do
			local button = Instance.new("TextButton")
			button.Name = if index == 1 then "Button" else "Button" .. index
			button.Parent = gui
		end

		return part
	end

	local function fakeCabin()
		local model = Instance.new("Model")
		model.Name = ElevatorConfig.ModelName

		local floor = Instance.new("Part")
		floor.Name = ElevatorConfig.FloorName
		floor.Size = FLOOR_SIZE
		floor.CFrame = CFrame.new(FLOOR_CENTER)
		floor.Parent = model

		local panel = Instance.new("Model")
		panel.Name = ElevatorConfig.PanelName
		panel.Parent = model

		fakeKey(panel, "F0", 1)
		fakeKey(panel, "F1", 1)
		fakeKey(panel, "F2", 1)
		fakeKey(panel, ElevatorConfig.OpenName, 2)
		fakeKey(panel, ElevatorConfig.CloseName, 2)
		fakeKey(panel, ElevatorConfig.ScreenName, 1)

		local body = Instance.new("Part")
		body.Name = "Part"
		body.Size = Vector3.new(0.100, 3.000, 2.000)
		body.Parent = panel

		return model, floor
	end

	t:test("os dois vãos entre andares não são iguais, e um passo único deixa a cabine fora do piso", function()
		-- MEDIDO pelo umbral de cada andar: o lintel de F0 está em Y -3.460, o de F1 em 12.350 e o de
		-- F2 em 28.350. Descer sempre 16 studs, que é o vão de cima, para a cabine 0.190 acima do piso
		-- de F0 — e o jogador sai do elevador dentro da laje, sem erro nenhum no console.
		local floors = ElevatorConfig.Floors
		t:assertEqual(#floors, 3, "o place tem três andares de elevador")
		t:assertNear(floors[1].Lift, -15.810, 1e-3, "F0 abaixo da pose autorada")
		t:assertNear(floors[2].Lift, 0, 1e-6, "F1 é a pose autorada")
		t:assertNear(floors[3].Lift, 16.000, 1e-3, "F2 acima da pose autorada")

		local down = floors[2].Lift - floors[1].Lift
		local up = floors[3].Lift - floors[2].Lift
		t:assert(math.abs(up - down) > 0.1, "os dois vãos viraram o mesmo número")
		t:assertNear(math.abs(up - down), 0.190, 1e-3, "o erro do passo único")
	end)

	t:test("a pose autorada é o andar de casa, senão a cabine nasce dizendo o andar errado", function()
		-- A cabine é publicada em F1 e `Lift = 0` é essa pose. Home apontando para outro andar faz o
		-- visor abrir mentindo e a primeira parada saltar sem sair do lugar.
		local home = ElevatorConfig.Home()
		t:assertEqual(ElevatorConfig.Floors[home].Name, "F1", "casa é o andar da pose autorada")
		t:assertNear(ElevatorConfig.Floors[home].Lift, 0, 1e-6, "e o Lift de casa é zero")
	end)

	t:test("o andar do jogador sai do Y dele, e ninguém fica sem andar", function()
		-- MEDIDO: o piso de F0 termina em Y -13.655, o de F1 em 2.147 e o de F2 em 18.150, e o pivô do
		-- personagem fica cerca de 3 studs acima dos pés. Quem cai no poço tem de cair em algum andar:
		-- devolver nada aqui deixaria a cabine parada no andar de antes, com o vão aberto.
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, -10.6), 1, "de pé em F0")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, 5.2), 2, "de pé em F1")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, 21.2), 3, "de pé em F2")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, -40), 1, "caindo no poço, ainda é F0")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, 400), 3, "acima do prédio, ainda é F2")
	end)

	t:test("estar no piso de um andar já conta como aquele andar, e não como o de baixo", function()
		-- A folga existe porque o pivô de um personagem caído desce abaixo do plano do andar. Sem ela,
		-- ele conta como o andar de baixo e a cabine desce para debaixo dele.
		local plane = FLOOR_TOP + ElevatorConfig.Floors[3].Lift
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, plane + 0.01), 3, "logo acima do piso de F2")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, plane - ElevatorConfig.FloorSlack + 0.01), 3, "caído em F2")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, plane - ElevatorConfig.FloorSlack - 0.01), 2, "abaixo da folga já é F1")
	end)

	t:test("a caixa da cabine acompanha a laje, e a soleira fica de fora", function()
		-- A caixa sai do CFrame da laje e não de números do mundo: a cabine levantada leva a caixa
		-- junto. Fixa no mundo, o passageiro deixaria de contar como dentro no primeiro stud de subida
		-- e a cabine sairia sem ele.
		local model, floor = fakeCabin()
		local top = floor.Position.Y + floor.Size.Y / 2

		local standing = floor.Position + Vector3.new(0, floor.Size.Y / 2 + 3, 0)
		t:assert(ElevatorConfig.Inside(floor, standing), "de pé no meio da cabine")

		floor.CFrame = floor.CFrame + Vector3.new(0, 16, 0)
		t:assert(ElevatorConfig.Inside(floor, standing + Vector3.new(0, 16, 0)), "a cabine subiu e ele foi junto")
		t:assert(not ElevatorConfig.Inside(floor, standing), "quem ficou para trás não está mais dentro")
		floor.CFrame = CFrame.new(FLOOR_CENTER)

		local outside = Vector3.new(FLOOR_CENTER.X, top + 3, FLOOR_CENTER.Z - FLOOR_SIZE.Z / 2 - 1.5)
		t:assert(not ElevatorConfig.Inside(floor, outside), "parado no corredor, fora da soleira")

		local roof = Vector3.new(FLOOR_CENTER.X, top + ElevatorConfig.RideHeight + 1, FLOOR_CENTER.Z)
		t:assert(not ElevatorConfig.Inside(floor, roof), "em cima do teto não é dentro")

		model:Destroy()
	end)

	t:test("parado no vão da porta não é passageiro, mesmo estando na planta da cabine", function()
		-- MEDIDO no place, com o pivô do personagem 2.937 acima dos pés: a borda da frente da laje
		-- (Z 66.790) é o PRÓPRIO plano do vão, então parado ali, com meio corpo no corredor, a caixa
		-- diz que ele está dentro. Quem desmente é o chão: o raio para baixo acha `Front`, não `Floor`.
		-- Sem essa conferência a cabine parte com ele meio de fora e leva a porta junto, deixando o
		-- andar dele com um poço aberto de 16 studs — e nada aparece no console.
		local model, floor = fakeCabin()
		local stray = Instance.new("Part")
		stray.Name = "Front"
		stray.Parent = model

		local edge = Vector3.new(FLOOR_CENTER.X, FLOOR_TOP + 2.937, FLOOR_CENTER.Z - FLOOR_SIZE.Z / 2)
		t:assert(ElevatorConfig.Inside(floor, edge), "a caixa sozinha aceita quem está no vão")
		t:assert(not ElevatorConfig.Aboard(floor, edge, stray), "o vão entrou como passageiro")
		t:assert(not ElevatorConfig.Aboard(floor, edge, nil), "sem chão nenhum também não é passageiro")

		model:Destroy()
	end)

	t:test("encostado na porta fechada é passageiro, e um recuo na planta o excluiria", function()
		-- MEDIDO: as folhas param em Z 66.622 e o HumanoidRootPart tem 1 de profundidade, então quem
		-- está colado na porta fechada tem o pivô em Z 67.122 — a 0.332 da borda da laje. Encolher a
		-- planta para tirar o vão, que é o conserto óbvio, precisaria de menos de 0.332 de recuo para
		-- não expulsar ESTE, e o vão fica a 0. Não há recuo que separe os dois: quem separa é o chão.
		local model, floor = fakeCabin()

		local shut = Vector3.new(FLOOR_CENTER.X, FLOOR_TOP + 2.937, 67.122)
		t:assert(ElevatorConfig.Aboard(floor, shut, floor), "colado na porta fechada ficou de fora")
		t:assertNear(shut.Z - (FLOOR_CENTER.Z - FLOOR_SIZE.Z / 2), 0.332, 1e-3, "a folga que não dá para recuar")

		model:Destroy()
	end)

	t:test("em cima do teto não é passageiro, nem com o chão certo", function()
		-- MEDIDO: o topo do teto está 7.134 acima da laje, e de pé ali o pivô fica a 10.071 — fora do
		-- pé-direito. As duas metades da conta importam: só o chão aceitaria quem subiu no teto, e só
		-- a caixa aceitaria quem está no vão.
		local model, floor = fakeCabin()

		local roof = Vector3.new(FLOOR_CENTER.X, FLOOR_TOP + 10.071, FLOOR_CENTER.Z)
		t:assert(not ElevatorConfig.Inside(floor, roof), "a caixa deixou o teto entrar")
		t:assert(not ElevatorConfig.Aboard(floor, roof, floor), "o teto entrou como passageiro")

		model:Destroy()
	end)

	t:test("o raio do chão alcança o salto dentro da cabine", function()
		-- MEDIDO: o pivô fica 2.937 acima dos pés e o salto bate no teto com 1.933 de folga sobre a
		-- cabeça, então ele não passa de 4.870 acima da laje. Raio mais curto que isso perde o chão no
		-- ar e, com a conferência ligada à saída, a cabine recusaria a viagem de quem pulou na hora.
		t:assert(ElevatorConfig.RideProbe > 4.870, "o raio não alcança o topo do salto")
		t:assert(
			ElevatorConfig.RideProbe <= ElevatorConfig.RideHeight + ElevatorConfig.RideSlack,
			"o raio alcança mais longe do que a caixa aceita, e as duas metades deixam de falar do mesmo volume"
		)
	end)

	t:test("a cabine anda o curso, e não um tempo fixo por viagem", function()
		-- MEDIDO: um vão de andar são 16.000 studs e F0 a F2 são 31.810, quase o dobro. Uma duração
		-- fixa faria a viagem longa correr quase duas vezes mais rápido que a curta. Os segundos são
		-- literais de propósito: dividir pelo próprio `Speed` passa em qualquer velocidade, e o ritmo
		-- pedido — 2.8 studs/s — voltaria aos 8 originais sem nada ficar vermelho.
		local floors = ElevatorConfig.Floors
		local short = ElevatorConfig.Travel(floors[2].Lift, floors[3].Lift)
		local long = ElevatorConfig.Travel(floors[1].Lift, floors[3].Lift)

		t:assertNear(short, 5.714, 1e-3, "um andar, a 2.8 studs/s")
		t:assertNear(long, 11.361, 1e-3, "dois andares, na mesma velocidade")
		t:assert(long > short * 1.9, "a viagem longa não custa quase o dobro")
		t:assertEqual(ElevatorConfig.Travel(0, 0), ElevatorConfig.MinTravel, "sem curso, ainda sobra o piso de duração")
	end)

	t:test("o passageiro afundado volta para a laje em vez de guardar a queda do quadro", function()
		-- VISTO EM PLAY: o corpo entra no chão da cabine enquanto ela sobe, e quem olha o vizinho vê
		-- pior ainda. O carry somava só o DELTA do quadro, então tudo o que a física tirasse entre um
		-- quadro e o outro ficava guardado para sempre. MEDIDO: Gravity 196.2 e 60 Hz dão 0.027 stud
		-- por quadro sem contato resolvido, contra 0.047 de subida a 2.8 studs/s — a sobra se soma
		-- quadro a quadro até o corpo atravessar a laje. A altura absoluta devolve a folga inteira.
		local top = 2.184
		local rise = 0.047
		local stand = top + rise + ElevatorConfig.RideStand
		local sunk = top + ElevatorConfig.RideStand - 0.081

		t:assertNear(ElevatorConfig.RideY(top + rise, sunk, rise), stand, 1e-6, "quem afundou volta para a laje")
		t:assertNear(sunk + rise, stand - 0.081, 1e-6, "somar só o delta guardaria os três quadros de queda")
		t:assertNear(
			ElevatorConfig.RideY(top + rise, top + ElevatorConfig.RideStand, rise),
			stand,
			1e-6,
			"de pé, a altura sai da laje nova"
		)
	end)

	t:test("quem salta dentro da cabine sobe junto em vez de ser cravado no piso", function()
		-- MEDIDO no rig do place: JumpHeight 7.2 com Gravity 196.2 dá 53.2 studs/s de saída, 0.886 stud
		-- no primeiro quadro a 60 Hz — bem acima da faixa de 0.5 que conta como de pé. Cravar todo
		-- quadro tiraria o salto inteiro dentro da cabine; só levar o delta deixaria o corpo afundar.
		local top = 2.184
		local rise = 0.047
		local jumped = top + ElevatorConfig.RideStand + 0.886

		t:assert(ElevatorConfig.RideCatch < 0.886, "a faixa de pé engoliria o primeiro quadro do salto")
		t:assertNear(ElevatorConfig.RideY(top + rise, jumped, rise), jumped + rise, 1e-6, "no ar, o delta")
		t:assertNear(ElevatorConfig.RideStand, 1.937 + 1, 1e-3, "HipHeight mais a meia altura do HumanoidRootPart")
	end)

	t:test("o visor parado ocupa a mesma largura do visor em curso", function()
		-- MEDIDO na fonte do visor, PressStart2P, que é monoespaçada: " 01" e "▲01" dão os mesmos 84
		-- px. Tirar a seta em vez de trocá-la por espaço encurta o texto, e com TextScaled ligado o
		-- número parado incharia a cada parada.
		local idle = ElevatorConfig.ScreenText(2, 0)
		local up = ElevatorConfig.ScreenText(3, 1)
		local down = ElevatorConfig.ScreenText(1, -1)

		t:assertEqual(idle, " 01", "parado em F1")
		t:assertEqual(up, "▲02", "subindo para F2")
		t:assertEqual(down, "▼00", "descendo para F0")
		t:assertEqual(utf8.len(idle), utf8.len(up), "parado e subindo têm o mesmo número de células")
		t:assertEqual(utf8.len(idle), utf8.len(down), "parado e descendo têm o mesmo número de células")
	end)

	t:test("a porta fica no andar do próprio jogador, e não num andar fixo", function()
		-- Existe UM Model de porta, e cada cliente o desenha no andar do jogador dele. É a porta que
		-- tapa o poço: presa num andar, os outros dois ficam com um buraco de 16 studs — e a cópia por
		-- andar, que parece o conserto óbvio, exigiria autorar duas portas que o place não tem.
		local parked = { floor = 2, going = 0, open = false }

		t:assertEqual(ElevatorConfig.DoorFloor(parked, 1, false), 1, "jogador em F0 vê a porta dele em F0")
		t:assertEqual(ElevatorConfig.DoorFloor(parked, 3, false), 3, "jogador em F2 vê a porta dele em F2")
	end)

	t:test("em curso o posto da porta fica no andar de PARTIDA, e só vira o destino na chegada", function()
		-- Trocar de posto TELEPORTA a porta, então ela troca sempre fechada de uma vez — é para isso
		-- que serve. Apontá-la para o destino no instante do pedido dispara essa troca com a folha
		-- ainda aberta: ela fecha seca em vez de correr, e o curso suave morre sem erro nenhum. Foi o
		-- que aconteceu quando `going` passou a valer desde o pedido, e não desde a partida.
		-- Seguir o Y do passageiro também não serve: ele varre o poço e a porta trocaria de posto no
		-- meio do caminho.
		local moving = { floor = 2, going = 3, open = false }

		t:assertEqual(ElevatorConfig.DoorFloor(moving, 2, true), 2, "a porta pulou para o destino e fecharia seca")
		t:assertEqual(ElevatorConfig.DoorFloor(moving, 1, true), 2, "e também não segue o Y do passageiro")

		local arrived = { floor = 3, going = 0, open = true }
		t:assertEqual(ElevatorConfig.DoorFloor(arrived, 3, true), 3, "na chegada ela assume o andar novo")
	end)

	t:test("a porta de quem está dentro sobe colada na cabine, stud a stud", function()
		-- O vão da frente da cabine é aberto e o passageiro olha para a porta o caminho inteiro. Pô-la
		-- de uma vez no plano do destino — o que o andar da DECISÃO já diz — o faria subir com um
		-- buraco na frente do nariz até chegar. MEDIDO: F1 a F2 são 16.000 studs, e no meio do curso a
		-- porta tem de estar no meio, não em cima.
		local half = 16.000 / 2

		t:assertNear(ElevatorConfig.DoorLift(3, half, true), half, 1e-6, "no meio do curso a porta ficou para trás")
		t:assertNear(ElevatorConfig.DoorLift(3, 16.000, true), 16.000, 1e-6, "no fim do curso a porta chega junto")
		t:assertNear(ElevatorConfig.DoorLift(3, half, false), 16.000, 1e-6, "quem está fora vê a porta parada no andar dele")
		t:assertNear(ElevatorConfig.DoorLift(1, 0, false), -15.810, 1e-3, "e em F0 ela fica no plano de F0")
	end)

	t:test("a porta não abre com a cabine noutro andar nem em curso", function()
		-- É a porta que tapa o poço. Abrir com a cabine longe escancara um vão de 16 studs na tela de
		-- quem apertou, e o Model continua íntegro: ninguém vê erro, alguém cai.
		local away = { floor = 3, going = 0, open = true }
		t:assert(not ElevatorConfig.Operable(away, 2), "a porta de F1 obedeceu com a cabine em F2")
		t:assert(ElevatorConfig.Operable(away, 3), "a porta de F2 tinha de obedecer")
		t:assert(not ElevatorConfig.DoorOpen(away, 2), "abriu em F1 com a cabine em F2")
		t:assert(ElevatorConfig.DoorOpen(away, 3), "não abriu em F2 com a cabine parada e aberta ali")

		local moving = { floor = 2, going = 3, open = true }
		t:assert(not ElevatorConfig.Operable(moving, 2), "obedeceu com a cabine em curso")
		t:assert(not ElevatorConfig.DoorOpen(moving, 3), "abriu no destino antes de a cabine chegar")
	end)

	t:test("aberto é compartilhado, mas só vale no andar em que a cabine está", function()
		-- Dois jogadores no mesmo andar da cabine veem a MESMA porta abrir, porque `open` é um atributo
		-- só. O terceiro, noutro andar, não vê nada: sem esse recorte, abrir para um abriria o poço
		-- para os outros dois.
		local shut = { floor = 2, going = 0, open = false }
		local open = { floor = 2, going = 0, open = true }

		t:assert(not ElevatorConfig.DoorOpen(shut, 2), "fechada é fechada")
		t:assert(ElevatorConfig.DoorOpen(open, 2), "quem divide o andar com a cabine vê a porta abrir")
		t:assert(not ElevatorConfig.DoorOpen(open, 1), "o andar de baixo viu a porta do outro abrir")
		t:assert(not ElevatorConfig.DoorOpen(open, 3), "o andar de cima viu a porta do outro abrir")
	end)

	t:test("o visor da porta diz ocupado quando a cabine não está no andar dela", function()
		-- Sem isso o jogador aperta e nada acontece, sem saber por quê. As respostas têm a mesma
		-- largura porque a fonte é monoespaçada: texto mais curto incharia com TextScaled ligado.
		local free = { floor = 2, going = 0, open = false }
		local moving = { floor = 2, going = 3, open = false }

		t:assertEqual(ElevatorConfig.DoorText(free, 2), " 01", "cabine parada no andar da porta")
		t:assertEqual(ElevatorConfig.DoorText(free, 3), ElevatorConfig.ScreenBusy, "de F2 a cabine está longe")
		t:assertEqual(ElevatorConfig.DoorText(moving, 2), "▲02", "em curso a porta vê para onde ela vai")
		t:assertEqual(utf8.len(ElevatorConfig.ScreenBusy), utf8.len(" 01"), "ocupado tem outra largura")
	end)

	t:test("o visor de dentro mostra o destino, e o da porta mostra o mesmo em curso", function()
		local moving = { floor = 3, going = 1, open = false }
		t:assertEqual(ElevatorConfig.CabinText(moving), "▼00", "descendo de F2 para F0")
		t:assertEqual(ElevatorConfig.DoorText(moving, 2), "▼00", "a porta do andar do meio vê a mesma descida")

		local parked = { floor = 3, going = 0, open = false }
		t:assertEqual(ElevatorConfig.CabinText(parked), " 02", "parada em F2")
	end)

	t:test("curso em andamento não é interrompido, por mais tarde que o pedido chegue", function()
		-- Um segundo pedido no meio da subida trocaria o destino com a cabine no ar, e o passageiro
		-- pararia entre dois andares. `going ~= 0` recusa, e recusa é diferente de enfileirar: o
		-- pedido morre, senão a cabine sairia de novo sozinha assim que chegasse.
		local moving = { floor = 2, going = 3, open = false }

		t:assert(not ElevatorConfig.Accepts(moving, 0, 0), "aceitou pedido com a cabine em curso")
		t:assert(not ElevatorConfig.Accepts(moving, 1e9, 0), "o tempo passou e ela ainda estava em curso")
	end)

	t:test("um curso novo espera os 3 s depois do anterior, e a porta espera depois de FECHAR", function()
		-- MEDIDO no comportamento pedido: 3 s entre um curso e o próximo, e alguns segundos depois de a
		-- folha fechar. Sem o resfriamento, o mesmo botão abre e fecha em sequência — a folha vira um
		-- bate-e-volta —, e um segundo andar apertado na chegada faz a cabine sair sem parar de fato.
		-- Abrir NÃO cobra resfriamento: quem viu a porta abrir pode fechá-la assim que ela para.
		t:assertEqual(ElevatorConfig.MoveCooldown, 3, "o intervalo entre cursos")
		t:assert(ElevatorConfig.DoorCooldown > 0, "sem resfriamento a porta aceita o toque seguinte na hora")

		local run = DoorConfig.ElevatorCloseTime
		t:assertNear(run, 1.43, 1e-6, "a folha corre 1.43 s, e é ela que o resfriamento espera")
		t:assertNear(ElevatorConfig.DoorHold(run, true), run, 1e-6, "abrir só espera a folha parar")
		t:assertNear(ElevatorConfig.DoorHold(run, false), run + ElevatorConfig.DoorCooldown, 1e-6, "fechar espera a folha e o resfriamento")

		local parked = { floor = 2, going = 0, open = false }
		t:assert(not ElevatorConfig.Accepts(parked, 100, 103), "aceitou antes de o resfriamento vencer")
		t:assert(ElevatorConfig.Accepts(parked, 103, 103), "no instante exato já vale")
	end)

	t:test("o curso sai do relógio do servidor, e não de um cronômetro que começa no aviso", function()
		-- MEDIDO: F1 a F2 são 16.000 studs, 5.714 s a 2.8 studs/s. Um cronômetro local poria a cabine em
		-- alturas diferentes em cada tela, e quem recebesse o Model pelo streaming no meio da viagem a
		-- veria recomeçar do andar de partida — atravessando a laje na frente de quem já estava lá.
		local started = 1000
		local duration = ElevatorConfig.Travel(0, 16.000)

		t:assertNear(duration, 5.714, 1e-3, "o curso de um andar")
		t:assertNear(ElevatorConfig.Progress(started, started, duration), 0, 1e-6, "no instante da partida")
		t:assertNear(ElevatorConfig.Progress(started, started + duration / 2, duration), 0.5, 1e-6, "quem chegou no meio pega o meio")
		t:assertNear(ElevatorConfig.Progress(started, started + 12, duration), 1, 1e-6, "depois do fim não passa de 1")
		t:assertNear(ElevatorConfig.Progress(started, started - 3, duration), 0, 1e-6, "relógio atrasado não volta o curso")
		t:assertNear(ElevatorConfig.Progress(started, started, 0), 1, 1e-6, "sem curso, já chegou")
	end)

	t:test("uma correção do relógio do servidor no meio do curso não sacode a cabine", function()
		-- VISTO EM PLAY: a cabine treme na subida. `Workspace:GetServerTimeNow()` é uma estimativa
		-- sincronizada, e a página dele NÃO TEM DESCRIÇÃO: de quanto ele se corrige não está
		-- documentado e não dá para medir fora de Play — os 0.010 s abaixo são a escala do efeito, não
		-- uma medição. Lido a cada quadro, cada correção entra direto na altura; ancorado uma vez por
		-- curso, o curso corre pelo relógio local e continua saindo do mesmo instante em toda tela.
		local span = ElevatorConfig.Travel(0, 16.000)

		t:assertEqual(ElevatorConfig.Anchor(100, 1000, 1000), 100, "o curso que sai agora começa no agora local")
		t:assertNear(
			ElevatorConfig.Progress(ElevatorConfig.Anchor(100, 1000, 1000), 100 + span / 2, span),
			0.5,
			1e-6,
			"o meio do curso pelo relógio local"
		)

		local ahead = ElevatorConfig.Progress(1000, 1000 + span / 2 + 0.010, span)
		local behind = ElevatorConfig.Progress(1000, 1000 + span / 2 - 0.010, span)
		t:assertNear((ahead - behind) * 16.000, 0.056, 1e-3, "0.020 s de correção valem 0.056 stud de salto")

		-- `StartedAt` vem no FUTURO, com o fechamento da folha embutido: a âncora vira espera local.
		local lead = ElevatorConfig.Anchor(100, 1000, 1001.43)
		t:assertNear(lead, 101.43, 1e-6, "o instante publicado no futuro continua no futuro")
		t:assertEqual(ElevatorConfig.Progress(lead, 100, span), 0, "com a folha ainda fechando, a cabine não saiu")
	end)

	t:test("o desenho do elevador corre antes da câmera, e não depois da física", function()
		-- VISTO EM PLAY: de dentro da cabine, ela e os outros jogadores tremem. MEDIDO no Studio: por
		-- quadro os `BindToRenderStep` correm em ordem de prioridade e só então vem `PreRender`; o
		-- passo de render vem ANTES da física do quadro. Desenhar em `PreSimulation` deixava a física
		-- mexer no corpo DEPOIS da correção, e a sobra do quadro ia parar na câmera, que mora na
		-- cabeça de quem viaja — de dentro, o mundo inteiro treme junto.
		t:assert(
			ElevatorConfig.RenderOrder < Enum.RenderPriority.Camera.Value,
			"a correção do corpo precisa chegar antes de a câmera ler a cabeça"
		)
		t:assertEqual(ElevatorConfig.RenderOrder, 199, "uma casa antes de Camera, que é 200")
		t:assert(#ElevatorConfig.RenderStep > 0, "o passo ligado por nome precisa de nome para ser desligado")
	end)

	t:test("a caixa da cabine sobe com ela, mesmo com a laje do servidor parada", function()
		-- O servidor não move peça nenhuma: a laje dele fica na pose autorada a partida inteira. Testar
		-- contra a laje crua diria que ninguém está dentro assim que a cabine sai de F1, e o elevador
		-- ficaria eternamente livre — abrindo a porta para outro jogador com um passageiro dentro.
		local model, floor = fakeCabin()
		local upstairs = Vector3.new(FLOOR_CENTER.X, FLOOR_TOP + 16.000 + 2.937, FLOOR_CENTER.Z)

		t:assert(ElevatorConfig.InsideAt(floor, upstairs, 16.000), "com a cabine em F2 ele está dentro")
		t:assert(not ElevatorConfig.InsideAt(floor, upstairs, 0), "com a cabine em F1 ele não está")
		t:assert(not ElevatorConfig.Inside(floor, upstairs), "a laje crua não alcança o andar de cima")

		model:Destroy()
	end)

	t:test("o andar em que a porta foi autorada sai da altura dela, e não de um número no código", function()
		-- MEDIDO: a folha da porta está em Y 5.258, 3.074 acima do plano de F1. É desse andar que sai o
		-- zero do deslocamento vertical dela; escrito à mão, mover a porta no place a faria nascer
		-- deslocada, e ela tamparia o vão do andar errado.
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, 5.258), 2, "a porta de hoje foi autorada em F1")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, 5.258 - 15.810), 1, "a mesma porta descida para F0")
		t:assertEqual(ElevatorConfig.FloorAt(FLOOR_TOP, 5.258 + 16.000), 3, "a mesma porta subida para F2")
	end)

	t:test("`Screen` não é tecla, e o corpo do painel também não", function()
		-- As duas são peças filhas de `Control` como qualquer botão. O visor tem um TextButton dentro —
		-- é assim que ele foi autorado —, então varrer por GuiButton sem tirá-lo faz o visor virar
		-- tecla: clicar no número mandaria a cabine para lugar nenhum e afundaria o visor.
		local model = fakeCabin()
		local rig = ElevatorConfig.Rig(model)
		t:assert(rig ~= nil, "rig da cabine")

		for _, key in ipairs(rig.keys) do
			t:assert(key.part.Name ~= ElevatorConfig.ScreenName, "o visor entrou como tecla")
			t:assert(key.part ~= rig.screen, "o visor entrou como tecla")
		end

		t:assertEqual(#rig.keys, 5, "três andares mais Open e Close")
		model:Destroy()
	end)

	t:test("`Open` e `Close` têm duas teclas cada, e as duas precisam responder", function()
		-- MEDIDO no place: `Open` traz dois TextButton chamados `Button`, e `Close` traz `Button` e
		-- `Button1` — cada seta é desenhada em dois pedaços. Ligar só o primeiro, como o teclado do
		-- telefone faz, deixa metade da seta morta, e o jogador que clica na metade errada acha que a
		-- porta travou.
		local model = fakeCabin()
		local rig = ElevatorConfig.Rig(model)
		local found = {}

		for _, key in ipairs(rig.keys) do
			found[key.part.Name] = #key.buttons
		end

		t:assertEqual(found[ElevatorConfig.OpenName], 2, "Open perdeu uma metade")
		t:assertEqual(found[ElevatorConfig.CloseName], 2, "Close perdeu uma metade")
		t:assertEqual(found.F1, 1, "tecla de andar tem um botão só")
		model:Destroy()
	end)

	t:test("toda tecla de andar do painel tem andar, e Open/Close não viram andar", function()
		-- O nome da peça é o vínculo entre o painel e a lista de andares, e não há nada que o garanta
		-- além disto: um `F3` autorado no place não acha andar e a tecla fica muda.
		local model = fakeCabin()
		local rig = ElevatorConfig.Rig(model)

		for _, key in ipairs(rig.keys) do
			local name = key.part.Name
			if name ~= ElevatorConfig.OpenName and name ~= ElevatorConfig.CloseName then
				t:assert(ElevatorConfig.IndexOf(name) ~= nil, name .. " não é andar nenhum")
			end
		end

		t:assertEqual(ElevatorConfig.IndexOf(ElevatorConfig.OpenName), nil, "Open não é andar")
		t:assertEqual(ElevatorConfig.IndexOf(ElevatorConfig.CloseName), nil, "Close não é andar")
		t:assertEqual(ElevatorConfig.IndexOf("F3"), nil, "andar que não existe devolve nada")
		model:Destroy()
	end)

	t:test("a tecla afunda pela face da SurfaceGui, e não pela base da peça", function()
		-- MEDIDO: as teclas do painel estão deitadas de lado na parede da cabine — o LookVector de `F1`
		-- é (-1, 0, 0) —, e a face da SurfaceGui é `Front`, que é o -Z LOCAL. Afundar pelo -Y, como as
		-- teclas do telefone, empurraria a tecla para fora do painel de lado.
		t:assertEqual(ElevatorConfig.FaceAxis(Enum.NormalId.Front), -Vector3.zAxis, "Front é o -Z local")
		t:assertEqual(ElevatorConfig.FaceAxis(Enum.NormalId.Back), Vector3.zAxis, "Back é o +Z local")
		t:assertEqual(ElevatorConfig.FaceAxis(Enum.NormalId.Top), Vector3.yAxis, "Top é o +Y local")
		t:assertEqual(ElevatorConfig.FaceAxis(nil), -Vector3.zAxis, "sem SurfaceGui, cai no Front")
	end)

	t:test("cabine sem laje ou sem painel não monta rig em vez de montar pela metade", function()
		-- Com streaming as peças chegam depois do Model. Rig montado sem a laje não teria caixa, e
		-- `Inside` responderia sempre não: o painel nunca ligaria e o elevador ficaria morto, calado.
		local model = fakeCabin()

		local floor = model:FindFirstChild(ElevatorConfig.FloorName)
		floor.Parent = nil
		t:assertEqual(ElevatorConfig.Rig(model), nil, "sem laje não há rig")
		floor.Parent = model

		local panel = model:FindFirstChild(ElevatorConfig.PanelName)
		panel.Parent = nil
		t:assertEqual(ElevatorConfig.Rig(model), nil, "sem painel não há rig")

		model:Destroy()
		panel:Destroy()
	end)
end
