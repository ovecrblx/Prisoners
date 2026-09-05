-- O exemplar parado no cenário, montado no cliente a partir do mesmo template da réplica de mão e
-- com ProximityPrompt local. Cada um coleta a sua: o exemplar some só para quem pegou e volta
-- quando o item é devolvido, então o lugar continua servindo quem ainda não passou por ele. Nada
-- disso existe no servidor — quem avisa que pegou é o controller do item.
local ItemPickup = {}
ItemPickup.__index = ItemPickup

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemView = require(script.Parent:WaitForChild("ItemView"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local TaskConfig = require(Shared:WaitForChild("TaskConfig"))
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))

local PROMPT_NAME = "ItemPrompt"

-- Mesmo estilo dos outros recursos do jogo: Custom, sem texto, desenhado pelo PromptDisplay. Os
-- números saem do DoorConfig porque são os do projeto — uma segunda cópia deles é como divergem.
local function buildPrompt(parent, title, triggered)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = title or ""
	prompt.UIOffset = DoorConfig.PromptOffset
	prompt.ClickablePrompt = DoorConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = DoorConfig.PromptDistance
	prompt.Parent = parent

	prompt.Triggered:Connect(triggered)
end

local pickups = {}
local wantedHighlight = {}

function ItemPickup.New(itemId, config)
	local pickup = setmetatable({ itemId = itemId, config = config }, ItemPickup)
	pickup.highlighted = wantedHighlight[itemId] == true
	pickups[itemId] = pickup
	return pickup
end

function ItemPickup.Get(itemId)
	return pickups[itemId]
end

-- Contorno pedido pelo nome do item, não pelo objeto: os Start correm em task.spawn, então as
-- tasks podem pedir o contorno antes de o controller do item ter montado o exemplar. O pedido
-- fica guardado e o New o encontra.
function ItemPickup.Highlight(itemId, on)
	wantedHighlight[itemId] = on or nil
	local pickup = pickups[itemId]
	if pickup then
		pickup:SetHighlight(on)
	end
end

-- Contorno de posição, ligado por fora. Fica guardado no objeto porque Show remonta o Model do
-- zero: sem isso o contorno sumiria a cada devolução.
function ItemPickup:SetHighlight(on)
	self.highlighted = on
	if not self.model then
		return
	end
	local handle = self.model:FindFirstChild(ItemConfig.HandleName)
	local existing = handle and handle:FindFirstChild(TaskConfig.HighlightName)
	if not on then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing or not handle then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = TaskConfig.HighlightName
	highlight.DepthMode = TaskConfig.HighlightDepthMode
	highlight.FillColor = TaskConfig.HighlightFillColor
	highlight.FillTransparency = TaskConfig.HighlightFillTransparency
	highlight.OutlineColor = TaskConfig.HighlightOutlineColor
	highlight.OutlineTransparency = TaskConfig.HighlightOutlineTransparency
	-- Marca antes de entrar no mundo: o HighlightGate escuta a tag, e contorno que nasce sem ela
	-- fica de fora do apagamento em bloco.
	CollectionService:AddTag(highlight, TaskConfig.HighlightTag)
	highlight.Parent = handle
end

function ItemPickup:Bind(callback)
	self.handler = callback
end

function ItemPickup:Pivot()
	local angles = self.config.PickupAngles
	return CFrame.new(self.config.PickupPosition)
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

function ItemPickup:Show()
	if self.model then
		return
	end
	local template = ItemView.Template(self.itemId)
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Name = self.itemId
	local handle = clone:FindFirstChild(ItemConfig.HandleName)
	if not (handle and handle:IsA("BasePart")) then
		clone:Destroy()
		warn("[Item] template de " .. self.itemId .. " sem " .. ItemConfig.HandleName)
		return
	end

	if self.dress then
		self.dress(clone, handle)
	end
	-- Só o Handle ancora: o resto do modelo pende dos Motor6D dele, e ancorar peça por peça
	-- prenderia cada uma onde o PivotTo a deixou, fora da junta.
	handle.Anchored = true
	clone:PivotTo(self:Pivot())
	-- Som antes do handler: ele esconde o exemplar, e som preso numa peça destruída não chega a
	-- soar. Sem peça de propósito — a coleta é local, e quem pegou está em cima dela.
	buildPrompt(handle, self.config.PromptTitle, function()
		if self.config.PickupSfx then
			Sfx.Play(self.config.PickupSfx)
		end
		if self.handler then
			self.handler()
		end
	end)

	-- Direto no workspace, fora das pastas do cenário: o exemplar é local e não depende do que o
	-- streaming traz.
	clone.Parent = workspace
	self.model = clone

	if self.highlighted then
		self:SetHighlight(true)
	end
end

function ItemPickup:Hide()
	if not self.model then
		return
	end
	self.model:Destroy()
	self.model = nil
end

return ItemPickup
