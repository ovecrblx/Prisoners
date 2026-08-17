-- Catálogo das classes do lobby. Fonte única: a UI, o viewer e o servidor leem daqui.
local ClassConfig = {}

-- Id: chave estável, usada em save e em RemoteEvent. Não renomear depois de publicado.
-- Rig: pasta em ReplicatedStorage.Client.Models.Character (padrão: o próprio Id).
-- Title: texto do card. Icon: rbxassetid; string vazia mantém a imagem do template.
-- Price: preço exibido no botão Buy, em Gold.
ClassConfig.List = {
	{ Id = "akame", Title = "Akame", Icon = "rbxassetid://119583885663870", Price = 99 },
	{ Id = "azy", Title = "Azy", Icon = "rbxassetid://105286110390630", Price = 49 },
	{ Id = "ovec", Title = "Ovec", Icon = "rbxassetid://95887552055121", Price = 29 },
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
