-- Lanterna do próprio jogador: coleta no cenário, alternância cintura/mão pelo slot do HUD e a luz
-- na tecla PowerKey. Coletar, devolver, alternar e acender acontecem aqui e valem no mesmo quadro;
-- o servidor é avisado depois, só para os outros clientes desenharem. O eco do servidor não volta
-- para cá, então dois toques rápidos não brigam com a latência.
-- Coletado é estado de rodada, não de vida: o slot volta sozinho no respawn, e só o hold devolve a
-- lanterna ao cenário. A luz é da mão: acende só com a lanterna lá, guardar apaga, e toda réplica
-- nova nasce apagada.
-- ColorMap é Plugin Security e nenhum script de runtime a escreve: a troca de aparência é de
-- instância, reparentando o skin certo de Flashlight.Skins no Handle.
local FlashlightController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Items = script.Parent.Parent:WaitForChild("Items")
local ItemHold = require(Items:WaitForChild("ItemHold"))
local ItemHud = require(Items:WaitForChild("ItemHud"))
local ItemPickup = require(Items:WaitForChild("ItemPickup"))
local ItemView = require(Items:WaitForChild("ItemView"))
local UI = script.Parent.Parent:WaitForChild("UI")
local KeyHint = require(UI:WaitForChild("KeyHint"))
local MobileHud = require(UI:WaitForChild("MobileHud"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local FlashlightConfig = require(Shared:WaitForChild("FlashlightConfig"))

local ITEM_ID = "Flashlight"

local player = Players.LocalPlayer

local actionRemote
local pickup
local slot
local touchPanel

local collected = false
local equipped = false
local inHand = false
local lit = false

-- O skin em uso mora no Handle e o de reserva na pasta, então procurar só na pasta acha um só a
-- partir da primeira troca. Os dois lugares valem.
local function findSkin(model, handle, name)

	local folder = model:FindFirstChild(FlashlightConfig.SkinFolderName)
	return (folder and folder:FindFirstChild(name)) or handle:FindFirstChild(name)
end

-- Molde de cada ParticleEmitter do Handle, tirado na primeira vez que a réplica passa por aqui — e
-- essa primeira vez é sempre apagando, no dress do modelo recém-clonado, então o molde sai com o que
-- o template configurou. Guarda também em que Attachment ele morava, que é para onde a cópia volta.
-- Chave fraca no Handle: a réplica morre e leva o estoque junto.
local emitterStock = setmetatable({}, { __mode = "k" })

local function stockOf(handle)
	local stock = emitterStock[handle]
	if stock then
		return stock
	end

	stock = {}
	for _, item in ipairs(handle:GetDescendants()) do
		if item:IsA("ParticleEmitter") then
			table.insert(stock, { mold = item:Clone(), parent = item.Parent, live = item })
		end
	end
	emitterStock[handle] = stock
	return stock
end

-- Apagar destrói o emissor; acender põe de volta uma cópia do molde. Destruir é o que não deixa
-- rastro: Enabled só corta o que ia nascer, e partícula já no ar carrega o próprio Lifetime até o
-- fim. Cópia nova a cada acender, e nenhuma propriedade do emissor é escrita em runtime.
local function switchEmitters(handle, on)
	for _, entry in ipairs(stockOf(handle)) do
		local live = entry.live
		if on then
			if not (live and live.Parent) and entry.parent.Parent then
				local copy = entry.mold:Clone()
				copy.Parent = entry.parent
				entry.live = copy
			end
		elseif live then
			live:Destroy()
			entry.live = nil
		end
	end
end

-- Um só lugar decide o que "aceso" quer dizer no modelo, e vale igual para o exemplar do cenário,
-- para a réplica do dono e para a dos outros.
local function applyPower(model, handle, on)
	local spot = handle:FindFirstChildOfClass("SpotLight")
	local beam = handle:FindFirstChildOfClass("Beam")
	if spot then
		spot.Enabled = on
	end
	if beam then
		beam.Enabled = on
	end
	switchEmitters(handle, on)

	local folder = model:FindFirstChild(FlashlightConfig.SkinFolderName)
	local skinOn = findSkin(model, handle, FlashlightConfig.SkinOnName)
	local skinOff = findSkin(model, handle, FlashlightConfig.SkinOffName)
	if not (folder and skinOn and skinOff) then
		warn("[Flashlight] " .. FlashlightConfig.SkinFolderName .. " incompleta no template")
		return
	end

	-- O skin que veio aplicado no template sai na primeira troca: daqui em diante quem manda no
	-- Handle são os dois de Skins, que ficam vivos e só trocam de pai.
	local applied = handle:FindFirstChildOfClass("SurfaceAppearance")
	if applied and applied ~= skinOn and applied ~= skinOff then
		applied:Destroy()
	end

	local wanted = if on then skinOn else skinOff
	local other = if on then skinOff else skinOn
	other.Parent = folder
	wanted.Parent = handle
end

local function dressPickup(model, handle)
	applyPower(model, handle, false)
end

-- A geometria autorada do feixe, lida uma vez por réplica. As pontas saem do próprio Beam, não do
-- nome delas: quem manda no que é perto e longe é Attachment0 e Attachment1.
local function captureBeam(view)
	local beam = view.handle:FindFirstChildOfClass("Beam")
	local near = beam and beam.Attachment0
	local far = beam and beam.Attachment1
	if not (near and far) then
		warn("[Flashlight] Beam sem as duas attachments; o feixe não vai ser recortado")
		return
	end
	local span = far.Position - near.Position
	if span.Magnitude < 1e-4 then
		return
	end

	view.beam = beam
	view.beamFar = far
	view.beamOrigin = near.Position
	view.beamAxis = span.Unit
	view.beamSpan = span.Magnitude
	view.beamWidth = beam.Width1
end
-- Recorta o feixe na primeira superfície à frente, e no teto de BeamRange quando não há nenhuma.
-- Sem isto o feixe atravessa parede: Beam é desenho, não consulta o mundo sozinho.
-- A largura acompanha o corte para o cone manter o ângulo — parada em 12 studs de largura contra
-- uma parede a dois studs, a ponta viraria um disco.
-- O RaycastParams é um só, reusado: isto roda todo quadro, por réplica acesa.
local beamParams = RaycastParams.new()
beamParams.FilterType = Enum.RaycastFilterType.Exclude
beamParams.IgnoreWater = true

local function aimBeam(view, character)
	local beam = view.beam
	if not (beam and beam.Enabled) then
		return
	end

	beamParams.FilterDescendantsInstances = { character }

	local handle = view.handle
	local origin = handle.CFrame * view.beamOrigin
	local direction = handle.CFrame:VectorToWorldSpace(view.beamAxis)
	local hit = workspace:Raycast(origin, direction * FlashlightConfig.BeamRange, beamParams)
	local reach = math.min(hit and hit.Distance or FlashlightConfig.BeamRange, FlashlightConfig.BeamRange)

	view.beamFar.Position = view.beamOrigin + view.beamAxis * reach
	beam.Width1 = beam.Width0 + (view.beamWidth - beam.Width0) * (reach / view.beamSpan)
end

-- A luz é da mão, não da posse: quem chama já garantiu que a lanterna está lá.
local function setPower(value)
	if lit == value then
		return
	end
	lit = value
	KeyHint.SetOn(value)
	local character = player.Character
	if character then
		ItemView.SetPower(character, ITEM_ID, value)
	end
	if touchPanel then
		touchPanel:SetOn(value)
	end
	actionRemote:FireServer(ITEM_ID, "on", value)
end

-- Pose local primeiro, aviso ao servidor depois. Vai o valor absoluto, não um "alterna": assim
-- dois toques rápidos convergem em vez de depender da ordem em que os avisos chegam lá.
local function setHand(value)
	if not equipped or inHand == value then
		return
	end
	if value and ItemHold.Seated() then
		return
	end
	-- Guardar apaga: na cintura a lanterna não acende, e sair da mão com ela acesa deixaria o
	-- facho saindo do quadril.
	if not value then
		setPower(false)
	end
	inHand = value
	local character = player.Character
	if character then
		ItemView.SetPose(character, ITEM_ID, value)
	end
	-- O painel de toque é da mão: fora dela a luz não acende, e o botão não teria o que fazer.
	if touchPanel then
		if value then
			touchPanel:Show()
		else
			touchPanel:Hide()
		end
	end
	if value then
		KeyHint.Show(FlashlightConfig.PowerHint, FlashlightConfig.PowerKey)
		KeyHint.SetOn(lit)
		ItemHold.Claim(ITEM_ID)
	else
		KeyHint.Hide()
		ItemHold.Release(ITEM_ID)
	end
	actionRemote:FireServer(ITEM_ID, "inHand", value)
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
	lit = false
	ItemView.SetPose(character, ITEM_ID, false)
	if slot then
		slot:Show()
	end
	task.spawn(ItemHold.Preload, ITEM_ID, character)
end

-- Hold no slot devolve a lanterna em vez de sumir com ela: o exemplar volta a esperar no cenário,
-- de onde quem devolveu pode pegar outra vez.
local function drop()
	collected = false
	equipped = false
	inHand = false
	lit = false
	local character = player.Character
	ItemHold.Release(ITEM_ID)
	KeyHint.Hide()
	if slot then
		slot:Hide()
	end
	if touchPanel then
		touchPanel:Hide()
	end
	if character then
		ItemView.Hide(character, ITEM_ID)
	end
	pickup:Show()
	actionRemote:FireServer(ITEM_ID, "equipped", false)
end

-- Coleta no cenário: o exemplar de lá some no mesmo quadro e a lanterna nasce no personagem, sem
-- esperar resposta. O servidor é avisado depois, e é ele quem devolve a lanterna no respawn.
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

function FlashlightController.Init()
	ItemView.Define(ITEM_ID, {
		config = FlashlightConfig,

		dress = function(view)
			applyPower(view.model, view.handle, false)
			captureBeam(view)
		end,

		-- O gancho só roda na virada, e roda em toda réplica: o estalo sai do Handle de quem acendeu,
		-- na máquina de quem olha, sem uma mensagem a mais na rede.
		power = function(view, on)
			applyPower(view.model, view.handle, on)
			Sfx.Play(if on then FlashlightConfig.PowerOnSfx else FlashlightConfig.PowerOffSfx, view.handle)
		end,

		step = function(view, _, character)
			aimBeam(view, character)
		end,
	})
end

function FlashlightController.Start()
	local remotes = ReplicatedStorage:WaitForChild(ItemConfig.RemotesFolderName)
	actionRemote = remotes:WaitForChild(ItemConfig.ActionRemote)

	slot = ItemHud.Slot(ITEM_ID, FlashlightConfig.IconId, FlashlightConfig.KeyLabel, FlashlightConfig.HotKey)
	if not slot then
		warn("[Flashlight] sem slot no HUD; a lanterna fica sem coleta")
		return
	end
	slot.tapped = function()
		setHand(not inHand)
	end
	slot.held = drop

	-- Vai o valor absoluto que o botão pede, não um "alterna": o par On/Off já diz qual é.
	touchPanel = MobileHud.Panel(ITEM_ID, function(wanted)
		if inHand then
			setPower(wanted)
		end
	end)
	touchPanel:SetOn(lit)
	touchPanel:Hide()

	ItemHold.Bind(ITEM_ID, FlashlightConfig.HoldAnimationId, function()
		setHand(false)
	end)

	pickup = ItemPickup.New(ITEM_ID, FlashlightConfig)
	pickup.dress = dressPickup
	pickup:Bind(collect)
	pickup:Show()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not inHand then
			return
		end
		if input.KeyCode == FlashlightConfig.PowerKey then
			setPower(not lit)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		if collected then
			task.spawn(equip, character)
		end
	end)
	player.CharacterRemoving:Connect(function()
		equipped = false
		inHand = false
		lit = false
		ItemHold.Release(ITEM_ID)
		KeyHint.Hide()
		if touchPanel then
			touchPanel:SetOn(false)
			touchPanel:Hide()
		end
		if slot then
			slot:Hide()
		end
	end)
end

return FlashlightController
