--!strict
-- RouteBuilderClient (cliente / UI) — a janela do Route Builder: aponta, clica e PEDE. Quem valida
-- e aplica é RouteBuilderServer (allowlist, rate-limit, bounds); o cliente não decide nada. Só
-- constrói GUI para jogador autorizado, e desenha os nós localmente pelo payload de visuais.
--
-- Contrato de seleção: os nós nascem CanQuery=false (Lib/RouteNodeRenderer), então raycast não os
-- acerta — toda escolha de nó é distância LATERAL da reta da mira, nunca hit de raio.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
local RouteData = require(Shared:WaitForChild("Npc"):WaitForChild("RouteData"))

local Lib = script.Parent.Parent:WaitForChild("Lib")
local PanelTheme = require(Lib:WaitForChild("PanelTheme"))
local DockMemory = require(Lib:WaitForChild("DockMemory"))
local RouteNodeRenderer = require(Lib:WaitForChild("RouteNodeRenderer"))

local RouteBuilderClient = {}

-- Chave desta janela no registro da barra (remote ToolLayout); chave fora da lista do servidor é podada.
local DOCK_KEY = "routes"

-- s de espera por cada remote antes de degradar (sem builder no servidor, sem ferramenta).
local REMOTE_WAIT = 10

-- Pastas só-de-olhar que a persiana apaga; nenhuma participa de lógica.
local DEBUG_FOLDERS = { NpcConfig.NODE_FOLDER_NAME, "NpcPathDebug", "NpcVisionDebug" }

-- studs; folga da mira para um nó contar como clicado, e alcance do raycast de colocação.
local PICK_RADIUS = 6
local PLACE_RANGE = 500

-- px; BODY_W é a largura ÚTIL do corpo e o teto de qualquer linha (ver `spread`).
local BUTTON_W = 88
local BUTTON_GAP = 6
local ROW_GAP = 6
local BODY_PAD = 10
local BODY_COLUMNS = 3
local BODY_W = BUTTON_W * BODY_COLUMNS + BUTTON_GAP * (BODY_COLUMNS - 1)
local WINDOW_W = BODY_W + BODY_PAD * 2
-- Altura que cabe TODAS as linhas sem rolar, com a de escuta aberta: linha empurrada para o scroll
-- some da vista, e a barra tem 4px.
local WINDOW_H = 376
local WINDOW_MIN = Vector2.new(WINDOW_W, 140)
local WINDOW_MAX = Vector2.new(760, 900)

-- Um routeType de RouteData (colocação) ou um modo de edição; "None" é nenhum.
type Mode = string

local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local applyOpen: ((boolean) -> ())? = nil
local modeButtons: { [string]: TextButton } = {}
local modeTints: { [string]: Color3 } = {}
local mode: Mode = "None"
local pendingNodeId: string? = nil
local npcPaused = true
local trailSpacing = NpcConfig.BUILDER_TRAIL_SPACING
local moveChain = 0
local refreshBuilderLabels: () -> () = function() end
local areaTargetId: string? = nil
local refreshSenseControl: () -> () = function() end
local refreshClassControl: () -> () = function() end

local function setStatus(text: string)
	if statusLabel then
		(statusLabel :: TextLabel).Text = text
	end
end

-- ==================================================================== PERSIANA DO DIAGNÓSTICO
-- Só-cliente: LocalTransparencyModifier não replica e nada daqui desliga lógica de servidor.

local debugHidden = false
local debugWatchers: { RBXScriptConnection } = {}

local persianaButton: TextButton? = nil
local dockHiddenSlots: { TextButton } = {}
local dockWatcher: RBXScriptConnection? = nil

local function refreshDockVisibility()
	if dockWatcher then
		(dockWatcher :: RBXScriptConnection):Disconnect()
		dockWatcher = nil
	end

	if not debugHidden then
		for _, button in ipairs(dockHiddenSlots) do
			if button.Parent then
				button.Visible = true
			end
		end
		table.clear(dockHiddenSlots)
		return
	end

	local function survives(child: Instance): boolean
		return child == persianaButton or PanelTheme.IsSlotPersistent(child)
	end

	table.clear(dockHiddenSlots)
	local rail = PanelTheme.Dock()
	for _, child in ipairs(rail:GetChildren()) do
		if child:IsA("TextButton") and not survives(child) and child.Visible then
			child.Visible = false
			table.insert(dockHiddenSlots, child :: TextButton)
		end
	end
	dockWatcher = rail.ChildAdded:Connect(function(child: Instance)
		if child:IsA("TextButton") and not survives(child) and child.Visible then
			child.Visible = false
			table.insert(dockHiddenSlots, child :: TextButton)
		end
	end)
end

local function applyHidden(inst: Instance, hidden: boolean)
	if inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = if hidden then 1 else 0
	elseif inst:IsA("BillboardGui") or inst:IsA("SurfaceGui") then
		inst.Enabled = not hidden
	elseif inst:IsA("SelectionBox") or inst:IsA("BoxHandleAdornment") then
		inst.Visible = not hidden
	end
end

local function refreshDebugVisibility()
	for _, connection in ipairs(debugWatchers) do
		connection:Disconnect()
	end
	table.clear(debugWatchers)

	for _, folderName in ipairs(DEBUG_FOLDERS) do
		local folder = Workspace:FindFirstChild(folderName)
		if folder then
			for _, inst in ipairs(folder:GetDescendants()) do
				applyHidden(inst, debugHidden)
			end
			if debugHidden then
				table.insert(debugWatchers, folder.DescendantAdded:Connect(function(inst: Instance)
					applyHidden(inst, true)
				end))
			end
		end
	end

	if debugHidden then
		table.insert(debugWatchers, Workspace.ChildAdded:Connect(function(child: Instance)
			for _, folderName in ipairs(DEBUG_FOLDERS) do
				if child.Name == folderName then
					refreshDebugVisibility()
					break
				end
			end
		end))
	end
end

-- ==================================================================================== PLACAR

local statsLabel: TextLabel? = nil

-- Rótulo humano por rede; tipo sem entrada cai no próprio nome em maiúsculas.
local TYPE_LABELS: { [string]: string } = {
	Main = "PRINCIPAL",
	Citizen = "CIVIL",
	Medic = "MÉDICO",
	Guard = "GUARDA",
	Detective = "DETETIVE",
}

local function typeLabel(routeType: string): string
	return TYPE_LABELS[routeType] or string.upper(routeType)
end

-- Ordem dos botões: Main, depois NpcConfig.Classes, depois o resto do enum. Derivada, nunca digitada.
local function routeTypeOrder(): { string }
	local ordered: { string } = {}
	local seen: { [string]: boolean } = {}

	local function push(routeType: string)
		if not seen[routeType] and RouteData.IsValidType(routeType) then
			seen[routeType] = true
			table.insert(ordered, routeType)
		end
	end

	push(RouteData.RouteType.Main)
	for _, class in ipairs(NpcConfig.Classes) do
		push(class)
	end

	local rest: { string } = {}
	for routeType in pairs(RouteData.RouteType) do
		if not seen[routeType] then
			table.insert(rest, routeType)
		end
	end
	table.sort(rest)
	for _, routeType in ipairs(rest) do
		push(routeType)
	end
	return ordered
end

-- Fração do orçamento a partir da qual o placar muda de cor.
local STATS_WARN_AT = 0.9

local function applyStats(payload: any)
	local label = statsLabel
	if not label or type(payload) ~= "table" then
		return
	end
	local total = tonumber(payload.total) or 0
	local components = tonumber(payload.components) or 0
	local largest = tonumber(payload.largest) or 0
	local orphans = tonumber(payload.orphans) or 0
	local maxTotal = tonumber(payload.maxTotal) or 1
	local maxComponents = tonumber(payload.maxComponents) or 1
	local maxLargest = tonumber(payload.maxLargest) or 1

	local mainX = tonumber(payload.mainSpanX) or 0
	local mainZ = tonumber(payload.mainSpanZ) or 0
	local mapX = math.max(tonumber(payload.mapSpanX) or 1, 1)
	local mapZ = math.max(tonumber(payload.mapSpanZ) or 1, 1)
	local coverage = (mainX * mainZ) / (mapX * mapZ) * 100

	local text = string.format("nós %d/%d · peças %d/%d · malha %.0fx%.0f (%.0f%% da planta)",
		total, maxTotal, components, maxComponents, mainX, mainZ, coverage)
	if orphans > 0 then
		text ..= string.format(" · %d nó(s) SOLTO(s)", orphans)
	end
	;(label :: TextLabel).Text = text

	local pressure = math.max(
		total / math.max(maxTotal, 1),
		components / math.max(maxComponents, 1),
		largest / math.max(maxLargest, 1))
	local tooSmall = total > 0 and coverage < 20
	;(label :: TextLabel).TextColor3 = if orphans > 0 or tooSmall or pressure >= STATS_WARN_AT
		then Color3.fromRGB(255, 120, 90)
		else PanelTheme.Color.TextDim

	if type(payload.reason) == "string" then
		setStatus("recusado: " .. payload.reason)
	end
end

-- Degrau pelo valor de DESTINO ao descer e pelo ATUAL ao subir: só assim a faixa fina não é pulada.
local function spacingStep(delta: number): number
	local reference = if delta < 0 then trailSpacing - 0.001 else trailSpacing + 0.001
	if reference <= NpcConfig.BUILDER_TRAIL_SPACING_FINE then
		return NpcConfig.BUILDER_TRAIL_SPACING_STEP_FINE
	end
	return NpcConfig.BUILDER_TRAIL_SPACING_STEP
end

local function nudgeSpacing(delta: number)
	local step = spacingStep(delta)
	local direction = if delta < 0 then -1 else 1
	trailSpacing = math.clamp(
		trailSpacing + direction * step,
		NpcConfig.BUILDER_TRAIL_SPACING_MIN,
		NpcConfig.BUILDER_TRAIL_SPACING_MAX
	)
	refreshBuilderLabels()
	setStatus(string.format("sub-ponto a cada %.1f studs", trailSpacing))
end

local function nudgeChain(delta: number)
	moveChain = math.clamp(moveChain + delta, 0, NpcConfig.BUILDER_MOVE_CHAIN_MAX)
	refreshBuilderLabels()
	setStatus(if moveChain == 0
		then "corrente desligada: move só o ponto escolhido"
		else string.format("corrente: %d ponto(s) acompanham, com queda suave", moveChain))
end

local opEvent: RemoteEvent? = nil
local queryFn: RemoteFunction? = nil

-- Declarados antes de setMode, que os chama; as definições vêm adiante.
local clearMoveHandles: () -> ()
local abortTrail: () -> ()
local abortSubdivide: () -> () = function() end

local function setMode(newMode: Mode)
	mode = newMode
	pendingNodeId = nil
	if newMode ~= "Move" then
		clearMoveHandles()
	end
	if newMode ~= "Area" then
		areaTargetId = nil
	end
	refreshSenseControl()
	abortTrail()
	abortSubdivide()
	for name, button in pairs(modeButtons) do
		local tint = modeTints[name] or PanelTheme.Color.Accent
		local active = name == newMode
		button.BackgroundColor3 = if active then tint else PanelTheme.Color.Surface
		button.TextColor3 = if active then PanelTheme.Color.TextInk else tint
	end
	refreshClassControl()
	if newMode == "None" then
		setStatus("")
	end
end

-- ====================================================================================== MIRA

-- Mouse pelo UnitRay do engine: GetMouseLocation já vem em viewport, subtrair GuiInset dá 2.9° de erro.
-- Toque pelo ScreenPointToRay: InputObject.Position já desconta o inset, e ViewportPointToRay não.
local function aimRay(input: InputObject?): Ray?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	if input and input.UserInputType == Enum.UserInputType.Touch then
		return camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	end
	return player:GetMouse().UnitRay
end

-- Nem o desenho nem corpo de NPC são chão: nó autorado em cima deles ficaria onde o NPC parou.
local function worldRayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if player.Character then
		table.insert(exclude, player.Character :: Model)
	end
	for _, name in ipairs({ NpcConfig.NODE_FOLDER_NAME, NpcConfig.BODY_FOLDER }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		end
	end
	params.FilterDescendantsInstances = exclude
	params.RespectCanCollide = true
	return params
end

local function raycastGround(input: InputObject?): RaycastResult?
	local ray = aimRay(input)
	if not ray then
		return nil
	end
	return Workspace:Raycast(ray.Origin, ray.Direction * PLACE_RANGE, worldRayParams())
end

-- Nó mais próximo da reta da mira; o filtro por tipo entra NA BUSCA, nunca depois de escolher.
local function pickNodeId(input: InputObject?, onlyType: string?, radius: number?): string?
	local ray = aimRay(input)
	local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
	if not ray or not folder then
		return nil
	end
	local origin = ray.Origin
	local direction = ray.Direction.Unit
	local bestId: string? = nil
	local bestDistance = radius or PICK_RADIUS
	for _, part in ipairs(folder:GetChildren()) do
		-- Só peça marcada RouteNode: a pasta também guarda os cabos, que não têm id pra devolver.
		if
			part:IsA("BasePart")
			and part:GetAttribute("RouteNode")
			and (onlyType == nil or part:GetAttribute("RouteType") == onlyType)
		then
			local toPart = part.Position - origin
			local along = toPart:Dot(direction)
			if along > 0 and along < PLACE_RANGE then
				local lateral = (toPart - direction * along).Magnitude
				if lateral < bestDistance then
					bestDistance = lateral
					bestId = part.Name
				end
			end
		end
	end
	return bestId
end

local function nodePart(id: string): BasePart?
	local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
	local part = folder and folder:FindFirstChild(id)
	return if part and part:IsA("BasePart") then part else nil
end

-- ============================================================== ESCOLHER UMA LINHA (subdividir)
-- Devolve (idA, idB, fração) da ligação sob a mira. A FRAÇÃO é o que vai pro servidor, nunca posição.
local function pickCable(input: InputObject?): (string?, string?, number?)
	local ray = aimRay(input)
	local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
	if not ray or not folder then
		return nil, nil, nil
	end
	local origin = ray.Origin
	local direction = ray.Direction.Unit

	local bestA: string? = nil
	local bestB: string? = nil
	local bestFraction: number? = nil
	local bestDistance = PICK_RADIUS
	for _, cable in ipairs(folder:GetChildren()) do
		local aId, bId = cable:GetAttribute("LinkA"), cable:GetAttribute("LinkB")
		if cable:IsA("BasePart") and type(aId) == "string" and type(bId) == "string" then
			local partA, partB = nodePart(aId :: string), nodePart(bId :: string)
			if partA and partB then
				local u = direction
				local v = (partB :: BasePart).Position - (partA :: BasePart).Position
				local w = origin - (partA :: BasePart).Position
				local b = u:Dot(v)
				local c = v:Dot(v)
				local d = u:Dot(w)
				local e = v:Dot(w)
				local denom = c - b * b -- u é unitário, então u:Dot(u) == 1
				local fraction = if math.abs(denom) < 1e-4 then 0.5 else math.clamp((e - b * d) / denom, 0, 1)
				local onCable = (partA :: BasePart).Position + v * fraction
				local toCable = onCable - origin
				local along = toCable:Dot(direction)
				if along > 0 and along < PLACE_RANGE then
					local lateral = (toCable - direction * along).Magnitude
					if lateral < bestDistance then
						bestDistance = lateral
						bestA, bestB, bestFraction = aId :: string, bId :: string, fraction
					end
				end
			end
		end
	end
	return bestA, bestB, bestFraction
end

-- ============================================================================= SETAS DE MOVER
-- O clique só ESCOLHE; quem move é a seta. A peça adornada morre no aceite, daí o reatamento por id.

local moveHandles: Handles? = nil
local moveTargetId: string? = nil
local moveOrigin: CFrame? = nil
-- Prévia da corrente, congelada no apertar do botão: peça -> (haste, escuta, posição inicial, fração).
local movePreview: { { part: BasePart, stem: BasePart?, sense: BasePart?, origin: Vector3, factor: number } } = {}
local moveOriginStem: BasePart? = nil
local moveOriginSense: BasePart? = nil
local moveCablePreview: { { part: BasePart, a: BasePart, b: BasePart } } = {}

function clearMoveHandles()
	if moveHandles then
		(moveHandles :: Handles):Destroy()
		moveHandles = nil
	end
	moveTargetId = nil
	moveOrigin = nil
	movePreview = {}
	moveOriginStem = nil
	moveOriginSense = nil
	moveCablePreview = {}
end

local function stemOf(part: BasePart?): BasePart?
	local stem = part and part:FindFirstChild("Stem")
	return if stem and stem:IsA("BasePart") then stem else nil
end

local function senseOf(part: BasePart?): BasePart?
	local sense = part and part:FindFirstChild("Sense")
	return if sense and sense:IsA("BasePart") then sense else nil
end

-- Grafo lido dos adornos das peças, só pra chamar a MESMA RouteData.ChainFactors do servidor;
-- `order`/`waitTime` entram zerados porque ela só lê `links` e `position`.
local function graphFromParts(): RouteData.Graph
	local net: RouteData.Graph = {}
	local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
	if not folder then
		return net
	end
	for _, part in ipairs(folder:GetChildren()) do
		if part:IsA("BasePart") and part:GetAttribute("RouteNode") then
			local links: { string } = {}
			local raw = part:GetAttribute("RouteLinks")
			if type(raw) == "string" and #raw > 0 then
				for id in string.gmatch(raw, "[^,]+") do
					table.insert(links, id)
				end
			end
			net[part.Name] = {
				id = part.Name,
				position = part.Position - Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0),
				routeType = tostring(part:GetAttribute("RouteType")),
				order = 0,
				waitTime = 0,
				links = links,
			}
		end
	end
	return net
end

local function attachMoveHandles(id: string)
	local part = nodePart(id)
	if not part or not gui then
		return
	end
	clearMoveHandles()
	moveTargetId = id

	local handles = Instance.new("Handles")
	handles.Name = "MoveHandles"
	handles.Style = Enum.HandlesStyle.Movement
	handles.Color3 = PanelTheme.Color.Accent
	handles.Transparency = 0.1
	handles.Adornee = part
	handles.Parent = gui
	moveHandles = handles

	handles.MouseButton1Down:Connect(function()
		local target = nodePart(moveTargetId or "")
		moveOrigin = target and target.CFrame or nil
		movePreview = {}
		moveCablePreview = {}
		moveOriginStem = stemOf(target)
		moveOriginSense = senseOf(target)
		if not target then
			return
		end

		local movingIds: { [string]: boolean } = { [moveTargetId :: string] = true }
		if moveChain > 0 then
			local factors = RouteData.ChainFactors(graphFromParts(), moveTargetId :: string, moveChain)
			for nodeId, factor in pairs(factors) do
				local part2 = nodePart(nodeId)
				if part2 and nodeId ~= moveTargetId then
					movingIds[nodeId] = true
					table.insert(movePreview, {
						part = part2,
						stem = stemOf(part2),
						sense = senseOf(part2),
						origin = part2.Position,
						factor = factor,
					})
				end
			end
		end

		local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
		if folder then
			for _, cable in ipairs(folder:GetChildren()) do
				if cable:IsA("BasePart") then
					local aId, bId = cable:GetAttribute("LinkA"), cable:GetAttribute("LinkB")
					if type(aId) == "string" and type(bId) == "string" and (movingIds[aId] or movingIds[bId]) then
						local partA, partB = nodePart(aId), nodePart(bId)
						if partA and partB then
							table.insert(moveCablePreview, { part = cable, a = partA, b = partB })
						end
					end
				end
			end
		end
	end)

	handles.MouseDrag:Connect(function(face: Enum.NormalId, distance: number)
		local target = nodePart(moveTargetId or "")
		if not target or not moveOrigin then
			return
		end
		local delta = Vector3.FromNormalId(face) * distance
		target.CFrame = (moveOrigin :: CFrame) + delta
		-- A fração parte da posição CONGELADA, nunca da atual: senão a prévia diverge do servidor.
		for _, entry in ipairs(movePreview) do
			entry.part.Position = entry.origin + delta * entry.factor
		end

		-- Peças em espaço de MUNDO. ORDEM IMPORTA: as esferas se movem acima, os cabos leem `.Position`.
		local lift = Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0)
		if moveOriginStem then
			(moveOriginStem :: BasePart).CFrame =
				RouteData.StemGeometry(target.Position - lift, NpcConfig.NODE_VISUAL_LIFT)
		end
		if moveOriginSense then
			(moveOriginSense :: BasePart).Position = target.Position
		end
		for _, entry in ipairs(movePreview) do
			if entry.stem then
				(entry.stem :: BasePart).CFrame =
					RouteData.StemGeometry(entry.part.Position - lift, NpcConfig.NODE_VISUAL_LIFT)
			end
			if entry.sense then
				(entry.sense :: BasePart).Position = entry.part.Position
			end
		end
		for _, entry in ipairs(moveCablePreview) do
			local cf, size = RouteData.CableGeometry(entry.a.Position, entry.b.Position, NpcConfig.LINK_THICKNESS)
			if cf then
				entry.part.CFrame = cf :: CFrame
				entry.part.Size = size :: Vector3
			end
		end
	end)

	handles.MouseButton1Up:Connect(function()
		local target = nodePart(moveTargetId or "")
		local id2 = moveTargetId
		moveOrigin = nil
		movePreview = {}
		moveCablePreview = {}
		moveOriginStem = nil
		moveOriginSense = nil
		if not target or not id2 or not opEvent then
			return
		end
		-- De volta pro DADO: a peça é desenhada elevada, o nó salvo é o ponto de chão.
		local ground = target.Position - Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0)
		local remote = opEvent :: RemoteEvent
		remote:FireServer({ op = "Move", id = id2, position = ground, chain = moveChain })
		setStatus(if moveChain > 0
			then string.format("ponto movido · %d ponto(s) acompanharam", moveChain)
			else string.format("ponto movido para (%.0f, %.0f, %.0f)", ground.X, ground.Y, ground.Z))
		task.spawn(function()
			local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
			if folder then
				folder:WaitForChild(id2, 3)
			end
			if mode == "Move" and moveTargetId == id2 then
				attachMoveHandles(id2)
			end
		end)
	end)
end

-- ============================================================================ TRILHA ARRASTADA
-- Clicar e arrastar cria um segmento RETO de nós ligados; a reta é refeita do zero a cada movimento
-- (XZ da reta, Y de sonda vertical) e o envio é UM SÓ, no soltar.

local trailAnchor: Vector3? = nil
local trailAnchorId: string? = nil
local trailPoints: { Vector3 } = {}
local trailGhosts: Folder? = nil
-- Pool das peças de prévia: reaproveitadas, só morrem quando a reta encolhe.
local trailGhostParts: { BasePart } = {}
local trailCableParts: { BasePart } = {}
local trailLastCursor: Vector3? = nil
-- studs; movimento de cursor abaixo disto não reconstrói a trilha.
local REBUILD_EPSILON = 0.75

-- studs; alcance da sonda vertical pra cima e pra baixo da reta.
local PROBE_UP = 200
local PROBE_DOWN = 600

local function clearTrailGhosts()
	if trailGhosts then
		(trailGhosts :: Folder):Destroy()
		trailGhosts = nil
	end
	trailGhostParts = {}
	trailCableParts = {}
	trailLastCursor = nil
end

-- Os modos que colocam nó são exatamente os tipos de rota: pergunte ao modelo, nunca liste à mão.
local function isPlacementMode(): boolean
	return RouteData.IsValidType(mode)
end

function abortTrail()
	trailAnchor = nil
	trailAnchorId = nil
	trailPoints = {}
	clearTrailGhosts()
end

-- Nó existente sob a mira e a posição de CHÃO dele. QUALQUER cor serve de âncora: é por aresta entre
-- cores que uma rede de classe fica alcançável a partir da malha Main.
local function pickSnapNode(input: InputObject?): (string?, Vector3?, string?)
	local id = pickNodeId(input, nil, NpcConfig.BUILDER_SNAP_RADIUS)
	if not id then
		return nil, nil, nil
	end
	local part = nodePart(id)
	if not part then
		return nil, nil, nil
	end
	local snapType = part:GetAttribute("RouteType")
	return id,
		part.Position - Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0),
		if type(snapType) == "string" then snapType else nil
end

local function groundBelow(position: Vector3): Vector3?
	local params = worldRayParams()
	local origin = position + Vector3.new(0, PROBE_UP, 0)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -(PROBE_UP + PROBE_DOWN), 0), params)
	return if hit then hit.Position else nil
end

local function addTrailGhost(position: Vector3, terminal: boolean, index: number)
	if not trailGhosts then
		local created = Instance.new("Folder")
		created.Name = "RouteTrailGhosts"
		created.Parent = Workspace
		trailGhosts = created
	end
	local ball = trailGhostParts[index]
	if not ball then
		ball = Instance.new("Part")
		ball.Name = "TrailGhost"
		ball.Shape = Enum.PartType.Ball
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanTouch = false
		-- CanQuery FALSO é obrigatório: aceso, o fantasma viraria chão pra mira e pra sonda.
		ball.CanQuery = false
		ball.Massless = true
		ball.Material = Enum.Material.Neon
		ball.Parent = trailGhosts
		trailGhostParts[index] = ball
	end
	local size = NpcConfig.NODE_SIZE * (if terminal then 1 else NpcConfig.NODE_SUB_SCALE)
	ball.Size = Vector3.one * size
	ball.Position = position + Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0)
	ball.Transparency = if terminal then 0.3 else 0.5
	ball.Color = NpcConfig.NODE_COLORS[mode] or Color3.fromRGB(255, 255, 255)
end

local function addTrailCable(a: Vector3, b: Vector3, index: number)
	local lift = Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0)
	local cf, size = RouteData.CableGeometry(a + lift, b + lift, NpcConfig.LINK_THICKNESS)
	if not cf then
		return
	end
	local cable = trailCableParts[index]
	if not cable then
		cable = Instance.new("Part")
		cable.Name = "TrailGhostCable"
		cable.Shape = Enum.PartType.Cylinder
		cable.Anchored = true
		cable.CanCollide = false
		cable.CanTouch = false
		cable.CanQuery = false
		cable.Massless = true
		cable.Material = Enum.Material.Neon
		cable.Transparency = 0.55
		cable.Parent = trailGhosts
		trailCableParts[index] = cable
	end
	cable.CFrame = cf :: CFrame
	cable.Size = size :: Vector3
	cable.Color = NpcConfig.NODE_COLORS[mode] or Color3.fromRGB(255, 255, 255)
end

local function trimTrailGhosts(count: number)
	for index = #trailGhostParts, count + 1, -1 do
		trailGhostParts[index]:Destroy()
		trailGhostParts[index] = nil
	end
	for index = #trailCableParts, math.max(count - 1, 0) + 1, -1 do
		trailCableParts[index]:Destroy()
		trailCableParts[index] = nil
	end
end

local function rebuildTrail(cursor: Vector3)
	local anchor = trailAnchor
	if not anchor then
		return
	end
	if trailLastCursor and (cursor - (trailLastCursor :: Vector3)).Magnitude < REBUILD_EPSILON then
		return
	end
	trailLastCursor = cursor

	local delta = Vector3.new(cursor.X - anchor.X, 0, cursor.Z - anchor.Z)
	local span = delta.Magnitude

	local points: { Vector3 } = { anchor }
	if span > 0.5 then
		local direction = delta.Unit
		local room = NpcConfig.BUILDER_MAX_TRAIL_NODES - 2
		local steps = math.min(math.floor(span / trailSpacing), math.max(room, 0))
		for index = 1, steps do
			local distance = index * trailSpacing
			if span - distance >= trailSpacing * 0.5 then
				local ground = groundBelow(anchor + direction * distance)
				if ground then
					table.insert(points, ground)
				end
			end
		end
		table.insert(points, cursor)
	end

	trailPoints = points
	for index, position in ipairs(points) do
		addTrailGhost(position, index == 1 or index == #points, index)
		if index > 1 then
			addTrailCable(points[index - 1], position, index - 1)
		end
	end
	trimTrailGhosts(#points)

	if #points > 1 then
		setStatus(string.format("reta de %.0f studs · %d nós · solte para criar", span, #points))
	else
		setStatus("arraste para esticar a reta · solte para criar")
	end
end

local function finishTrail()
	local points = trailPoints
	local fromId = trailAnchorId
	trailAnchor = nil
	trailAnchorId = nil
	trailPoints = {}
	clearTrailGhosts()

	local event = opEvent
	if not event or #points == 0 or not isPlacementMode() then
		return
	end

	if fromId then
		local fresh = table.move(points, 2, #points, 1, {})
		if #fresh == 0 then
			setStatus("arraste para longe do nó para esticar a linha")
			return
		end
		(event :: RemoteEvent):FireServer({
			op = "AddTrail",
			positions = fresh,
			routeType = mode,
			fromId = fromId,
		})
		setStatus(string.format("linha nova: %d nós a partir do nó existente", #fresh))
		return
	end

	if #points == 1 then
		(event :: RemoteEvent):FireServer({ op = "Add", position = points[1], routeType = mode })
		setStatus(string.format("nó %s em (%.0f, %.0f, %.0f)", mode, points[1].X, points[1].Y, points[1].Z))
		return
	end
	(event :: RemoteEvent):FireServer({ op = "AddTrail", positions = points, routeType = mode })
	setStatus(string.format("trilha %s: %d nós ligados em sequência", mode, #points))
end

-- ======================================================= ARRASTO DE SUBDIVISÃO (modo DIVIDIR)
-- O arrasto escolhe QUAIS linhas: cada aresta pintada é dividida de ponta a ponta, em partes iguais.

type PaintedEdge = { a: string, b: string }
local subdividePaint: { PaintedEdge } = {}
local subdivideAt: { [string]: number } = {}
local subdivideGhosts: { BasePart } = {}
local subdivideLastKey: string? = nil

-- Chave sem direção, igual à do desenho dos cabos: (A,B) e (B,A) têm que cair no mesmo trecho.
local function edgeKey(aId: string, bId: string): string
	return if aId < bId then aId .. "|" .. bId else bId .. "|" .. aId
end

-- Frações que dividem a aresta em partes iguais, mais o vão real em studs.
local function subdivideFractions(aId: string, bId: string): ({ number }, number)
	local partA, partB = nodePart(aId), nodePart(bId)
	if not partA or not partB then
		return {}, 0
	end
	local length = ((partB :: BasePart).Position - (partA :: BasePart).Position).Magnitude
	if length < 0.01 then
		return {}, 0
	end
	local parts = math.max(1, math.floor(length / trailSpacing + 0.5))
	local out: { number } = {}
	for index = 1, parts - 1 do
		table.insert(out, index / parts)
	end
	return out, length / parts
end

local function clearSubdividePreview()
	for _, part in ipairs(subdivideGhosts) do
		part:Destroy()
	end
	subdivideGhosts = {}
	subdivideLastKey = nil
end

-- Uma entrada por aresta pintada. Teto GLOBAL, e aresta INTEIRA ou nenhuma.
local function subdividePlan(): ({ { fromId: string, toId: string, fractions: { number } } }, number)
	local plan = {}
	local budget = NpcConfig.BUILDER_MAX_TRAIL_NODES
	local gapSum, gapCount = 0, 0
	for _, edge in ipairs(subdividePaint) do
		if budget <= 0 then
			break
		end
		local fractions, gap = subdivideFractions(edge.a, edge.b)
		if #fractions > 0 and #fractions <= budget then
			budget -= #fractions
			gapSum += gap
			gapCount += 1
			table.insert(plan, { fromId = edge.a, toId = edge.b, fractions = fractions })
		end
	end
	return plan, if gapCount > 0 then gapSum / gapCount else 0
end

local function rebuildSubdividePreview()
	if #subdividePaint == 0 then
		return
	end
	local plan, gap = subdividePlan()
	local slot = 0
	local total = 0
	for _, entry in ipairs(plan) do
		local partA, partB = nodePart(entry.fromId), nodePart(entry.toId)
		if partA and partB then
			local origin = (partA :: BasePart).Position
			local span = (partB :: BasePart).Position - origin
			for _, fraction in ipairs(entry.fractions) do
				slot += 1
				local ghost = subdivideGhosts[slot]
				if not ghost then
					ghost = Instance.new("Part")
					ghost.Shape = Enum.PartType.Ball
					ghost.Size = Vector3.one * (NpcConfig.NODE_SIZE * NpcConfig.NODE_SUB_SCALE)
					ghost.Anchored = true
					ghost.CanCollide = false
					ghost.CanQuery = false -- invisível ao raio da mira, como os nós de verdade
					ghost.CastShadow = false
					ghost.Material = Enum.Material.Neon
					ghost.Color = PanelTheme.Color.Accent
					ghost.Transparency = 0.35
					ghost.Parent = Workspace
					subdivideGhosts[slot] = ghost
				end
				ghost.Position = origin + span * fraction
				total += 1
			end
		end
	end
	for index = slot + 1, #subdivideGhosts do
		subdivideGhosts[index]:Destroy()
		subdivideGhosts[index] = nil
	end
	setStatus(string.format(
		"%d ponto(s) em %d linha(s), vãos de %.1f studs — solte para confirmar",
		total,
		#plan,
		gap
	))
end

local function paintEdge(aId: string, bId: string)
	local key = edgeKey(aId, bId)
	if subdivideAt[key] == nil then
		table.insert(subdividePaint, { a = aId, b = bId })
		subdivideAt[key] = #subdividePaint
	end
end

abortSubdivide = function()
	subdividePaint = {}
	subdivideAt = {}
	clearSubdividePreview()
end

local function finishSubdivide()
	if #subdividePaint == 0 then
		return
	end
	local plan, gap = subdividePlan()
	subdividePaint = {}
	subdivideAt = {}
	clearSubdividePreview()
	if #plan == 0 or not opEvent then
		return
	end
	local total = 0
	for _, entry in ipairs(plan) do
		total += #entry.fractions
	end
	;(opEvent :: RemoteEvent):FireServer({ op = "Subdivide", edges = plan })
	setStatus(string.format("%d ponto(s) em %d linha(s), vãos de %.1f studs", total, #plan, gap))
end

-- ==================================================================================== CLIQUE

local function handleClick(input: InputObject?)
	local event = opEvent
	if not event then
		return
	end

	if isPlacementMode() then
		local snapId, snapGround, snapType = pickSnapNode(input)
		local anchorPosition = snapGround
		if not anchorPosition then
			local hit = raycastGround(input)
			anchorPosition = hit and hit.Position or nil
		end
		if anchorPosition then
			abortTrail()
			trailAnchorId = snapId
			trailAnchor = anchorPosition
			trailPoints = { anchorPosition :: Vector3 }
			addTrailGhost(anchorPosition :: Vector3, true, 1)
			local message
			if snapId == nil then
				message = "arraste para esticar a reta · solte para criar"
			elseif snapType ~= nil and snapType ~= mode then
				message = string.format("JUNÇÃO com a rede %s · arraste", typeLabel(snapType :: string))
			else
				message = "linha nova a partir do ponto existente · arraste"
			end
			setStatus(message)
		end
		return
	end

	if mode == "Delete" then
		local id = pickNodeId(input)
		if id then
			(event :: RemoteEvent):FireServer({ op = "Delete", id = id })
			setStatus("nó apagado")
		end
		return
	end

	if mode == "Move" then
		local id = pickNodeId(input)
		if id then
			attachMoveHandles(id)
			setStatus("arraste as setas para posicionar")
		else
			setStatus("clique mais perto de um nó")
		end
		return
	end

	if mode == "Subdivide" then
		local aId, bId = pickCable(input)
		if aId and bId then
			abortSubdivide()
			paintEdge(aId :: string, bId :: string)
			rebuildSubdividePreview()
		else
			setStatus("clique mais perto de uma linha")
		end
		return
	end

	if mode == "Area" then
		local id = pickNodeId(input)
		if not id or not nodePart(id) then
			setStatus("clique mais perto de um nó")
			return
		end
		areaTargetId = id
		refreshSenseControl()
		setStatus("digite o alcance em studs · vazio volta ao padrão")
		return
	end

	if mode == "Link" then
		local id = pickNodeId(input)
		if not id then
			setStatus("clique mais perto de um nó")
			return
		end
		if not pendingNodeId then
			pendingNodeId = id
			setStatus("primeira ponta — clique na segunda")
		elseif pendingNodeId ~= id then
			(event :: RemoteEvent):FireServer({ op = "Link", fromId = pendingNodeId, toId = id })
			setStatus("ligação alternada")
			pendingNodeId = nil
		end
		return
	end
end

-- ======================================================================================= GUI

local function makeButton(parent: Instance, label: string, order: number, tint: Color3?, width: number?): TextButton
	local button = PanelTheme.Button(parent, "Btn_" .. label, label, width or BUTTON_W, tint)
	button.LayoutOrder = order
	-- Sem largura explícita = ELÁSTICO; com largura, fixo (ver `spread`).
	if width == nil then
		button:SetAttribute("Flex", true)
	end
	return button
end

-- Reparte a largura entre os elásticos, em ESCALA: redimensionar reacomoda sem listener de resize.
local function spread(row: Frame)
	local flexible: { GuiObject } = {}
	local fixedWidth = 0
	local count = 0
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("GuiObject") then
			count += 1
			if child:GetAttribute("Flex") then
				table.insert(flexible, child)
			else
				fixedWidth += child.Size.X.Offset
			end
		end
	end
	if #flexible == 0 then
		return
	end
	local committed = fixedWidth + BUTTON_GAP * math.max(count - 1, 0)
	local share = 1 / #flexible
	local reserve = committed / #flexible
	for _, child in ipairs(flexible) do
		child.Size = UDim2.new(share, -reserve, 0, child.Size.Y.Offset)
	end
end

local function buildGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local metrics = PanelTheme.Metrics

	local screen = Instance.new("ScreenGui")
	screen.Name = "RouteBuilderGui"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1000 -- as janelas ficam abaixo da barra de botões (1001)
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui = screen

	-- 📍 e não 🛣: a fonte de emoji do Roblox não traz o glifo de estrada (sai caixa vazia).
	local toggle = PanelTheme.LauncherSlot("RouteLauncher", "📍", 2)

	local window = Instance.new("Frame")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(1, 0.5)
	window.Position = UDim2.new(1, -metrics.WINDOW_MARGIN, 0.5, 0)
	window.Size = UDim2.fromOffset(WINDOW_W, WINDOW_H)
	window.BackgroundColor3 = PanelTheme.Color.Void
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.Visible = false
	window.Parent = screen
	PanelTheme.Edge(window, PanelTheme.Color.Accent)

	local bar, _title, minimize = PanelTheme.TitleBar(window, "◈  ROUTE BUILDER")

	PanelTheme.MakeDraggable(bar, nil, function(delta: Vector2)
		window.Position = UDim2.new(
			window.Position.X.Scale,
			window.Position.X.Offset + delta.X,
			window.Position.Y.Scale,
			window.Position.Y.Offset + delta.Y
		)
	end)
	PanelTheme.ResizeGrip(window, WINDOW_MIN, WINDOW_MAX)

	local body = Instance.new("ScrollingFrame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, metrics.TITLE_H)
	body.Size = UDim2.new(1, 0, 1, -metrics.TITLE_H)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ScrollBarThickness = 4
	body.ScrollBarImageColor3 = PanelTheme.Color.ChromeDim
	body.CanvasSize = UDim2.fromOffset(0, 0)
	body.AutomaticCanvasSize = Enum.AutomaticSize.Y
	body.Parent = window
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, BODY_PAD)
	padding.PaddingRight = UDim.new(0, BODY_PAD)
	padding.Parent = body
	local column = Instance.new("UIListLayout")
	column.FillDirection = Enum.FillDirection.Vertical
	column.HorizontalAlignment = Enum.HorizontalAlignment.Left
	column.SortOrder = Enum.SortOrder.LayoutOrder
	column.Padding = UDim.new(0, ROW_GAP)
	column.Parent = body

	-- Contador: as seções são derivadas, então nenhum LayoutOrder é fixo.
	local orderCounter = 0
	local function nextOrder(): number
		orderCounter += 1
		return orderCounter
	end

	local function sectionLabel(caption: string, order: number)
		local label = PanelTheme.Text(body, "Sec_" .. caption, 9, Enum.Font.GothamBold, PanelTheme.Color.TextDim)
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, 12)
		label.Text = caption
	end

	local function makeRow(order: number): Frame
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, metrics.BUTTON_H)
		row.BackgroundTransparency = 1
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Horizontal
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, BUTTON_GAP)
		layout.Parent = row
		row.Parent = body
		row.ChildAdded:Connect(function()
			task.defer(spread, row)
		end)
		return row
	end

	-- Uma linha por RouteType na lista, na cor de NpcConfig.NODE_COLORS: rede nova aparece sozinha
	-- aqui e a janela não cresce por causa dela.
	sectionLabel("COLOCAR NÓ", nextOrder())
	local classRow = makeRow(nextOrder())
	local classLabel = PanelTheme.Text(classRow, "Cap_Classe", 9, Enum.Font.GothamBold, PanelTheme.Color.TextDim)
	classLabel.LayoutOrder = 1
	classLabel.Size = UDim2.fromOffset(140, metrics.BUTTON_H)
	classLabel:SetAttribute("Flex", true)
	local classButton = makeButton(classRow, "NODE CLASS", 2, nil, BUTTON_W)

	local classTypes = routeTypeOrder()
	local CLASS_PANEL_W = 230
	local CLASS_PANEL_H = #classTypes * PanelTheme.SLOT_ROW_STRIDE + 26
	local classPanel, classScroll = PanelTheme.SlotPanel(window, "CLASSE DO NÓ", CLASS_PANEL_W, CLASS_PANEL_H)
	classPanel.AnchorPoint = Vector2.new(1, 1)
	classPanel.Position = UDim2.new(1, -BODY_PAD, 1, -8) -- o Y real vem de placeClassPanel()

	-- Abre PARA BAIXO: o botão mora no topo do corpo. A lista de slots abre para cima, e as duas
	-- nunca ficam abertas juntas.
	local function placeClassPanel()
		local top = classButton.AbsolutePosition.Y - window.AbsolutePosition.Y
		local bottom = top + metrics.BUTTON_H + PanelTheme.SlotPanelGap() + CLASS_PANEL_H
		local floor = window.AbsoluteSize.Y - 8
		local ceiling = math.min(metrics.TITLE_H + 4 + CLASS_PANEL_H, floor)
		classPanel.Position = UDim2.new(1, -BODY_PAD, 0, math.clamp(bottom, ceiling, floor))
	end
	body:GetPropertyChangedSignal("CanvasPosition"):Connect(placeClassPanel)
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeClassPanel)

	for index, routeType in ipairs(classTypes) do
		local tint = NpcConfig.NODE_COLORS[routeType] or PanelTheme.Color.Accent
		local _row, pick, del = PanelTheme.SlotRow(classScroll, typeLabel(routeType), index)
		del.Visible = false
		pick.TextColor3 = tint -- a pintura de setMode só chega no primeiro modo escolhido
		modeButtons[routeType] = pick
		modeTints[routeType] = tint
		pick.Activated:Connect(function()
			setMode(if mode == routeType then "None" else routeType)
			classPanel.Visible = false
		end)
	end
	classScroll.CanvasSize = UDim2.fromOffset(0, #classTypes * PanelTheme.SLOT_ROW_STRIDE)

	-- Atribuída lá embaixo, quando slotPanel existir.
	local hideSlotPanel: () -> () = function() end

	classButton.MouseButton1Click:Connect(function()
		classPanel.Visible = not classPanel.Visible
		if classPanel.Visible then
			hideSlotPanel()
			placeClassPanel()
		end
	end)

	refreshClassControl = function()
		local active = RouteData.IsValidType(mode)
		local tint = modeTints[mode] or PanelTheme.Color.Accent
		classLabel.Text = if active then typeLabel(mode) else "nenhuma rede"
		classLabel.TextColor3 = if active then tint else PanelTheme.Color.TextDim
		classButton.BackgroundColor3 = if active then tint else PanelTheme.Color.Surface
		classButton.TextColor3 = if active then PanelTheme.Color.TextInk else PanelTheme.Color.Accent
	end
	refreshClassControl()

	local function stepperRow(order: number, caption: string, onLess: () -> (), onMore: () -> ()): TextLabel
		local row = makeRow(order)
		local label = PanelTheme.Text(row, "Cap_" .. caption, 9, Enum.Font.GothamBold, PanelTheme.Color.TextDim)
		label.LayoutOrder = 1
		label.Size = UDim2.fromOffset(104, metrics.BUTTON_H)
		label.Text = caption
		label:SetAttribute("Flex", true)
		makeButton(row, "−", 2, nil, 34).MouseButton1Click:Connect(onLess)
		local value = PanelTheme.Text(row, "Val_" .. caption, 10, Enum.Font.Code, PanelTheme.Color.Text)
		value.LayoutOrder = 3
		value.Size = UDim2.fromOffset(52, metrics.BUTTON_H)
		value.TextXAlignment = Enum.TextXAlignment.Center
		makeButton(row, "+", 4, nil, 34).MouseButton1Click:Connect(onMore)
		return value
	end

	local trailValue = stepperRow(nextOrder(), "SUB-PONTOS", function()
		nudgeSpacing(1)
	end, function()
		nudgeSpacing(-1)
	end)

	sectionLabel("EDITAR", nextOrder())
	local editRow = makeRow(nextOrder())
	local editModes: { { string } } = {
		{ "Delete", "APAGAR" },
		{ "Move", "MOVER" },
		{ "Link", "LIGAR" },
		{ "Subdivide", "DIVIDIR" },
		{ "Area", "ÁREA" },
	}
	for index, pair in ipairs(editModes) do
		local button = makeButton(editRow, pair[2], index)
		modeButtons[pair[1]] = button
		modeTints[pair[1]] = PanelTheme.Color.Accent
		button.MouseButton1Click:Connect(function()
			setMode(if mode == pair[1] then "None" else pair[1])
		end)
	end

	local chainValue = stepperRow(nextOrder(), "CORRENTE", function()
		nudgeChain(-1)
	end, function()
		nudgeChain(1)
	end)

	refreshBuilderLabels = function()
		trailValue.Text = string.format("%.1f studs", trailSpacing)
		chainValue.Text = if moveChain == 0 then "off" else string.format("%d pontos", moveChain)
	end
	refreshBuilderLabels()

	-- ESCUTA (senseRadius): raio próprio do nó, de qualquer rede. Escondida fora do modo ÁREA.
	local senseRow = makeRow(nextOrder())
	local senseLabel = PanelTheme.Text(senseRow, "Cap_Escuta", 9, Enum.Font.GothamBold, PanelTheme.Color.TextDim)
	senseLabel.LayoutOrder = 1
	senseLabel.Size = UDim2.fromOffset(104, metrics.BUTTON_H)
	senseLabel.Text = "Escuta (studs)"
	local senseBox = PanelTheme.TextBox(
		senseRow,
		"SenseRadius",
		string.format("padrão %d · %d–%d", NpcConfig.NODE_SENSE_RADIUS, RouteData.SENSE_MIN, RouteData.SENSE_MAX),
		140
	)
	senseBox.LayoutOrder = 2
	senseBox:SetAttribute("Flex", true)
	senseRow.Visible = false

	refreshSenseControl = function()
		local id = areaTargetId
		local part = if id then nodePart(id) else nil
		if mode ~= "Area" or not part then
			senseRow.Visible = false
			return
		end
		senseRow.Visible = true
		local current = part:GetAttribute("SenseRadius")
		senseBox.Text = if type(current) == "number" then tostring(current) else ""
	end

	-- Campo vazio manda `radius = nil` (voltar ao padrão). A FAIXA é recusada pelo servidor, e a razão
	-- sobe por RouteBuilderStats.reason.
	senseBox.FocusLost:Connect(function()
		local id = areaTargetId
		local event = opEvent
		if not id or not event then
			return
		end
		local part = nodePart(id)
		if not part then
			return
		end
		local trimmed = senseBox.Text:match("^%s*(.-)%s*$") or ""
		local radius: number? = nil
		if trimmed ~= "" then
			local parsed = tonumber(trimmed)
			if not parsed then
				setStatus("escuta: digite um número, ou deixe vazio para o padrão")
				refreshSenseControl()
				return
			end
			radius = parsed
		end
		(event :: RemoteEvent):FireServer({ op = "SetSense", id = id, radius = radius })
		setStatus(if radius
			then string.format("escuta pedida: %s studs", trimmed)
			else "escuta: voltando ao padrão")
		task.spawn(function()
			local folder = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
			if folder then
				folder:WaitForChild(id, 3)
			end
			if mode == "Area" and areaTargetId == id then
				refreshSenseControl()
			end
		end)
	end)

	local actionRow = makeRow(nextOrder())
	local undoButton = makeButton(actionRow, "DESFAZER", 1)
	undoButton.MouseButton1Click:Connect(function()
		if opEvent then
			(opEvent :: RemoteEvent):FireServer({ op = "Undo" })
			setStatus("desfeito")
		end
	end)
	local clearButton = makeButton(actionRow, "LIMPAR", 2)
	clearButton.MouseButton1Click:Connect(function()
		local payload: { [string]: any } = { op = "Clear" }
		if RouteData.IsValidType(mode) then
			payload.routeType = mode
		end
		if opEvent then
			(opEvent :: RemoteEvent):FireServer(payload)
			setStatus(if payload.routeType then "rota " .. tostring(payload.routeType) .. " limpa" else "grafo limpo")
		end
	end)

	sectionLabel("NPC", nextOrder())
	local npcRow = makeRow(nextOrder())
	local pauseButton = makeButton(npcRow, "SOLTAR", 1)
	local function setNpcPaused(paused: boolean)
		npcPaused = paused
		pauseButton.Text = if paused then "SOLTAR" else "PAUSAR"
		pauseButton.BackgroundColor3 = if paused
			then PanelTheme.Color.Surface
			else PanelTheme.Color.Bad -- solto = aceso, o estado "perigoso" da edição
		pauseButton.TextColor3 = if paused then PanelTheme.Color.Accent else PanelTheme.Color.TextInk
		if queryFn then
			(queryFn :: RemoteFunction):InvokeServer({ op = "SetNpcPaused", paused = paused })
		end
		setStatus(if paused then "NPCs pausados" else "NPCs SOLTOS — estão andando a rota")
	end
	pauseButton.MouseButton1Click:Connect(function()
		setNpcPaused(not npcPaused)
	end)

	sectionLabel("SLOTS", nextOrder())
	local persistRow = makeRow(nextOrder())
	local nameBox = PanelTheme.TextBox(persistRow, "SlotName", "nome da rota", BODY_W)
	nameBox.LayoutOrder = 1
	nameBox:SetAttribute("Flex", true)
	local saveButton = makeButton(persistRow, "SALVAR", 2, nil, BUTTON_W)
	local slotsButton = makeButton(persistRow, "SLOTS", 3, nil, BUTTON_W)

	local SLOT_PANEL_W, SLOT_PANEL_H = 230, 158
	local slotPanel, slotScroll = PanelTheme.SlotPanel(window, "ROTAS SALVAS", SLOT_PANEL_W, SLOT_PANEL_H)
	slotPanel.AnchorPoint = Vector2.new(1, 1)
	slotPanel.Position = UDim2.new(1, -BODY_PAD, 1, -8) -- o Y real vem de placeSlotPanel()

	local function placeSlotPanel()
		local top = slotsButton.AbsolutePosition.Y - window.AbsolutePosition.Y
		local bottom = top - PanelTheme.SlotPanelGap()
		local floor = window.AbsoluteSize.Y - 8
		local ceiling = math.min(metrics.TITLE_H + 4 + SLOT_PANEL_H, floor)
		slotPanel.Position = UDim2.new(1, -BODY_PAD, 0, math.clamp(bottom, ceiling, floor))
	end
	body:GetPropertyChangedSignal("CanvasPosition"):Connect(placeSlotPanel)
	window:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeSlotPanel)

	local slotConfirm, askSlotConfirm = PanelTheme.ConfirmBox(slotPanel)

	hideSlotPanel = function()
		slotPanel.Visible = false
		slotConfirm.Visible = false
	end

	local function adoptFrom(payload: { [string]: any }, described: string)
		setStatus("carregando…")
		slotPanel.Visible = false
		local loaded = (queryFn :: RemoteFunction):InvokeServer(payload)
		setStatus(if loaded and loaded.ok
			then string.format("%s carregada: %d nó(s)", described, loaded.nodes or 0)
			else "falha ao carregar: " .. tostring(loaded and loaded.reason))
	end

	local function refreshSlots()
		for _, child in ipairs(slotScroll:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		setStatus("lendo slots…")

		task.spawn(function()
			local ok, result = pcall(function()
				return (queryFn :: RemoteFunction):InvokeServer({ op = "ListSlots" })
			end)
			local names = (ok and result and result.ok and result.names) or {}
			local current = ok and result and result.current or nil
			if type(current) == "string" and #nameBox.Text == 0 then
				nameBox.Text = current
			end

			local _autoRow, autoPick, autoDel = PanelTheme.SlotRow(slotScroll, "↺ autosave (1 min)", 1)
			autoDel.Visible = false
			autoPick.Activated:Connect(function()
				adoptFrom({ op = "LoadAuto" }, "cópia automática")
			end)

			if #names == 0 then
				local empty = PanelTheme.Text(slotScroll, "Empty", 10, Enum.Font.Code, PanelTheme.Color.TextDim)
				empty.Size = UDim2.new(1, 0, 0, 18)
				empty.LayoutOrder = 2 -- num UIListLayout quem posiciona é a ordem, não Position
				empty.Text = if ok then "  (nenhuma rota salva)" else "  (DataStore indisponível)"
				slotScroll.CanvasSize = UDim2.fromOffset(0, PanelTheme.SLOT_ROW_STRIDE + 18)
				setStatus(if ok then "0 slot(s)" else "DataStore off")
				return
			end

			for index, name in ipairs(names) do
				-- +1 no índice: a linha 1 é o autosave.
				local _row, pick, del = PanelTheme.SlotRow(slotScroll, name, index + 1)
				if name == current then
					pick.Text = "  " .. name .. "   ← na mesa"
					pick.TextColor3 = PanelTheme.Color.Accent
				end
				pick.Activated:Connect(function()
					nameBox.Text = name
					adoptFrom({ op = "Load", name = name }, "'" .. name .. "'")
				end)
				del.Activated:Connect(function()
					askSlotConfirm(
						string.format("Apagar a rota '%s'?\n\nO traçado gravado nela some e NÃO volta.", name),
						function()
							task.spawn(function()
								pcall(function()
									(queryFn :: RemoteFunction):InvokeServer({ op = "DeleteSlot", name = name })
								end)
								refreshSlots()
							end)
						end
					)
				end)
			end
			slotScroll.CanvasSize = UDim2.fromOffset(0, (#names + 1) * PanelTheme.SLOT_ROW_STRIDE)
			setStatus(string.format("%d slot(s)", #names))
		end)
	end

	saveButton.MouseButton1Click:Connect(function()
		if not queryFn then
			return
		end
		setStatus("salvando…")
		local result = (queryFn :: RemoteFunction):InvokeServer({ op = "Save", name = nameBox.Text })
		setStatus(if result and result.ok
			then "salva como '" .. nameBox.Text .. "'"
			else "falha ao salvar: " .. tostring(result and result.reason))
		if result and result.ok and slotPanel.Visible then
			refreshSlots()
		end
	end)

	slotsButton.MouseButton1Click:Connect(function()
		slotPanel.Visible = not slotPanel.Visible
		if slotPanel.Visible then
			classPanel.Visible = false
			placeSlotPanel()
			refreshSlots()
		else
			slotConfirm.Visible = false
		end
	end)

	local function syncCurrentName()
		if not queryFn then
			return
		end
		task.spawn(function()
			local ok, result = pcall(function()
				return (queryFn :: RemoteFunction):InvokeServer({ op = "ListSlots" })
			end)
			local current = ok and result and result.ok and result.current or nil
			if type(current) == "string" and #nameBox.Text == 0 then
				nameBox.Text = current
			end
		end)
	end

	local stats = PanelTheme.Text(body, "Stats", 10, Enum.Font.Code, PanelTheme.Color.TextDim)
	stats.LayoutOrder = nextOrder()
	stats.Size = UDim2.new(1, 0, 0, 14)
	stats.TextTruncate = Enum.TextTruncate.AtEnd
	stats.Text = "nós —/— · maior linha — · peças —/—"
	statsLabel = stats

	local status = PanelTheme.Text(body, "Status", 10, Enum.Font.Gotham, PanelTheme.Color.TextDim)
	status.LayoutOrder = nextOrder()
	status.Size = UDim2.new(1, 0, 0, 14)
	status.TextTruncate = Enum.TextTruncate.AtEnd
	statusLabel = status

	-- Na BARRA e não na janela: apaga o diagnóstico do mundo inteiro e vale com a janela fechada.
	local persiana = PanelTheme.LauncherSlot(
		"DebugPersiana", "📲", 99, math.round(PanelTheme.Metrics.LAUNCHER_SIZE / 2))
	persianaButton = persiana
	PanelTheme.SetSlotPersistent(persiana)

	local function refreshPersiana()
		persiana.Text = if debugHidden then "📱" else "📲"
		persiana.TextColor3 = if debugHidden then PanelTheme.Color.TextDim else PanelTheme.Color.Accent
	end

	persiana.Activated:Connect(function()
		debugHidden = not debugHidden
		refreshDebugVisibility()
		refreshDockVisibility()
		refreshPersiana()
		setStatus(if debugHidden then "diagnóstico oculto (só nesta tela)" else "diagnóstico visível")
	end)
	refreshPersiana()

	-- Dono único do abrir/fechar: o botão da barra e o "—" do título passam os dois por aqui.
	local function setOpen(open: boolean)
		window.Visible = open
		PanelTheme.SetLauncherActive(toggle, open)
		if not open then
			setMode("None")
			classPanel.Visible = false
			hideSlotPanel()
		else
			syncCurrentName()
		end
		-- AVISO, não comando: quem suspende o NPC é o servidor, que solta a retenção se o cliente sumir.
		if opEvent then
			(opEvent :: RemoteEvent):FireServer({ op = "SetOpen", open = open })
		end
		if open then
			setNpcPaused(true)
		else
			npcPaused = true
			pauseButton.Text = "SOLTAR"
			pauseButton.BackgroundColor3 = PanelTheme.Color.Surface
			pauseButton.TextColor3 = PanelTheme.Color.Accent
			setStatus("")
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

-- ===================================================================================== CICLO

function RouteBuilderClient.Start()
	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
	if remotes == nil then
		return
	end
	local op = remotes:WaitForChild("RouteBuilderOp", REMOTE_WAIT)
	local query = remotes:WaitForChild("RouteBuilderQuery", REMOTE_WAIT)
	local statsRemote = remotes:WaitForChild("RouteBuilderStats", REMOTE_WAIT)
	local visualsRemote = remotes:WaitForChild("RouteBuilderVisuals", REMOTE_WAIT)
	-- Sem o servidor do builder no ar, a ferramenta simplesmente não existe nesta sessão.
	if not (op and query and statsRemote and visualsRemote) then
		return
	end
	opEvent = op :: RemoteEvent
	queryFn = query :: RemoteFunction

	local authorized, result = pcall(function()
		return (queryFn :: RemoteFunction):InvokeServer({ op = "IsAuthorized" })
	end)
	if not (authorized and result and result.ok and result.authorized) then
		return
	end

	-- CONECTAR ANTES DE PEDIR: entre o snapshot e o primeiro push não pode haver janela.
	;(visualsRemote :: RemoteEvent).OnClientEvent:Connect(function(payload)
		RouteNodeRenderer.Apply(payload)
	end)
	local gotVisuals, visuals = pcall(function()
		return (queryFn :: RemoteFunction):InvokeServer({ op = "GetVisuals" })
	end)
	if gotVisuals and visuals and visuals.ok then
		RouteNodeRenderer.Apply(visuals)
	end

	buildGui()

	-- `default = false` porque abrir o builder SUSPENDE os NPCs. Em task.spawn: DockMemory.Load yielda.
	task.spawn(function()
		DockMemory.Restore(DOCK_KEY, false, function(open: boolean)
			local apply = applyOpen
			if apply ~= nil and open then
				apply(true) -- só ABRE: fechada já é o estado em que buildGui a deixou
			end
		end)
	end)

	;(statsRemote :: RemoteEvent).OnClientEvent:Connect(applyStats)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or mode == "None" or gui == nil then
			return -- clique na própria GUI (ou sem modo): não é gesto de mundo
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			handleClick(input)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement
			and input.UserInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		if #subdividePaint > 0 then
			local aId, bId = pickCable(input)
			if aId and bId then
				local key = edgeKey(aId :: string, bId :: string)
				if key ~= subdivideLastKey then
					subdivideLastKey = key
					paintEdge(aId :: string, bId :: string)
					rebuildSubdividePreview()
				end
			end
			return
		end

		if trailAnchor == nil or not isPlacementMode() then
			return
		end
		local hit = raycastGround(input)
		if hit then
			rebuildTrail(hit.Position)
		end
	end)

	-- RODA: o número do modo ATIVO. ContextActionService pelo SINK — sem afundar, o zoom vem junto.
	ContextActionService:BindAction("RouteBuilderWheel", function(_, inputState: Enum.UserInputState, input: InputObject)
		if inputState ~= Enum.UserInputState.Change or gui == nil then
			return Enum.ContextActionResult.Pass
		end
		local direction = if input.Position.Z > 0 then 1 else -1
		if mode == "Move" then
			nudgeChain(direction)
		elseif isPlacementMode() or mode == "Subdivide" then
			nudgeSpacing(-direction)
			rebuildSubdividePreview()
		else
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseWheel)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			finishTrail()
			finishSubdivide()
		end
	end)
end

return RouteBuilderClient
