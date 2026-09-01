-- Réplica local dos itens equipáveis, uma por personagem e por item: o dono monta a sua e monta
-- também a dos outros jogadores, a partir dos templates em ReplicatedStorage.Client. Nada disso
-- existe no servidor, então nenhuma junta, pose ou tween passa pela rede — o dono vê a resposta no
-- mesmo quadro.
-- A pose sai do C0 do Motor6D que prende o Handle ao corpo. Na mão o C0 é amostrado enquanto a
-- animação de segurar levanta o braço, e congela em HandSettleTime; dali o item é rígido no espaço
-- da mão, e quem o move é o braço. Um único PreRender amostra todos os itens de todos os
-- personagens.
-- Cada item se registra com Define: `config` traz a pose, e `dress`/`pose` são os ganchos do que só
-- aquele item sabe fazer com o próprio modelo.
local ItemView = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))
local ItemAim = require(script.Parent:WaitForChild("ItemAim"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local TEMPLATE_TIMEOUT = 10 -- segundos esperando os templates aparecerem no boot
local WAIST_TIMEOUT = 5 -- segundos esperando a parte da cintura no personagem

-- Depois da câmera: o PlayerModule liga o apagamento de primeira pessoa em RenderPriority.Camera e,
-- com a câmera colada no rosto, reescreve o quadro inteiro. Antes dele, a correção abaixo seria
-- desfeita no mesmo quadro em que é escrita.
local FIRST_PERSON_BIND = "ItemFirstPerson"
local FIRST_PERSON_PRIORITY = Enum.RenderPriority.Camera.Value + 1

-- As classes que o TransparencyController apaga, e por isso as que precisam ser trazidas de volta.
-- LocalTransparencyModifier não é só de BasePart: o feixe da lanterna é um Beam e sumiria sozinho.
local SHOWN_CLASSES = { "BasePart", "Decal", "Beam", "ParticleEmitter", "Trail" }

local player = Players.LocalPlayer

local specs = {}
local templates = {}
local views = {}
local pending = {}
local settleLink

local function poseC0(character, part0, config)
	if part0.Name ~= ItemConfig.HandPartName then
		local angles = config.WaistAngles
		return CFrame.new(config.WaistOffset)
			* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	end

	local baked = config.HandC0Angles
	if config.HandC0Offset and baked then
		return CFrame.new(config.HandC0Offset)
			* CFrame.fromOrientation(math.rad(baked.X), math.rad(baked.Y), math.rad(baked.Z))
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local angles = config.HandAngles
	local facing = CFrame.Angles(0, select(2, root.CFrame:ToOrientation()), 0)
	local wanted = facing
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	local place = CFrame.new((part0.CFrame * CFrame.new(config.HandOffset)).Position) * wanted.Rotation
	return part0.CFrame:Inverse() * place
end

local function readback(itemId, joint)
	local x, y, z = joint.C0:ToOrientation()
	warn(("[Item] pose travada da mão — %s\n"
		.. "Config.HandC0Offset = Vector3.new(%.4f, %.4f, %.4f)\n"
		.. "Config.HandC0Angles = Vector3.new(%.2f, %.2f, %.2f)"):format(
		itemId, joint.C0.Position.X, joint.C0.Position.Y, joint.C0.Position.Z,
		math.deg(x), math.deg(y), math.deg(z)))
end

local function settleView(character, view, delta)
	local part0 = view.joint.Part0
	local c0 = part0 and poseC0(character, part0, view.config)
	if not c0 then
		return
	end
	view.joint.C0 = c0
	view.held += delta
	if view.held < view.config.HandSettleTime then
		return
	end
	view.handC0 = c0
	if view.config.CalibrateHand and character == player.Character then
		readback(view.itemId, view.joint)
	end
end

local function settle(delta)
	-- Move o alvo da mira; quem gira o braço é o solver do IKControl, no passo de animação.
	ItemAim.Step(delta)

	for character, byItem in pairs(views) do
		for itemId, view in pairs(byItem) do
			if character.Parent == nil or view.model.Parent == nil then
				ItemView.Hide(character, itemId)
			else
				if view.inHand and not view.handC0 then
					settleView(character, view, delta)
				elseif view.inHand and view.config.AimChainRoot and character == player.Character then
					-- Só depois de a pose travar: a amostragem do C0 lê o CFrame da mão, e a mira
					-- movendo o braço nesses primeiros quadros congelaria a lanterna fora do lugar.
					ItemAim.Bind(character, view.config)
				end
				-- Roda em toda réplica, a do dono e a dos outros: efeito que depende do mundo em
				-- volta tem que ser refeito na máquina de quem olha, não mandado pela rede.
				local spec = specs[itemId]
				if spec.step then
					spec.step(view, delta, character)
				end
			end
		end
	end
end

local function collectShown(model)
	local shown = {}
	for _, item in ipairs(model:GetDescendants()) do
		for _, className in ipairs(SHOWN_CLASSES) do
			if item:IsA(className) then
				table.insert(shown, item)
				break
			end
		end
	end
	return shown
end

-- Em primeira pessoa o PlayerModule apaga o personagem inteiro, e o item preso a ele vai junto. Aqui
-- voltam o item que está na mão e o braço que o segura, e só eles: o resto do corpo continua sumindo.
-- Escrever 0 fora da primeira pessoa não muda nada — é o valor que o próprio controlador põe lá.
local function showInFirstPerson()
	local character = player.Character
	local byItem = character and views[character]
	if not byItem then
		return
	end

	for _, view in pairs(byItem) do
		if view.inHand then
			for _, item in ipairs(view.shown) do
				item.LocalTransparencyModifier = 0
			end
			for _, partName in ipairs(ItemConfig.HandChain) do
				local part = character:FindFirstChild(partName)
				if part and part:IsA("BasePart") then
					part.LocalTransparencyModifier = 0
				end
			end
		end
	end
end

local function build(character, itemId, waist)
	local spec = specs[itemId]
	local model = templates[itemId]:Clone()
	model.Name = itemId
	local handle = model:FindFirstChild(ItemConfig.HandleName)
	if not handle or not handle:IsA("BasePart") then
		model:Destroy()
		warn("[Item] template de " .. itemId .. " sem " .. ItemConfig.HandleName)
		return nil
	end

	-- Template de item de cenário pode vir ancorado; preso ao corpo, ancorado não acompanha.
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	local view = {
		itemId = itemId,
		config = spec.config,
		model = model,
		handle = handle,
		inHand = false,
		on = false,
		held = 0,
	}
	if spec.dress then
		spec.dress(view)
	end
	view.shown = collectShown(model)

	local joint = Instance.new("Motor6D")
	joint.Name = ItemConfig.JointName
	joint.Part0 = waist
	joint.Part1 = handle
	joint.C1 = CFrame.identity
	joint.C0 = poseC0(character, waist, spec.config)
	joint.Parent = handle

	view.joint = joint
	model.Parent = character
	return view
end

function ItemView.Define(itemId, spec)
	specs[itemId] = spec
end

function ItemView.Template(itemId)
	return templates[itemId]
end

function ItemView.Get(character, itemId)
	local byItem = views[character]
	return byItem and byItem[itemId]
end

function ItemView.Show(character, itemId)
	local existing = ItemView.Get(character, itemId)
	if existing then
		return existing
	end
	if not (templates[itemId] and specs[itemId]) then
		return nil
	end
	-- CharacterAdded chega antes das partes: esperar aqui deixa Show seguro de chamar de qualquer
	-- evento, e `pending` impede que dois avisos seguidos montem dois exemplares.
	local waiting = pending[character]
	if not waiting then
		waiting = {}
		pending[character] = waiting
	end
	if waiting[itemId] then
		repeat
			task.wait()
		until not waiting[itemId]
		return ItemView.Get(character, itemId)
	end

	waiting[itemId] = true
	local waist = character:WaitForChild(ItemConfig.WaistPartName, WAIST_TIMEOUT)
	waiting[itemId] = nil
	if next(waiting) == nil then
		pending[character] = nil
	end
	if character.Parent == nil then
		return nil
	end
	if not waist or not waist:IsA("BasePart") then
		warn("[Item] " .. ItemConfig.WaistPartName .. " ausente em " .. character.Name)
		return nil
	end

	local view = build(character, itemId, waist)
	if not view then
		return nil
	end

	local byItem = views[character]
	if not byItem then
		byItem = {}
		views[character] = byItem
	end
	byItem[itemId] = view

	if not settleLink then
		settleLink = RunService.PreRender:Connect(settle)
		RunService:BindToRenderStep(FIRST_PERSON_BIND, FIRST_PERSON_PRIORITY, showInFirstPerson)
	end
	return view
end

function ItemView.Hide(character, itemId)
	local byItem = views[character]
	local view = byItem and byItem[itemId]
	if not view then
		return
	end
	byItem[itemId] = nil
	if next(byItem) == nil then
		views[character] = nil
	end

	if view.config.AimChainRoot then
		ItemAim.Release(character)
	end

	local spec = specs[itemId]
	if spec and spec.clear then
		spec.clear(view)
	end
	view.model:Destroy()

	if next(views) == nil and settleLink then
		settleLink:Disconnect()
		settleLink = nil
		RunService:UnbindFromRenderStep(FIRST_PERSON_BIND)
	end
end

function ItemView.HideAll(character)
	local byItem = views[character]
	if not byItem then
		return
	end
	for itemId in pairs(byItem) do
		ItemView.Hide(character, itemId)
	end
end

function ItemView.SetPose(character, itemId, inHand)
	local view = ItemView.Get(character, itemId)
	if not view then
		return
	end
	local partName = if inHand then ItemConfig.HandPartName else ItemConfig.WaistPartName
	local part0 = character:FindFirstChild(partName)
	if not part0 or not part0:IsA("BasePart") then
		warn("[Item] " .. partName .. " ausente em " .. character.Name)
		return
	end

	-- Som só na virada, e nunca na primeira pose: o retrato dos outros repõe a pose a cada aviso e a
	-- cada respawn, e réplica que nasce já com o item na mão não teve gesto para soar.
	local key = if inHand then view.config.EquipSfx else view.config.StowSfx
	if key and view.posed and view.inHand ~= inHand then
		Sfx.Play(key, view.handle)
	end
	view.posed = true

	-- Guardar solta o braço na hora; sacar liga a mira só quando a pose travar, lá no settle.
	if not inHand and view.config.AimChainRoot then
		ItemAim.Release(character)
	end

	view.inHand = inHand
	view.held = 0
	view.handC0 = nil
	view.joint.Part0 = part0
	local c0 = poseC0(character, part0, view.config)
	if c0 then
		view.joint.C0 = c0
	end
	-- Com HandC0 preenchido a pose já é final: nada a amostrar, nada a acomodar.
	if inHand and view.config.HandC0Offset and view.config.HandC0Angles then
		view.handC0 = view.joint.C0
	end

	local spec = specs[itemId]
	if spec and spec.pose then
		spec.pose(view, inHand)
	end
end

-- Estado ligado/desligado de item que tem um: o gancho é do item, porque só ele sabe o que acender
-- dentro do próprio modelo. Item sem gancho ignora.
-- Só a virada chama o gancho. O retrato dos outros jogadores chega inteiro a cada aviso e a cada
-- respawn, então repintar o que já estava pintado é barato, mas tocar de novo o estalo do
-- interruptor não é.
function ItemView.SetPower(character, itemId, on)
	local view = ItemView.Get(character, itemId)
	local spec = specs[itemId]
	-- Item sem estado nasce com `on` vazio no retrato dos outros; aqui vazio é desligado.
	local wanted = on == true
	if not (view and spec and spec.power) or view.on == wanted then
		return
	end
	view.on = wanted
	spec.power(view, wanted)
end

function ItemView.Init()
	local client = ReplicatedStorage:WaitForChild("Client", TEMPLATE_TIMEOUT)
	local folder = client and client:WaitForChild(ItemConfig.TemplateFolder, TEMPLATE_TIMEOUT)
	for _, itemId in ipairs(ItemConfig.Order) do
		templates[itemId] = folder and folder:FindFirstChild(itemId)
		if not templates[itemId] then
			warn("[Item] ReplicatedStorage.Client." .. ItemConfig.TemplateFolder .. "." .. itemId
				.. " ausente — ninguém desenha esse item")
		end
	end
end

return ItemView
