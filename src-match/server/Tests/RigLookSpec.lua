-- RigLookSpec — o corpo é um só, a classe é a roupa. O que precisa estar completo para que ninguém
-- nasça parecendo outra pessoa.
--
-- O QUE ESTA SPEC PROTEGE. Antes existiam oito Models em ReplicatedStorage.Client — quatro em `Npc`,
-- quatro em `Character` — e MEDIDO no place eles eram idênticos: mesma malha, mesma textura, mesma
-- cor, mesmo Humanoid (WalkSpeed 16, HipHeight 1.937, R15) e o mesmo catálogo de 27 animações. A
-- única diferença entre as oito árvores eram DOIS rbxassetid (Shirt e Pants) e um acessório em
-- guard_class. Agora há um rig só, em ServerStorage.Rigs.Base, e ele é o corpo do CITIZEN.
--
-- A ARMADILHA QUE ISSO CRIA. Classe sem Shirt ou sem Pants não quebra nada: ela nasce com a roupa
-- que veio na Base, que é a de civil. Um Guard vestido de civil não gera erro, não some do jogo e
-- não aparece no console — só está errado. Por isso a falta de roupa é testada, e não presumida.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")

	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local ClassConfig = t:freshRequire(Shared:WaitForChild("ClassConfig"))
	local NpcConfig = t:freshRequire(Shared:WaitForChild("NpcConfig"))
	local RigLibrary = t:freshRequire(
		ServerScriptService:WaitForChild("Source"):WaitForChild("Character"):WaitForChild("RigLibrary")
	)

	-- MEDIDO no place, em ReplicatedStorage.Client.Npc.Citizen, o Model que virou a Base.
	local BASE_SHIRT = "rbxassetid://10490258776"
	local BASE_PANTS = "rbxassetid://10490263290"

	local function fakeRig()
		local model = Instance.new("Model")
		model.Name = "Base"

		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = model

		local shirt = Instance.new("Shirt")
		shirt.Name = "Clothing"
		shirt.ShirtTemplate = BASE_SHIRT
		shirt.Parent = model

		local pants = Instance.new("Pants")
		pants.Name = "Clothing"
		pants.PantsTemplate = BASE_PANTS
		pants.Parent = model

		return model, shirt, pants
	end

	t:test("toda classe jogável veste, senão nasce de civil sem um aviso sequer", function()
		for _, entry in ipairs(ClassConfig.List) do
			t:assert(type(entry.Shirt) == "string" and entry.Shirt ~= "", entry.Id .. " sem Shirt: nasce de civil")
			t:assert(type(entry.Pants) == "string" and entry.Pants ~= "", entry.Id .. " sem Pants: nasce de civil")
			t:assert(entry.Shirt ~= BASE_SHIRT, entry.Id .. " usa a camisa da Base, que é a do Citizen")
			t:assert(entry.Pants ~= BASE_PANTS, entry.Id .. " usa a calça da Base, que é a do Citizen")
		end
	end)

	t:test("toda classe de NPC tem look, e o Citizen é quem herda a roupa da Base", function()
		for _, class in ipairs(NpcConfig.Classes) do
			local look = NpcConfig.LOOKS[class]
			t:assert(look ~= nil, class .. " está em NpcConfig.Classes e não em LOOKS: nasce de civil")
			t:assert(type(look.Shirt) == "string" and look.Shirt ~= "", class .. " sem Shirt")
			t:assert(type(look.Pants) == "string" and look.Pants ~= "", class .. " sem Pants")
		end

		-- O Citizen É a Base. Se um dia divergir, a Base foi trocada e o resto do arquivo mente.
		t:assertEqual(NpcConfig.LOOKS.Citizen.Shirt, BASE_SHIRT, "a Base deixou de ser o corpo do Citizen")
		t:assertEqual(NpcConfig.LOOKS.Citizen.Pants, BASE_PANTS, "a Base deixou de ser o corpo do Citizen")
	end)

	t:test("duas classes não podem vestir a mesma roupa: ficariam indistinguíveis em jogo", function()
		local seen = {}
		local function claim(key, owner)
			t:assert(seen[key] == nil, owner .. " veste igual a " .. tostring(seen[key]))
			seen[key] = owner
		end

		for _, entry in ipairs(ClassConfig.List) do
			claim(entry.Shirt .. "|" .. entry.Pants, entry.Id)
		end

		local npcSeen = {}
		for _, class in ipairs(NpcConfig.Classes) do
			local look = NpcConfig.LOOKS[class]
			local key = look.Shirt .. "|" .. look.Pants
			t:assert(npcSeen[key] == nil, class .. " veste igual a " .. tostring(npcSeen[key]))
			npcSeen[key] = class
		end
	end)

	t:test("rbxassetid e não o número cru: id solto não carrega e a peça fica lisa", function()
		local function wellFormed(id)
			return type(id) == "string" and id:sub(1, 13) == "rbxassetid://" and tonumber(id:sub(14)) ~= nil
		end

		for _, entry in ipairs(ClassConfig.List) do
			t:assert(wellFormed(entry.Shirt), entry.Id .. " Shirt fora do formato rbxassetid://<id>")
			t:assert(wellFormed(entry.Pants), entry.Id .. " Pants fora do formato rbxassetid://<id>")
		end
		for _, class in ipairs(NpcConfig.Classes) do
			t:assert(wellFormed(NpcConfig.LOOKS[class].Shirt), class .. " Shirt fora do formato")
			t:assert(wellFormed(NpcConfig.LOOKS[class].Pants), class .. " Pants fora do formato")
		end
	end)

	t:test("Dress escreve nas duas peças do clone e não na Base", function()
		local rig, shirt, pants = fakeRig()
		local look = { Shirt = "rbxassetid://1", Pants = "rbxassetid://2" }
		RigLibrary.Dress(rig, "guard_class", look)

		t:assertEqual(shirt.ShirtTemplate, "rbxassetid://1", "a camisa do clone não mudou")
		t:assertEqual(pants.PantsTemplate, "rbxassetid://2", "a calça do clone não mudou")
		rig:Destroy()
	end)

	t:test("Dress sem look deixa o corpo intacto em vez de estourar no spawn", function()
		-- A classe some do config, ou o nome muda: o corpo tem de nascer, feio, e avisar. Um erro
		-- aqui derruba o spawn inteiro do NpcService, e aí NENHUM NPC nasce.
		local rig, shirt, pants = fakeRig()
		RigLibrary.Dress(rig, "Fantasma", nil)

		t:assertEqual(shirt.ShirtTemplate, BASE_SHIRT, "roupa mexida sem look")
		t:assertEqual(pants.PantsTemplate, BASE_PANTS, "roupa mexida sem look")
		rig:Destroy()
	end)

	t:test("acessório é lista sempre, porque Dress itera nela sem checar", function()
		-- ClassConfig normaliza para {} no loop de baixo do arquivo. Sem isso, `ipairs(nil)` estoura
		-- dentro do spawn — e o spawn é o mesmo caminho de TODA classe, não só a que faltou.
		for _, entry in ipairs(ClassConfig.List) do
			t:assertEqual(type(entry.Accessories), "table", entry.Id .. " com Accessories que não é tabela")
		end

		local rig = fakeRig()
		local ok = pcall(RigLibrary.Dress, rig, "guard_class", { Shirt = "rbxassetid://1" })
		rig:Destroy()
		t:assert(ok, "Dress estourou com look sem Accessories")
	end)

	t:test("guard_class é a única classe com acessório, e o nome tem de bater com a pasta", function()
		-- MEDIDO: só `Character.guard_class.Rig` tinha um Accessory — `Guard Cap`, HatAttachment com
		-- AccessoryRigidConstraint. O nome aqui é o nome procurado em
		-- ServerStorage.Rigs.Accessories.<Id>; divergiu, o guarda nasce sem boné e só o console conta.
		local withAccessory = {}
		for _, entry in ipairs(ClassConfig.List) do
			if #entry.Accessories > 0 then
				withAccessory[entry.Id] = entry.Accessories
			end
		end

		t:assertEqual(#(withAccessory.guard_class or {}), 1, "guard_class perdeu o boné")
		t:assertEqual(withAccessory.guard_class[1], "Guard Cap", "o nome do acessório mudou")

		local count = 0
		for _ in pairs(withAccessory) do
			count += 1
		end
		t:assertEqual(count, 1, "surgiu classe com acessório sem pasta em ServerStorage.Rigs.Accessories")
	end)

	-- Monta em ServerStorage.Rigs.Accessories um balde descartável, para exercitar o caminho real de
	-- Dress em vez de uma cópia da lógica. Devolve o que precisa ser destruído no fim.
	local function plantAccessory(key)
		local ServerStorage = game:GetService("ServerStorage")
		local trash = {}

		local rigs = ServerStorage:FindFirstChild("Rigs")
		if not rigs then
			rigs = Instance.new("Folder")
			rigs.Name = "Rigs"
			rigs.Parent = ServerStorage
			table.insert(trash, rigs)
		end

		local accessories = rigs:FindFirstChild("Accessories")
		if not accessories then
			accessories = Instance.new("Folder")
			accessories.Name = "Accessories"
			accessories.Parent = rigs
			table.insert(trash, accessories)
		end

		local bucket = Instance.new("Folder")
		bucket.Name = key
		bucket.Parent = accessories
		table.insert(trash, bucket)

		-- O corpo ESTRANHO: é a cabeça dele que o acessório traz presa no Clone.
		local foreign = Instance.new("Model")
		foreign.Name = "corpo de origem"
		local foreignHead = Instance.new("Part")
		foreignHead.Name = "Head"
		foreignHead.Parent = foreign
		local foreignHook = Instance.new("Attachment")
		foreignHook.Name = "HatAttachment"
		foreignHook.Parent = foreignHead
		foreign.Parent = ServerStorage
		table.insert(trash, foreign)

		local accessory = Instance.new("Accessory")
		accessory.Name = "Spec Cap"
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Parent = accessory
		local hook = Instance.new("Attachment")
		hook.Name = "HatAttachment"
		hook.Parent = handle
		local rigid = Instance.new("RigidConstraint")
		rigid.Name = "AccessoryRigidConstraint"
		rigid.Attachment0 = hook
		rigid.Attachment1 = foreignHook
		rigid.Parent = handle
		-- Um SEGUNDO vinculo, que attach nunca toca: so unbind alcanca este.
		local stray = Instance.new("Weld")
		stray.Name = "StrayWeld"
		stray.Part0 = handle
		stray.Part1 = foreignHead
		stray.Parent = handle

		accessory.Parent = bucket

		return trash, foreignHook, foreignHead
	end

	local function fakeBody(withHatAttachment)
		local body = Instance.new("Model")
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Parent = body
		if withHatAttachment then
			local hook = Instance.new("Attachment")
			hook.Name = "HatAttachment"
			hook.Parent = head
		end
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = body
		return body, head
	end

	-- A limpeza tem de acontecer mesmo com asserção vermelha: sem isso uma bateria que falha deixa
	-- balde e corpo espalhados no ServerStorage, e a rodada seguinte mede um place sujo.
	local function withScene(bodyHasHatAttachment, run)
		local trash, foreignHook, foreignHead = plantAccessory("__spec_class")
		local body, head = fakeBody(bodyHasHatAttachment)

		local ok, err = pcall(run, body, head, foreignHook, foreignHead)

		body:Destroy()
		for _, item in ipairs(trash) do
			item:Destroy()
		end

		if not ok then
			error(err, 0)
		end
	end

	t:test("acessório não pode nascer preso à cabeça do rig de onde foi copiado", function()
		-- MEDIDO no place, e foi assim que o bug apareceu: `Instance:Clone()` PRESERVA referência que
		-- aponta para fora da árvore clonada. O `Guard Cap` autorado dentro de guard_class saiu do
		-- Clone com Attachment1 = <rig de origem>.Head.HatAttachment, e Humanoid:AddAccessory NÃO
		-- reescreve vínculo já preenchido. O boné acompanharia uma cabeça parada em ServerStorage, e
		-- viraria nil no dia em que aquele rig fosse apagado. Nada disso gera erro.
		withScene(true, function(body, head, foreignHook, foreignHead)
			RigLibrary.Dress(body, "__spec_class", { Accessories = { "Spec Cap" } })

			local cap = body:FindFirstChild("Spec Cap")
			t:assert(cap ~= nil, "o acessório não foi parenteado no corpo")

			local rigid = cap.Handle:FindFirstChildOfClass("RigidConstraint")
			t:assert(rigid.Attachment1 ~= foreignHook, "o acessório continua preso ao corpo de origem")
			t:assertEqual(rigid.Attachment1.Parent, head, "o acessório não foi preso à cabeça deste corpo")
			t:assert(rigid.Attachment0:IsDescendantOf(cap), "Attachment0 saiu do próprio acessório")

			-- attach reescreve o RigidConstraint, e só ele. Todo OUTRO vínculo que veio apontando
			-- para fora continua apontando, e é isso que unbind existe para cortar.
			for _, descendant in ipairs(cap:GetDescendants()) do
				if descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
					t:assert(descendant.Part1 ~= foreignHead, descendant.Name .. " ainda prende no corpo de origem")
				end
			end
		end)
	end)

	t:test("corpo sem o attachment do acessório não recebe peça solta, que cairia no chão", function()
		-- ClassMorphService desancora TODA BasePart depois de vestir. Um acessório parenteado sem
		-- vínculo é uma peça solta: cai, rola, e fica no mapa. Melhor nascer sem boné e avisar.
		withScene(false, function(body)
			RigLibrary.Dress(body, "__spec_class", { Accessories = { "Spec Cap" } })
			t:assertEqual(body:FindFirstChild("Spec Cap"), nil, "acessório parenteado sem onde prender")
		end)
	end)

	t:test("o corpo vem de dentro do pacote, e traz o que Dress precisa", function()
		-- MEDIDO: o corpo é ServerStorage.Rigs.Character.citizen_class.Rig, DENTRO do pacote
		-- 127188560784122 v11 — não uma cópia dele. Cópia divergia calada: "Update Package" no Lobby
		-- mudava a prévia da loja e o Match continuava spawnando o corpo velho.
		-- Este teste morre se alguém mover a pasta, renomear o rig, ou se um pacote novo vier sem
		-- Shirt ou sem Pants — e aí TODA classe nasceria com a roupa que veio no corpo.
		local base = RigLibrary.Base()
		t:assert(base ~= nil, "corpo ausente: confira ServerStorage.Rigs.Character.citizen_class.Rig")
		t:assert(base:IsA("Model"), "o corpo não é um Model")
		t:assert(base:FindFirstChildOfClass("Humanoid") ~= nil, "corpo sem Humanoid: nada anda")
		t:assert(base:FindFirstChildOfClass("Shirt") ~= nil, "corpo sem Shirt: Dress não tem onde escrever")
		t:assert(base:FindFirstChildOfClass("Pants") ~= nil, "corpo sem Pants: Dress não tem onde escrever")
		t:assert(base:FindFirstChild("Animate") ~= nil, "corpo sem Animate: NpcAnimator fica sem catálogo")
		t:assert(base:FindFirstChild("Head") ~= nil, "corpo sem Head: acessório não acha onde prender")
	end)

	-- Planta um rig custom descartável em ServerStorage.Rigs.Npc.<classe>.
	local function plantNpcRig(class, shirt)
		local ServerStorage = game:GetService("ServerStorage")
		local trash = {}

		local npc = ServerStorage.Rigs:FindFirstChild("Npc")
		if not npc then
			npc = Instance.new("Folder")
			npc.Name = "Npc"
			npc.Parent = ServerStorage.Rigs
			table.insert(trash, npc)
		end

		local rig = Instance.new("Model")
		rig.Name = class
		local cloth = Instance.new("Shirt")
		cloth.ShirtTemplate = shirt
		cloth.Parent = rig
		Instance.new("Humanoid").Parent = rig
		rig.Parent = npc
		table.insert(trash, rig)

		return trash, rig
	end

	t:test("classe sem rig custom cai no corpo do pacote", function()
		local body, custom = RigLibrary.Body("Citizen")
		t:assertEqual(body, RigLibrary.Base(), "Citizen deixou de usar o corpo do pacote")
		t:assertEqual(custom, false, "Citizen marcado como custom sem ter pasta em Rigs.Npc")
	end)

	t:test("classe com rig custom usa o dela, e NÃO é vestida por cima", function()
		-- O pedido é NPC custom com rig e animação próprios. Vestir por cima apagaria a roupa
		-- autorada, e o defeito seria mudo: o NPC nasce, anda, e só está com a roupa errada.
		-- O `custom` que Body devolve é o que NpcService lê para pular Dress.
		local trash, planted = plantNpcRig("__SpecNpc", "rbxassetid://777")

		local body, custom = RigLibrary.Body("__SpecNpc")
		t:assertEqual(body, planted, "o rig custom não foi escolhido")
		t:assertEqual(custom, true, "rig custom não foi sinalizado, e NpcService o vestiria por cima")

		for _, item in ipairs(trash) do
			item:Destroy()
		end
	end)

	t:test("o Animate do rig custom é dele, senão a classe herda a animação do corpo padrão", function()
		-- NpcAnimator monta o catálogo lendo o Animate do TEMPLATE. Com um corpo só, as quatro
		-- classes recebiam o mesmo conjunto e não havia como separar. Rig custom devolve isso: o
		-- catálogo passa a sair do rig da classe.
		local trash, planted = plantNpcRig("__SpecNpc", "rbxassetid://777")
		local animate = Instance.new("Folder")
		animate.Name = "Animate"
		local group = Instance.new("Folder")
		group.Name = "walk"
		group.Parent = animate
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://999"
		anim.Parent = group
		animate.Parent = planted

		local body = RigLibrary.Body("__SpecNpc")
		local found = body:FindFirstChild("Animate")
		t:assert(found ~= nil, "rig custom sem Animate próprio")
		t:assertEqual(found.walk:FindFirstChildOfClass("Animation").AnimationId, "rbxassetid://999", "catálogo não é o do rig custom")

		for _, item in ipairs(trash) do
			item:Destroy()
		end
	end)
end
