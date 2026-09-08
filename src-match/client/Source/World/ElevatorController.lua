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
local homeCabin
local homePrimary
local homeTop
local remote

local door
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

local stepLink
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
	if not stepLink then
		stepLink = RunService.PreSimulation:Connect(step)
	end
end

local function label(part)
	if not (part and part.Parent) then
		return nil
	end

	return part:FindFirstChildWhichIsA("TextLabel", true) or part:FindFirstChildWhichIsA("TextButton", true)
end

local function write(part, text)
	local face = label(part)
	if face then
		face.Text = text
	end
end

local function paint()
	write(rig.screen, ElevatorConfig.CabinText(state))

	if door then
		write(door:FindFirstChild(ElevatorConfig.ScreenName), ElevatorConfig.DoorText(state, doorFloor))
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

-- Peça ancorada movida por CFrame não leva ninguém junto, então o passageiro anda o mesmo delta na
-- mão. Quem é o passageiro foi decidido quando a cabine SAIU, e não se remede a cada quadro: um
-- quadro em que a conta diga não — no salto, no encontrão — largaria no meio do poço quem está
-- dentro. Cada cliente move só o próprio personagem, e é por isso que dois passageiros funcionam.
local function carry(rise)
	local character, base = root()

	if not (character and base) then
		riding = false
		return
	end

	character:PivotTo(character:GetPivot() + rise)
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
	local raw = ElevatorConfig.Progress(state.startedAt, Workspace:GetServerTimeNow(), span)

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

function step(delta)
	local height, raw = heightNow()

	-- Antessala: a porta ainda fecha e a cabine não saiu do lugar. Quem é o passageiro só congela no
	-- primeiro quadro em que ela ANDA — sem isso, quem apertou o andar e deu um passo para trás
	-- durante o fechamento sairia flutuando pelo corredor, carregado por uma cabine que ficou longe.
	if state.going ~= 0 and raw <= 0 then
		riding = aboard()
	end

	if height ~= lift then
		if riding then
			carry(Vector3.new(0, height - lift, 0))
		end
		lift = height
	end

	advancePresses(delta)
	poseCabin()

	local wanted = ElevatorConfig.DoorLift(doorFloor, lift, riding)
	if wanted ~= doorLift then
		doorLift = wanted
		poseDoor()
	end

	advanceDoor(delta)

	for _, part in ipairs(retire) do
		presses[part] = nil
	end
	table.clear(retire)

	if state.going == 0 and alpha == target and not next(presses) and stepLink then
		stepLink:Disconnect()
		stepLink = nil
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
	Sfx.Play(if open then "DoorOpen" else "DoorClose", doorLeaves[1].part)
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
		state = ElevatorConfig.State(cabin)

		if before == 0 and state.going ~= 0 then
			riding = aboard()
		elseif state.going == 0 then
			riding = false
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

	if stepLink then
		stepLink:Disconnect()
		stepLink = nil
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

	state = ElevatorConfig.State(cabin)
	lift = ElevatorConfig.Floors[state.floor].Lift
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
