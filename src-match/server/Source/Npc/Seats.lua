--!strict
-- Os assentos do mapa: quais existem, qual está livre e como sentar e levantar. Livre é
-- `Occupant == nil`; sair é destruir o SeatWeld, que a engine parenteia no assento e não no corpo.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))

local Seats = {}

local WELD_NAME = "SeatWeld"

local warnedMissing = false

local list: { Seat } = {}
local watched: Instance? = nil
local links: { RBXScriptConnection } = {}

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

local function track(item: Instance)
	if item:IsA("Seat") then
		table.insert(list, item)
	end
end

local function untrack(item: Instance)
	if not item:IsA("Seat") then
		return
	end
	local index = table.find(list, item)
	if index then
		table.remove(list, index)
	end
end

-- Nenhum Seat é filho direto da pasta: eles moram dentro dos Models do móvel (`Home.Seat1`,
-- `Sec_Seat.Seat`), então a varredura é por descendente. Ela roda uma vez e os sinais da pasta
-- mantêm a lista — a busca é a 5 Hz POR NPC, e refazer GetDescendants ali aloca uma tabela por
-- corpo por tick. A ordem da varredura é estável, então dois NPCs no mesmo ponto empatam no mesmo.
local function seats(): { Seat }
	local root = folder()
	if not root or watched == root then
		return list
	end

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)
	table.clear(list)

	watched = root
	for _, item in ipairs(root:GetDescendants()) do
		track(item)
	end
	table.insert(links, root.DescendantAdded:Connect(track))
	table.insert(links, root.DescendantRemoving:Connect(untrack))

	return list
end

-- `Disabled` NÃO entra: o SeatService o liga em TODO assento do cenário para matar o sentar por
-- encostar, e com isso ele deixou de dizer se o lugar está vago. Medido: com ele ligado, `Seat:Sit`
-- à mão continua sentando — que é por onde o NPC e o prompt do jogador ocupam o lugar.
function Seats.IsFree(seat: Seat): boolean
	return seat.Parent ~= nil and seat.Occupant == nil
end

-- Assento livre mais próximo dentro de `radius`, ignorando os de `skip`.
function Seats.Nearest(position: Vector3, radius: number, skip: { [Instance]: boolean }?): Seat?
	local best: Seat? = nil
	local bestDistance = radius
	for _, seat in ipairs(seats()) do
		if Seats.IsFree(seat) and not (skip and skip[seat]) then
			local distance = (seat.Position - position).Magnitude
			if distance < bestDistance then
				best = seat
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
