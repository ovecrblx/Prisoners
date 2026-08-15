-- Mecanismo do handoff Lobby -> Match. Só encanamento: reserva servidor, publica o payload e
-- teleporta. Não sabe o que é party, pad ou contagem — quem orquestra isso é o
-- AreaTeleportService. Separado para o retry/backoff ficar testável sem simular um pad.
--
-- === POR QUE MEMORYSTORE, E NÃO SÓ TELEPORTDATA ===============================================
-- TeleportData chega no destino, mas é FORJÁVEL: um exploiter no lobby pode teleportar a si
-- mesmo para o place do Match com um payload inventado (papel privilegiado, party fake). O
-- Match não tem como distinguir isso de um handoff legítimo.
--
-- O MemoryStore fecha o buraco: o payload é escrito pelo SERVIDOR do lobby, sob uma chave que o
-- cliente não escolhe (o privateServerId do servidor reservado). O Match lê por
-- game.PrivateServerId — que ele mesmo observa, não recebe. Payload forjado não tem chave para
-- morar, então não é lido.
local MatchHandoff = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeleportConfig"))

local MatchMap = MemoryStoreService:GetSortedMap(Config.MapName)

-- Reserva um servidor privado no place do Match, com algumas tentativas.
--
-- ReserveServer devolve DOIS valores: (accessCode, privateServerId).
--   - accessCode      -> é o que TeleportToPrivateServer exige.
--   - privateServerId -> é o que o servidor reservado enxerga em game.PrivateServerId, e
--                        portanto a ÚNICA chave sob a qual o Match consegue buscar.
-- Capturar só o primeiro é o erro clássico: o lobby grava sob accessCode, o Match busca por
-- privateServerId, a busca nunca acerta e todo handoff degrada para o TeleportData forjável.
--
-- Retorna (nil, nil) se esgotar as tentativas.
function MatchHandoff.ReserveServer(attempts)
	attempts = attempts or Config.ReserveAttempts

	if Config.MatchPlaceId == 0 then
		warn("[MatchHandoff] MatchPlaceId não configurado — reserva abortada.")
		return nil, nil
	end

	for attempt = 1, attempts do
		local ok, code, privateServerId = pcall(function()
			return TeleportService:ReserveServer(Config.MatchPlaceId)
		end)

		if ok and code and privateServerId then
			return code, privateServerId
		end

		-- Em falha o `code` carrega a mensagem de erro do pcall, não um access code.
		warn(string.format("[MatchHandoff] ReserveServer falhou (tentativa %d/%d): %s", attempt, attempts, tostring(code)))

		if attempt < attempts then
			task.wait(attempt)
		end
	end

	return nil, nil
end

-- Publica o payload sob a chave que o Match vai ler. Falha aqui NÃO cancela o teleporte: o
-- Match tem fallback e o jogo segue degradado; travar a party por causa do MemoryStore seria
-- pior que entrar sem os dados. Retorna false para o chamador poder logar/telemetrar.
function MatchHandoff.PublishPayload(privateServerId, payload)
	local ok, err = pcall(function()
		MatchMap:SetAsync(privateServerId, payload, Config.PayloadTtl)
	end)

	if not ok then
		warn("[MatchHandoff] SetAsync do payload falhou: " .. tostring(err))
	end

	return ok
end

-- Teleporta a lista para o servidor reservado, com tentativas.
--
-- `stillValid` é revalidado ANTES de cada tentativa: durante o backoff a party pode ser
-- cancelada ou superada por uma sequência nova, e insistir teleportaria gente que já não
-- pertence àquele handoff.
--
-- Jogadores que saíram entre o snapshot e agora são filtrados a cada tentativa —
-- TeleportToPrivateServer erra a chamada inteira se receber um Player fora de Players.
function MatchHandoff.Teleport(code, players, payload, attempts, stillValid)
	attempts = attempts or Config.TeleportAttempts

	for attempt = 1, attempts do
		if stillValid and not stillValid() then
			return false
		end

		local present = {}
		for _, player in ipairs(players) do
			if player.Parent then
				table.insert(present, player)
			end
		end

		if #present == 0 then
			return false
		end

		local ok, err = pcall(function()
			TeleportService:TeleportToPrivateServer(Config.MatchPlaceId, code, present, nil, payload)
		end)

		if ok then
			return true
		end

		warn(string.format("[MatchHandoff] TeleportToPrivateServer falhou (tentativa %d/%d): %s", attempt, attempts, tostring(err)))

		if attempt < attempts then
			task.wait(attempt)
		end
	end

	return false
end

return MatchHandoff
