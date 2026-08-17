-- Catálogo das classes do lobby. Fonte única: a UI, o viewer e o servidor leem daqui.
local ClassConfig = {}

-- Id: chave estável, usada em save e em RemoteEvent. Não renomear depois de publicado.
-- Rig: pasta em ReplicatedStorage.Client.Character (padrão: o próprio Id).
-- Title: texto do card. Icon: rbxassetid; string vazia mantém a imagem do template.
-- Price: preço em diamante, exibido direto. ProductId: DeveloperProduct da compra em
-- Robux; o preço dele vem do produto real, publicado pelo servidor (ver ClassPriceService).
ClassConfig.List = {
	{ Id = "detective_class", Title = "Detective", Icon = "rbxassetid://119583885663870", Price = 99, ProductId = 0 },
	{ Id = "guard_class", Title = "Guard", Icon = "rbxassetid://102951150936232", Price = 49, ProductId = 0 },
	{ Id = "medic_class", Title = "Medic", Icon = "rbxassetid://139845748242300", Price = 29, ProductId = 0 },
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

function ClassConfig.Default()
	return ClassConfig.List[1]
end

return ClassConfig
