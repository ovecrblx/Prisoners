--!strict
-- Os assentos do mapa: quais existem, qual está livre e como sentar e levantar. Livre é
-- `Occupant == nil` e `Disabled == false`; sair é destruir o SeatWeld, que a engine parenteia no
-- assento e não no corpo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))

local Seats = {}

local WELD_NAME = "SeatWeld"

local warnedMissing = false

local function folder(): Instance?
	local current: Instance? = Workspace
	for _, name in ipairs(NpcConfig.SEAT_FOLDER) do
		current = current and current:FindFirstChild(name)
	end
	if not current and not warnedMissing then
		warnedMissing = true
		warn(string.format(
			"[Seats] pasta workspace.%s ausente; nenhum NPC senta.",
			table.concat(NpcConfig.SEAT_FOLDER, ".")
		))
	end
	return current
end

function Seats.IsFree(seat: Seat): boolean
	return seat.Parent ~= nil and not seat.Disabled and seat.Occupant == nil
end

-- Assento livre mais próximo dentro de `radius`, ignorando os de `skip`. Empate pelo nome completo
-- para dois NPCs no mesmo ponto não sortearem alvos diferentes a cada tick.
function Seats.Nearest(position: Vector3, radius: number, skip: { [Instance]: boolean }?): Seat?
	local root = folder()
	if not root then
		return nil
	end

	local best: Seat? = nil
	local bestDistance = radius
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Seat") and Seats.IsFree(child) and not (skip and skip[child]) then
			local distance = (child.Position - position).Magnitude
			if distance < bestDistance then
				best = child
				bestDistance = distance
			end
		end
	end
	return best
end

function Seats.SeatOf(agent: any): Seat?
	local part = agent.Humanoid.SeatPart
	if part and part:IsA("Seat") then
		return part
	end
	return nil
end

function Seats.Sit(agent: any, seat: Seat): boolean
	if not Seats.IsFree(seat) then
		return false
	end
	local ok = pcall(function()
		seat:Sit(agent.Humanoid)
	end)
	return ok and agent.Humanoid.SeatPart == seat
end

-- Destruir a solda é a saída documentada, e sozinha ela NÃO basta: medido neste rig, `Humanoid.Sit`
-- continua true e o corpo fica preso no estado sentado. Os três passos, na ordem.
function Seats.Stand(agent: any)
	-- Sem assento a solda não existe, mas a flag pode estar presa: zerar vale nos dois casos.
	local seat = Seats.SeatOf(agent)
	if seat then
		local weld = seat:FindFirstChild(WELD_NAME)
		if weld then
			weld:Destroy()
		end
	end
	agent.Humanoid.Sit = false
	agent.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
end

-- Sentado por qualquer caminho: SeatPart é a ponte, mas Sit sozinho já trava o resto da árvore.
function Seats.IsSeated(agent: any): boolean
	return agent.Humanoid.SeatPart ~= nil or agent.Humanoid.Sit
end

return Seats
