-- OverheadCardSpec — quando o cartão acima da cabeça precisa girar, e quando não precisa.
--
-- O QUE ESTA SPEC PROTEGE. O cartão é SurfaceGui numa peça soldada à cabeça, e o cliente reescreve
-- `weld.C0` para ele encarar a câmera. Escrever é a parte cara: MEDIDO no place, 4.368 us por
-- escrita em `Weld.C0` contra 0.299 us da conta que decide se ela é necessária — 14 para 1. Com
-- `Players.MaxPlayers = 60` e todo mundo dentro do raio, escrever sem pensar são ~262 us por quadro
-- em cada cliente, e num aparelho fraco isso é vários por cento do orçamento.
--
-- A ARMADILHA. Cada recusa de `NeedsFacing` é uma que, invertida, deixa o cartão de costas para o
-- jogador sem gerar erro nenhum — ou reescreve tudo de novo e devolve o custo. O teste fixa os
-- quatro casos e o SINAL de cada comparação, que é onde um refactor troca `>=` por `>` e ninguém vê.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Config = t:freshRequire(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))

	-- Câmera na origem olhando para -Z, que é a convenção de LookVector da engine.
	local CAMERA = CFrame.new(0, 0, 0)

	-- Cartão a `distance` studs à frente da câmera, girado `degrees` para longe de encará-la.
	local function card(distance, degrees)
		local position = Vector3.new(0, 0, -distance)
		return CFrame.new(position) * CFrame.Angles(0, math.rad(180 + (degrees or 0)), 0)
	end

	t:test("cartão de costas para a câmera precisa girar", function()
		-- Sem isto o cartão nasce mostrando o verso e fica assim: a peça é transparente, o texto some
		-- de um lado só, e não há erro nenhum para investigar.
		local facingAway = CFrame.new(0, 0, -20)
		t:assert(Config.NeedsFacing(CAMERA, facingAway), "cartão virado ao contrário não seria corrigido")
	end)

	t:test("cartão já encarando a câmera não paga escrita", function()
		t:assert(not Config.NeedsFacing(CAMERA, card(20, 0)), "escreve de novo o que já está certo")
	end)

	t:test("a folga é de FacingEpsilonDegrees, e o lado de dentro dela não escreve", function()
		-- MEDIDO: 0.5 grau. Um cartão meio grau fora de esquadro a 20 studs não chega no olho, e a
		-- escrita evitada vale 14 contas. Trocar o sinal desta comparação devolve as 60 escritas por
		-- quadro sem mudar um pixel na tela — regressão de desempenho pura, invisível.
		local inside = Config.FacingEpsilonDegrees * 0.5
		local outside = Config.FacingEpsilonDegrees * 2

		t:assert(not Config.NeedsFacing(CAMERA, card(20, inside)), "girou dentro da folga e mesmo assim escreveu")
		t:assert(Config.NeedsFacing(CAMERA, card(20, outside)), "girou o dobro da folga e não foi corrigido")
	end)

	t:test("cartão atrás da câmera nunca gira", function()
		-- MEDIDO no place: a área jogável do lobby tem 43 studs de ponta a ponta e FacingRadius é 100,
		-- então o raio NÃO corta ninguém — quem corta é este teste. Numa roda de 60, metade está
		-- atrás do olho a qualquer momento, e cartão atrás não é visto por definição.
		local behind = CFrame.new(0, 0, 20)
		t:assert(not Config.NeedsFacing(CAMERA, behind), "cartão atrás da câmera pagou escrita")

		-- Exatamente no plano do olho também é invisível: aqui o sinal `>=` é o que importa.
		local onPlane = CFrame.new(30, 0, 0)
		t:assert(not Config.NeedsFacing(CAMERA, onPlane), "cartão no plano da câmera pagou escrita")
	end)

	t:test("fora do alcance de render não gira, e o limite é o mesmo do SurfaceGui", function()
		-- `FacingRadius` tem de bater com `SurfaceGui.MaxDistance` do template, que mora no PLACE e
		-- não no repo — nada além de disciplina garante isso. MEDIDO hoje: os dois valem 100.
		-- Divergiu, o cartão ou para de girar enquanto ainda aparece, ou gira invisível de graça.
		t:assertEqual(Config.FacingRadius, 100, "FacingRadius saiu de 100; confira SurfaceGui.MaxDistance no place")

		local justInside = CFrame.new(0, 0, -(Config.FacingRadius - 1))
		local justOutside = CFrame.new(0, 0, -(Config.FacingRadius + 1))
		t:assert(Config.NeedsFacing(CAMERA, justInside), "dentro do alcance e não gira")
		t:assert(not Config.NeedsFacing(CAMERA, justOutside), "fora do alcance e gira assim mesmo")
	end)

	t:test("câmera em cima do cartão não gira: o lookAt ficaria indefinido", function()
		-- Origem e alvo coincidentes não definem rotação. Sem esta recusa o giro vira NaN e o cartão
		-- some da tela — e volta sozinho no quadro seguinte, o que torna o bug quase irreproduzível.
		local onTop = CFrame.new(0, 0, 0)
		t:assert(not Config.NeedsFacing(CAMERA, onTop), "câmera em cima do cartão pagou escrita")
	end)

	t:test("a decisão não olha para a câmera do mundo, e sim para a que recebeu", function()
		-- O laço roda dentro de BindToRenderStep depois de Enum.RenderPriority.Camera, e passa a
		-- CFrame daquele quadro. Uma versão que lesse workspace.CurrentCamera por dentro ignoraria
		-- isso e voltaria a encarar a câmera do quadro anterior.
		local moved = CFrame.new(0, 0, -40) * CFrame.Angles(0, math.rad(180), 0)
		local nearMoved = card(20, 0)

		t:assert(not Config.NeedsFacing(CAMERA, nearMoved), "com a câmera na origem o cartão já encara")
		t:assert(Config.NeedsFacing(moved, nearMoved), "com a câmera do outro lado ele tem de girar")
	end)
end
