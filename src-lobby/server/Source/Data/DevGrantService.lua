-- TEMPORÁRIO: completa o saldo de diamante de quem está na lista, para teste.
-- Apagar este arquivo quando a compra de diamante existir — nada mais depende dele.
local DevGrantService = {}

local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- UserId que recebe. Saldo abaixo de MINIMUM é completado até MINIMUM, então reentrar não
-- acumula: é piso, não bônus por sessão.
local WHITELIST = {
	[45958817] = true,
	[607476507] = true,
	[4040308] = true,
}

local MINIMUM = 90000

-- O perfil carrega em outra thread; PlayerData.Get devolve nil até lá.
local POLL_INTERVAL = 0.25
local POLL_TIMEOUT = 15

local function grant(player)
	local deadline = os.clock() + POLL_TIMEOUT
	local data = PlayerData.Get(player)

	while not data and os.clock() < deadline do
		task.wait(POLL_INTERVAL)
		if not player:IsDescendantOf(Players) then
			return
		end
		data = PlayerData.Get(player)
	end

	if not data then
		warn("[DevGrantService] perfil de " .. player.Name .. " não carregou; nada concedido")
		return
	end

	local missing = MINIMUM - (data.Gold or 0)
	if missing <= 0 then
		return
	end

	if PlayerData.AddGold(player, missing) then
		PlayerData.Flush(player)
		print(("[DevGrantService] %s (%d): +%d diamante"):format(player.Name, player.UserId, missing))
	end
end

function DevGrantService.Start()
	local function onAdded(player)
		if WHITELIST[player.UserId] then
			task.spawn(grant, player)
		end
	end

	Players.PlayerAdded:Connect(onAdded)

	for _, player in ipairs(Players:GetPlayers()) do
		onAdded(player)
	end
end

return DevGrantService
