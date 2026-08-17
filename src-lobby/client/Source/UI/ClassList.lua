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

-- Pasta que o ClassPriceService publica: atributo por Id, valor em Robux. Enquanto não
-- chega, o botão mostra o traço em vez de um número que não é o preço real.
local PRICE_FOLDER = "ClassPrices"
local ROBUX_UNKNOWN = "—"

-- Remote do ClassService: (action, classId). O servidor confere preço, saldo e posse.
local REMOTE_FOLDER = "Remotes"
local ACTION_EVENT = "ClassAction"

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

-- Contorno do Background acompanha o gradiente. O UIStroke do texto fica de fora: é o
-- contorno preto de legibilidade.
local EQUIP_STROKE = Color3.fromRGB(56, 160, 245)
local UNEQUIP_STROKE = Color3.fromRGB(255, 196, 0)

local player = Players.LocalPlayer

local template, list
local optionsFrame, optionsScale
local dimaLabel, dimaLayout, dimaIco, dimaFill, dimaTint, dimaStroke
local robuxLabel, priceFolder, actionEvent
local dimaLook = {}
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

-- Só o botão de diamante muda de estado. O de Robux segue no preço mesmo com a classe
-- comprada: é a referência de valor para presentear outro jogador.
local function applyBuyState()
	local entry = ClassConfig.Get(ClassList.Selected())
	if not entry then
		return
	end

	if robuxLabel then
		local robux = priceFolder and priceFolder:GetAttribute(entry.Id)
		robuxLabel.Text = robux and tostring(robux) or ROBUX_UNKNOWN
	end

	if not dimaLabel then
		return
	end

	if not ownedSet[entry.Id] then
		dimaLabel.Text = tostring(entry.Price)
		if dimaIco then
			dimaIco.Visible = dimaLook.IcoVisible
		end
		if dimaLayout then
			dimaLayout.HorizontalAlignment = dimaLook.Alignment
		end
		if dimaFill then
			dimaFill.Color = dimaLook.Fill
		end
		if dimaTint then
			dimaTint.Color = dimaLook.Tint
		end
		if dimaStroke then
			Motion.Tween(dimaStroke, Motion.Hover, { Color = dimaLook.Stroke })
		end
		return
	end

	local equipped = equippedId == entry.Id
	dimaLabel.Text = equipped and UNEQUIP_TEXT or EQUIP_TEXT

	if dimaIco then
		dimaIco.Visible = false
	end
	if dimaLayout then
		dimaLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end
	if dimaFill then
		dimaFill.Color = equipped and UNEQUIP_FILL or EQUIP_FILL
	end
	if dimaTint then
		dimaTint.Color = equipped and UNEQUIP_TINT or EQUIP_TINT
	end
	if dimaStroke then
		Motion.Tween(dimaStroke, Motion.Hover, { Color = equipped and UNEQUIP_STROKE or EQUIP_STROKE })
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

-- O botão de diamante é um só: o que ele faz depende do estado que está exibindo.
local function requestDimaAction()
	local entry = ClassConfig.Get(ClassList.Selected())
	if not (entry and actionEvent) then
		return
	end

	if not ownedSet[entry.Id] then
		actionEvent:FireServer("Buy", entry.Id)
	elseif equippedId == entry.Id then
		actionEvent:FireServer("Unequip")
	else
		actionEvent:FireServer("Equip", entry.Id)
	end
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

		local dima = optionsFrame:FindFirstChild("Buy_Dima")
		local dimaInner = dima and dima:FindFirstChild("Buying")
		local dimaBackground = dima and dima:FindFirstChild("Background")

		dimaLabel = dimaInner and dimaInner:FindFirstChild("TextButton")
		dimaLayout = dimaInner and dimaInner:FindFirstChildOfClass("UIListLayout")
		dimaIco = dimaInner and dimaInner:FindFirstChild("Ico")
		dimaFill = dimaBackground and dimaBackground:FindFirstChildOfClass("UIGradient")
		dimaTint = dimaLabel and dimaLabel:FindFirstChildOfClass("UIGradient")
		dimaStroke = dimaBackground and dimaBackground:FindFirstChildOfClass("UIStroke")

		dimaLook = {
			Alignment = dimaLayout and dimaLayout.HorizontalAlignment,
			IcoVisible = dimaIco and dimaIco.Visible,
			Fill = dimaFill and dimaFill.Color,
			Tint = dimaTint and dimaTint.Color,
			Stroke = dimaStroke and dimaStroke.Color,
		}

		local robux = optionsFrame:FindFirstChild("Buy_Rbx")
		local robuxInner = robux and robux:FindFirstChild("Buying")
		robuxLabel = robuxInner and robuxInner:FindFirstChild("TextButton")

		if not (dimaLabel and robuxLabel) then
			warn("[ClassList] Options sem Buy_Dima.Buying.TextButton ou Buy_Rbx.Buying.TextButton.")
		end

		if dima then
			local buttons = {}
			for _, descendant in ipairs(dima:GetDescendants()) do
				if descendant:IsA("GuiButton") then
					buttons[#buttons + 1] = descendant
				end
			end
			Motion.BindButton(dima, buttons, { OnClick = requestDimaAction })
		end
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

	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(REMOTE_FOLDER, 30)
		actionEvent = remotes and remotes:WaitForChild(ACTION_EVENT, 30)

		if not actionEvent then
			warn("[ClassList] " .. REMOTE_FOLDER .. "." .. ACTION_EVENT .. " não apareceu; comprar e equipar ficam inertes.")
		end
	end)

	-- A pasta nasce no Init do servidor e os preços chegam depois, um por consulta.
	task.spawn(function()
		priceFolder = ReplicatedStorage:WaitForChild(PRICE_FOLDER, 30)
		if not priceFolder then
			warn("[ClassList] ReplicatedStorage." .. PRICE_FOLDER .. " não apareceu; preço em Robux fica vazio.")
			return
		end

		priceFolder.AttributeChanged:Connect(applyBuyState)
		applyBuyState()
	end)

	ClassList.Select(ClassConfig.Default().Id)
end

return ClassList
