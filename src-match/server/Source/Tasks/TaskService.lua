-- Sorteio e histórico das tasks, por jogador. A cada turno cada um recebe até
-- TaskConfig.DrawPerShift tasks tiradas do que ainda não fez; quando não sobra o que sortear, o
-- histórico do ciclo zera e as Loop voltam ao monte. As Canon feitas ficam de fora para sempre.
-- O monte é de cada jogador porque task de classe só existe contra a classe de alguém — o mesmo
-- turno entrega listas diferentes para funções diferentes.
-- Quem cumpre a task não é este módulo: os serviços donos de cada gatilho avisam, e aqui só se
-- decide o que isso conclui.
local TaskService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemService = require(script.Parent.Parent:WaitForChild("Items"):WaitForChild("ItemService"))
local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))
local ShiftService = require(script.Parent.Parent:WaitForChild("Shift"):WaitForChild("ShiftService"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassConfig = require(Shared:WaitForChild("ClassConfig"))
local TaskConfig = require(Shared:WaitForChild("TaskConfig"))

local rng = Random.new()

local stateRemote
local states = {}

local function stateOf(player)
	local state = states[player]
	if not state then
		state = { done = {}, retired = {}, active = {}, order = {}, shift = 0 }
		states[player] = state
	end
	return state
end

local function publish(player)
	local state = states[player]
	if not (state and player.Parent) then
		return
	end
	local payload = {}
	for _, id in ipairs(state.order) do
		table.insert(payload, { Id = id, Done = not state.active[id] })
	end
	stateRemote:FireClient(player, payload)
end

local function candidates(state, classId)
	local pool = {}
	for _, entry in ipairs(TaskConfig.List) do
		if
			TaskConfig.IsDrawable(entry)
			and TaskConfig.Allows(entry, classId)
			and not state.retired[entry.Id]
			and not state.done[entry.Id]
			and not state.active[entry.Id]
		then
			table.insert(pool, entry)
		end
	end
	return pool
end

-- `recycled` corta o laço em partida cujo monte inteiro já é Canon feita: sem ele, zerar um
-- histórico que não devolve nada giraria para sempre.
local function draw(player, shift)
	local state = stateOf(player)
	if state.shift == shift then
		return
	end
	state.shift = shift
	table.clear(state.active)
	table.clear(state.order)

	local classId = player:GetAttribute(ClassConfig.EquippedAttribute)
	local pool = candidates(state, classId)
	local recycled = false

	while #state.order < TaskConfig.DrawPerShift do
		if #pool == 0 then
			if recycled then
				break
			end
			recycled = true
			table.clear(state.done)
			pool = candidates(state, classId)
			if #pool == 0 then
				break
			end
		end
		local entry = table.remove(pool, rng:NextInteger(1, #pool))
		state.active[entry.Id] = true
		table.insert(state.order, entry.Id)
	end

	publish(player)
end

local function complete(player, taskId)
	local state = states[player]
	if not (state and state.active[taskId]) then
		return
	end
	local entry = TaskConfig.Get(taskId)
	if not entry then
		return
	end

	state.active[taskId] = nil
	state.done[taskId] = true
	if TaskConfig.IsPermanent(entry) then
		state.retired[taskId] = true
	end
	publish(player)
end

-- Entrega fora do sorteio, para as Event: quem dispara o evento chama, e a task entra no turno
-- corrente como qualquer outra.
function TaskService.Give(player, taskId)
	local entry = TaskConfig.Get(taskId)
	local state = states[player]
	if not (entry and state) or state.active[taskId] then
		return
	end
	state.active[taskId] = true
	table.insert(state.order, taskId)
	publish(player)
end

function TaskService.Complete(player, taskId)
	complete(player, taskId)
end

local function onTrigger(player, triggerType, key)
	local state = states[player]
	if not state then
		return
	end
	for _, id in ipairs(state.order) do
		if state.active[id] then
			local entry = TaskConfig.Get(id)
			local trigger = entry and entry.Trigger
			if trigger and trigger.Type == triggerType and trigger.ItemId == key then
				complete(player, id)
			end
		end
	end
end

-- A classe é escrita no spawn, depois do PlayerAdded: quem entra sem ela ainda não pode receber
-- task de classe, e sairia do turno de mãos vazias. Só o sorteio vazio é refeito — lista boa não
-- se re-sorteia no meio do turno por troca de classe.
local function watchClass(player)
	player:GetAttributeChangedSignal(ClassConfig.EquippedAttribute):Connect(function()
		local state = states[player]
		if state and #state.order == 0 then
			state.shift = 0
			draw(player, ShiftService.Number())
		end
	end)
end

function TaskService.Init()
	stateRemote = Remotes.Event(TaskConfig.StateRemote)

	-- O pedido de retrato também semeia: cliente que chega antes do PlayerAdded daqui não fica
	-- sem lista até a virada do turno.
	stateRemote.OnServerEvent:Connect(function(player)
		draw(player, ShiftService.Number())
		publish(player)
	end)

	ItemService.OnCollect(function(player, itemId)
		onTrigger(player, TaskConfig.Trigger.CollectItem, itemId)
	end)

	ShiftService.OnShift(function(shift)
		for _, player in ipairs(Players:GetPlayers()) do
			draw(player, shift)
		end
	end)

	-- Quem chega no meio do turno recebe a lista do turno corrente, não a do próximo.
	local function onPlayer(player)
		watchClass(player)
		draw(player, ShiftService.Number())
	end

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return TaskService
