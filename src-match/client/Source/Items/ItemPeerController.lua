-- Itens dos outros jogadores. Chegam três fatos por item — equipado, na mão e ligado — e o resto do
-- visual é derivado aqui: quem só assiste vê o item na cintura ou na mão, nunca a virada de páginas
-- do caderno, que é do dono. O item do próprio jogador é do controller dele, que não espera o
-- servidor; o eco da própria pose é ignorado.
local ItemPeerController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemView = require(script.Parent:WaitForChild("ItemView"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))

local player = Players.LocalPlayer

local wanted = {}
local links = {}

local function stateOf(peer, itemId)
	local byItem = wanted[peer]
	return byItem and byItem[itemId]
end

local function render(peer, itemId)
	local character = peer.Character
	if not character then
		return
	end
	local state = stateOf(peer, itemId)
	if not state or not state.equipped then
		ItemView.Hide(character, itemId)
		return
	end
	-- Show rende esperando as partes do personagem; reler o alvo depois evita aplicar uma pose que
	-- já mudou, ou desenhar num personagem que já foi trocado.
	local view = ItemView.Show(character, itemId)
	state = stateOf(peer, itemId)
	if not view or peer.Character ~= character or not state or not state.equipped then
		return
	end
	ItemView.SetPose(character, itemId, state.inHand)
	ItemView.SetPower(character, itemId, state.on)
end

local function renderAll(peer)
	local byItem = wanted[peer]
	if not byItem then
		return
	end
	for itemId in pairs(byItem) do
		task.spawn(render, peer, itemId)
	end
end

local function watch(peer)
	if links[peer] then
		return
	end
	links[peer] = peer.CharacterAdded:Connect(function()
		renderAll(peer)
	end)
end

local function forget(peer)
	local character = peer.Character
	if character then
		ItemView.HideAll(character)
	end
	wanted[peer] = nil
	if links[peer] then
		links[peer]:Disconnect()
		links[peer] = nil
	end
end

function ItemPeerController.Start()
	local remotes = ReplicatedStorage:WaitForChild(ItemConfig.RemotesFolderName)
	local stateRemote = remotes:WaitForChild(ItemConfig.StateRemote)

	stateRemote.OnClientEvent:Connect(function(peer, itemId, equipped, inHand, on)
		if typeof(peer) ~= "Instance" or peer == player or typeof(itemId) ~= "string" then
			return
		end
		local byItem = wanted[peer]
		if not byItem then
			byItem = {}
			wanted[peer] = byItem
		end
		byItem[itemId] = { equipped = equipped, inHand = inHand, on = on }
		watch(peer)
		task.spawn(render, peer, itemId)
	end)

	Players.PlayerRemoving:Connect(forget)

	-- Sem argumento o servidor devolve o retrato de quem já está com algum item.
	stateRemote:FireServer()
end

return ItemPeerController
