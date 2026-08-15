-- Lado Match do handoff: recupera o payload que o Lobby depositou antes de teleportar.
--
-- === POR QUE NÃO LER DIRETO O TELEPORTDATA =====================================================
-- TeleportData chega junto com o jogador, mas passa pelo CLIENTE — é forjável. Alguém pode
-- teleportar-se para cá com um payload inventado e reivindicar o que quiser. Por isso a fonte de
-- verdade é o MemoryStore, escrito pelo servidor do lobby sob o privateServerId deste servidor:
-- uma chave que quem entra não escolhe e não conhece de antemão.
--
-- O fallback do TeleportData continua aqui porque perder a partida inteira por um GetAsync
-- instável é pior que rodar com dados fracos — mas ele vem marcado `Trusted = false`. Quem
-- consumir DEVE checar essa flag antes de conceder qualquer coisa que valha exploit
-- (papel privilegiado, item, moeda).
local MatchBootstrap = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeleportConfig"))

local MatchMap = MemoryStoreService:GetSortedMap(Config.MapName)

local payload = nil
local resolved = false

-- Busca no MemoryStore com retry.
--
-- O SetAsync do lobby acontece antes do teleporte, mas o MemoryStore é eventualmente
-- consistente: a primeira leitura pode voltar vazia mesmo com a escrita já aceita. Leitura
-- única aqui equivale a jogar fora uma parte das partidas.
local function fetchFromMemoryStore(privateServerId)
	for attempt = 1, Config.FetchRetries do
		local ok, data = pcall(function()
			return MatchMap:GetAsync(privateServerId)
		end)

		if ok and data then
			return data
		end

		warn(string.format("[MatchBootstrap] GetAsync sem payload (tentativa %d/%d).", attempt, Config.FetchRetries))

		if attempt < Config.FetchRetries then
			task.wait(Config.FetchRetryDelay)
		end
	end

	return nil
end

-- Último recurso: o TeleportData do primeiro jogador presente. NÃO confiável — ver o cabeçalho.
local function fetchFromTeleportData()
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)

		local data = ok and joinData and joinData.TeleportData
		if type(data) == "table" then
			warn("[MatchBootstrap] Caindo no TeleportData (forjável) — payload marcado como não confiável.")
			data.Trusted = false
			return data
		end
	end

	return nil
end

local function resolve()
	local privateServerId = game.PrivateServerId

	-- Servidor público: ninguém veio do lobby (teste no Studio, join direto). Sem payload, e
	-- isso é normal — quem consome tem que aguentar nil.
	if privateServerId == "" then
		return nil
	end

	local data = fetchFromMemoryStore(privateServerId)
	if data then
		data.Trusted = true
		return data
	end

	return fetchFromTeleportData()
end

-- Payload da partida, ou nil se este servidor não veio de um handoff.
-- Campo `Trusted`: true = veio do MemoryStore; false = TeleportData, trate como palpite.
function MatchBootstrap.GetPayload()
	return payload
end

-- Espera a resolução terminar. Serviços que dependem do payload chamam isto no Start (que roda
-- em task.spawn, então render aqui não trava o boot dos outros).
function MatchBootstrap.AwaitPayload(timeout)
	local deadline = os.clock() + (timeout or 30)

	while not resolved and os.clock() < deadline do
		task.wait(0.1)
	end

	return payload
end

function MatchBootstrap.Init()
	-- Resolve fora do Init: ele roda em série para TODOS os serviços antes de qualquer Start, e
	-- os retries do MemoryStore levam segundos. Render aqui atrasaria o boot inteiro.
	task.spawn(function()
		payload = resolve()
		resolved = true
	end)
end

return MatchBootstrap
