-- Os slots dos itens no HUD. O template é o ImageButton dentro de HudGui.Hud: Press leva a
-- imagem do item, Key o rótulo da tecla, Fill o progresso do hold. O template fica invisível; cada
-- item é um clone, na ordem de ItemConfig.Order — que é também a das teclas.
-- Toque no slot ou na tecla alterna cintura/mão; segurar por HoldTime devolve o item ao cenário. A
-- GUI liga quando o primeiro slot aparece, desliga quando o último sai, e fica desligada enquanto
-- alguma cena a bloquear — sentar e a chamada no telefone são as de hoje.
local ItemHud = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ItemConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ItemConfig"))
local ItemHold = require(script.Parent:WaitForChild("ItemHold"))

local GUI_TIMEOUT = 10 -- segundos esperando a GUI publicada no PlayerGui
local FILL_HIDDEN = UDim2.fromScale(0, 0)
local FILL_FULL = UDim2.fromScale(1, 1)
local FILL_RESET_TIME = 0.2 -- segundos para o Fill recuar em hold cancelado

local player = Players.LocalPlayer

local gui, hud, template
local slots = {}
local keyLink
local blocks = {}

local Slot = {}
Slot.__index = Slot

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function anyVisible()
	for _, slot in pairs(slots) do
		if slot.visible then
			return true
		end
	end
	return false
end

-- Cena que toma o jogador leva a GUI inteira: sentar, e a chamada no telefone. Cada uma some com a
-- própria chave e a GUI só volta quando a última sair — dois donos escrevendo `Enabled` direto é
-- como um devolve o que o outro acabou de apagar.
local function refreshGui()
	if gui then
		gui.Enabled = anyVisible() and next(blocks) == nil
	end
end

function ItemHud.Block(source, active)
	blocks[source] = active or nil
	refreshGui()
end

function Slot:_resetHold(instant)
	if self.holdTween then
		self.holdTween:Cancel()
		self.holdTween = nil
	end
	if instant then
		self.fill.Size = FILL_HIDDEN
		return
	end
	local info = TweenInfo.new(FILL_RESET_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.fill, info, { Size = FILL_HIDDEN }):Play()
end

function Slot:_startHold()
	if self.holdTween or not self.visible then
		return
	end
	self.holdStart = os.clock()
	self.fill.Size = FILL_HIDDEN

	local tween = TweenService:Create(
		self.fill,
		TweenInfo.new(ItemConfig.HoldTime, Enum.EasingStyle.Linear),
		{ Size = FILL_FULL }
	)
	self.holdTween = tween
	tween.Completed:Connect(function(state)
		if state ~= Enum.PlaybackState.Completed then
			return
		end
		self.holdTween = nil
		-- Soltar depois do disparo não pode virar clique curto.
		self.holdStart = 0
		self:_resetHold(true)
		if self.held then
			self.held()
		end
	end)
	tween:Play()
end

function Slot:_stopHold()
	if not self.holdTween then
		return
	end
	local elapsed = os.clock() - self.holdStart
	self:_resetHold(false)
	if self.holdStart > 0 and elapsed < ItemConfig.HoldTime and self.tapped then
		self.tapped()
	end
end

function Slot:Show()
	self.visible = true
	self.frame.Visible = true
	refreshGui()
end

function Slot:Hide()
	self.visible = false
	self.frame.Visible = false
	self:_resetHold(true)
	refreshGui()
end

local function buildSlot(itemId, icon, keyLabel)
	local frame = template:Clone()
	frame.Name = itemId
	frame.Visible = false
	frame.LayoutOrder = ItemConfig.Index(itemId) or 0

	local press = frame:FindFirstChild("Press")
	local fill = frame:FindFirstChild("Fill")
	if not (press and press:IsA("GuiButton") and fill and fill:IsA("GuiObject")) then
		frame:Destroy()
		warn("[Item] slot de " .. itemId .. " sem Press ou Fill")
		return nil
	end

	press.Image = icon
	fill.Size = FILL_HIDDEN

	local key = frame:FindFirstChild("Key")
	if key and (key:IsA("TextButton") or key:IsA("TextLabel")) then
		key.Text = keyLabel
	end

	local slot = setmetatable({
		itemId = itemId,
		frame = frame,
		fill = fill,
		visible = false,
		holdStart = 0,
	}, Slot)

	press.InputBegan:Connect(function(input)
		if isPress(input) then
			slot:_startHold()
		end
	end)
	press.InputEnded:Connect(function(input)
		if isPress(input) then
			slot:_stopHold()
		end
	end)
	press.MouseLeave:Connect(function()
		slot:_stopHold()
	end)

	frame.Parent = hud
	return slot
end

-- Uma conexão de teclado para todos os slots: cada item traz a sua tecla, e só o slot visível
-- responde. N conexões idênticas disputando a mesma tecla é como um toque vira dois.
-- GUI apagada também não responde tecla: o slot continua vivo por baixo dela, e sem isso sentar ou
-- atender o telefone tirava o botão da tela sem tirar o atalho dele.
local function bindKeys()
	if keyLink then
		return
	end
	keyLink = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or (gui and not gui.Enabled) then
			return
		end
		for _, slot in pairs(slots) do
			if slot.visible and slot.hotKey and input.KeyCode == slot.hotKey and slot.tapped then
				slot.tapped()
				return
			end
		end
	end)
end

function ItemHud.Gui()
	return gui
end

-- Item que toma a tela inteira tira os slots de cena sem mexer no que cada um tem.
function ItemHud.SetVisible(visible)
	if hud then
		hud.Visible = visible
	end
end

function ItemHud.Slot(itemId, icon, keyLabel, hotKey)
	if not hud then
		return nil
	end
	local slot = slots[itemId]
	if slot then
		return slot
	end
	slot = buildSlot(itemId, icon, keyLabel)
	if not slot then
		return nil
	end
	slot.hotKey = hotKey
	slots[itemId] = slot
	bindKeys()
	return slot
end

function ItemHud.Init()
	ItemHold.OnSeat(function(active)
		ItemHud.Block("Seat", active)
	end)

	local playerGui = player:WaitForChild("PlayerGui", GUI_TIMEOUT)
	gui = playerGui and playerGui:WaitForChild(ItemConfig.GuiName, GUI_TIMEOUT)
	if not gui then
		warn("[Item] " .. ItemConfig.GuiName .. " não apareceu no PlayerGui")
		return
	end

	hud = gui:FindFirstChild(ItemConfig.HudName)
	template = hud and hud:FindFirstChild(ItemConfig.SlotTemplateName)
	if not template then
		warn("[Item] estrutura de " .. ItemConfig.GuiName .. " incompleta")
		hud = nil
		return
	end

	template.Visible = false
	gui.Enabled = false
end

return ItemHud
