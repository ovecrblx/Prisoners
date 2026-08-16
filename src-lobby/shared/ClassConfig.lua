-- Catálogo das classes do lobby. Fonte única: a UI, o viewer e o servidor leem daqui.
local ClassConfig = {}

-- Id: chave estável, usada em save e em RemoteEvent. Não renomear depois de publicado.
-- Rig: pasta em ReplicatedStorage.Client.Models.Character (padrão: o próprio Id).
-- Title: texto do card. Icon: rbxassetid; string vazia mantém a imagem do template.
-- Price: preço exibido no botão Buy, em Gold.
ClassConfig.List = {
	{ Id = "akame", Title = "Akame", Icon = "", Price = 0 },
	{ Id = "azy", Title = "Azy", Icon = "", Price = 0 },
	{ Id = "ovec", Title = "Ovec", Icon = "", Price = 0 },
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
