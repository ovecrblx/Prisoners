-- CaseFitSpec — a fila de pastas dentro da gaveta: onde pousa, para onde a capa olha, e o que a
-- lista de casos precisa ter.
--
-- O QUE ESTA SPEC PROTEGE. A pasta é MAIS ALTA que a caixa da gaveta e fica em pé, então a única
-- coisa que a segura no lugar é a base encostada no piso. E `PivotTo` posiciona o PIVÔ do Model, que
-- neste molde está 0,225 abaixo do centro do volume — assumir que os dois coincidem deixa a fila
-- flutuando. Os dois erros são mudos: quem abre a gaveta encontra pasta boiando, afundada no móvel,
-- ou uma fila de versos.
--
-- POR QUE ELA MONTA A PASTA DE VERDADE. A primeira versão deste teste conferia a conta, não o
-- resultado, e passou verde com a fila flutuando 0,225 stud. Quem acusou foi a simulação. Agora o
-- teste clona o molde, aplica a MESMA pose que o serviço aplica, e mede o volume que sobrou.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local CaseConfig = t:freshRequire(ReplicatedStorage.Shared.CaseConfig)

	-- MEDIDO NO PLACE, e igual nas 24 gavetas: caixa 1.426 x 0.981 x 3.063. A boca é o -Z LOCAL
	-- dela, medido nos dois sentidos de armário.
	local DRAWER = Vector3.new(1.4258860349655151, 0.9808174967765808, 3.0631303787231445)
	local MOUTH = Vector3.new(0, 0, -1)
	local RIG = { height = DRAWER.Y, depth = DRAWER.Z, axis = MOUTH }

	local template = ReplicatedStorage
	for _, name in ipairs(CaseConfig.TemplatePath) do
		template = template and template:FindFirstChild(name)
	end
	t:assert(template ~= nil, "molde da pasta não está no place: " .. table.concat(CaseConfig.TemplatePath, "."))

	local metrics = CaseConfig.Metrics(template)

	-- Monta a pasta `slot` na caixa em CFrame identidade, e devolve o volume dela.
	local function placed(slot, count)
		local clone = template:Clone()
		clone.Parent = workspace
		clone:PivotTo(CaseConfig.PoseAt(RIG, slot, count, metrics))
		local center, size = clone:GetBoundingBox()
		clone:Destroy()
		return center, size
	end

	t:test("a pasta é mais alta que a gaveta, e por isso sobra acima da borda", function()
		-- 1.148 contra 0.981: 0.167 de pasta ficam para fora. Não é defeito, é o que deixa a fila
		-- visível de cima. O teste tranca a MEDIÇÃO: se o molde encolher, ele cai e a regra pode ser
		-- revista de propósito em vez de silenciosamente.
		t:assert(metrics.size.Y > DRAWER.Y, "pasta mais alta que a caixa")
		t:assertNear(metrics.size.Y - DRAWER.Y, 0.1667, 1e-3, "a sobra acima da borda")
	end)

	t:test("o pivô do molde não é o centro do volume, e a pose conta com isso", function()
		-- É a medição que a primeira versão do código ignorou. Se um dia o molde for reautorado com
		-- o pivô no centro, este teste cai e a conta pode ser simplificada de propósito.
		t:assert(math.abs(metrics.delta.Y) > 0.1, "o pivô estava a 0.225 do centro; virou " .. tostring(metrics.delta))
	end)

	t:test("a base da pasta pousa no piso da gaveta, sem afundar nem flutuar", function()
		-- Este é o teste que a simulação obrigou a existir: mede a pasta MONTADA, não a fórmula.
		local center, size = placed(1, CaseConfig.PerDrawer)
		local base = center.Position.Y - size.Y / 2
		t:assertNear(base, -DRAWER.Y / 2 + CaseConfig.Clearance, 1e-3, "a base tem que pousar no piso")
	end)

	t:test("a fila não sai pela lateral nem pela frente da gaveta", function()
		-- Altura fica de fora de propósito: é o eixo em que a pasta sobra, e está no teste acima.
		local first = placed(1, CaseConfig.PerDrawer)
		local last, size = placed(CaseConfig.PerDrawer, CaseConfig.PerDrawer)
		local run = (first.Position - last.Position).Magnitude / 2

		t:assert(math.abs(first.Position.X) + size.X / 2 <= DRAWER.X / 2, "a pasta sai pela lateral")
		t:assert(run + size.Z / 2 <= DRAWER.Z / 2, "a fila sai pela frente ou por trás da gaveta")
	end)

	t:test("as pastas ficam separadas pela folga pedida, em fila", function()
		-- 3% da profundidade da gaveta, somados à espessura da própria pasta. Coladas, a fila vira um
		-- bloco e não dá para ver que são pastas distintas.
		local a = placed(1, CaseConfig.PerDrawer)
		local b = placed(2, CaseConfig.PerDrawer)
		local pitch = (a.Position - b.Position).Magnitude
		t:assertNear(pitch, metrics.size.Z + CaseConfig.Gap * DRAWER.Z, 1e-3, "passo entre duas pastas")
		t:assert(pitch > metrics.size.Z, "o passo tem que ser maior que a espessura, senão elas se tocam")
	end)

	t:test("a capa olha para a boca da gaveta, não para o fundo", function()
		-- MEDIDO: a arte mora na face Front do Root, que é o -Z local da pasta. Pousar e apontar são
		-- perguntas diferentes: a conta de extensão usa módulo e passa com a pasta virada para
		-- qualquer lado, então só este teste segura o lado.
		local FACE_NORMAL = {
			[Enum.NormalId.Front] = Vector3.new(0, 0, -1),
			[Enum.NormalId.Back] = Vector3.new(0, 0, 1),
			[Enum.NormalId.Top] = Vector3.new(0, 1, 0),
			[Enum.NormalId.Bottom] = Vector3.new(0, -1, 0),
			[Enum.NormalId.Right] = Vector3.new(1, 0, 0),
			[Enum.NormalId.Left] = Vector3.new(-1, 0, 0),
		}

		local cover = CaseConfig.Node(template, { CaseConfig.CoverName, "SurfaceGui" })
		t:assert(cover ~= nil, "o molde perdeu a SurfaceGui da capa")

		local aim = CaseConfig.Rotation():VectorToWorldSpace(FACE_NORMAL[cover.Face])
		t:assert(aim:Dot(MOUTH) > 0.9, "a capa aponta para " .. tostring(aim) .. ", não para a boca")
	end)

	t:test("todo caso da lista tem id e nome", function()
		-- Caso sem nome nasce com o rótulo do molde, "TOP SECRET", e passa por caso de verdade na
		-- tela. Caso sem id não dá para reconhecer depois pelo atributo que o serviço grava.
		for index, case in ipairs(CaseConfig.Cases) do
			t:assert(type(case.id) == "string" and case.id ~= "", "caso " .. index .. " sem id")
			t:assert(type(case.name) == "string" and case.name ~= "", "caso " .. index .. " sem nome")
		end
	end)

	t:test("há caso suficiente para a fila que a partida promete", function()
		-- PerDrawer acima do tamanho da lista faz duas pastas da MESMA gaveta mostrarem o mesmo caso.
		t:assert(CaseConfig.PerDrawer >= 1, "PerDrawer abaixo de 1 não semeia nada")
		t:assert(#CaseConfig.Cases >= CaseConfig.PerDrawer, "mais pastas na fila que casos na lista")
	end)

	t:test("as três teclas da fila são distintas", function()
		-- Duas iguais desenham duas plaquinhas com o mesmo glifo, e uma das ações fica inalcançável.
		t:assert(CaseConfig.PrevKey ~= CaseConfig.NextKey, "retroceder e avançar na mesma tecla")
		t:assert(CaseConfig.PrevKey ~= CaseConfig.TakeKey, "retroceder e pegar na mesma tecla")
		t:assert(CaseConfig.NextKey ~= CaseConfig.TakeKey, "avançar e pegar na mesma tecla")
	end)
end
