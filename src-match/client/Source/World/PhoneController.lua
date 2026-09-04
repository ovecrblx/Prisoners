-- Telefone de workspace.Siland_Home.interactive.Phone, desenhado em cada cliente. O servidor
-- publica só o UserId de quem atendeu; daqui saem o fone subindo ao rosto, a vista de quem está na
-- linha — enquadramento fixo em cima do teclado — e o cancelamento ao sair do lugar.
-- O fone é peça de mundo, uma só: cada cliente move a sua cópia para o rosto do dono da chamada,
-- então todos veem a mesma cena sem o servidor mexer em CFrame quadro a quadro.
-- Com streaming o Model e as peças dele vão e voltam, e voltam como instância nova: nada é resolvido
-- no boot e guardado para a partida inteira — o Model vem por evento da pasta, e o fone na hora de
-- levantar, junto com o lugar de casa dele.
local PhoneController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CameraConfig"))
local PhoneConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PhoneConfig"))

-- Depois da câmera, em RenderPriority.Camera + 2: o módulo de câmera escreve a CFrame em Camera e o
-- CameraLimit em Camera + 1, e lida antes deles ela ainda é a do quadro passado — o fone nadaria um
-- quadro atrás da vista.
local RENDER_BIND = "PhoneHandset"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 2

local player = Players.LocalPlayer

local model
local modelLink
local handset
local home
local hangUpRemote

local links = {}
local render
local mine = false
local pose
local cameraMode = Enum.CameraMode.Classic
local token = 0

local apply

local function stop()
	token += 1

	if render then
		render = false
		RunService:UnbindFromRenderStep(RENDER_BIND)
	end

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)

	pose = nil
	if handset and handset.Parent and home then
		handset.CFrame = home
	end

	if mine then
		mine = false
		player.CameraMode = cameraMode

		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end
end

local function hangUp()
	stop()
	if hangUpRemote then
		hangUpRemote:FireServer()
	end
end

local function resolveHandset()
	local part = model:FindFirstChild(PhoneConfig.HandsetName)
		or model:WaitForChild(PhoneConfig.HandsetName, PhoneConfig.ModelWait)
	if not (part and part:IsA("BasePart")) then
		return nil
	end

	if part ~= handset then
		handset = part
		home = part.CFrame
	end

	return part
end

-- Quem atende vê pela câmera, e é nela que o fone fica preso: seguir a cabeça deixaria o aparelho
-- parado quando a vista sobe ou desce, porque a cabeça do personagem só acompanha o giro horizontal.
-- Para quem assiste não existe a câmera do outro, e aí vale a cabeça dele. A folga de primeira
-- pessoa cobre os quadros em que o zoom ainda está chegando ao rosto.
local function anchorOf(face)
	if mine then
		local camera = Workspace.CurrentCamera
		if camera and (camera.CFrame.Position - face.Position).Magnitude < CameraConfig.FirstPersonDistance then
			return camera.CFrame
		end
	end
	return face.CFrame
end

-- Vista de quem atende, chegando ao enquadramento por percurso e não por corte. Em Scriptable o
-- módulo de câmera larga o volante, e o CameraLimit também — ele só aperta Custom.
local function aim(delta)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(PhoneConfig.View(), 1 - math.exp(-PhoneConfig.CameraSmoothing * delta))
end

local function begin(userId)
	stop()
	local mark = token

	local who = Players:GetPlayerByUserId(userId)
	if not who then
		return
	end

	local character = who.Character
	if not character then
		table.insert(links, who.CharacterAdded:Connect(function()
			begin(userId)
		end))
		return
	end

	local face = character:WaitForChild(PhoneConfig.FacePartName, PhoneConfig.ModelWait)
	local part = face and resolveHandset()
	if not (part and face:IsA("BasePart")) or token ~= mark then
		return
	end

	render = true
	RunService:BindToRenderStep(RENDER_BIND, RENDER_PRIORITY, function(delta)
		if not (face.Parent and part.Parent) then
			if mine then
				hangUp()
			else
				stop()
			end
			return
		end
		if mine then
			aim(delta)
		end
		local target = PhoneConfig.Pose(anchorOf(face))
		pose = (pose or part.CFrame):Lerp(target, 1 - math.exp(-PhoneConfig.HandsetSmoothing * delta))
		part.CFrame = pose
	end)

	if who ~= player then
		return
	end

	mine = true
	cameraMode = player.CameraMode
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	table.insert(links, humanoid.Running:Connect(function(speed)
		if speed > PhoneConfig.CancelSpeed then
			hangUp()
		end
	end))
	table.insert(links, humanoid.Jumping:Connect(function(active)
		if active then
			hangUp()
		end
	end))
	table.insert(links, humanoid.Died:Connect(hangUp))
end

function apply()
	local userId = model:GetAttribute(PhoneConfig.UserAttribute)
	if type(userId) == "number" and userId ~= 0 then
		begin(userId)
	else
		stop()
	end
end

local function bind(target)
	if model == target then
		return
	end

	stop()
	if modelLink then
		modelLink:Disconnect()
	end

	model = target
	handset = nil
	home = nil
	modelLink = model:GetAttributeChangedSignal(PhoneConfig.UserAttribute):Connect(apply)
	apply()
end

function PhoneController.Start()
	local folder = PhoneConfig.Folder(PhoneConfig.ModelWait)
	if not folder then
		warn("[Phone] workspace." .. table.concat(PhoneConfig.Path, ".") .. " não encontrado.")
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", PhoneConfig.ModelWait)
	hangUpRemote = remotes and remotes:WaitForChild(PhoneConfig.HangUpRemote, PhoneConfig.ModelWait)
	if not hangUpRemote then
		warn("[Phone] remote " .. PhoneConfig.HangUpRemote .. " não apareceu; desligar não sai do cliente.")
	end

	local wanted = string.lower(PhoneConfig.ModelName)
	folder.ChildAdded:Connect(function(child)
		if string.lower(child.Name) == wanted then
			bind(child)
		end
	end)

	for _, child in ipairs(folder:GetChildren()) do
		if string.lower(child.Name) == wanted then
			bind(child)
			break
		end
	end
end

return PhoneController
