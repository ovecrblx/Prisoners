-- Monitor da sala de segurança: cada slot da tela mostra o que uma câmera enquadra. ViewportFrame
-- não desenha o mundo, só o que está dentro dele — então o feed é uma cópia da cena em volta da
-- câmera mais bonecos vivos dos jogadores. Tudo local, e só montado para quem ocupa o posto.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DoorConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DoorConfig"))
-- Só pelo contrato da lâmpada: o nome do atributo mora no módulo que o publica.
local SecCamController = require(script.Parent:WaitForChild("SecCamController"))

local SecMonitorController = {}

-- Caminho a partir do workspace, e os nomes que amarram slot, câmera e peça que gira.
local FOLDER = { "Siland_Home", "interactive" }
local MONITOR_NAME = "Sec_Monitor"
local SLOT_PATH = { "Screen", "Surface", "Frame_Cam" }
local SLOT_PREFIX = "Cam_"
local CAM_PREFIX = "Sec_Cam_"
local HEAD_NAME = "Head"
local HEAD_MESH = "rbxassetid://86032184172019"
local LED_NAME = "Led"
local REC_NAME = "REC"

-- Painel aceso na cor autorada e apagado no pulso: quanto do caminho até o preto o apagado desce.
local LAMP_DIM = 0.82
local BLACK = Color3.new(0, 0, 0)
local LAMP_ATTRIBUTE = SecCamController.LampAttribute

-- Chiado analógico do Vfx: o TileSize em Y salta até esta fração da base, no intervalo sorteado.
local VFX_NAME = "Vfx"
local VFX_SWING = 0.3
local VFX_MIN, VFX_MAX = 0.05, 0.18

-- Onde o operador senta, de onde ele olha, e o gatilho que o leva até lá. Só quem está NESTE
-- assento vê os feeds.
local SEATS_PATH = { "Siland_Home", "Seats" }
local SEAT_NAME = "Sec_Seat"
local VIEWER_NAME = "Viewer_Cam"
local PROMPT_NAME = "Sec_Prompt"

-- s de caminhada até desistir de sentar; o corpo pode ficar preso no caminho.
local WALK_TIMEOUT = 12

-- Cena copiada por feed: raio em volta da câmera e teto de peças. O teto é o que segura o custo.
local SCENE_RADIUS = 32
local SCENE_CAP = 120

-- Teto da consulta espacial, antes da ordenação por distância: limita o custo da busca em si.
local SCENE_QUERY_CAP = 500

-- graus; mesmo cone da lente do SecCamController, senão o feed mente sobre o que ela vê.
local FEED_FOV = 90

-- studs e graus do alcance em que um jogador vira boneco no feed.
local FIGURE_RADIUS = 60
local FIGURE_HALF = math.rad(50)

-- s entre atualizações dos bonecos e entre verificações de presença na mesa.
local FIGURE_INTERVAL = 1 / 15
local CHECK_INTERVAL = 0.5

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

local evaluate = nil

local slots = {}
local seat = nil
local viewer = nil
local prompt = nil
local walking = false

-- A SurfaceGui da tela e a peça dona dela: enquanto se opera, a GUI é adotada no PlayerGui.
local surface = nil
local surfaceHome = nil

-- Painéis cuja câmera ainda não chegou pelo streaming, por índice; adotados quando ela chegar.
local pending = {}
local boundFolder = nil
local live = false
local driver = nil
local sinceFigure = 0
local sinceCheck = 0

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
local function childLike(parent, name)
	local wanted = string.lower(name)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

local function findHead(model)
	local byMesh = nil
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.Name == HEAD_NAME then
				return item
			elseif item:IsA("MeshPart") and item.MeshId == HEAD_MESH then
				byMesh = byMesh or item
			end
		end
	end
	return byMesh
end

-- Dentro do viewport nada disso desenha nem roda; só pesaria na cópia.
local function stripCopy(part)
	for _, item in ipairs(part:GetDescendants()) do
		if not (item:IsA("Decal") or item:IsA("SpecialMesh")) then
			item:Destroy()
		end
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function clearScene(slot)
	if slot.scene then
		slot.scene:Destroy()
		slot.scene = nil
	end
end

-- Distância até a CAIXA da peça, não até o centro dela: a consulta devolve por limites, e medir
-- pelo centro mandaria uma parede grande para o fim da fila e a cortaria antes de um enfeite perto.
local function nearness(part, origin)
	local point = part.CFrame:PointToObjectSpace(origin)
	local half = part.Size / 2
	local inside = Vector3.new(
		math.clamp(point.X, -half.X, half.X),
		math.clamp(point.Y, -half.Y, half.Y),
		math.clamp(point.Z, -half.Z, half.Z)
	)
	return (point - inside).Magnitude
end

-- Cópia estática, feita uma vez por ativação: o feed anda porque a CÂMERA anda, não a cena.
local function buildScene(slot)
	clearScene(slot)

	local scene = Instance.new("Folder")
	scene.Name = "Scene"

	local params = OverlapParams.new()
	params.MaxParts = SCENE_QUERY_CAP
	local origin = slot.head.Position
	local found = Workspace:GetPartBoundsInRadius(origin, SCENE_RADIUS, params)

	-- A consulta não devolve ordenado, e o teto corta o excedente: sem ordenar por distância as
	-- peças descartadas seriam sorteadas, e a cena sairia com buracos no meio.
	local ranked = {}
	for _, part in ipairs(found) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not (model and Players:GetPlayerFromCharacter(model)) then
			table.insert(ranked, { part = part, distance = nearness(part, origin) })
		end
	end
	table.sort(ranked, function(a, b)
		return a.distance < b.distance
	end)

	local kept = math.min(#ranked, SCENE_CAP)
	for index = 1, kept do
		local copy = ranked[index].part:Clone()
		stripCopy(copy)
		copy.Parent = scene
	end

	scene.Parent = slot.viewport
	slot.scene = scene

	-- Cena vazia é o sintoma de sala ainda não transmitida, e sem aviso pareceria feed quebrado.
	if kept == 0 and not slot.warned then
		slot.warned = true
		warn(string.format("[SecMonitor] %s sem cenário carregado; feed fica vazio.", slot.head:GetFullName()))
	end
end

local function clearFigures(slot)
	for player, figure in pairs(slot.figures) do
		figure.model:Destroy()
		slot.figures[player] = nil
	end
end

-- Boneco: cópia enxuta do personagem, com as peças reposicionadas em lote a cada atualização.
local function makeFigure(slot, character)
	local model = Instance.new("Model")
	model.Name = "Figure"

	local parts, sources = {}, {}
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			local copy = item:Clone()
			stripCopy(copy)
			copy.Parent = model
			table.insert(parts, copy)
			table.insert(sources, item)
		end
	end

	model.Parent = slot.viewport
	return { model = model, parts = parts, sources = sources, poses = table.create(#parts) }
end

local function sees(slot, position)
	local offset = position - slot.head.Position
	local distance = offset.Magnitude
	if distance < 1e-3 or distance > FIGURE_RADIUS then
		return false
	end
	return offset.Unit:Dot(slot.head.CFrame.LookVector) >= math.cos(FIGURE_HALF)
end

local function syncFigures(slot)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
		local figure = slot.figures[player]

		if root and sees(slot, root.Position) then
			if not figure or figure.parts[1] == nil or figure.parts[1].Parent == nil then
				if figure then
					figure.model:Destroy()
				end
				figure = makeFigure(slot, character)
				slot.figures[player] = figure
			end

			local poses = figure.poses
			for index, source in ipairs(figure.sources) do
				poses[index] = source.CFrame
			end
			Workspace:BulkMoveTo(figure.parts, poses, Enum.BulkMoveMode.FireCFrameChanged)
		elseif figure then
			figure.model:Destroy()
			slot.figures[player] = nil
		end
	end
end

-- A vista do posto é a pose do próprio Viewer_Cam, e o prompt sai do ar enquanto se está sentado:
-- desabilitar no cliente é local, então some só para quem está operando.
local function takeView()
	if prompt then
		prompt.Enabled = false
	end

	-- SurfaceGui pendurada na peça é desenhada pelo pipeline do mundo, que NÃO desenha
	-- ViewportFrame — medido: cena montada, câmera setada, tela preta. Adotada no PlayerGui com
	-- Adornee na mesma peça ela desenha igual, pelo pipeline do jogador, que desenha. E como só o
	-- operador a recebe, o feed continua privado de graça.
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if surface and surfaceHome and playerGui then
		surface.Adornee = surfaceHome
		surface.Parent = playerGui
	end

	local camera = Workspace.CurrentCamera
	if camera and viewer then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = viewer.CFrame
	end
end

local function releaseView()
	if prompt then
		prompt.Enabled = true
	end

	-- De volta à peça; pcall porque o streaming pode ter destruído a dona nesse meio-tempo.
	if surface then
		pcall(function()
			surface.Parent = surfaceHome
			surface.Adornee = nil
		end)
	end

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

local function activate()
	if live then
		return
	end
	live = true
	takeView()
	for _, slot in ipairs(slots) do
		buildScene(slot)
	end

	-- Diagnóstico do posto: sem isto, feed vazio e feed que nem ligou são o mesmo preto na tela.
	local total = 0
	for _, slot in ipairs(slots) do
		total += #slot.scene:GetChildren()
	end
	print(string.format("[SecMonitor] posto ligado: %d feeds, %d peças copiadas", #slots, total))
end

local function deactivate()
	if not live then
		return
	end
	live = false
	releaseView()
	for _, slot in ipairs(slots) do
		clearScene(slot)
		clearFigures(slot)
		-- Tudo volta à base autorada: a tela decorativa não fica congelada num salto do chiado nem
		-- com a lâmpada apagada no meio de uma piscada.
		if slot.vfx and slot.vfxBase then
			slot.vfx.TileSize = slot.vfxBase
		end
		if slot.led and slot.ledBase then
			slot.led.ImageColor3 = slot.ledBase
		end
		if slot.rec and slot.recBase then
			slot.rec.TextColor3 = slot.recBase
		end
		slot.lampColor = nil
	end
end

local unbind = nil

-- O feed é montado NO CLIENTE, então ele já nasce privado: quem não está no posto não tem o que ver
-- porque nada foi criado no viewport dele.
-- O assento vive em OUTRA pasta, e com streaming ele pode chegar depois: resolver aqui, enquanto
-- estiver faltando, é o que impede o posto de nunca ligar por causa da ordem de carregamento.
local function resolveSeat()
	if seat and seat.Parent then
		return seat
	end
	local seats = Workspace
	for _, name in ipairs(SEATS_PATH) do
		seats = seats and childLike(seats, name)
	end
	local model = seats and childLike(seats, SEAT_NAME)
	seat = model and model:FindFirstChildWhichIsA("Seat", true)
	return seat
end

local function operating()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return resolveSeat() ~= nil and humanoid ~= nil and humanoid.SeatPart == seat
end

-- O posto é o ASSENTO, não o prompt: sentar por conta própria vale exatamente o mesmo gesto.
evaluate = function()
	if #slots == 0 then
		return
	end
	if operating() then
		activate()
	else
		deactivate()
	end
end

-- O assento senta por toque, como qualquer Seat: basta levar o corpo até ele.
local function takePost()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (resolveSeat() and humanoid) or humanoid.SeatPart == seat or walking then
		return
	end

	walking = true
	humanoid:MoveTo(seat.Position)
	task.delay(WALK_TIMEOUT, function()
		walking = false
	end)
end

local function step(delta)
	sinceCheck += delta
	if sinceCheck >= CHECK_INTERVAL then
		sinceCheck = 0

		-- Streaming pode levar o monitor no meio da partida; as peças guardadas ficam órfãs.
		if surfaceHome == nil or surfaceHome.Parent == nil then
			unbind()
			return
		end

		-- Câmera que o streaming levou volta à fila; a que voltar é readotada pelo attach.
		for i = #slots, 1, -1 do
			local slot = slots[i]
			if slot.head.Parent == nil then
				clearScene(slot)
				clearFigures(slot)
				pending[slot.index] = slot.panel
				table.remove(slots, i)
			end
		end

		evaluate()
	end

	if not live then
		return
	end

	-- A cena é estática; quem se move é a câmera do feed, colada na cabeça que gira. O chiado salta
	-- o TileSize do Vfx dentro da faixa, cada tela no próprio ritmo — em sincronia leria como UMA
	-- interferência, não como quatro monitores velhos.
	local now = os.clock()
	for _, slot in ipairs(slots) do
		slot.camera.CFrame = slot.head.CFrame

		-- Led e REC seguem o ritmo da lâmpada da câmera, INVERTIDO: ficam acesos na cor autorada e
		-- apagam no instante em que ela acende. Por QUADRO e só na mudança — a piscada dura 0,12s, e
		-- amostrar a cada meio segundo dava um ritmo que a câmera não tem.
		local shown = 1 - (slot.ledPart and slot.ledPart:GetAttribute(LAMP_ATTRIBUTE) or 0)
		if shown ~= slot.lampLevel then
			slot.lampLevel = shown
			if slot.led then
				slot.led.ImageColor3 = slot.ledDark:Lerp(slot.ledBase, shown)
			end
			if slot.rec then
				slot.rec.TextColor3 = slot.recDark:Lerp(slot.recBase, shown)
			end
		end

		if slot.vfx and now >= slot.vfxAt then
			slot.vfxAt = now + VFX_MIN + math.random() * (VFX_MAX - VFX_MIN)
			local swing = 1 + (math.random() * 2 - 1) * VFX_SWING
			local base = slot.vfxBase
			slot.vfx.TileSize = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale * swing, base.Y.Offset * swing)
		end
	end

	sinceFigure += delta
	if sinceFigure >= FIGURE_INTERVAL then
		sinceFigure = 0
		for _, slot in ipairs(slots) do
			syncFigures(slot)
		end
	end
end

unbind = function()
	deactivate()
	if driver then
		driver:Disconnect()
		driver = nil
	end
	table.clear(slots)
	table.clear(pending)
	surface = nil
	surfaceHome = nil
	viewer = nil
	prompt = nil
	boundFolder = nil
end

-- Mesmo estilo dos outros recursos do jogo: Custom, sem texto, desenhado pelo PromptDisplay. Os
-- números saem do DoorConfig porque são os do projeto — uma segunda cópia deles é como divergem.
local function ensurePrompt(screen)
	local existing = screen:FindFirstChild(PROMPT_NAME)
	if existing then
		return existing
	end

	local created = Instance.new("ProximityPrompt")
	created.Name = PROMPT_NAME
	created.Style = Enum.ProximityPromptStyle.Custom
	created.ActionText = ""
	created.ObjectText = ""
	created.UIOffset = DoorConfig.PromptOffset
	created.ClickablePrompt = DoorConfig.PromptClickable
	created.HoldDuration = 0
	created.MaxActivationDistance = DoorConfig.PromptDistance
	created.RequiresLineOfSight = false
	created.Parent = screen
	return created
end

-- Liga um painel à sua câmera. A GUI replica inteira, mas a câmera vem pelo streaming e pode
-- chegar DEPOIS: o painel sem par espera em `pending` em vez de ser perdido no boot — era assim
-- que o posto ligava com 3 feeds e o quarto ficava preto para sempre.
local function attach(index, panel)
	local model = boundFolder and childLike(boundFolder, CAM_PREFIX .. index)
	local viewport = panel:FindFirstChildOfClass("ViewportFrame")
	local head = model and findHead(model)
	if not (viewport and head) then
		pending[index] = panel
		return
	end
	pending[index] = nil

	local camera = viewport:FindFirstChildOfClass("Camera") or Instance.new("Camera")
	camera.FieldOfView = FEED_FOV
	camera.CFrame = head.CFrame
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local value = panel:FindFirstChild("Value")
	if value and value:IsA("TextButton") then
		value.Text = "CAM " .. index
	end

	local vfx = panel:FindFirstChild(VFX_NAME)
	local led = panel:FindFirstChild(LED_NAME)
	local rec = panel:FindFirstChild(REC_NAME)
	local slot = {
		index = index,
		panel = panel,
		viewport = viewport,
		camera = camera,
		head = head,
		led = led,
		rec = rec,
		ledBase = led and led.ImageColor3,
		recBase = rec and rec.TextColor3,
		ledDark = led and led.ImageColor3:Lerp(BLACK, LAMP_DIM),
		recDark = rec and rec.TextColor3:Lerp(BLACK, LAMP_DIM),
		ledPart = model:FindFirstChild(LED_NAME, true),
		vfx = vfx,
		vfxBase = vfx and vfx.TileSize,
		vfxAt = 0,
		figures = {},
	}
	table.insert(slots, slot)

	-- Chegou com o posto já ocupado: entra com a cena montada, não preta até o próximo sentar.
	if live then
		buildScene(slot)
	end
end

local function bind(folder, monitor)
	local frame = monitor
	for _, name in ipairs(SLOT_PATH) do
		frame = frame and childLike(frame, name)
	end
	if not frame then
		return false
	end
	boundFolder = folder
	surfaceHome = childLike(monitor, SLOT_PATH[1])
	surface = childLike(surfaceHome, SLOT_PATH[2])
	viewer = childLike(monitor, VIEWER_NAME)
	prompt = ensurePrompt(surfaceHome)

	local index = 0
	while true do
		index += 1
		local panel = childLike(frame, SLOT_PREFIX .. index)
		if not panel then
			break
		end
		attach(index, panel)
	end

	if #slots == 0 and next(pending) == nil then
		return false
	end
	driver = RunService.PostSimulation:Connect(step)
	return true
end

function SecMonitorController.Start()
	local folder = Workspace
	for _, name in ipairs(FOLDER) do
		folder = childLike(folder, name) or folder:WaitForChild(name, FOLDER_WAIT)
		if not folder then
			warn("[SecMonitor] workspace." .. table.concat(FOLDER, ".") .. " não encontrado.")
			return
		end
	end

	-- Com streaming o monitor e as câmeras chegam depois do boot, e podem ir e voltar: a ligação é
	-- refeita enquanto não estiver de pé, em vez de uma tentativa só na entrada.
	local function attempt()
		-- Ligado: só adota os painéis que ainda esperam câmera. Desligado: tenta a ligação inteira.
		if driver then
			for index, panel in pairs(pending) do
				attach(index, panel)
			end
			return
		end
		local monitor = childLike(folder, MONITOR_NAME)
		if monitor then
			bind(folder, monitor)
		end
	end

	attempt()
	folder.DescendantAdded:Connect(function(item)
		if item:IsA("BasePart") or item:IsA("Model") or item:IsA("ViewportFrame") then
			attempt()
		end
	end)

	-- Sentar sozinho no posto vale o mesmo gesto do prompt, e o sinal responde na hora em vez de
	-- esperar a próxima verificação.
	local function watchSeat(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid then
			humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
				if evaluate then
					evaluate()
				end
			end)
		end
	end

	if Players.LocalPlayer.Character then
		task.spawn(watchSeat, Players.LocalPlayer.Character)
	end
	Players.LocalPlayer.CharacterAdded:Connect(function(character)
		task.spawn(watchSeat, character)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(fired, player)
		if player == Players.LocalPlayer and fired.Name == PROMPT_NAME then
			attempt()
			takePost()
		end
	end)
end

return SecMonitorController
