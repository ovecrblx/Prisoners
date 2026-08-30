-- Dono do turno: publica o estado nos attributes do workspace e vira a página a cada
-- ShiftConfig.Duration. Era o escritor que o ShiftConfig reservava e o NpcService reclamava não
-- existir no boot.
-- Duração é teto, não piso: End() encerra antes, e é por onde uma condição de vitória futura fecha
-- o turno sem esperar o relógio.
local ShiftService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShiftConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShiftConfig"))

local number = 0
local endsAt = 0
local listeners = {}
local ticker

-- Quem quer saber que um turno começou se inscreve aqui. Roda em task.spawn: ouvinte que rende ou
-- estoura não pode segurar a virada nem derrubar os outros.
function ShiftService.OnShift(callback)
	table.insert(listeners, callback)
end

function ShiftService.Number()
	return number
end

local function advance()
	number += 1
	endsAt = workspace:GetServerTimeNow() + ShiftConfig.Duration
	ShiftConfig.Publish(true, number, endsAt)

	for _, callback in ipairs(listeners) do
		task.spawn(callback, number)
	end
end

-- Encerra o turno corrente agora e começa o próximo.
function ShiftService.End()
	advance()
end

function ShiftService.Init()
	-- Publicado no Init, antes de qualquer Start: o NpcService lê ShiftConfig.IsLive() no Start
	-- dele e não pode achar o mundo sem turno.
	number = ShiftConfig.DefaultNumber
	endsAt = workspace:GetServerTimeNow() + ShiftConfig.Duration
	ShiftConfig.Publish(true, number, endsAt)
end

function ShiftService.Start()
	for _, callback in ipairs(listeners) do
		task.spawn(callback, number)
	end

	ticker = RunService.Heartbeat:Connect(function()
		if workspace:GetServerTimeNow() < endsAt then
			return
		end
		advance()
	end)
end

function ShiftService.Stop()
	if ticker then
		ticker:Disconnect()
		ticker = nil
	end
end

return ShiftService
