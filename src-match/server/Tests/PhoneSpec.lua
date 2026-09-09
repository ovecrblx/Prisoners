-- PhoneSpec — o que some da tela de quem está no telefone.
--
-- O QUE ESTA SPEC PROTEGE. A vista da chamada é fixa em cima do teclado, e quem passar entre a
-- câmera e o aparelho tapa o visor. Sumir com o corpo alheio é escrita local, e ela tem DUAS portas
-- que não se cobrem: `LocalTransparencyModifier` apaga peça, adesivo e efeito, mas a página dela não
-- lista classe nenhuma — e MEDIDO no runtime, SurfaceGui, BillboardGui e Highlight simplesmente NÃO
-- têm a propriedade. Justamente eles: a GUI presa no corpo é o que tapa a vista.
--
-- Errar a porta é mudo dos dois lados. Classe na lista errada estoura a escrita no meio da chamada,
-- ou pior, não estoura e a peça continua na frente do visor sem nada acusar.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local PhoneConfig = t:freshRequire(ReplicatedStorage.Shared.PhoneConfig)

	-- MEDIDO no runtime, uma classe concreta por linha da lista, mais o que não é imagem.
	local SAMPLES = {
		{ class = "Part", how = "fade" },
		{ class = "MeshPart", how = "fade" },
		{ class = "Decal", how = "fade" },
		{ class = "Texture", how = "fade" },
		{ class = "Beam", how = "fade" },
		{ class = "ParticleEmitter", how = "fade" },
		{ class = "Trail", how = "fade" },
		{ class = "SurfaceGui", how = "gui" },
		{ class = "BillboardGui", how = "gui" },
		{ class = "Highlight", how = "gui" },
		{ class = "Humanoid", how = nil },
		{ class = "Motor6D", how = nil },
		{ class = "Model", how = nil },
		{ class = "Sound", how = nil },
	}

	t:test("cada classe some pela porta que ela de fato aceita", function()
		-- O DEFEITO: classe na lista errada. Em `VeilFade`, a escrita estoura no meio da chamada; em
		-- `VeilHide`, ela não estoura e a peça fica de pé na frente do visor, calada.
		for _, sample in ipairs(SAMPLES) do
			local instance = Instance.new(sample.class)
			local how = PhoneConfig.Veil(instance)

			t:assertEqual(how, sample.how, sample.class .. " saiu pela porta errada")

			if how == "fade" then
				local ok = pcall(function()
					instance.LocalTransparencyModifier = 1
				end)
				t:assert(ok, sample.class .. " não aceita LocalTransparencyModifier")
			elseif how == "gui" then
				local ok = pcall(function()
					instance.Enabled = false
				end)
				t:assert(ok, sample.class .. " não aceita Enabled")
			end

			instance:Destroy()
		end
	end)

	t:test("a GUI presa no corpo não aceita transparência local, e é por isso que ela desliga", function()
		-- É a medição que justifica a segunda porta existir. Se um dia a engine der
		-- `LocalTransparencyModifier` a SurfaceGui, este teste cai e as duas listas podem virar uma
		-- de propósito — em vez de alguém descobrir sozinho e mexer no escuro.
		for _, class in ipairs({ "SurfaceGui", "BillboardGui", "Highlight" }) do
			local instance = Instance.new(class)
			local ok = pcall(function()
				instance.LocalTransparencyModifier = 1
			end)
			instance:Destroy()

			t:assert(not ok, class .. " passou a aceitar LocalTransparencyModifier")
		end
	end)

	t:test("o corpo alheio some da imagem, nunca da simulação", function()
		-- Humanoid, junta e Model ficam de pé: o corpo continua existindo, andando e colidindo para o
		-- dono dele. Some da tela de quem está na linha, e só. Apagar o Humanoid tiraria o chão de
		-- outro jogador por causa de uma vista local.
		for _, class in ipairs({ "Humanoid", "Motor6D", "Model", "Sound", "Animator" }) do
			local instance = Instance.new(class)
			local how = PhoneConfig.Veil(instance)
			instance:Destroy()

			t:assertEqual(how, nil, class .. " entrou na lista do que some")
		end
	end)
end
