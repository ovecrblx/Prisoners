-- Lista de classes em Frame_Class.Hud_List. Um card clonado por registro do ClassConfig;
-- clicar troca o Rig no ClassViewer e atualiza o preço em Options.
local ClassList = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local ClassViewer = require(script.Parent:WaitForChild("ClassViewer"))
local Motion = require(script.Parent:WaitForChild("Motion"))

-- Cor do card selecionado: o âmbar que o place já usa na moldura do ícone.
local SELECTED_STROKE = Color3.fromRGB(255, 191, 0)
local SELECTED_THICKNESS = 4.5
local CARD_HOVER_SCALE = 1.04

-- Options mora na mesma lista dos cards e entra logo abaixo do selecionado. LayoutOrder é
-- inteiro, então o card ocupa múltiplos do passo e sobra a folga entre dois cards.
local CARD_ORDER_STEP = 10
local OPTIONS_POP_SCALE = 0.88

local template, list
local optionsFrame, optionsScale
local priceLabel, giftLabel
local cards = {}
local selected

function ClassList.Selected()
	return selected or ClassConfig.Default().Id
end

function ClassList.Select(classId)
	local entry = ClassConfig.Get(classId)
	if not (entry and cards[classId]) then
		return false
	end

	for id, card in pairs(cards) do
		if card.Stroke then
			local chosen = id == classId
			Motion.Tween(card.Stroke, Motion.Hover, {
				Color = chosen and SELECTED_STROKE or card.Color,
				Thickness = chosen and SELECTED_THICKNESS or card.Thickness,
			})
		end
	end

	if optionsFrame then
		optionsFrame.LayoutOrder = entry.Order * CARD_ORDER_STEP + 1
		optionsScale.Scale = OPTIONS_POP_SCALE
		Motion.Tween(optionsScale, Motion.Release, { Scale = 1 })
	end

	if priceLabel then
		priceLabel.Text = tostring(entry.Price)
	end
	if giftLabel then
		giftLabel.Text = string.format("Gifting (%d)", entry.Price)
	end

	selected = classId
	ClassViewer.Show(classId)
	return true
end

local function buildCard(entry)
	local card = template:Clone()
	card.Name = "Class_Card_" .. entry.Id
	card.LayoutOrder = entry.Order * CARD_ORDER_STEP
	card.Visible = true

	local profile = card:FindFirstChild("Profile")
	local title = profile and profile:FindFirstChild("Title")
	if title then
		title.Text = entry.Title
	end

	local image = profile and profile:FindFirstChild("Image")
	local icon = image and image:FindFirstChild("Icon")
	if icon and entry.Icon ~= "" then
		icon.Image = entry.Icon
	end

	local background = profile and profile:FindFirstChild("Background")
	local stroke = background and background:FindFirstChildOfClass("UIStroke")

	local buttons = {}
	for _, descendant in ipairs(card:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			buttons[#buttons + 1] = descendant
		end
	end

	Motion.BindButton(card, buttons, {
		Hover = CARD_HOVER_SCALE,
		OnClick = function()
			ClassList.Select(entry.Id)
		end,
	})

	cards[entry.Id] = {
		Frame = card,
		Stroke = stroke,
		Color = stroke and stroke.Color,
		Thickness = stroke and stroke.Thickness,
	}

	card.Parent = list
end

function ClassList.Build(panel)
	list = panel:WaitForChild("Hud_List")
	template = list:WaitForChild("Class_Card")
	template.Visible = false

	optionsFrame = list:FindFirstChild("Options")
	if optionsFrame then
		optionsScale = Motion.EnsureScale(optionsFrame)

		local buy = optionsFrame:FindFirstChild("Buy")
		local buying = buy and buy:FindFirstChild("Buying")
		priceLabel = buying and buying:FindFirstChild("TextButton")

		local gift = optionsFrame:FindFirstChild("Gift")
		local gifting = gift and gift:FindFirstChild("Gifting")
		giftLabel = gifting and gifting:FindFirstChild("TextButton")
	end

	for _, entry in ipairs(ClassConfig.List) do
		buildCard(entry)
	end

	ClassList.Select(ClassConfig.Default().Id)
end

return ClassList
