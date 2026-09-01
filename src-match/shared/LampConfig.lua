-- Contrato das lâmpadas de workspace.Siland_Home.Lighting e das teclas que as acendem, lido pelo
-- servidor e pelo cliente. O servidor publica o estado na tecla; acender e virar é do cliente.
local LampConfig = {}

-- Estrutura esperada no place, casada pelo sufixo do nome: `Lamp_<sala>` carrega o Part `Light`,
-- `Light_Part_<sala>` é a luz solta da sala, e o `Switch_<sala>` de mesmo sufixo carrega a tecla
-- `Button`. Sufixo sem par fica inerte, e tudo que compartilha sufixo acende junto.
LampConfig.LampFolder = { "Siland_Home", "Lighting" }
LampConfig.SwitchFolder = { "Siland_Home", "interactive" }
LampConfig.LampPrefix = "Lamp_"
LampConfig.SwitchPrefix = "Switch_"
LampConfig.LightPrefix = "Light_Part_"
LampConfig.BulbName = "Light"
LampConfig.ButtonName = "Button"
LampConfig.OnAttribute = "On"

-- Estado em que o place nasce: a tecla já vem ligada, e é assim que a sala está montada.
LampConfig.StartOn = true

-- Aceso e apagado do bulbo, em fração da cor que o bulbo já tem no cenário: 1 é ela intacta, 0 é
-- preto. Quem escolhe a cor é o place, e aqui só se mexe em quanto ela clareia ou escurece —
-- multiplicar os três canais junto mantém matiz e saturação. Acima de 1 os canais saturam, e aí a
-- matiz anda. O Beam, as luzes e a poeira dentro do bulbo acompanham o estado.
LampConfig.BulbOnScale = 1
LampConfig.BulbOffScale = 0.55
LampConfig.BulbTime = 0.12

-- Giro da tecla em graus, somado à pose em que ela foi publicada, em torno do eixo local do próprio
-- Part: 0 é a pose do cenário. Orientação absoluta programada aqui reconstruía a rotação inteira e
-- desalinhava a tecla com a placa.
LampConfig.ButtonAxis = Vector3.xAxis
LampConfig.ButtonOffAngle = 0
LampConfig.ButtonOnAngle = 45
LampConfig.ButtonTime = 0.14
LampConfig.ButtonStyle = Enum.EasingStyle.Back
LampConfig.ButtonDirection = Enum.EasingDirection.Out

-- Style Custom: quem desenha é o PromptDisplay do cliente. Distância curta porque a tecla é de
-- parede e a sala tem outras a poucos studs.
LampConfig.PromptDistance = 8
LampConfig.PromptOffset = Vector2.new(0, 40)
LampConfig.PromptClickable = false

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
function LampConfig.Folder(path, timeout)
	local folder = workspace

	for _, name in ipairs(path) do
		local found = nil

		for _, child in ipairs(folder:GetChildren()) do
			if string.lower(child.Name) == string.lower(name) then
				found = child
				break
			end
		end

		folder = found or folder:WaitForChild(name, timeout)
		if not folder then
			return nil
		end
	end

	return folder
end

-- O sufixo é o que casa as peças, e o índice no fim não entra nele: `Lamp_Lobby_2` e
-- `Light_Part_Lobby_3` caem no mesmo grupo do `Switch_Lobby`. Só número puro no fim sai, então
-- `Light_Part_Corridor_C` fica inteiro — e sala que se chame `Lobby_2` cai junto com `Lobby`.
function LampConfig.Suffix(name, prefix)
	if string.sub(name, 1, #prefix) ~= prefix then
		return nil
	end

	local suffix = string.gsub(string.sub(name, #prefix + 1), "_%d+$", "")
	return suffix ~= "" and suffix or nil
end

function LampConfig.Pose(rest, degrees)
	return rest * CFrame.fromAxisAngle(LampConfig.ButtonAxis, math.rad(degrees))
end

return LampConfig
