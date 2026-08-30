-- Dono da sanidade: guarda o número por jogador e publica no attribute que o HUD lê. Nada no jogo
-- move o valor sozinho — Task e evento chamam Add ou Set, e é essa a única porta enquanto não
-- existe fonte automática.
-- Sanidade é estado de rodada, não de vida: morrer não devolve o que se perdeu, e só Reset devolve.
local SanityService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SanityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SanityConfig"))

local values = {}
local listeners = {}

-- Quem quer saber que a sanidade mudou se inscreve aqui. Roda em task.spawn: ouvinte que rende ou
-- estoura não segura quem mudou o valor nem derruba os outros.
function SanityService.OnChanged(callback)
	table.insert(listeners, callback)
end

function SanityService.Get(player)
	return values[player] or SanityConfig.Start
end

function SanityService.Set(player, value)
	local wanted = SanityConfig.Clamp(value)
	if values[player] == wanted then
		return wanted
	end

	values[player] = wanted
	player:SetAttribute(SanityConfig.Attribute, wanted)

	for _, callback in ipairs(listeners) do
		task.spawn(callback, player, wanted)
	end
	return wanted
end

function SanityService.Add(player, delta)
	return SanityService.Set(player, SanityService.Get(player) + delta)
end

function SanityService.Reset(player)
	return SanityService.Set(player, SanityConfig.Start)
end

function SanityService.Level(player)
	return SanityConfig.Level(SanityService.Get(player))
end

function SanityService.Init()
	local function onPlayer(player)
		SanityService.Set(player, SanityConfig.Start)
	end

	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		values[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return SanityService
