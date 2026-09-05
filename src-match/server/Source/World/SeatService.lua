-- Desliga o sentar por encostar em todo assento do cenário. Regra de mundo, e por isso do servidor:
-- escrita no cliente não replicaria e o NPC continuaria grudando na cadeira que passasse por perto.
-- Medido: com `Disabled` ligado, o encostão não senta e o `Seat:Sit` à mão continua sentando — que é
-- por onde o prompt do cliente ocupa o lugar.
local SeatService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SeatConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeatConfig"))

local function lock(item)
	if item:IsA("Seat") or item:IsA("VehicleSeat") then
		item.Disabled = true
	end
end

function SeatService.Start()
	local folder = SeatConfig.Folder(SeatConfig.FolderWait)
	if not folder then
		warn("[Seat] workspace." .. table.concat(SeatConfig.Path, ".") .. " não encontrado.")
		return
	end

	for _, item in ipairs(folder:GetDescendants()) do
		lock(item)
	end

	folder.DescendantAdded:Connect(lock)
end

return SeatService
