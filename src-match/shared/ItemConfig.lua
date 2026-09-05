-- Contrato comum dos itens equipáveis: onde mora o template, em que parte do corpo a junta prende,
-- os nomes dos remotes e a ordem dos slots. O que muda de item para item — pose, ponto de coleta,
-- ícone, tecla — vive no config do próprio item, e os campos de pose têm o mesmo nome em todos
-- porque é por eles que o ItemView monta qualquer um sem saber qual é.
-- Order é a ordem do HUD e a das teclas: o item na posição N responde à tecla N.
local ItemConfig = {}

ItemConfig.Order = { "Manual", "Flashlight" }

ItemConfig.TemplateFolder = "Models" -- dentro de ReplicatedStorage.Client
ItemConfig.HandleName = "Handle"
ItemConfig.JointName = "ItemJoint"
ItemConfig.WaistPartName = "LowerTorso"
ItemConfig.HandPartName = "LeftHand"

-- O braço que segura, da mão para cima. Em primeira pessoa o PlayerModule apaga o personagem
-- inteiro; estes voltam junto com o item que está na mão.
ItemConfig.HandChain = { "LeftHand", "LeftLowerArm", "LeftUpperArm" }

-- A GUI publicada carrega o Hud, e é dentro dele que ficam os slots de todos os itens.
ItemConfig.GuiName = "HudGui"
ItemConfig.HudName = "Hud"
ItemConfig.SlotTemplateName = "ImageButton"

ItemConfig.RemotesFolderName = "Remotes"
ItemConfig.ActionRemote = "ItemAction" -- cliente -> servidor: (itemId, campo, valor)
ItemConfig.StateRemote = "ItemState" -- servidor -> todos; sem argumento, cliente pede o retrato

ItemConfig.HoldTime = 3 -- segundos de botão segurado para devolver o item ao lugar de coleta

-- studs do HumanoidRootPart ao ponto de coleta que o servidor aceita como "pegou". O prompt do
-- cliente abre a DoorConfig.PromptDistance; a folga é latência e corpo em movimento.
ItemConfig.CollectRange = 16

-- Pedidos de ItemAction por jogador por segundo; acima disso o servidor ignora.
ItemConfig.ActionsPerSecond = 10

function ItemConfig.Index(itemId)
	for index, name in ipairs(ItemConfig.Order) do
		if name == itemId then
			return index
		end
	end
	return nil
end

-- Config do próprio item, pelo nome do módulo no Shared: Flashlight -> FlashlightConfig. É lá que
-- moram pose e ponto de coleta.
function ItemConfig.Of(itemId)
	local module = script.Parent:FindFirstChild(itemId .. "Config")
	return if module then require(module) else nil
end

return ItemConfig
