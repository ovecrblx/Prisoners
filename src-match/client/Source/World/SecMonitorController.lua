-- Monitor da sala de segurança: cada slot da tela mostra o que uma câmera enquadra. ViewportFrame
-- não desenha o mundo, só o que está dentro dele — então o feed é uma cópia do cenário inteiro,
-- com porta espelhada quando se move, mais os corpos vivos, jogadores e NPCs, redesenhados por
-- quadro. Tudo local, e só montado para quem ocupa o posto.
local ContentProvider = game:GetService("ContentProvider")
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
local HighlightGate = require(script.Parent:WaitForChild("HighlightGate"))
local SecCamController = require(script.Parent:WaitForChild("SecCamController"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

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

-- Chiado do fundo da tela: a capa opaca atrás dela, onde a folha de grão mora, os s entre saltos do
-- grão, e quanto a folha passa da tela para ter folga onde deslizar. O nome da folha também é o da
-- capa inerte de cada painel.
local BACKING_NAME = "Back"
local BACKGROUND_NAME = "Background"
local SNOW_GAP = NumberRange.new(0.05, 0.12)
local SNOW_OVERSCAN = 1.3

-- Falha de sinal, uma tela por vez: s de espera até ela cair, o intervalo curto do chiado enquanto
-- está caída, e os s longe do posto que a consertam. A espera vai de segundos a minutos.
local GLITCH_WAIT = NumberRange.new(8, 210)
local GLITCH_MIN, GLITCH_MAX = 0.02, 0.05
local GLITCH_COLOR = Color3.new(1, 1, 1)
local GLITCH_FADE = 0.7
local GLITCH_BACKING = 0
local GLITCH_COOLDOWN = 30

-- Painel de controle: a lâmpada que pisca junto das câmeras e o botão que desliga o posto.
local CONTROL_NAME = "Control"
local POWER_NAME = "Power"

-- studs que a tecla afunda, s de cada perna do curso (ida e volta), e s entre o clique e sair.
local PRESS_DEPTH = 0.015
local PRESS_TIME = 0.12
local POWER_DELAY = 0.5

-- Painel transparente por cima da tecla: é ele que recebe o hover e o clique.
local HOVER_NAME = "PowerHover"

-- Efeito das teclas da tela: quanto crescem sob o ponteiro, quanto afundam no clique, quanto do
-- fundo revelam apontadas, e o curso de cada movimento.
local HOVER_GROW = 1.06
local PRESS_SINK = 0.95
local HOVER_LIFT = 0.25
local HOVER_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local SINK_TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- Feed em solo: os botões que entram e saem dele, a célula que faz um painel ocupar a grade toda, o
-- quanto o chiado da tela escolhida desbota, os s de chiado que cobrem a troca de janela, e os s de
-- fundo fechado no Vfx quando o mosaico volta.
local VIEW_NAME = "View"
local BACK_NAME = "Back"
local VALUE_NAME = "Value"
local NO_SIGNAL = "No Signal"
local SOLO_CELL = UDim2.fromScale(1, 1)
local SOLO_FADE = 0.75
local SWITCH_BURST = 0.35
local FLASH_SPAN = NumberRange.new(1, 2)

-- O direcional do solo: cada tecla do painel Control soma o próprio eixo (x guinada, y inclinação)
-- enquanto segurada. graus/s do giro, e os tetos a partir da pose em que a lente estava.
local TURN_DIRS = {
	Up = Vector2.new(0, 1),
	Low = Vector2.new(0, -1),
	Left = Vector2.new(-1, 0),
	Right = Vector2.new(1, 0),
}
local TURN_SPEED = 40
local TURN_YAW = 110
local TURN_PITCH = 50

-- s do rabo do servo: ao soltar, o efeito salta para tão perto do fim, e some tanto depois disso.
local SERVO_TAIL, SERVO_GRACE = 0.3, 0.2

-- Limites por câmera, os dois eixos no MESMO convênio: curso em graus a partir da pose de REPOUSO
-- autorada da lente — o solo sempre abre nela, no zero. `yaw` Min à esquerda / Max à direita;
-- `pitch` Min para baixo / Max para cima. Câmera sem entrada aqui fica nos tetos gerais.
local TURN_LIMITS = {
	[1] = { yaw = NumberRange.new(-12, 12), pitch = NumberRange.new(-12, 12) },
	[2] = { yaw = NumberRange.new(-12, 12), pitch = NumberRange.new(-12, 12) },
	[3] = { yaw = NumberRange.new(-12, 12), pitch = NumberRange.new(-12, 12) },
	[4] = { yaw = NumberRange.new(-12, 12), pitch = NumberRange.new(-12, 12) },
}

-- Modelos do cenário que cada câmera NÃO renderiza, por nome em minúsculas: ficam fora da cópia do
-- feed dela e são velados na vista ao vivo do solo dela. Nome exato — Dual_Door1 não é Dual_Door.
local CAM_IGNORES = {
	[1] = { ["dual_door"] = true },
}

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

-- s entre atualizações dos bonecos e entre verificações de presença na mesa. 10 quadros/s é o passo
-- dos sistemas de CCTV de referência, e em tela de vigilância lê como vídeo, não como jogo.
local FIGURE_INTERVAL = 1 / 10
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

-- O cenário compartilhado pelos feeds: a última pose espelhada de cada peça de origem, e as
-- ligações que acompanham o streaming enquanto o posto está ligado. Mapa por peça: quem o
-- streaming leva sai do registro, em vez de acumular entrada morta.
local scenePoses = {}
local sceneLinks = {}

-- A grade dos feeds, a célula autorada dela, e qual painel está em solo agora.
local grid = nil
local gridCell = nil
local solo = nil

-- O solo dirigido: a pose da lente ao entrar já decomposta em posição, guinada e inclinação de
-- MUNDO, o giro acumulado, e as teclas seguradas agora. A rolagem do rastreio é descartada.
local soloBase = nil
local soloYaw = 0
local soloPitch = 0
local turnHeld = {}
-- O motor da lente, num só nome: o Sound tocando, o que está terminando, e os três gestos. Luau só
-- dá 200 registradores por escopo, e o topo deste módulo está perto do teto — campos de tabela não
-- gastam nenhum.
local Servo = { sound = nil, tail = nil, noise = nil }

-- Corta NA HORA, sem rabo: trocar de câmera, sair do solo, largar o posto.
function Servo.cut()
	if Servo.sound then
		Servo.sound:Destroy()
		Servo.sound = nil
	end
	if Servo.tail then
		Servo.tail:Destroy()
		Servo.tail = nil
	end
end

-- O aperto entra no MEIO da gravação, pulando o arranque do motor.
function Servo.start()
	Servo.cut()
	Servo.sound = Sfx.Hold("CamServo")
	if Servo.sound and Servo.sound.TimeLength > 0 then
		Servo.sound.TimePosition = Servo.sound.TimeLength / 2
	end
end

-- Soltar salta para o rabo da gravação em vez de cortar — é a desaceleração. O Sound vive o que
-- sobrou e sai sozinho; um aperto novo no meio disso o mata antes, pelo `cut`.
function Servo.stop()
	local sound = Servo.sound
	Servo.sound = nil
	if not sound then
		return
	end

	Servo.tail = sound
	if sound.TimeLength > 0 then
		sound.TimePosition = math.max(0, sound.TimeLength - SERVO_TAIL)
	end

	task.delay(SERVO_TAIL + SERVO_GRACE, function()
		if Servo.tail == sound then
			Servo.tail = nil
		end
		sound:Destroy()
	end)
end

-- A folha de chiado atrás da grade: a GUI da capa que a carrega, a folga que ela tem para deslizar,
-- e quando o grão salta.
local snow = nil
local snowSurface = nil
local snowSlack = Vector2.zero
local snowAt = 0

-- A cabine clonada do operador, a pose autorada da vista, o desvio da vista até o pivô da cabine, e
-- a lâmpada da mesa decorativa, que pisca para quem passa.
local booth = nil
local viewerHome = nil
local boothOffset = nil
local deskLamp = nil
local deskLed = nil

-- A tecla de desligar, o desvio autorado dela até o pivô da cabine, o instante do clique, a pose
-- autorada de cada tecla da tela e o passo da lâmpada da cabine.
local boundMonitor = nil
local powerPart = nil
local powerLocal = nil
local pressedAt = -math.huge
local controlLinks = {}
local buttonHomes = {}
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
	-- Sem mouse não há ponteiro a desenhar, e esconder o ícone do sistema não teria o que esconder.
	if not UserInputService.MouseEnabled then
		return
	end

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

-- Apertar e soltar valem para todo aparelho: InputBegan e InputEnded do GuiObject trazem o dedo e o
-- mouse pelo mesmo caminho, e Activated fecha o toque simples em qualquer um. MouseButton1Down/Up e
-- MouseEnter/Leave são de mouse — no celular a tecla ficava muda.
local POINTERS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

-- Soltar longe da tecla não chega ao objeto — arrastar para fora e largar deixaria o gesto preso.
-- Quem vê isso é o serviço, e daí as duas escutas do fim. O trinco `held` é o que impede a de fora
-- de soltar tecla que ninguém apertou: sem ele, todo dedo levantado na tela mexeria em todas.
local function onPointer(object, press, release, links)
	local held = false

	table.insert(links, object.InputBegan:Connect(function(input)
		if POINTERS[input.UserInputType] and not held then
			held = true
			press()
		end
	end))

	local function finish(input)
		if POINTERS[input.UserInputType] and held then
			held = false
			release()
		end
	end

	table.insert(links, object.InputEnded:Connect(finish))
	table.insert(links, UserInputService.InputEnded:Connect(finish))
end

-- Contar quantos alvos estão sob o ponteiro, em vez de esconder no primeiro MouseLeave: passando
-- direto de um botão para o vizinho, a saída de um chega depois da entrada do outro e apagaria o
-- cursor com o mouse ainda em cima.
-- Só de mouse: dedo não paira, e o ponteiro desenhado não existe fora dele.
local function watchHover(button, links)
	links = links or controlLinks
	table.insert(links, button.MouseEnter:Connect(function()
		hovering += 1
		showCursor()
	end))
	table.insert(links, button.MouseLeave:Connect(function()
		hovering = math.max(0, hovering - 1)
		if hovering == 0 then
			hideCursor()
		end
	end))
end

-- A cabine sobrevive à sessão, e largar o posto não dispara MouseLeave: sem devolver a pose autorada,
-- a tecla ficaria crescida esperando um ponteiro que já não está lá.
local function restoreHomes(homes)
	for _, home in ipairs(homes) do
		if home.button.Parent then
			home.scale.Scale = 1
			home.button.BackgroundTransparency = home.fade
		end
	end
end

local function restoreButtons()
	restoreHomes(buttonHomes)
	for _, slot in ipairs(slots) do
		restoreHomes(slot.homes)
	end
end

-- Toda tecla da tela reage igual: cresce e fecha o fundo sob o ponteiro, afunda no clique e volta.
-- O crescer é um UIScale dentro do alvo — Size direto brigaria com o UIGridLayout do direcional, que
-- é dono do tamanho dos filhos. O alvo pode ser o Frame pai da tecla; os sinais vêm de `source`.
-- AutoButtonColor sai porque tinge a tecla por conta própria, fora deste curso.
-- `links`/`homes` dizem quem é o dono das conexões: as do painel de um feed vivem no slot e morrem
-- com ele; sem dono, caem nas listas da cabine, que só o unbind limpa.
local function dressButton(button, source, clickKey, links, homes)
	source = source or button
	clickKey = clickKey or "UiClick"
	links = links or controlLinks
	homes = homes or buttonHomes
	local fade = button.BackgroundTransparency
	for _, item in ipairs({ button, source }) do
		if item:IsA("GuiButton") then
			item.AutoButtonColor = false
		end
	end

	-- Reaproveitado: o painel readotado refaz o attach na mesma tecla, e um segundo UIScale
	-- multiplicaria o primeiro.
	local scale = button:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = button
	end
	table.insert(homes, { button = button, scale = scale, fade = fade })

	-- Onde o ponteiro para depois de soltar: em cima da tecla ela fica crescida, e no toque, que não
	-- paira, volta ao tamanho de repouso.
	local under = false

	table.insert(
		links,
		source.MouseEnter:Connect(function()
			under = true
			local lifted = math.max(0, fade - HOVER_LIFT)
			TweenService:Create(scale, HOVER_TWEEN, { Scale = HOVER_GROW }):Play()
			TweenService:Create(button, HOVER_TWEEN, { BackgroundTransparency = lifted }):Play()
			Sfx.Play("UiHover")
		end)
	)
	table.insert(
		links,
		source.MouseLeave:Connect(function()
			under = false
			TweenService:Create(scale, HOVER_TWEEN, { Scale = 1 }):Play()
			TweenService:Create(button, HOVER_TWEEN, { BackgroundTransparency = fade }):Play()
		end)
	)

	onPointer(source, function()
		TweenService:Create(scale, SINK_TWEEN, { Scale = PRESS_SINK }):Play()
		Sfx.Play(clickKey)
	end, function()
		TweenService:Create(scale, SINK_TWEEN, { Scale = if under then HOVER_GROW else 1 }):Play()
	end, links)

	watchHover(source, links)
end

local function dropControlLinks()
	for _, link in ipairs(controlLinks) do
		link:Disconnect()
	end
	table.clear(controlLinks)
	table.clear(turnHeld)
	Servo.cut()
	restoreButtons()
	table.clear(buttonHomes)
	hideCursor()
	lamp = nil
	powerPart = nil
	powerLocal = nil

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

-- Dentro do viewport nada disso desenha nem roda; só pesaria na cópia. Texture herda de Decal, e
-- SurfaceAppearance é a pintura PBR das MeshParts — sem ela o corpo e o cenário saem lisos.
local function stripCopy(part)
	for _, item in ipairs(part:GetDescendants()) do
		if not (item:IsA("Decal") or item:IsA("SpecialMesh") or item:IsA("SurfaceAppearance")) then
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

-- Peça invisível ainda desenha o Decal que carrega — a cortina de escritório é autorada assim, o
-- pano é só o Decal num Part transparente. Cortá-la pela Transparency abria buraco no feed.
local function wantedInScene(item)
	if not item:IsA("BasePart") or isCamPart(item) then
		return false
	end
	if item.Transparency < 1 then
		return true
	end
	for _, child in ipairs(item:GetChildren()) do
		if child:IsA("Decal") and child.Transparency < 1 then
			return true
		end
	end
	return false
end

-- A caixa do nome não tem cobertura, então a peça pertence ao modelo ignorado por nome minúsculo,
-- em qualquer nível de aninhamento.
local function inNamedModel(item, names)
	local model = item:FindFirstAncestorOfClass("Model")
	while model do
		if names[string.lower(model.Name)] then
			return true
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- Fora da renderização DESTE cliente agora: a lente em uso e o que a câmera dela ignora. As demais
-- lentes ficam de pé — aparecem no quadro umas das outras, como câmera de verdade.
-- LocalTransparencyModifier é só de render local; a Transparency replicada fica intacta.
local veiled = {}

local function veilModel(model, on)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = if on then 1 else 0
		end
	end
end

local function syncVeil(wanted)
	for model in pairs(veiled) do
		if not wanted[model] then
			veiled[model] = nil
			veilModel(model, false)
		end
	end
	for model in pairs(wanted) do
		if not veiled[model] then
			veiled[model] = true
			veilModel(model, true)
		end
	end
end

-- O mapa INTEIRO entra, varrendo a hierarquia do cenário: consulta espacial não devolve peça com
-- CanQuery desligado (medido: 148 das 1546 assim), e raio ou teto cortavam o resto em silêncio.
local function collectSources()
	table.clear(scenePoses)
	for _, item in ipairs(sceneRoot and sceneRoot:GetDescendants() or {}) do
		if wantedInScene(item) then
			scenePoses[item] = item.CFrame
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

	local ignores = CAM_IGNORES[slot.index]
	task.spawn(function()
		-- Foto das chaves antes do laço: o streaming muda o mapa durante as esperas de orçamento, e
		-- mutar tabela em iteração é indefinido.
		local sources = {}
		for source in pairs(scenePoses) do
			table.insert(sources, source)
		end

		local spent = 0
		for _, source in ipairs(sources) do
			if slot.scene ~= scene then
				return
			end
			if source.Parent and scenePoses[source] and not (ignores and inNamedModel(source, ignores)) then
				local copy = source:Clone()
				stripCopy(copy)
				copy.Parent = scene
				slot.copies[source] = copy
			end

			spent += 1
			if spent >= SCENE_BUDGET then
				spent = 0
				RunService.PostSimulation:Wait()
			end
		end

		-- Textura de Decal só é buscada quando o viewport a desenha pela primeira vez, e sai cinza até
		-- chegar; puxar agora cobre a janela de quem acabou de sentar.
		local decals = {}
		for _, item in ipairs(scene:GetDescendants()) do
			if item:IsA("Decal") then
				table.insert(decals, item)
			end
		end
		if #decals > 0 and slot.scene == scene then
			pcall(function()
				ContentProvider:PreloadAsync(decals)
			end)
		end
	end)

	-- Cena vazia é o sintoma de sala ainda não transmitida, e sem aviso pareceria feed quebrado.
	if next(scenePoses) == nil and not slot.warned then
		slot.warned = true
		warn(string.format("[SecMonitor] %s sem cenário carregado; feed fica vazio.", slot.head:GetFullName()))
	end
end

-- Peça de cenário que se moveu (porta, elevador) move a cópia em todos os feeds, em lote e só as
-- que mudaram: comparar CFrame é barato, e reescrever o mapa inteiro por quadro não é.
local function syncScenery()
	local moved = {}
	for source, pose in pairs(scenePoses) do
		if source.Parent and source.CFrame ~= pose then
			scenePoses[source] = source.CFrame
			table.insert(moved, source)
		end
	end
	if #moved == 0 then
		return
	end

	for _, slot in ipairs(slots) do
		local parts, poses = {}, {}
		for _, source in ipairs(moved) do
			local copy = slot.copies[source]
			if copy then
				table.insert(parts, copy)
				table.insert(poses, scenePoses[source])
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
			-- Peça de modelo velado que o streaming trouxe no meio do solo chega já invisível. E um
			-- modelo ignorado que renasce invalida o cache: a próxima passada o resolve de novo.
			if item:IsA("BasePart") then
				for model in pairs(veiled) do
					if item:IsDescendantOf(model) then
						item.LocalTransparencyModifier = 1
						break
					end
				end
			elseif item:IsA("Model") then
				for _, slot in ipairs(slots) do
					local ignores = CAM_IGNORES[slot.index]
					if ignores and ignores[string.lower(item.Name)] then
						slot.hidden = nil
					end
				end
			end
			if scenePoses[item] ~= nil or not wantedInScene(item) then
				return
			end
			scenePoses[item] = item.CFrame
			for _, slot in ipairs(slots) do
				local ignores = CAM_IGNORES[slot.index]
				if slot.scene and not (ignores and inNamedModel(item, ignores)) then
					local copy = item:Clone()
					stripCopy(copy)
					copy.Parent = slot.scene
					slot.copies[item] = copy
				end
			end
		end)
	)

	table.insert(
		sceneLinks,
		sceneRoot.DescendantRemoving:Connect(function(item)
			-- Sai do registro de vez; se a mesma peça voltar pelo streaming, o DescendantAdded a
			-- registra de novo.
			if scenePoses[item] == nil then
				return
			end
			scenePoses[item] = nil
			for _, slot in ipairs(slots) do
				local copy = slot.copies[item]
				if copy then
					copy:Destroy()
					slot.copies[item] = nil
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
	table.clear(scenePoses)
end

local function clearFigures(slot)
	for body, figure in pairs(slot.figures) do
		figure.model:Destroy()
		slot.figures[body] = nil
	end
end

-- Solta o que o attach ligou na GUI persistente: painel readotado religa tudo, e a conexão antiga
-- duplicaria cada gesto.
local function releaseSlot(slot)
	for _, link in ipairs(slot.links) do
		link:Disconnect()
	end
	table.clear(slot.links)
	restoreHomes(slot.homes)
	table.clear(slot.homes)
end

local function listParts(items)
	local parts = {}
	for _, item in ipairs(items) do
		if item:IsA("BasePart") then
			table.insert(parts, item)
		end
	end
	return parts
end

-- Boneco: o personagem INTEIRO clonado, com as peças reposicionadas em lote a cada atualização. Em
-- corpo R15 a roupa é composta pelo motor a partir do conjunto — Humanoid, peças e Shirt juntos — e
-- não mora na textura de peça nenhuma: copiando peça por peça vinha a cor e nunca a roupa.
local function makeFigure(slot, character)
	local sourceList = character:GetDescendants()
	local model = character:Clone()
	local copyList = model:GetDescendants()
	model.Name = "Figure"

	-- O viewport pendura no PlayerGui, e script copiado ali dentro RODA; som e GUI idem.
	for _, item in ipairs(copyList) do
		if item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("LayerCollector") then
			item:Destroy()
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	-- As peças saem da MESMA árvore, na mesma ordem, então casam por posição — pelo nome não dá, que
	-- todo acessório traz um "Handle". Contagem diferente é corpo mexido no meio do clone: o boneco
	-- entra como estátua, em vez de espelhar peça na peça errada.
	local parts, sources = listParts(copyList), listParts(sourceList)
	local statue = #parts ~= #sources
	if statue then
		warn(string.format(
			"[SecMonitor] boneco de %s divergiu do corpo (%d peças no clone, %d no vivo); entra como estátua.",
			character.Name, #parts, #sources))
		table.clear(parts)
		table.clear(sources)
	end

	for _, item in ipairs(copyList) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		end
	end

	model.Parent = slot.viewport
	return { model = model, parts = parts, sources = sources, poses = table.create(#parts), statue = statue }
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
			-- Estátua fica: sem peças espelhadas ela reprovaria no teste de vida e seria reclonada a
			-- cada passada.
			if not figure or (not figure.statue and (figure.parts[1] == nil or figure.parts[1].Parent == nil)) then
				if figure then
					figure.model:Destroy()
				end
				figure = makeFigure(slot, body)
				slot.figures[body] = figure
			end

			if not figure.statue then
				local poses = figure.poses
				for index, source in ipairs(figure.sources) do
					poses[index] = source.CFrame
				end
				Workspace:BulkMoveTo(figure.parts, poses, Enum.BulkMoveMode.FireCFrameChanged)
			end
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
		-- Active é o que deixa a GUI de mundo receber gesto; sem ele o toque não chega às teclas.
		surface.Active = true
		surface.Adornee = surfaceHome
		surface.Parent = playerGui
	end

	-- O chiado da capa é do OPERADOR, como os feeds: a cabine fica de pé a partida inteira, e fora da
	-- sessão a folha nem chega a ser desenhada.
	if snowSurface then
		snowSurface.Enabled = true
	end

	local camera = Workspace.CurrentCamera
	if camera and viewerHome then
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = viewerHome
	end
end

local function releaseView()
	coverSwap()
	if prompt then
		prompt.Enabled = true
	end

	if snowSurface then
		snowSurface.Enabled = false
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
	glitchAt = now + GLITCH_WAIT.Min + math.random() * (GLITCH_WAIT.Max - GLITCH_WAIT.Min)
end

-- Painel sem sinal E escolhido fecha o próprio fundo: no solo o viewport está escondido e a tela da
-- cabine é transparente, então a falha não teria onde aparecer. No mosaico o painel fica no autorado.
local function panelBacking(slot, dead)
	if slot.panelBase then
		slot.panel.BackgroundTransparency = if dead and solo == slot.index then GLITCH_BACKING else slot.panelBase
	end
end

local function brokenLook(slot, on)
	panelBacking(slot, on)
	slot.viewport.BackgroundTransparency = if on then GLITCH_BACKING else slot.backingBase
	if slot.vfx then
		slot.vfx.ImageColor3 = if on then GLITCH_COLOR else slot.vfxColor
		slot.vfx.ImageTransparency = if on then GLITCH_FADE else slot.vfxFade
	end

	-- O rótulo do botão diz o estado da tela: a falha se anuncia onde o operador ia clicar para
	-- abrir o feed. E tela caída não se dirige — o direcional some com o sinal.
	if slot.view then
		slot.view.Text = if on then NO_SIGNAL else slot.viewText
	end
	if slot.control then
		slot.control.Visible = not on and solo == slot.index
	end
end

local function breakSlot(slot)
	broken = slot.index
	brokenLook(slot, true)
	Sfx.Play("Glitch")
	clearScene(slot)
	clearFigures(slot)
end

-- A cabine nasce ao sentar: clone local do Viewer_Model, com o monitor REAL dentro — tela, tecla e
-- Viewer_Cam. Só o operador a tem, então a privacidade dos feeds continua de graça.
local function slotAt(index)
	for _, slot in ipairs(slots) do
		if slot.index == index then
			return slot
		end
	end
	return nil
end

-- A ordem de `slots` é a de chegada pelo streaming, não a dos rótulos: a troca segue o NÚMERO da
-- câmera, senão a CAM 1 levaria à CAM 3.
-- Voltar ao mosaico fecha o fundo do Vfx de todas as telas, cada uma pelo próprio tempo sorteado:
-- juntas, as quatro abrindo no mesmo instante leriam como um só clarão da tela, não como quatro
-- monitores reentrando.
local function flashPanels()
	local now = os.clock()
	for _, slot in ipairs(slots) do
		slot.flash = now + FLASH_SPAN.Min + math.random() * (FLASH_SPAN.Max - FLASH_SPAN.Min)
	end
end

local function nextIndex(from)
	local order = {}
	for _, slot in ipairs(slots) do
		table.insert(order, slot.index)
	end
	if #order == 0 then
		return nil
	end

	table.sort(order)
	for _, index in ipairs(order) do
		if index > from then
			return index
		end
	end
	return order[1]
end

-- Um feed sozinho na tela: os outros painéis saem, e a célula da grade cresce para a tela inteira.
-- `Back` só existe no solo, e é ele quem devolve a célula autorada e traz os quatro de volta.
local function setSolo(index)
	local changed = solo ~= index
	solo = index
	if grid then
		grid.CellSize = if index then SOLO_CELL else gridCell
	end

	-- Cada solo começa na pose em que a lente estava, com o giro zerado; dali quem vira é o operador.
	if changed then
		soloBase = nil
		soloYaw, soloPitch = 0, 0
		table.clear(turnHeld)
		Servo.cut()
	end

	for _, slot in ipairs(slots) do
		local alone = index ~= nil and slot.index == index
		slot.panel.Visible = index == nil or alone

		-- Escolhida uma tela, TODO feed sai: o cenário está montado para a vista olhar ao vivo a
		-- posição de cada câmera, e a cópia do viewport só taparia o que ela mostra. O chiado da tela
		-- escolhida desbota junto, pelo mesmo motivo: na cor cheia ele é o que sobra na frente.
		slot.viewport.Visible = index == nil
		panelBacking(slot, slot.index == broken)
		if slot.vfx and slot.index ~= broken then
			slot.vfx.ImageTransparency = if alone then SOLO_FADE else slot.vfxFade
		end

		-- No solo os dois trocam de lugar: quem abriu a tela sai, e só resta o caminho de volta.
		if slot.view then
			slot.view.Visible = not alone
		end
		if slot.back then
			slot.back.Visible = alone
		end
		if slot.control then
			slot.control.Visible = alone
		end
	end

	-- Corte seco entre câmeras leria como a MESMA lente girando: o estouro curto de chiado é o que
	-- marca que a janela trocou.
	local opened = if changed and index then slotAt(index) else nil
	if opened then
		opened.burst = os.clock() + SWITCH_BURST
		Sfx.Play("CamSwitch")
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

	-- A pose autorada da vista, e o desvio dela até o pivô: com os dois a cabine INTEIRA viaja com a
	-- câmera, e a moldura cai sobre o quadro do mesmo jeito em qualquer lente.
	viewerHome = viewer and viewer.CFrame
	boothOffset = if viewerHome then viewerHome:Inverse() * booth:GetPivot() else nil

	-- O chiado mora na SurfaceGui da capa opaca ATRÁS da tela, não na da tela: a tela ficou
	-- transparente para a vista olhar através dela, e a folha pendurada nela sumiria junto.
	-- Ladrilhada e maior que a capa: o grão guarda o tamanho e é a folha que desliza dentro da folga.
	-- Embaralhar o chiado esticando o ladrilho fazia o grão respirar, que lê como zoom, não como ruído.
	local backing = childLike(monitor, BACKING_NAME)
	local backSurface = backing and childLike(backing, SLOT_PATH[2])
	local sheet = backSurface and backSurface:FindFirstChild(BACKGROUND_NAME)
	snow = if sheet and sheet:IsA("ImageLabel") then sheet else nil
	snowSurface = if snow then backSurface else nil
	if snowSurface then
		snowSurface.Enabled = false
	end
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

	-- O chiado do tubo é CONTÍNUO enquanto se opera: os estouros da troca e da falha são por cima
	-- dele, e sem o leito a sala emudecia assim que a tela expandia.
	Servo.noise = Sfx.Hold("ScreenNoise")

	-- Ocupar o posto é o mosaico entrando pela primeira vez: mesmo clarão da volta do solo, e ele
	-- ainda cobre o tempo em que a cena está sendo montada em fatias.
	flashPanels()
	Sfx.Play("MonitorOn")

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
	local sources = 0
	for _ in pairs(scenePoses) do
		sources += 1
	end
	print(string.format("[SecMonitor] posto ligado: %d feeds, %d peças de cenário", #slots, sources))
end

local function deactivate()
	if not live then
		return
	end
	live = false
	SecCamController.KeepAwake(false)
	releaseView()

	if Servo.noise then
		Servo.noise:Destroy()
		Servo.noise = nil
	end
	leftAt = os.clock()
	unwatchScenery()
	syncVeil({})

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
		slot.burst = 0
		slot.bursting = false
		slot.flash = 0
		slot.flashing = false
		if slot.vfx then
			slot.vfx.BackgroundTransparency = slot.vfxBacking
		end
	end
	restoreButtons()

	-- A grade volta ao arranjo autorado: quem sentar depois começa com os quatro feeds, não no solo
	-- que o operador anterior deixou. E a cabine volta à base, que ela fica de pé entre sessões.
	setSolo(nil)
	if booth and viewerHome and boothOffset then
		booth:PivotTo(viewerHome * boothOffset)
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
-- Os contornos saem do assento, não da sessão do posto: eles some com o corpo sentado mesmo que o
-- monitor ainda não tenha chegado pelo streaming.
evaluate = function()
	local atPost = operating()
	HighlightGate.Suppress(atPost)

	if not boundMonitor then
		return
	end
	if atPost then
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
				releaseSlot(slot)
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
		snowAt = now + SNOW_GAP.Min + math.random() * (SNOW_GAP.Max - SNOW_GAP.Min)
		local x = 0.5 + (math.random() * 2 - 1) * snowSlack.X
		local y = 0.5 + (math.random() * 2 - 1) * snowSlack.Y
		snow.Position = UDim2.fromScale(x, y)
	end

	-- No solo os quatro viewports estão escondidos e as poses guardadas ficam velhas de propósito: a
	-- volta ao mosaico compara contra elas e a primeira passada emparelha tudo que se moveu.
	sinceScene += delta
	if sinceScene >= SCENE_SYNC_INTERVAL and solo == nil then
		sinceScene = 0
		syncScenery()
	end

	-- O chiado salta o TileSize do Vfx dentro da faixa, cada tela no próprio ritmo — em sincronia
	-- leria como UMA interferência, não como quatro monitores velhos.
	if not broken and now >= glitchAt and #slots > 0 then
		breakSlot(slots[math.random(#slots)])
	end

	-- No solo a vista É a câmera do jogador na lente escolhida, e a cabine viaja colada na orientação
	-- dela: moldura, chiado e teclas continuam sendo o quadro do monitor sobre o que a lente enquadra.
	-- A lente NÃO segue a Head no solo: parte da pose em que estava e dali quem vira é o direcional.
	-- Sem solo, ou com a tela caída, a vista volta ao posto — e a cabine, à base autorada.
	local soloSlot = if solo and solo ~= broken then slotAt(solo) else nil

	-- O véu acompanha a lente em uso, por quadro: a própria lente mais o que a câmera dela ignora.
	-- Cobre troca de solo, tela que cai no meio dele e câmera que o streaming levou — no quadro
	-- seguinte o véu já está nos modelos certos, ou em nenhum.
	local wantedVeil = {}
	if soloSlot then
		if soloSlot.camModel then
			wantedVeil[soloSlot.camModel] = true
		end
		local ignores = CAM_IGNORES[soloSlot.index]
		if ignores and not soloSlot.hidden then
			soloSlot.hidden = {}
			for _, item in ipairs(sceneRoot and sceneRoot:GetDescendants() or {}) do
				if item:IsA("Model") and ignores[string.lower(item.Name)] then
					table.insert(soloSlot.hidden, item)
				end
			end
		end
		for _, model in ipairs(soloSlot.hidden or {}) do
			if model.Parent then
				wantedVeil[model] = true
			end
		end
	end
	syncVeil(wantedVeil)

	local target = viewerHome
	if soloSlot then
		-- O zero é a pose de REPOUSO autorada da lente, a base do patrulhamento — não a pose solta em
		-- que o rastreio estava ao entrar: nela os limites caíam num lugar diferente a cada solo. E a
		-- pose entra DECOMPOSTA em guinada e inclinação de mundo, rolagem fora: girar sobre o CFrame
		-- cru misturava os eixos, e cada tecla deve mover só o próprio.
		if not soloBase then
			local pose = SecCamController.BasePose(soloSlot.camModel) or soloSlot.head.CFrame
			local look = pose.LookVector
			soloBase = {
				position = pose.Position,
				yaw = math.atan2(-look.X, -look.Z),
				pitch = math.asin(math.clamp(look.Y, -1, 1)),
			}
		end

		local turn = Vector2.zero
		for direction, axis in pairs(TURN_DIRS) do
			if turnHeld[direction] then
				turn += axis
			end
		end

		local limits = TURN_LIMITS[soloSlot.index]
		local yawLo = if limits then limits.yaw.Min else -TURN_YAW
		local yawHi = if limits then limits.yaw.Max else TURN_YAW
		local pitchLo = if limits then limits.pitch.Min else -TURN_PITCH
		local pitchHi = if limits then limits.pitch.Max else TURN_PITCH

		soloYaw = math.clamp(soloYaw + turn.X * TURN_SPEED * delta, yawLo, yawHi)
		soloPitch = math.clamp(soloPitch + turn.Y * TURN_SPEED * delta, pitchLo, pitchHi)
		target = CFrame.new(soloBase.position)
			* CFrame.Angles(0, soloBase.yaw + math.rad(soloYaw), 0)
			* CFrame.Angles(soloBase.pitch + math.rad(soloPitch), 0, 0)
	end
	local camera = Workspace.CurrentCamera
	if camera and target then
		camera.CFrame = target
		if boothOffset then
			local pivot = target * boothOffset
			booth:PivotTo(pivot)

			-- A tecla é reescrita em espaço LOCAL da cabine: o afundo do clique viaja junto dela em
			-- qualquer lente — escrito em pose absoluta da mesa, o clique a mandava de volta para lá.
			if powerPart and powerLocal then
				local t = (now - pressedAt) / PRESS_TIME
				local leg = math.clamp(if t < 1 then t else 2 - t, 0, 1)
				local eased = 1 - (1 - leg) * (1 - leg)
				powerPart.CFrame = pivot * powerLocal * CFrame.new(0, 0, PRESS_DEPTH * eased)
			end
		end
	end

	-- No solo os quatro viewports estão escondidos: mover a lente do feed e redesenhar boneco seria
	-- trabalho por quadro em cima do que ninguém vê.
	for _, slot in ipairs(slots) do
		if solo == nil and slot.index ~= broken then
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

		-- O estouro da troca de janela DESVANECE em vez de piscar: cor e ritmo entram nos da falha e
		-- escorrem de volta aos autorados ao longo da janela, e a troca lê como sinal reassentando.
		local flashing = now < slot.flash
		if flashing ~= slot.flashing then
			slot.flashing = flashing
			if slot.vfx then
				slot.vfx.BackgroundTransparency = if flashing then 0 else slot.vfxBacking
			end
		end

		local heat = math.clamp((slot.burst - now) / SWITCH_BURST, 0, 1)
		if heat > 0 or slot.bursting then
			slot.bursting = heat > 0
			if slot.vfx and slot.index ~= broken then
				slot.vfx.ImageColor3 = slot.vfxColor:Lerp(GLITCH_COLOR, heat)
			end
		end

		if slot.vfx and now >= slot.vfxAt then
			local low = VFX_MIN + (GLITCH_MIN - VFX_MIN) * heat
			local high = VFX_MAX + (GLITCH_MAX - VFX_MAX) * heat
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
	if sinceFigure >= FIGURE_INTERVAL and solo == nil then
		sinceFigure = 0
		for _, slot in ipairs(slots) do
			if slot.index ~= broken then
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
	for _, slot in ipairs(slots) do
		releaseSlot(slot)
	end
	table.clear(slots)
	table.clear(pending)
	surface = nil
	surfaceHome = nil
	snow = nil
	snowSurface = nil
	viewer = nil
	viewerHome = nil
	boothOffset = nil
	if booth then
		booth:Destroy()
		booth = nil
	end
	seat = nil
	prompt = nil
	deskLamp = nil
	deskLed = nil
	boundFolder = nil
	sceneRoot = nil
	boundMonitor = nil
end

-- A tecla afunda e volta sozinha — o curso é desenhado no passo, em espaço local da cabine — e o
-- posto só é largado depois da espera: sair no mesmo quadro do clique engoliria o movimento.
local function pressPower()
	if pressing or not live or not powerPart then
		return
	end
	pressing = true
	pressedAt = os.clock()

	-- O estalo mora AQUI, e não no `dressButton`: a tecla recebe o gesto por um Frame de hover, e o
	-- ramo de clique de lá só liga em GuiButton. Este é o funil dos dois caminhos — o TextButton
	-- autorado e o painel por cima —, e o trinco de `pressing` já impede o disparo dobrado.
	Sfx.Play("Power")

	task.delay(POWER_DELAY, function()
		pressing = false
		hideCursor()
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
	powerLocal = if powerPart and booth then booth:GetPivot():Inverse() * powerPart.CFrame else nil
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

		onPointer(pad, pressPower, function() end, controlLinks)
		dressButton(button, pad)
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

	local value = panel:FindFirstChild(VALUE_NAME)
	if value and value:IsA("TextButton") then
		value.Text = "CAM " .. index
	end

	local vfx = panel:FindFirstChild(VFX_NAME)
	local led = panel:FindFirstChild(LED_NAME)
	local rec = panel:FindFirstChild(REC_NAME)
	local back = panel:FindFirstChild(BACK_NAME)
	local view = panel:FindFirstChild(VIEW_NAME)
	local pad = panel:FindFirstChild(CONTROL_NAME)
	local slot = {
		index = index,
		back = back,
		view = view,
		control = pad,
		camModel = model,
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
		vfxBacking = vfx and vfx.BackgroundTransparency,
		burst = 0,
		bursting = false,
		flash = 0,
		flashing = false,
		backingBase = viewport.BackgroundTransparency,
		panelBase = panel.BackgroundTransparency,
		figures = {},
		copies = {},
		links = {},
		homes = {},
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
		table.insert(slot.links, view.Activated:Connect(function()
			setSolo(index)
		end))
		dressButton(view, nil, nil, slot.links, slot.homes)
	end
	if back and back:IsA("GuiButton") then
		table.insert(slot.links, back.Activated:Connect(function()
			setSolo(nil)
			flashPanels()
		end))
		dressButton(back, nil, nil, slot.links, slot.homes)
	end

	-- O rótulo é a tecla de trocar de janela: no mosaico ele abre a própria câmera, e no solo passa
	-- para a seguinte sem devolver o operador ao mosaico entre uma e outra.
	if value and value:IsA("GuiButton") then
		table.insert(slot.links, value.Activated:Connect(function()
			setSolo(if solo == nil then index else nextIndex(index))
		end))
		dressButton(value, nil, nil, slot.links, slot.homes)
	end

	-- O direcional: segurar vira, soltar para — Activated não serve, o gesto é contínuo. Arrastar
	-- para fora da tecla solta também, senão o giro ficaria preso com o botão do mouse já livre.
	-- O servo nasce NO clique, junto do estalo da tecla, e não no passo seguinte: um quadro de atraso
	-- é o bastante para os dois soarem em fila em vez de juntos. E cada aperto abre um Sound novo,
	-- que é o que o faz recomeçar do zero. Soltar uma tecla com outra ainda segurada não cala.
	for direction in pairs(TURN_DIRS) do
		local arm = pad and pad:FindFirstChild(direction)
		local button = arm and arm:FindFirstChildWhichIsA("GuiButton", true)
		if button then
			local function release()
				turnHeld[direction] = nil
				if not next(turnHeld) then
					Servo.stop()
				end
			end

			onPointer(button, function()
				turnHeld[direction] = true
				Servo.start()
			end, release, slot.links)
			dressButton(arm, button, nil, slot.links, slot.homes)
		end
	end

	-- O painel que o streaming devolveu no meio de um solo entra no arranjo de agora, não no mosaico.
	setSolo(solo)

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
