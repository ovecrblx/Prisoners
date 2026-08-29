-- Viewer 3D das classes. Clona ReplicatedStorage.Client.GUI.Viewer_Model em workspace.Temp,
-- assume a câmera e põe o Rig da classe em pé sobre o Part Base. A câmera é fixa: arrastar
-- gira o próprio Rig no eixo vertical, com inércia.
-- O clone é client-side: instância replicada movida para o workspace morre no streaming.
local ClassViewer = {}

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local Motion = require(script.Parent:WaitForChild("Motion"))

-- Pasta do place que recebe o clone da sala, e o Part que serve de pedestal.
local SCENE_PARENT = "Temp"
local BASE_NAME = "Base"

-- Folga em studs entre a sola do Rig e o topo do Base.
local RIG_GAP = 0.05

-- FieldOfView da câmera enquanto o viewer está aberto, em graus.
local VIEWER_FOV = 60

-- Idle do próprio avatar: Animate.idle.Animation1, o mesmo asset que o personagem usa em
-- jogo. O Animate é LocalScript e não roda fora do Character do jogador, então serve só
-- como fonte do AnimationId; quem toca é o Animator.
local IDLE_TRACK = "Animation1"
local IDLE_FADE = 0.3

-- Giro: graus por pixel arrastado, teto da velocidade em graus/s, amortecimento da
-- inércia (maior = para antes) e velocidade abaixo da qual o giro zera.
local ROTATE_SPEED = 0.55
local MAX_SPIN = 900
local SPIN_DAMPING = 2.6
local SPIN_SMOOTHING = 0.35
local SPIN_EPSILON = 1

-- Entrada da câmera: recua este fator da distância e volta ao lugar.
local INTRO_PULLBACK = 1.25
local INTRO_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Arrasto abaixo disso ainda conta como clique.
local DRAG_THRESHOLD = 6

-- Segundos de espera por um Rig que ainda não replicou.
local RIG_TIMEOUT = 20

-- s de folga entre itens da fila de pré-carga; item com alguém esperando não paga a folga.
local QUEUE_GAP = 1

-- s de espera pelas pastas fundamentais no boot; a replicação logo após o join é lenta.
local BOOT_TIMEOUT = 30

local scene, rig, camPart, basePart
local rigPosition, idleTrack
local yaw, spin, lastYaw = 0, 0, 0
local request = 0
local savedType, savedCFrame, savedSubject, savedFov
local dragging, dragMoved = false, false
local dragStartX, dragStartY, lastX = 0, 0, 0
local introTween
local connections = {}

-- Fundamentais do boot (sala e pasta de destino), a pasta dos rigs (dona: a fila), e a fila de
-- pré-carga: ids pendentes em ordem de prioridade, o que já foi pré-carregado e quem espera cada
-- rig. `openRequest` invalida um Open que ainda aguardava o boot quando o painel fechou.
local viewerSource, sceneFolder, charFolder
local bootStarted, bootDone = false, false
local openRequest = 0
local queue = {}
local preloaded = {}
local waiters = {}
local pumping = false

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}
end

-- Boot: sala e pasta de destino, uma vez e fora do clique. Pasta de cena ausente não vale espera:
-- o clone é local, uma pasta local serve igual.
local function resolveBoot()
	local client = ReplicatedStorage:WaitForChild("Client", BOOT_TIMEOUT)
	local gui = client and client:WaitForChild("GUI", BOOT_TIMEOUT)
	viewerSource = gui and gui:WaitForChild("Viewer_Model", BOOT_TIMEOUT)
	if not viewerSource then
		warn("[ClassViewer] ReplicatedStorage.Client.GUI.Viewer_Model não encontrado.")
	end

	sceneFolder = workspace:FindFirstChild(SCENE_PARENT)
	if not sceneFolder then
		local folder = Instance.new("Folder")
		folder.Name = SCENE_PARENT
		folder.Parent = workspace
		sceneFolder = folder
	end
	bootDone = true
end

local function ensureBoot()
	if bootStarted then
		return
	end
	bootStarted = true
	task.spawn(resolveBoot)
end

-- Yielda até o boot terminar; o clique só passa por aqui com o painel já animando.
local function awaitBoot()
	ensureBoot()
	while not bootDone do
		task.wait(0.1)
	end
	return viewerSource ~= nil
end

local function fireWaiters(classId, template)
	local list = waiters[classId]
	waiters[classId] = nil
	if list then
		for _, callback in ipairs(list) do
			task.spawn(callback, template)
		end
	end
end

-- A fila espera cada rig replicar e pré-carrega os assets, um por vez, em thread própria — clique
-- nenhum espera por ela. Dona única de `charFolder`.
local function pumpQueue()
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		if not charFolder then
			local client = ReplicatedStorage:WaitForChild("Client", BOOT_TIMEOUT)
			charFolder = client and client:WaitForChild("Character", BOOT_TIMEOUT)
			if not charFolder then
				warn("[ClassViewer] ReplicatedStorage.Client.Character não encontrado.")
				pumping = false
				return
			end
		end

		while #queue > 0 do
			local classId = table.remove(queue, 1)
			local entry = ClassConfig.Get(classId)
			if entry then
				local classFolder = charFolder:FindFirstChild(entry.Rig)
					or charFolder:WaitForChild(entry.Rig, RIG_TIMEOUT)
				local template = classFolder
					and (classFolder:FindFirstChild("Rig") or classFolder:WaitForChild("Rig", RIG_TIMEOUT))
				if template then
					if not preloaded[classId] then
						preloaded[classId] = true
						pcall(function()
							ContentProvider:PreloadAsync(template:GetDescendants())
						end)
					end
					fireWaiters(classId, template)
				else
					warn("[ClassViewer] Rig não encontrado em Character." .. entry.Rig)
					fireWaiters(classId, nil)
				end
			end

			-- A folga é só do trabalho de fundo: cabeça com alguém esperando é rig visualizado.
			local head = queue[1]
			if head and waiters[head] == nil then
				task.wait(QUEUE_GAP)
			end
		end
		pumping = false
		if #queue > 0 then
			pumpQueue()
		end
	end)
end

-- Rig pedido fura a fila; `callback` recebe o template, ou nil se ele não existir no pacote.
local function promote(classId, callback)
	for index, id in ipairs(queue) do
		if id == classId then
			table.remove(queue, index)
			break
		end
	end
	table.insert(queue, 1, classId)
	local list = waiters[classId]
	if not list then
		list = {}
		waiters[classId] = list
	end
	list[#list + 1] = callback
	pumpQueue()
end

-- Meia altura no eixo Y do mundo. O Base está rotacionado, então Size.Y não serve.
local function halfHeight(part)
	local cframe, size = part.CFrame, part.Size
	return 0.5
		* (
			math.abs(cframe.XVector.Y) * size.X
			+ math.abs(cframe.YVector.Y) * size.Y
			+ math.abs(cframe.ZVector.Y) * size.Z
		)
end

local function applyYaw()
	if rig and rigPosition then
		rig:PivotTo(CFrame.new(rigPosition) * CFrame.Angles(0, math.rad(yaw), 0))
	end
end

-- Sola do Rig no topo do Base: o pivot é o HumanoidRootPart, que fica acima dos pés.
local function standPosition()
	local bounds, size = rig:GetBoundingBox()
	local soleOffset = rig:GetPivot().Position.Y - (bounds.Position.Y - size.Y / 2)
	local top = basePart.Position.Y + halfHeight(basePart)

	return Vector3.new(basePart.Position.X, top + soleOffset + RIG_GAP, basePart.Position.Z)
end

-- Uma track por vez: só a classe em cena anima, e ela morre junto com o rig anterior.
local function playIdle()
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = rig:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	local source = idle and idle:FindFirstChild(IDLE_TRACK)

	if not (animator and source) then
		warn("[ClassViewer] Sem Animator ou sem Animate.idle." .. IDLE_TRACK .. " no rig.")
		return
	end

	idleTrack = animator:LoadAnimation(source)
	idleTrack.Looped = true
	idleTrack.Priority = Enum.AnimationPriority.Idle
	idleTrack:Play(IDLE_FADE)
end

local function stopIdle()
	if idleTrack then
		idleTrack:Stop(0)
		idleTrack:Destroy()
		idleTrack = nil
	end
end

local function focusPoint()
	if rig then
		return rig:GetBoundingBox().Position
	end
	return basePart and basePart.Position or Vector3.zero
end

-- Rig que chega tarde reaponta a câmera; se a entrada ainda corre, ela só troca de alvo.
local function aimCamera()
	local camera = workspace.CurrentCamera
	if not (camera and camPart) then
		return
	end

	local goal = CFrame.lookAt(camPart.Position, focusPoint())

	if introTween then
		introTween:Cancel()
		introTween = Motion.Tween(camera, INTRO_INFO, { CFrame = goal })
		return
	end

	camera.CFrame = goal
end

local function placeRig(template)
	rig = template:Clone()
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	rig.Parent = scene

	rigPosition = standPosition()
	yaw, spin, lastYaw = 0, 0, 0
	applyYaw()

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end

	playIdle()
end

local function swapRig(template)
	stopIdle()
	if rig then
		rig:Destroy()
		rig = nil
	end
	placeRig(template)
end

-- Sem yield, e o rig atual só morre com o substituto em mãos: template já replicado troca na
-- hora; senão o pedido fura a fila e o boneco atual segura o pedestal até o novo chegar.
local function loadRig(classId)
	local entry = ClassConfig.Get(classId)
	if not entry then
		warn("[ClassViewer] Classe fora do ClassConfig: " .. tostring(classId))
		return false
	end

	request += 1
	local token = request

	local classFolder = charFolder and charFolder:FindFirstChild(entry.Rig)
	local template = classFolder and classFolder:FindFirstChild("Rig")
	if template then
		swapRig(template)
		return true
	end

	promote(classId, function(model)
		if model and scene and request == token then
			swapRig(model)
			aimCamera()
		end
	end)
	return true
end

function ClassViewer.Show(classId)
	if not scene then
		return false
	end
	if not loadRig(classId) then
		return false
	end

	aimCamera()
	return true
end

function ClassViewer.Open(classId, dragSource)
	if scene then
		ClassViewer.Close()
	end

	openRequest += 1
	local myOpen = openRequest

	-- Só o boot leve (sala + pasta); o painel já está animando quando isto yielda. Fechar durante
	-- a espera invalida o pedido — sem isto a cena nasceria órfã com a câmera presa nela.
	if not awaitBoot() or openRequest ~= myOpen then
		return false
	end

	scene = viewerSource:Clone()

	-- O Base não tem weld com o Handle: solto no workspace, ele cairia.
	for _, descendant in ipairs(scene:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end
	scene.Parent = sceneFolder

	camPart = scene:FindFirstChild("Cam")
	basePart = scene:FindFirstChild(BASE_NAME, true)

	if not (camPart and basePart) then
		warn("[ClassViewer] Viewer_Model sem Cam ou sem " .. BASE_NAME .. ".")
		scene:Destroy()
		scene = nil
		return false
	end

	if not loadRig(classId or ClassConfig.Default().Id) then
		scene:Destroy()
		scene = nil
		return false
	end

	local camera = workspace.CurrentCamera
	if camera then
		savedType = camera.CameraType
		savedCFrame = camera.CFrame
		savedSubject = camera.CameraSubject
		savedFov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = VIEWER_FOV

		local target = focusPoint()
		local offset = camPart.Position - target
		camera.CFrame = CFrame.lookAt(target + offset * INTRO_PULLBACK, target)
		introTween = Motion.Tween(camera, INTRO_INFO, { CFrame = CFrame.lookAt(camPart.Position, target) })
	end

	local function beginDrag(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if introTween then
			introTween:Cancel()
			introTween = nil
			aimCamera()
		end

		dragging = true
		dragMoved = false
		spin = 0
		dragStartX, dragStartY = input.Position.X, input.Position.Y
		lastX = dragStartX
		lastYaw = yaw
	end

	if dragSource then
		connections[#connections + 1] = dragSource.InputBegan:Connect(beginDrag)
	end

	connections[#connections + 1] = UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		yaw += (input.Position.X - lastX) * ROTATE_SPEED
		lastX = input.Position.X
		applyYaw()

		local travelled = math.abs(input.Position.X - dragStartX) + math.abs(input.Position.Y - dragStartY)
		if travelled > DRAG_THRESHOLD then
			dragMoved = true
		end
	end)

	connections[#connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)

	-- Enquanto arrasta, mede a velocidade; solto, ela empurra o giro e decai.
	connections[#connections + 1] = RunService.RenderStepped:Connect(function(delta)
		local step = math.max(delta, 1 / 240)

		if dragging then
			local instant = math.clamp((yaw - lastYaw) / step, -MAX_SPIN, MAX_SPIN)
			spin += (instant - spin) * SPIN_SMOOTHING
			lastYaw = yaw
			return
		end

		if spin ~= 0 then
			yaw += spin * delta
			spin *= math.exp(-SPIN_DAMPING * delta)
			if math.abs(spin) < SPIN_EPSILON then
				spin = 0
			end
			applyYaw()
		end
	end)

	return true
end

-- Verdadeiro se o último gesto foi arrasto, não clique. Zera na leitura.
function ClassViewer.ConsumeDrag()
	local moved = dragMoved
	dragMoved = false
	return moved
end

function ClassViewer.Close()
	openRequest += 1
	disconnectAll()
	stopIdle()
	dragging, dragMoved = false, false
	yaw, spin, lastYaw = 0, 0, 0

	if introTween then
		introTween:Cancel()
		introTween = nil
	end

	local camera = workspace.CurrentCamera
	if camera and savedType then
		camera.CameraType = savedType
		if savedCFrame then
			camera.CFrame = savedCFrame
		end
		if savedSubject then
			camera.CameraSubject = savedSubject
		end
		if savedFov then
			camera.FieldOfView = savedFov
		end
	end
	savedType, savedCFrame, savedSubject, savedFov = nil, nil, nil, nil

	if scene then
		scene:Destroy()
	end
	scene, rig, camPart, basePart = nil, nil, nil, nil
	rigPosition = nil
end

-- Boot do loader: resolve o fundamental fora do clique e enfileira a pré-carga de todos os rigs
-- na ordem do catálogo. Clique nenhum espera replicação: no máximo promove um item da fila.
function ClassViewer.Init()
	ensureBoot()
	for _, entry in ipairs(ClassConfig.List) do
		queue[#queue + 1] = entry.Id
	end
	pumpQueue()
end

return ClassViewer
