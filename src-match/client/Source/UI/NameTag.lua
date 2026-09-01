-- O nome sobre a cabeça, só na tela de quem o carrega. DisplayDistanceType None é do SUJEITO: apaga
-- o nome e a barra de vida daquele Humanoid, e não mexe na distância com que este cliente vê os
-- outros — eles seguem no modo Viewer, medidos pela distância deste personagem.
-- Escrita de propriedade no cliente não sobe para o servidor, então nas outras telas o nome fica.
-- Refeito a cada respawn: o personagem é outro Model, com outro Humanoid.
local NameTag = {}

local Players = game:GetService("Players")

local HUMANOID_WAIT = 10 -- segundos esperando o Humanoid do personagem novo

local player = Players.LocalPlayer

local function hide(character)
	local humanoid = character:WaitForChild("Humanoid", HUMANOID_WAIT)
	if not humanoid then
		warn("[NameTag] personagem sem Humanoid; o nome do dono fica na tela")
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function NameTag.Start()
	if player.Character then
		hide(player.Character)
	end
	player.CharacterAdded:Connect(hide)
end

return NameTag
