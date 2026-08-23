-- Monitor da sala de segurança: cada slot da tela mostra o que uma câmera enquadra. ViewportFrame
-- não desenha o mundo, só o que está dentro dele — então o feed é uma cópia do cenário inteiro,
-- com porta espelhada quando se move, mais os corpos vivos, jogadores e NPCs, redesenhados por
-- quadro. Tudo local, e só montado para quem ocupa o posto.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))
-- Só pelo nome da pasta dos corpos: quem a cria é o serviço de NPC, e uma segunda cópia do nome aqui
-- é como os dois lados divergem em silêncio.
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
-- Só pelo contrato da lâmpada: o nome do atributo mora no módulo que o publica.
local SecCamController = require(script.Parent:WaitForChild("SecCamController"))

local SecMonitorController = {}

-- Caminho a partir do workspace, e os nomes que amarram slot, câmera e peça que gira. O Sec_Monitor
-- do workspace é decoração e âncora do prompt; o monitor que o operador USA é a cabine.
local FOLDER = { "Siland_Home", "interactive" }
local MONITOR_NAME = "Sec_Monitor"

-- Caminho da cabine a partir de ReplicatedStorage: clone local montado no boot e vivo o resto da
-- partida. Ela já é autorada longe do mapa, então o clone nasce isolado sem reposicionar nada.
local VIEWER_MODEL = { "Client", "Models", "Viewer_Model" }
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

-- Chiado do fundo da tela: s entre saltos do grão, e quanto a folha passa da tela para ter folga
-- onde deslizar. O nome também é o da capa inerte de cada painel.
local BACKGROUND_NAME = "Background"
local SNOW_MIN, SNOW_MAX = 0.05, 0.12
local SNOW_OVERSCAN = 1.3

-- Falha de sinal, uma tela por vez: s de espera até ela cair, o intervalo curto do chiado enquanto
-- está caída, e os s longe do posto que a consertam. A espera vai de segundos a minutos.
local GLITCH_WAIT_MIN, GLITCH_WAIT_MAX = 8, 210
local GLITCH_MIN, GLITCH_MAX = 0.02, 0.05
local GLITCH_COLOR = Color3.new(1, 1, 1)
local GLITCH_FADE = 0.7
local GLITCH_BACKING = 0
local GLITCH_COOLDOWN = 30

-- Painel de controle: a lâmpada que pisca junto das câmeras e o botão que desliga o posto.
local CONTROL_NAME = "Control"
local POWER_NAME = "Power"

-- studs que a tecla afunda, s do curso de ida e volta, e s entre o clique e sair do monitor.
local PRESS_DEPTH = 0.015
local PRESS_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local POWER_DELAY = 0.5

-- Painel transparente por cima da tecla: é ele que recebe o hover e o clique.
local HOVER_NAME = "PowerHover"

-- Feed em solo: os botões que entram e saem dele, e a célula que faz um painel ocupar a grade toda.
local VIEW_NAME = "View"
local BACK_NAME = "Back"
local NO_SIGNAL = "No Signal"
local SOLO_CELL = UDim2.fromScale(1, 1)

-- Corte preto que cobre a troca de vista: s parado no preto, curso do desvanecer, e a ordem que o
-- põe acima de tudo, cursor incluso.
local FADE_NAME = "SecFade"
local FADE_TWEEN = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.15)
local FADE_ORDER = 200

-- Ponteiro do hover: a imagem, o lado dela em px, e a ordem que a põe acima da GUI do jogo.
local CURSOR_NAME = "SecCursor"
local CURSOR_IMAGE = "rbxassetid://284663799"
local CURSOR_SIZE = 32
local CURSOR_ORDER = 100

-- Onde o operador senta, de onde ele olha, e o gatilho que o leva até lá. Só quem está NESTE
-- assento vê os feeds.
local SEATS_PATH = { "Siland_Home", "Seats" }
local SEAT_NAME = "Sec_Seat"
local VIEWER_NAME = "Viewer_Cam"
local PROMPT_NAME = "Sec_Prompt"

-- s de caminhada até desistir de sentar; o corpo pode ficar preso no caminho.
local WALK_TIMEOUT = 12

-- s de espera pelo streaming em volta de cada câmera, e s entre passadas que espelham no feed a
-- peça de cenário que se moveu (porta, elevador).
local SCENE_STREAM_WAIT = 5
local SCENE_SYNC_INTERVAL = 0.1

-- Peças clonadas por quadro ao montar um feed: o mapa inteiro de uma vez trava o quadro e atrasa a
-- iluminação, que só reassenta quando o trabalho do quadro acaba.
local SCENE_BUDGET = 250

-- graus; mesmo cone da lente do SecCamController, senão o feed mente sobre o que ela vê.
local FEED_FOV = 90

-- graus do cone em que um corpo vivo vira boneco no feed; atrás da lente ninguém aparece.
local FIGURE_HALF = math.rad(50)

-- s entre atualizações dos bonecos e entre verificações de presença na mesa.
local FIGURE_INTERVAL = 1 / 15
local CHECK_INTERVAL = 0.5

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

local evaluate = nil
local bindControl = nil
local attach = nil

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
local sceneRoot = nil
local live = false
local driver = nil
local sinceFigure = 0
local sinceCheck = 0
local sinceScene = 0

-- O cenário compartilhado pelos feeds: as peças de origem, a última pose espelhada de cada uma, e
-- as ligações que acompanham o streaming enquanto o posto está ligado.
local sceneSources = {}
local scenePoses = {}
local sceneLinks = {}

-- A grade dos feeds, a célula autorada dela, e qual painel está em solo agora.
local grid = nil
local gridCell = nil
local solo = nil

-- A folha de chiado atrás da grade: a folga que ela tem para deslizar, e quando o grão salta.
local snow = nil
local snowSlack = Vector2.zero
local snowAt = 0

-- A cabine clonada do operador, e a lâmpada da mesa decorativa, que pisca para quem passa.
local booth = nil
local deskLamp = nil
local deskLed = nil

-- A tecla de desligar, a pose dela em repouso, o clique preso e o passo da lâmpada da cabine.
local boundMonitor = nil
local powerPart = nil
local powerHome = nil
local controlLinks = {}
local hoverPad = nil
local pressing = false
local lamp = nil

-- O corte preto da troca de vista, e o ponteiro do hover: a tela dele, a imagem, a ligação que a faz
-- seguir o mouse e quantos alvos estão sob ele.
local fadeGui = nil
local fadeSheet = nil
local cursorGui = nil
local cursorPointer = nil
local cursorMove = nil
local hovering = 0

-- O índice da tela caída, quando a próxima cai, e desde quando o posto está vazio.
local broken = nil
local glitchAt = 0
local leftAt = 0

-- O ponteiro do hover é DESENHADO por nós: a referência do MouseIcon diz que o ícone é ignorado
-- enquanto o cursor está sobre botão de GUI, e os cursores de sistema só valem em plugin. Um
-- ScreenGui seguindo o mouse não depende de nenhum dos dois.
local function buildCursor()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if cursorGui or not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = CURSOR_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = CURSOR_ORDER
	gui.Enabled = false

	local image = Instance.new("ImageLabel")
	image.Name = "Pointer"
	image.BackgroundTransparency = 1
	-- Sem âncora no centro: o ponto de contato do ponteiro é o canto superior esquerdo do desenho, e
	-- centrar deixaria o clique caindo abaixo da ponta.
	image.AnchorPoint = Vector2.zero
	image.Size = UDim2.fromOffset(CURSOR_SIZE, CURSOR_SIZE)
	image.Image = CURSOR_IMAGE
	image.Parent = gui

	gui.Parent = playerGui
	cursorGui = gui
	cursorPointer = image
end

local function hideCursor()
	hovering = 0
	if cursorMove then
		cursorMove:Disconnect()
		cursorMove = nil
	end
	if cursorGui then
		cursorGui.Enabled = false
	end
	UserInputService.MouseIconEnabled = true
end

local function showCursor()
	buildCursor()
	if not cursorGui then
		return
	end

	local mouse = Players.LocalPlayer:GetMouse()
	local function follow()
		cursorPointer.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	end

	follow()
	cursorGui.Enabled = true
	UserInputService.MouseIconEnabled = false

	cursorMove = mouse.Move:Connect(follow)
end

-- Contar quantos alvos estão sob o ponteiro, em vez de esconder no primeiro MouseLeave: passando
-- direto de um botão para o vizinho, a saída de um chega depois da entrada do outro e apagaria o
-- cursor com o mouse ainda em cima.
local function watchHover(button)
	table.insert(controlLinks, button.MouseEnter:Connect(function()
		hovering += 1
		showCursor()
	end))
	table.insert(controlLinks, button.MouseLeave:Connect(function()
		hovering = math.max(0, hovering - 1)
		if hovering == 0 then
			hideCursor()
		end
	end))
end

local function dropControlLinks()
	for _, link in ipairs(controlLinks) do
		link:Disconnect()
	end
	table.clear(controlLinks)
	hideCursor()
	lamp = nil
	powerPart = nil
	powerHome = nil

	if hoverPad then
		hoverPad:Destroy()
		hoverPad = nil
	end
	if cursorGui then
		cursorGui:Destroy()
		cursorGui = nil
		cursorPointer = nil
	end
	if fadeGui then
		fadeGui:Destroy()
		fadeGui = nil
		fadeSheet = nil
	end
end

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
	slot.copies = {}
end

-- A câmera não entra no próprio vídeo: a cópia da cabeça sentaria em cima da lente e taparia o feed.
local function isCamPart(item)
	local model = item:FindFirstAncestorOfClass("Model")
	while model do
		if string.find(string.lower(model.Name), "^sec_cam") then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

local function wantedInScene(item)
	return item:IsA("BasePart") and item.Transparency < 1 and not isCamPart(item)
end

-- O mapa INTEIRO entra, varrendo a hierarquia do cenário: consulta espacial não devolve peça com
-- CanQuery desligado (medido: 148 das 1546 assim), e raio ou teto cortavam o resto em silêncio.
local function collectSources()
	table.clear(sceneSources)
	table.clear(scenePoses)
	for _, item in ipairs(sceneRoot and sceneRoot:GetDescendants() or {}) do
		if wantedInScene(item) then
			table.insert(sceneSources, item)
			scenePoses[#sceneSources] = item.CFrame
		end
	end
end

-- Montada em fatias, com orçamento por quadro: o mapa inteiro de uma vez congela o quadro e segura a
-- iluminação. O feed enche em ondas, e a pasta já entra no viewport para aparecer enquanto enche.
local function buildScene(slot)
	clearScene(slot)

	local scene = Instance.new("Folder")
	scene.Name = "Scene"
	scene.Parent = slot.viewport
	slot.scene = scene

	task.spawn(function()
		local spent = 0
		for index, source in ipairs(sceneSources) do
			if slot.scene ~= scene then
				return
			end
			if source.Parent then
				local copy = source:Clone()
				stripCopy(copy)
				copy.Parent = scene
				slot.copies[index] = copy
			end

			spent += 1
			if spent >= SCENE_BUDGET then
				spent = 0
				RunService.PostSimulation:Wait()
			end
		end
	end)

	-- Cena vazia é o sintoma de sala ainda não transmitida, e sem aviso pareceria feed quebrado.
	if #sceneSources == 0 and not slot.warned then
		slot.warned = true
		warn(string.format("[SecMonitor] %s sem cenário carregado; feed fica vazio.", slot.head:GetFullName()))
	end
end

-- Peça de cenário que se moveu (porta, elevador) move a cópia em todos os feeds, em lote e só as
-- que mudaram: comparar CFrame é barato, e reescrever o mapa inteiro por quadro não é.
local function syncScenery()
	local moved = {}
	for index, source in ipairs(sceneSources) do
		if source.Parent and source.CFrame ~= scenePoses[index] then
			scenePoses[index] = source.CFrame
			table.insert(moved, index)
		end
	end
	if #moved == 0 then
		return
	end

	for _, slot in ipairs(slots) do
		local parts, poses = {}, {}
		for _, index in ipairs(moved) do
			local copy = slot.copies[index]
			if copy then
				table.insert(parts, copy)
				table.insert(poses, scenePoses[index])
			end
		end
		if #parts > 0 then
			Workspace:BulkMoveTo(parts, poses, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

-- Streaming durante a sessão: peça que chega entra em todos os feeds na hora, peça que sai leva a
-- cópia junto — sem isto o mapa do vídeo seria só o que existia no instante de sentar.
local function watchScenery()
	if not sceneRoot then
		return
	end

	table.insert(
		sceneLinks,
		sceneRoot.DescendantAdded:Connect(function(item)
			if not wantedInScene(item) then
				return
			end
			table.insert(sceneSources, item)
			local index = #sceneSources
			scenePoses[index] = item.CFrame
			for _, slot in ipairs(slots) do
				if slot.scene then
					local copy = item:Clone()
					stripCopy(copy)
					copy.Parent = slot.scene
					slot.copies[index] = copy
				end
			end
		end)
	)

	table.insert(
		sceneLinks,
		sceneRoot.DescendantRemoving:Connect(function(item)
			-- A origem fica na lista com Parent nil, e a passada de poses a ignora por isso; se a
			-- mesma peça voltar pelo streaming, o DescendantAdded a registra como entrada nova.
			for index, source in ipairs(sceneSources) do
				if source == item then
					for _, slot in ipairs(slots) do
						local copy = slot.copies[index]
						if copy then
							copy:Destroy()
							slot.copies[index] = nil
						end
					end
					break
				end
			end
		end)
	)
end

local function unwatchScenery()
	for _, link in ipairs(sceneLinks) do
		link:Disconnect()
	end
	table.clear(sceneLinks)
	table.clear(sceneSources)
	table.clear(scenePoses)
end

local function clearFigures(slot)
	for body, figure in pairs(slot.figures) do
		figure.model:Destroy()
		slot.figures[body] = nil
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
	if distance < 1e-3 then
		return false
	end
	return offset.Unit:Dot(slot.head.CFrame.LookVector) >= math.cos(FIGURE_HALF)
end

-- Corpo vivo é jogador e NPC: os dois andam, e a câmera que só mostrasse jogador entregaria uma sala
-- parada com gente passando fora do vídeo.
local function livingBodies()
	local bodies = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(bodies, player.Character)
		end
	end

	local folder = Workspace:FindFirstChild(NpcConfig.BODY_FOLDER)
	for _, model in ipairs(folder and folder:GetChildren() or {}) do
		if model:IsA("Model") then
			table.insert(bodies, model)
		end
	end
	return bodies
end

local function syncFigures(slot)
	local shown = {}
	for _, body in ipairs(livingBodies()) do
		local root = body.PrimaryPart or body:FindFirstChild("HumanoidRootPart")
		if root and sees(slot, root.Position) then
			shown[body] = true
			local figure = slot.figures[body]
			if not figure or figure.parts[1] == nil or figure.parts[1].Parent == nil then
				if figure then
					figure.model:Destroy()
				end
				figure = makeFigure(slot, body)
				slot.figures[body] = figure
			end

			local poses = figure.poses
			for index, source in ipairs(figure.sources) do
				poses[index] = source.CFrame
			end
			Workspace:BulkMoveTo(figure.parts, poses, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	-- Quem saiu do enquadramento, morreu ou desconectou some do feed; sem esta varredura o boneco
	-- ficaria congelado na última pose que teve.
	for body, figure in pairs(slot.figures) do
		if not shown[body] then
			figure.model:Destroy()
			slot.figures[body] = nil
		end
	end
end

-- A vista do posto é a pose do próprio Viewer_Cam, e o prompt sai do ar enquanto se está sentado:
-- desabilitar no cliente é local, então some só para quem está operando.
-- Câmera que teleporta cai numa região com o mapa de luz por preencher, e as luzes de lá acendem
-- alguns quadros depois — é a técnica Voxel, não o place. O corte preto cobre a janela: some junto
-- com o preenchimento, e a troca lê como corte de vídeo em vez de sala acendendo sozinha.
local function coverSwap()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	if not fadeGui then
		local gui = Instance.new("ScreenGui")
		gui.Name = FADE_NAME
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = FADE_ORDER

		local sheet = Instance.new("Frame")
		sheet.Name = "Sheet"
		sheet.Size = UDim2.fromScale(1, 1)
		sheet.BackgroundColor3 = BLACK
		sheet.BorderSizePixel = 0
		sheet.Parent = gui

		gui.Parent = playerGui
		fadeGui = gui
		fadeSheet = sheet
	end

	fadeSheet.BackgroundTransparency = 0
	fadeGui.Enabled = true
	TweenService:Create(fadeSheet, FADE_TWEEN, { BackgroundTransparency = 1 }):Play()
end

local function takeView()
	coverSwap()
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
	coverSwap()
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

-- Tela caída: o fundo do viewport fecha, o chiado vira branco e curto, e a cena sai de dentro dele —
-- sem nada para desenhar sobra só o BackgroundColor3, que é como um feed morto se lê.
local function scheduleGlitch(now)
	glitchAt = now + GLITCH_WAIT_MIN + math.random() * (GLITCH_WAIT_MAX - GLITCH_WAIT_MIN)
end

local function brokenLook(slot, on)
	slot.viewport.BackgroundTransparency = if on then GLITCH_BACKING else slot.backingBase
	if slot.vfx then
		slot.vfx.ImageColor3 = if on then GLITCH_COLOR else slot.vfxColor
		slot.vfx.ImageTransparency = if on then GLITCH_FADE else slot.vfxFade
	end

	-- O rótulo do botão diz o estado da tela: a falha se anuncia onde o operador ia clicar para
	-- abrir o feed.
	if slot.view then
		slot.view.Text = if on then NO_SIGNAL else slot.viewText
	end
end

local function breakSlot(slot)
	broken = slot.index
	brokenLook(slot, true)
	clearScene(slot)
	clearFigures(slot)
end

-- A cabine nasce ao sentar: clone local do Viewer_Model, com o monitor REAL dentro — tela, tecla e
-- Viewer_Cam. Só o operador a tem, então a privacidade dos feeds continua de graça.
-- Um feed sozinho na tela: os outros painéis saem, e a célula da grade cresce para a tela inteira.
-- `Back` só existe no solo, e é ele quem devolve a célula autorada e traz os quatro de volta.
local function setSolo(index)
	solo = index
	if grid then
		grid.CellSize = if index then SOLO_CELL else gridCell
	end

	for _, slot in ipairs(slots) do
		local alone = index ~= nil and slot.index == index
		slot.panel.Visible = index == nil or alone

		-- No solo os dois trocam de lugar: quem abriu a tela sai, e só resta o caminho de volta.
		if slot.view then
			slot.view.Visible = not alone
		end
		if slot.back then
			slot.back.Visible = alone
		end
	end
end

-- A cabine nasce no BOOT, não ao sentar: a luz dela é um PointLight, e iluminação recém-criada leva
-- segundos para assentar. Montada cedo, já está acesa quando alguém ocupa o posto. É clone local,
-- então continua invisível para os outros jogadores.
local function buildBooth()
	if booth and booth.Parent then
		return true
	end

	local source = ReplicatedStorage
	for _, name in ipairs(VIEWER_MODEL) do
		source = source and source:FindFirstChild(name)
	end
	if not source then
		warn("[SecMonitor] ReplicatedStorage." .. table.concat(VIEWER_MODEL, ".") .. " não encontrado.")
		return false
	end

	booth = source:Clone()
	booth.Parent = Workspace

	local monitor = childLike(booth, MONITOR_NAME)
	local frame = monitor
	for _, name in ipairs(SLOT_PATH) do
		frame = frame and childLike(frame, name)
	end
	if not (monitor and frame) then
		warn("[SecMonitor] cabine sem " .. MONITOR_NAME .. "." .. table.concat(SLOT_PATH, "."))
		booth:Destroy()
		booth = nil
		return false
	end

	surfaceHome = childLike(monitor, SLOT_PATH[1])
	surface = childLike(surfaceHome, SLOT_PATH[2])
	viewer = childLike(monitor, VIEWER_NAME)

	-- Ladrilhada e maior que a tela: o grão guarda o tamanho e é a folha que desliza dentro da folga.
	-- Embaralhar o chiado esticando o ladrilho fazia o grão respirar, que lê como zoom, não como ruído.
	local sheet = surface and surface:FindFirstChild(BACKGROUND_NAME)
	snow = if sheet and sheet:IsA("ImageLabel") then sheet else nil
	if snow then
		local size = snow.Size
		snow.ScaleType = Enum.ScaleType.Tile
		snow.AnchorPoint = Vector2.new(0.5, 0.5)
		snow.Size = UDim2.fromScale(size.X.Scale * SNOW_OVERSCAN, size.Y.Scale * SNOW_OVERSCAN)
		snowSlack = Vector2.new(size.X.Scale, size.Y.Scale) * ((SNOW_OVERSCAN - 1) * 0.5)
	end

	grid = frame:FindFirstChildOfClass("UIGridLayout")
	gridCell = grid and grid.CellSize
	bindControl(monitor)

	-- Clique em GUI de mundo sai de um raio do mouse contra a peça adornada, e a tela é publicada com
	-- CanQuery desligado — o raio atravessa e nenhum botão recebe nada. AlwaysOnTop resolveria o
	-- input, mas custa o LightInfluence da tela. Então só a tela e a tecla entram na consulta, e o
	-- resto da cabine sai dela: assim o raio chega sem esbarrar no gabinete. Escrita local, no clone.
	for _, item in ipairs(booth:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CanQuery = item == surfaceHome or item == powerPart
		end
	end

	local index = 0
	while true do
		index += 1
		local panel = childLike(frame, SLOT_PREFIX .. index)
		if not panel then
			break
		end
		attach(index, panel)
	end

	setSolo(nil)
	return true
end

local function activate()
	if live or not buildBooth() then
		return
	end
	live = true
	SecCamController.KeepAwake(true)
	takeView()

	-- A tela só conserta com o posto vazio o tempo do intervalo: sentar de novo na hora devolve o
	-- operador à mesma falha, senão sair e voltar seria o conserto.
	local now = os.clock()
	if broken and now - leftAt >= GLITCH_COOLDOWN then
		broken = nil
	end
	if broken then
		glitchAt = math.huge
	else
		scheduleGlitch(now)
	end

	collectSources()
	watchScenery()
	for _, slot in ipairs(slots) do
		if slot.index == broken then
			brokenLook(slot, true)
		else
			buildScene(slot)
		end
	end

	-- O place usa streaming: a sala que a câmera enquadra pode nem existir neste cliente, e a cópia
	-- sairia furada sem sintoma. O pedido puxa o entorno de cada câmera, e o que chegar entra nos
	-- feeds pelo DescendantAdded; é temporário e sem garantia, então o posto pede a cada ativação.
	for _, slot in ipairs(slots) do
		task.spawn(function()
			pcall(function()
				Players.LocalPlayer:RequestStreamAroundAsync(slot.head.Position, SCENE_STREAM_WAIT)
			end)
		end)
	end

	-- Diagnóstico do posto: sem isto, feed vazio e feed que nem ligou são o mesmo preto na tela. A
	-- contagem é da FONTE, porque as cópias ainda estão entrando em fatias quando isto imprime.
	print(string.format("[SecMonitor] posto ligado: %d feeds, %d peças de cenário", #slots, #sceneSources))
end

local function deactivate()
	if not live then
		return
	end
	live = false
	SecCamController.KeepAwake(false)
	releaseView()
	leftAt = os.clock()
	unwatchScenery()

	-- A cabine FICA de pé, só esvaziada: derrubá-la a cada sessão devolveria o atraso da luz, que é
	-- justamente o que montá-la no boot evita. Some o cenário dos feeds, some o boneco, e o painel
	-- volta à base autorada.
	for _, slot in ipairs(slots) do
		clearScene(slot)
		clearFigures(slot)
		brokenLook(slot, false)
		if slot.vfx and slot.vfxBase then
			slot.vfx.TileSize = slot.vfxBase
		end
		if slot.led and slot.ledBase then
			slot.led.ImageColor3 = slot.ledBase
		end
		if slot.rec and slot.recBase then
			slot.rec.TextColor3 = slot.recBase
		end
		slot.lampLevel = nil
	end

	-- A grade volta ao arranjo autorado: quem sentar depois começa com os quatro feeds, não no solo
	-- que o operador anterior deixou.
	setSolo(nil)
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
	if not boundMonitor then
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
	local now = os.clock()

	-- A lâmpada do painel pisca com o posto vazio também: é a luz de que o gravador está de pé.
	if lamp then
		lamp(now)
	end

	if deskLamp then
		deskLamp(now)
	end

	sinceCheck += delta
	if sinceCheck >= CHECK_INTERVAL then
		sinceCheck = 0

		-- Streaming pode levar a mesa decorativa no meio da partida; as peças guardadas ficam órfãs.
		-- A cabine é clone local, o streaming nunca a leva.
		if boundMonitor == nil or boundMonitor.Parent == nil then
			unbind()
			return
		end

		-- Câmera que o streaming levou volta à fila; a que voltar é readotada pelo attach.
		for i = #slots, 1, -1 do
			local slot = slots[i]
			if slot.head.Parent == nil then
				clearScene(slot)
				clearFigures(slot)
				brokenLook(slot, false)
				pending[slot.index] = slot.panel
				table.remove(slots, i)
			end
		end

		evaluate()
	end

	if not live then
		return
	end

	-- O grão do fundo salta no próprio passo, fora do ritmo do Vfx dos painéis: junto deles o fundo
	-- leria como um quinto feed, não como ruído do tubo.
	if snow and now >= snowAt then
		snowAt = now + SNOW_MIN + math.random() * (SNOW_MAX - SNOW_MIN)
		local x = 0.5 + (math.random() * 2 - 1) * snowSlack.X
		local y = 0.5 + (math.random() * 2 - 1) * snowSlack.Y
		snow.Position = UDim2.fromScale(x, y)
	end

	sinceScene += delta
	if sinceScene >= SCENE_SYNC_INTERVAL then
		sinceScene = 0
		syncScenery()
	end

	-- O chiado salta o TileSize do Vfx dentro da faixa, cada tela no próprio ritmo — em sincronia
	-- leria como UMA interferência, não como quatro monitores velhos.
	if not broken and now >= glitchAt and #slots > 0 then
		breakSlot(slots[math.random(#slots)])
	end

	for _, slot in ipairs(slots) do
		if slot.index ~= broken and (solo == nil or slot.index == solo) then
			slot.camera.CFrame = slot.head.CFrame
		end

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
			local low, high = VFX_MIN, VFX_MAX
			if slot.index == broken then
				low, high = GLITCH_MIN, GLITCH_MAX
			end
			slot.vfxAt = now + low + math.random() * (high - low)
			local swing = 1 + (math.random() * 2 - 1) * VFX_SWING
			local base = slot.vfxBase
			slot.vfx.TileSize = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale * swing, base.Y.Offset * swing)
		end
	end

	sinceFigure += delta
	-- Painel fora da tela não gasta boneco: no solo, três dos quatro feeds estão escondidos.
	if sinceFigure >= FIGURE_INTERVAL then
		sinceFigure = 0
		for _, slot in ipairs(slots) do
			if slot.index ~= broken and (solo == nil or slot.index == solo) then
				syncFigures(slot)
			end
		end
	end
end

unbind = function()
	deactivate()
	if driver then
		driver:Disconnect()
		driver = nil
	end
	dropControlLinks()
	table.clear(slots)
	table.clear(pending)
	surface = nil
	surfaceHome = nil
	snow = nil
	viewer = nil
	if booth then
		booth:Destroy()
		booth = nil
	end
	prompt = nil
	deskLamp = nil
	deskLed = nil
	boundFolder = nil
	sceneRoot = nil
	boundMonitor = nil
end

-- A tecla afunda e volta sozinha (o tween reverte), e o posto só é largado depois da espera: sair no
-- mesmo quadro do clique engoliria o movimento da tecla.
local function pressPower()
	if pressing or not live or not powerPart then
		return
	end
	pressing = true
	TweenService:Create(powerPart, PRESS_TWEEN, { CFrame = powerHome * CFrame.new(0, 0, PRESS_DEPTH) }):Play()

	task.delay(POWER_DELAY, function()
		pressing = false
		hideCursor()
		if powerPart and powerHome then
			powerPart.CFrame = powerHome
		end
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Sit = false
		end
	end)
end

-- Lâmpada e tecla do painel de controle. Quem recebe o clique é o TextButton autorado na SurfaceGui
-- da tecla.
bindControl = function(monitor)
	dropControlLinks()

	local control = childLike(monitor, CONTROL_NAME)
	if not control then
		return
	end

	local led = childLike(control, LED_NAME)
	if led and led:IsA("BasePart") then
		lamp = SecCamController.Lamp(led, os.clock())
	end

	powerPart = childLike(control, POWER_NAME)
	powerHome = powerPart and powerPart.CFrame
	if not powerPart then
		return
	end

	-- Quem aciona é o TextButton da SurfaceGui da tecla, e só ele: a peça entra apenas como pose de
	-- repouso do movimento, sem depender de CanQuery, raio do mouse ou linha de visão livre.
	local button = powerPart:FindFirstChildWhichIsA("GuiButton", true)
	if button then
		table.insert(controlLinks, button.Activated:Connect(pressPower))

		-- Sobre um TextButton a engine sobrescreve o ícone do ponteiro e ignora o nosso. Por isso o
		-- hover mora num Frame por cima da tecla: em Frame o ícone vale, e o clique dele vem pelo
		-- InputBegan, já que o painel por cima recebe o gesto antes do botão.
		local pad = Instance.new("Frame")
		pad.Name = HOVER_NAME
		pad.BackgroundTransparency = 1
		pad.Active = true
		pad.AnchorPoint = button.AnchorPoint
		pad.Position = button.Position
		pad.Size = button.Size
		pad.ZIndex = button.ZIndex + 1
		pad.Parent = button.Parent
		hoverPad = pad

		table.insert(
			controlLinks,
			pad.InputBegan:Connect(function(input)
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					pressPower()
				end
			end)
		)
		watchHover(pad)
	end

	print(
		string.format(
			"[SecMonitor] controle ligado: lâmpada=%s botão=%s",
			tostring(lamp ~= nil),
			tostring(button ~= nil)
		)
	)
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
attach = function(index, panel)
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
	local back = panel:FindFirstChild(BACK_NAME)
	local view = panel:FindFirstChild(VIEW_NAME)
	local slot = {
		index = index,
		back = back,
		view = view,
		viewText = view and view:IsA("TextButton") and view.Text or "",
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
		vfxColor = vfx and vfx.ImageColor3,
		vfxFade = vfx and vfx.ImageTransparency,
		vfxAt = 0,
		backingBase = viewport.BackgroundTransparency,
		figures = {},
		copies = {},
	}
	table.insert(slots, slot)

	-- O Background é um ImageButton de tela cheia em ZIndex 20, acima de Back, REC e Value: sem tirar
	-- ele da fila de input, o clique deles morre nele. Sem função ligada, ele não perde nada.
	local background = panel:FindFirstChild(BACKGROUND_NAME)
	if background and background:IsA("GuiButton") then
		background.Interactable = false
		background.Active = false
	end

	if view and view:IsA("GuiButton") then
		table.insert(controlLinks, view.Activated:Connect(function()
			setSolo(index)
		end))
		watchHover(view)
	end
	if back and back:IsA("GuiButton") then
		table.insert(controlLinks, back.Activated:Connect(function()
			setSolo(nil)
		end))
		watchHover(back)
	end

	-- Chegou com o posto já ocupado: entra com a cena montada, não preta até o próximo sentar. Se for
	-- a tela caída, volta caída — a falha é do índice, não do slot, que o streaming refaz.
	if live then
		if slot.index == broken then
			brokenLook(slot, true)
		else
			buildScene(slot)
		end
	end
end

-- A lâmpada da mesa decorativa pisca para qualquer um que passe, com o posto vazio inclusive.
local function bindDesk(monitor)
	local control = childLike(monitor, CONTROL_NAME)
	local led = control and childLike(control, LED_NAME)
	if led and led:IsA("BasePart") then
		deskLed = led
		deskLamp = SecCamController.Lamp(led, os.clock())
	end
end

-- A mesa do workspace só dá o prompt, a lâmpada decorativa e o gancho das câmeras; painel, tecla e
-- vista vêm da cabine, clonada quando alguém senta.
local function bind(folder, monitor)
	local screen = childLike(monitor, SLOT_PATH[1])
	if not screen then
		return false
	end
	boundFolder = folder
	sceneRoot = folder.Parent
	boundMonitor = monitor
	prompt = ensurePrompt(screen)
	bindDesk(monitor)
	buildBooth()

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
		-- Ligado: readota os painéis que esperam câmera e a lâmpada da mesa que o streaming refez.
		-- Desligado: tenta a ligação inteira.
		if driver then
			for index, panel in pairs(pending) do
				attach(index, panel)
			end
			if boundMonitor and (deskLed == nil or deskLed.Parent == nil) then
				bindDesk(boundMonitor)
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
