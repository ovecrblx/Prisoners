-- Estado do elevador de workspace.Siland_Home. A cabine é uma só no mundo: aqui moram o andar dela, o
-- destino e o aberto. Nenhuma peça se move por aqui — o curso é desenhado por cada cliente a partir
-- do instante publicado, então todos a veem na mesma altura sem CFrame nenhuma passando pela rede.
-- A porta não tem estado próprio: cada cliente desenha a dele no andar do próprio jogador, e `Open`
-- só vale no andar em que a cabine está.
-- Quem manda no painel é quem está DENTRO, e isso é conferido aqui: a laje do servidor nunca sai da
-- pose autorada, então a caixa da cabine é levantada pela conta.
local ElevatorService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))
local ElevatorConfig = require(Shared:WaitForChild("ElevatorConfig"))
local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))

local ANCHOR_NAME = "PromptAnchor"

local cabin
local floorPart
local homeTop
local hold = 0

local state = { floor = 1, going = 0, startedAt = 0, open = false }
local token = 0
local holdToken = 0

-- Relógio dos portões, em os.clock(). `doorAnimUntil` é quando a folha para de correr; `doorReady`
-- quando ela volta a aceitar comando de jogador; `moveReady` quando a cabine pode partir de novo.
local doorAnimUntil = 0
local doorReady = 0
local moveReady = 0

local setOpen

local function publish()
	cabin:SetAttribute(ElevatorConfig.FloorAttribute, state.floor)
	cabin:SetAttribute(ElevatorConfig.GoingAttribute, state.going)
	cabin:SetAttribute(ElevatorConfig.StartedAttribute, state.startedAt)
	cabin:SetAttribute(ElevatorConfig.OpenAttribute, state.open)
end

function setOpen(open)
	if state.open == open then
		return
	end

	state.open = open
	publish()

	local run = if open then DoorConfig.ElevatorOpenTime else DoorConfig.ElevatorCloseTime
	local now = os.clock()
	doorAnimUntil = now + run
	doorReady = now + ElevatorConfig.DoorHold(run, open)

	if not (open and hold > 0) then
		return
	end

	holdToken += 1
	local mark = holdToken

	task.delay(DoorConfig.ElevatorOpenTime + hold, function()
		if holdToken == mark and state.open and state.going == 0 then
			setOpen(false)
		end
	end)
end

-- A porta fecha ANTES do curso, e as duas coisas saem num aviso só: `StartedAt` é publicado JÁ com a
-- espera do fechamento embutida, então o cliente segura a cabine no andar de partida — `Progress`
-- grampeia o negativo em 0 — e ela sai sozinha quando a folha termina. Partir com a porta aberta
-- deixaria o vão escancarado para o poço na tela de quem ficou naquele andar.
-- `going` é marcado NA HORA do pedido, e não na partida: é isso que impede um segundo pedido de
-- trocar o destino enquanto a folha ainda fecha.
local function travel(index)
	if index == state.floor or not ElevatorConfig.Floors[index] then
		return
	end

	if not ElevatorConfig.Accepts(state, os.clock(), moveReady) then
		return
	end

	if state.open then
		setOpen(false)
	end

	local lead = math.max(0, doorAnimUntil - os.clock())
	local duration = ElevatorConfig.Travel(
		ElevatorConfig.Floors[state.floor].Lift,
		ElevatorConfig.Floors[index].Lift
	)

	state.going = index
	state.startedAt = Workspace:GetServerTimeNow() + lead
	publish()

	token += 1
	local mark = token

	task.delay(lead + duration, function()
		if token ~= mark then
			return
		end

		state.floor = index
		state.going = 0
		state.startedAt = 0
		moveReady = os.clock() + ElevatorConfig.MoveCooldown
		publish()
		setOpen(true)
	end)
end

local function pivotOf(player)
	local character = player.Character
	local base = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
	return base and base.Position or nil
end

-- Chamar de fora: com a cabine em curso não há resposta, e o visor daquele jogador já diz ocupado.
-- Parada no andar de quem chamou, a porta abre; noutro andar, a cabine vem.
local function callFrom(player)
	local position = pivotOf(player)

	if not position then
		return
	end

	local index = ElevatorConfig.FloorAt(homeTop, position.Y)

	if state.floor ~= index then
		travel(index)
	elseif ElevatorConfig.Accepts(state, os.clock(), doorReady) then
		setOpen(not state.open)
	end
end

-- O painel só obedece a quem está dentro, e quem confere é o servidor: a tecla do cliente é um
-- pedido, não uma ordem.
local function command(player, action, value)
	local position = pivotOf(player)

	if type(action) ~= "string" or not position then
		return
	end

	if not ElevatorConfig.InsideAt(floorPart, position, ElevatorConfig.Floors[state.floor].Lift) then
		return
	end

	if action == ElevatorConfig.GoAction then
		if type(value) == "number" then
			travel(value)
		end
		return
	end

	if not ElevatorConfig.Accepts(state, os.clock(), doorReady) then
		return
	end

	if action == ElevatorConfig.OpenName then
		setOpen(true)
	elseif action == ElevatorConfig.CloseName then
		setOpen(false)
	end
end

-- O prompt mora no botão `Call` da porta. A porta é desenhada por cada cliente no andar dele, e o
-- prompt acompanha a peça: um só serve os três andares.
local function buildPrompt(door, leaves)
	local call = door:FindFirstChild(DoorConfig.ElevatorCall)

	if not (call and call:IsA("BasePart")) then
		warn("[ElevatorService] " .. door:GetFullName() .. " sem o botão " .. DoorConfig.ElevatorCall .. ".")
		return
	end

	local center = Vector3.zero
	for _, leaf in ipairs(leaves) do
		center += leaf.part.Position
	end

	local mark = Instance.new("Attachment")
	mark.Name = ANCHOR_NAME
	mark.Position = DoorConfig.CallAnchor(call, center / #leaves)
	mark.Parent = call

	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = DoorConfig.ElevatorTitle
	prompt.UIOffset = DoorConfig.PromptOffset
	prompt.ClickablePrompt = DoorConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DoorConfig.PromptDistance
	prompt.Parent = mark

	prompt.Triggered:Connect(callFrom)
end

local function resolve(path, name)
	local node = Workspace

	for _, step in ipairs(path) do
		node = node:WaitForChild(step, 20)
		if not node then
			warn("[ElevatorService] workspace." .. table.concat(path, ".") .. " não encontrado.")
			return nil
		end
	end

	return if name then node:WaitForChild(name, 20) else node
end

function ElevatorService.Start()
	cabin = resolve(ElevatorConfig.Path, ElevatorConfig.ModelName)
	local rig = cabin and ElevatorConfig.Rig(cabin)

	if not rig then
		warn("[ElevatorService] cabine sem laje ou sem painel; o elevador fica parado.")
		return
	end

	floorPart = rig.floor
	homeTop = floorPart.Position.Y + floorPart.Size.Y / 2
	hold = math.max(DoorConfig.Number(cabin, "AutoClose", DoorConfig.ElevatorAutoClose), 0)
	state.floor = ElevatorConfig.Home()
	publish()

	local doors = resolve(DoorConfig.Folder)
	local found = false

	if doors then
		for _, model in ipairs(doors:GetChildren()) do
			local slide = model:IsA("Model") and DoorConfig.Kind(model) == "elevator" and DoorConfig.SlideRig(model)
			if slide and not found then
				found = true
				buildPrompt(model, slide.leaves)
			end
		end
	end

	if not found then
		warn("[ElevatorService] nenhuma porta de elevador; a cabine anda, mas ninguém a chama.")
	end

	Remotes.Event(ElevatorConfig.Remote).OnServerEvent:Connect(command)
end

return ElevatorService
