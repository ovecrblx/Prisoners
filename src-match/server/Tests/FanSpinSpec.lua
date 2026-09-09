-- FanSpinSpec — o ventilador da decoração: quem a varredura reconhece como ventilador, e o que o
-- cenário precisa ter para o giro e o laço de ambiente nascerem.
--
-- O QUE ESTA SPEC PROTEGE. O NOME do Model é o único laço entre o cenário e o controlador, e o
-- cenário é publicado à mão, sem cobertura. Quando o ventilador foi clonado e virou `Fan_1`/`Fan_2`,
-- a comparação por igualdade com "fan" parou de achar qualquer um: os dois ficaram parados e mudos.
-- O erro é o pior tipo — não há exceção, não há warn, o cômodo só fica quieto.
--
-- POR QUE ELA LÊ O PLACE. A regra do nome sozinha é opinião; ela só vale contra os nomes que estão
-- lá. A spec cruza as duas coisas: a regra do código e os Models do cenário.

return function(t)
	local StarterPlayer = game:GetService("StarterPlayer")
	local module = StarterPlayer.StarterPlayerScripts.Source.World.FanController
	local FanController = t:freshRequire(module)

	local home = workspace:FindFirstChild("Siland_Home")
	local deco = home and home:FindFirstChild("Decoration")
	t:assert(deco ~= nil, "workspace.Siland_Home.Decoration não está no place")

	local function fans()
		local list = {}

		for _, child in ipairs(deco:GetChildren()) do
			if child:IsA("Model") and FanController.IsFan(child.Name) then
				table.insert(list, child)
			end
		end

		return list
	end

	t:test("o ventilador foi clonado e virou Fan_1/Fan_2: igualdade exata não acha mais nenhum", function()
		-- MEDIDO NO PLACE: Decoration não tem mais nenhum Model chamado exatamente "Fan". Tem Fan_1 e
		-- Fan_2, mesma estrutura, 11 peças cada, uma delas a hélice `Rot`. O controlador comparava o
		-- nome por IGUALDADE, então os dois ficaram sem giro e sem o laço FanLoop.
		local exact = 0

		for _, child in ipairs(deco:GetChildren()) do
			if child:IsA("Model") and string.lower(child.Name) == "fan" then
				exact += 1
			end
		end

		local found = fans()

		t:assertEqual(exact, 0, "voltou a existir um Model chamado exatamente Fan; a medição mudou")
		t:assert(#found >= 2, "a regra do nome achou " .. #found .. " ventilador(es); o cenário tem 2")
	end)

	t:test("a regra do nome não engole vizinho que só começa com fan", function()
		-- Prefixo solto pega `Fantasma`, que é classe de NPC deste projeto: a varredura registraria o
		-- que não é ventilador e penduraria o laço de ambiente num corpo. Exigir o `_` é o que separa
		-- o clone do vizinho, e o nome puro continua valendo porque o cenário pode voltar a usá-lo.
		t:assert(FanController.IsFan("Fan_1"), "Fan_1 é ventilador")
		t:assert(FanController.IsFan("Fan_12"), "o sufixo não é de um dígito só")
		t:assert(FanController.IsFan("fan"), "o nome antigo continua valendo")
		t:assert(not FanController.IsFan("Fantasma"), "Fantasma é classe de NPC, não ventilador")
		t:assert(not FanController.IsFan("Fancy"), "prefixo sem o _ pega qualquer coisa que comece com fan")
	end)

	t:test("cada ventilador tem a hélice dele, senão o laço nasce num só", function()
		-- O `FanLoop` é pendurado NA hélice e a atenuação é por peça: ventilador sem `Rot` fica parado
		-- e mudo, e o som do vizinho não cobre o buraco. MEDIDO: a hélice é MeshPart 2.212 x 2.166 x
		-- 1.268, igual nos dois.
		for _, fan in ipairs(fans()) do
			local rotor

			for _, part in ipairs(fan:GetChildren()) do
				if string.lower(part.Name) == "rot" then
					rotor = part
				end
			end

			t:assert(rotor ~= nil, fan.Name .. " está sem a hélice Rot")
			t:assert(rotor:IsA("BasePart"), fan.Name .. ".Rot não é peça: " .. rotor.ClassName)
		end
	end)
end
