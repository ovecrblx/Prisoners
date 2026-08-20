--!nonstrict
-- Painel de IA (cliente): a árvore do NPC observado como um mapa — cards num canvas com zoom e pan,
-- ligados por linhas, pintados com o status do último tick. Só olha; nenhuma op daqui muda o mundo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Lib = script.Parent.Parent:WaitForChild("Lib")
local PanelTheme = require(Lib:WaitForChild("PanelTheme"))
local DockMemory = require(Lib:WaitForChild("DockMemory"))
-- Esta janela ESCOLHE o sujeito; a câmera livre lê daqui. Ver Lib/WatchedNpc.
local WatchedNpc = require(Lib:WaitForChild("WatchedNpc"))

local BrainMonitorClient = {}

local DOCK_KEY = "brain"
local REMOTE_WAIT = 10

-- s entre a última mudança de geometria e a gravação; arrastar a janela não é uma escrita por frame.
local GEOM_DEBOUNCE = 1.5

-- px; janela inicial e faixa da alça de redimensionar.
local WINDOW_W, WINDOW_H = 640, 640
local WINDOW_MIN = Vector2.new(380, 300)
local WINDOW_MAX = Vector2.new(2200, 1500)
local FOOT_H = 88

-- px do card, espessura da linha e quanto do card TEM que continuar visível ao arrastar.
local CARD_W, CARD_H = 122, 38
local LINK_W = 2
local EDGE_KEEP = 26

-- Arranjo automático: profundidade vira linha, irmãos espalham na coluna.
local LAYER_GAP = CARD_H + 46
local SIBLING_GAP = CARD_W + 26

local ZOOM_MIN, ZOOM_MAX, ZOOM_FACTOR = 0.05, 8, 1.18

-- Vocabulário DESTA janela, não do tema. Não existe estado "trancado" aqui: não há nó Gate.
local COL = table.clone(PanelTheme.Color)
COL.Live = Color3.fromRGB(0, 235, 120)
COL.Evaluated = Color3.fromRGB(255, 150, 40)
COL.Unlocked = Color3.fromRGB(126, 138, 156)

local TYPE_COL = {
	Selector = Color3.fromRGB(168, 130, 255),
	Sequence = Color3.fromRGB(34, 224, 238),
	Condition = Color3.fromRGB(90, 170, 255),
	Action = Color3.fromRGB(60, 235, 150),
}

local TYPE_TAG = {
	Selector = "?",
	Sequence = "→",
	Condition = "◇",
	Action = "▶",
}

local ICON = {
	["cidadão"] = "🧠",
	["descanso"] = "🪑",
	["sentado"] = "◇",
	["descansar"] = "😴",
	["assento"] = "🪑",
	["quer assento"] = "🎯",
	["ir ao assento"] = "🚶",
	["patrulhar"] = "🧭",
}

local DESC = {
	["cidadão"] = "Selector: lista de prioridade, de cima para baixo. Para no primeiro ramo que não falha.",
	["descanso"] = "Sequence: só corre com o corpo já sentado.",
	["sentado"] = "Lê Humanoid.SeatPart. A engine também senta por toque, sem a árvore pedir.",
	["descansar"] = "Conta o tempo sentado e levanta destruindo o SeatWeld.",
	["assento"] = "Sequence: escolhe um assento livre e conduz o corpo até ele.",
	["quer assento"] = "Assento livre dentro do raio e fora da carência.",
	["ir ao assento"] = "A marcha conduz pelo grafo; só o último trecho sai da rota.",
	["patrulhar"] = "Ronda a rede: vizinho menos visitado, sem voltar por onde veio.",
}

local player = Players.LocalPlayer
local queryFn: RemoteFunction? = nil
local layoutFn: RemoteFunction? = nil

local ui = {}
local state = {
	zoom = 1,
	cards = {},
	links = {},
	positions = {},
	selected = nil,
	watching = nil,
	cardDrag = 0,
	keyOf = {},
	idOfKey = {},
	classOf = {},
}

local applyOpen = nil
local relayoutLinks

local function invoke(payload)
	local fn = queryFn
	if not fn then
		return nil
	end
	local ok, result = pcall(function()
		return fn:InvokeServer(payload)
	end)
	return if ok then result else nil
end

-- Sem o remote de layout a ferramenta continua inteira: geometria e arranjo viram memória de sessão.
local function layoutCall(action, name, payload)
	local fn = layoutFn
	if not fn then
		return nil
	end
	local ok, result = pcall(function()
		return fn:InvokeServer(action, name, payload)
	end)
	return if ok then result else nil
end

local function setStatus(text)
	if ui.status then
		ui.status.Text = text
	end
end

-- ==================================================================== CANVAS

-- O ponto do mundo sob o cursor tem que continuar sob o cursor: sem a âncora, aproximar joga a
-- árvore para fora da tela e o dev perde o que estava olhando.
local function applyZoom(target, screenPoint)
	local zoom = math.clamp(target, ZOOM_MIN, ZOOM_MAX)
	local viewport = ui.viewport
	local vx = screenPoint.X - viewport.AbsolutePosition.X
	local vy = screenPoint.Y - viewport.AbsolutePosition.Y
	local ox, oy = ui.world.Position.X.Offset, ui.world.Position.Y.Offset
	local wx = (vx - ox) / state.zoom
	local wy = (vy - oy) / state.zoom

	state.zoom = zoom
	ui.scale.Scale = zoom
	ui.world.Position = UDim2.fromOffset(vx - wx * zoom, vy - wy * zoom)
	relayoutLinks()
end

local function centreOf(key)
	local p = state.positions[key]
	return p.x + CARD_W / 2, p.y + CARD_H / 2
end

-- Retângulo do mundo que a janela mostra agora, com folga de um card.
local function visibleRect()
	local size = ui.viewport.AbsoluteSize
	local ox, oy = ui.world.Position.X.Offset, ui.world.Position.Y.Offset
	local pad = CARD_W
	return (0 - ox) / state.zoom - pad,
		(0 - oy) / state.zoom - pad,
		(size.X - ox) / state.zoom + pad,
		(size.Y - oy) / state.zoom + pad
end

-- Segmento inteiramente fora da vista não vira Frame: com zoom aproximado a linha entre dois cards
-- distantes viraria milhares de px rotacionados, e nada disso aparece na tela.
local function positionLink(link, minX, minY, maxX, maxY)
	local ax, ay = centreOf(link.parentKey)
	local bx, by = centreOf(link.childKey)

	if
		(ax < minX and bx < minX)
		or (ax > maxX and bx > maxX)
		or (ay < minY and by < minY)
		or (ay > maxY and by > maxY)
	then
		link.line.Visible = false
		return
	end
	link.line.Visible = true

	local dx, dy = bx - ax, by - ay
	local length = math.sqrt(dx * dx + dy * dy)

	link.line.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
	link.line.Size = UDim2.fromOffset(length, LINK_W)
	link.line.Rotation = math.deg(math.atan2(dy, dx))
end

relayoutLinks = function()
	local minX, minY, maxX, maxY = visibleRect()
	for _, link in ipairs(state.links) do
		positionLink(link, minX, minY, maxX, maxY)
	end
end

local function refreshLinksFor(key)
	local minX, minY, maxX, maxY = visibleRect()
	for _, link in ipairs(state.links) do
		if link.parentKey == key or link.childKey == key then
			positionLink(link, minX, minY, maxX, maxY)
		end
	end
end

-- ==================================================================== ARRANJO

-- Camadas: profundidade vira linha e cada pai fica centrado sobre o bloco dos filhos. Substitui o
-- layout autorado do original — a árvore daqui é outra, então não há posição herdada.
local function arrangeTree(node, depth, cursor)
	local children = node.children or {}
	if #children == 0 then
		local x = cursor.x
		cursor.x += SIBLING_GAP
		state.positions[node.id] = { x = x, y = depth * LAYER_GAP }
		return x
	end

	local first, last
	for index, child in ipairs(children) do
		local x = arrangeTree(child, depth + 1, cursor)
		if index == 1 then
			first = x
		end
		last = x
	end
	local x = (first + last) / 2
	state.positions[node.id] = { x = x, y = depth * LAYER_GAP }
	return x
end

-- ==================================================================== CARDS

local function selectNode(node)
	state.selected = node
	ui.inspector.Text = string.format(
		"%s  ·  %s\n%s",
		node.name,
		node.type,
		DESC[node.name] or "—"
	)
end

local function buildCard(node)
	local pos = state.positions[node.id]

	local card = Instance.new("TextButton")
	card.Name = "Node_" .. node.name
	card.Position = UDim2.fromOffset(pos.x, pos.y)
	card.Size = UDim2.fromOffset(CARD_W, CARD_H)
	card.BackgroundColor3 = COL.Unlocked
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.Text = ""
	card.ZIndex = 4
	card.Parent = ui.world
	local stroke = PanelTheme.Edge(card, COL.ChromeDim)

	local accent = Instance.new("Frame")
	accent.Name = "TypeAccent"
	accent.Size = UDim2.fromOffset(3, CARD_H)
	accent.BackgroundColor3 = TYPE_COL[node.type] or COL.ChromeDim
	accent.BorderSizePixel = 0
	accent.ZIndex = 5
	accent.Parent = card

	local icon = PanelTheme.Text(card, "NodeIcon", 15, Enum.Font.GothamMedium, COL.Text)
	icon.Position = UDim2.fromOffset(10, 0)
	icon.Size = UDim2.fromOffset(22, CARD_H)
	icon.Text = ICON[node.name] or TYPE_TAG[node.type] or "•"
	icon.ZIndex = 5

	local title = PanelTheme.Text(card, "NodeTitle", 12, Enum.Font.GothamBold, COL.Text)
	title.Position = UDim2.fromOffset(34, 5)
	title.Size = UDim2.fromOffset(CARD_W - 42, 17)
	title.Text = node.name
	title.ZIndex = 5

	local sub = PanelTheme.Text(card, "NodeSubtitle", 10, Enum.Font.Code, COL.TextDim)
	sub.Position = UDim2.fromOffset(34, 21)
	sub.Size = UDim2.fromOffset(CARD_W - 42, 15)
	sub.Text = (TYPE_TAG[node.type] or "•") .. " " .. node.type
	sub.ZIndex = 5

	local moved, counted = false, false
	-- O delta do mouse está em px de TELA e a posição em px de MUNDO: sem dividir pelo zoom, o card
	-- derrapa em relação ao cursor assim que a escala sai de 1.
	local disconnect = PanelTheme.MakeDraggable(card, function()
		moved = false
		counted = true
		state.cardDrag += 1
		selectNode(node)
	end, function(delta)
		moved = true
		local p = state.positions[node.id]
		p.x += delta.X / state.zoom
		p.y += delta.Y / state.zoom

		-- Trava de borda, em espaço de viewport e devolvida ao mundo: sem ela dá para empurrar um
		-- card para fora do recorte e a única forma de reachá-lo é adivinhar a direção do pan.
		local size = ui.viewport.AbsoluteSize
		local ox, oy = ui.world.Position.X.Offset, ui.world.Position.Y.Offset
		local sx, sy = p.x * state.zoom + ox, p.y * state.zoom + oy
		local cw, ch = CARD_W * state.zoom, CARD_H * state.zoom
		local clampedX = math.clamp(sx, EDGE_KEEP - cw, size.X - EDGE_KEEP)
		local clampedY = math.clamp(sy, EDGE_KEEP - ch, size.Y - EDGE_KEEP)
		if clampedX ~= sx then
			p.x = (clampedX - ox) / state.zoom
		end
		if clampedY ~= sy then
			p.y = (clampedY - oy) / state.zoom
		end

		card.Position = UDim2.fromOffset(p.x, p.y)
		refreshLinksFor(node.id)
	end)

	-- A baixa vem do card E do global: soltar o botão fora do card não pode deixar o pan mudo.
	local function release()
		if counted then
			counted = false
			state.cardDrag = math.max(0, state.cardDrag - 1)
		end
	end
	local globalUp = UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			release()
		end
	end)
	card.InputEnded:Connect(release)
	card.Activated:Connect(function()
		if not moved then
			selectNode(node)
		end
	end)

	return {
		card = card,
		stroke = stroke,
		title = title,
		sub = sub,
		icon = icon,
		node = node,
		disconnect = function()
			disconnect()
			globalUp:Disconnect()
		end,
	}
end

-- Desconecta ANTES de destruir: MakeDraggable registra ouvintes no UserInputService, que sobrevivem
-- ao Destroy do card. Sem isto, cada troca de NPC deixa closures ouvindo mouse para sempre.
local function clearGraph()
	for _, handle in pairs(state.cards) do
		handle.disconnect()
		handle.card:Destroy()
	end
	for _, link in ipairs(state.links) do
		link.line:Destroy()
	end
	state.cards = {}
	state.links = {}
	state.positions = {}
	state.keyOf = {}
	state.idOfKey = {}
	state.selected = nil
end

-- A chave do arranjo é o CAMINHO DE ÍNDICES ("r", "r.2", "r.2.1"), não o id: id muda quando a
-- árvore é remontada, e nomes se repetem entre ramos.
local function buildGraph(tree)
	clearGraph()
	arrangeTree(tree, 0, { x = 0 })

	local function walk(node, key)
		state.keyOf[node.id] = key
		state.idOfKey[key] = node.id
		state.cards[node.id] = buildCard(node)
		for index, child in ipairs(node.children or {}) do
			local line = Instance.new("Frame")
			line.Name = "Link"
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.BackgroundColor3 = COL.ChromeDim
			line.BorderSizePixel = 0
			line.ZIndex = 3
			line.Parent = ui.world
			table.insert(state.links, {
				line = line,
				parentKey = node.id,
				childKey = child.id,
				childId = child.id,
			})
			walk(child, key .. "." .. index)
		end
	end
	walk(tree, "r")
	relayoutLinks()
	selectNode(tree)
end

-- ==================================================================== PINTURA

local function paint(trace)
	for id, handle in pairs(state.cards) do
		local status = trace[id]
		if status == "Running" then
			handle.card.BackgroundColor3 = COL.Live
			handle.stroke.Color = COL.Live
			handle.stroke.Thickness = 3
			handle.title.TextColor3 = COL.TextInk
			handle.sub.TextColor3 = COL.TextInk
			handle.icon.TextColor3 = COL.TextInk
		else
			handle.stroke.Thickness = 1
			handle.icon.TextColor3 = COL.Text
			if status ~= nil then
				handle.card.BackgroundColor3 = COL.Evaluated
				handle.stroke.Color = COL.Evaluated
				handle.title.TextColor3 = COL.TextInk
				handle.sub.TextColor3 = COL.TextInk
			else
				handle.card.BackgroundColor3 = COL.Unlocked
				handle.stroke.Color = COL.Unlocked
				handle.title.TextColor3 = COL.TextInk
				handle.sub.TextColor3 = COL.TextDim
			end
		end

		if state.selected and state.selected.id == id then
			handle.stroke.Color = COL.Accent
			handle.stroke.Thickness = 2
		end
	end

	for _, link in ipairs(state.links) do
		local status = trace[link.childId]
		link.line.BackgroundColor3 = if status == "Running"
			then COL.Live
			elseif status ~= nil then COL.Evaluated
			else COL.ChromeDim
	end
end

-- ==================================================================== SERVIDOR

local function watch(agentId)
	state.watching = agentId
	invoke({ op = "Watch", agentId = agentId })
	ui.chip.Text = agentId or "nenhum NPC"
	-- Quem escolhe publica: a câmera livre segue o mesmo corpo que este painel desenha.
	WatchedNpc.Set(agentId, if agentId then state.classOf[agentId] else nil)

	if not agentId then
		clearGraph()
		return
	end
	local result = invoke({ op = "Tree", agentId = agentId })
	if result and result.ok then
		buildGraph(result.tree)
		setStatus(agentId)
	else
		clearGraph()
		setStatus("sem árvore para " .. agentId)
	end
end

local function onSnapshot(payload)
	if type(payload) ~= "table" or payload.agentId ~= state.watching then
		return
	end
	if payload.gone then
		setStatus("corpo sumiu; escolha outro")
		return
	end

	paint(payload.status or {})

	local board = payload.board or {}
	ui.board.Text = string.format(
		"%s   ·   nó %s ← %s\nassento %s   ·   descanso %.1fs",
		tostring(board.state or "—"),
		tostring(board.nodeId or "—"),
		tostring(board.fromId or "—"),
		if board.seat ~= "" then tostring(board.seat) else "—",
		tonumber(board.rest) or 0
	)
end

-- ==================================================================== JANELA

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local metrics = PanelTheme.Metrics

	local screen = Instance.new("ScreenGui")
	screen.Name = "BrainMonitorGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1000
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local toggle = PanelTheme.LauncherSlot("BrainLauncher", "🧠", 1)

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(1, 0.5)
	window.Position = UDim2.new(1, -metrics.WINDOW_MARGIN, 0.5, 0)
	window.Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)
	window.BackgroundColor3 = COL.Void
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.Visible = false
	window.Parent = screen
	PanelTheme.Edge(window, COL.Accent)

	local bar, _title, minimize = PanelTheme.TitleBar(window, "◈  IA BRAIN")
	PanelTheme.MakeDraggable(bar, nil, function(delta)
		window.Position = UDim2.new(
			window.Position.X.Scale,
			window.Position.X.Offset + delta.X,
			window.Position.Y.Scale,
			window.Position.Y.Offset + delta.Y
		)
	end)
	PanelTheme.ResizeGrip(window, WINDOW_MIN, WINDOW_MAX)

	-- Geometria com atraso: arrastar a janela dispara Position a cada frame, e cada uma seria uma
	-- ida ao DataStore. Guardada em absoluto, então volta ancorada no canto de cima à esquerda.
	local geomPending = false
	local function saveGeometry()
		if geomPending then
			return
		end
		geomPending = true
		task.delay(GEOM_DEBOUNCE, function()
			geomPending = false
			layoutCall("geom_set", DOCK_KEY, {
				x = window.AbsolutePosition.X,
				y = window.AbsolutePosition.Y,
				w = window.AbsoluteSize.X,
				h = window.AbsoluteSize.Y,
			})
		end)
	end
	window:GetPropertyChangedSignal("Position"):Connect(saveGeometry)
	window:GetPropertyChangedSignal("Size"):Connect(saveGeometry)

	task.spawn(function()
		local saved = layoutCall("geom_get", DOCK_KEY)
		local box = saved and saved.geom
		if box then
			window.AnchorPoint = Vector2.zero
			window.Position = UDim2.fromOffset(box.x, box.y)
			window.Size = UDim2.fromOffset(box.w, box.h)
		end
	end)

	-- Chip do NPC observado, na própria barra de título: é o seletor e o rótulo ao mesmo tempo.
	local chip = PanelTheme.Button(bar, "Chip", "nenhum NPC", 150)
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, -62, 0.5, 0)
	chip.ZIndex = 6
	ui.chip = chip

	local viewport = Instance.new("Frame")
	viewport.Name = "Viewport"
	viewport.Position = UDim2.fromOffset(0, metrics.TITLE_H)
	viewport.Size = UDim2.new(1, 0, 1, -(metrics.TITLE_H + FOOT_H))
	viewport.BackgroundColor3 = COL.Sunken
	viewport.BorderSizePixel = 0
	viewport.ClipsDescendants = true
	viewport.Active = true
	viewport.Parent = window
	ui.viewport = viewport

	local world = Instance.new("Frame")
	world.Name = "World"
	world.BackgroundTransparency = 1
	world.Size = UDim2.fromOffset(0, 0)
	world.Position = UDim2.fromOffset(60, 40)
	world.Parent = viewport
	ui.world = world

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = world
	ui.scale = scale

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOT_H)
	footer.BackgroundColor3 = COL.Sunken
	footer.BorderSizePixel = 0
	footer.Parent = window

	local inspector = PanelTheme.Text(footer, "Inspector", 11, Enum.Font.Gotham, COL.Text)
	inspector.Position = UDim2.fromOffset(10, 4)
	inspector.Size = UDim2.new(1, -20, 0, 28)
	inspector.TextYAlignment = Enum.TextYAlignment.Top
	inspector.TextWrapped = true
	inspector.Text = "—"
	ui.inspector = inspector

	local board = PanelTheme.Text(footer, "Board", 10, Enum.Font.Code, COL.Accent)
	board.Position = UDim2.fromOffset(10, 32)
	board.Size = UDim2.new(1, -20, 0, 26)
	board.TextYAlignment = Enum.TextYAlignment.Top
	board.Text = "—"
	ui.board = board

	local status = PanelTheme.Text(footer, "Status", 10, Enum.Font.Gotham, COL.TextDim)
	status.AnchorPoint = Vector2.new(1, 1)
	status.Position = UDim2.new(1, -10, 1, -2)
	status.Size = UDim2.fromOffset(180, 12)
	status.TextXAlignment = Enum.TextXAlignment.Right
	ui.status = status

	-- ARRANJOS: o desenho que o autor arrumou à mão vira perfil nomeado, como os slots de rota.
	local nameBox = PanelTheme.TextBox(footer, "ProfileName", "nome do arranjo", 150)
	nameBox.Position = UDim2.fromOffset(10, 60)

	local saveButton = PanelTheme.Button(footer, "Btn_SalvarArranjo", "SALVAR", 76)
	saveButton.Position = UDim2.fromOffset(166, 60)

	local listButton = PanelTheme.Button(footer, "Btn_Arranjos", "ARRANJOS", 82)
	listButton.Position = UDim2.fromOffset(248, 60)

	local PROF_W, PROF_H = 210, 140
	local profPanel, profScroll = PanelTheme.SlotPanel(window, "ARRANJOS SALVOS", PROF_W, PROF_H)
	profPanel.AnchorPoint = Vector2.new(0, 1)
	profPanel.Position = UDim2.new(0, 10, 1, -(FOOT_H + 4))

	local function currentCards()
		local cards = {}
		for id, point in pairs(state.positions) do
			local key = state.keyOf[id]
			if key then
				cards[key] = { x = point.x, y = point.y }
			end
		end
		return cards
	end

	local function applyCards(cards)
		for key, point in pairs(cards) do
			local id = state.idOfKey[key]
			local handle = id and state.cards[id]
			if handle then
				state.positions[id] = { x = point.x, y = point.y }
				handle.card.Position = UDim2.fromOffset(point.x, point.y)
			end
		end
		relayoutLinks()
	end

	local function refreshProfiles()
		for _, child in ipairs(profScroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local result = layoutCall("layout_list", DOCK_KEY)
		local names = (result and result.ok and result.names) or {}
		if #names == 0 then
			local empty = PanelTheme.Text(profScroll, "Empty", 10, Enum.Font.Code, COL.TextDim)
			empty.Size = UDim2.new(1, 0, 0, 18)
			empty.LayoutOrder = 1
			empty.Text = "  (nenhum arranjo salvo)"
			return
		end
		for index, name in ipairs(names) do
			local _row, pick, del = PanelTheme.SlotRow(profScroll, name, index)
			pick.Activated:Connect(function()
				local loaded = layoutCall("layout_load", DOCK_KEY, name)
				if loaded and loaded.ok then
					applyCards(loaded.cards)
					nameBox.Text = name
					setStatus("arranjo '" .. name .. "' aplicado")
				end
				profPanel.Visible = false
			end)
			del.Activated:Connect(function()
				layoutCall("layout_delete", DOCK_KEY, name)
				refreshProfiles()
			end)
		end
		profScroll.CanvasSize = UDim2.fromOffset(0, #names * PanelTheme.SLOT_ROW_STRIDE)
	end

	saveButton.MouseButton1Click:Connect(function()
		local name = nameBox.Text:match("^%s*(.-)%s*$") or ""
		if #name == 0 then
			setStatus("dê um nome ao arranjo")
			return
		end
		local result = layoutCall("layout_save", DOCK_KEY, { name = name, cards = currentCards() })
		setStatus(if result and result.ok
			then "arranjo '" .. name .. "' salvo"
			else "falha ao salvar: " .. tostring(result and result.reason))
		if profPanel.Visible then
			refreshProfiles()
		end
	end)

	listButton.MouseButton1Click:Connect(function()
		profPanel.Visible = not profPanel.Visible
		if profPanel.Visible then
			refreshProfiles()
		end
	end)

	-- ZOOM pela roda, ancorado no cursor.
	viewport.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			applyZoom(state.zoom * ZOOM_FACTOR ^ input.Position.Z, UserInputService:GetMouseLocation())
		end
	end)

	-- PAN por arrasto no vazio; mudo enquanto um card está na mão.
	PanelTheme.MakeDraggable(viewport, nil, function(delta)
		if state.cardDrag > 0 then
			return
		end
		world.Position = UDim2.fromOffset(
			world.Position.X.Offset + delta.X,
			world.Position.Y.Offset + delta.Y
		)
		relayoutLinks()
	end)

	local LIST_W, LIST_H = 210, 150
	local listPanel, listScroll = PanelTheme.SlotPanel(window, "NPCs NO MUNDO", LIST_W, LIST_H)
	listPanel.AnchorPoint = Vector2.new(1, 0)
	listPanel.Position = UDim2.new(1, -12, 0, metrics.TITLE_H + 4)

	local function refreshList()
		for _, child in ipairs(listScroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local result = invoke({ op = "List" })
		local agents = (result and result.ok and result.agents) or {}
		if #agents == 0 then
			local empty = PanelTheme.Text(listScroll, "Empty", 10, Enum.Font.Code, COL.TextDim)
			empty.Size = UDim2.new(1, 0, 0, 18)
			empty.LayoutOrder = 1
			empty.Text = "  (nenhum NPC no mundo)"
			return
		end
		for index, entry in ipairs(agents) do
			state.classOf[entry.id] = entry.class
			local _row, choose, del = PanelTheme.SlotRow(listScroll, entry.id .. "  " .. tostring(entry.state), index)
			del.Visible = false
			choose.Activated:Connect(function()
				listPanel.Visible = false
				watch(entry.id)
			end)
		end
		listScroll.CanvasSize = UDim2.fromOffset(0, #agents * PanelTheme.SLOT_ROW_STRIDE)
	end

	chip.MouseButton1Click:Connect(function()
		listPanel.Visible = not listPanel.Visible
		if listPanel.Visible then
			refreshList()
		end
	end)

	local function setOpen(open)
		window.Visible = open
		PanelTheme.SetLauncherActive(toggle, open)
		if open then
			refreshList()
			if state.watching then
				watch(state.watching)
			end
		else
			listPanel.Visible = false
			watch(nil)
		end
		DockMemory.SetOpen(DOCK_KEY, open)
	end
	applyOpen = setOpen

	toggle.MouseButton1Click:Connect(function()
		setOpen(not window.Visible)
	end)
	minimize.Activated:Connect(function()
		setOpen(false)
	end)

	screen.Parent = playerGui
end

function BrainMonitorClient.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
	local query = remotes and remotes:WaitForChild("NpcBrain", REMOTE_WAIT)
	local snapshot = remotes and remotes:WaitForChild("NpcBrainSnapshot", REMOTE_WAIT)
	if not query or not snapshot then
		return
	end
	queryFn = query
	-- Opcional: sem ele a janela funciona, só não lembra geometria nem arranjo entre sessões.
	local tool = remotes:FindFirstChild("ToolLayout")
	layoutFn = if tool and tool:IsA("RemoteFunction") then tool else nil

	local allowed = invoke({ op = "IsAuthorized" })
	if not allowed or not allowed.ok then
		return
	end

	buildGui()
	snapshot.OnClientEvent:Connect(onSnapshot)

	if DockMemory.Load()[DOCK_KEY] and applyOpen then
		applyOpen(true)
	end
end

return BrainMonitorClient
