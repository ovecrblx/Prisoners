--!strict
-- RouteNodeRenderer (cliente / Lib): desenha localmente os marcadores de nó do Route Builder a
-- partir do payload do servidor, com a pasta, os nomes e os atributos que a seleção do
-- RouteBuilderClient lê. Classe de superfície/aérea e marca de órfão vêm prontas no payload.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
local RouteData = require(Shared:WaitForChild("Npc"):WaitForChild("RouteData"))

local RouteNodeRenderer = {}

-- Uma entrada por nó, como RouteBuilderServer.Pure.VisualPayload monta.
export type Entry = {
	id: string,
	position: Vector3,
	routeType: string,
	links: { string },
	senseRadius: number?,
	order: number,
	aerial: boolean,
	orphan: boolean,
}

-- Geração da última foto desenhada; payload de geração menor que a desenhada é descartado.
local lastVersion = -1

local ORPHAN_TINT = Color3.fromRGB(255, 40, 40)

local function getFolder(): Folder
	local existing = Workspace:FindFirstChild(NpcConfig.NODE_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = NpcConfig.NODE_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

-- O dado é o ponto de CHÃO; o lift vale só para o desenho.
local function visualPosition(position: Vector3): Vector3
	return position + Vector3.new(0, NpcConfig.NODE_VISUAL_LIFT, 0)
end

-- CanQuery/CanTouch=false em toda peça: o cliente também raycasteia (colocação pela mira).
local function decorate(part: BasePart, color: Color3, transparency: number)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
end

local function buildNodePart(folder: Folder, entry: Entry)
	local passthrough = #entry.links == 2
	local size = NpcConfig.NODE_SIZE * (if passthrough then NpcConfig.NODE_SUB_SCALE else 1)

	local part = Instance.new("Part")
	part.Name = entry.id
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(size, size, size)
	part.Position = visualPosition(entry.position)
	decorate(part, NpcConfig.NODE_COLORS[entry.routeType] or Color3.fromRGB(255, 255, 255), 0.25)
	-- Contrato da seleção: só peça com RouteNode é selecionável; SenseRadius nil limpa o atributo.
	part:SetAttribute("RouteNode", true)
	part:SetAttribute("RouteType", entry.routeType)
	part:SetAttribute("RouteLinks", table.concat(entry.links, ","))
	part:SetAttribute("SenseRadius", entry.senseRadius)

	local stem = Instance.new("Part")
	stem.Name = "Stem"
	stem.Shape = Enum.PartType.Cylinder
	stem.Size = Vector3.new(NpcConfig.NODE_VISUAL_LIFT, 0.15, 0.15)
	stem.CFrame = RouteData.StemGeometry(entry.position, NpcConfig.NODE_VISUAL_LIFT)
	decorate(stem, if entry.orphan then ORPHAN_TINT else part.Color, if entry.orphan then 0 else 0.6)
	stem.Parent = part

	if entry.orphan then
		local outline = Instance.new("SelectionBox")
		outline.Name = "Orphan"
		outline.Adornee = part
		outline.Color3 = ORPHAN_TINT
		outline.LineThickness = 0.05
		outline.Parent = part
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Order"
	billboard.Size = UDim2.fromOffset(48, 24)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.2
	label.Text = (if entry.aerial then "A" else "S") .. tostring(entry.order)
	label.TextColor3 = if entry.aerial then Color3.fromRGB(120, 245, 255) else Color3.new(1, 1, 1)
	label.Parent = billboard
	billboard.Parent = part

	-- Esfera de escuta em escala real (diâmetro = 2×raio), só com raio explícito no nó.
	if entry.senseRadius ~= nil then
		local diameter = 2 * (entry.senseRadius :: number)
		local sense = Instance.new("Part")
		sense.Name = "Sense"
		sense.Shape = Enum.PartType.Ball
		sense.Size = Vector3.new(diameter, diameter, diameter)
		sense.Position = part.Position
		decorate(sense, NpcConfig.SENSE_AREA_COLOR, NpcConfig.SENSE_AREA_TRANSPARENCY)
		sense.Material = Enum.Material.ForceField
		sense.CastShadow = false
		sense.Parent = part
	end

	part.Parent = folder
end

local function buildLinkPart(folder: Folder, name: string, from: Entry, to: Entry)
	local a = visualPosition(from.position)
	local b = visualPosition(to.position)
	local cf, size = RouteData.CableGeometry(a, b, NpcConfig.LINK_THICKNESS)
	if not cf then
		return
	end

	local cable = Instance.new("Part")
	cable.Name = name
	cable.Shape = Enum.PartType.Cylinder
	cable.Size = size :: Vector3
	cable.CFrame = cf :: CFrame
	cable:SetAttribute("LinkA", from.id)
	cable:SetAttribute("LinkB", to.id)
	local tint = if from.routeType == to.routeType
		then NpcConfig.NODE_COLORS[from.routeType] or Color3.fromRGB(255, 255, 255)
		else Color3.fromRGB(255, 255, 255)
	decorate(cable, tint, 0.35)
	cable.Parent = folder
end

function RouteNodeRenderer.Apply(payload: any)
	if type(payload) ~= "table" or type(payload.nodes) ~= "table" then
		return
	end
	local version = if type(payload.version) == "number" then payload.version else 0
	if version < lastVersion then
		return
	end
	lastVersion = version

	local folder = getFolder()
	folder:ClearAllChildren()

	local entries = payload.nodes :: { Entry }
	local byId: { [string]: Entry } = {}
	for _, entry in ipairs(entries) do
		byId[entry.id] = entry
	end

	for _, entry in ipairs(entries) do
		buildNodePart(folder, entry)
	end

	local drawn: { [string]: boolean } = {}
	local index = 0
	for _, entry in ipairs(entries) do
		for _, linkId in ipairs(entry.links) do
			local other = byId[linkId]
			if other and other.id ~= entry.id then
				local key = if entry.id < other.id
					then entry.id .. "|" .. other.id
					else other.id .. "|" .. entry.id
				if not drawn[key] then
					drawn[key] = true
					index += 1
					buildLinkPart(folder, "Link_" .. index, entry, other)
				end
			end
		end
	end
end

return RouteNodeRenderer
