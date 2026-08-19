--!strict
-- RouteStorage (servidor / Npc) — slots nomeados de rota autorada, sobre Util/SlotStorage.
-- O índice (ROUTE_RECORD_KEY) guarda só os nomes; o grafo de cada slot vive na chave própria
-- `slot_<nome>`, e o autosave (ROUTE_AUTOSAVE_KEY) fica fora do índice. Nome começando com
-- "__" é reservado: sai da listagem e não pode ser gravado.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))
local RouteData = require(Shared:WaitForChild("Npc"):WaitForChild("RouteData"))
local SlotStorage = require(ServerScriptService:WaitForChild("Source"):WaitForChild("Util"):WaitForChild("SlotStorage"))

local RouteStorage = {}

-- Preguiçoso: dar require neste módulo não pode tocar DataStoreService.
local store: SlotStorage.Store? = nil
local function getStore(): SlotStorage.Store
	if not store then
		store = SlotStorage.new(NpcConfig.ROUTE_DATASTORE_NAME)
	end
	return store :: SlotStorage.Store
end

-- ===================================================================================== NOMES

function RouteStorage.IsReserved(name: string): boolean
	return string.sub(name, 1, 2) == "__"
end

-- Devolve (nomeLimpo, motivo).
function RouteStorage.NormalizeName(name: any): (string?, string?)
	if type(name) ~= "string" then
		return nil, "nome ausente"
	end
	local clean = (name:gsub("^%s+", ""):gsub("%s+$", ""))
	if #clean == 0 then
		return nil, "nome vazio"
	end
	if #clean > NpcConfig.ROUTE_SLOT_NAME_MAX then
		return nil, string.format("nome acima de %d caracteres", NpcConfig.ROUTE_SLOT_NAME_MAX)
	end
	if RouteStorage.IsReserved(clean) then
		return nil, "nome reservado (começa com __)"
	end
	return clean, nil
end

function RouteStorage.SlotKey(clean: string): string
	return "slot_" .. clean
end

-- Formato antigo guardava o registro inteiro (com `nodes`) no índice; o novo, só um marcador.
local function isInlineRecord(value: any): boolean
	return type(value) == "table" and type(value.nodes) == "table"
end

-- ==================================================================================== LEITURA

local function loadAll(): (boolean, any)
	local ok, record = getStore():Load(NpcConfig.ROUTE_RECORD_KEY)
	if not ok then
		return false, record
	end
	return true, if type(record) == "table" then record else {}
end

-- (ok, nomes ordenados | erro).
function RouteStorage.List(): (boolean, { string } | string)
	local ok, all = loadAll()
	if not ok then
		return false, tostring(all)
	end
	local names: { string } = {}
	for name in pairs(all) do
		if type(name) == "string" and not RouteStorage.IsReserved(name) then
			table.insert(names, name)
		end
	end
	table.sort(names)
	return true, names
end

-- ======================================================================== O SLOT EM TRABALHO

-- Nome reservado no índice que registra qual slot originou o grafo em edição.
local CURRENT_KEY = "__current"

-- (ok, nome?); ok=false é falha de infra, nome nil é "nunca carregou nem salvou".
function RouteStorage.GetCurrent(): (boolean, string?)
	local ok, all = loadAll()
	if not ok then
		return false, nil
	end
	local value = all[CURRENT_KEY]
	return true, if type(value) == "string" then value else nil
end

-- `nil` esquece.
function RouteStorage.SetCurrent(name: string?): boolean
	local ok = getStore():Save(NpcConfig.ROUTE_RECORD_KEY, function(current)
		local all = if type(current) == "table" then current else {}
		all[CURRENT_KEY] = name
		return all
	end)
	return ok
end

-- (ok, graph|motivo, descartados).
function RouteStorage.Load(name: any): (boolean, RouteData.Graph | string, number)
	local clean, reason = RouteStorage.NormalizeName(name)
	if not clean then
		return false, reason :: string, 0
	end
	local ok, all = loadAll()
	if not ok then
		return false, tostring(all), 0
	end
	local entry = all[clean]
	if entry == nil then
		return false, "slot '" .. clean .. "' não existe", 0
	end

	local record: any = entry
	if not isInlineRecord(entry) then
		local okSlot, payload = getStore():Load(RouteStorage.SlotKey(clean))
		if not okSlot then
			return false, tostring(payload), 0
		end
		if type(payload) ~= "table" then
			return false, string.format("slot '%s' está no índice mas a chave dele está vazia", clean), 0
		end
		record = payload
	end

	local graph, dropped = RouteData.Deserialize(record, NpcConfig.MAP_BOUNDS)
	if dropped > 0 then
		warn(string.format(
			"[RouteStorage] slot '%s': %d nó(s) descartado(s) na leitura (malformados ou fora dos bounds).",
			clean, dropped))
	end
	return true, graph, dropped
end

-- ===================================================================================== TETOS

-- Única dona de "este grafo cabe?" — edição e Save consultam a mesma resposta. Motivo ou nil.
function RouteStorage.CapViolation(graph: RouteData.Graph): string?
	local stats = RouteData.Stats(graph)
	if stats.total > NpcConfig.MAX_NODES_PER_SLOT then
		return string.format(
			"%d nós no grafo, teto é %d por slot", stats.total, NpcConfig.MAX_NODES_PER_SLOT)
	end
	if stats.components > NpcConfig.MAX_ROUTES_PER_SLOT then
		return string.format(
			"%d peças no grafo, teto é %d por slot", stats.components, NpcConfig.MAX_ROUTES_PER_SLOT)
	end
	if stats.largest > NpcConfig.MAX_NODES_PER_ROUTE then
		return string.format(
			"uma linha com %d nós, teto é %d", stats.largest, NpcConfig.MAX_NODES_PER_ROUTE)
	end
	return nil
end

-- =================================================================================== ESCRITA

-- Ordem do Save: grafo antes do índice — falha parcial deixa chave órfã, nunca slot listado
-- que não abre. O slot antigo em formato inline migra aqui: o blob sai do índice.
function RouteStorage.Save(name: any, graph: RouteData.Graph): (boolean, string?)
	local clean, reason = RouteStorage.NormalizeName(name)
	if not clean then
		return false, reason
	end

	local violation = RouteStorage.CapViolation(graph)
	if violation then
		return false, violation
	end

	local record = RouteData.Serialize(graph)

	local okSlot, errSlot = getStore():Save(RouteStorage.SlotKey(clean), function()
		return record
	end)
	if not okSlot then
		return false, errSlot
	end

	local rejected: string? = nil
	local ok, err = getStore():Save(NpcConfig.ROUTE_RECORD_KEY, function(current)
		local all = if type(current) == "table" then current else {}
		-- Teto de slots conferido DENTRO do UpdateAsync, contra o valor atual.
		if all[clean] == nil then
			local count = 0
			for existing in pairs(all) do
				if not RouteStorage.IsReserved(existing) then
					count += 1
				end
			end
			if count >= NpcConfig.MAX_ROUTE_SLOTS then
				rejected = string.format(
					"teto de %d slots atingido — apague um antes de criar outro", NpcConfig.MAX_ROUTE_SLOTS)
				return nil -- devolver nil CANCELA a gravação (contrato do UpdateAsync)
			end
		end
		all[clean] = true
		return all
	end)
	if rejected then
		return false, rejected
	end
	return ok, err
end

-- Ordem inversa do Save: índice primeiro — o slot some da lista mesmo se a limpeza falhar.
function RouteStorage.Delete(name: any): (boolean, string?)
	local clean, reason = RouteStorage.NormalizeName(name)
	if not clean then
		return false, reason
	end
	local ok, err = getStore():Save(NpcConfig.ROUTE_RECORD_KEY, function(current)
		local all = if type(current) == "table" then current else {}
		all[clean] = nil
		return all
	end)
	if not ok then
		return false, err
	end
	-- Tabela vazia, não nil: nil cancelaria a gravação (contrato do UpdateAsync).
	getStore():Save(RouteStorage.SlotKey(clean), function()
		return {}
	end)
	return true, nil
end

-- ================================================================================== AUTOSAVE
-- Fora do índice: não aparece na lista, não gasta vaga de MAX_ROUTE_SLOTS e nenhum Save comum
-- o alcança (NormalizeName recusa "__"). Sem conferir teto: é a rede de segurança.

function RouteStorage.SaveAuto(graph: RouteData.Graph): (boolean, string?)
	-- Serializa antes de qualquer yield: o registro é o grafo como está no momento da chamada.
	local record = RouteData.Serialize(graph)
	return getStore():Save(NpcConfig.ROUTE_AUTOSAVE_KEY, function()
		return record
	end)
end

-- (ok, graph|motivo, descartados); autosave inexistente é o caso normal, sem warn.
function RouteStorage.LoadAuto(): (boolean, RouteData.Graph | string, number)
	local ok, payload = getStore():Load(NpcConfig.ROUTE_AUTOSAVE_KEY)
	if not ok then
		return false, tostring(payload), 0
	end
	if type(payload) ~= "table" then
		return false, "não há autosave gravado nesta experiência", 0
	end
	local graph, dropped = RouteData.Deserialize(payload, NpcConfig.MAP_BOUNDS)
	return true, graph, dropped
end

return RouteStorage
