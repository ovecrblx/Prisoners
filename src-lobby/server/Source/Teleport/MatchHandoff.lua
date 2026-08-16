-- Reserva servidor, publica o payload no MemoryStore e teleporta.
-- ReserveServerAsync devolve (accessCode, privateServerId): o payload é chaveado pelo
-- privateServerId, que é o que o Match lê em game.PrivateServerId.
local MatchHandoff = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeleportConfig"))

local MatchMap = MemoryStoreService:GetHashMap(Config.MapName)

function MatchHandoff.ReserveServerAsync(attempts)
	attempts = attempts or Config.ReserveAttempts

	if Config.MatchPlaceId == 0 then
		warn("[MatchHandoff] MatchPlaceId não configurado — reserva abortada.")
		return nil, nil
	end

	for attempt = 1, attempts do
		local ok, code, privateServerId = pcall(function()
			return TeleportService:ReserveServerAsync(Config.MatchPlaceId)
		end)

		if ok and code and privateServerId then
			return code, privateServerId
		end

		warn(string.format("[MatchHandoff] ReserveServerAsync falhou (tentativa %d/%d): %s", attempt, attempts, tostring(code)))

		if attempt < attempts then
			task.wait(attempt)
		end
	end

	return nil, nil
end

-- Falha aqui não cancela o teleporte: o Match tem fallback.
function MatchHandoff.PublishPayload(privateServerId, payload)
	local ok, err = pcall(function()
		MatchMap:SetAsync(privateServerId, payload, Config.PayloadTtl)
	end)

	if not ok then
		warn("[MatchHandoff] SetAsync do payload falhou: " .. tostring(err))
	end

	return ok
end

function MatchHandoff.Teleport(code, players, payload, attempts, stillValid)
	attempts = attempts or Config.TeleportAttempts

	-- ReservedServerAccessCode é mutuamente exclusivo com ShouldReserveServer e ServerInstanceId.
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = code
	options:SetTeleportData(payload)

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
			TeleportService:TeleportAsync(Config.MatchPlaceId, present, options)
		end)

		if ok then
			return true
		end

		warn(string.format("[MatchHandoff] TeleportAsync falhou (tentativa %d/%d): %s", attempt, attempts, tostring(err)))

		if attempt < attempts then
			task.wait(attempt)
		end
	end

	return false
end

return MatchHandoff
