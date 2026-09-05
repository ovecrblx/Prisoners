-- Telefone de workspace.Siland_Home.interactive.Phone, desenhado em cada cliente. O servidor
-- publica só o UserId de quem atendeu; daqui saem o fone subindo ao rosto, a vista de quem está na
-- linha — enquadramento fixo em cima do teclado — e o cancelamento ao sair do lugar. Teclado e visor
-- são do PhoneDial, montado só para quem atendeu.
-- O fone é peça de mundo, uma só: cada cliente move a sua cópia para o rosto do dono da chamada,
-- então todos veem a mesma cena sem o servidor mexer em CFrame quadro a quadro.
-- Com streaming o Model e as peças dele vão e voltam, e voltam como instância nova: nada é resolvido
-- no boot e guardado para a partida inteira — o Model vem por evento da pasta, e o fone na hora de
-- levantar, junto com o lugar de casa dele.
local PhoneController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraConfig = require(Shared:WaitForChild("CameraConfig"))
local PhoneConfig = require(Shared:WaitForChild("PhoneConfig"))
local SeatConfig = require(Shared:WaitForChild("SeatConfig"))
local PhoneDial = require(script.Parent:WaitForChild("PhoneDial"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))
local Items = script.Parent.Parent:WaitForChild("Items")
local ItemHold = require(Items:WaitForChild("ItemHold"))
local ItemHud = require(Items:WaitForChild("ItemHud"))

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
local wide = false
local pose
local cameraMode = Enum.CameraMode.Classic
local token = 0

local ringLink
local ringing

local apply

-- O toque é de mundo: sai da base do aparelho, em laço, e todo cliente o desenha a partir do mesmo
-- atributo. Quem o cala é atender ou a janela do servidor vencer.
local function syncRing()
	local on = model:GetAttribute(PhoneConfig.RingingAttribute) == true
	if on == (ringing ~= nil) then
		return
	end

	if ringing then
		ringing:Destroy()
		ringing = nil
		return
	end

	local base = model:FindFirstChild(PhoneConfig.BaseName)
	if base and base:IsA("BasePart") then
		ringing = Sfx.Hold("PhoneRing", base)
	end
end

local function stop()
	token += 1
	wide = false

	local ran = render
	if render then
		render = false
		RunService:UnbindFromRenderStep(RENDER_BIND)
	end

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)

	pose = nil
	if handset and handset.Parent then
		if ran then
			Sfx.Play("PhoneDrop", handset)
		end
		if home then
			handset.CFrame = home
		end
	end

	if mine then
		mine = false
		ItemHud.Block("Phone", false)
		PhoneDial.Close()
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
-- São duas: em cima do teclado enquanto se digita, e recuada com o número cheio. A troca corre pelo
-- mesmo Lerp, então o recuo é o mesmo percurso, só com outro destino.
local function aim(delta)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local wanted = if wide then PhoneConfig.CallView() else PhoneConfig.View()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(wanted, 1 - math.exp(-PhoneConfig.CameraSmoothing * delta))
end

-- `loud` separa a transição de quem acabou de atender do retrato que o streaming ou a entrada tardia
-- entregam: só a primeira tem gancho sendo tirado.
local function begin(userId, loud)
	stop()
	local mark = token

	local who = Players:GetPlayerByUserId(userId)
	if not who then
		return
	end

	local character = who.Character
	if not character then
		table.insert(links, who.CharacterAdded:Connect(function()
			begin(userId, loud)
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
			-- LockFirstPerson prende o mouse no centro, e o teclado precisa do ponteiro solto. A
			-- escrita vem DEPOIS do módulo de câmera, pelo mesmo motivo que a da vista.
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			aim(delta)
		end
		local target = PhoneConfig.Pose(anchorOf(face))
		pose = (pose or part.CFrame):Lerp(target, 1 - math.exp(-PhoneConfig.HandsetSmoothing * delta))
		part.CFrame = pose
	end)

	if loud then
		Sfx.Play("PhonePick", part)
	end

	if who ~= player then
		return
	end

	mine = true
	-- Na linha o HUD sai da tela: o fone toma o rosto, o teclado toma o ponteiro, e item nenhum se
	-- usa com o aparelho na mão.
	ItemHud.Block("Phone", true)
	ItemHold.Stow()
	cameraMode = player.CameraMode
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	-- Linha que ENTROU já vem com o outro lado do jogo: não há o que discar, e o visor abre com o
	-- nome de quem ligou. Vazio é linha de saída, e aí vale o teclado.
	local origin = model:GetAttribute(PhoneConfig.CallerAttribute)
	PhoneDial.Open(model, PhoneConfig.Callers[origin], function(active)
		wide = active
	end)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Mesma lógica do posto do monitor: anda até a cadeira e senta. A vista é fixa em cima do
	-- teclado, e de pé o jogador sai dela andando sem perceber.
	local chair = SeatConfig.Find(PhoneConfig.SeatName)
	SeatConfig.Take(chair, humanoid)

	-- O caminho até a cadeira É andar, e andar é o que cancela: sem esta janela de graça a chamada
	-- se desligava no primeiro passo em direção ao assento. Sentar fecha a janela na hora; o prazo
	-- fecha para quem nunca chega lá, e a partir daí mover cancela como antes.
	local settled = false
	task.delay(PhoneConfig.SeatWait, function()
		settled = true
	end)

	table.insert(
		links,
		humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
			if humanoid.SeatPart == chair then
				settled = true
			elseif settled then
				hangUp()
			end
		end)
	)

	table.insert(links, humanoid.Running:Connect(function(speed)
		if settled and speed > PhoneConfig.CancelSpeed then
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

function apply(loud)
	local userId = model:GetAttribute(PhoneConfig.UserAttribute)
	if type(userId) == "number" and userId ~= 0 then
		begin(userId, loud)
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
	modelLink = model:GetAttributeChangedSignal(PhoneConfig.UserAttribute):Connect(function()
		apply(true)
	end)

	-- O Model velho levou o Sound do toque junto ao ser destruído; a alça sobrevivendo faria o
	-- syncRing achar que ainda está tocando e nunca mais acender.
	if ringing then
		ringing:Destroy()
		ringing = nil
	end
	if ringLink then
		ringLink:Disconnect()
	end
	ringLink = model:GetAttributeChangedSignal(PhoneConfig.RingingAttribute):Connect(syncRing)

	apply(false)
	syncRing()
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
