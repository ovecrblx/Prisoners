-- Painel da party: MainGui.Frame_Party.Frame_Play.{Play_Button, Exit_Button}.{Button, Background}
-- Botão Play alterna entre Start, Ready, Cancel e rótulos inertes (o servidor recusaria a ação).
local PartyController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Motion = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Motion"))

local DEBOUNCE = 0.4

-- Cor do botão no estado Cancel. O resto do visual vem do Studio.
local CANCEL_STROKE = Color3.fromRGB(79, 111, 255)
local CANCEL_BG = Color3.fromRGB(49, 86, 255)

local player
local ActionEvent
local remotesFolder
local panel
local playVisual, playBackground
local exitButton, exitBackground
local playStroke, backgroundStroke
local origStrokeColor, origBackgroundColor, origBackgroundStrokeColor

local currentAction = nil
local isLeader = false
local lastClick = 0
local lastStatus = "waiting"
local lastRole = nil
local lastCount = 0

-- Escala o Background e o rótulo juntos. Sem glow: o UIStroke daqui carrega o estado
-- de Cancel em setCancelLook.
local function bindPress(background, label)
	local parts = {}

	for _, part in ipairs({ background, label }) do
		if part then
			parts[#parts + 1] = part
		end
	end

	Motion.BindButton(parts, parts)
end

local function setLabel(text)
	if playVisual:IsA("TextButton") or playVisual:IsA("TextLabel") then
		playVisual.Text = text
		return
	end

	local label = playVisual:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.Text = text
	end
end

local function setCancelLook(active)
	if playStroke then
		playStroke.Color = active and CANCEL_STROKE or origStrokeColor
	end
	if playBackground then
		playBackground.BackgroundColor3 = active and CANCEL_BG or origBackgroundColor
	end
	if backgroundStroke then
		backgroundStroke.Color = active and CANCEL_STROKE or origBackgroundStrokeColor
	end
end

local function applyState(status, role)
	isLeader = (role == "Leader")

	if status == "teleporting" then
		if isLeader or player:GetAttribute("IsReady") then
			currentAction = "Cancel"
			setLabel("Cancel")
			setCancelLook(true)
		else
			currentAction = "Ready"
			setLabel("Ready")
			setCancelLook(false)
		end
	elseif status == "recycling" then
		currentAction = nil
		setLabel("...")
		setCancelLook(false)
	else
		if isLeader then
			local minPlayers = remotesFolder:GetAttribute("MinPlayers") or 1
			if lastCount < minPlayers then
				currentAction = nil
				setLabel("Faltam " .. (minPlayers - lastCount))
			else
				currentAction = "Play"
				setLabel("Start")
			end
		else
			currentAction = nil
			setLabel("Aguardando")
		end
		setCancelLook(false)
	end
end

local function hide()
	panel.Visible = false
	currentAction = nil
	isLeader = false
	setCancelLook(false)
end

function PartyController.Init()
	player = Players.LocalPlayer

	remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	ActionEvent = remotesFolder:WaitForChild("AreaTeleportAction")
	local updateEvent = remotesFolder:WaitForChild("AreaTeleportUpdate")

	local playerGui = player:WaitForChild("PlayerGui")
	local mainGui = playerGui:WaitForChild("MainGui")
	panel = mainGui:WaitForChild("Frame_Party")

	local framePlay = panel:WaitForChild("Frame_Play")
	local playFrame = framePlay:WaitForChild("Play_Button")
	local exitFrame = framePlay:WaitForChild("Exit_Button")

	playVisual = playFrame:WaitForChild("Button")
	exitButton = exitFrame:WaitForChild("Button")
	playBackground = playFrame:FindFirstChild("Background")
	exitBackground = exitFrame:FindFirstChild("Background")

	playStroke = playVisual:FindFirstChild("UIStroke")
	if playStroke then
		origStrokeColor = playStroke.Color
	end
	if playBackground then
		origBackgroundColor = playBackground.BackgroundColor3
		backgroundStroke = playBackground:FindFirstChild("UIStroke")
		if backgroundStroke then
			origBackgroundStrokeColor = backgroundStroke.Color
		end
	end

	bindPress(playBackground, playVisual)
	bindPress(exitBackground, exitButton)

	hide()

	updateEvent.OnClientEvent:Connect(function(instruction, _padName, count, status, _timer, role)
		if instruction == "Hide" then
			hide()
			return
		end

		lastStatus = status
		lastRole = role
		lastCount = count or lastCount
		panel.Visible = true
		applyState(status, role)
	end)

	-- Atributo e RemoteEvent replicam sem ordem garantida entre si.
	player:GetAttributeChangedSignal("IsReady"):Connect(function()
		if panel.Visible and lastRole then
			applyState(lastStatus, lastRole)
		end
	end)
end

function PartyController.Start()
	local function fire(action)
		local now = os.clock()
		if now - lastClick < DEBOUNCE then
			return
		end
		lastClick = now
		ActionEvent:FireServer(action)
	end

	-- O rótulo cobre 35% da largura: sem o Background, a borda do botão não clica.
	for _, clickable in ipairs({ playVisual, playBackground }) do
		if clickable then
			clickable.Activated:Connect(function()
				if currentAction then
					fire(currentAction)
				end
			end)
		end
	end

	for _, clickable in ipairs({ exitButton, exitBackground }) do
		if clickable then
			clickable.Activated:Connect(function()
				fire("Leave")
				hide()
			end)
		end
	end
end

return PartyController
