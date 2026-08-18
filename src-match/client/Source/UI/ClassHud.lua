-- Cartão da classe no HUD: ImageButton recebe o ícone, Title o nome e Background a cor da
-- classe. Sem classe equipada o cartão sai da lista.
local ClassHud = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))

-- Caminho no place: PlayerGui.MainGui.Frame_Hud.Class.
local GUI_NAME = "MainGui"
local HUD_NAME = "Frame_Hud"
local CARD_NAME = "Class"
local ICON_NAME = "Ico"
local TITLE_NAME = "Title"
local BACKGROUND_NAME = "Background"

local WAIT_TIMEOUT = 20

local function resolveCard(player)
	local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
	local gui = playerGui and playerGui:WaitForChild(GUI_NAME, WAIT_TIMEOUT)
	local hud = gui and gui:WaitForChild(HUD_NAME, WAIT_TIMEOUT)
	local card = hud and hud:WaitForChild(CARD_NAME, WAIT_TIMEOUT)

	if not card then
		warn("[ClassHud] " .. GUI_NAME .. "." .. HUD_NAME .. "." .. CARD_NAME .. " não encontrado.")
		return nil
	end

	return card, card:FindFirstChild(ICON_NAME), card:FindFirstChild(TITLE_NAME), card:FindFirstChild(BACKGROUND_NAME)
end

function ClassHud.Start()
	local player = Players.LocalPlayer
	if not player then
		return
	end

	local card, icon, title, background = resolveCard(player)
	if not card then
		return
	end

	local function apply()
		local entry = ClassConfig.Get(player:GetAttribute(ClassConfig.EquippedAttribute))

		if not entry then
			card.Visible = false
			return
		end

		if icon then
			icon.Image = entry.Icon
		end
		if title then
			title.Text = entry.Title
		end
		if background then
			background.BackgroundColor3 = entry.Color
		end

		card.Visible = true
	end

	player:GetAttributeChangedSignal(ClassConfig.EquippedAttribute):Connect(apply)
	apply()
end

return ClassHud
