-- Pose do cabo do telefone, uma lista por fase. O cabo deixou de ser física: os elos ficam
-- ancorados e vão de uma pose à outra por percurso, e quem desenha a espiral são os
-- SpringConstraint do place, que passam a ser só o desenho.
local CordConfig = {}

-- CALIBRAGEM DO CABO. Posição é no espaço do BODY do aparelho, em studs — não é coordenada de
-- mundo: mover o telefone leva o cabo junto. A ordem da lista é o sufixo do nome, então o item 1 é
-- Cord_Link_1, o que sai do aparelho, e o último é o que segura o fone.

-- Parado: o fone no gancho, ninguém na linha.
CordConfig.Idle = {
	Vector3.new(0.7241, -0.3302, -0.9287),
	Vector3.new(0.8093, -0.1559, -0.4158),
	Vector3.new(0.845, 0.0467, 0.0743),
	Vector3.new(0.7001, 0.3579, 0.5492),
	Vector3.new(0.5424, 0.3976, 0.8017),
}

-- Foco no teclado: de atender até o número encher.
CordConfig.Keypad = {
	Vector3.new(0.4011, -0.2859, -1.0051),
	Vector3.new(0.7629, -0.3164, -0.8897),
	Vector3.new(0.7773, -0.2284, -0.4608),
	Vector3.new(0.7645, -0.1245, -0.2015),
	Vector3.new(0.7723, 0.0205, -0.5832),
}

-- Fora do foco: entra com as seis casas cheias, sai quando o campo recomeça vazio.
CordConfig.Call = {
	Vector3.new(0.228, -0.3983, -1.1027),
	Vector3.new(0.5258, -0.4326, -1.1638),
	Vector3.new(0.7871, -0.2905, -1.2483),
	Vector3.new(0.8803, -0.0215, -1.3364),
	Vector3.new(0.8339, 0.1489, -1.4265),
}

-- Vale nas três. Ângulo é grau, na ordem Y-X-Z do campo Orientation do Studio, e é um só para
-- todos os elos: o elo é um cubo de 0,05 e o que a rotação move é o ponto onde a espiral prende.
CordConfig.LinkAngles = Vector3.new(-7.9376, -120.4655, 0)

-- Smoothing é 1/s, só o tempo de chegar lá: maior endurece até virar corte seco. Settle são os
-- studs abaixo dos quais a pose é dada por chegada — é ele que solta o laço e zera o custo parado.
CordConfig.Smoothing = 8
CordConfig.Settle = 0.001

-- Classes que a física do cabo usava e que a pose autorada dispensa. SpringConstraint fica de fora
-- de propósito: é ele o desenho da espiral, e entre peças ancoradas não empurra nada.
CordConfig.DeadClasses = { "RopeConstraint", "LinearVelocity", "AlignOrientation" }

CordConfig.Phases = { "Idle", "Keypad", "Call" }

function CordConfig.Nodes(phase)
	return CordConfig[phase] or CordConfig.Idle
end

return CordConfig
