-- Cliente do caderno: slot no HUD, câmera diegética e virada de páginas por raycast nas
-- hitboxes. Toda conexão entra em session.links (slot/hold/tecla) ou use.links (modo em uso)
-- e morre no release() — o modo em uso entra e sai várias vezes e conexão órfã duplicaria gesto.
-- O HUD é o template ImageButton dentro de ManualGui.Hud: Press leva a imagem do item, Key o
-- rótulo da tecla, Fill o progresso do hold. O template fica invisível; cada item é um clone.
-- ManualGui e MainGui são irmãs: o modo em uso desliga só a MainGui.
-- No modo em uso a câmera congela num CFrame tirado de ManualConfig (offset da cabeça + graus)
-- e enquadra o livro real na mão, na pose calibrada de HandAngles.
local ManualController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local MenuController = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("MenuController"))
local ManualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ManualConfig"))

-- Valores visuais do slot provisório, até a arte final.
local SLOT_LAYOUT_ORDER = 1
local KEY_LABEL = "1" -- rótulo exibido; a tecla real é ManualConfig.HotKey
local FILL_HIDDEN = UDim2.fromScale(0, 0)
local FILL_FULL = UDim2.fromScale(1, 1)

local FILL_RESET_TIME = 0.2 -- segundos para o Fill recuar em hold cancelado
local MOVE_SPEED_THRESHOLD = 0.5 -- velocidade de Running que fecha o caderno
local REPLICA_GRACE = 0.5 -- segundos tolerando a réplica do caderno sumir antes de desistir

-- CurrentCamera é recriada no spawn: sempre resolver na hora, nunca guardar no boot.
local player = Players.LocalPlayer

local toggleModeRemote
local unequipRemote
local toggleButtonRemote
local updateStateRemote

local playerGui
local gui, slot, press, fill

local session = { links = {}, holdTween = nil, holdStart = 0, bound = false }
local use = { links = {}, motors = {}, baseC1 = {}, hitboxes = {}, actions = {}, active = false, token = 0 }
local currentPage = 1
local hiddenAccessories = {}
local holdTrack
local holdTrackCharacter

local function resetHold(instant)
	if session.holdTween then
		session.holdTween:Cancel()
		session.holdTween = nil
	end
	if instant then
		fill.Size = FILL_HIDDEN
	else
		local info = TweenInfo.new(FILL_RESET_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(fill, info, { Size = FILL_HIDDEN }):Play()
	end
end

local function startHold()
	if session.holdTween then
		return
	end
	session.holdStart = os.clock()

	fill.Size = FILL_HIDDEN

	local tween = TweenService:Create(
		fill,
		TweenInfo.new(ManualConfig.HoldTime, Enum.EasingStyle.Linear),
		{ Size = FILL_FULL }
	)
	session.holdTween = tween
	tween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed then
			return
		end
		session.holdTween = nil
		-- Soltar depois do disparo não pode virar clique curto.
		session.holdStart = 0
		resetHold(true)
		unequipRemote:FireServer()
	end)
	tween:Play()
end

local function stopHold()
	if not session.holdTween then
		return
	end
	local held = os.clock() - session.holdStart
	resetHold(false)
	if session.holdStart > 0 and held < ManualConfig.HoldTime then
		toggleModeRemote:FireServer()
	end
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function bindButton()
	if session.bound then
		return
	end
	session.bound = true

	table.insert(session.links, press.InputBegan:Connect(function(input)
		if isPress(input) then
			startHold()
		end
	end))
	table.insert(session.links, press.InputEnded:Connect(function(input)
		if isPress(input) then
			stopHold()
		end
	end))
	table.insert(session.links, press.MouseLeave:Connect(stopHold))
	table.insert(session.links, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == ManualConfig.HotKey and gui.Enabled then
			toggleModeRemote:FireServer()
		end
	end))
end

local function tempFolder()
	local folder = workspace:FindFirstChild("Temp")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Temp"
		folder.Parent = workspace
	end
	return folder
end

local function hideAccessories()
	local character = player.Character
	if not character or #hiddenAccessories > 0 then
		return
	end
	local folder = tempFolder()
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") then
			table.insert(hiddenAccessories, child)
			child.Parent = folder
		end
	end
end

local function restoreAccessories()
	local character = player.Character
	for _, accessory in ipairs(hiddenAccessories) do
		if character and accessory.Parent ~= nil then
			accessory.Parent = character
		end
	end
	table.clear(hiddenAccessories)
end

local function animatePages()
	for index, pageName in ipairs(ManualConfig.PageOrder) do
		local motor = use.motors[pageName]
		local base = use.baseC1[pageName]
		if motor and base then
			local angle = if index < currentPage then 0 else ManualConfig.StackAngle
			local target = base * CFrame.Angles(0, 0, math.rad(angle))
			TweenService:Create(motor, ManualConfig.PageTween, { C1 = target }):Play()
		end
	end
end

local function buildBook(manual)
	local handle = manual:WaitForChild("Handle", 1)
	if not handle then
		warn("[Manual] Handle não replicou a tempo para o modo uso")
		return
	end

	table.clear(use.motors)
	table.clear(use.baseC1)
	table.clear(use.hitboxes)
	table.clear(use.actions)

	for index, pageName in ipairs(ManualConfig.PageOrder) do
		-- O servidor recria juntas logo após a solda; a réplica delas pode chegar depois do
		-- UpdateManualState.
		local pagePart = manual:WaitForChild(pageName, 1)
		local motor = handle:WaitForChild(pageName .. "Motor", 1)
		if pagePart and pagePart:IsA("BasePart") and motor and motor:IsA("Motor6D") then
			use.motors[pageName] = motor
			use.baseC1[pageName] = CFrame.new(motor.C1.Position)

			local top = pagePart:FindFirstChild("Hitbox_Top")
			if top and top:IsA("BasePart") then
				table.insert(use.hitboxes, top)
				use.actions[top] = function()
					currentPage = index
					animatePages()
				end
			end

			local bottom = pagePart:FindFirstChild("Hitbox_Bottom")
			if bottom and bottom:IsA("BasePart") then
				table.insert(use.hitboxes, bottom)
				use.actions[bottom] = function()
					-- Verso só navega em página já virada; na ativa o clique é ruído.
					if currentPage ~= index then
						currentPage = index
						animatePages()
					end
				end
			end
		else
			warn("[Manual] página " .. pageName .. " ou motor ausente no acessório")
		end
	end

	local backCover = manual:FindFirstChild(ManualConfig.BackCoverName)
	local closeBox = backCover and backCover:FindFirstChild("Hitbox_Top")
	if closeBox and closeBox:IsA("BasePart") then
		table.insert(use.hitboxes, closeBox)
		use.actions[closeBox] = function()
			toggleModeRemote:FireServer()
		end
	end
end

local function onTap()
	local camera = workspace.CurrentCamera
	local location = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = use.hitboxes
	local hit = workspace:Raycast(ray.Origin, ray.Direction * ManualConfig.RaycastRange, params)
	local action = hit and use.actions[hit.Instance]
	if action then
		action()
	end
end

-- Animação de segurar: toca aqui no dono — em personagem de jogador a replicação de
-- animação é cliente -> servidor, nunca o contrário.
local function ensureTrack(character)
	if holdTrack and holdTrackCharacter == character then
		return holdTrack
	end
	holdTrack = nil
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = ManualConfig.HoldAnimationId
	local ok, track = pcall(animator.LoadAnimation, animator, animation)
	if not ok then
		return nil
	end
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	holdTrackCharacter = character
	holdTrack = track
	return track
end

local function exitUse()
	use.token += 1
	if not use.active then
		return
	end
	use.active = false

	if holdTrack then
		holdTrack:Stop()
	end

	for _, link in ipairs(use.links) do
		link:Disconnect()
	end
	table.clear(use.links)
	table.clear(use.motors)
	table.clear(use.baseC1)
	table.clear(use.hitboxes)
	table.clear(use.actions)

	if use.humanoid then
		if use.humanoid.Parent then
			use.humanoid.AutoRotate = use.autoRotate
		end
		use.humanoid = nil
	end

	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	restoreAccessories()

	local mainGui = playerGui:FindFirstChild("MainGui")
	if mainGui then
		mainGui.Enabled = true
	end
end

local function enterUse()
	exitUse()
	local token = use.token

	local character = player.Character
	if not character then
		return
	end
	-- O evento pode chegar antes do modelo replicar no personagem.
	local manual = character:FindFirstChild(ManualConfig.ModelName)
		or character:WaitForChild(ManualConfig.ModelName, 2)
	if use.token ~= token then
		return
	end
	if not manual then
		warn("[Manual] modelo não replicou a tempo para o modo uso")
		return
	end
	use.active = true

	-- Calibrando, sai só a tomada de câmera e as travas de movimento; o resto do modo em uso é
	-- idêntico, sempre sobre o livro real.
	local calibrating = ManualConfig.CalibrateHand
	if not calibrating then
		MenuController.CloseAll()
		local mainGui = playerGui:FindFirstChild("MainGui")
		if mainGui then
			mainGui.Enabled = false
		end
		hideAccessories()
	end
	buildBook(manual)
	-- buildBook rende: sem este corte, um exitUse durante o yield deixaria o RenderStepped
	-- abaixo fora de use.links, sem quem desconecte.
	if use.token ~= token then
		return
	end

	local track = ensureTrack(character)
	if track then
		track:Play()
	end

	-- Um disparo só: Running repete antes da resposta do servidor, e o segundo toggle
	-- reabriria o caderno.
	local interrupted = false
	local function interrupt()
		if interrupted then
			return
		end
		interrupted = true
		toggleModeRemote:FireServer()
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		warn("[Manual] HumanoidRootPart ausente no modo uso")
		exitUse()
		return
	end

	if not calibrating then
		-- Congelado na entrada, nunca lido de novo. Seguir o yaw vivo fecharia laço: a ControlModule
		-- monta o vetor de movimento relativo à câmera e AutoRotate vira o personagem para ele, o
		-- que giraria a câmera outra vez. Girando no lugar a velocidade não passa do limiar de
		-- Running, então nada interrompia.
		local head = character:FindFirstChild("Head") or root
		local baseYaw = select(2, root.CFrame:ToOrientation())
		local offset = ManualConfig.CameraOffset
		local angles = ManualConfig.CameraAngles
		local readCamera = CFrame.new(head.Position)
			* CFrame.Angles(0, baseYaw, 0)
			* CFrame.new(offset)
			* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))

		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
		-- Se o modelo sumir, re-resolve em vez de sair no primeiro frame sem Parent; só desiste
		-- depois de REPLICA_GRACE sem ele voltar.
		local missingSince
		table.insert(use.links, RunService.RenderStepped:Connect(function()
			if character.Parent == nil or root.Parent == nil then
				exitUse()
				return
			end
			if manual.Parent == nil then
				local replacement = character:FindFirstChild(ManualConfig.ModelName)
				if replacement and replacement ~= manual then
					manual = replacement
					task.spawn(buildBook, manual)
				end
			end
			if manual.Parent == nil then
				missingSince = missingSince or os.clock()
				if os.clock() - missingSince > REPLICA_GRACE then
					exitUse()
				end
				return
			end
			missingSince = nil

			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = readCamera
		end))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and not calibrating then
		-- Segunda trava do laço: sem AutoRotate o personagem não vira sozinho debaixo do livro.
		use.humanoid = humanoid
		use.autoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false

		table.insert(use.links, humanoid.Running:Connect(function(speed)
			if speed > MOVE_SPEED_THRESHOLD then
				interrupt()
			end
		end))
		table.insert(use.links, humanoid.Jumping:Connect(function(active)
			if active then
				interrupt()
			end
		end))
	end

	table.insert(use.links, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if isPress(input) then
			onTap()
		end
	end))

	task.delay(ManualConfig.OpenDelay, function()
		if use.token == token and use.active then
			animatePages()
		end
	end)
end

local function release()
	exitUse()
	resetHold(true)
	for _, link in ipairs(session.links) do
		link:Disconnect()
	end
	table.clear(session.links)
	session.bound = false
	currentPage = 1
	gui.Enabled = false
end

local function buildSlot(hud, template)
	template.Visible = false

	slot = template:Clone()
	slot.Name = ManualConfig.ModelName
	slot.Visible = true
	slot.LayoutOrder = SLOT_LAYOUT_ORDER

	press = slot:FindFirstChild("Press")
	fill = slot:FindFirstChild("Fill")
	if not (press and press:IsA("GuiButton") and fill and fill:IsA("GuiObject")) then
		slot:Destroy()
		slot = nil
		return false
	end

	press.Image = ManualConfig.IconId
	fill.Size = FILL_HIDDEN

	local key = slot:FindFirstChild("Key")
	if key and (key:IsA("TextButton") or key:IsA("TextLabel")) then
		key.Text = KEY_LABEL
	end

	slot.Parent = hud
	return true
end

function ManualController.Start()
	playerGui = player:WaitForChild("PlayerGui")
	gui = playerGui:WaitForChild("ManualGui", 10)
	if not gui then
		warn("[Manual] ManualGui não apareceu no PlayerGui")
		return
	end

	local hud = gui:FindFirstChild("Hud")
	local template = hud and hud:FindFirstChild("ImageButton")
	if not template or not buildSlot(hud, template) then
		warn("[Manual] estrutura do ManualGui incompleta")
		return
	end

	gui.Enabled = false

	local remotes = ReplicatedStorage:WaitForChild(ManualConfig.RemotesFolderName)
	toggleModeRemote = remotes:WaitForChild(ManualConfig.ToggleModeRemote)
	unequipRemote = remotes:WaitForChild(ManualConfig.UnequipRemote)
	toggleButtonRemote = remotes:WaitForChild(ManualConfig.ToggleButtonRemote)
	updateStateRemote = remotes:WaitForChild(ManualConfig.UpdateStateRemote)

	toggleButtonRemote.OnClientEvent:Connect(function(visible)
		if visible then
			gui.Enabled = true
			bindButton()
		else
			release()
		end
	end)

	updateStateRemote.OnClientEvent:Connect(function(inHand)
		if inHand then
			enterUse()
		else
			exitUse()
		end
	end)

	-- O servidor pode ter anunciado o botão antes deste Start conectar.
	local character = player.Character
	if character and character:FindFirstChild(ManualConfig.ModelName) then
		gui.Enabled = true
		bindButton()
	end
end

return ManualController
