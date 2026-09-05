-- Sons dos assentos do cenário e o prompt que os ocupa. Corpo dos OUTROS — NPC e demais jogadores —
-- vem pelo Occupant do assento. O jogador local vem pelo Humanoid.Seated, que dispara no quadro do
-- gesto: o Occupant só muda depois da volta do servidor, e por ele o som saía atrasado do próprio
-- movimento. O som sai preso na peça, então quem está por perto ouve.
-- O prompt é UM só, e migra para o assento mais perto: 28 assentos com prompt cada encheriam a sala
-- de teclas, e o jogador só senta em um de cada vez.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SeatConfig = require(Shared:WaitForChild("SeatConfig"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local SeatController = {}

-- Par de chaves do SfxConfig por PREFIXO do Model de assento, em minúsculas: `sec_seat` cobre tanto
-- o `Sec_Seat` quanto os `Sec_Seat_2`, `Sec_Seat_3` e os que vierem, sem uma linha por assento.
-- Model que não casa com prefixo nenhum fica mudo. Os prefixos não podem se sobrepor — a varredura
-- para no primeiro que casar, e `pairs` não tem ordem.
local SEAT_SFX = {
	sec_seat = { sit = "Sit", stand = "Stand" },
	home = { sit = "HomeSit", stand = "HomeStand" },
}

local bound = {}
local seats = {}
local prompt
local perched

-- O par vem do Model DONO do assento, não do assento: os cinco Seat de um `Home` soam igual, e o
-- nome deles é só `Seat1`..`Seat4`.
local function keysFor(part)
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local name = string.lower(model.Name)
		for prefix, keys in pairs(SEAT_SFX) do
			if string.sub(name, 1, #prefix) == prefix then
				return keys
			end
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function ensurePrompt()
	if prompt then
		return prompt
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = SeatConfig.PromptName
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.UIOffset = SeatConfig.PromptOffset
	prompt.ClickablePrompt = SeatConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = SeatConfig.PromptDistance

	prompt.Triggered:Connect(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		SeatConfig.Take(perched, humanoid)
	end)

	return prompt
end

-- O assento livre mais perto do corpo, dentro do raio de busca. Assento ocupado sai da conta: o
-- prompt em cadeira cheia oferece um lugar que não existe.
local function nearest(root)
	local best, bestDist = nil, SeatConfig.SearchRange

	for part in pairs(seats) do
		if part.Parent and not part.Occupant then
			local dist = (part.Position - root.Position).Magnitude
			if dist < bestDist then
				best, bestDist = part, dist
			end
		end
	end

	return best
end

-- O prompt muda de dono, não de existência: recriá-lo a cada passo faria o PromptShown piscar o
-- desenho a cada quarto de segundo.
local function perch()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	local wanted = if root and not humanoid.SeatPart then nearest(root) else nil

	if wanted == perched then
		return
	end
	perched = wanted

	if not wanted then
		if prompt then
			prompt.Parent = nil
		end
		return
	end

	local seatPrompt = ensurePrompt()
	seatPrompt.ObjectText = SeatConfig.Title(wanted)
	seatPrompt.Parent = wanted
end

local function bind(part)
	if seats[part] then
		return
	end
	seats[part] = true

	-- Assento que o streaming levar sai das duas tabelas: sem isto elas cresceriam a partida inteira
	-- com peça que já não existe, e a busca pelo mais perto acharia cadeira fantasma.
	part.Destroying:Once(function()
		seats[part] = nil
		local link = bound[part]
		bound[part] = nil
		if link then
			link:Disconnect()
		end
		if perched == part then
			perched = nil
		end
	end)

	-- Model sem prefixo no catálogo entra no prompt, mas fica mudo: sentar sempre é possível, o par
	-- de sons é que nem todo móvel tem.
	local keys = keysFor(part)
	if not keys then
		return
	end

	-- Quem estava sentado é guardado porque ao levantar o Occupant já vem nil, e sem isso não dá para
	-- saber se quem saiu foi o jogador local — que já soou pelo Seated, e soaria em eco aqui.
	local seated = nil
	bound[part] = part:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = part.Occupant
		local who = occupant or seated
		seated = occupant

		if who and who.Parent == Players.LocalPlayer.Character then
			return
		end
		Sfx.Play(if occupant then keys.sit else keys.stand, part)
	end)

end

-- Ao levantar, `Seated` entrega o assento como nil: o último fica guardado para o som do levantar
-- sair do lugar certo.
local function watchLocal(character)
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	local lastSeat = nil
	humanoid.Seated:Connect(function(active, part)
		local seat = part or lastSeat
		lastSeat = if active then part else nil

		local keys = seat and keysFor(seat)
		if keys then
			Sfx.Play(if active then keys.sit else keys.stand, seat)
		end
	end)
end

function SeatController.Start()
	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(watchLocal, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(watchLocal, character)
	end)

	local folder = SeatConfig.Folder(SeatConfig.FolderWait)
	if not folder then
		warn("[Seat] workspace." .. table.concat(SeatConfig.Path, ".") .. " não encontrado.")
		return
	end

	for _, item in ipairs(folder:GetDescendants()) do
		if item:IsA("Seat") then
			bind(item)
		end
	end

	-- Com streaming os assentos chegam depois da pasta, e podem ir e voltar. Evento, não varredura.
	folder.DescendantAdded:Connect(function(item)
		if item:IsA("Seat") then
			bind(item)
		end
	end)

	-- Passo largo de propósito: o prompt só troca de assento quando o jogador ANDA até outro, e por
	-- quadro seriam 28 distâncias calculadas para responder a um gesto que leva segundos.
	local since = 0
	RunService.Heartbeat:Connect(function(delta)
		since += delta
		if since < SeatConfig.SearchStep then
			return
		end
		since = 0
		perch()
	end)
end

return SeatController
