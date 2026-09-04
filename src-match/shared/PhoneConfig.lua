-- Contrato do telefone de workspace.Siland_Home.interactive.Phone, lido pelo servidor e pelo
-- cliente. O servidor publica só quem atendeu; levar o fone ao rosto, a primeira pessoa e o
-- cancelamento ao sair do lugar são do cliente.
local PhoneConfig = {}

-- Estrutura esperada no place. O prompt mora na base, que é a peça com CanQuery ligado; o fone é a
-- peça que sobe ao rosto, e o que estiver soldado nela vai junto.
PhoneConfig.Path = { "Siland_Home", "interactive" }
PhoneConfig.ModelName = "Phone"
PhoneConfig.BaseName = "Body"
PhoneConfig.HandsetName = "Head"
PhoneConfig.FacePartName = "Head" -- parte do corpo que serve de referência

-- Estado publicado pelo servidor: UserId de quem está no aparelho, 0 livre. Atributo, não remote:
-- quem entra no meio da partida já recebe o retrato junto com o Model.
PhoneConfig.UserAttribute = "User"

-- Cliente -> servidor, sem argumento: desliga. Atender é só pelo prompt, e quem decide é o servidor.
PhoneConfig.HangUpRemote = "PhoneHangUp"

-- Style Custom: quem desenha é o PromptDisplay do cliente. Distância curta porque o aparelho é de
-- mesa e o balcão tem outras coisas a poucos studs.
PhoneConfig.PromptDistance = 8
PhoneConfig.PromptOffset = Vector2.new(0, 40)
PhoneConfig.PromptClickable = false

-- Pose do fone, no espaço da CÂMERA de quem atende — para quem assiste, no da cabeça dele. Offset em
-- studs, com X à direita, Y para cima e Z para trás: Z negativo é à frente da vista. Ângulos em
-- graus, ordem Y-X-Z igual ao campo Orientation do Studio, não a de CFrame.Angles. Preso à câmera, o
-- fone acompanha o giro horizontal e o vertical, e fica parado na tela de quem está na linha.
PhoneConfig.HandsetOffset = Vector3.new(-0.95, 0.09, -1.3)
PhoneConfig.HandsetAngles = Vector3.new(60, 45, 180)

-- Percurso do fone até o rosto, em 1/s. Não é enfeite: o cabo é uma corrente de RopeConstraint
-- presa nele, e ponta ancorada que salta dá tranco na corda. Na volta o salto é seguro — rope só
-- puxa ao separar, e voltar ao gancho afrouxa.
PhoneConfig.HandsetSmoothing = 8

-- Prefixo dos elos soltos do cabo. Quem está na linha simula a corda: o fone só sobe ao rosto na
-- tela de cada cliente, e quem não simula contra o próprio fone veria o cabo ignorando o aparelho.
PhoneConfig.LinkPrefix = "Cord_Link"

-- Vista de quem atende, solta no mundo: posição em studs e ângulos em graus, ordem Y-X-Z igual ao
-- campo Orientation do Studio. Nasce em cima do teclado olhando para baixo — X é o pitch, e -90 é a
-- vertical. Não segue o jogador: é enquadramento fixo, e o telefone não anda.
-- Smoothing em 1/s, só o tempo de chegar lá: maior endurece até virar corte seco.
-- Enquanto a vista é do telefone o CameraLimit sai da frente sozinho, porque ele só age em Custom.
PhoneConfig.CameraPosition = Vector3.new(-2, 6.75, -38.4)
PhoneConfig.CameraAngles = Vector3.new(-60, 90, 0)
PhoneConfig.CameraSmoothing = 12

-- Cancela a chamada: studs/s de caminhada que já contam como sair do lugar. Pulo cancela sempre.
PhoneConfig.CancelSpeed = 0.1

-- s de espera pelo Model e pelas peças dele. Com streaming o Model chega antes das peças, e pode
-- ir e voltar: nada aqui é resolvido uma vez só e guardado para a partida inteira.
PhoneConfig.ModelWait = 20

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
function PhoneConfig.Folder(timeout)
	local node = workspace

	for _, name in ipairs(PhoneConfig.Path) do
		local found = nil

		for _, child in ipairs(node:GetChildren()) do
			if string.lower(child.Name) == string.lower(name) then
				found = child
				break
			end
		end

		node = found or node:WaitForChild(name, timeout)
		if not node then
			return nil
		end
	end

	return node
end

function PhoneConfig.View()
	local angles = PhoneConfig.CameraAngles
	return CFrame.new(PhoneConfig.CameraPosition)
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

function PhoneConfig.Pose(anchor)
	local angles = PhoneConfig.HandsetAngles
	return anchor
		* CFrame.new(PhoneConfig.HandsetOffset)
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

return PhoneConfig
