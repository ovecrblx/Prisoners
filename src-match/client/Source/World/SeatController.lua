-- Sons dos assentos do cenário, por dois sinais. Corpo dos OUTROS — NPC e demais jogadores — vem
-- pelo Occupant do assento. O jogador local vem pelo Humanoid.Seated, que dispara no quadro do
-- gesto: o Occupant só muda depois da volta do servidor, e por ele o som saía atrasado do próprio
-- movimento. O som sai preso na peça, então quem está por perto ouve.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local SeatController = {}

-- Onde os assentos vivem.
local FOLDER = { "Siland_Home", "Seats" }

-- Par de chaves do SfxConfig por PREFIXO do Model de assento, em minúsculas: `sec_seat` cobre tanto
-- o `Sec_Seat` quanto os `Sec_Seat_2`, `Sec_Seat_3` e os que vierem, sem uma linha por assento.
-- Model que não casa com prefixo nenhum fica mudo. Os prefixos não podem se sobrepor — a varredura
-- para no primeiro que casar, e `pairs` não tem ordem.
local SEAT_SFX = {
	sec_seat = { sit = "Sit", stand = "Stand" },
	home = { sit = "HomeSit", stand = "HomeStand" },
}

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

local bound = {}

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

local function bind(part)
	if bound[part] then
		return
	end

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

	-- Assento que o streaming levar solta a ligação: sem isto a tabela cresceria a partida inteira
	-- com peça que já não existe.
	part.Destroying:Once(function()
		local link = bound[part]
		bound[part] = nil
		if link then
			link:Disconnect()
		end
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

	local folder = Workspace
	for _, name in ipairs(FOLDER) do
		folder = childLike(folder, name) or folder:WaitForChild(name, FOLDER_WAIT)
		if not folder then
			warn("[Seat] workspace." .. table.concat(FOLDER, ".") .. " não encontrado.")
			return
		end
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
end

return SeatController
