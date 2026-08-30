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

-- A GUI publicada ainda se chama ManualGui, de quando o caderno era o único item; o Hud dentro
-- dela é que carrega os slots de todos.
ItemConfig.GuiName = "ManualGui"
ItemConfig.HudName = "Hud"
ItemConfig.SlotTemplateName = "ImageButton"

ItemConfig.RemotesFolderName = "Remotes"
ItemConfig.ActionRemote = "ItemAction" -- cliente -> servidor: (itemId, campo, valor)
ItemConfig.StateRemote = "ItemState" -- servidor -> todos; sem argumento, cliente pede o retrato

ItemConfig.HoldTime = 3 -- segundos de botão segurado para devolver o item ao lugar de coleta

function ItemConfig.Index(itemId)
	for index, name in ipairs(ItemConfig.Order) do
		if name == itemId then
			return index
		end
	end
	return nil
end

return ItemConfig
