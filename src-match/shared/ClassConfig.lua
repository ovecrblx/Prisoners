-- Catálogo das classes (Match). Id e Rig precisam ser iguais aos de
-- src-lobby/shared/ClassConfig.lua: as árvores são separadas, então isso é duplicado por
-- necessidade. Divergiu, o jogador spawna sem a classe que comprou.
-- Preço não vem: compra é assunto do Lobby.
local ClassConfig = {}

-- Atributo no Player com o Id da classe equipada, escrito no spawn.
ClassConfig.EquippedAttribute = "EquippedClass"

-- Rig: pasta em ReplicatedStorage.Client.Character (padrão: o próprio Id).
-- Icon: mesmo asset do Lobby. Color: fundo do cartão no HUD.
ClassConfig.List = {
	{
		Id = "detective_class",
		Title = "Detective",
		Icon = "rbxassetid://119583885663870",
		Color = Color3.fromRGB(255, 179, 0),
	},
	{
		Id = "guard_class",
		Title = "Guard",
		Icon = "rbxassetid://102951150936232",
		Color = Color3.fromRGB(214, 96, 66),
	},
	{
		Id = "medic_class",
		Title = "Medic",
		Icon = "rbxassetid://139845748242300",
		Color = Color3.fromRGB(72, 196, 132),
	},
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
