-- Lista de classes em Frame_Class.Hud_List. Um card clonado por registro do ClassConfig;
-- clicar troca o Rig no ClassViewer e atualiza o preço em Options.
local ClassList = {}

local Players = game:GetService("Players")
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

-- Contrato com o servidor, por atributo do Player: OwnedClasses é lista de Id separada por
-- vírgula (atributo não guarda tabela) e EquippedClass é o Id em uso. Enquanto o servidor
-- não escrever, o botão fica no estado de preço.
local OWNED_ATTRIBUTE = "OwnedClasses"
local EQUIPPED_ATTRIBUTE = "EquippedClass"

local EQUIP_TEXT = "Equip"
local UNEQUIP_TEXT = "Unequip"

-- Gradientes do botão Buy por estado. O de preço vem do place e é lido no Build.
local EQUIP_FILL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 103, 192)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(56, 160, 245)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(24, 103, 192)),
})
local EQUIP_TINT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(56, 160, 245)),
})
local UNEQUIP_FILL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 179, 0)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 242, 62)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 179, 0)),
})
local UNEQUIP_TINT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 179, 0)),
})

local player = Players.LocalPlayer

local template, list
local optionsFrame, optionsScale
local priceLabel, buyLayout, buyIco, buyFill, buyTint
local priceLook = {}
local ownedSet = {}
local equippedId
local cards = {}
local selected

function ClassList.Selected()
	return selected or ClassConfig.Default().Id
end

local function refreshOwned()
	ownedSet = {}

	local raw = player:GetAttribute(OWNED_ATTRIBUTE)
	if type(raw) == "string" then
		for id in raw:gmatch("[^,%s]+") do
			ownedSet[id] = true
		end
	end
end

-- Classe não comprada mostra o preço; comprada troca para Equip/Unequip, esconde o Ico da
-- moeda e centraliza o texto que sobrou.
local function applyBuyState()
	local entry = ClassConfig.Get(ClassList.Selected())
	if not (entry and priceLabel) then
		return
	end

	if not ownedSet[entry.Id] then
		priceLabel.Text = tostring(entry.Price)
		if buyIco then
			buyIco.Visible = priceLook.IcoVisible
		end
		if buyLayout then
			buyLayout.HorizontalAlignment = priceLook.Alignment
		end
		if buyFill then
			buyFill.Color = priceLook.Fill
		end
		if buyTint then
			buyTint.Color = priceLook.Tint
		end
		return
	end

	local equipped = equippedId == entry.Id
	priceLabel.Text = equipped and UNEQUIP_TEXT or EQUIP_TEXT

	if buyIco then
		buyIco.Visible = false
	end
	if buyLayout then
		buyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	if buyFill then
		buyFill.Color = equipped and UNEQUIP_FILL or EQUIP_FILL
	end
	if buyTint then
		buyTint.Color = equipped and UNEQUIP_TINT or EQUIP_TINT
	end
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

	selected = classId
	applyBuyState()
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
		local background = buy and buy:FindFirstChild("Background")

		priceLabel = buying and buying:FindFirstChild("TextButton")
		buyLayout = buying and buying:FindFirstChildOfClass("UIListLayout")
		buyIco = buying and buying:FindFirstChild("Ico")
		buyFill = background and background:FindFirstChildOfClass("UIGradient")
		buyTint = priceLabel and priceLabel:FindFirstChildOfClass("UIGradient")

		priceLook = {
			Alignment = buyLayout and buyLayout.HorizontalAlignment,
			IcoVisible = buyIco and buyIco.Visible,
			Fill = buyFill and buyFill.Color,
			Tint = buyTint and buyTint.Color,
		}
	end

	for _, entry in ipairs(ClassConfig.List) do
		buildCard(entry)
	end

	refreshOwned()
	equippedId = player:GetAttribute(EQUIPPED_ATTRIBUTE)

	player:GetAttributeChangedSignal(OWNED_ATTRIBUTE):Connect(function()
		refreshOwned()
		applyBuyState()
	end)

	player:GetAttributeChangedSignal(EQUIPPED_ATTRIBUTE):Connect(function()
		equippedId = player:GetAttribute(EQUIPPED_ATTRIBUTE)
		applyBuyState()
	end)

	ClassList.Select(ClassConfig.Default().Id)
end

return ClassList
