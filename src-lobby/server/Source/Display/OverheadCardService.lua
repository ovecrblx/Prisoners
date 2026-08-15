-- Cartão acima da cabeça — LADO SERVIDOR: anexa o accessory ao personagem.
--
-- Só o mecanismo de exibição. Este módulo NÃO escreve em Image, Class nem Leaderboard — quem
-- preenche é outro serviço, via OverheadCardService.GetCard(character).
--
-- Anexado pelo servidor (Humanoid:AddAccessory), então replica para todos automaticamente. Um
-- accessory criado no cliente só apareceria para quem o criou.
--
-- Template esperado (existe no place, em ReplicatedStorage.Client.GUI):
--   BillboardAccessory (Accessory)
--   └── Handle (Part)
--       ├── HatAttachment          solda na HatAttachment da Head
--       └── SurfaceGui
--           └── Card (Frame)
--               ├── Image (ImageButton)
--               └── Info (Frame) > Class, Leaderboard (TextButton)
local OverheadCardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))

local warnedTemplate = false

local function getTemplate()
	local folder = ReplicatedStorage:FindFirstChild(Config.TemplateFolder)
	local sub = folder and folder:FindFirstChild(Config.TemplateSubfolder)
	local template = sub and sub:FindFirstChild(Config.TemplateName)

	if not template and not warnedTemplate then
		warnedTemplate = true
		warn(string.format("[OverheadCardService] Template ausente: ReplicatedStorage.%s.%s.%s", Config.TemplateFolder, Config.TemplateSubfolder, Config.TemplateName))
	end

	return template
end

-- Converte o vínculo rígido do accessory num Weld que o cliente possa reorientar.
--
-- Em R15, Humanoid:AddAccessory solda por RigidConstraint (attachment-a-attachment), não pelo
-- Weld que o engine criava em R6. O controller do cliente só sabe dirigir um Weld — ele reescreve
-- o C0 por frame para encarar a câmera. Sem esta conversão o cartão é anexado corretamente e
-- simplesmente nunca gira: falha silenciosa, e o tipo mais difícil de diagnosticar, porque tudo
-- parece certo na hierarquia.
--
-- O Weld reproduz EXATAMENTE a pose rígida. Com C0/C1 = as CFrames locais das duas attachments,
-- Handle.CFrame*C0 == Head.CFrame*C1, ou seja, as duas HatAttachment coincidem no mundo — que é
-- precisamente o que o RigidConstraint garantia.
--
-- Idempotente: já existindo o Weld, sai na hora.
local function rebindAsWeld(accessory)
	local handle = accessory:FindFirstChild(Config.HandleName)
	if not handle or handle:FindFirstChild(Config.WeldName) then
		return
	end

	local character = accessory.Parent
	local head = character and character:FindFirstChild("Head")
	local handleAtt = handle:FindFirstChild(Config.HatAttachmentName)
	local headAtt = head and head:FindFirstChild(Config.HatAttachmentName)

	-- Remove o vínculo do AddAccessory. Se as attachments não vierem por nome (rig customizado,
	-- attachment renomeada), deriva do próprio constraint ANTES de destruí-lo — depois disso a
	-- informação some.
	for _, child in ipairs(handle:GetChildren()) do
		if child:IsA("RigidConstraint") then
			if not (head and handleAtt and headAtt) then
				local a0, a1 = child.Attachment0, child.Attachment1
				if a0 and a1 then
					local fromHandle = (a0.Parent == handle)
					handleAtt = fromHandle and a0 or a1
					headAtt = fromHandle and a1 or a0
					head = headAtt.Parent
				end
			end
			child:Destroy()
		end
	end

	if not (head and handleAtt and headAtt) then
		return
	end

	local weld = Instance.new("Weld")
	weld.Name = Config.WeldName
	weld.Part0 = handle
	weld.Part1 = head
	weld.C0 = handleAtt.CFrame
	weld.C1 = headAtt.CFrame
	weld.Parent = handle
end

local function attach(character)
	if character:FindFirstChild(Config.AccessoryName) then
		return
	end

	-- AddAccessory precisa da Head e do Humanoid já presentes. CharacterAdded dispara antes do
	-- personagem estar completo, então esperar é obrigatório — com timeout, para não segurar a
	-- thread para sempre se o personagem for destruído no meio.
	local humanoid = character:FindFirstChildWhichIsA("Humanoid") or character:WaitForChild("Humanoid", 10)
	local head = character:FindFirstChild("Head") or character:WaitForChild("Head", 10)
	if not (humanoid and head) then
		return
	end

	-- O personagem pode ter morrido/saído durante a espera acima.
	if not character.Parent then
		return
	end

	local template = getTemplate()
	if not template then
		return
	end

	local accessory = template:Clone()
	accessory.Name = Config.AccessoryName
	humanoid:AddAccessory(accessory)

	rebindAsWeld(accessory)
end

-- O Frame `Card` do personagem, ou nil se o cartão ainda não foi anexado.
--
-- É o gancho para preencher Image, Class e Leaderboard — este serviço deliberadamente não
-- escreve em nenhum deles. Quem chamar precisa aguentar o nil: o anexo é assíncrono (espera a
-- Head), então o cartão não existe no instante do CharacterAdded.
function OverheadCardService.GetCard(character)
	local accessory = character and character:FindFirstChild(Config.AccessoryName)
	local handle = accessory and accessory:FindFirstChild(Config.HandleName)
	local surface = handle and handle:FindFirstChildWhichIsA("SurfaceGui")
	return surface and surface:FindFirstChild(Config.CardName) or nil
end

function OverheadCardService.Start()
	local function track(player)
		player.CharacterAdded:Connect(function(character)
			task.spawn(attach, character)
		end)

		-- Personagem que já existe: CharacterAdded não dispara retroativamente.
		if player.Character then
			task.spawn(attach, player.Character)
		end
	end

	Players.PlayerAdded:Connect(track)

	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
end

return OverheadCardService
