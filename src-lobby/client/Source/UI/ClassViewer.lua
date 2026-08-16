-- Viewer 3D das classes. Clona ReplicatedStorage.Client.GUI.Viewer_Model no workspace,
-- assume a câmera e mostra o Rig da classe dentro da sala. Arrastar orbita a câmera.
-- O clone é client-side: instância replicada movida para o workspace morre no streaming.
local ClassViewer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local Motion = require(script.Parent:WaitForChild("Motion"))

-- Pasta do place que recebe o clone da sala.
local SCENE_PARENT = "Temp"

-- Pose do Rig dentro da sala. O HumanoidRootPart fica ancorado nela.
local RIG_CFRAME = CFrame.new(3192.137, -40.243, 13.377)

-- Órbita: graus por pixel arrastado e limite do pitch, em graus.
local ROTATE_SPEED = 0.4
local PITCH_LIMIT = 30

-- Entrada da câmera: recua este fator da distância e volta ao lugar.
local INTRO_PULLBACK = 1.25
local INTRO_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Arrasto abaixo disso ainda conta como clique.
local DRAG_THRESHOLD = 6

local scene, rig, camPart
local pivot, offset
local yaw, pitch = 0, 0
local savedType, savedCFrame, savedSubject
local dragging, dragMoved = false, false
local dragStartX, dragStartY, lastX, lastY = 0, 0, 0, 0
local introTween
local connections = {}

local function disconnectAll()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connections = {}
end

local function characterFolder()
	local client = ReplicatedStorage:WaitForChild("Client", 10)
	local models = client and client:WaitForChild("Models", 10)
	return models and models:WaitForChild("Character", 10)
end

-- O nome da pasta vem do ClassConfig; o place só entra com o modelo.
local function rigTemplate(classId)
	local entry = ClassConfig.Get(classId)
	if not entry then
		warn("[ClassViewer] Classe fora do ClassConfig: " .. tostring(classId))
		return nil
	end

	local folder = characterFolder()
	local source = folder and folder:FindFirstChild(entry.Rig)
	local template = source and source:FindFirstChild("Rig")

	if not template then
		warn("[ClassViewer] Rig não encontrado em Character." .. entry.Rig)
	end

	return template
end

local function updateOrbit()
	local camera = workspace.CurrentCamera
	if not (camera and pivot and offset) then
		return
	end

	local direction = CFrame.Angles(0, math.rad(yaw), 0) * offset
	local right = direction:Cross(Vector3.yAxis)
	if right.Magnitude > 1e-4 then
		direction = CFrame.fromAxisAngle(right.Unit, math.rad(pitch)) * direction
	end

	camera.CFrame = CFrame.lookAt(pivot + direction, pivot)
end

local function loadRig(classId)
	if rig then
		rig:Destroy()
		rig = nil
	end

	local template = rigTemplate(classId)
	if not template then
		return false
	end

	rig = template:Clone()
	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end

	rig:PivotTo(RIG_CFRAME)

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root then
		root.Anchored = true
	end

	rig.Parent = scene
	return true
end

function ClassViewer.Show(classId)
	if not scene then
		return false
	end
	if not loadRig(classId) then
		return false
	end

	pivot = rig:GetBoundingBox().Position
	offset = camPart.Position - pivot
	updateOrbit()
	return true
end

function ClassViewer.Open(classId, dragSource)
	if scene then
		ClassViewer.Close()
	end

	local client = ReplicatedStorage:WaitForChild("Client", 10)
	local guiFolder = client and client:WaitForChild("GUI", 10)
	local source = guiFolder and guiFolder:WaitForChild("Viewer_Model", 10)

	if not source then
		warn("[ClassViewer] ReplicatedStorage.Client.GUI.Viewer_Model não encontrado.")
		return false
	end

	local container = workspace:WaitForChild(SCENE_PARENT, 10)
	if not container then
		warn("[ClassViewer] workspace." .. SCENE_PARENT .. " não encontrado; usando o workspace.")
		container = workspace
	end

	scene = source:Clone()
	scene.Parent = container

	camPart = scene:FindFirstChild("Cam")
	if not camPart then
		warn("[ClassViewer] Viewer_Model sem a parte Cam.")
		scene:Destroy()
		scene = nil
		return false
	end

	if not loadRig(classId or ClassConfig.Default().Id) then
		scene:Destroy()
		scene = nil
		return false
	end

	pivot = rig:GetBoundingBox().Position
	offset = camPart.Position - pivot
	yaw, pitch = 0, 0

	local camera = workspace.CurrentCamera
	if camera then
		savedType = camera.CameraType
		savedCFrame = camera.CFrame
		savedSubject = camera.CameraSubject
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(pivot + offset * INTRO_PULLBACK, pivot)
		introTween = Motion.Tween(camera, INTRO_INFO, { CFrame = CFrame.lookAt(pivot + offset, pivot) })
	end

	local function beginDrag(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if introTween then
			introTween:Cancel()
			introTween = nil
		end
		dragging = true
		dragMoved = false
		dragStartX, dragStartY = input.Position.X, input.Position.Y
		lastX, lastY = dragStartX, dragStartY
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

		local deltaX = input.Position.X - lastX
		local deltaY = input.Position.Y - lastY
		lastX, lastY = input.Position.X, input.Position.Y

		yaw -= deltaX * ROTATE_SPEED
		pitch = math.clamp(pitch + deltaY * ROTATE_SPEED, -PITCH_LIMIT, PITCH_LIMIT)
		updateOrbit()

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

	return true
end

-- Verdadeiro se o último gesto foi arrasto, não clique. Zera na leitura.
function ClassViewer.ConsumeDrag()
	local moved = dragMoved
	dragMoved = false
	return moved
end

function ClassViewer.Close()
	disconnectAll()
	dragging, dragMoved = false, false

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
	end
	savedType, savedCFrame, savedSubject = nil, nil, nil

	if scene then
		scene:Destroy()
	end
	scene, rig, camPart = nil, nil, nil
	pivot, offset = nil, nil
	yaw, pitch = 0, 0
end

return ClassViewer
