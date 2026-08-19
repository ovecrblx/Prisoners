--!strict
-- Vocabulário visual (dark flat) das ferramentas de autoria/depuração de NPC e a barra de botões
-- que elas dividem. Sem Init/Start: biblioteca inerte até alguém chamar.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local PanelTheme = {}

-- ============= PALETA — só a casca; cor de ESTADO (tipo de rota etc.) é vocabulário da ferramenta
PanelTheme.Color = table.freeze({
	Void = Color3.fromRGB(15, 16, 19), -- plano 0: fundo da janela
	Sunken = Color3.fromRGB(24, 26, 31), -- plano 1: barra de título, painéis internos
	Surface = Color3.fromRGB(35, 38, 45), -- plano 2: botões, caixas de texto, linhas de lista
	Accent = Color3.fromRGB(0, 229, 255), -- ciano: título, ícone, rótulo de botão
	ChromeDim = Color3.fromRGB(55, 60, 70), -- fio de 1px, barra de rolagem, alça
	Text = Color3.fromRGB(226, 236, 246),
	TextDim = Color3.fromRGB(132, 144, 160),
	TextInk = Color3.fromRGB(6, 14, 10), -- texto sobre fundo claro/aceso
	Bad = Color3.fromRGB(255, 82, 82),
})

-- ==================================================================== MEDIDAS
PanelTheme.Metrics = table.freeze({
	DOCK_MARGIN = 16, -- px da borda direita da tela até a barra de botões
	LAUNCHER_SIZE = 48, -- lado do botão da barra
	LAUNCHER_GAP = 10, -- px entre um botão e o seguinte na barra
	WINDOW_MARGIN = 16 + 48 + 12, -- px da borda direita até a janela; passa além da barra permanente
	TITLE_H = 34, -- altura da barra de título
	BUTTON_H = 20, -- altura padrão de botão pequeno
	BUTTON_TEXT = 10,
	TITLE_TEXT = 12,
	SLOT_PANEL_GAP = 0.15, -- fração de BUTTON_H entre painel de lista e o botão que o abre
})

function PanelTheme.SlotPanelGap(): number
	return math.round(PanelTheme.Metrics.BUTTON_H * PanelTheme.Metrics.SLOT_PANEL_GAP)
end

-- ==================================================================== PRIMITIVAS

-- Fio de 1px opaco, sem raio. Devolve o UIStroke: quem chama pode repintar ou engrossar.
function PanelTheme.Edge(inst: Instance, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1
	stroke.Transparency = 0
	stroke.Parent = inst
	return stroke
end

function PanelTheme.Text(parent: Instance, name: string, size: number, font: Enum.Font, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = ""
	label.Parent = parent
	return label
end

-- `tint` opcional troca a cor do rótulo e do fio mantendo o corpo neutro.
function PanelTheme.Button(parent: Instance, name: string, label: string, width: number, tint: Color3?): TextButton
	local metrics = PanelTheme.Metrics
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(width, metrics.BUTTON_H)
	button.BackgroundColor3 = PanelTheme.Color.Surface
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = metrics.BUTTON_TEXT
	button.TextColor3 = tint or PanelTheme.Color.Accent
	button.Text = label
	button.Parent = parent
	PanelTheme.Edge(button, tint or PanelTheme.Color.ChromeDim)
	return button
end

-- Devolve (barra, rótulo, botãoMinimizar) — quem chama liga o arrasto e o que o minimizar faz.
function PanelTheme.TitleBar(window: Instance, title: string): (Frame, TextLabel, TextButton)
	local metrics = PanelTheme.Metrics
	local bar = Instance.new("Frame")
	bar.Name = "TitleBar"
	bar.Size = UDim2.new(1, 0, 0, metrics.TITLE_H)
	bar.BackgroundColor3 = PanelTheme.Color.Sunken
	bar.BorderSizePixel = 0
	bar.Parent = window

	local label = PanelTheme.Text(bar, "Title", metrics.TITLE_TEXT, Enum.Font.GothamBold, PanelTheme.Color.Accent)
	label.Position = UDim2.fromOffset(14, 0)
	label.Size = UDim2.new(1, -120, 1, 0)
	label.Text = title

	local minimize = Instance.new("TextButton")
	minimize.Name = "MinimizeButton"
	minimize.AnchorPoint = Vector2.new(1, 0.5)
	minimize.Position = UDim2.new(1, -10, 0.5, 0)
	minimize.Size = UDim2.fromOffset(24, 20)
	minimize.BackgroundColor3 = PanelTheme.Color.Surface
	minimize.BorderSizePixel = 0
	minimize.Font = Enum.Font.GothamBold
	minimize.TextSize = 14
	minimize.Text = "—"
	minimize.TextColor3 = PanelTheme.Color.Accent
	minimize.Parent = bar

	return bar, label, minimize
end

-- ==================================================================== ARRASTO E REDIMENSIONAMENTO

-- onDelta(deltaEmPixels) enquanto arrasta; devolve função que desconecta tudo. InputEnded É
-- FILTRADO por botão/toque: GuiObject.InputEnded também dispara ao cursor sair de cima.
function PanelTheme.MakeDraggable(handle: GuiObject, onStart: (() -> ())?, onDelta: (Vector2) -> ()): () -> ()
	local dragging, lastPos = false, Vector2.zero
	local conns: { RBXScriptConnection } = {}

	local function stop()
		dragging = false
	end

	table.insert(conns, handle.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lastPos = Vector2.new(input.Position.X, input.Position.Y)
			if onStart then
				onStart()
			end
		end
	end))

	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		if not dragging then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		local now = Vector2.new(input.Position.X, input.Position.Y)
		onDelta(now - lastPos)
		lastPos = now
	end))

	table.insert(conns, handle.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			stop()
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			stop()
		end
	end))

	return function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
	end
end

-- Alça no canto inferior direito. ASSUME a janela ancorada em (1, 0.5): a posição é compensada
-- (X inteiro, Y/2) pra o canto arrastado seguir o cursor.
function PanelTheme.ResizeGrip(
	window: GuiObject,
	minSize: Vector2,
	maxSize: Vector2,
	onResized: (() -> ())?
): TextButton
	local grip = Instance.new("TextButton")
	grip.Name = "ResizeGrip"
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.new(1, -3, 1, -3)
	grip.Size = UDim2.fromOffset(16, 16)
	grip.BackgroundTransparency = 1
	grip.AutoButtonColor = false
	grip.Font = Enum.Font.GothamBold
	grip.TextSize = 14
	grip.TextColor3 = PanelTheme.Color.ChromeDim
	grip.Text = "◢"
	grip.ZIndex = 40
	grip.Parent = window

	local startSize = Vector2.zero
	local startPos = Vector2.zero
	local moved = Vector2.zero

	PanelTheme.MakeDraggable(grip, function()
		startSize = window.AbsoluteSize
		startPos = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
		moved = Vector2.zero
	end, function(delta: Vector2)
		moved += delta
		local w = math.clamp(startSize.X + moved.X, minSize.X, maxSize.X)
		local h = math.clamp(startSize.Y + moved.Y, minSize.Y, maxSize.Y)
		local grewX, grewY = w - startSize.X, h - startSize.Y
		window.Size = UDim2.fromOffset(w, h)
		window.Position = UDim2.new(
			window.Position.X.Scale,
			startPos.X + grewX,
			window.Position.Y.Scale,
			startPos.Y + grewY / 2
		)
		if onResized then
			onResized()
		end
	end)

	return grip
end

function PanelTheme.TextBox(parent: Instance, name: string, placeholder: string, width: number): TextBox
	local box = Instance.new("TextBox")
	box.Name = name
	box.Size = UDim2.fromOffset(width, PanelTheme.Metrics.BUTTON_H)
	box.BackgroundColor3 = PanelTheme.Color.Surface
	box.BorderSizePixel = 0
	box.Font = Enum.Font.Code
	box.TextSize = 10
	box.TextColor3 = PanelTheme.Color.Text
	box.PlaceholderText = placeholder
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = parent
	PanelTheme.Edge(box, PanelTheme.Color.ChromeDim)
	return box
end

-- ==================================================================== LISTA DE SLOTS
-- Painel dos slots do DataStore, uma linha por nome (carregar + apagar); o MESMO widget para toda
-- ferramenta que salva por slot.
function PanelTheme.SlotPanel(parent: Instance, title: string, width: number, height: number): (Frame, ScrollingFrame)
	local panel = Instance.new("Frame")
	panel.Name = "SlotList"
	panel.Size = UDim2.fromOffset(width, height)
	panel.BackgroundColor3 = PanelTheme.Color.Sunken
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = parent
	PanelTheme.Edge(panel, PanelTheme.Color.Accent)

	local heading = PanelTheme.Text(panel, "PaneTitle", 9, Enum.Font.GothamBold, PanelTheme.Color.Accent)
	heading.Position = UDim2.fromOffset(8, 5)
	heading.Size = UDim2.new(1, -16, 0, 12)
	heading.Text = title
	heading.ZIndex = 31

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Slots"
	scroll.Position = UDim2.fromOffset(6, 20)
	scroll.Size = UDim2.new(1, -12, 1, -26)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = PanelTheme.Color.ChromeDim
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ZIndex = 31
	scroll.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 3)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	return panel, scroll
end

-- px; altura de uma linha + espaçamento, pra quem preenche calcular o CanvasSize à mão.
PanelTheme.SLOT_ROW_STRIDE = 23

-- Devolve (linha, botãoCarregar, botãoApagar, checkbox?); o estado do checkbox é de quem chama.
-- "×" é Latin-1 de propósito: Dingbats ("✕") sai como caixa vazia nesta fonte.
function PanelTheme.SlotRow(
	scroll: Instance,
	name: string,
	order: number,
	withCheck: boolean?
): (Frame, TextButton, TextButton, TextButton?)
	local row = Instance.new("Frame")
	row.Name = "Slot_" .. name
	row.Size = UDim2.new(1, -4, 0, 20)
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.ZIndex = 32
	row.Parent = scroll

	local check: TextButton? = nil
	if withCheck then
		local box = Instance.new("TextButton")
		box.Name = "Check"
		box.Size = UDim2.fromOffset(20, 20)
		box.BackgroundTransparency = 1
		box.Font = Enum.Font.Code
		box.TextSize = 12
		box.ZIndex = 33
		box.Parent = row
		check = box
		PanelTheme.SetSlotChecked(box, false)
	end

	local pick = Instance.new("TextButton")
	pick.Name = "Load"
	pick.Position = if withCheck then UDim2.fromOffset(20, 0) else UDim2.fromOffset(0, 0)
	pick.Size = if withCheck then UDim2.new(1, -44, 1, 0) else UDim2.new(1, -24, 1, 0)
	pick.BackgroundColor3 = PanelTheme.Color.Surface
	pick.BorderSizePixel = 0
	pick.Font = Enum.Font.Code
	pick.TextSize = 10
	pick.TextColor3 = PanelTheme.Color.Text
	pick.TextXAlignment = Enum.TextXAlignment.Left
	pick.Text = "  " .. name
	pick.ZIndex = 33
	pick.Parent = row

	local del = Instance.new("TextButton")
	del.Name = "Delete"
	del.AnchorPoint = Vector2.new(1, 0)
	del.Position = UDim2.fromScale(1, 0)
	del.Size = UDim2.fromOffset(20, 20)
	del.BackgroundTransparency = 1
	del.Font = Enum.Font.GothamBold
	del.TextSize = 11
	del.TextColor3 = Color3.fromRGB(255, 150, 40)
	del.Text = "×"
	del.ZIndex = 33
	del.Parent = row

	return row, pick, del, check
end

-- Dono único do glifo do checkbox ("■"/"□" são Geometric Shapes, provados nesta fonte).
function PanelTheme.SetSlotChecked(check: TextButton, on: boolean)
	check.Text = if on then "■" else "□"
	check.TextColor3 = if on then PanelTheme.Color.Accent else PanelTheme.Color.TextDim
end

-- ==================================================================== CONFIRMAÇÃO
-- Caixa que COBRE o painel dono: enquanto visível, nada atrás recebe clique. Devolve (caixa, ask);
-- ask(mensagem, aoConfirmar?) sem ação vira aviso — o SIM some e o CANCELAR vira OK.
function PanelTheme.ConfirmBox(parent: GuiObject): (Frame, (string, (() -> ())?) -> ())
	local box = Instance.new("Frame")
	box.Name = "Confirm"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = PanelTheme.Color.Void
	box.BorderSizePixel = 0
	box.Visible = false
	box.ZIndex = 40
	box.Parent = parent
	PanelTheme.Edge(box, PanelTheme.Color.Bad)

	local label = PanelTheme.Text(box, "Message", 10, Enum.Font.GothamBold, PanelTheme.Color.Text)
	label.Position = UDim2.fromOffset(10, 10)
	label.Size = UDim2.new(1, -20, 1, -46)
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.None
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.ZIndex = 41

	local yes = PanelTheme.Button(box, "Yes", "SIM", 70, PanelTheme.Color.Bad)
	yes.AnchorPoint = Vector2.new(0, 1)
	yes.Position = UDim2.new(0, 10, 1, -10)
	yes.ZIndex = 41

	local cancel = PanelTheme.Button(box, "Cancel", "CANCELAR", 84)
	cancel.AnchorPoint = Vector2.new(1, 1)
	cancel.Position = UDim2.new(1, -10, 1, -10)
	cancel.ZIndex = 41

	local pending: (() -> ())? = nil

	local function ask(message: string, onConfirm: (() -> ())?)
		label.Text = message
		pending = onConfirm
		yes.Visible = onConfirm ~= nil
		cancel.Text = if onConfirm ~= nil then "CANCELAR" else "OK"
		box.Visible = true
	end

	yes.Activated:Connect(function()
		local action = pending
		-- Desarma ANTES de rodar: a ação pode yieldar, e um segundo clique apagaria duas vezes.
		pending = nil
		box.Visible = false
		if action then
			action()
		end
	end)

	cancel.Activated:Connect(function()
		pending = nil
		box.Visible = false
	end)

	return box, ask
end

-- ==================================================================== A BARRA DE BOTÕES
local DOCK_GUI_NAME = "NpcToolDock"

-- Devolve (criando na primeira chamada) o Frame da barra; idempotente e tolerante a respawn.
function PanelTheme.Dock(): Frame
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local metrics = PanelTheme.Metrics

	local existing = playerGui:FindFirstChild(DOCK_GUI_NAME)
	if existing then
		local frame = existing:FindFirstChild("Rail")
		if frame and frame:IsA("Frame") then
			return frame
		end
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = DOCK_GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1001 -- acima das janelas: a barra é o caminho de volta às ferramentas
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local rail = Instance.new("Frame")
	rail.Name = "Rail"
	rail.AnchorPoint = Vector2.new(1, 0.5)
	rail.Position = UDim2.new(1, -metrics.DOCK_MARGIN, 0.5, 0)
	rail.Size = UDim2.fromOffset(metrics.LAUNCHER_SIZE, 0)
	rail.AutomaticSize = Enum.AutomaticSize.Y
	rail.BackgroundTransparency = 1
	rail.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, metrics.LAUNCHER_GAP)
	layout.Parent = rail

	return rail
end

-- Botão só-ícone e permanente; `order` empilha (menor em cima), `height` em px (nil = quadrado).
function PanelTheme.LauncherSlot(name: string, icon: string, order: number, height: number?): TextButton
	local rail = PanelTheme.Dock()
	local metrics = PanelTheme.Metrics

	local existing = rail:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(metrics.LAUNCHER_SIZE, height or metrics.LAUNCHER_SIZE)
	button.BackgroundColor3 = PanelTheme.Color.Void
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 22
	button.Text = icon
	button.TextColor3 = PanelTheme.Color.Accent
	button.Parent = rail
	PanelTheme.Edge(button, PanelTheme.Color.Accent)
	return button
end

-- Slot marcado NÃO some quando um modo esvazia a barra; a marca mora aqui, nunca num nome
-- comparado à mão nos controllers.
local PERSISTENT_ATTR = "PersistentSlot"

function PanelTheme.SetSlotPersistent(button: TextButton)
	button:SetAttribute(PERSISTENT_ATTR, true)
end

function PanelTheme.IsSlotPersistent(button: Instance): boolean
	return button:GetAttribute(PERSISTENT_ATTR) == true
end

-- Aceso = janela aberta; o único feedback de estado da barra.
function PanelTheme.SetLauncherActive(button: TextButton, active: boolean)
	button.BackgroundColor3 = if active then PanelTheme.Color.Accent else PanelTheme.Color.Void
	button.TextColor3 = if active then PanelTheme.Color.TextInk else PanelTheme.Color.Accent
end

return PanelTheme
