--!strict
-- DockMemory (cliente / Lib) — lembra quais janelas da barra ficaram abertas, pelo remote
-- ToolLayout. Sem o remote, degrada para memória volátil da sessão. Biblioteca: sem Init/Start.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DockMemory = {}

-- s entre a última mudança e a escrita agendada; s de espera pelo remote antes de desistir dele.
local WRITE_DEBOUNCE = 1.5
local REMOTE_WAIT = 5

local state: { [string]: boolean } = {}
local touched: { [string]: boolean } = {}
local loaded = false
local loading = false
local pending = false

local remoteFn: RemoteFunction? = nil
local remoteResolved = false

local function remote(): RemoteFunction?
	if remoteResolved then
		return remoteFn
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT)
	local fn = remotes and remotes:WaitForChild("ToolLayout", REMOTE_WAIT)
	remoteResolved = true
	remoteFn = if fn and fn:IsA("RemoteFunction") then fn :: RemoteFunction else nil
	return remoteFn
end

-- Yielda; reentrante. O gesto desta sessão (`touched`) ganha do registro que chegar depois.
function DockMemory.Load(): { [string]: boolean }
	if loaded then
		return state
	end
	if loading then
		while loading do
			task.wait()
		end
		return state
	end

	loading = true
	local fn = remote()
	if fn ~= nil then
		local ok, result = pcall(function()
			return (fn :: RemoteFunction):InvokeServer("dock_get")
		end)
		if ok and type(result) == "table" and type(result.dock) == "table" then
			for key, open in pairs(result.dock) do
				if type(key) == "string" and not touched[key] then
					state[key] = open == true
				end
			end
		end
	end
	loaded = true
	loading = false
	return state
end

-- nil = nunca gravado; o default de estreia de cada janela é de cada controller, não daqui.
function DockMemory.Get(key: string): boolean?
	return state[key]
end

function DockMemory.IsOpen(key: string): boolean
	return state[key] == true
end

-- Devolve na hora; escreve a barra inteira, não um delta — o servidor poda o que não conhece.
function DockMemory.SetOpen(key: string, open: boolean)
	if state[key] == open then
		touched[key] = true
		return
	end
	state[key] = open
	touched[key] = true
	if pending then
		return
	end
	pending = true
	task.delay(WRITE_DEBOUNCE, function()
		pending = false
		local fn = remote()
		if fn == nil then
			return
		end
		pcall(function()
			(fn :: RemoteFunction):InvokeServer("dock_set", nil, state)
		end)
	end)
end

-- Yielda via Load; `default` vale só na estreia. O task.spawn é do chamador.
function DockMemory.Restore(key: string, default: boolean, apply: (boolean) -> ())
	DockMemory.Load()
	local saved = DockMemory.Get(key)
	apply(if saved == nil then default else saved :: boolean)
end

function DockMemory.Flush()
	if not pending then
		return
	end
	pending = false
	local fn = remote()
	if fn == nil then
		return
	end
	pcall(function()
		(fn :: RemoteFunction):InvokeServer("dock_set", nil, state)
	end)
end

Players.LocalPlayer.CharacterRemoving:Connect(function()
	task.spawn(DockMemory.Flush)
end)

return DockMemory
