-- Recupera o payload que o Lobby depositou antes do teleporte.
-- Payload.Trusted: true = MemoryStore; false = TeleportData (forjável pelo cliente).
-- nil = servidor público, não veio de handoff.
local MatchBootstrap = {}

local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeleportConfig"))

local MatchMap = MemoryStoreService:GetHashMap(Config.MapName)

local payload = nil
local resolved = false

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

local function fetchFromTeleportData()
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, joinData = pcall(function()
			return player:GetJoinData()
		end)

		local data = ok and joinData and joinData.TeleportData
		if type(data) == "table" then
			warn("[MatchBootstrap] Caindo no TeleportData — payload marcado como não confiável.")
			data.Trusted = false
			return data
		end
	end

	return nil
end

local function resolve()
	local privateServerId = game.PrivateServerId

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

function MatchBootstrap.GetPayload()
	return payload
end

function MatchBootstrap.AwaitPayload(timeout)
	local deadline = os.clock() + (timeout or 30)

	while not resolved and os.clock() < deadline do
		task.wait(0.1)
	end

	return payload
end

function MatchBootstrap.Init()
	task.spawn(function()
		payload = resolve()
		resolved = true
	end)
end

return MatchBootstrap
