-- Contrato das gavetas dos armários, lido pelo servidor e pelo cliente. O servidor publica se a
-- gaveta está fora e cria o prompt; o cliente usa os mesmos números para correr o trilho.
local StorageConfig = {}

StorageConfig.Path = { "Siland_Home", "interactive" }
StorageConfig.FolderWait = 20

-- Gaveta que abre, uma linha por gaveta. Cada armário tem seis; o que não está aqui fica fechado e
-- sem prompt. Model do armário, depois o Model da gaveta dentro dele.
StorageConfig.Drawers = {
	{ storage = "Storage_1", drawer = "D3" },
	{ storage = "Storage_2", drawer = "D3" },
	{ storage = "Storage_3", drawer = "D6" },
	{ storage = "Storage_4", drawer = "D4" },
}

-- Estado publicado pelo servidor, no Model da GAVETA: o armário tem seis, e o atributo nele faria
-- as seis dividirem o mesmo aberto/fechado.
StorageConfig.OpenAttribute = "Open"

-- Uso exclusivo, como o telefone e o posto do monitor: uma gaveta é de um jogador de cada vez. O
-- servidor guarda o dono e publica o UserId dele; 0 é livre. Enquanto tem dono o prompt some, então
-- ninguém disputa a fila de pastas por cima de quem já está nela.
-- Sair é do cliente, porque o gatilho é ANDAR e só ele vê isso no quadro do passo — mas quem escreve
-- o estado é sempre o servidor, e pedido de quem não é dono não passa.
StorageConfig.UserAttribute = "User"
StorageConfig.LeaveRemote = "DrawerLeave"

-- Fração da profundidade da caixa que sai do armário. 1 seria a gaveta inteira fora do trilho.
StorageConfig.Travel = 0.7

-- Sair é o gesto de quem puxa, e para na frente; voltar é empurrão que termina no batente. Os dois
-- tempos são os do som: a batida gravada tem que cair no quadro em que a gaveta encosta.
StorageConfig.OpenTime = 0.8
StorageConfig.OpenStyle = Enum.EasingStyle.Quint
StorageConfig.OpenDirection = Enum.EasingDirection.Out
StorageConfig.CloseTime = 0.65
StorageConfig.CloseStyle = Enum.EasingStyle.Quad
StorageConfig.CloseDirection = Enum.EasingDirection.In

-- Style Custom, como todo prompt do projeto: quem desenha é o PromptDisplay. Clicável só no toque —
-- no PC o alvo de clique cobre o prompt e engole o arrasto do mouse.
StorageConfig.PromptTitle = "Drawer"
StorageConfig.PromptDistance = 8
StorageConfig.PromptOffset = Vector2.new(0, 40)
StorageConfig.PromptClickable = false
StorageConfig.PromptAnchor = "PromptAnchor"

-- Studs que a âncora do prompt avança da face da frente para fora. A engine só mostra o prompt com
-- caminho livre da câmera até ele, e o miolo da caixa fica DENTRO do armário.
StorageConfig.PromptDepth = 0.4

local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }

function StorageConfig.Find(folder, spec)
	local storage = folder:FindFirstChild(spec.storage)
	local model = storage and storage:FindFirstChild(spec.drawer)
	return if model and model:IsA("Model") then model else nil
end

-- A gaveta é um Model de peças soltas, sem PrimaryPart e sem nome garantido: em Storage_1 as quatro
-- se chamam MeshPart, nos outros três a caixa se chama Root. A caixa é a de maior volume, e o eixo
-- mais longo dela é o do trilho. O sentido sai da frente, do puxador e da etiqueta, que ficam todos
-- do lado de fora: medido nas 24 gavetas, a soma dá 4,89 studs para a frente, nunca perto de zero.
-- O centro do armário não serve de referência: as gavetas são duas colunas, e a diferença ao longo
-- do trilho é de 0,08 stud.
function StorageConfig.Rig(model)
	local box, volume
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") then
			local size = part.Size
			local mass = size.X * size.Y * size.Z
			if not volume or mass > volume then
				box, volume = part, mass
			end
		end
	end

	if not box then
		return nil
	end

	local size = box.Size
	local axis, depth = AXES[1], size.X
	if size.Y > depth then
		axis, depth = AXES[2], size.Y
	end
	if size.Z > depth then
		axis, depth = AXES[3], size.Z
	end

	local lead = 0
	local out = box.CFrame:VectorToWorldSpace(axis)
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= box then
			lead += (part.Position - box.Position):Dot(out)
		end
	end

	if lead < 0 then
		axis, out = -axis, -out
	end

	return { box = box, axis = axis, out = out, depth = depth, height = size.Y }
end

return StorageConfig
