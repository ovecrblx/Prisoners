-- Contornos do mundo, apagados em bloco e só nesta tela. Enquanto está ligado, todo Highlight
-- marcado com TaskConfig.HighlightTag fica Enabled = false, e o que nascer no meio nasce apagado —
-- contorno é dica de mundo, e de dentro de uma tela de vigilância ele atravessa parede e cabine.
-- O registro é a tag, não uma varredura: quem cria um Highlight marca, e aqui só se lê a lista já
-- pronta. Varrer workspace custava percorrer dezenas de milhares de instâncias a cada sentada.
-- Volta a acender só o que este módulo apagou: contorno que já estava apagado tinha o próprio motivo,
-- e o que foi destruído no meio não é reerguido.
local HighlightGate = {}

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local TaskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TaskConfig"))

local suppressed = false
local muted = {}
local link

-- A tag pega qualquer lugar do DataModel; só o mundo interessa, e template guardado não desenha.
local function mute(item)
	if item:IsA("Highlight") and item.Enabled and item:IsDescendantOf(Workspace) then
		muted[item] = true
		item.Enabled = false
	end
end

function HighlightGate.Suppress(on)
	if suppressed == on then
		return
	end
	suppressed = on

	if on then
		for _, item in ipairs(CollectionService:GetTagged(TaskConfig.HighlightTag)) do
			mute(item)
		end
		link = CollectionService:GetInstanceAddedSignal(TaskConfig.HighlightTag):Connect(mute)
		return
	end

	if link then
		link:Disconnect()
		link = nil
	end
	for item in pairs(muted) do
		if item.Parent then
			item.Enabled = true
		end
	end
	table.clear(muted)
end

return HighlightGate
