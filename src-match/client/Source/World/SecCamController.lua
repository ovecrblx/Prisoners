-- Câmeras de segurança: a cabeça varre o ambiente e segue o jogador mais próximo, com o passo de um
-- servo velho — velocidade limitada, zona morta e tremor. Só visual e só neste cliente; escrita de
-- CFrame em peça do servidor não sobe. O place usa streaming, então quem registra é a chegada da
-- peça, não só a varredura da entrada.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SecCamController = {}

-- Atributo em que o brilho da lâmpada (0 a 1) é publicado, para quem espelha o ritmo dela.
SecCamController.LampAttribute = "SecCamLamp"

-- Caminho a partir do workspace e o nome que um modelo de câmera tem que ter.
local FOLDER = { "Siland_Home", "interactive" }
local MODEL_PATTERN = "^Sec_Cam_?%d*$"

-- A peça que gira: pelo nome, e pela malha dela nos modelos que não a nomearam.
local HEAD_NAME = "Head"
local HEAD_MESH = "rbxassetid://86032184172019"

-- Peças que NÃO acompanham o giro: o suporte fica preso na parede.
local STATIC_NAMES = { Base = true }

-- Curso da cabeça a partir da pose de repouso: para cada lado, na horizontal e na vertical.
local TURN_LIMIT = math.rad(75)

-- studs; fora disso a câmera não persegue ninguém e volta a varrer.
local SENSE_RADIUS = 30

-- Cone da lente: metade do ângulo para entrar, e a folga para não perder quem anda na borda. Fora
-- dele o jogador não existe para a câmera — inclusive quem está atrás dela.
local FOV_HALF = math.rad(45)
local FOV_KEEP = math.rad(8)

-- rad/s do servo. A horizontal corre mais que a vertical, como no motor de verdade.
local PAN_SPEED = math.rad(28)
local TILT_SPEED = math.rad(16)

-- rad/s de piso: sem ele o último grau levaria uma eternidade.
local MIN_SPEED = math.rad(2)

-- rad; o servo ignora erro menor que isto e só assenta abaixo de um terço dele.
local DEADZONE = math.rad(1.5)

-- rad e Hz do tremor mecânico, sempre ligado.
local JITTER = math.rad(0.12)
local JITTER_HZ = 1.7

-- Varredura ociosa: fração do curso usada, s parado em cada ponta e inclinação de descanso.
local PATROL_ARC = 0.8
local PATROL_DWELL_MIN, PATROL_DWELL_MAX = 2, 4.5
local PATROL_TILT = math.rad(-12)

-- LED: s entre rajadas varrendo e seguindo alguém, e s aceso em cada piscada.
local LED_NAME = "Led"
local BLINK_IDLE_MIN, BLINK_IDLE_MAX = 2.5, 4.5
local BLINK_BUSY_MIN, BLINK_BUSY_MAX = 0.8, 1.4
local BLINK_ON = 0.12

-- A piscada vem em rajada: quantas a rajada tem, sorteadas, e o intervalo curto entre elas.
local BLINK_BURST_MIN, BLINK_BURST_MAX = 1, 3
local BLINK_GAP = BLINK_ON * 2.2

-- 1/s com que a brasa do neon apaga depois da piscada.
local BLINK_FADE = 6

-- A lâmpada pisca em INTENSIDADE da própria cor autorada: aceso é a cor cheia, apagado é ela
-- escurecida a esta fração — nunca o quase-preto, que em Neon lê como lâmpada oca.
local LED_EMBER = 0.35

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

-- s entre buscas do alvo; o giro em si é por quadro.
local TARGET_INTERVAL = 0.2

-- studs entre a câmera do jogador e a de segurança; além disso ela não é calculada.
local ACTIVE_RADIUS = 140

local cams = {}
local watchers = {}
local driver = nil

-- Quem assiste os feeds mantém TODAS as câmeras calculando, longe do olho ou não: a vista do posto
-- fica na cabine, a milhares de studs do mapa, e o critério de distância mandaria todas dormirem.
local forced = false

function SecCamController.KeepAwake(state)
	forced = state == true
end

-- A pose de repouso da lente — o zero do patrulhamento. É daqui que quem dirige a câmera mede os
-- limites, em vez da pose solta em que o rastreio estava no instante.
function SecCamController.BasePose(model)
	local entry = cams[model]
	return entry and entry.base
end
local sinceTarget = 0

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
local function childLike(parent, name)
	local wanted = string.lower(name)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

local function findHead(model)
	local byMesh = nil
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			if item.Name == HEAD_NAME then
				return item
			elseif item:IsA("MeshPart") and item.MeshId == HEAD_MESH then
				byMesh = byMesh or item
			end
		end
	end
	return byMesh
end

-- Quem já está soldado à cabeça vem junto sozinho; escrever CFrame nele seria brigar com o solver.
local function weldedParts(model)
	local welded = {}
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("JointInstance") then
			welded[item.Part0] = true
			welded[item.Part1] = true
		end
	end
	return welded
end

-- Sem solda o modelo não é um corpo só, então o giro é aplicado peça por peça. O offset de cada uma
-- sai da POSE DE REPOUSO e é lido uma vez só: a peça que já girou não serve de referência.
local function refresh(entry)
	local welded = weldedParts(entry.model)
	local followers = {}

	for _, item in ipairs(entry.model:GetDescendants()) do
		if item:IsA("BasePart") and item ~= entry.head and not welded[item] and not STATIC_NAMES[item.Name] then
			local offset = entry.offsets[item]
			if not offset then
				offset = entry.base:Inverse() * item.CFrame
				entry.offsets[item] = offset
				item.Anchored = true
			end
			table.insert(followers, { part = item, offset = offset })
		end
	end

	entry.followers = followers

	-- A paleta sai da cor autorada da peça, e só quando a peça TROCA: capturar de novo a mesma no
	-- meio de uma piscada assaria o escurecido como se fosse o aceso.
	local led = entry.model:FindFirstChild(LED_NAME, true)
	if led ~= entry.led then
		entry.led = led
		entry.ledLit = led and led.Color
		entry.ledDim = led and led.Color:Lerp(Color3.new(0, 0, 0), 1 - LED_EMBER)
		entry.ledLevel = -1
	end

	-- Listas do movimento em lote, montadas aqui e reaproveitadas todo quadro.
	local parts = table.create(#followers + 1)
	parts[1] = entry.head
	for index, follower in ipairs(followers) do
		parts[index + 1] = follower.part
	end
	entry.parts = parts
	entry.poses = table.create(#parts)
end

local function lookOf(entry)
	local pose = entry.base * CFrame.Angles(0, entry.yaw, 0) * CFrame.Angles(entry.pitch, 0, 0)
	return pose.LookVector
end

-- O mais próximo DENTRO da lente, medido a partir de para onde a cabeça aponta agora. Quem está
-- seguido tem o cone um pouco mais largo, senão a borda ligaria e desligaria a perseguição.
local function visiblePosition(entry)
	local origin = entry.base.Position
	local look = lookOf(entry)
	local edge = math.cos(if entry.tracking then FOV_HALF + FOV_KEEP else FOV_HALF)

	local best, bestDistance = nil, SENSE_RADIUS
	for _, position in ipairs(watchers) do
		local offset = position - origin
		local distance = offset.Magnitude
		if distance > 1e-3 and distance < bestDistance and offset.Unit:Dot(look) >= edge then
			best = position
			bestDistance = distance
		end
	end
	return best
end

local function aimAngles(entry, target)
	local d = entry.base:VectorToObjectSpace(target - entry.base.Position)
	return math.clamp(math.atan2(-d.X, -d.Z), -TURN_LIMIT, TURN_LIMIT),
		math.clamp(math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z)), -TURN_LIMIT, TURN_LIMIT)
end

local function dwellSpan()
	return PATROL_DWELL_MIN + math.random() * (PATROL_DWELL_MAX - PATROL_DWELL_MIN)
end

-- Alvo fora do curso não trava a cabeça: ela vai até o batente daquele lado e para lá.
local function updateGoal(entry, now)
	local target = visiblePosition(entry)

	if target then
		if not entry.tracking then
			entry.tracking = true
			entry.blinkAt = now
		end
		entry.goalYaw, entry.goalPitch = aimAngles(entry, target)
		return
	end

	-- Perdeu o alvo: retoma a varredura pela ponta mais perto de onde a cabeça parou.
	if entry.tracking then
		entry.tracking = false
		entry.sweep = if entry.yaw >= 0 then 1 else -1
		entry.dwellUntil = now + PATROL_DWELL_MIN
	end

	entry.goalPitch = PATROL_TILT
	if now < entry.dwellUntil then
		entry.goalYaw = entry.yaw
		return
	end

	local edge = entry.sweep * TURN_LIMIT * PATROL_ARC
	if math.abs(entry.yaw - edge) < DEADZONE * 2 then
		entry.sweep = -entry.sweep
		entry.dwellUntil = now + dwellSpan()
		entry.goalYaw = entry.yaw
	else
		entry.goalYaw = edge
	end
end

-- Velocidade limitada com freio no fim, e zona morta com histerese: o motor não persegue tremor,
-- e uma vez parado só volta a andar quando o erro cresce de novo.
local function servo(current, goal, speed, delta, moving)
	local err = goal - current
	local size = math.abs(err)

	if size < DEADZONE / 3 or (not moving and size < DEADZONE) then
		return current, false
	end
	local rate = math.clamp(size * 4, MIN_SPEED, speed)
	return current + math.sign(err) * math.min(size, rate * delta), true
end

local function blinkSpan(entry)
	if entry.tracking then
		return BLINK_BUSY_MIN + math.random() * (BLINK_BUSY_MAX - BLINK_BUSY_MIN)
	end
	return BLINK_IDLE_MIN + math.random() * (BLINK_IDLE_MAX - BLINK_IDLE_MIN)
end

local function updateLed(entry, now)
	local led = entry.led
	if not led then
		return
	end

	if now >= entry.blinkAt then
		entry.litUntil = now + BLINK_ON

		-- Dentro da rajada gasta o que falta; fora dela sorteia o tamanho da próxima. A pausa longa
		-- só volta quando a rajada acaba, senão duas piscadas seguidas viravam duas rajadas.
		if entry.queued > 0 then
			entry.queued -= 1
		else
			entry.queued = math.random(BLINK_BURST_MIN, BLINK_BURST_MAX) - 1
		end
		entry.blinkAt = now + (if entry.queued > 0 then BLINK_GAP else blinkSpan(entry))
	end

	-- Neon só é reescrito quando o brilho muda: parada e apagada, a câmera não escreve nada.
	local level = if now < entry.litUntil then 1 else math.max(0, 1 - (now - entry.litUntil) * BLINK_FADE)
	if math.abs(level - entry.ledLevel) > 0.01 then
		entry.ledLevel = level
		led.Color = entry.ledDim:Lerp(entry.ledLit, level)
		-- Publica o brilho junto da cor: quem quiser o RITMO da lâmpada lê daqui em vez de tentar
		-- decodificar a cor, o que só funcionaria copiando a paleta deste módulo.
		led:SetAttribute(SecCamController.LampAttribute, level)
	end
end

-- Uma lâmpada avulsa com a cadência das câmeras: devolve o passo dela, para chamar por quadro. É o
-- que deixa outro painel piscar no mesmo ritmo sem copiar daqui a paleta nem os tempos.
function SecCamController.Lamp(part, now)
	local entry = {
		led = part,
		ledLit = part.Color,
		ledDim = part.Color:Lerp(Color3.new(0, 0, 0), 1 - LED_EMBER),
		tracking = false,
		blinkAt = now + math.random() * BLINK_IDLE_MAX,
		litUntil = 0,
		queued = 0,
		ledLevel = -1,
	}
	return function(clock)
		updateLed(entry, clock)
	end
end

-- Uma chamada de movimento por câmera em vez de uma escrita por peça, e no modo que dispara só o
-- sinal de CFrame. `jitter` desligado é o pouso exato no alvo, sem tremor.
local function applyPose(entry, now, jitter)
	local yaw, pitch = entry.yaw, entry.pitch
	if jitter then
		yaw += math.noise(now * JITTER_HZ, entry.seed) * JITTER
		pitch += math.noise(entry.seed, now * JITTER_HZ) * JITTER
	end
	local pose = entry.base * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)

	local followers = entry.followers
	if #followers == 0 then
		entry.head.CFrame = pose
		return
	end

	local poses = entry.poses
	poses[1] = pose
	for index, follower in ipairs(followers) do
		poses[index + 1] = pose * follower.offset
	end
	Workspace:BulkMoveTo(entry.parts, poses, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Uma leitura de personagem por tique, compartilhada por todas as câmeras.
local function snapshotWatchers()
	table.clear(watchers)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and (character.PrimaryPart or character:FindFirstChild("HumanoidRootPart"))
		if root then
			table.insert(watchers, root.Position)
		end
	end
end

local function step(delta)
	local now = os.clock()
	sinceTarget += delta
	local retarget = sinceTarget >= TARGET_INTERVAL
	if retarget then
		sinceTarget = 0
		snapshotWatchers()
	end

	local eye = Workspace.CurrentCamera
	local viewer = if eye then eye.CFrame.Position else nil

	for model, entry in pairs(cams) do
		-- Streaming leva o modelo embora no meio da partida, e volta com peças novas.
		if entry.head.Parent == nil or model.Parent == nil then
			cams[model] = nil
		else
			-- Longe do olho do jogador ninguém vê a cabeça mexer, então ela nem é calculada.
			if retarget then
				entry.awake = forced or viewer == nil or (entry.base.Position - viewer).Magnitude <= ACTIVE_RADIUS
				if entry.awake then
					updateGoal(entry, now)
				end
			end

			if entry.awake then
				entry.yaw, entry.movingYaw = servo(entry.yaw, entry.goalYaw, PAN_SPEED, delta, entry.movingYaw)
				entry.pitch, entry.movingPitch = servo(entry.pitch, entry.goalPitch, TILT_SPEED, delta, entry.movingPitch)

				-- Servo parado não vibra: assentada, a câmera escreve uma vez e para de escrever.
				if entry.movingYaw or entry.movingPitch or entry.tracking then
					entry.parked = false
					applyPose(entry, now, true)
				elseif not entry.parked then
					entry.parked = true
					applyPose(entry, now, false)
				end

				updateLed(entry, now)
			end
		end
	end

	if not next(cams) and driver then
		driver:Disconnect()
		driver = nil
	end
end

local function register(model)
	local entry = cams[model]
	if entry then
		refresh(entry)
		return true
	end

	local head = findHead(model)
	if not head then
		return false
	end
	head.Anchored = true

	local now = os.clock()
	entry = {
		model = model,
		head = head,
		base = head.CFrame,
		yaw = 0,
		pitch = 0,
		goalYaw = 0,
		goalPitch = PATROL_TILT,
		movingYaw = false,
		movingPitch = false,
		tracking = false,
		sweep = if math.random() < 0.5 then -1 else 1,
		dwellUntil = now + math.random() * PATROL_DWELL_MAX,
		blinkAt = now + math.random() * BLINK_IDLE_MAX,
		litUntil = 0,
		queued = 0,
		ledLevel = -1,
		awake = true,
		parked = false,
		-- Semente por câmera: duas na mesma sala não podem tremer nem piscar em sincronia.
		seed = math.random() * 500,
		offsets = {},
		followers = {},
	}
	cams[model] = entry
	refresh(entry)

	if not driver then
		driver = RunService.PostSimulation:Connect(step)
	end
	return true
end

local function scan(folder)
	for _, item in ipairs(folder:GetDescendants()) do
		if string.match(item.Name, MODEL_PATTERN) then
			register(item)
		end
	end
end

-- A peça pode chegar depois do modelo, então quem entra é rastreado até a câmera que o contém.
local function ownerOf(item, folder)
	local current = item
	while current and current ~= folder do
		if string.match(current.Name, MODEL_PATTERN) then
			return current
		end
		current = current.Parent
	end
	return nil
end

function SecCamController.Start()
	local folder = Workspace
	for _, name in ipairs(FOLDER) do
		folder = childLike(folder, name) or folder:WaitForChild(name, FOLDER_WAIT)
		if not folder then
			warn("[SecCam] workspace." .. table.concat(FOLDER, ".") .. " não encontrado.")
			return
		end
	end

	scan(folder)
	Players.PlayerAdded:Connect(function()
		scan(folder)
	end)

	folder.DescendantAdded:Connect(function(item)
		-- Streaming despeja muita coisa nesta pasta; só peça e modelo podem virar câmera.
		if not (item:IsA("BasePart") or item:IsA("Model")) then
			return
		end
		local model = ownerOf(item, folder)
		if model then
			register(model)
		end
	end)
end

return SecCamController
