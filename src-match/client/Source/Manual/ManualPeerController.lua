-- Caderno dos outros jogadores. Chegam dois fatos por jogador — equipado e na mão — e o resto
-- do visual é derivado aqui: quem só assiste vê o livro na cintura ou na mão com a capa aberta,
-- nunca a virada de páginas, que é do dono. O caderno do próprio jogador é do ManualController,
-- que não espera o servidor; o eco da própria pose é ignorado.
local ManualPeerController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ManualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ManualConfig"))
local ManualView = require(script.Parent:WaitForChild("ManualView"))

local player = Players.LocalPlayer

local wanted = {}
local links = {}

local function render(peer)
	local character = peer.Character
	if not character then
		return
	end
	local state = wanted[peer]
	if not state or not state.equipped then
		ManualView.Hide(character)
		return
	end
	-- Show rende esperando as partes do personagem; reler o alvo depois evita aplicar uma pose
	-- que já mudou, ou desenhar num personagem que já foi trocado.
	local view = ManualView.Show(character)
	state = wanted[peer]
	if not view or peer.Character ~= character or not state or not state.equipped then
		return
	end
	ManualView.SetPose(character, state.inHand)
end

local function watch(peer)
	if links[peer] then
		return
	end
	links[peer] = peer.CharacterAdded:Connect(function()
		render(peer)
	end)
end

local function forget(peer)
	local character = peer.Character
	if character then
		ManualView.Hide(character)
	end
	wanted[peer] = nil
	if links[peer] then
		links[peer]:Disconnect()
		links[peer] = nil
	end
end

function ManualPeerController.Start()
	local remotes = ReplicatedStorage:WaitForChild(ManualConfig.RemotesFolderName)
	local stateRemote = remotes:WaitForChild(ManualConfig.StateRemote)

	stateRemote.OnClientEvent:Connect(function(peer, equipped, inHand)
		if typeof(peer) ~= "Instance" or peer == player then
			return
		end
		wanted[peer] = { equipped = equipped, inHand = inHand }
		watch(peer)
		task.spawn(render, peer)
	end)

	Players.PlayerRemoving:Connect(forget)

	-- Sem argumento o servidor devolve o retrato de quem já está com o caderno.
	stateRemote:FireServer()
end

return ManualPeerController
