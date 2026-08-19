--!strict
-- FlyCamController (cliente / UI) — vista pelos olhos do NPC observado, com câmera livre opcional.
-- Ocupa a tela inteira: entrar no modo troca os botões da barra compartilhada em vez de abrir
-- janela. Atrás da mesma allowlist do Route Builder, pelo canal RouteBuilderQuery.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))

local Lib = script.Parent.Parent:WaitForChild("Lib")
local PanelTheme = require(Lib:WaitForChild("PanelTheme"))

local FlyCamController = {}

-- ==================================================================== TUNING
-- Distâncias, zoom e folgas em ALTURAS DE RIG (ver rigScale), nunca em studs; FOLLOW_LERP é
-- fração recuperada por quadro a 60fps (corrigida por dt em followAlpha); FREE_SPEED em studs/s;
-- FREE_SENS em radianos por pixel de mouse; PITCH_LIMIT em radianos; REACQUIRE_INTERVAL em s.
local FOLLOW_DIST = 9
local FOLLOW_HEIGHT = 3
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 2.5, 24, 1.2
local FOLLOW_LERP = 0.2
local WALL_PAD = 0.5
local FREE_SPEED, FREE_SPEED_FAST = 60, 200
local FREE_SENS = 0.0045
local PITCH_LIMIT = math.rad(85)
local REACQUIRE_INTERVAL = 2

-- Pastas de desenho que nunca empurram a câmera: marcador de diagnóstico não é mundo.
local IGNORED_FOLDERS = { NpcConfig.NODE_FOLDER_NAME, "Temp" }

local RENDER_BIND = "FlyCamRender"

local player = Players.LocalPlayer
local queryFn: RemoteFunction? = nil

local camSlot: TextButton? = nil
local backSlot: TextButton? = nil
local freeSlot: TextButton? = nil

local active = false
local free = false
local npc: Model? = nil
local npcId: string? = nil
local lastAcquire = 0

local followDist = FOLLOW_DIST
local orbitYaw, orbitPitch = 0, 0
local freePos = Vector3.zero
local freeYaw, freePitch = 0, 0
local looking = false

-- Lib/WatchedNpc publica qual NPC as ferramentas observam e pode não existir: ausente, o pedido
-- vai sem agentId e o servidor escolhe — nil é resposta válida em todo caminho abaixo.
local watchedModule: any = nil
local watchedResolved = false

local function watchedNpc(): any
	if watchedResolved then
		return watchedModule
	end
	watchedResolved = true
	local moduleScript = Lib:FindFirstChild("WatchedNpc")
	if moduleScript and moduleScript:IsA("ModuleScript") then
		local ok, result = pcall(require, moduleScript :: any)
		if ok and type(result) == "table" then
			watchedModule = result
		end
	end
	return watchedModule
end

local function watchedId(): string?
	local watcher = watchedNpc()
	if watcher == nil then
		return nil
	end
	local ok, id = pcall(function()
		return watcher.Get()
	end)
	return if ok and type(id) == "string" then id :: string else nil
end

local function acquireNpc()
	local fn = queryFn
	if fn == nil then
		return
	end
	local wanted = watchedId()
	local ok, result = pcall(function()
		return (fn :: RemoteFunction):InvokeServer({ op = "NpcModel", agentId = wanted })
	end)
	if ok and type(result) == "table" and result.ok and typeof(result.model) == "Instance" then
		local model = result.model :: Instance
		npc = if model:IsA("Model") then model :: Model else nil
		-- Quem o servidor DE FATO entregou: sem isto uma degradação passaria por atendimento.
		npcId = if type(result.agentId) == "string" then result.agentId else nil
	else
		npc = nil
		npcId = nil
	end
end

-- Studs por altura de rig; o HumanoidRootPart do R15 padrão tem 2. Medido no corpo: BodyScale
-- maior afasta a câmera na mesma proporção sozinho.
local function rigScale(): number
	local model = npc
	local hrp = model and model:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return math.max(0.25, (hrp :: BasePart).Size.Y / 2)
	end
	return 1
end

local function npcAnchor(): BasePart?
	local model = npc
	if model == nil or model.Parent == nil then
		return nil
	end
	local part = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part :: BasePart else nil
end

-- Com a câmera Scriptable o movimento fica relativo à câmera do NPC: sem esta trava, WASD
-- empurra o corpo do jogador às cegas.
local function setControlsEnabled(enabled: boolean)
	local scripts = player:FindFirstChild("PlayerScripts")
	local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
	if moduleScript == nil then
		return
	end
	local okRequire, playerModule = pcall(require, moduleScript :: any)
	if not okRequire then
		return
	end
	pcall(function()
		local controls = (playerModule :: any):GetControls()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function followAlpha(dt: number): number
	return 1 - (1 - FOLLOW_LERP) ^ (dt * 60)
end

local function wallSafeDistance(from: Vector3, dir: Vector3, want: number, scale: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if npc then
		table.insert(exclude, npc :: Instance)
	end
	if player.Character then
		table.insert(exclude, player.Character :: Instance)
	end
	for _, name in ipairs(IGNORED_FOLDERS) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true

	local hit = Workspace:Raycast(from, dir * want, params)
	if hit == nil then
		return want
	end
	return math.max(ZOOM_MIN * scale * 0.5, (hit.Position - from).Magnitude - WALL_PAD * scale)
end

local function stepFollow(camera: Camera, dt: number)
	local anchor = npcAnchor()
	if anchor == nil then
		return
	end

	local scale = rigScale()
	local head = anchor.Position
	local facing = CFrame.lookAt(head, head + anchor.CFrame.LookVector)
	local rot = facing * CFrame.fromEulerAnglesYXZ(orbitPitch, orbitYaw, 0)

	local back = rot:VectorToWorldSpace(Vector3.new(0, 0, 1))
	local up = Vector3.new(0, 1, 0)
	local pivot = head + up * (FOLLOW_HEIGHT * scale)
	local dist = wallSafeDistance(pivot, back, followDist * scale, scale)

	local goal = CFrame.lookAt(pivot + back * dist, head)
	camera.CFrame = camera.CFrame:Lerp(goal, followAlpha(dt))
end

local function stepFree(camera: Camera, dt: number)
	if looking then
		local delta = UserInputService:GetMouseDelta()
		freeYaw -= delta.X * FREE_SENS
		freePitch = math.clamp(freePitch - delta.Y * FREE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
	end

	local rot = CFrame.fromEulerAnglesYXZ(freePitch, freeYaw, 0)
	local move = Vector3.zero
	local function held(key: Enum.KeyCode): boolean
		return UserInputService:IsKeyDown(key)
	end
	if held(Enum.KeyCode.W) then
		move += Vector3.new(0, 0, -1)
	end
	if held(Enum.KeyCode.S) then
		move += Vector3.new(0, 0, 1)
	end
	if held(Enum.KeyCode.A) then
		move += Vector3.new(-1, 0, 0)
	end
	if held(Enum.KeyCode.D) then
		move += Vector3.new(1, 0, 0)
	end
	if held(Enum.KeyCode.E) then
		move += Vector3.new(0, 1, 0)
	end
	if held(Enum.KeyCode.Q) then
		move += Vector3.new(0, -1, 0)
	end

	if move.Magnitude > 0 then
		local fast = held(Enum.KeyCode.LeftShift) or held(Enum.KeyCode.RightShift)
		local speed = if fast then FREE_SPEED_FAST else FREE_SPEED
		local planar = rot:VectorToWorldSpace(Vector3.new(move.X, 0, move.Z))
		freePos += (planar + Vector3.new(0, move.Y, 0)).Unit * speed * dt
	end

	camera.CFrame = CFrame.new(freePos) * rot
end

local function onRender(dt: number)
	if not active then
		return
	end
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	-- Reafirmado todo quadro: respawn devolve a câmera pra Custom e o modo seguiria aceso mentindo.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Compara contra o id que o SERVIDOR entregou: contra o pedido, uma degradação viraria um
	-- InvokeServer por quadro.
	local wantedId = watchedId()
	if npc == nil or npc.Parent == nil or (wantedId ~= nil and wantedId ~= npcId) then
		local now = os.clock()
		if now - lastAcquire >= REACQUIRE_INTERVAL then
			lastAcquire = now
			task.spawn(acquireNpc) -- InvokeServer dá yield: nunca de dentro do laço de render
		end
	end

	if free then
		stepFree(camera, dt)
	else
		stepFollow(camera, dt)
	end
end

local hiddenSlots: { TextButton } = {}

local function setMainSlotsVisible(visible: boolean)
	if visible then
		for _, button in ipairs(hiddenSlots) do
			if button.Parent then
				button.Visible = true
			end
		end
		hiddenSlots = {}
		return
	end

	hiddenSlots = {}
	local rail = PanelTheme.Dock()
	for _, child in ipairs(rail:GetChildren()) do
		-- Slot persistente é caminho de volta de algum modo: escondê-lo deixaria a barra sem saída.
		local keep = child == backSlot or child == freeSlot or PanelTheme.IsSlotPersistent(child)
		if child:IsA("TextButton") and not keep and child.Visible then
			child.Visible = false
			table.insert(hiddenSlots, child :: TextButton)
		end
	end
end

local function setFree(on: boolean)
	free = on
	if freeSlot then
		PanelTheme.SetLauncherActive(freeSlot :: TextButton, on)
	end
	if on then
		-- Entra de onde a vista presa estava: soltar a câmera não pode ser um salto.
		local camera = Workspace.CurrentCamera
		if camera then
			freePos = camera.CFrame.Position
			local look = camera.CFrame.LookVector
			freeYaw = math.atan2(-look.X, -look.Z)
			freePitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -PITCH_LIMIT, PITCH_LIMIT)
		end
	else
		looking = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

local function exitMode()
	if not active then
		return
	end
	active = false
	free = false
	looking = false

	RunService:UnbindFromRenderStep(RENDER_BIND)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
	setControlsEnabled(true)

	if backSlot then
		(backSlot :: TextButton):Destroy()
		backSlot = nil
	end
	if freeSlot then
		(freeSlot :: TextButton):Destroy()
		freeSlot = nil
	end
	setMainSlotsVisible(true)
	if camSlot then
		PanelTheme.SetLauncherActive(camSlot :: TextButton, false)
	end
end

local function enterMode()
	if active then
		return
	end
	active = true
	orbitYaw, orbitPitch = 0, 0
	followDist = FOLLOW_DIST
	lastAcquire = 0

	-- Ordem 10/11: UIListLayout ignora filho invisível, então estes dois sobem sozinhos ao topo.
	backSlot = PanelTheme.LauncherSlot("FlyCamBack", "◀️", 10)
	freeSlot = PanelTheme.LauncherSlot("FlyCamFree", "📷", 11)
	PanelTheme.SetSlotPersistent(backSlot :: TextButton)
	PanelTheme.SetSlotPersistent(freeSlot :: TextButton);
	(backSlot :: TextButton).Activated:Connect(exitMode);
	(freeSlot :: TextButton).Activated:Connect(function()
		setFree(not free)
	end)
	setMainSlotsVisible(false)
	if camSlot then
		PanelTheme.SetLauncherActive(camSlot :: TextButton, true)
	end

	setControlsEnabled(false)
	setFree(false)
	task.spawn(acquireNpc)

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	RunService:BindToRenderStep(RENDER_BIND, Enum.RenderPriority.Camera.Value, onRender)
end

local function wireInput()
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not active or gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			looking = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and looking and not free then
			orbitYaw -= input.Delta.X * FREE_SENS
			orbitPitch = math.clamp(orbitPitch - input.Delta.Y * FREE_SENS, -PITCH_LIMIT, PITCH_LIMIT)
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and not free and not gameProcessed then
			followDist = math.clamp(followDist - input.Position.Z * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		end
	end)
end

function FlyCamController.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	local query = remotes and remotes:FindFirstChild("RouteBuilderQuery")
	if query == nil or not query:IsA("RemoteFunction") then
		return
	end

	local ok, result = pcall(function()
		return (query :: RemoteFunction):InvokeServer({ op = "IsAuthorized" })
	end)
	if not (ok and type(result) == "table" and result.ok and result.authorized) then
		return -- sem autorização, nenhum botão nasce
	end
	queryFn = query :: RemoteFunction

	camSlot = PanelTheme.LauncherSlot("FlyCamLauncher", "💻", 3);
	(camSlot :: TextButton).Activated:Connect(function()
		if active then
			exitMode()
		else
			enterMode()
		end
	end)

	wireInput()

	-- Trocar de sujeito é gesto do autor: zera a espera que o laço de render usa como backstop.
	local watcher = watchedNpc()
	if watcher ~= nil then
		pcall(function()
			watcher.Changed:Connect(function()
				if not active then
					return
				end
				lastAcquire = os.clock()
				task.spawn(acquireNpc)
			end)
		end)
	end

	-- Sem isto o respawn devolveria o jogador a um corpo sem controles e com a barra escondida.
	player.CharacterAdded:Connect(function()
		if active then
			exitMode()
		end
	end)
end

return FlyCamController
