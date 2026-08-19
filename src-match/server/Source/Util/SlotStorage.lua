--!strict
-- Persistência genérica por slots num DataStore: UpdateAsync com retry + backoff, espera de
-- orçamento e pcall em toda borda. UpdateAsync e nunca SetAsync: o transform vê o valor atual e
-- pode desistir devolvendo nil. Sem acesso à API (Studio), degrada para (false, "offline").
local DataStoreService = game:GetService("DataStoreService")

local SlotStorage = {}
SlotStorage.__index = SlotStorage

-- Tentativas por operação; base em s do backoff exponencial; teto em s da espera por orçamento
-- (o budget de UpdateAsync é do servidor inteiro — esperar pra sempre seguraria o caller).
local MAX_ATTEMPTS = 3
local BACKOFF_BASE = 1
local BUDGET_WAIT_TIMEOUT = 10

type StoreImpl = {
	_store: DataStore?,
	_name: string,
	Save: (self: StoreImpl, slotKey: string, transform: (any) -> any) -> (boolean, string?),
	Load: (self: StoreImpl, slotKey: string) -> (boolean, any),
}
export type Store = StoreImpl

function SlotStorage.new(storeName: string): Store
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(storeName)
	end)
	local self = setmetatable({
		_store = if ok then store else nil,
		_name = storeName,
	}, SlotStorage) :: any
	if not ok then
		warn(string.format(
			"[SlotStorage] '%s' sem acesso a DataStore (Studio sem API access?). Save/Load respondem offline.",
			storeName
		))
	end
	return self :: Store
end

local function waitForBudget(requestType: Enum.DataStoreRequestType): boolean
	local waited = 0
	while DataStoreService:GetRequestBudgetForRequestType(requestType) <= 0 do
		if waited >= BUDGET_WAIT_TIMEOUT then
			return false
		end
		task.wait(0.5)
		waited += 0.5
	end
	return true
end

local function withRetry(operation: () -> any): (boolean, any)
	local lastError: any = nil
	for attempt = 1, MAX_ATTEMPTS do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < MAX_ATTEMPTS then
			task.wait(BACKOFF_BASE * 2 ^ (attempt - 1))
		end
	end
	return false, lastError
end

-- `transform(atual) -> novo` roda dentro do UpdateAsync; devolver nil cancela a gravação.
function SlotStorage.Save(self: StoreImpl, slotKey: string, transform: (any) -> any): (boolean, string?)
	local store = self._store
	if not store then
		return false, "offline"
	end
	if not waitForBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "sem orçamento de UpdateAsync (teto de espera atingido)"
	end
	local ok, err = withRetry(function()
		return (store :: DataStore):UpdateAsync(slotKey, transform)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true, nil
end

-- Devolve (true, valor|nil) ou (false, erro).
function SlotStorage.Load(self: StoreImpl, slotKey: string): (boolean, any)
	local store = self._store
	if not store then
		return false, "offline"
	end
	if not waitForBudget(Enum.DataStoreRequestType.GetAsync) then
		return false, "sem orçamento de GetAsync (teto de espera atingido)"
	end
	return withRetry(function()
		return (store :: DataStore):GetAsync(slotKey)
	end)
end

return SlotStorage
