-- Estado dos itens equipáveis, e só isso: quem já pegou o seu, se está na mão e se está ligado.
-- Nenhum Model, junta ou tween aqui — os itens são visuais, cada cliente monta a própria réplica, e
-- o exemplar parado no cenário também é do cliente. O servidor existe para os outros clientes
-- saberem em quem desenhar o quê, para quem entra depois receber o retrato, e para devolver o item
-- a quem morreu com ele.
-- Pegou é da rodada, não da vida: morrer tira o item da vista dos outros, e o CharacterAdded
-- devolve. Só o hold no slot larga o item de volta no cenário.
local ItemService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

-- Campos que o cliente pode pedir. equipped derruba os outros dois; inHand e on só valem em item
-- equipado, então cliente que pula a coleta não acende lanterna nenhuma.
local FIELDS = { equipped = true, inHand = true, on = true }

local actionRemote
local stateRemote

local states = {}
local watched = {}
local collectListeners = {}

-- Quem quer saber que alguém pegou um item se inscreve aqui — é por onde as tasks de coleta
-- fecham. Roda em task.spawn: ouvinte que rende não pode segurar a resposta ao dono.
function ItemService.OnCollect(callback)
	table.insert(collectListeners, callback)
end

local function stateOf(player, itemId)
	local byItem = states[player]
	if not byItem then
		byItem = {}
		states[player] = byItem
	end
	local state = byItem[itemId]
	if not state then
		state = { collected = false, equipped = false, inHand = false, on = false }
		byItem[itemId] = state
	end
	return state
end

local function publish(player, itemId, state)
	stateRemote:FireAllClients(player, itemId, state.equipped, state.inHand, state.on)
end

local function setState(player, itemId, equipped, inHand, on)
	local state = stateOf(player, itemId)
	if state.equipped == equipped and state.inHand == inHand and state.on == on then
		return
	end
	state.equipped = equipped
	state.inHand = inHand
	state.on = on
	publish(player, itemId, state)
end

-- O cliente manda o valor que quer, não um "alterna": mandar o absoluto faz dois toques rápidos
-- convergirem em vez de dependerem da ordem de chegada.
local function onAction(player, itemId, field, value)
	if typeof(itemId) ~= "string" or not ItemConfig.Index(itemId) then
		return
	end
	if typeof(field) ~= "string" or not FIELDS[field] or typeof(value) ~= "boolean" then
		return
	end

	local state = stateOf(player, itemId)
	if field == "equipped" then
		local first = value and not state.collected
		state.collected = value
		setState(player, itemId, value, false, false)
		if first then
			for _, callback in ipairs(collectListeners) do
				task.spawn(callback, player, itemId)
			end
		end
		return
	end
	if not state.equipped then
		return
	end
	-- Ligado é da mão: guardar apaga, e pedido de acender com o item na cintura não passa. Sem
	-- isso um cliente deixaria os outros desenhando facho saindo do quadril dele.
	if field == "inHand" then
		setState(player, itemId, true, value, value and state.on)
	elseif state.inHand then
		setState(player, itemId, true, true, value)
	end
end

local function onRoster(player)
	for other, byItem in pairs(states) do
		if other ~= player and other.Parent then
			for itemId, state in pairs(byItem) do
				if state.equipped then
					stateRemote:FireClient(player, other, itemId, state.equipped, state.inHand, state.on)
				end
			end
		end
	end
end

function ItemService.Init()
	actionRemote = Remotes.Event(ItemConfig.ActionRemote)
	stateRemote = Remotes.Event(ItemConfig.StateRemote)

	actionRemote.OnServerEvent:Connect(onAction)
	stateRemote.OnServerEvent:Connect(onRoster)

	-- PlayerAdded e o laço abaixo podem ver o mesmo jogador; `watched` impede o CharacterAdded
	-- dobrado.
	local function onPlayer(player)
		if watched[player] then
			return
		end
		watched[player] = true
		player.CharacterAdded:Connect(function()
			local byItem = states[player]
			if not byItem then
				return
			end
			for itemId, state in pairs(byItem) do
				if state.collected then
					setState(player, itemId, true, false, false)
				end
			end
		end)
		player.CharacterRemoving:Connect(function()
			local byItem = states[player]
			if not byItem then
				return
			end
			for itemId in pairs(byItem) do
				setState(player, itemId, false, false, false)
			end
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		local byItem = states[player]
		if byItem then
			for itemId in pairs(byItem) do
				setState(player, itemId, false, false, false)
			end
		end
		states[player] = nil
		watched[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return ItemService
