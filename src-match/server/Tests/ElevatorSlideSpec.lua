-- ElevatorSlideSpec — a porta do elevador: para que lado as folhas correm, quanto cada uma anda, e
-- onde fica o prompt.
--
-- O QUE ESTA SPEC PROTEGE. Door_Elevator mora na MESMA pasta das portas de dobradiça e usa a MESMA
-- convenção de nome (`Left Root`, `Right Root`), então o DoorService a adotava como porta comum e
-- girava as duas folhas 90 graus no lugar. O erro é mudo: as outras dez portas continuam abrindo, e
-- o console não diz nada. `DoorConfig.Kind` é o único lugar que separa as três famílias, e cada um
-- dos quatro módulos pergunta a ele.
--
-- A SEGUNDA ARMADILHA É O LADO. `Vector3.yAxis:Cross(normal)` devolve um eixo lateral qualquer, e no
-- elevador do place ele CALHA de apontar para o bolso — uma versão sem a correção de sinal passa
-- verde aqui e sai correndo para o corredor no primeiro elevador espelhado. Por isso o teste do
-- espelho existe.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local DoorConfig = t:freshRequire(ReplicatedStorage.Shared.DoorConfig)

	-- MEDIDO NO PLACE, em Door_Elevator: folhas de 2.850 x 6.230 x 0.497, a 1.229 do centro do vão
	-- para cada lado e separadas 0.446 em Z, uma atrás da outra. Botão `Call` de 0.600 x 1.400 x
	-- 0.100, a 3.004 de lado e 1.127 à frente do centro das folhas, do lado do corredor.
	local LEAF = Vector3.new(2.850, 6.230, 0.497)
	local SPREAD = 1.229
	local STAGGER = 0.223

	local function fakeElevator(turn, mirror)
		local model = Instance.new("Model")
		model.Name = "Door_Elevator"

		local side = mirror and -1 or 1
		local leaves = {
			{ name = "Left Root", at = Vector3.new(SPREAD * side, 0, -STAGGER) },
			{ name = "Right Root", at = Vector3.new(-SPREAD * side, 0, STAGGER) },
		}

		for _, spec in ipairs(leaves) do
			local part = Instance.new("Part")
			part.Name = spec.name
			part.Size = LEAF
			part.CFrame = turn * CFrame.new(spec.at)
			part.Parent = model
		end

		local call = Instance.new("Part")
		call.Name = DoorConfig.ElevatorCall
		call.Size = Vector3.new(0.600, 1.400, 0.100)
		call.CFrame = turn * CFrame.new(-3.004 * side, 0, -1.127)
		call.Parent = model

		return model, call
	end

	local function leafNamed(rig, name)
		for index, leaf in ipairs(rig.leaves) do
			if leaf.part.Name == name then
				return leaf, index
			end
		end
		return nil, 0
	end

	t:test("a porta do elevador não é adotada pela lógica de giro das portas comuns", function()
		-- MEDIDO: Door_Elevator tem `Left Root` e `Right Root`, e nenhuma das duas tem PivotOffset —
		-- então `LeafSign` recebe braço zero, devolve -1 para as duas, e a porta girava as duas
		-- folhas em torno do próprio centro. Nada quebra, nada avisa: só o elevador fica errado.
		local model = fakeElevator(CFrame.new(), false)
		t:assertEqual(#DoorConfig.Hinges(model), 2, "o elevador PARECE porta: duas folhas na convenção Root")
		t:assertEqual(DoorConfig.Kind(model), "elevator", "o elevador tem família própria")
		model:Destroy()

		local door = Instance.new("Model")
		door.Name = "Door_MainOffice"
		t:assertEqual(DoorConfig.Kind(door), "door", "porta comum continua sendo porta")
		door.Name = "Dual_Door_MachineRoom"
		t:assertEqual(DoorConfig.Kind(door), "door", "porta dupla é porta, e o dual é outro eixo")
		door.Name = "Curtain"
		t:assertEqual(DoorConfig.Kind(door), "curtain", "a cortina não pode virar elevador")
		door:Destroy()
	end)

	t:test("o nome do bolso obedece à convenção de folha, senão o rig nunca o acha", function()
		-- `SlideRig` exige que a folha do bolso esteja ENTRE as folhas, e folha é o que `Hinges`
		-- devolve. Um `ElevatorPocket` escrito fora da convenção não acusa: a porta some do jogo.
		local suffix = " " .. DoorConfig.HingeName
		local name = DoorConfig.ElevatorPocket
		t:assert(
			name == DoorConfig.HingeName or name:sub(-#suffix) == suffix,
			"ElevatorPocket é " .. name .. ", que Hinges nunca vai devolver"
		)
	end)

	t:test("as duas folhas correm para o lado da folha do bolso", function()
		local model = fakeElevator(CFrame.new(), false)
		local rig = DoorConfig.SlideRig(model)
		t:assert(rig ~= nil, "rig do elevador")

		local pocket = leafNamed(rig, DoorConfig.ElevatorPocket)
		local toPocket = pocket.part.Position - model:FindFirstChild("Right Root").Position
		model:Destroy()

		t:assert(rig.axis:Dot(toPocket) > 0, "o eixo aponta para longe do bolso")
		for _, leaf in ipairs(rig.leaves) do
			t:assert(leaf.travel > 0, leaf.part.Name .. " ficaria parada")
		end
	end)

	t:test("elevador espelhado corre para o outro lado, e não para o mesmo de sempre", function()
		-- ESTE é o teste que mata a simplificação. `yAxis:Cross(normal)` devolve +X no elevador do
		-- place, que por acaso é o lado do bolso, então o sinal cru passa despercebido. Com o bolso
		-- do outro lado — outro andar, outro elevador — as folhas correriam para o corredor e
		-- atravessariam a parede, sem um aviso sequer.
		local straight = fakeElevator(CFrame.new(), false)
		local flipped = fakeElevator(CFrame.new(), true)
		local a = DoorConfig.SlideRig(straight)
		local b = DoorConfig.SlideRig(flipped)
		straight:Destroy()
		flipped:Destroy()

		t:assert(a ~= nil and b ~= nil, "os dois rigs")
		t:assertNear(a.axis:Dot(b.axis), -1, 1e-3, "os dois bolsos são opostos")
	end)

	t:test("armário virado continua correndo para o bolso, não para o eixo do mundo", function()
		-- O eixo sai da folha e não de um Vector3 escrito à mão: o elevador do outro andar pode
		-- estar virado, e um eixo fixo o faria correr para o lado errado ou nem correr.
		local model = fakeElevator(CFrame.Angles(0, math.pi / 2, 0), false)
		local rig = DoorConfig.SlideRig(model)
		local pocket = leafNamed(rig, DoorConfig.ElevatorPocket)
		local toPocket = pocket.part.Position - model:FindFirstChild("Right Root").Position
		model:Destroy()

		t:assert(rig.axis:Dot(toPocket) > 0, "o eixo largou o bolso quando a porta virou")
		t:assertNear(rig.axis.Y, 0, 1e-6, "folha corre de lado, não sobe")
	end)

	t:test("cada folha anda o seu curso, e a de trás anda quase o dobro da da frente", function()
		-- MEDIDO: com o vão de 5.308 e folhas de 2.850, o curso pleno é 2.850 para a do bolso e
		-- 5.308 para a de trás; ElevatorTravel = 0.9 dá 2.565 e 4.777. Um deslocamento ÚNICO para as
		-- duas — a simplificação óbvia — deixaria a de trás parando onde a da frente estava, com
		-- metade do vão ainda tapada, e o jogador vendo a porta "abrir" sem abrir.
		local model = fakeElevator(CFrame.new(), false)
		local rig = DoorConfig.SlideRig(model)
		model:Destroy()

		local front = leafNamed(rig, "Left Root")
		local back = leafNamed(rig, "Right Root")
		t:assertNear(front.travel, 2.565, 1e-3, "curso da folha do bolso")
		t:assertNear(back.travel, 4.777, 1e-3, "curso da folha de trás")
		t:assert(back.travel > front.travel * 1.5, "as duas andam quase o mesmo; a de trás tapa o vão")
	end)

	t:test("a folha do bolso vem primeiro na lista", function()
		-- A ordem é a da pilha: quem para na frente é a primeira. Invertida, quem quiser escalonar o
		-- som ou o início do curso escalona ao contrário.
		local model = fakeElevator(CFrame.new(), false)
		local rig = DoorConfig.SlideRig(model)
		model:Destroy()

		local _, index = leafNamed(rig, DoorConfig.ElevatorPocket)
		t:assertEqual(index, 1, "a folha do bolso não é a primeira")
	end)

	t:test("a retração é quase completa, e não completa", function()
		-- O pedido é "quase por completo": a nesga que sobra é o que diz ao jogador que ali existe
		-- porta. Travel = 1 encosta a folha na borda e ela some; acima de 1 ela atravessa a parede.
		-- MEDIDO: com 0.9 sobram 0.531 stud da folha de trás e 0.285 da da frente dentro do vão.
		t:assert(DoorConfig.ElevatorTravel > 0.5, "abaixo disso a porta mal abre")
		t:assert(DoorConfig.ElevatorTravel < 1, "1 esconde a folha inteira, e acima ela fura a parede")

		local model = fakeElevator(CFrame.new(), false)
		local rig = DoorConfig.SlideRig(model)
		model:Destroy()

		local back = leafNamed(rig, "Right Root")
		local full = back.travel / DoorConfig.ElevatorTravel
		t:assertNear(full - back.travel, 0.531, 1e-3, "a nesga da folha de trás")
	end)

	t:test("elevador sem a folha do bolso fica parado em vez de escolher um lado", function()
		-- Sem saber onde é o bolso não há palpite honesto: correr para um lado arbitrário atravessa
		-- a parede. O rig devolve nada, e o serviço avisa no console.
		local model = fakeElevator(CFrame.new(), false)
		model:FindFirstChild(DoorConfig.ElevatorPocket):Destroy()
		local rig = DoorConfig.SlideRig(model)
		model:Destroy()

		t:assertEqual(rig, nil, "rig montado sem saber para que lado correr")
	end)

	t:test("a âncora do prompt sai do botão para o corredor, não para dentro do poço", function()
		-- MEDIDO: o botão tem 0.100 de espessura e fica rente à parede. A engine só mostra o prompt
		-- com caminho livre da câmera até ele; ancorado no miolo, ou empurrado para o lado das
		-- folhas, o prompt fica tapado e o elevador não pode ser chamado — sem erro nenhum.
		local model, call = fakeElevator(CFrame.new(), false)
		local anchor = DoorConfig.CallAnchor(call, Vector3.zero)
		local world = call.CFrame:PointToWorldSpace(anchor)
		model:Destroy()

		t:assertNear(anchor.Magnitude, 0.450, 1e-3, "meia espessura mais PromptDepth")
		t:assert(world.Z < call.Position.Z, "a âncora entrou no poço, do lado das folhas")
	end)
end
