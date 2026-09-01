-- Teto e piso da vista em primeira pessoa. Não existe propriedade de engine para isto: o limite de
-- quase 90 graus mora no PlayerModule e não é aberto, então a trava é escrever por cima da CFrame
-- que ele acabou de pôr.
-- Depois da câmera, em RenderPriority.Camera + 1: antes dele a correção seria desfeita no mesmo
-- quadro em que é escrita.
-- Não precisa compensar entrada: o módulo de câmera tira o rumo novo da CFrame que a câmera TEM, e
-- não de um ângulo guardado, então o que sai daqui é de onde ele parte no quadro seguinte. Sem isso
-- o mouse acumularia contra a trava e a vista só voltaria depois de desfazer o excesso.
-- Vale só na câmera do jogador: em CameraType fora de Custom quem manda é o modo que assumiu a
-- câmera — o caderno aberto, a fly cam, o monitor — e este passo sai da frente.
local CameraLimit = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CameraConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CameraConfig"))

local RENDER_BIND = "CameraPitchLimit"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1
local EPSILON = 1e-4

local player = Players.LocalPlayer

-- LockFirstPerson dispensa a medida: nesse modo não há terceira pessoa para sair.
local function inFirstPerson(camera)
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end
	local character = player.Character
	local head = character and character:FindFirstChild(CameraConfig.HeadPartName)
	if not (head and head:IsA("BasePart")) then
		return false
	end
	return (camera.CFrame.Position - head.Position).Magnitude < CameraConfig.FirstPersonDistance
end

local function limit()
	local camera = workspace.CurrentCamera
	if not camera or camera.CameraType ~= Enum.CameraType.Custom or not inFirstPerson(camera) then
		return
	end

	local cframe = camera.CFrame
	local pitch, yaw, roll = cframe:ToOrientation()
	local capped = math.clamp(
		pitch,
		math.rad(CameraConfig.FirstPersonMinPitch),
		math.rad(CameraConfig.FirstPersonMaxPitch)
	)
	if math.abs(capped - pitch) < EPSILON then
		return
	end
	camera.CFrame = CFrame.new(cframe.Position) * CFrame.fromOrientation(capped, yaw, roll)
end

function CameraLimit.Start()
	RunService:BindToRenderStep(RENDER_BIND, RENDER_PRIORITY, limit)
end

return CameraLimit
