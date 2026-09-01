-- Contornos do mundo, apagados em bloco e só nesta tela. Enquanto está ligado, todo Highlight de
-- workspace fica Enabled = false, e o que nascer no meio nasce apagado — contorno é dica de mundo, e
-- de dentro de uma tela de vigilância ele atravessa parede e cabine.
-- Volta a acender só o que este módulo apagou: contorno que já estava apagado tinha o próprio motivo,
-- e o que foi destruído no meio não é reerguido.
-- O sinal de workspace fica de pé só enquanto está ligado: com streaming ele dispara a cada peça que
-- chega, e é conexão cara para manter à toa.
local HighlightGate = {}

local Workspace = game:GetService("Workspace")

local suppressed = false
local muted = {}
local link

local function mute(item)
	if item:IsA("Highlight") and item.Enabled then
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
		for _, item in ipairs(Workspace:GetDescendants()) do
			mute(item)
		end
		link = Workspace.DescendantAdded:Connect(mute)
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
