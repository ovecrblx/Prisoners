-- Persistência do jogador (lado Match). NÃO é dono do schema — o Lobby é.
--
-- === O MESMO PERFIL DO LOBBY ===================================================================
-- Mesmo STORE_NAME, mesma key ("Player_"..UserId): este place carrega LITERALMENTE o mesmo
-- registro que o lobby carregou. Não há cópia nem sincronização. Gravar `Wins` aqui já é o
-- handoff de volta — quando o jogador retorna ao lobby, o valor está lá.
--
-- Isso substitui o canal TeleportData de volta, que era forjável: um cliente podia anunciar
-- "ganhei 1e9" na volta e virar top do ranking. Aqui só o servidor da partida escreve.
--
-- === A REGRA QUE MAIS DÓI: COLISÃO DE CHAVE ====================================================
-- Reconcile PREENCHE chave faltante; NUNCA troca o tipo de uma que já existe. Então, se o Lobby
-- um dia gravar `Level` como TABELA (nível por item, por exemplo) e este place tratar `Level`
-- como NÚMERO, o perfil chega com tabela e toda aritmética estoura — em produção, no perfil de
-- quem já passou pelo lobby, e não no seu teste com perfil novo.
--
-- Daí a convenção: campo que é só desta place ganha prefixo `Match`. Campo compartilhado só
-- entra se tiver o MESMO NOME e o MESMO TIPO nos dois lados.
local PlayerData = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local Store

-- IDÊNTICO ao de src-lobby/server/Source/Data/PlayerData.lua. Divergiu, os dois places veem
-- perfis diferentes e o progresso da partida nunca aparece no lobby. São árvores independentes:
-- não há import cruzado que garanta isso, só disciplina.
local STORE_NAME = RunService:IsStudio() and "ALT_Data_Prisoners" or "Data_Prisoners"

-- Só o que ESTA place possui. `Gold` e `Wins` NÃO entram aqui: pertencem ao schema do lobby, e
-- este place os lê/incrementa com (or 0) para o caso de um perfil que nunca passou por lá.
local TEMPLATE = {
	MatchLevel = 1,
	MatchXP = 0,
}

local Profiles = {}

local function isSafeNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function onPlayerAdded(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player:IsDescendantOf(Players) == false
		end,
	})

	if not profile then
		player:Kick("Não foi possível carregar os teus dados. Tenta entrar de novo.")
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		player:Kick("Os teus dados foram abertos noutro servidor. Volta a entrar.")
	end)

	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		return
	end

	Profiles[player] = profile
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if not profile then
		return
	end

	Profiles[player] = nil
	profile:EndSession()
end

function PlayerData.Get(player)
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

-- Credita vitória no campo COMPARTILHADO. Autoritativo: só o servidor da partida chama, no fim
-- do jogo. `Wins` pertence ao schema do lobby, então num perfil que nunca passou por lá chega
-- nil — daí o (or 0).
function PlayerData.AddWins(player, amount)
	if not isSafeNumber(amount) or amount <= 0 then
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Wins = (profile.Data.Wins or 0) + amount
	return true
end

-- Credita Ouro no campo COMPARTILHADO (mesmo nome e tipo do lobby). É o que faz o jogador voltar
-- ao lobby já com o que ganhou na partida.
function PlayerData.AddGold(player, amount)
	if not isSafeNumber(amount) then
		warn("[PlayerData] AddGold recusado: valor inválido (" .. tostring(amount) .. ")")
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Gold = (profile.Data.Gold or 0) + amount
	return true
end

function PlayerData.AddXP(player, amount)
	if not isSafeNumber(amount) or amount <= 0 then
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.MatchXP += amount
	return true
end

-- Grava na hora, sem esperar o auto-save (300s). Chame no FIM DA PARTIDA: o teleporte de volta
-- ao lobby vem logo depois, e o que não foi salvo até o EndSession ainda depende do encerramento
-- limpo. Um crash do servidor no meio perde o resultado inteiro.
function PlayerData.Flush(player)
	local profile = Profiles[player]
	if profile then
		profile:Save()
	end
end

function PlayerData.Init()
	ProfileStore.OnError:Connect(function(message, storeName, profileKey)
		warn(string.format("[PlayerData] DataStore falhou (%s / %s): %s", tostring(storeName), tostring(profileKey), tostring(message)))
	end)

	Store = ProfileStore.New(STORE_NAME, TEMPLATE)
end

function PlayerData.Start()
	if not Store then
		warn("[PlayerData] Store não inicializado — Init não rodou.")
		return
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)

	Players.PlayerRemoving:Connect(onPlayerRemoving)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerData
