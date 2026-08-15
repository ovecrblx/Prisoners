-- Persistência do jogador (lado Lobby). Dono do schema.
--
-- === UM PERFIL, DOIS PLACES ====================================================================
-- Lobby e Match usam o MESMO store e a MESMA key ("Player_"..UserId), então compartilham UM
-- perfil. Não existe sincronização entre eles: é literalmente o mesmo registro, carregado por um
-- servidor de cada vez. Isso é o que faz o Ouro ganhado na partida já estar lá quando o jogador
-- volta ao lobby — sem TeleportData de volta, sem store de retorno.
--
-- Duas consequências que mordem:
--
-- 1. SESSION LOCK A CADA TELEPORTE. Só um servidor pode ter a sessão aberta. No teleporte
--    Lobby -> Match, o lobby precisa encerrar antes do Match abrir. PlayerRemoving chama
--    EndSession, e o ProfileStore resolve o resto (é por causa disto que ele usa
--    MessagingService: acelera essa troca).
--
-- 2. COLISÃO DE CHAVE ENTRE PLACES. Reconcile só PREENCHE chave faltante — nunca troca o TIPO
--    de uma que já existe. Se o Lobby grava `Level` como tabela e o Match espera número, o
--    perfil chega com tabela e toda aritmética estoura. Por isso o Match usa nomes próprios
--    (MatchLevel/MatchXP) e só toca em campo compartilhado quando o TIPO é o mesmo dos dois
--    lados. Ver src-match/server/Source/Data/PlayerData.lua.
local PlayerData = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("Packages"):WaitForChild("ProfileStore"))

local Store

-- Store separado no Studio: teste NUNCA escreve em dado de produção. Um Reconcile com schema
-- errado, um loop de debug creditando Ouro — tudo isso fica contido no ALT_.
-- O nome tem que ser IDÊNTICO ao de src-match/server/Source/Data/PlayerData.lua; divergiu, os
-- dois places passam a ver perfis diferentes e o progresso da partida some no lobby.
local STORE_NAME = RunService:IsStudio() and "ALT_Data_Prisoners" or "Data_Prisoners"

-- === SCHEMA ====================================================================================
-- Campo novo aqui é grátis: Reconcile preenche nos perfis antigos no próximo load. Campo
-- REMOVIDO daqui continua nos perfis já salvos (Reconcile não apaga) — pense antes de adicionar,
-- porque sair é mais difícil que entrar.
--
-- Nada de userdata: Vector3, Color3, CFrame e Instance NÃO serializam. Um só desses em Data faz
-- TODO save futuro daquele perfil falhar. Serialize antes (Color3 -> :ToHex(), por exemplo).
local TEMPLATE = {
	Gold = 0,

	-- Compartilhado com o Match: mesmo nome, MESMO TIPO (número) nos dois lados. É assim que a
	-- partida credita resultado — grava aqui, o lobby lê no próximo load.
	Wins = 0,

	-- Telemetria de sessão. os.time() (UTC, segundos) — nunca tick()/os.clock(), que são
	-- relativos ao processo e viram lixo entre servidores.
	FirstJoin = 0,
	LastSeen = 0,
}

local Profiles = {}

-- Publica o Ouro como ATRIBUTO do Player, para a HUD ler sem round-trip.
--
-- REGRA: só o servidor escreve, e o servidor NUNCA lê de volta. O cliente até consegue chamar
-- SetAttribute localmente, mas isso não replica — ele engana a própria tela e nada mais. A fonte
-- da verdade é sempre profile.Data.Gold. Ler o atributo no servidor quebraria exatamente essa
-- garantia e abriria o exploit.
--
-- Atributo de Player replica para TODOS os clientes: o saldo é público. Não coloque aqui nada
-- que não possa ser.
local function publish(player, profile)
	player:SetAttribute("Gold", profile.Data.Gold or 0)
end

-- Guarda de sanidade numérica. NaN e infinito não serializam: entrando em Data, todo save
-- seguinte daquele perfil falha e o jogador perde o progresso de vez. Barrar na entrada é
-- barato; recuperar perfil envenenado, não.
local function isSafeNumber(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function onPlayerAdded(player)
	local profile = Store:StartSessionAsync("Player_" .. player.UserId, {
		-- Chamado enquanto o load está em voo. Jogador que saiu no meio não precisa mais da
		-- sessão — sem isto, ela abriria para um jogador ausente e ficaria travada até o
		-- ASSUME_DEAD, atrasando o próximo servidor que tentasse carregar esse perfil.
		Cancel = function()
			return player:IsDescendantOf(Players) == false
		end,
	})

	if not profile then
		player:Kick("Não foi possível carregar os teus dados. Tenta entrar de novo.")
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: associa o perfil ao dono
	profile:Reconcile() -- preenche o que o TEMPLATE ganhou desde o último load

	profile.OnSessionEnd:Connect(function()
		Profiles[player] = nil
		-- Sessão encerrada de fora = outro servidor assumiu o perfil. Continuar aqui gravaria
		-- em dados que já não são salvos: o jogador jogaria uma sessão fantasma. Kick é a saída
		-- honesta. (Dispara também no EndSession normal do PlayerRemoving, quando o jogador já
		-- saiu — Kick em quem não está mais no jogo é no-op.)
		player:Kick("Os teus dados foram abertos noutro servidor. Volta a entrar.")
	end)

	-- Saiu durante o load: encerra em vez de guardar. Sem isto a sessão fica aberta sem dono.
	if not player:IsDescendantOf(Players) then
		profile:EndSession()
		return
	end

	local now = os.time()
	if profile.Data.FirstJoin == 0 then
		profile.Data.FirstJoin = now
	end
	profile.Data.LastSeen = now

	Profiles[player] = profile

	-- Publica no LOAD, não só quando muda: sem isto a HUD mostra 0 até a primeira transação,
	-- inclusive o Ouro que o jogador ganhou na partida.
	publish(player, profile)
end

local function onPlayerRemoving(player)
	local profile = Profiles[player]
	if not profile then
		return
	end

	profile.Data.LastSeen = os.time()
	Profiles[player] = nil
	profile:EndSession()
end

-- Tabela VIVA do perfil, ou nil se ainda não carregou (ou já encerrou). Escrever nela persiste.
-- Todo chamador precisa aguentar o nil: o load é assíncrono e o jogador entra antes dele acabar.
function PlayerData.Get(player)
	local profile = Profiles[player]
	return profile and profile.Data or nil
end

function PlayerData.GetGold(player)
	local profile = Profiles[player]
	return profile and profile.Data.Gold or 0
end

-- Credita (ou debita, com amount negativo) Ouro. Retorna false se o perfil não estiver carregado
-- ou o valor for inválido — o chamador DEVE checar antes de entregar o item da compra.
function PlayerData.AddGold(player, amount)
	if not isSafeNumber(amount) then
		warn("[PlayerData] AddGold recusado: valor inválido (" .. tostring(amount) .. ")")
		return false
	end

	local profile = Profiles[player]
	if not profile then
		return false
	end

	profile.Data.Gold += amount
	publish(player, profile)
	return true
end

-- Grava na hora, sem esperar o auto-save (300s). Use em momento crítico — compra de DevProduct,
-- concessão paga: se o servidor cair no intervalo, o jogador pagou e não recebeu.
function PlayerData.Flush(player)
	local profile = Profiles[player]
	if profile then
		profile:Save()
	end
end

function PlayerData.Init()
	-- Erro de DataStore não deve morrer calado: sem este log, perda de dado só aparece como
	-- reclamação de jogador.
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

	-- Jogadores que entraram ANTES do Start conectar. Acontece de verdade em Studio (recarga de
	-- script) e na primeira instância de um servidor novo; sem isto, ficam para sempre sem perfil.
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return PlayerData
