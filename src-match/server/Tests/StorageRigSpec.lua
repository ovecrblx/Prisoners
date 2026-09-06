-- StorageRigSpec — como uma gaveta descobre qual peça é a caixa e para que lado ela corre.
--
-- O QUE ESTA SPEC PROTEGE. `StorageConfig.Rig` não pode depender de nome de peça nem do centro do
-- armário, e as duas tentações são fortes: procurar por `Root` é uma linha, e medir contra o corpo
-- do armário "parece" o jeito óbvio de saber onde é fora. As duas quebram no place publicado, e
-- quebram em silêncio — o armário errado simplesmente não abre, e os outros continuam funcionando.

return function(t)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local StorageConfig = t:freshRequire(ReplicatedStorage.Shared.StorageConfig)

	-- Réplica da gaveta do place, em peças soltas e sem PrimaryPart, como ela é. Medidas reais:
	-- caixa 1.426 x 0.981 x 3.063; frente, etiqueta e puxador à frente dela em 1.549, 1.695 e 1.646.
	local function fakeDrawer(facing)
		local model = Instance.new("Model")

		local box = Instance.new("Part")
		box.Name = "MeshPart"
		box.Size = Vector3.new(1.426, 0.981, 3.063)
		box.CFrame = CFrame.new(0, 0, 0)
		box.Parent = model

		local parts = {
			{ name = "MeshPart", size = Vector3.new(1.501, 1.376, 0.145), at = 1.549 },
			{ name = "MeshPart", size = Vector3.new(0.896, 0.393, 0.002), at = 1.695 },
			{ name = "MeshPart", size = Vector3.new(0.191, 0.191, 0.095), at = 1.646 },
		}
		for _, spec in ipairs(parts) do
			local part = Instance.new("Part")
			part.Name = spec.name
			part.Size = spec.size
			part.CFrame = CFrame.new(0, 0, spec.at * facing)
			part.Parent = model
		end

		return model, box
	end

	t:test("gaveta cuja caixa não se chama Root ainda acha o trilho", function()
		-- MEDIDO NO PLACE: em Storage_1 as QUATRO peças se chamam MeshPart; só em Storage_2, 3 e 4 a
		-- caixa se chama Root. Uma versão que procurasse por nome deixaria as seis gavetas de
		-- Storage_1 sem prompt e sem curso, e o erro é mudo: os outros três armários continuam
		-- abrindo, então nada no console acusa.
		local model, box = fakeDrawer(1)
		local rig = StorageConfig.Rig(model)
		model:Destroy()

		t:assertEqual(rig.box, box, "a caixa é a de maior volume, não a primeira do GetChildren")
		t:assertNear(rig.depth, 3.063, 1e-6, "o trilho é o eixo mais longo da caixa")
	end)

	t:test("o sentido sai das peças da frente, não do centro do armário", function()
		-- MEDIDO NAS 24 GAVETAS: a soma das peças ao longo do trilho dá 4.891 studs para a frente,
		-- sempre. A diferença contra o centro do armário dá 0.079 stud — as gavetas são duas colunas,
		-- então quase toda a distância até o corpo está no eixo LATERAL, não no do trilho. Medir por
		-- ali é decidir o sentido no ruído, e o sinal vira quando não devia.
		local model = fakeDrawer(1)
		local rig = StorageConfig.Rig(model)
		model:Destroy()

		t:assertNear(rig.out.Z, 1, 1e-6, "aponta para onde estão frente, etiqueta e puxador")
	end)

	t:test("gaveta autorada virada ao contrário corre para o lado dela, não para dentro", function()
		-- Storage_3 e Storage_4 estão virados 180 graus em relação a Storage_1 e Storage_2: o mesmo
		-- eixo local Z aponta para -Z do mundo. Fixar o sentido no eixo local sem conferir onde as
		-- peças estão faria metade dos armários abrir para dentro da parede.
		local model = fakeDrawer(-1)
		local rig = StorageConfig.Rig(model)
		model:Destroy()

		t:assertNear(rig.out.Z, -1, 1e-6, "segue as peças, mesmo com o eixo local invertido")
	end)

	t:test("o curso é 70% da profundidade da caixa", function()
		-- 3.063 * 0.7 = 2.1441. Raycast de 2.74 studs à frente das quatro gavetas escolhidas não
		-- achou obstáculo: o número cabe na sala. Trocar Travel sem refazer essa medição põe gaveta
		-- dentro de móvel.
		local model = fakeDrawer(1)
		local rig = StorageConfig.Rig(model)
		model:Destroy()

		t:assertNear(rig.depth * StorageConfig.Travel, 2.1441, 1e-4, "70% de 3.063")
	end)
end
