-- Preenche o cartão acima da cabeça conforme a classe equipada: com classe mostra o Title,
-- sem classe mostra o Leaderboard. Roda no servidor porque o cartão é visto por todos.
local ClassCardService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))
local OverheadCardService = require(script.Parent:WaitForChild("OverheadCardService"))

local EQUIPPED_ATTRIBUTE = "EquippedClass"

-- Com classe os dois dividem a faixa; sem classe o Leaderboard ocupa ela sozinho.
local LEADERBOARD_PAIR_SIZE = UDim2.new(1, 0, 0.25, 0)
local LEADERBOARD_ALONE_SIZE = UDim2.new(1, 0, 0.5, 0)

-- O cartão nasce em outra thread (AddAccessory no OverheadCardService).
local POLL_INTERVAL = 0.2
local POLL_TIMEOUT = 10

local warnedLayout = false

local function apply(player)
	local character = player.Character
	local card = character and OverheadCardService.GetCard(character)
	local info = card and card:FindFirstChild(Config.InfoName)
	local class = info and info:FindFirstChild(Config.ClassName)
	local leaderboard = info and info:FindFirstChild(Config.LeaderboardName)
	local image = card and card:FindFirstChild(Config.ImageName)

	if not (class and leaderboard) then
		if card and not warnedLayout then
			warnedLayout = true
			warn(("[ClassCardService] Card.%s sem %s ou %s"):format(Config.InfoName, Config.ClassName, Config.LeaderboardName))
		end
		return false
	end

	local entry = ClassConfig.Get(player:GetAttribute(EQUIPPED_ATTRIBUTE) or "")

	-- Leaderboard aparece nos dois casos; o que muda é dividir a faixa ou ocupá-la sozinho.
	class.Visible = entry ~= nil
	leaderboard.Visible = true
	leaderboard.Size = entry and LEADERBOARD_PAIR_SIZE or LEADERBOARD_ALONE_SIZE

	if entry then
		class.Text = entry.Title
	end

	if image then
		image.Visible = entry ~= nil
		if entry and entry.Icon ~= "" then
			image.Image = entry.Icon
		end
	end

	return true
end

local function applyWhenReady(player)
	local deadline = os.clock() + POLL_TIMEOUT

	while os.clock() < deadline do
		if not player:IsDescendantOf(Players) then
			return
		end
		if apply(player) then
			return
		end
		task.wait(POLL_INTERVAL)
	end
end

function ClassCardService.Start()
	local function track(player)
		player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(function()
			apply(player)
		end)

		player.CharacterAdded:Connect(function()
			task.spawn(applyWhenReady, player)
		end)

		if player.Character then
			task.spawn(applyWhenReady, player)
		end
	end

	Players.PlayerAdded:Connect(track)

	for _, player in ipairs(Players:GetPlayers()) do
		track(player)
	end
end

return ClassCardService
