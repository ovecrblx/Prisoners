-- Estado do caderno, e só isso: quem já pegou o seu na mesa e se está na mão. Nenhum Model, junta
-- ou tween aqui — o caderno é visual, cada cliente monta a própria réplica, e o exemplar parado na
-- mesa também é do cliente. O servidor existe para os outros clientes saberem em quem desenhar,
-- para quem entra depois receber o retrato de quem já está em jogo, e para devolver o caderno a
-- quem morreu com ele.
local ManualService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))
local ManualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ManualConfig"))

local equipRemote
local toggleModeRemote
local unequipRemote
local stateRemote

local states = {}
local watched = {}

local function stateOf(player)
	local state = states[player]
	if not state then
		state = { collected = false, equipped = false, inHand = false }
		states[player] = state
	end
	return state
end

local function setState(player, equipped, inHand)
	local state = stateOf(player)
	if state.equipped == equipped and state.inHand == inHand then
		return
	end
	state.equipped = equipped
	state.inHand = inHand
	stateRemote:FireAllClients(player, equipped, inHand)
end

-- Coletado é da rodada, não da vida: morrer tira o caderno da vista dos outros, e o CharacterAdded
-- devolve. Só o hold no slot larga o caderno de volta na mesa.
local function onEquip(player)
	stateOf(player).collected = true
	setState(player, true, false)
end

local function onUnequip(player)
	stateOf(player).collected = false
	setState(player, false, false)
end

-- O cliente manda a pose que quer, não um "alterna": mandar o absoluto faz dois toques rápidos
-- convergirem em vez de dependerem da ordem de chegada.
local function onToggle(player, inHand)
	if typeof(inHand) ~= "boolean" then
		return
	end
	if not stateOf(player).equipped then
		return
	end
	setState(player, true, inHand)
end

local function onRoster(player)
	for other, state in pairs(states) do
		if state.equipped and other ~= player and other.Parent then
			stateRemote:FireClient(player, other, state.equipped, state.inHand)
		end
	end
end

function ManualService.Init()
	equipRemote = Remotes.Event(ManualConfig.EquipRemote)
	toggleModeRemote = Remotes.Event(ManualConfig.ToggleModeRemote)
	unequipRemote = Remotes.Event(ManualConfig.UnequipRemote)
	stateRemote = Remotes.Event(ManualConfig.StateRemote)

	equipRemote.OnServerEvent:Connect(onEquip)
	unequipRemote.OnServerEvent:Connect(onUnequip)
	toggleModeRemote.OnServerEvent:Connect(onToggle)
	stateRemote.OnServerEvent:Connect(onRoster)

	-- PlayerAdded e o laço abaixo podem ver o mesmo jogador; `watched` impede o CharacterAdded
	-- dobrado.
	local function onPlayer(player)
		if watched[player] then
			return
		end
		watched[player] = true
		player.CharacterAdded:Connect(function()
			if stateOf(player).collected then
				setState(player, true, false)
			end
		end)
		player.CharacterRemoving:Connect(function()
			setState(player, false, false)
		end)
	end

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		setState(player, false, false)
		states[player] = nil
		watched[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return ManualService
