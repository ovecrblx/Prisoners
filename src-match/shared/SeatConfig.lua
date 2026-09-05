-- Assentos do cenário. Sentar por ENCOSTAR saiu do jogo: atravessar a sala correndo grudava o
-- jogador na primeira cadeira do caminho, e numa fuga isso decide a partida. Quem senta agora é o
-- prompt, e o prompt é um só — o do assento mais perto de quem está olhando.
-- O servidor desliga o toque, porque é regra de mundo e vale para NPC também; o prompt é do cliente,
-- porque "mais perto" só existe em relação a um jogador.
local SeatConfig = {}

SeatConfig.Path = { "Siland_Home", "Seats" }

-- Style Custom, como todo prompt do projeto: quem desenha é o PromptDisplay.
SeatConfig.PromptName = "SeatPrompt"
SeatConfig.PromptDistance = 8
SeatConfig.PromptOffset = Vector2.new(0, 40)
SeatConfig.PromptClickable = false

-- studs de raio da busca pelo assento mais perto, e s entre duas buscas. O raio é maior que a
-- distância do prompt para o assento já estar escolhido quando o jogador entra no alcance dele.
SeatConfig.SearchRange = 14
SeatConfig.SearchStep = 0.25

-- studs entre o corpo e o assento que ainda contam como ter chegado. O caminho pode parar curto por
-- esbarrão, e exigir o ponto exato deixaria o jogador de pé ao lado da cadeira.
SeatConfig.SitRange = 6

-- Título por PREFIXO do Model dono, em minúsculas — mesma regra do som do assento. O prefixo mais
-- longo ganha, então `sec_seat` não é engolido por um `sec` que venha a existir.
SeatConfig.Titles = {
	sec_seat = "Chair",
	home = "Couch",
}
SeatConfig.DefaultTitle = "Chair"

SeatConfig.FolderWait = 20

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
local function childLike(parent, name)
	local wanted = string.lower(name)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

function SeatConfig.Folder(timeout)
	local node = workspace

	for _, name in ipairs(SeatConfig.Path) do
		node = childLike(node, name) or node:WaitForChild(name, timeout)
		if not node then
			return nil
		end
	end

	return node
end

-- O assento de um Model nomeado, para quem tem posto fixo: o monitor e o telefone.
function SeatConfig.Find(name, timeout)
	local folder = SeatConfig.Folder(timeout)
	local model = folder and childLike(folder, name)
	return model and model:FindFirstChildWhichIsA("Seat", true)
end

-- O título vem do Model DONO, não do assento: os cinco Seat de um `Home` são o mesmo móvel, e o
-- nome deles é só `Seat1`..`Seat4`.
function SeatConfig.Title(seat)
	local model = seat:FindFirstAncestorOfClass("Model")

	while model do
		local name = string.lower(model.Name)
		local best, bestLength = nil, 0
		for prefix, title in pairs(SeatConfig.Titles) do
			if #prefix > bestLength and string.sub(name, 1, #prefix) == prefix then
				best, bestLength = title, #prefix
			end
		end
		if best then
			return best
		end
		model = model:FindFirstAncestorOfClass("Model")
	end

	return SeatConfig.DefaultTitle
end

-- Ocupar um assento: anda até ele e senta À MÃO. Com o toque desligado o MoveTo sozinho já não
-- senta ninguém, e `reached` é o que separa ter chegado de o caminho ter vencido o prazo — sem ele,
-- quem desistisse e saísse andando seria puxado para a cadeira 8s depois.
function SeatConfig.Take(seat, humanoid)
	if not (seat and humanoid) or humanoid.SeatPart == seat or humanoid.Health <= 0 then
		return
	end

	humanoid:MoveTo(seat.Position)
	humanoid.MoveToFinished:Once(function(reached)
		local root = humanoid.RootPart
		if not (reached and root and seat.Parent) or seat.Occupant or humanoid.Health <= 0 then
			return
		end
		if (root.Position - seat.Position).Magnitude <= SeatConfig.SitRange then
			seat:Sit(humanoid)
		end
	end)
end

return SeatConfig
