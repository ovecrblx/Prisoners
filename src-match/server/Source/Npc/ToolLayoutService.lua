--!strict
-- Estado das janelas das ferramentas de autoria, por jogador: quais abas ficaram abertas, o tamanho
-- e a posição de cada janela, os perfis de arranjo de cards e o que reabrir de cada um.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))
local Remotes = require(ServerScriptService:WaitForChild("Source"):WaitForChild("Util"):WaitForChild("Remotes"))
local SlotStorage = require(ServerScriptService:WaitForChild("Source"):WaitForChild("Util"):WaitForChild("SlotStorage"))

local ToolLayoutService = {}

-- Sem sufixo de Studio de propósito: o estado das ferramentas atravessa Play -> Edit -> servidor
-- publicado. É preferência de ferramenta, não dado de jogo.
local STORE_NAME = "NpcDockState_v1"

-- Chaves de janela aceitas. O cliente manda a barra inteira e o que não estiver aqui é podado,
-- senão uma ferramenta removida deixaria lixo no registro para sempre.
local DOCK_KEYS: { [string]: boolean } = {
	routes = true,
	brain = true,
}

-- Ferramentas que guardam geometria de janela e perfis de arranjo.
local TOOL_KEYS: { [string]: boolean } = {
	brain = true,
}

-- Tetos do registro: perfis por ferramenta, cards por perfil, tamanho do nome e do id de NPC.
local MAX_PROFILES = 8
local MAX_CARDS = 240
local NAME_MAX = 24
local ID_MAX = 64

-- px; faixa de sanidade da geometria vinda do cliente.
local GEOM_MIN, GEOM_MAX = -8000, 8000

-- s entre gravações do mesmo jogador; o cliente já faz debounce, isto é o teto do servidor.
local WRITE_GAP = 5

type Point = { x: number, y: number }

-- Caixa da janela: x/y/w/h sempre; escala e pan só quando a ferramenta os guarda.
type Geom = { [string]: number? }

-- Um desenho salvo: onde ficou cada card, e com que escala o autor o arrumou.
type Profile = { cards: { [string]: Point }, zoom: number? }

-- Marcas por ferramenta: `first` é o arranjo padrão (o primeiro que o autor criou), `last` o
-- reaberto, e `npc` o sujeito da última sessão.
type Mark = { first: string?, last: string?, npc: string? }

type Record = {
	dock: { [string]: boolean },
	geom: { [string]: Geom },
	layouts: { [string]: { [string]: Profile } },
	marks: { [string]: Mark },
}

local store: SlotStorage.Store? = nil
local cache: { [number]: Record } = {}
local lastWrite: { [number]: number } = {}

local function getStore(): SlotStorage.Store
	if not store then
		store = SlotStorage.new(STORE_NAME)
	end
	return store :: SlotStorage.Store
end

local function keyFor(player: Player): string
	return "u_" .. tostring(player.UserId)
end

-- Mesma lista do Route Builder: quem edita rota é quem tem ferramenta.
local function isAuthorized(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return NpcConfig.BUILDER_ALLOWLIST[player.UserId] == true
end

local function number(value: any): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(value, GEOM_MIN, GEOM_MAX)
end

local function text(value: any, limit: number): string?
	if type(value) ~= "string" or #value == 0 or #value > limit then
		return nil
	end
	return value
end

local function pruneDock(raw: any): { [string]: boolean }
	local dock: { [string]: boolean } = {}
	if type(raw) ~= "table" then
		return dock
	end
	for key, open in pairs(raw) do
		if DOCK_KEYS[key] and open == true then
			dock[key] = true
		end
	end
	return dock
end

local function pruneGeom(raw: any): { [string]: Geom }
	local geom: { [string]: Geom } = {}
	if type(raw) ~= "table" then
		return geom
	end
	for tool, box in pairs(raw) do
		if TOOL_KEYS[tool] and type(box) == "table" then
			local x, y = number(box.x), number(box.y)
			local w, h = number(box.w), number(box.h)
			if x and y and w and h then
				-- Escala e pan viajam com a JANELA, não com o desenho: carregar um arranjo salvo em
				-- outro monitor não pode reescalar a ferramenta de quem só queria os cards de volta.
				local kept: Geom = { x = x, y = y, w = w, h = h }
				kept.zoom = number(box.zoom)
				kept.px = number(box.px)
				kept.py = number(box.py)
				geom[tool] = kept
			end
		end
	end
	return geom
end

local function pruneCards(raw: any): { [string]: Point }?
	if type(raw) ~= "table" then
		return nil
	end
	local cards: { [string]: Point } = {}
	local count = 0
	for key, point in pairs(raw) do
		if count >= MAX_CARDS then
			break
		end
		if type(key) == "string" and #key <= 64 and type(point) == "table" then
			local x, y = number(point.x), number(point.y)
			if x and y then
				cards[key] = { x = x, y = y }
				count += 1
			end
		end
	end
	return if count > 0 then cards else nil
end

local function pruneLayouts(raw: any): { [string]: { [string]: Profile } }
	local layouts: { [string]: { [string]: Profile } } = {}
	if type(raw) ~= "table" then
		return layouts
	end
	for tool, profiles in pairs(raw) do
		if TOOL_KEYS[tool] and type(profiles) == "table" then
			local kept: { [string]: Profile } = {}
			local count = 0
			for name, entry in pairs(profiles) do
				if count < MAX_PROFILES and type(name) == "string" and #name > 0 and #name <= NAME_MAX then
					-- Registro anterior à escala guardava o mapa de cards direto; ler as duas formas
					-- é o que impede um desenho salvo antes de sumir na primeira carga.
					local boxed = type(entry) == "table" and entry.cards ~= nil
					local pruned = pruneCards(if boxed then entry.cards else entry)
					if pruned then
						kept[name] = { cards = pruned, zoom = if boxed then number(entry.zoom) else nil }
						count += 1
					end
				end
			end
			layouts[tool] = kept
		end
	end
	return layouts
end

local function pruneMarks(raw: any): { [string]: Mark }
	local marks: { [string]: Mark } = {}
	if type(raw) ~= "table" then
		return marks
	end
	for tool, mark in pairs(raw) do
		if TOOL_KEYS[tool] and type(mark) == "table" then
			marks[tool] = {
				first = text(mark.first, NAME_MAX),
				last = text(mark.last, NAME_MAX),
				npc = text(mark.npc, ID_MAX),
			}
		end
	end
	return marks
end

local function markOf(record: Record, tool: string): Mark
	local mark = record.marks[tool]
	if not mark then
		mark = {}
		record.marks[tool] = mark
	end
	return mark
end

local function load(player: Player): Record
	local cached = cache[player.UserId]
	if cached then
		return cached
	end

	local ok, raw = getStore():Load(keyFor(player))
	local source = if ok and type(raw) == "table" then raw else {}
	local record: Record = {
		dock = pruneDock(source.dock),
		geom = pruneGeom(source.geom),
		layouts = pruneLayouts(source.layouts),
		marks = pruneMarks(source.marks),
	}
	cache[player.UserId] = record
	return record
end

local function flush(player: Player, record: Record)
	task.spawn(function()
		getStore():Save(keyFor(player), function()
			return record
		end)
	end)
end

local function save(player: Player, record: Record)
	local userId = player.UserId
	cache[userId] = record

	local now = os.clock()
	if now - (lastWrite[userId] or -math.huge) < WRITE_GAP then
		return
	end
	lastWrite[userId] = now
	flush(player, record)
end

local function onInvoke(player: Player, action: any, name: any, payload: any): any
	if not isAuthorized(player) then
		return nil
	end
	local record = load(player)

	if action == "dock_get" then
		return { dock = record.dock }
	elseif action == "dock_set" then
		record.dock = pruneDock(payload)
		save(player, record)
		return { ok = true }
	elseif action == "geom_get" then
		return { geom = if TOOL_KEYS[name] then record.geom[name] else nil }
	elseif action == "geom_set" then
		-- Mescla, nunca substitui o mapa: gravar uma ferramenta não pode apagar a geometria de outra.
		local one = if TOOL_KEYS[name] then pruneGeom({ [name] = payload }) else {}
		if one[name] then
			record.geom[name] = one[name]
			save(player, record)
		end
		return { ok = true }
	elseif action == "layout_list" then
		local names: { string } = {}
		for profile in pairs(record.layouts[name] or {}) do
			table.insert(names, profile)
		end
		table.sort(names)
		return { ok = true, names = names }
	elseif action == "mark_get" then
		return { ok = true, mark = if TOOL_KEYS[name] then record.marks[name] or {} else {} }
	elseif action == "npc_set" then
		if TOOL_KEYS[name] then
			markOf(record, name).npc = text(payload, ID_MAX)
			save(player, record)
		end
		return { ok = true }
	elseif action == "layout_load" then
		local profiles = record.layouts[name]
		local profile = tostring(payload)
		local entry = profiles and profiles[profile]
		-- Carregar é MARCAR: é o que faz a janela reabrir no arranjo que o autor escolheu por último.
		if entry and TOOL_KEYS[name] then
			markOf(record, name).last = text(profile, NAME_MAX)
			save(player, record)
		end
		return { ok = entry ~= nil, cards = entry and entry.cards, zoom = entry and entry.zoom }
	elseif action == "layout_save" then
		if not TOOL_KEYS[name] or type(payload) ~= "table" then
			return { ok = false }
		end
		local profile = tostring(payload.name or "")
		local cards = pruneCards(payload.cards)
		if #profile == 0 or #profile > NAME_MAX or cards == nil then
			return { ok = false, reason = "nome ou arranjo inválido" }
		end
		local profiles = record.layouts[name] or {}
		if profiles[profile] == nil then
			local count = 0
			for _ in pairs(profiles) do
				count += 1
			end
			if count >= MAX_PROFILES then
				return { ok = false, reason = "teto de perfis" }
			end
		end
		profiles[profile] = { cards = cards, zoom = number(payload.zoom) }
		record.layouts[name] = profiles

		-- O primeiro criado vira o padrão e fica; salvar de novo só troca o reaberto.
		local mark = markOf(record, name)
		if mark.first == nil then
			mark.first = profile
		end
		mark.last = profile

		save(player, record)
		return { ok = true }
	elseif action == "layout_delete" then
		local profiles = record.layouts[name]
		if profiles then
			local profile = tostring(payload)
			profiles[profile] = nil
			-- Marca apontando para perfil apagado é pior que marca vazia: o próximo criado assume.
			local mark = record.marks[name]
			if mark then
				mark.first = if mark.first == profile then nil else mark.first
				mark.last = if mark.last == profile then nil else mark.last
			end
			save(player, record)
		end
		return { ok = true }
	end

	return nil
end

function ToolLayoutService.Start()
	Remotes.Function("ToolLayout").OnServerInvoke = onInvoke

	Players.PlayerRemoving:Connect(function(player)
		local record = cache[player.UserId]
		cache[player.UserId] = nil
		lastWrite[player.UserId] = nil

		-- Última escrita sem o teto de intervalo: o jogador já não volta a mandar nada.
		if record then
			flush(player, record)
		end
	end)
end

return ToolLayoutService
