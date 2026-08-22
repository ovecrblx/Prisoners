--!nonstrict
-- Painel de IA (cliente): a árvore do NPC observado como um mapa — cards num canvas com zoom e pan,
-- ligados por linhas, pintados com o status do último tick. Só olha; nenhuma op daqui muda o mundo.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

-- s entre tentativas de achar um corpo ao abrir, e quantas: no boot a janela sobe antes do spawn.
local NPC_RETRY, NPC_RETRIES = 2, 5

-- px; janela inicial e faixa da alça de redimensionar.
local WINDOW_W, WINDOW_H = 640, 640
local WINDOW_MIN = Vector2.new(380, 300)
local WINDOW_MAX = Vector2.new(2200, 1500)
local FOOT_H = 88

-- px do chip do NPC na barra de título: largura e folga até a borda direita da janela. O painel que
-- ele abre se alinha por esta mesma borda — a aresta que liga botão e painel tem que ser uma só.
local CHIP_W, CHIP_RIGHT = 150, 62

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
	marks = {},
}

local applyOpen = nil
local relayoutLinks
-- Marca a janela como suja para a gravação com atraso; ligado quando a janela existe.
local touchGeometry = nil

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
	if touchGeometry then
		touchGeometry()
	end
end

-- Escala sem âncora de cursor: é o caminho de quem RESTAURA uma escala, não de quem gira a roda.
local function setZoom(zoom)
	state.zoom = math.clamp(zoom, ZOOM_MIN, ZOOM_MAX)
	ui.scale.Scale = state.zoom
	relayoutLinks()
end

local function centreOf(key)
	local p = state.positions[key]
	return p.x + CARD_W / 2, p.y + CARD_H / 2
end

-- Retângulo do mundo que a janela mostra agora, em px de mundo. SEM folga: é contra ele que o
-- segmento é cortado, e uma folga aqui viraria linha desenhada por fora da janela.
local function visibleRect()
	local size = ui.viewport.AbsoluteSize
	local ox, oy = ui.world.Position.X.Offset, ui.world.Position.Y.Offset
	local z = state.zoom
	return -ox / z, -oy / z, (size.X - ox) / z, (size.Y - oy) / z
end

-- Liang–Barsky: devolve o segmento a→b cortado no retângulo, ou nada se ele estiver todo fora.
local function clipSegment(ax, ay, bx, by, minX, minY, maxX, maxY)
	local dx, dy = bx - ax, by - ay
	local t0, t1 = 0, 1
	local p = { -dx, dx, -dy, dy }
	local q = { ax - minX, maxX - ax, ay - minY, maxY - ay }

	for i = 1, 4 do
		if p[i] == 0 then
			-- Paralelo a este lado: só sobrevive quem já está do lado de dentro dele.
			if q[i] < 0 then
				return nil
			end
		else
			local r = q[i] / p[i]
			if p[i] < 0 then
				if r > t1 then
					return nil
				elseif r > t0 then
					t0 = r
				end
			elseif r < t0 then
				return nil
			elseif r < t1 then
				t1 = r
			end
		end
	end

	return ax + t0 * dx, ay + t0 * dy, ax + t1 * dx, ay + t1 * dy
end

-- O RECORTE É À MÃO porque `ClipsDescendants` não recorta GuiObject rotacionado: o card tem Rotation
-- 0 e some na borda, a linha tem Rotation de atan2 e continuava desenhada por cima do jogo, fora da
-- janela. Não há propriedade que conserte — o jeito é o segmento nunca passar da borda.
local function positionLink(link, minX, minY, maxX, maxY)
	local ax, ay = centreOf(link.parentKey)
	local bx, by = centreOf(link.childKey)

	local cax, cay, cbx, cby = clipSegment(ax, ay, bx, by, minX, minY, maxX, maxY)
	if not cax then
		link.line.Visible = false
		return
	end
	link.line.Visible = true

	local dx, dy = cbx - cax, cby - cay
	link.line.Position = UDim2.fromOffset((cax + cbx) / 2, (cay + cby) / 2)
	link.line.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), LINK_W)
	-- Ângulo do segmento INTEIRO: no recortado quase nulo o atan2 fica instável e a linha treme.
	link.line.Rotation = math.deg(math.atan2(by - ay, bx - ax))
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

-- ==================================================================== ARRANJOS

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

-- Aplicar um arranjo é MARCÁ-LO: é essa marca que a próxima abertura reabre. `keepCamera` guarda a
-- escala da janela: na restauração de sessão o zoom do arranjo engoliria o zoom com que o autor
-- deixou a ferramenta, e o zoom lembrado nunca apareceria. No clique manual é o contrário.
local function loadProfile(name, keepCamera)
	if not name then
		return false
	end
	local loaded = layoutCall("layout_load", DOCK_KEY, name)
	if not (loaded and loaded.ok and loaded.cards) then
		return false
	end
	applyCards(loaded.cards)
	if loaded.zoom and not keepCamera then
		setZoom(loaded.zoom)
	end
	state.marks.last = name
	setStatus("arranjo '" .. name .. "'")
	return true
end

-- Manda o último marcado; sem ele, o primeiro que o autor criou. Sem nenhum dos dois fica o arranjo
-- automático — o que não pode é a janela voltar ao automático tendo desenho salvo.
local function restoreLayout()
	if loadProfile(state.marks.last, true) then
		return
	end
	loadProfile(state.marks.first, true)
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

-- Assinatura no servidor e publicação para a câmera livre, sem tocar no desenho: fechar a janela
-- passa por aqui, e é o que deixa o sujeito lembrado ao reabrir.
local function subscribe(agentId)
	invoke({ op = "Watch", agentId = agentId })
	WatchedNpc.Set(agentId, if agentId then state.classOf[agentId] else nil)
end

local function watch(agentId)
	state.watching = agentId
	subscribe(agentId)
	ui.chip.Text = agentId or "nenhum NPC"

	if not agentId then
		clearGraph()
		return
	end
	if state.marks.npc ~= agentId then
		state.marks.npc = agentId
		layoutCall("npc_set", DOCK_KEY, agentId)
	end

	local result = invoke({ op = "Tree", agentId = agentId })
	if result and result.ok then
		buildGraph(result.tree)
		setStatus(agentId)
		restoreLayout()
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
			-- A câmera do canvas vai junto: restaurar 8× sem restaurar PARA ONDE ela apontava reabre
			-- num pedaço vazio do mundo, e a escala lembrada parece quebrada.
			layoutCall("geom_set", DOCK_KEY, {
				x = window.AbsolutePosition.X,
				y = window.AbsolutePosition.Y,
				w = window.AbsoluteSize.X,
				h = window.AbsoluteSize.Y,
				zoom = state.zoom,
				px = ui.world.Position.X.Offset,
				py = ui.world.Position.Y.Offset,
			})
		end)
	end
	window:GetPropertyChangedSignal("Position"):Connect(saveGeometry)
	window:GetPropertyChangedSignal("Size"):Connect(saveGeometry)
	touchGeometry = saveGeometry

	-- Chip do NPC observado, na própria barra de título: é o seletor e o rótulo ao mesmo tempo.
	local chip = PanelTheme.Button(bar, "Chip", "nenhum NPC", CHIP_W)
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.new(1, -CHIP_RIGHT, 0.5, 0)
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
	-- A geometria da linha fica em constantes porque o painel é ancorado pela BORDA DIREITA do botão
	-- que o abre: mover o botão sem mover o painel desalinha os dois, e desalinho de 8 px é o que
	-- ninguém reporta e todo mundo vê.
	local FOOT_X, ROW_Y, ROW_GAP = 10, 60, 6
	local NAME_W, SAVE_W, LIST_BTN_W = 150, 76, 82
	local SAVE_X = FOOT_X + NAME_W + ROW_GAP
	local LIST_BTN_X = SAVE_X + SAVE_W + ROW_GAP

	local nameBox = PanelTheme.TextBox(footer, "ProfileName", "nome do arranjo", NAME_W)
	nameBox.Position = UDim2.fromOffset(FOOT_X, ROW_Y)

	local saveButton = PanelTheme.Button(footer, "Btn_SalvarArranjo", "SALVAR", SAVE_W)
	saveButton.Position = UDim2.fromOffset(SAVE_X, ROW_Y)

	local listButton = PanelTheme.Button(footer, "Btn_Arranjos", "ARRANJOS", LIST_BTN_W)
	listButton.Position = UDim2.fromOffset(LIST_BTN_X, ROW_Y)

	-- Sobe ACIMA do botão, nunca por cima dele, e cresce para a ESQUERDA: ancorado pela esquerda ele
	-- se estica na direção da borda da janela e sai por ela.
	local PROF_W, PROF_H = 210, 140
	local profPanel, profScroll = PanelTheme.SlotPanel(window, "ARRANJOS SALVOS", PROF_W, PROF_H)
	profPanel.AnchorPoint = Vector2.new(1, 1)
	profPanel.Position = UDim2.new(0, LIST_BTN_X + LIST_BTN_W, 1, -(FOOT_H + PanelTheme.SlotPanelGap()))

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
			local label = if name == state.marks.first then name .. "  ·  padrão" else name
			local _row, pick, del = PanelTheme.SlotRow(profScroll, label, index)
			pick.Activated:Connect(function()
				if loadProfile(name) then
					nameBox.Text = name
				end
				profPanel.Visible = false
			end)
			del.Activated:Connect(function()
				layoutCall("layout_delete", DOCK_KEY, name)
				state.marks.first = if state.marks.first == name then nil else state.marks.first
				state.marks.last = if state.marks.last == name then nil else state.marks.last
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
		local result = layoutCall("layout_save", DOCK_KEY, {
			name = name,
			cards = currentCards(),
			zoom = state.zoom,
		})
		if result and result.ok then
			state.marks.first = state.marks.first or name
			state.marks.last = name
		end
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
		saveGeometry()
	end)

	local LIST_W, LIST_H = 210, 150
	local listPanel, listScroll = PanelTheme.SlotPanel(window, "NPCs NO MUNDO", LIST_W, LIST_H)
	-- Desce do chip e alinha pela MESMA borda dele; estava 50 px à direita, solto do botão que o abre.
	listPanel.AnchorPoint = Vector2.new(1, 0)
	listPanel.Position = UDim2.new(1, -CHIP_RIGHT, 0, metrics.TITLE_H + PanelTheme.SlotPanelGap())

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
			return agents
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
		return agents
	end

	-- Abrir sem sujeito não pode dar tela vazia: vale o último visto se ele ainda existe, senão um
	-- corpo qualquer do mundo.
	local function pickAgent(agents)
		for _, entry in ipairs(agents) do
			if entry.id == state.marks.npc then
				return entry.id
			end
		end
		return if #agents > 0 then agents[math.random(#agents)].id else nil
	end

	-- Mundo ainda sem corpo: insiste enquanto a janela seguir aberta e sem sujeito.
	local function chaseAgent()
		task.spawn(function()
			for _ = 1, NPC_RETRIES do
				task.wait(NPC_RETRY)
				if not window.Visible or state.watching then
					return
				end
				local chosen = pickAgent(refreshList())
				if chosen then
					watch(chosen)
					return
				end
			end
		end)
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
			local agents = refreshList()
			-- Desenho já montado nesta sessão volta como está; só reassina. Remontar aqui jogaria
			-- fora os cards que o autor arrastou desde a última vez.
			if state.watching and next(state.cards) then
				subscribe(state.watching)
			else
				local chosen = pickAgent(agents)
				watch(chosen)
				if not chosen then
					chaseAgent()
				end
			end
		else
			listPanel.Visible = false
			subscribe(nil)
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

	-- Depois de a janela inteira existir: a restauração mexe no mundo e na escala, que nascem acima.
	task.spawn(function()
		local saved = layoutCall("geom_get", DOCK_KEY)
		local box = saved and saved.geom
		if not box then
			return
		end
		window.AnchorPoint = Vector2.zero
		window.Size = UDim2.fromOffset(box.w, box.h)

		-- Presa à tela: geometria gravada com a janela encostada na borda de um monitor maior reabre
		-- fora da vista, e o único resgate seria adivinhar para onde arrastar o que não se enxerga.
		local camera = Workspace.CurrentCamera
		local x, y = box.x, box.y
		if camera then
			local view = camera.ViewportSize
			x = math.clamp(x, 0, math.max(view.X - box.w, 0))
			y = math.clamp(y, 0, math.max(view.Y - box.h, 0))
		end
		window.Position = UDim2.fromOffset(x, y)

		if box.zoom then
			setZoom(box.zoom)
		end
		if box.px and box.py then
			ui.world.Position = UDim2.fromOffset(box.px, box.py)
			relayoutLinks()
		end
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
	-- Opcional: sem ele a janela funciona, só não lembra geometria, arranjo nem sujeito.
	local tool = remotes:FindFirstChild("ToolLayout")
	layoutFn = if tool and tool:IsA("RemoteFunction") then tool else nil

	local allowed = invoke({ op = "IsAuthorized" })
	if not allowed or not allowed.ok then
		return
	end

	-- Antes da janela: a primeira abertura já escolhe arranjo e NPC a partir daqui.
	local marks = layoutCall("mark_get", DOCK_KEY)
	state.marks = (marks and marks.mark) or {}

	buildGui()
	snapshot.OnClientEvent:Connect(onSnapshot)

	if DockMemory.Load()[DOCK_KEY] and applyOpen then
		applyOpen(true)
	end
end

return BrainMonitorClient
