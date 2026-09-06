-- Corrida das gavetas dos armários, local em cada cliente. O servidor só publica se a gaveta está
-- fora; o trilho, a distância e o amortecimento saem daqui. Uma animação por gaveta da lista do
-- StorageConfig, com o estado lido do Model dela.
local StorageController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local StorageConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StorageConfig"))

local folder
local byStorage = {}
local watching = {}
local active = {}
local stepConnection
local step
local setState

-- CFrame + Vector3 empurra a pose em coordenadas do mundo e não mexe na rotação (medido; a página
-- do CFrame lista a operação sem descrever). A conta sai sempre da pose de repouso, nunca da
-- anterior: incremental acumula erro e a gaveta escorrega do batente.
local function apply(entry, alpha)
	entry.alpha = alpha
	entry.model:PivotTo(entry.rest + entry.out * (entry.distance * alpha))
end

local function published(entry)
	local model = StorageConfig.Find(folder, entry.spec)
	return model ~= nil and model:GetAttribute(StorageConfig.OpenAttribute) == true
end

-- A gaveta só se move aqui, então o servidor sempre a devolve recolhida: o que o streaming trouxer
-- de volta serve de pose de referência. Caixa nova é peça nova, e a escuta do atributo vai junto.
local function resolve(entry)
	local model = StorageConfig.Find(folder, entry.spec)
	local rig = model and StorageConfig.Rig(model)

	if not rig then
		entry.box = nil
		return false
	end

	if entry.box == rig.box then
		return true, false
	end

	entry.model = model
	entry.box = rig.box
	entry.rest = model:GetPivot()
	entry.out = rig.out
	entry.distance = rig.depth * StorageConfig.Travel
	entry.alpha = 0

	if entry.link then
		entry.link:Disconnect()
	end
	entry.link = model:GetAttributeChangedSignal(StorageConfig.OpenAttribute):Connect(function()
		setState(entry, model:GetAttribute(StorageConfig.OpenAttribute) == true, true)
	end)

	return true, true
end

local function play(entry)
	entry.elapsed = 0
	entry.from = entry.alpha
	entry.goal = entry.open and 1 or 0

	if entry.open then
		entry.duration = StorageConfig.OpenTime
		entry.style = StorageConfig.OpenStyle
		entry.direction = StorageConfig.OpenDirection
	else
		entry.duration = StorageConfig.CloseTime
		entry.style = StorageConfig.CloseStyle
		entry.direction = StorageConfig.CloseDirection
	end

	active[entry] = true

	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

function step(delta)
	for entry in pairs(active) do
		entry.elapsed = math.min(entry.elapsed + delta, entry.duration)

		local eased = TweenService:GetValue(entry.elapsed / entry.duration, entry.style, entry.direction)
		apply(entry, entry.from + (entry.goal - entry.from) * eased)

		if entry.elapsed >= entry.duration then
			active[entry] = nil
		end
	end

	if not next(active) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

function setState(entry, open, animate)
	entry.open = open

	if not resolve(entry) then
		return
	end

	if animate then
		play(entry)
	else
		active[entry] = nil
		apply(entry, open and 1 or 0)
	end
end

-- Com streaming as peças chegam depois do armário, e o armário pode ir e voltar. Uma escuta por
-- armário cobre as gavetas dele: são 24 descendentes, e a alternativa seria uma escuta por nível.
-- Só peça conta, e só quando a caixa troca de exemplar: o som da gaveta nasce DENTRO da caixa, e
-- reagir a ele recolocaria a gaveta na pose final no quadro em que ela começa a andar.
local function watch(storage)
	local list = byStorage[storage.Name]
	if not list or watching[storage] then
		return
	end

	watching[storage] = storage.DescendantAdded:Connect(function(child)
		if not child:IsA("BasePart") then
			return
		end

		for _, entry in ipairs(list) do
			local _, changed = resolve(entry)
			if changed then
				setState(entry, published(entry), false)
			end
		end
	end)

	for _, entry in ipairs(list) do
		setState(entry, published(entry), false)
	end
end

local function forget(storage)
	local link = watching[storage]
	if not link then
		return
	end

	link:Disconnect()
	watching[storage] = nil

	for _, entry in ipairs(byStorage[storage.Name]) do
		if entry.link then
			entry.link:Disconnect()
			entry.link = nil
		end
		entry.box = nil
		active[entry] = nil
	end
end

function StorageController.Start()
	folder = workspace

	for _, name in ipairs(StorageConfig.Path) do
		folder = folder:WaitForChild(name, StorageConfig.FolderWait)
		if not folder then
			warn("[StorageController] workspace." .. table.concat(StorageConfig.Path, ".") .. " não encontrado.")
			return
		end
	end

	for _, spec in ipairs(StorageConfig.Drawers) do
		local entry = {
			spec = spec,
			open = false,
			alpha = 0,
			from = 0,
			goal = 0,
			elapsed = 0,
			duration = StorageConfig.OpenTime,
			style = StorageConfig.OpenStyle,
			direction = StorageConfig.OpenDirection,
		}

		local list = byStorage[spec.storage] or {}
		table.insert(list, entry)
		byStorage[spec.storage] = list
	end

	folder.ChildAdded:Connect(watch)
	folder.ChildRemoved:Connect(forget)

	for _, storage in ipairs(folder:GetChildren()) do
		watch(storage)
	end
end

return StorageController
