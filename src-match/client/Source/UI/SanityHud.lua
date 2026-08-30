-- Cartão de sanidade no HUD: Ico, Value e a cor de Background mostram o nível em que o jogador
-- está. O número não aparece na tela — quem olha o HUD lê a palavra, não a escala.
local SanityHud = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SanityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SanityConfig"))

-- Caminho no place: PlayerGui.MainGui.Frame_Hud.Sanity.
local GUI_NAME = "MainGui"
local HUD_NAME = "Frame_Hud"
local CARD_NAME = "Sanity"
local ICON_NAME = "Ico"
local VALUE_NAME = "Value"
local BACKGROUND_NAME = "Background"

local WAIT_TIMEOUT = 20

local function resolveCard(player)
	local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
	local gui = playerGui and playerGui:WaitForChild(GUI_NAME, WAIT_TIMEOUT)
	local hud = gui and gui:WaitForChild(HUD_NAME, WAIT_TIMEOUT)
	local card = hud and hud:WaitForChild(CARD_NAME, WAIT_TIMEOUT)

	if not card then
		warn("[SanityHud] " .. GUI_NAME .. "." .. HUD_NAME .. "." .. CARD_NAME .. " não encontrado.")
		return nil
	end

	return card,
		card:FindFirstChild(ICON_NAME),
		card:FindFirstChild(VALUE_NAME),
		card:FindFirstChild(BACKGROUND_NAME)
end

function SanityHud.Start()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local card, icon, value, background = resolveCard(player)
	if not card then
		return
	end

	local function apply()
		local level = SanityConfig.Level(SanityConfig.Read(player))

		if icon then
			icon.Image = level.Icon
		end
		if value then
			value.Text = level.Title
		end
		if background then
			background.BackgroundColor3 = level.Color
		end
	end

	player:GetAttributeChangedSignal(SanityConfig.Attribute):Connect(apply)
	apply()
end

return SanityHud
