-- Catálogo das classes (Match). Id e Rig precisam ser iguais aos de
-- src-lobby/shared/ClassConfig.lua: as árvores são separadas, então isso é duplicado por
-- necessidade. Divergiu, o jogador spawna sem a classe que comprou.
-- Preço e ícone não vêm: compra é assunto do Lobby.
local ClassConfig = {}

-- Rig: pasta em ReplicatedStorage.Client.Character (padrão: o próprio Id).
ClassConfig.List = {
	{ Id = "detective_class", Title = "Detective" },
	{ Id = "guard_class", Title = "Guard" },
	{ Id = "medic_class", Title = "Medic" },
}

ClassConfig.ById = {}

for order, entry in ipairs(ClassConfig.List) do
	entry.Order = order
	entry.Rig = entry.Rig or entry.Id
	ClassConfig.ById[entry.Id] = entry
end

function ClassConfig.Get(id)
	return ClassConfig.ById[id]
end

return ClassConfig
