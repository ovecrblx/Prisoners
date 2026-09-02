-- Crédito de turno. Quem atravessou um turno INTEIRO ganha +1 no total do perfil, e a corrida desta
-- partida sobe o recorde quando passa dele. Turno começado antes de o jogador entrar não conta.
-- Presença é o critério, não vida: quem está conectado quando o turno vira recebe.
-- Uma gravação por jogador por turno, e só quando algo mudou: o auto-save do ProfileStore é de 300s
-- e a partida dura mais que isso, então queda de servidor perderia turno já vencido.
local ShiftCreditService = {}

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerData = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("PlayerData"))
local ShiftService = require(script.Parent:WaitForChild("ShiftService"))

local joinedAt = {}
local run = {}
local shiftStartedAt = 0
local lastShift

-- Marca de tempo e não número de turno: entrar no meio do turno 1 e entrar antes dele são
-- indistinguíveis pelo número, e o primeiro não vale crédito.
local function onShift(number)
	local now = Workspace:GetServerTimeNow()

	if lastShift == nil or number <= lastShift then
		lastShift = number
		shiftStartedAt = now
		return
	end
	lastShift = number

	for _, player in ipairs(Players:GetPlayers()) do
		local since = joinedAt[player]
		if since and since <= shiftStartedAt then
			local total = (run[player] or 0) + 1
			run[player] = total

			local counted = PlayerData.AddShifts(player, 1)
			local record = PlayerData.RaiseBestShifts(player, total)
			if counted or record then
				PlayerData.Flush(player)
			end
		end
	end

	shiftStartedAt = now
end

-- Semeado com o turno corrente, não com nil: os Start correm em task.spawn e a ordem entre eles não
-- é garantida. Chegando depois do Start do ShiftService, o primeiro aviso já é uma virada, e nil
-- faria essa virada passar por boot — o primeiro turno da partida não pagaria ninguém.
function ShiftCreditService.Start()
	local now = Workspace:GetServerTimeNow()
	shiftStartedAt = now
	lastShift = ShiftService.Number()

	-- Quem já está no servidor quando isto sobe entrou antes do turno corrente começar a valer.
	for _, player in ipairs(Players:GetPlayers()) do
		joinedAt[player] = 0
	end

	Players.PlayerAdded:Connect(function(player)
		joinedAt[player] = Workspace:GetServerTimeNow()
	end)

	Players.PlayerRemoving:Connect(function(player)
		joinedAt[player] = nil
		run[player] = nil
	end)

	ShiftService.OnShift(onShift)
end

return ShiftCreditService
