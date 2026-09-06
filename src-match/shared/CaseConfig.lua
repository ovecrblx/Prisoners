-- Pastas de caso que nascem dentro das gavetas. O que cada pasta mostra sai da lista aqui embaixo;
-- em que gaveta a fila nasce é sorteado no boot da partida, entre as gavetas que abrem.
local CaseConfig = {}

-- Molde publicado no place. É um Model, não um Folder — o nome engana.
CaseConfig.TemplatePath = { "Client", "Models", "Folder" }
CaseConfig.TemplateWait = 20

-- Caminhos dentro do clone, a partir do Model. `Page` está reservada para a descrição do caso e
-- ainda não tem leitor: o campo existe na lista, ninguém o escreve.
CaseConfig.PhotoPath = { "Root", "SurfaceGui", "Frame", "Frame_Image", "Photo" }
-- O nome do caso mora na ABA de topo, na peça Part, que fica 0,5 acima do centro da capa. Com a
-- pasta em pé é ela que a câmera enquadra de cima.
-- Na capa NÃO se mexe: Root.SurfaceGui.Frame.Frame_Tag é o carimbo TOP SECRET, e é decoração.
CaseConfig.NamePath = { "Part", "SurfaceGui", "Frame_Text", "Name" }
CaseConfig.TagPath = { "Root", "SurfaceGui", "Frame", "Frame_Tag" }
CaseConfig.CoverName = "Root"

-- Um caso por linha. `photo` vai direto para o Image do retrato, e vazio deixa o quadro em branco,
-- que é como o molde vem publicado. `page` é a descrição, reservada.
-- Só o Farmer tem retrato próprio; os outros dois repetem o dele à espera dos ids de verdade.
CaseConfig.Cases = {
	{ id = "farmer", name = "Farmer", photo = "rbxassetid://111541704155412", page = "" },
	{ id = "case_2", name = "Case 02", photo = "rbxassetid://111541704155412", page = "" },
	{ id = "case_3", name = "Case 03", photo = "rbxassetid://111541704155412", page = "" },
}

-- Pastas da fila, todas na MESMA gaveta sorteada: é o que dá o que percorrer com as teclas. Acima do
-- tamanho da lista o caso repetiria, e a bateria reprova antes disso.
CaseConfig.PerDrawer = 3

-- Atributos gravados pelo servidor em cada pasta. `Slot` fixa a ordem da fila: sem ele o cliente
-- dependeria da ordem de GetChildren, que a engine não promete.
CaseConfig.IdAttribute = "CaseId"
CaseConfig.SlotAttribute = "Slot"

-- Giro da pasta no local da caixa. Zerado já põe a capa virada para a boca: a arte mora na face
-- Front do Root, que é o -Z local da pasta, e a boca da gaveta é o -Z local da caixa. Medido nos
-- dois sentidos de armário. EM PÉ, como arquivo em gaveta: a pasta tem 1,148 de altura e a caixa
-- 0,981, então ela sobra 0,167 acima da borda, e é isso que deixa a fila visível de cima.
CaseConfig.Angles = Vector3.new(0, 0, 0)

-- Fração da PROFUNDIDADE da gaveta entre uma pasta e a seguinte, somada à espessura da própria
-- pasta. 3% de 3,063 dá 0,092 stud de folga, e a fila de três ocupa 0,54 de 3,06 de fundo.
CaseConfig.Gap = 0.03

-- Studs entre a base da pasta e o piso da caixa. 0 encosta.
CaseConfig.Clearance = 0

-- Deslocamento lateral dentro da gaveta. A ALTURA não está aqui de propósito: ela é derivada do
-- molde em PoseAt, porque o pivô do Model não fica no centro do volume — está 0,225 abaixo dele — e
-- um número escrito à mão aqui deixaria a fila flutuando sem nada acusar.
CaseConfig.Side = 0

-- Destaque da pasta selecionada. Preenchimento apagado de propósito: quem marca é o contorno, e
-- preenchimento em cima da capa esconderia foto e nome, que são a informação.
CaseConfig.FillTransparency = 1
CaseConfig.OutlineTransparency = 0
CaseConfig.FillColor = Color3.fromRGB(255, 255, 255)
CaseConfig.OutlineColor = Color3.fromRGB(255, 255, 255)

-- Fração da ALTURA da pasta que ela sobe ao ser destacada: 50% de 1,148 = 0,574 stud. Sobe no eixo
-- do mundo, não no da gaveta — pasta destacada sai da fila para cima, e a gaveta é nivelada.
CaseConfig.Lift = 0.5
CaseConfig.LiftTime = 0.18
CaseConfig.LiftStyle = Enum.EasingStyle.Quad
CaseConfig.LiftDirection = Enum.EasingDirection.Out

-- Teclas da fila, e o texto que a dica mostra ao lado delas. A ordem aqui é a ordem das plaquinhas
-- no Frame_Info.
CaseConfig.PrevKey = Enum.KeyCode.Q
CaseConfig.TakeKey = Enum.KeyCode.F
CaseConfig.NextKey = Enum.KeyCode.E
CaseConfig.PrevHint = "Prev"
CaseConfig.TakeHint = "Take"
CaseConfig.NextHint = "Next"

-- Vista de quem assumiu a gaveta, no espaço LOCAL da caixa: vale igual nas quatro e acompanha a
-- gaveta enquanto ela corre. O telefone usa coordenada do mundo porque é um aparelho só na sala.
-- Medido: olho a 1,6 acima e 1,6 à frente, mirando 0,25 acima do centro, dá -40 graus de mergulho a
-- 2,09 studs da fila, com caminho livre nas quatro gavetas.
CaseConfig.CameraOffset = Vector3.new(0, 1.6, -1.6)
CaseConfig.CameraTarget = Vector3.new(0, 0.25, 0)
CaseConfig.CameraSmoothing = 12

-- Andar larga a gaveta, como largar o telefone. `SettleWait` são os s de graça logo depois de
-- assumir: quem acabou de chegar ainda carrega velocidade do último passo, e sem a janela a gaveta
-- se fecharia no quadro seguinte ao prompt.
CaseConfig.CancelSpeed = 0.1
CaseConfig.SettleWait = 0.35

function CaseConfig.Node(root, path)
	local node = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

-- Os dois rótulos do molde são TextButton, não TextLabel: as duas classes carregam `Text` mas não
-- descendem uma da outra, e exigir só TextLabel faz a pasta nascer com o texto autorado.
local function textOf(node)
	return if node and (node:IsA("TextLabel") or node:IsA("TextButton")) then node else nil
end

-- Escreve o caso no clone: retrato, rótulo da capa e aba de topo. Devolve o que NÃO encontrou, para
-- o chamador avisar em vez de deixar nascer pasta com o nome do molde.
function CaseConfig.Dress(model, case)
	local missing = {}

	local photo = CaseConfig.Node(model, CaseConfig.PhotoPath)
	if photo and photo:IsA("ImageLabel") then
		photo.Image = case.photo
	else
		table.insert(missing, table.concat(CaseConfig.PhotoPath, "."))
	end

	local label = textOf(CaseConfig.Node(model, CaseConfig.NamePath))
	if label then
		label.Text = case.name
	else
		table.insert(missing, table.concat(CaseConfig.NamePath, "."))
	end

	model:SetAttribute(CaseConfig.IdAttribute, case.id)
	return missing
end

function CaseConfig.Rotation()
	local angles = CaseConfig.Angles
	return CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

-- Medidas do molde, tiradas dele e não escritas à mão: espessura para o passo da fila, o volume, e
-- onde o volume está em relação ao PIVÔ. `PivotTo` posiciona o pivô, e no molde ele fica 0,225
-- abaixo do centro do volume — assumir que os dois coincidem deixa a fila flutuando.
function CaseConfig.Metrics(template)
	local center, size = template:GetBoundingBox()
	return { size = size, delta = template:GetPivot():PointToObjectSpace(center.Position) }
end

-- Passo entre duas pastas da fila, ao longo do trilho da gaveta.
function CaseConfig.Pitch(depth, thickness)
	return thickness + CaseConfig.Gap * depth
end

-- Meia-extensão de um volume girado, projetada em cada eixo de quem o recebe.
function CaseConfig.Extent(rotation, size)
	local half = size / 2
	local x, y, z = rotation.XVector, rotation.YVector, rotation.ZVector
	return Vector3.new(
		math.abs(x.X) * half.X + math.abs(y.X) * half.Y + math.abs(z.X) * half.Z,
		math.abs(x.Y) * half.X + math.abs(y.Y) * half.Y + math.abs(z.Y) * half.Z,
		math.abs(x.Z) * half.X + math.abs(y.Z) * half.Y + math.abs(z.Z) * half.Z
	)
end

-- Altura do PIVÔ, no local da caixa, que faz a BASE do volume pousar no piso da gaveta.
function CaseConfig.BaseHeight(rig, metrics)
	local rotation = CaseConfig.Rotation()
	local reach = CaseConfig.Extent(rotation, metrics.size)
	local above = rotation:VectorToWorldSpace(metrics.delta).Y
	return -rig.height / 2 + CaseConfig.Clearance + reach.Y - above
end

-- Vista da gaveta no MUNDO, tirada da caixa: olho e alvo saem do local dela, então o enquadramento
-- vira junto com o armário e acompanha a gaveta enquanto ela corre.
function CaseConfig.View(box)
	return CFrame.lookAt(
		box.CFrame:PointToWorldSpace(CaseConfig.CameraOffset),
		box.CFrame:PointToWorldSpace(CaseConfig.CameraTarget)
	)
end

-- Pose da pasta `index` de uma fila de `count`, no espaço local da caixa. A fila fica centrada no
-- fundo da gaveta, e `rig.axis` aponta para a boca, então a pasta 1 é a da frente.
function CaseConfig.PoseAt(rig, index, count, metrics)
	local pitch = CaseConfig.Pitch(rig.depth, metrics.size.Z)
	local shift = (index - (count + 1) / 2) * pitch
	local seat = Vector3.new(CaseConfig.Side, CaseConfig.BaseHeight(rig, metrics), 0)
	return CFrame.new(seat + rig.axis * shift) * CaseConfig.Rotation()
end

return CaseConfig
