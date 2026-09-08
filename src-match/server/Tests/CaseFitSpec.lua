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
	local StorageConfig = t:freshRequire(ReplicatedStorage.Shared.StorageConfig)

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

	t:test("a câmera fica do lado da boca, e não atrás da gaveta", function()
		-- A capa das pastas olha para a boca. Câmera do outro lado enquadra o VERSO da fila, e o
		-- erro é mudo: a vista abre, tudo se move, e o jogador só vê pasta em branco. Basta trocar
		-- o sinal de CameraOffset.Z num ajuste.
		t:assert(
			CaseConfig.CameraOffset.Z * MOUTH.Z > 0,
			"o olho está em Z=" .. CaseConfig.CameraOffset.Z .. ", do lado do fundo"
		)
	end)

	t:test("a câmera olha para baixo, de cima da borda da gaveta", function()
		-- Abaixo da borda a vista fica rente ao móvel e a fila some atrás da frente da gaveta.
		-- Medido: 1.6 acima do centro contra 0.49 de meia-altura da caixa, e -40 graus de mergulho.
		t:assert(CaseConfig.CameraOffset.Y > DRAWER.Y / 2, "o olho tem que passar da borda da gaveta")

		local box = Instance.new("Part")
		box.CFrame = CFrame.new()
		local view = CaseConfig.View(box)
		box:Destroy()

		t:assert(view.LookVector.Y < -0.3, "a vista tem que mergulhar na gaveta, não correr rente")
	end)

	t:test("sair da gaveta é mais lento que um passo parado", function()
		-- CancelSpeed alto demais nunca cancela e a gaveta acompanha o jogador pela sala; zerado,
		-- cancela no tremor do personagem parado.
		t:assert(CaseConfig.CancelSpeed > 0, "zerado cancela sozinho")
		t:assert(CaseConfig.CancelSpeed < 1, "acima disso andar deixa de cancelar")
		t:assert(CaseConfig.SettleWait > 0, "sem janela a gaveta fecha no quadro seguinte ao prompt")
	end)

	t:test("o nome do caso chega na aba, e o carimbo da capa fica intocado", function()
		-- MEDIDO: o rótulo da aba é TextButton, e TextButton NÃO é TextLabel — as duas carregam
		-- `Text` mas são irmãs, não uma descendente da outra. A primeira versão exigia TextLabel,
		-- então nada era escrito e a pasta nascia com o texto autorado, sem erro nenhum.
		-- A aba é o alvo porque com a pasta EM PÉ é ela que a câmera enquadra de cima. O Frame_Tag
		-- da capa é o carimbo TOP SECRET e é decoração: escrever nele apaga a arte.
		local clone = template:Clone()
		local missing = CaseConfig.Dress(clone, { id = "x", name = "ALVO", photo = "rbxassetid://1" })
		local label = CaseConfig.Node(clone, CaseConfig.NamePath)
		local photo = CaseConfig.Node(clone, CaseConfig.PhotoPath)
		local tag = CaseConfig.Node(clone, CaseConfig.TagPath)
		local stamp = tag and tag:FindFirstChildWhichIsA("TextButton")
		local labelText = label and label.Text
		local image = photo and photo.Image
		local stampText = stamp and stamp.Text
		clone:Destroy()

		t:assert(#missing == 0, "o molde não entregou: " .. table.concat(missing, ", "))
		t:assertEqual(labelText, "ALVO", "nome na aba de topo")
		t:assertEqual(image, "rbxassetid://1", "retrato")
		t:assertEqual(stampText, "TOP SECRET", "o carimbo da capa não pode ser tocado")
	end)

	t:test("com a gaveta guardada a fila some dentro da caixa", function()
		-- O DEFEITO: a pose de repouso encosta a BASE da pasta no piso, e a pasta é mais alta que a
		-- caixa — então a sobra fica acima da borda SEMPRE, gaveta fechada inclusive, e atravessa o
		-- móvel. MEDIDO NO PLACE: caixa 0.9808 de altura, pasta 1.148, sobra 0.1667.
		local center, size = placed(1, CaseConfig.PerDrawer)
		local sink = CaseConfig.StowDepth(DRAWER.Y, metrics.size)
		local top = center.Position.Y + size.Y / 2 - sink
		local rim = DRAWER.Y / 2

		t:assert(top <= rim, "recolhida, a fila ainda sobra " .. string.format("%.4f", top - rim) .. " acima da borda")
		t:assert(top > rim - size.Y / 2, "a fila afundou tanto que sumiu pelo fundo da gaveta")
		t:assertNear(sink, 0.1667 + CaseConfig.StowMargin, 1e-3, "o afundamento é a sobra medida mais a folga")
	end)

	t:test("a fila não se projeta enquanto a gaveta ainda corre", function()
		-- O DEFEITO: subir junto com o curso põe a sobra da pasta dentro do móvel enquanto a gaveta
		-- sai — ela atravessa a frente antes de existir boca por onde sair. Os dois relógios partem
		-- do MESMO aviso, então a espera da fila tem que cobrir o curso inteiro da gaveta.
		t:assertEqual(
			CaseConfig.RiseProgress(StorageConfig.OpenTime - 1e-3, true),
			0,
			"a fila começou a subir com a gaveta ainda correndo"
		)
		t:assert(
			CaseConfig.RiseProgress(StorageConfig.OpenTime + CaseConfig.RiseTime, true) >= 1,
			"a fila nunca termina de subir"
		)
	end)

	t:test("a fila se recolhe antes de a gaveta bater no batente", function()
		-- O DEFEITO: recolher no mesmo tempo do fechamento deixa a pasta ainda para fora no quadro em
		-- que o móvel a engole. MEDIDO: 0.65 s de fechamento contra 0.3 s de recolhimento.
		t:assert(CaseConfig.SinkTime < StorageConfig.CloseTime, "o recolhimento acaba depois do fechamento")
		t:assertEqual(
			CaseConfig.RiseProgress(StorageConfig.CloseTime, false),
			1,
			"a fila ainda estava descendo quando a gaveta encostou"
		)
		t:assert(
			StorageConfig.CloseTime - CaseConfig.SinkTime >= 0.2,
			"a folga entre o fim do recolhimento e o batente ficou curta demais"
		)
	end)
end
