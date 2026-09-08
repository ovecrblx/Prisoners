-- Catálogo das classes (Match). Id precisa ser igual ao de src-lobby/shared/ClassConfig.lua: as
-- árvores são separadas, então isso é duplicado por necessidade. Divergiu, o jogador spawna sem a
-- classe que comprou.
-- Preço não vem: compra é assunto do Lobby.
local ClassConfig = {}

-- Atributo no Player com o Id da classe equipada, escrito no spawn.
ClassConfig.EquippedAttribute = "EquippedClass"

-- Shirt/Pants: rbxassetid aplicado sobre o rig único (ServerStorage.Rigs.Base) — é a ÚNICA coisa
-- que separa uma classe da outra. Accessories: nomes em ServerStorage.Rigs.Accessories.<Id>.
-- Icon: mesmo asset do Lobby. Color: fundo do cartão no HUD.
ClassConfig.List = {
	{
		Id = "detective_class",
		Title = "Detective",
		Icon = "rbxassetid://119583885663870",
		Color = Color3.fromRGB(255, 179, 0),
		Shirt = "rbxassetid://94474587811696",
		Pants = "rbxassetid://92858965926465",
	},
	{
		Id = "guard_class",
		Title = "Guard",
		Icon = "rbxassetid://102951150936232",
		Color = Color3.fromRGB(214, 96, 66),
		Shirt = "rbxassetid://79216673501908",
		Pants = "rbxassetid://125966993565881",
		Accessories = { "Guard Cap" },
	},
	{
		Id = "medic_class",
		Title = "Medic",
		Icon = "rbxassetid://139845748242300",
		Color = Color3.fromRGB(72, 196, 132),
		Shirt = "rbxassetid://16403480536",
		Pants = "rbxassetid://16403694955",
	},
}

ClassConfig.ById = {}

for order, entry in ipairs(ClassConfig.List) do
	entry.Order = order
	entry.Accessories = entry.Accessories or {}
	ClassConfig.ById[entry.Id] = entry
end

function ClassConfig.Get(id)
	return ClassConfig.ById[id]
end

return ClassConfig
