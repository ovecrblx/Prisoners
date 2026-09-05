-- Caderno do próprio jogador: coleta na mesa, câmera diegética e virada de páginas por raycast nas
-- hitboxes. Coletar, devolver e alternar cintura/mão acontecem aqui e valem no mesmo quadro; o
-- servidor é avisado depois, só para os outros clientes desenharem. O eco do servidor não volta
-- para cá, então dois toques rápidos não brigam com a latência.
-- Coletado é estado de rodada, não de vida: o slot volta sozinho no respawn, e só o hold devolve
-- o caderno à mesa. O slot em si, o hold e a tecla são do ItemHud.
-- Toda conexão do modo em uso entra em use.links e morre no exitUse — o modo entra e sai várias
-- vezes e conexão órfã duplicaria gesto.
-- No modo em uso a câmera orbita o ponto de mira do livro com o topo no mundo: segue a posição
-- dele, nunca a rotação, então o horizonte não tomba e a vista não gira junto com a mão. Com
-- CalibrateCamera um painel mostra os quatro valores vivos e CameraDumpKey imprime.
local ManualController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Items = script.Parent.Parent:WaitForChild("Items")
local ItemHold = require(Items:WaitForChild("ItemHold"))
local ItemHud = require(Items:WaitForChild("ItemHud"))
local ItemPickup = require(Items:WaitForChild("ItemPickup"))
local ItemView = require(Items:WaitForChild("ItemView"))
local ManualView = require(script.Parent:WaitForChild("ManualView"))
local MobileHud = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("MobileHud"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local ManualConfig = require(Shared:WaitForChild("ManualConfig"))

local ITEM_ID = "Manual"
local MOVE_SPEED_THRESHOLD = 0.5 -- velocidade de Running que fecha o caderno

-- CurrentCamera é recriada no spawn: sempre resolver na hora, nunca guardar no boot.
local player = Players.LocalPlayer

local actionRemote
local pickup
local slot
local touchPanel
local touchPager

local use = { links = {}, hitboxes = {}, actions = {}, active = false, token = 0 }
local collected = false
local equipped = false
local inHand = false
local currentPage = 1
local hiddenAccessories = {}
local hiddenHeads = {}

-- Órbita viva da câmera: radianos e studs, semeada de ManualConfig e mantida entre aberturas
-- para a calibração não se perder a cada fechada.
local orbit = { yaw = 0, pitch = 0, distance = 0 }
local focus = Vector3.zero
local drag
local pinchScale
local anchor
local readout

local setHand

local function resetOrbit()
	orbit.yaw = math.rad(ManualConfig.CameraYaw)
	orbit.pitch = math.rad(ManualConfig.CameraPitch)
	orbit.distance = ManualConfig.CameraDistance
	focus = ManualConfig.CameraFocusOffset
end

local function orbitBy(deltaX, deltaY)
	local speed = math.rad(ManualConfig.CameraOrbitSpeed)
	orbit.yaw -= deltaX * speed
	orbit.pitch = math.clamp(
		orbit.pitch - deltaY * speed,
		math.rad(ManualConfig.CameraMinPitch),
		math.rad(ManualConfig.CameraMaxPitch)
	)
end

local function zoomBy(amount)
	orbit.distance = math.clamp(
		orbit.distance + amount,
		ManualConfig.CameraMinDistance,
		ManualConfig.CameraMaxDistance
	)
end

local function panBy(deltaX, deltaY)
	local handle = use.handle
	if not handle then
		return
	end
	local screen = Vector3.new(-deltaX, deltaY, 0) * ManualConfig.CameraPanSpeed
	local world = workspace.CurrentCamera.CFrame:VectorToWorldSpace(screen)
	focus += handle.CFrame:VectorToObjectSpace(world)
end

local function dumpCamera()
	warn(("[Manual] calibração da câmera\n"
		.. "ManualConfig.CameraFocusOffset = Vector3.new(%.3f, %.3f, %.3f)\n"
		.. "ManualConfig.CameraYaw = %.1f\n"
		.. "ManualConfig.CameraPitch = %.1f\n"
		.. "ManualConfig.CameraDistance = %.2f"):format(
		focus.X, focus.Y, focus.Z,
		math.deg(orbit.yaw), math.deg(orbit.pitch), orbit.distance))
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function isOrbit(input)
	return input.UserInputType == Enum.UserInputType.MouseButton2
end

local function isPan(input)
	return input.UserInputType == Enum.UserInputType.MouseButton3
end

local function dragTo(position)
	local delta = position - drag.last
	drag.last = position
	if not drag.moved and (position - drag.origin).Magnitude > ManualConfig.CameraDragThreshold then
		drag.moved = true
	end
	if drag.moved then
		orbitBy(delta.X, delta.Y)
	end
end

-- Painel de calibração, montado em código: a GUI publicada não tem lugar para ele.
local function buildReadout()
	local gui = ItemHud.Gui()
	if readout or not gui then
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = "Calibrate"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 8)
	label.Size = UDim2.fromOffset(340, 40)
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 14
	label.ZIndex = 10
	label.Parent = gui
	readout = label
end

local function clearReadout()
	if readout then
		readout:Destroy()
		readout = nil
	end
end

-- Fora do workspace de propósito: só o que desce dele é desenhado e simulado, e acessório guardado
-- não é nem um nem outro. No mundo, o Handle solto vira assembly acordada e continua na tela.
local function tempFolder()
	local home = player:FindFirstChildOfClass("PlayerScripts") or player
	local folder = home:FindFirstChild(ManualConfig.TempFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ManualConfig.TempFolderName
		folder.Parent = home
	end
	return folder
end

-- A câmera de leitura fica perto da capa e a cabeça do rig entra no enquadramento. Some só nesta
-- máquina: Transparency escrita no cliente não sobe para o servidor, e os outros continuam vendo o
-- leitor inteiro. Transparency e não LocalTransparencyModifier — essa a doc marca como Hidden.
-- Nome, e não o Head do Humanoid: o WrapTarget lá dentro também se chama Head, daí o IsA.
local function hideHeads()
	local character = player.Character
	if not character or #hiddenHeads > 0 then
		return
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == ManualConfig.HeadPartName then
			table.insert(hiddenHeads, { part = part, transparency = part.Transparency })
			part.Transparency = 1
		end
	end
end

local function restoreHeads()
	for _, entry in ipairs(hiddenHeads) do
		entry.part.Transparency = entry.transparency
	end
	table.clear(hiddenHeads)
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

-- AddAccessory e não reparent: sair do personagem destrói a junta, e é o Humanoid quem a refaz. A
-- doc não descreve o mecanismo, e neste projeto o runtime já mostrou criar AccessoryRigidConstraint
-- em R15 onde a página fala em Weld.
local function restoreAccessories()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	for _, accessory in ipairs(hiddenAccessories) do
		if character and accessory.Parent ~= nil then
			if humanoid then
				humanoid:AddAccessory(accessory)
			else
				accessory.Parent = character
			end
		end
	end
	table.clear(hiddenAccessories)
end

local function turnTo(character, index)
	currentPage = index
	ManualView.SetPage(character, index)
end

-- Setas do toque. Passo preso nas pontas, e não circular: no fim do caderno a seta não faz nada, em
-- vez de saltar para a primeira folha. Clicar na própria página continua valendo — isto é o atalho
-- de quem não tem ponteiro.
local function stepPage(delta)
	local character = player.Character
	if not (use.active and character) then
		return
	end

	local index = math.clamp(currentPage + delta, 1, #ManualConfig.PageOrder)
	if index ~= currentPage then
		turnTo(character, index)
	end
end

local function bindHitboxes(character, view)
	table.clear(use.hitboxes)
	table.clear(use.actions)
	use.handle = view.handle

	for _, page in pairs(view.pages) do
		local top = page.part:FindFirstChild("Hitbox_Top")
		if top and top:IsA("BasePart") then
			table.insert(use.hitboxes, top)
			use.actions[top] = function()
				turnTo(character, page.index)
			end
		end

		local bottom = page.part:FindFirstChild("Hitbox_Bottom")
		if bottom and bottom:IsA("BasePart") then
			table.insert(use.hitboxes, bottom)
			use.actions[bottom] = function()
				-- Verso só navega em página já virada; na ativa o clique é ruído.
				if currentPage ~= page.index then
					turnTo(character, page.index)
				end
			end
		end
	end

	local backCover = view.model:FindFirstChild(ManualConfig.BackCoverName)
	local closeBox = backCover and backCover:FindFirstChild("Hitbox_Top")
	if closeBox and closeBox:IsA("BasePart") then
		table.insert(use.hitboxes, closeBox)
		use.actions[closeBox] = function()
			setHand(false)
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

local function exitUse()
	use.token += 1
	currentPage = 1
	-- Antes da saída curta: livro fechado por outro caminho também tira os botões da tela.
	if touchPanel then
		touchPanel:Hide()
	end
	if touchPager then
		touchPager.next:Hide()
		touchPager.previous:Hide()
	end
	if not use.active then
		return
	end
	use.active = false

	ItemHold.Release(ITEM_ID)

	for _, link in ipairs(use.links) do
		link:Disconnect()
	end
	table.clear(use.links)
	table.clear(use.hitboxes)
	table.clear(use.actions)
	use.handle = nil
	drag = nil
	pinchScale = nil
	anchor = nil
	clearReadout()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default

	if use.humanoid then
		if use.humanoid.Parent then
			use.humanoid.AutoRotate = use.autoRotate
		end
		use.humanoid = nil
	end

	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	restoreAccessories()
	restoreHeads()

	local playerGui = player:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
	if mainGui then
		mainGui.Enabled = true
	end
	ItemHud.SetVisible(true)
end

local function enterUse()
	exitUse()
	local token = use.token

	local character = player.Character
	local view = character and ItemView.Get(character, ITEM_ID)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (view and root) then
		return
	end
	use.active = true

	if touchPanel then
		touchPanel:Show()
	end
	if touchPager then
		touchPager.next:Show()
		touchPager.previous:Show()
	end

	ItemHold.Claim(ITEM_ID)

	local playerGui = player:FindFirstChild("PlayerGui")
	local mainGui = playerGui and playerGui:FindFirstChild("MainGui")
	if mainGui then
		mainGui.Enabled = false
	end
	ItemHud.SetVisible(false)
	hideHeads()
	hideAccessories()
	bindHitboxes(character, view)
	if use.token ~= token then
		return
	end

	anchor = nil
	if ManualConfig.CalibrateCamera then
		buildReadout()
	end
	-- Base do yaw congelada na entrada: relativa à direção que o personagem encara, para o
	-- enquadramento não depender de para onde ele nasceu virado. Lê-la viva reabriria o laço
	-- câmera -> personagem que AutoRotate fecha.
	local baseYaw = select(2, root.CFrame:ToOrientation())
	workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable
	table.insert(use.links, RunService.PreRender:Connect(function(delta)
		local handle = use.handle
		if character.Parent == nil or root.Parent == nil or not handle or handle.Parent == nil then
			setHand(false)
			return
		end

		local target = (handle.CFrame * CFrame.new(focus)).Position
		if anchor then
			anchor = anchor:Lerp(target, 1 - math.exp(-ManualConfig.CameraSmoothing * delta))
		else
			anchor = target
		end

		local camera = workspace.CurrentCamera
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.new(anchor)
			* CFrame.Angles(0, baseYaw + orbit.yaw, 0)
			* CFrame.Angles(orbit.pitch, 0, 0)
			* CFrame.new(0, 0, orbit.distance)

		if readout then
			readout.Text = ("Yaw %.1f   Pitch %.1f   Dist %.2f\nFoco %.3f, %.3f, %.3f   [%s] copia"):format(
				math.deg(orbit.yaw), math.deg(orbit.pitch), orbit.distance,
				focus.X, focus.Y, focus.Z, ManualConfig.CameraDumpKey.Name)
		end
	end))

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Segunda trava do laço: sem AutoRotate o personagem não vira sozinho debaixo do livro.
		use.humanoid = humanoid
		use.autoRotate = humanoid.AutoRotate
		humanoid.AutoRotate = false

		table.insert(use.links, humanoid.Running:Connect(function(speed)
			if speed > MOVE_SPEED_THRESHOLD then
				setHand(false)
			end
		end))
		table.insert(use.links, humanoid.Jumping:Connect(function(active)
			if active then
				setHand(false)
			end
		end))
	end

	-- Fora da calibração a vista é a de ManualConfig e nada a move: o clique só vira página.
	if not ManualConfig.CalibrateCamera then
		table.insert(use.links, UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if isPress(input) then
				onTap()
			end
		end))
		return
	end

	-- Botão direito, botão do meio e roda ignoram gameProcessed: com a câmera em Scriptable o
	-- módulo de câmera padrão ainda marca esses como consumidos e engoliria a calibração.
	table.insert(use.links, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if isOrbit(input) or isPan(input) then
			drag = { input = input, origin = input.Position, last = input.Position, moved = true }
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			return
		end
		if gameProcessed then
			return
		end
		if input.KeyCode == ManualConfig.CameraDumpKey then
			dumpCamera()
			return
		end
		if isPress(input) then
			drag = { input = input, origin = input.Position, last = input.Position, moved = false }
		end
	end))

	table.insert(use.links, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			zoomBy(-input.Position.Z * ManualConfig.CameraZoomStep)
			return
		end
		if not drag or pinchScale then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			if input == drag.input then
				dragTo(input.Position)
			end
			return
		end
		if isPan(drag.input) then
			panBy(input.Delta.X, input.Delta.Y)
		elseif isOrbit(drag.input) then
			orbitBy(input.Delta.X, input.Delta.Y)
		else
			dragTo(input.Position)
		end
	end))

	table.insert(use.links, UserInputService.InputEnded:Connect(function(input)
		if not drag or input.UserInputType ~= drag.input.UserInputType then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and input ~= drag.input then
			return
		end
		local tapped = isPress(input) and not drag.moved
		drag = nil
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if tapped then
			onTap()
		end
	end))

	table.insert(use.links, UserInputService.TouchPinch:Connect(function(_, scale, _, state, gameProcessed)
		if gameProcessed then
			return
		end
		if state == Enum.UserInputState.Begin then
			drag = nil
			pinchScale = scale
			return
		end
		if state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			pinchScale = nil
			return
		end
		if pinchScale then
			zoomBy((pinchScale - scale) * ManualConfig.CameraPinchStep)
			pinchScale = scale
		end
	end))
end

-- Pose local primeiro, aviso ao servidor depois. Vai o valor absoluto, não um "alterna": assim
-- dois toques rápidos convergem em vez de depender da ordem em que os avisos chegam lá.
function setHand(value)
	if not equipped or inHand == value then
		return
	end
	if value and ItemHold.Seated() then
		return
	end
	inHand = value
	local character = player.Character
	if character then
		ItemView.SetPose(character, ITEM_ID, value)
	end
	if value then
		enterUse()
	else
		exitUse()
	end
	actionRemote:FireServer(ITEM_ID, "inHand", value)
end

local function release()
	exitUse()
	if slot then
		slot:Hide()
	end
end

local function equip(character)
	if not ItemView.Show(character, ITEM_ID) then
		return
	end
	if player.Character ~= character then
		ItemView.Hide(character, ITEM_ID)
		return
	end
	equipped = true
	inHand = false
	ItemView.SetPose(character, ITEM_ID, false)
	if slot then
		slot:Show()
	end
	task.spawn(ItemHold.Preload, ITEM_ID, character)
end

-- Hold no slot devolve o caderno em vez de sumir com ele: o exemplar volta a esperar na mesa, de
-- onde quem devolveu pode pegar outra vez.
local function drop()
	collected = false
	equipped = false
	inHand = false
	local character = player.Character
	release()
	if character then
		ItemView.Hide(character, ITEM_ID)
	end
	pickup:Show()
	actionRemote:FireServer(ITEM_ID, "equipped", false)
end

-- Coleta na mesa: o exemplar de lá some no mesmo quadro e o caderno nasce no personagem, sem
-- esperar resposta. O servidor é avisado depois, e é ele quem devolve o caderno no respawn.
local function collect()
	local character = player.Character
	if collected or not character then
		return
	end
	collected = true
	pickup:Hide()
	actionRemote:FireServer(ITEM_ID, "equipped", true)
	task.spawn(equip, character)
end

function ManualController.Start()
	resetOrbit()

	local remotes = ReplicatedStorage:WaitForChild(ItemConfig.RemotesFolderName)
	actionRemote = remotes:WaitForChild(ItemConfig.ActionRemote)

	slot = ItemHud.Slot(ITEM_ID, ManualConfig.IconId, ManualConfig.KeyLabel, ManualConfig.HotKey)
	if not slot then
		warn("[Manual] sem slot no HUD; o caderno fica sem coleta")
		return
	end
	slot.tapped = function()
		setHand(not inHand)
	end
	slot.held = drop

	-- Os três painéis do toque são do livro aberto: fechar e virar página. Abrir é do slot do HUD, que
	-- some com a leitura. Painel sem par — o Frame inteiro é um botão só.
	touchPanel = MobileHud.Panel(ITEM_ID, nil, function()
		setHand(false)
	end)
	touchPanel:Hide()
	touchPager = {
		next = MobileHud.Panel("Right", nil, function()
			stepPage(1)
		end),
		previous = MobileHud.Panel("Left", nil, function()
			stepPage(-1)
		end),
	}
	touchPager.next:Hide()
	touchPager.previous:Hide()

	ItemHold.Bind(ITEM_ID, ManualConfig.HoldAnimationId, function()
		setHand(false)
	end)

	pickup = ItemPickup.New(ITEM_ID, ManualConfig)
	pickup.dress = ManualView.Dress
	pickup:Bind(collect)
	pickup:Show()

	player.CharacterAdded:Connect(function(character)
		if collected then
			task.spawn(equip, character)
		end
	end)
	player.CharacterRemoving:Connect(function()
		equipped = false
		inHand = false
		release()
	end)
end

return ManualController
