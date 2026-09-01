-- De qual perfil do config saem os números do item, pelo aparelho de agora. Fora do PC quem aponta é
-- a câmera, e a lanterna é vista de outro jeito: o config pode trazer uma segunda tabela, OffPc, com
-- os valores de lá. Chave que faltar nela cai no config de cima, pelo __index do próprio config.
-- Medido a cada leitura e nunca guardado: teclado pareado num tablet muda isto em partida, e o
-- emulador do Studio move as três propriedades de uma vez.
local ItemDevice = {}

local UserInputService = game:GetService("UserInputService")

-- PC é mouse COM teclado.
function ItemDevice.OnPc()
	return UserInputService.MouseEnabled and UserInputService.KeyboardEnabled
end

function ItemDevice.Tuning(config)
	if ItemDevice.OnPc() then
		return config
	end
	return config.OffPc or config
end

return ItemDevice
