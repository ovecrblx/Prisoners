-- Desenho do elevador de workspace.Siland_Home, local em cada cliente.
-- A CABINE é uma só no mundo: o andar, o destino e o aberto vêm dos atributos do servidor, e a altura
-- é interpolada do instante publicado — não de um cronômetro que começa quando o aviso chega. Assim
-- todas as telas a mostram na mesma altura, e quem recebe o Model pelo streaming no meio da viagem
-- entra na altura certa em vez de recomeçar do andar de partida.
-- A PORTA é de cada jogador: o Model é um só, e aqui ele é desenhado no andar do jogador DESTE
-- cliente. É ela que tapa o poço, então ela acompanha quem olha — parada no andar de quem está fora,
-- e subindo colada na cabine para quem está dentro. Abrir e fechar não é decidido aqui — vem do
-- servidor —, mas só vale no andar em que a cabine está.
-- O painel é o mesmo gesto do teclado do telefone: CanQuery ligado enquanto vale, botão de GUI de
-- mundo pelo Pointer, e tudo devolvido ao sair. A tecla pede; quem decide é o servidor.
local ElevatorController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))
local ElevatorConfig = require(Shared:WaitForChild("ElevatorConfig"))
local Lib = script.Parent.Parent:WaitForChild("Lib")
local Pointer = require(Lib:WaitForChild("Pointer"))
local Sfx = require(Lib:WaitForChild("Sfx"))

local player = Players.LocalPlayer

local cabin
local rig
local cabinScreen
local homeCabin
local homePrimary
local homeTop
local remote

local door
local doorScreen
local doorParts = {}
local doorLeaves = {}
local doorAxis
local doorHome = 1
local doorFloor = 1
local doorLift = 0
local alpha = 0
local from = 0
local target = 0
local elapsed = 0
local duration = 0
local blocking

local state = { floor = 1, going = 0, startedAt = 0, open = false }
local lift = 0
local riding = false
local riders = {}
local rideAnchor = 0
local rideOn = false
local rideBed
local rideRush = false
local rideStop = 1
local shakeStart = 0
local shakeAxis = Vector3.zero
local shakeSize = 0
local shakeRider = false
local passFloor = 0
local startArmed = false
local stopShook = false

-- Espelho local dos resfriamentos do servidor, que ele guarda em `os.clock()` e não publica. Servem
-- só para o som de recusa: o pedido vai para o servidor de qualquer jeito, e quem decide continua
-- sendo ele. Erram pela latência da réplica, e errar aqui toca um som a mais ou a menos, nunca perde
-- um comando.
local moveReady = 0
local doorReady = 0

local stepBound
local attributeLink
local pending = false

local bound = false
local links = {}
local queries = {}
local presses = {}
local retire = {}

local probe = RaycastParams.new()
probe.FilterType = Enum.RaycastFilterType.Include
probe.RespectCanCollide = true

local step

local function basePivot()
	return homeCabin + Vector3.new(0, lift, 0)
end

local function ensureStep()
	if not stepBound then
		stepBound = true
		RunService:BindToRenderStep(ElevatorConfig.RenderStep, ElevatorConfig.RenderOrder, step)
	end
end

-- Visor: o número e as setas, achados pelo NOME na SurfaceGui da peça e ordenados pela ALTURA em que
-- foram autorados. O vão entre duas setas vizinhas é o passo do desfile, então mover ou acrescentar
-- uma seta no place não exige tocar em código. A pose de cada uma fica guardada para a devolução.
local function screenRig(part)
	local gui = part and part:FindFirstChildWhichIsA("SurfaceGui")

	if not gui then
		return nil
	end

	local arrows = {}

	for _, child in ipairs(gui:GetChildren()) do
		local writes = child:IsA("TextLabel") or child:IsA("TextButton")

		if writes and string.sub(child.Name, 1, #ElevatorConfig.ScreenArrow) == ElevatorConfig.ScreenArrow then
			arrows[#arrows + 1] = child
		end
	end

	table.sort(arrows, function(first, second)
		return first.Position.Y.Scale < second.Position.Y.Scale
	end)

	local entry = { number = gui:FindFirstChild(ElevatorConfig.ScreenNumber), arrows = arrows, home = {} }

	for index, arrow in ipairs(arrows) do
		entry.home[index] = { pose = arrow.Position, text = arrow.Text, fade = arrow.TextTransparency }
	end

	entry.lowest = if arrows[1] then arrows[1].Position.Y.Scale else 0
	entry.span = if arrows[1]
		then ElevatorConfig.ArrowSpan(entry.lowest, arrows[#arrows].Position.Y.Scale, #arrows)
		else 0

	if entry.number then
		entry.numberHome = { text = entry.number.Text, fade = entry.number.TextTransparency }
	end

	return entry
end

local function restoreScreen(entry)
	if not entry then
		return
	end

	for index, arrow in ipairs(entry.arrows) do
		if arrow.Parent then
			local home = entry.home[index]
			arrow.Position = home.pose
			arrow.Text = home.text
			arrow.TextTransparency = home.fade
		end
	end

	if entry.number and entry.number.Parent and entry.numberHome then
		entry.number.Text = entry.numberHome.text
		entry.number.TextTransparency = entry.numberHome.fade
	end
end

-- O visor de um quadro. O número só é reescrito quando muda de verdade — isto roda a cada quadro, e
-- gravar a mesma string suja a propriedade à toa. As setas vão sempre, porque é o que as anima:
-- parada a cabine elas somem e voltam à pose autorada, e o número sozinho diz onde ela está.
local function drawScreen(entry, text, direction, settled)
	local number = entry.number

	if number and number.Parent then
		local fade = if settled then ElevatorConfig.NumberHere else ElevatorConfig.NumberPassing

		if number.Text ~= text then
			number.Text = text
		end

		if number.TextTransparency ~= fade then
			number.TextTransparency = fade
		end
	end

	local glyph = if direction < 0 then ElevatorConfig.ArrowDown else ElevatorConfig.ArrowUp
	local phase = (os.clock() / ElevatorConfig.ArrowPeriod) % 1

	for index, arrow in ipairs(entry.arrows) do
		if arrow.Parent then
			local home = entry.home[index]

			if direction == 0 then
				if arrow.TextTransparency ~= 1 then
					arrow.TextTransparency = 1
				end

				if arrow.Position ~= home.pose then
					arrow.Position = home.pose
				end
			else
				local cycle, fade = ElevatorConfig.Arrow(index - 1, #entry.arrows, phase, direction)
				local y = if entry.span > 0 then entry.lowest + cycle * entry.span else home.pose.Y.Scale

				if arrow.Text ~= glyph then
					arrow.Text = glyph
				end

				arrow.TextTransparency = fade
				arrow.Position = UDim2.new(home.pose.X.Scale, home.pose.X.Offset, y, home.pose.Y.Offset)
			end
		end
	end
end

local function paint()
	if cabinScreen then
		drawScreen(cabinScreen, ElevatorConfig.Screen(state, lift))
	end

	if doorScreen then
		drawScreen(doorScreen, ElevatorConfig.Screen(state, lift))
	end
end

local function applyKeys(pivot)
	for part, entry in pairs(presses) do
		if part.Parent then
			part.CFrame = (pivot * entry.rest) * CFrame.new(entry.axis * (-ElevatorConfig.KeyDepth * entry.phase))
		end
	end
end

-- A cabine vai de PivotTo, com `PrimaryPart` apontado para a laje: sem ele o pivô é o centro da caixa
-- dos filhos, e uma peça que o streaming traga depois muda o pivô e faz a cabine inteira saltar.
local function poseCabin()
	local pivot = basePivot()
	cabin:PivotTo(pivot)
	applyKeys(pivot)
end

-- A folha fechada é o que tapa o poço no andar deste jogador, e ela é publicada com CanCollide
-- desligado — MEDIDO. Com a cabine noutro andar, atravessar a porta é uma queda de 16 studs.
local function block(on)
	if blocking == on then
		return
	end

	blocking = on

	for _, leaf in ipairs(doorLeaves) do
		leaf.part.CanCollide = on
	end
end

-- A porta vai peça a peça, e não de PivotTo: o pivô do Model dela cairia numa folha que anda.
local function poseDoor()
	if not door then
		return
	end

	local rise = Vector3.new(0, doorLift - ElevatorConfig.Floors[doorHome].Lift, 0)

	for _, entry in ipairs(doorParts) do
		if entry.part.Parent then
			entry.part.CFrame = entry.home + rise
		end
	end

	for _, leaf in ipairs(doorLeaves) do
		leaf.part.CFrame = leaf.closed + rise + doorAxis * (leaf.travel * alpha)
	end

	block(alpha <= 0)
end

local function root()
	local character = player.Character
	if not character then
		return nil, nil
	end

	return character, character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
end

-- A peça da cabine sob os pés do jogador. Filtro por inclusão: fora da cabine o raio não acha nada, e
-- é assim que o corredor se distingue do vão da porta, que é peça da cabine.
local function ground(position)
	probe.FilterDescendantsInstances = { cabin }

	local hit = Workspace:Raycast(position, Vector3.new(0, -ElevatorConfig.RideProbe, 0), probe)
	return hit and hit.Instance or nil
end

local function aboard()
	local character, base = root()

	if not (character and base) then
		return false
	end

	return ElevatorConfig.Aboard(rig.floor, base.Position, ground(base.Position))
end

-- Quem a cabine leva neste curso, decidido por ESTE cliente para TODOS os personagens. A cabine é
-- desenho local, então o passageiro também tem que ser: a posição do vizinho chega pela rede alguns
-- quadros atrasada, e desenhá-lo por ela o enterra na laje enquanto ela sobe.
local function scanRiders()
	table.clear(riders)

	for _, other in ipairs(Players:GetPlayers()) do
		local character = other.Character
		local base = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))

		if base and ElevatorConfig.Aboard(rig.floor, base.Position, ground(base.Position)) then
			riders[character] = true
		end
	end

	riding = player.Character ~= nil and riders[player.Character] == true
end

-- O passageiro é levado por altura ABSOLUTA, e não pelo delta do quadro: peça ancorada movida por
-- CFrame não leva ninguém junto, e o que a física tirar num quadro o delta guarda para sempre — é
-- essa sobra somada que afunda o corpo na laje. Quem está no ar leva o delta, senão o salto some.
local function carry(slabTop, rise)
	for character in pairs(riders) do
		local base = character.Parent and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))

		if base then
			local pivot = character:GetPivot()
			local wanted = ElevatorConfig.RideY(slabTop, pivot.Y, rise)

			character:PivotTo(pivot + Vector3.new(0, wanted - pivot.Y, 0))
		else
			riders[character] = nil
		end
	end

	riding = player.Character ~= nil and riders[player.Character] == true
end

-- Ancora o curso no relógio LOCAL. O relógio do servidor é lido UMA vez por curso: ele é estimativa
-- sincronizada e se corrige sozinha, e cada correção lida no meio do caminho entra direto na altura
-- da cabine.
local function anchorRide()
	rideAnchor = ElevatorConfig.Anchor(os.clock(), Workspace:GetServerTimeNow(), state.startedAt)
end

-- Devolve a altura e a fração crua do curso. `StartedAt` vem publicado no FUTURO, com a espera do
-- fechamento da porta embutida, e `Progress` grampeia o negativo em 0: enquanto a folha corre a
-- cabine fica parada no andar de partida, e sai sozinha quando o relógio alcança o instante marcado.
local function heightNow()
	local here = ElevatorConfig.Floors[state.floor].Lift

	if state.going == 0 then
		return here, 1
	end

	local goal = ElevatorConfig.Floors[state.going].Lift
	local span = ElevatorConfig.Travel(here, goal)
	local raw = ElevatorConfig.Progress(rideAnchor, os.clock(), span)

	return here + (goal - here) * TweenService:GetValue(raw, ElevatorConfig.Style, ElevatorConfig.Direction), raw
end

local function advanceDoor(delta)
	if alpha == target then
		return
	end

	elapsed = math.min(elapsed + delta, duration)

	local raw = if duration > 0 then elapsed / duration else 1
	alpha = from + (target - from) * TweenService:GetValue(raw, DoorConfig.ElevatorStyle, DoorConfig.ElevatorDirection)

	if elapsed >= duration then
		alpha = target
	end

	poseDoor()
end

-- O curso da tecla é escrito AQUI e não num tween: apertar um andar põe a cabine em movimento, e um
-- tween de CFrame absoluta deixaria a tecla parada na altura do andar de partida enquanto o resto da
-- cabine sobe.
local function advancePresses(delta)
	local span = ElevatorConfig.KeyTravel * 2
	table.clear(retire)

	for part, entry in pairs(presses) do
		entry.elapsed += delta

		local raw = math.min(entry.elapsed / span, 1)
		local wave = if raw < 0.5 then raw * 2 else (1 - raw) * 2
		entry.phase = TweenService:GetValue(wave, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

		if raw >= 1 then
			entry.phase = 0
			retire[#retire + 1] = part
		end
	end
end

-- Tranco da câmera, escrito em `Humanoid.CameraOffset` e NÃO na CFrame da câmera: este passo corre uma
-- casa ANTES do passo da câmera, e uma CFrame escrita aqui seria sobrescrita no mesmo quadro. O
-- offset o passo da câmera lê e aplica sozinho. A página do `CameraOffset` não tem descrição e não
-- diz o espaço; o exemplo dela é um balanço de caminhada em Y, que é o eixo que importa aqui.
local function clearShake()
	shakeStart = 0
	startArmed = false

	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

	if humanoid then
		humanoid.CameraOffset = Vector3.zero
	end
end

-- Um tranco só de quem está DENTRO: o vizinho no corredor vê a cabine passar e não sente nada.
local function startShake(size)
	if not shakeRider then
		return
	end

	shakeStart = os.clock()
	shakeSize = size
	shakeAxis = ElevatorConfig.ShakeAxis(math.random(), math.random(), math.random(), math.random())
end

-- Zerar no fim é obrigatório: parado no meio, o deslocamento fica preso e o jogador sai andando pelo
-- mapa com a cabeça torta. É por isso também que o passo não se desliga com tranco correndo.
local function applyShake()
	if shakeStart == 0 then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildWhichIsA("Humanoid")

	if not humanoid then
		shakeStart = 0
		return
	end

	local phase = (os.clock() - shakeStart) / ElevatorConfig.ShakeTime

	if phase >= 1 then
		shakeStart = 0
		humanoid.CameraOffset = Vector3.zero
		return
	end

	humanoid.CameraOffset = shakeAxis * (shakeSize * ElevatorConfig.ShakeFall(phase))
end

-- Quando o tranco entra. A laje cruzada sai do MESMO `PassedAt` que escreve o número do visor, então
-- o solavanco cai no quadro em que o número troca. A do DESTINO não conta: ela é a chegada, e a
-- chegada já tem o tranco dela, maior — contadas as duas, o jogador leva dois trancos colados.
-- A partida tranca no PRIMEIRO quadro em que a cabine anda, e só para quem viu o quadro anterior
-- parado: quem chegou com o curso em andamento levaria um tranco de partida no meio da viagem.
local function shakeRide(raw)
	if state.going == 0 then
		return
	end

	if raw <= 0 then
		shakeRider = riding
		passFloor = state.floor
		startArmed = true
		stopShook = false
		return
	end

	if startArmed then
		startArmed = false
		startShake(ElevatorConfig.ShakeStart)
	end

	if raw >= 1 then
		if not stopShook then
			stopShook = true
			startShake(ElevatorConfig.ShakeStop)
		end

		return
	end

	local here = ElevatorConfig.PassedAt(lift, ElevatorConfig.Heading(state))

	if here ~= passFloor then
		passFloor = here

		if here ~= state.going then
			startShake(ElevatorConfig.ShakePass)
		end
	end
end

-- Tira o leito de cena sem cortá-lo: ele desce a zero por cima do freio, que já começou, e só então
-- some. O sumiço vai por Tween e NÃO pelo passo de desenho — o passo se desliga quando a cabine para
-- e a folha assenta, e um leito no meio do fade ficaria tocando para sempre.
local function fadeBed(sound)
	local fade = TweenService:Create(
		sound,
		TweenInfo.new(ElevatorConfig.BedFade, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Volume = 0 }
	)

	fade.Completed:Connect(function()
		sound:Destroy()
	end)

	fade:Play()
end

-- Onde o freio deste curso entra, em fração, e se ele é o de alta. A conta sai do MESMO par de
-- andares que decide o leito, então leito e freio nunca discordam sobre o comprimento do curso.
local function rideBrake()
	local rush = ElevatorConfig.Rush(state.floor, state.going)
	local span = ElevatorConfig.Travel(
		ElevatorConfig.Floors[state.floor].Lift,
		ElevatorConfig.Floors[state.going].Lift
	)

	return rush, ElevatorConfig.StopAt(span, if rush then ElevatorConfig.RushStopLead else ElevatorConfig.StopLead)
end

-- Som do curso, em três tempos: partida, leito e freio. O leito nasce no primeiro quadro em que a
-- cabine ANDA e não quando o aviso chega — a partida vem publicada no FUTURO, com o fechamento da
-- folha embutido, e um leito que começasse no aviso roncaria 1.43 s com a cabine parada. O freio
-- entra ANTES da chegada, o quanto a gravação dele leva, para acabar no instante em que a cabine
-- para: entrando na chegada ele soa com ela já parada, e leva o pib junto, sempre. O leito não é
-- cortado quando o freio entra: ele some POR BAIXO de um freio que já está tocando. Quem guarda a vez
-- é `rideOn` e não o Sound: chave que falte devolve nil, e o leito seria repedido a cada quadro.
local function rideAudio(raw)
	if not rideOn then
		if state.going == 0 or raw <= 0 then
			return
		end

		local rush, stopAt = rideBrake()

		-- Entrou no meio do curso, com o freio já passado: sem leito para acompanhar, não há o que
		-- frear. Um pib avulso anunciaria uma chegada que este cliente não viu acontecer.
		if raw >= stopAt then
			return
		end

		rideOn = true
		rideRush = rush
		rideStop = stopAt

		Sfx.Play(ElevatorConfig.StartSound, rig.floor)
		rideBed = Sfx.Hold(ElevatorConfig.RunSound, rig.floor)
		return
	end

	if state.going ~= 0 and raw < rideStop then
		return
	end

	rideOn = false

	Sfx.Play(if rideRush then ElevatorConfig.RushStopSound else ElevatorConfig.StopSound, rig.floor)
	Sfx.Play(ElevatorConfig.DingSound, rig.floor)

	-- Depois dos dois: o leito sai por baixo de um freio que JÁ está tocando.
	if rideBed then
		fadeBed(rideBed)
		rideBed = nil
	end
end

-- Cala o curso SEM tocar a parada: a cabine não chegou, ela saiu da tela — streaming, ou o jogador
-- deixando a sala. O pib aqui anunciaria uma chegada que não houve.
local function hushRide()
	rideOn = false
	rideStop = 1

	if rideBed then
		rideBed:Destroy()
		rideBed = nil
	end
end

function step(delta)
	local height, raw = heightNow()

	-- Antessala: a porta ainda fecha e a cabine não saiu do lugar. Quem é o passageiro só congela no
	-- primeiro quadro em que ela ANDA — sem isso, quem apertou o andar e deu um passo para trás
	-- durante o fechamento sairia flutuando pelo corredor, carregado por uma cabine que ficou longe.
	if state.going ~= 0 and raw <= 0 then
		scanRiders()
	end

	rideAudio(raw)

	if height ~= lift then
		carry(homeTop + height, height - lift)
		lift = height
	end

	shakeRide(raw)
	applyShake()

	advancePresses(delta)
	poseCabin()

	local wanted = ElevatorConfig.DoorLift(doorFloor, lift, riding)
	if wanted ~= doorLift then
		doorLift = wanted
		poseDoor()
	end

	advanceDoor(delta)

	paint()

	for _, part in ipairs(retire) do
		presses[part] = nil
	end
	table.clear(retire)

	if state.going == 0 and alpha == target and not next(presses) and shakeStart == 0 and stepBound then
		stepBound = nil
		RunService:UnbindFromRenderStep(ElevatorConfig.RenderStep)
	end
end

local function aim(open, animate)
	local wanted = if open then 1 else 0

	if target == wanted then
		return
	end

	from = alpha
	target = wanted
	elapsed = 0

	if not animate then
		alpha = wanted
		duration = 0
		poseDoor()
		return
	end

	duration = if open then DoorConfig.ElevatorOpenTime else DoorConfig.ElevatorCloseTime
	Sfx.Play(if open then ElevatorConfig.OpenSound else ElevatorConfig.CloseSound, doorLeaves[1].part)
	ensureStep()
end

-- A porta muda de andar de uma vez e fechada. Ela é o tampo do poço: descer junto com a cabine, ou
-- acompanhar o jogador em curso, deixaria o vão do andar dele aberto no caminho.
local function parkDoor(animate)
	if door then
		local _, base = root()
		local here = if base then ElevatorConfig.FloorAt(homeTop, base.Position.Y) else doorFloor
		local wanted = ElevatorConfig.DoorFloor(state, here, riding or aboard())
		local moved = false

		if wanted ~= doorFloor then
			doorFloor = wanted
			alpha = 0
			from = 0
			target = 0
			elapsed = 0
			duration = 0
			moved = true
		end

		local height = ElevatorConfig.DoorLift(doorFloor, lift, riding)

		if height ~= doorLift then
			doorLift = height
			moved = true
		end

		if moved then
			poseDoor()
		end

		aim(ElevatorConfig.DoorOpen(state, doorFloor), animate)
	end

	paint()
end

-- Adiado de propósito. O servidor publica os atributos em sequência e cada um acorda este aviso: lido
-- no primeiro, o retrato mistura o andar novo com o destino velho, e a cabine salta um quadro para
-- uma altura que nunca existiu. O defer espera a leva inteira chegar.
local function sync()
	if pending then
		return
	end

	pending = true

	task.defer(function()
		pending = false

		if not cabin then
			return
		end

		local before = state.going
		local wasOpen = state.open
		state = ElevatorConfig.State(cabin)

		if before == 0 and state.going ~= 0 then
			anchorRide()
			scanRiders()
		elseif state.going == 0 then
			table.clear(riders)
			riding = false
		end

		if before ~= 0 and state.going == 0 then
			moveReady = os.clock() + ElevatorConfig.MoveCooldown
		end

		if wasOpen ~= state.open then
			local run = if state.open then DoorConfig.ElevatorOpenTime else DoorConfig.ElevatorCloseTime
			doorReady = os.clock() + ElevatorConfig.DoorHold(run, state.open)
		end

		parkDoor(true)
		ensureStep()
	end)
end

-- Resolvido na hora do clique, e não no boot: o serviço cria o evento no `Start` dele, e esperar por
-- ele aqui seguraria o desenho da cabine até o servidor subir.
local function bell()
	if remote then
		return remote
	end

	local box = ReplicatedStorage:FindFirstChild("Remotes")
	remote = box and box:FindFirstChild(ElevatorConfig.Remote)

	return remote
end

-- O que o servidor vai recusar, previsto AQUI só para o som: curso em andamento, resfriamento ainda
-- correndo, ou a tecla do andar em que a cabine já está. Espelha `travel` e `command` do serviço. O
-- pedido sai de qualquer jeito — prever errado toca um som a mais, prever e engolir perderia a tecla.
local function refused(name)
	local now = os.clock()

	if name == ElevatorConfig.OpenName or name == ElevatorConfig.CloseName then
		return not ElevatorConfig.Accepts(state, now, doorReady)
	end

	local index = ElevatorConfig.IndexOf(name)

	return index == nil or index == state.floor or not ElevatorConfig.Accepts(state, now, moveReady)
end

local function press(key)
	local part = key.part
	local entry = presses[part]

	if entry then
		entry.elapsed = 0
	else
		local gui = part:FindFirstChildWhichIsA("SurfaceGui")
		presses[part] = {
			rest = basePivot():ToObjectSpace(part.CFrame),
			axis = ElevatorConfig.FaceAxis(gui and gui.Face),
			elapsed = 0,
			phase = 0,
		}
	end

	ensureStep()
	Sfx.Play(ElevatorConfig.KeySound, part)

	if refused(part.Name) then
		Sfx.Play(ElevatorConfig.FailSound, part)
	end

	if not bell() then
		return
	end

	if part.Name == ElevatorConfig.OpenName or part.Name == ElevatorConfig.CloseName then
		remote:FireServer(part.Name)
		return
	end

	local index = ElevatorConfig.IndexOf(part.Name)
	if index then
		remote:FireServer(ElevatorConfig.GoAction, index)
	end
end

-- Clique em GUI de mundo sai de um raio do mouse contra a peça adornada, e as teclas do painel são
-- publicadas com CanQuery desligado — MEDIDO. Escrita local, devolvida ao sair da cabine.
local function bindPanel(on)
	if bound == on then
		return
	end

	bound = on

	if on then
		for _, key in ipairs(rig.keys) do
			queries[key.part] = key.part.CanQuery
			key.part.CanQuery = true

			for _, button in ipairs(key.buttons) do
				Pointer.Press(button, function()
					press(key)
				end, function() end, links)
				Pointer.Hover(button, links)
			end
		end

		return
	end

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)
	Pointer.Drop()

	for _, entry in pairs(presses) do
		entry.phase = 0
	end
	applyKeys(basePivot())
	table.clear(presses)

	for part, query in pairs(queries) do
		if part.Parent then
			part.CanQuery = query
		end
	end
	table.clear(queries)
end

local function dropDoor()
	if not door then
		return
	end

	restoreScreen(doorScreen)
	doorScreen = nil

	for _, leaf in ipairs(doorLeaves) do
		if leaf.part.Parent then
			leaf.part.CanCollide = leaf.collide
		end
	end

	for _, entry in ipairs(doorParts) do
		if entry.part.Parent then
			entry.part.CFrame = entry.home
		end
	end

	table.clear(doorParts)
	table.clear(doorLeaves)
	door = nil
	doorAxis = nil
	blocking = nil
	alpha = 0
	from = 0
	target = 0
end

local function detach()
	if not cabin then
		return
	end

	bindPanel(false)
	dropDoor()
	hushRide()
	clearShake()
	restoreScreen(cabinScreen)
	cabinScreen = nil

	if stepBound then
		stepBound = nil
		RunService:UnbindFromRenderStep(ElevatorConfig.RenderStep)
	end

	if attributeLink then
		attributeLink:Disconnect()
		attributeLink = nil
	end

	if cabin.Parent then
		lift = 0
		poseCabin()
		cabin.PrimaryPart = homePrimary
	end

	cabin = nil
	rig = nil
	lift = 0
	table.clear(riders)
	riding = false
end

-- Com streaming os Models vão e voltam, e voltam como instância nova, na pose do servidor: nada é
-- resolvido no boot e guardado para a partida inteira. O andar em que a porta foi autorada sai da
-- ALTURA dela, então mover a porta no place não exige tocar em código.
local function grabDoor(doors)
	if door and door.Parent and doorLeaves[1] and doorLeaves[1].part.Parent then
		return false
	end

	dropDoor()

	for _, model in ipairs(doors:GetChildren()) do
		local slide = model:IsA("Model") and DoorConfig.Kind(model) == "elevator" and DoorConfig.SlideRig(model)

		if slide then
			door = model
			doorScreen = screenRig(model:FindFirstChild(ElevatorConfig.ScreenName))
			doorAxis = slide.axis
			doorLeaves = slide.leaves

			for _, leaf in ipairs(doorLeaves) do
				leaf.closed = leaf.part.CFrame
				leaf.collide = leaf.part.CanCollide
			end

			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					doorParts[#doorParts + 1] = { part = part, home = part.CFrame }
				end
			end

			doorHome = ElevatorConfig.FloorAt(homeTop, doorLeaves[1].part.Position.Y)
			doorFloor = doorHome
			doorLift = ElevatorConfig.Floors[doorHome].Lift
			return true
		end
	end

	return false
end

local function attach(folder, doors)
	local nextCabin = folder:FindFirstChild(ElevatorConfig.ModelName)

	if nextCabin == cabin then
		return
	end

	detach()

	local nextRig = nextCabin and ElevatorConfig.Rig(nextCabin)

	if not nextRig then
		return
	end

	cabin = nextCabin
	rig = nextRig
	homePrimary = cabin.PrimaryPart
	cabin.PrimaryPart = rig.floor
	homeCabin = cabin:GetPivot()
	homeTop = rig.floor.Position.Y + rig.floor.Size.Y / 2
	cabinScreen = screenRig(rig.screen)

	state = ElevatorConfig.State(cabin)
	anchorRide()
	lift = ElevatorConfig.Floors[state.floor].Lift
	table.clear(riders)
	riding = false

	grabDoor(doors)
	poseCabin()
	poseDoor()
	parkDoor(false)

	attributeLink = cabin.AttributeChanged:Connect(sync)
end

function ElevatorController.Start()
	local folder = Workspace

	for _, name in ipairs(ElevatorConfig.Path) do
		folder = folder:WaitForChild(name, 20)
		if not folder then
			warn("[ElevatorController] workspace." .. table.concat(ElevatorConfig.Path, ".") .. " não encontrado.")
			return
		end
	end

	local doors = Workspace

	for _, name in ipairs(DoorConfig.Folder) do
		doors = doors:WaitForChild(name, 20)
		if not doors then
			warn("[ElevatorController] workspace." .. table.concat(DoorConfig.Folder, ".") .. " não encontrado.")
			return
		end
	end

	while true do
		attach(folder, doors)

		if cabin then
			if grabDoor(doors) then
				poseDoor()
			end

			parkDoor(true)
			bindPanel(aboard() or riding)
		end

		task.wait(ElevatorConfig.ScanInterval)
	end
end

return ElevatorController
