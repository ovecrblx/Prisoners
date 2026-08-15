-- Painel da party (cliente / Lobby) — MainGui.Frame_Party.
--
-- A party é FÍSICA: o jogador entra encostando no pad (workspace.Tp.Party_N) e fica em pé nele.
-- O cartaz do próprio pad já mostra lotação e contagem, então este painel NÃO tem lista de
-- membros, timer nem card de líder — só os dois botões.
--
-- Hierarquia esperada (a que existe no place; conferida via inspeção do Studio):
--   MainGui.Frame_Party
--     Frame_Play.Play_Button.Button   TextButton — Start / Ready / Cancel
--     Frame_Play.Play_Button.Background   ImageButton (recolore quando vira Cancel)
--     Frame_Play.Exit_Button.Button   TextButton — sair da party
--     Frame_Play.Exit_Button.Background
--
-- O painel do Code-Egg tinha um Frame_Top (Info.ViewportFrame, rótulo de status, Frame_Close)
-- que este place NÃO tem. Nada aqui depende dele.
local PartyController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DEBOUNCE = 0.4
local TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Cor do botão quando ele vira "Cancel".
local CANCEL_STROKE = Color3.fromRGB(79, 111, 255)
local CANCEL_BG = Color3.fromRGB(49, 86, 255)

local player
local ActionEvent
local panel
local playButton, playVisual, playBackground
local exitButton
local playStroke, backgroundStroke
local origStrokeColor, origBackgroundColor, origBackgroundStrokeColor

-- Estado da última mensagem do servidor. O clique lê daqui em vez de recalcular: assim o botão
-- nunca dispara uma ação diferente da que está escrita nele.
local currentAction = nil
local isLeader = false
local lastClick = 0

-- Última mensagem recebida, para reaplicar o visual quando só o IsReady mudar.
local lastStatus = "waiting"
local lastRole = nil
local lastCount = 0

local remotesFolder

local function pressAnimation(visual, clickable)
	local originalSize = visual.Size
	local shrunk = UDim2.new(
		originalSize.X.Scale * 0.9, originalSize.X.Offset * 0.9,
		originalSize.Y.Scale * 0.9, originalSize.Y.Offset * 0.9
	)

	local function reset()
		TweenService:Create(visual, TWEEN_INFO, { Size = originalSize }):Play()
	end

	clickable.MouseButton1Down:Connect(function()
		TweenService:Create(visual, TWEEN_INFO, { Size = shrunk }):Play()
	end)
	clickable.MouseButton1Up:Connect(reset)
	clickable.MouseLeave:Connect(reset)
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

-- Visual de "Cancel" (azul) vs. estado normal. As cores originais são lidas no Init, então o
-- que o Studio autorou continua sendo a fonte da verdade — nada é hardcoded exceto o azul.
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

-- Decide o que o botão diz e o que ele dispara, a partir do estado que o servidor mandou.
--
-- O servidor só aceita "Ready"/"Cancel" durante a contagem. Por isso o membro fora dela vê
-- "Aguardando" com o clique inerte, em vez de um "Ready" que não faria nada — botão que não
-- responde parece bug.
local function applyState(status, role)
	isLeader = (role == "Leader")

	if status == "teleporting" then
		-- Líder cancela a contagem inteira; membro já pronto desmarca o próprio pronto. Botão
		-- igual, ação igual ("Cancel") — quem separa os dois casos é o servidor, que sabe quem
		-- lidera. O membro ainda não pronto vê "Ready".
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
		-- Colchão pós-teleporte: o pad está fechado e a party vai ser esvaziada. Nada a fazer.
		currentAction = nil
		setLabel("...")
		setCancelLook(false)
	else
		if isLeader then
			-- MinPlayers vem como atributo do Remotes, publicado pelo servidor — o cliente não
			-- duplica o número. O servidor recusa Play abaixo do mínimo de qualquer jeito; o que
			-- se evita aqui é o clique que não faz nada, que o jogador lê como botão quebrado.
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
	playButton = playFrame
	playBackground = playFrame:FindFirstChild("Background")

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

	pressAnimation(playButton, playVisual)
	pressAnimation(exitFrame, exitButton)

	-- O Frame_Party nasce Visible=true no Studio (é assim que dá para editá-lo). Some até o
	-- jogador entrar num pad.
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

	-- IsReady é atributo do Player, e atributo replica por um canal DIFERENTE do RemoteEvent —
	-- sem ordem garantida entre os dois. Só ler o atributo dentro do handler do evento deixaria
	-- o botão com o valor velho sempre que a replicação chegasse depois. Isso aparece de verdade
	-- no auto-ready dos 3s, que o servidor aplica sem mandar evento novo por jogador.
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

	playVisual.MouseButton1Click:Connect(function()
		-- currentAction nil = estado sem ação (membro fora da contagem, ou reciclando).
		if currentAction then
			fire(currentAction)
		end
	end)

	exitButton.MouseButton1Click:Connect(function()
		fire("Leave")
		-- Esconde na hora em vez de esperar o "Hide" do servidor: o round-trip deixa o painel
		-- aberto por um instante depois do clique, e parece que o botão falhou.
		hide()
	end)
end

return PartyController
