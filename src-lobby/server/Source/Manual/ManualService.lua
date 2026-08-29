-- Autoridade do caderno: um Model preso ao personagem por um Motor6D, cuja Part0 decide cintura
-- ou mão. Sem Accessory e sem Attachment, então nada de solda do Humanoid destruindo junta nem de
-- restrição resolvendo contra o personagem — a pose inteira sai do C0, montado de ManualConfig.
-- Na mão o C0 congela depois de HandSettleTime: dali em diante o livro é rígido no espaço da
-- mão, sem reler o yaw do personagem, e nada que mexa a câmera alcança a orientação dele.
-- A capa anima aqui e replica; a animação de segurar toca no cliente dono (em personagem de
-- jogador, animação replica cliente -> servidor).
-- O cliente dono recebe UpdateManualState para câmera, páginas, animação e HUD.
local ManualService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local ManualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ManualConfig"))

local toggleModeRemote
local unequipRemote
local toggleButtonRemote
local updateStateRemote

local sessions = {}
local watched = {}
local template

local function stopVisuals(session)
	if session.coverTween then
		session.coverTween:Cancel()
		session.coverTween = nil
	end
end

local function releaseSession(player)
	local session = sessions[player]
	if not session then
		return
	end
	for _, link in ipairs(session.links) do
		link:Disconnect()
	end
	stopVisuals(session)
	if session.model then
		session.model:Destroy()
	end
	sessions[player] = nil
end

-- Pilha fechada: páginas e guarda em StackAngle, capa em zero, preservando a posição própria
-- de cada C1. A guarda é autorada invertida (geometria espelhada, SurfaceGuis com Face trocada):
-- na pilha ela fica em rotação zero, não em StackAngle.
local function stackPose(handle)
	for _, pageName in ipairs(ManualConfig.PageOrder) do
		local motor = handle:FindFirstChild(pageName .. "Motor")
		if motor and motor:IsA("Motor6D") then
			motor.C1 = CFrame.new(motor.C1.Position) * CFrame.Angles(0, 0, math.rad(ManualConfig.StackAngle))
		end
	end
	local endMotor = handle:FindFirstChild(ManualConfig.EndpaperName .. "Motor")
	if endMotor and endMotor:IsA("Motor6D") then
		endMotor.C1 = CFrame.new(endMotor.C1.Position)
	end
	local coverMotor = handle:FindFirstChild(ManualConfig.FrontCoverMotorName)
	if coverMotor and coverMotor:IsA("Motor6D") then
		coverMotor.C1 = CFrame.new(coverMotor.C1.Position)
	end
end

-- Motor6D com C1 na identidade: Handle = Part0 * C0. Na cintura o C0 é direto, porque o
-- LowerTorso acompanha o personagem. Na mão não: a animação a deixa torta, então os ângulos são
-- lidos na direção que o personagem encara e trazidos de volta para o espaço da mão.
local function poseC0(character, part0)
	if part0.Name ~= ManualConfig.HandPartName then
		local angles = ManualConfig.WaistAngles
		return CFrame.new(ManualConfig.WaistOffset)
			* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local angles = ManualConfig.HandAngles
	local facing = CFrame.Angles(0, select(2, root.CFrame:ToOrientation()), 0)
	local wanted = facing
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	local place = CFrame.new((part0.CFrame * CFrame.new(ManualConfig.HandOffset)).Position) * wanted.Rotation
	return part0.CFrame:Inverse() * place
end

local function jointOf(model)
	local handle = model:FindFirstChild("Handle")
	local joint = handle and handle:FindFirstChild(ManualConfig.JointName)
	if joint and joint:IsA("Motor6D") then
		return joint, handle
	end
	return nil, handle
end

local function applyPose(character, model)
	local joint = jointOf(model)
	if not (joint and joint.Part0) then
		return
	end
	local c0 = poseC0(character, joint.Part0)
	if c0 then
		joint.C0 = c0
	end
end

-- Só a capa: animação de segurar toca no cliente dono — em personagem de jogador a
-- replicação de animação é cliente -> servidor, nunca o contrário.
local function setVisuals(session, model)
	stopVisuals(session)

	local _, handle = jointOf(model)
	local coverMotor = handle and handle:FindFirstChild(ManualConfig.FrontCoverMotorName)
	if not coverMotor then
		return
	end

	local closed = CFrame.new(coverMotor.C1.Position)
	if session.inHand then
		coverMotor.C1 = closed
		task.delay(ManualConfig.OpenDelay, function()
			if not session.inHand or coverMotor.Parent == nil then
				return
			end
			local open = closed * CFrame.Angles(0, 0, math.rad(ManualConfig.CoverOpenAngle))
			session.coverTween = TweenService:Create(coverMotor, ManualConfig.CoverOpenTween, { C1 = open })
			session.coverTween:Play()
		end)
	else
		session.coverTween = TweenService:Create(coverMotor, ManualConfig.CoverCloseTween, { C1 = closed })
		session.coverTween:Play()
	end
end

local function equip(session, player, character)
	if not template then
		return
	end
	local waist = character:FindFirstChild(ManualConfig.WaistPartName)
	if not waist then
		warn("[Manual] " .. ManualConfig.WaistPartName .. " ausente em " .. character.Name)
		return
	end

	local model = template:Clone()
	model.Name = ManualConfig.ModelName
	local handle = model:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		model:Destroy()
		warn("[Manual] template sem Handle")
		return
	end

	local joint = Instance.new("Motor6D")
	joint.Name = ManualConfig.JointName
	joint.Part0 = waist
	joint.Part1 = handle
	joint.C1 = CFrame.identity
	joint.Parent = handle

	stackPose(handle)
	model.Parent = character

	session.model = model
	session.inHand = false
	applyPose(character, model)
	toggleButtonRemote:FireClient(player, true)
end

local function toggleMode(player)
	local session = sessions[player]
	local character = player.Character
	if not session or not session.model or not character or character.Parent == nil then
		return
	end
	if session.model.Parent ~= character then
		return
	end

	local joint = jointOf(session.model)
	if not joint then
		return
	end

	local toHand = not session.inHand
	local partName = if toHand then ManualConfig.HandPartName else ManualConfig.WaistPartName
	local part0 = character:FindFirstChild(partName)
	if not part0 or not part0:IsA("BasePart") then
		warn("[Manual] " .. partName .. " ausente em " .. character.Name)
		return
	end

	joint.Part0 = part0
	session.inHand = toHand
	session.handC0 = nil
	session.handHeld = 0
	applyPose(character, session.model)

	-- Readback da calibração, depois do C0 congelar.
	if ManualConfig.CalibrateHand and toHand then
		task.delay(ManualConfig.HandSettleTime + ManualConfig.HandPoseRate, function()
			local root = character:FindFirstChild("HumanoidRootPart")
			if not (session.inHand and root and joint.Part1) then
				return
			end
			local facing = CFrame.Angles(0, select(2, root.CFrame:ToOrientation()), 0)
			local x, y, z = (facing:Inverse() * joint.Part1.CFrame):ToOrientation()
			warn(("[Manual] HandAngles pedido (%.0f, %.0f, %.0f) -> livro em (%.1f, %.1f, %.1f)"):format(
				ManualConfig.HandAngles.X, ManualConfig.HandAngles.Y, ManualConfig.HandAngles.Z,
				math.deg(x), math.deg(y), math.deg(z)))
		end)
	end
	-- Estado antes do visual: o cliente precisa do evento mesmo se a capa falhar.
	updateStateRemote:FireClient(player, toHand)
	setVisuals(session, session.model)
end

local function unequip(player)
	local session = sessions[player]
	if not session or not session.model then
		return
	end
	session.model:Destroy()
	session.model = nil
	session.inHand = false
	stopVisuals(session)
	toggleButtonRemote:FireClient(player, false)
	updateStateRemote:FireClient(player, false)
end

local function watchCharacter(player, character)
	releaseSession(player)
	local session = { links = {}, inHand = false, handHeld = 0 }
	sessions[player] = session

	equip(session, player, character)

	-- A mão chega posada pela animação, e essa pose replica com atraso: uma aplicação só pegaria
	-- a mão ainda em repouso. Passado HandSettleTime o C0 congela — daí em diante o livro é
	-- rígido no espaço da mão e nada mais lê o yaw do personagem.
	local since = 0
	table.insert(session.links, RunService.Heartbeat:Connect(function(delta)
		if not session.inHand or not session.model or session.model.Parent ~= character then
			return
		end
		if session.handC0 then
			return
		end
		session.handHeld += delta
		since += delta
		if since < ManualConfig.HandPoseRate then
			return
		end
		since = 0
		local joint = jointOf(session.model)
		if not (joint and joint.Part0) then
			return
		end
		local c0 = poseC0(character, joint.Part0)
		if not c0 then
			return
		end
		joint.C0 = c0
		if session.handHeld >= ManualConfig.HandSettleTime then
			session.handC0 = c0
		end
	end))
end

function ManualService.Init()
	local remotesFolder = ReplicatedStorage:FindFirstChild(ManualConfig.RemotesFolderName)
	assert(remotesFolder, "[Manual] ReplicatedStorage.Remotes ausente — sincronize o lobby.project.json")

	template = ServerStorage:FindFirstChild(ManualConfig.ModelName)
	if not template then
		warn("[Manual] ServerStorage." .. ManualConfig.ModelName .. " ausente — ninguém recebe o caderno")
	end

	toggleModeRemote = remotesFolder:WaitForChild(ManualConfig.ToggleModeRemote)
	unequipRemote = remotesFolder:WaitForChild(ManualConfig.UnequipRemote)
	toggleButtonRemote = remotesFolder:WaitForChild(ManualConfig.ToggleButtonRemote)
	updateStateRemote = remotesFolder:WaitForChild(ManualConfig.UpdateStateRemote)

	toggleModeRemote.OnServerEvent:Connect(toggleMode)
	unequipRemote.OnServerEvent:Connect(unequip)

	-- PlayerAdded e o laço abaixo podem ver o mesmo jogador; `watched` impede o CharacterAdded
	-- dobrado que o rascunho original tinha.
	local function onPlayer(player)
		if watched[player] then
			return
		end
		watched[player] = true
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		player.CharacterRemoving:Connect(function()
			releaseSession(player)
		end)
		if player.Character then
			watchCharacter(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		releaseSession(player)
		watched[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return ManualService
