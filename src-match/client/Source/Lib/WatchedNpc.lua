--!strict
-- Qual NPC as ferramentas de diagnóstico estão observando. Dono único da resposta: o IA Brain
-- ESCOLHE e publica aqui, a câmera livre LÊ daqui. Módulo e não atributo do Player porque atributo
-- replica, e isto é estado de ferramenta — vive e morre neste cliente.
-- nil = sem escolha explícita; quem lê cai no automático.
local WatchedNpc = {}

local currentId: string? = nil
local currentClass: string? = nil

local changed = Instance.new("BindableEvent")

-- Dispara só na mudança de verdade: o painel republica a cada retrato, e sem a guarda a câmera
-- reobteria o corpo cinco vezes por segundo, cada uma um InvokeServer.
function WatchedNpc.Set(id: string?, class: string?)
	if id == currentId and class == currentClass then
		return
	end
	currentId = id
	currentClass = class
	changed:Fire(id, class)
end

function WatchedNpc.Get(): (string?, string?)
	return currentId, currentClass
end

WatchedNpc.Changed = changed.Event

return WatchedNpc
