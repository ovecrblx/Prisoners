-- Fila de pastas dentro da gaveta aberta: seleção, destaque e o levante da pasta escolhida.
-- Tudo local. O servidor semeia as pastas e publica `Slot` em cada uma; percorrer a fila não muda
-- estado de mundo, então não passa pela rede.
-- A pasta destacada sobe no eixo do MUNDO, e a conta sai sempre da pose de repouso guardada no
-- referencial da caixa da gaveta: a gaveta corre enquanto a fila está viva, e pose absoluta
-- guardada uma vez ficaria para trás no primeiro puxão.
local CaseFolderController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseConfig = require(Shared:WaitForChild("CaseConfig"))
local StorageConfig = require(Shared:WaitForChild("StorageConfig"))

local UI = script.Parent.Parent:WaitForChild("UI")
local KeyHint = require(UI:WaitForChild("KeyHint"))

local HINT_PREV = 1
local HINT_TAKE = 2
local HINT_NEXT = 3

local player = Players.LocalPlayer

local folder
local drawers = {}
local active
local selected = 0
local highlight
local lifting = {}
local stepConnection
local step
local takeWarned = false

local function coverOf(model)
	local part = model:FindFirstChild(CaseConfig.CoverName)
	return if part and part:IsA("BasePart") then part else nil
end

-- Pose de repouso no referencial da caixa: é o que sobrevive à gaveta correndo.
local function restOf(entry, case)
	local at = entry.rest[case]
	if not at then
		at = entry.box.CFrame:ToObjectSpace(case.model:GetPivot())
		entry.rest[case] = at
	end
	return at
end

local function apply(entry, case)
	local goal = entry.box.CFrame * restOf(entry, case)
	case.model:PivotTo(goal + Vector3.new(0, case.height, 0))
end

local function play(entry, case, up)
	case.from = case.height
	case.goal = if up then entry.lift else 0
	case.elapsed = 0

	if case.goal == case.from then
		return
	end

	lifting[case] = entry
	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

function step(delta)
	for case, entry in pairs(lifting) do
		case.elapsed = math.min(case.elapsed + delta, CaseConfig.LiftTime)

		local eased = TweenService:GetValue(
			case.elapsed / CaseConfig.LiftTime,
			CaseConfig.LiftStyle,
			CaseConfig.LiftDirection
		)
		case.height = case.from + (case.goal - case.from) * eased
		apply(entry, case)

		if case.elapsed >= CaseConfig.LiftTime then
			lifting[case] = nil
		end
	end

	if not next(lifting) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

-- Um Highlight só, mudando de dono. A página do Highlight não descreve Adornee nem o teto de
-- destaques simultâneos, então um exemplar reaproveitado é o caminho que não depende do que a doc
-- não diz.
local function adorn(model)
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "CaseSelection"
		highlight.FillTransparency = CaseConfig.FillTransparency
		highlight.OutlineTransparency = CaseConfig.OutlineTransparency
		highlight.FillColor = CaseConfig.FillColor
		highlight.OutlineColor = CaseConfig.OutlineColor
	end

	highlight.Adornee = model
	highlight.Parent = model
end

local function focus(index)
	if not active or #active.cases == 0 then
		return
	end

	local count = #active.cases
	local at = (index - 1) % count + 1
	if at == selected then
		return
	end

	local previous = active.cases[selected]
	if previous then
		play(active, previous, false)
	end

	selected = at
	local case = active.cases[selected]
	play(active, case, true)
	adorn(case.model)
end

local function casesIn(model)
	local list = {}

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(CaseConfig.IdAttribute) then
			table.insert(list, {
				model = child,
				slot = child:GetAttribute(CaseConfig.SlotAttribute) or 0,
				height = 0,
				from = 0,
				goal = 0,
				elapsed = 0,
			})
		end
	end

	table.sort(list, function(a, b)
		return a.slot < b.slot
	end)

	return list
end

local function close()
	if not active then
		return
	end

	for _, case in ipairs(active.cases) do
		lifting[case] = nil
		case.height = 0
		apply(active, case)
	end

	if highlight then
		highlight.Adornee = nil
		highlight.Parent = nil
	end

	KeyHint.Hide()
	active = nil
	selected = 0
end

local function open(entry)
	local model = StorageConfig.Find(folder, entry.spec)
	local rig = model and StorageConfig.Rig(model)
	if not rig then
		return
	end

	local cases = casesIn(model)
	if #cases == 0 then
		return
	end

	local cover = coverOf(cases[1].model)
	if not cover then
		return
	end

	entry.box = rig.box
	entry.cases = cases
	entry.rest = {}
	entry.lift = cover.Size.Y * CaseConfig.Lift

	active = entry
	selected = 0
	KeyHint.Show({
		{ key = CaseConfig.PrevKey, text = CaseConfig.PrevHint },
		{ key = CaseConfig.TakeKey, text = CaseConfig.TakeHint },
		{ key = CaseConfig.NextKey, text = CaseConfig.NextHint },
	})
	focus(1)
end

local function published(entry)
	local model = StorageConfig.Find(folder, entry.spec)
	return model ~= nil and model:GetAttribute(StorageConfig.OpenAttribute) == true
end

local function watch(entry)
	local model = StorageConfig.Find(folder, entry.spec)
	if not model or entry.model == model then
		return
	end

	entry.model = model
	if entry.link then
		entry.link:Disconnect()
	end

	entry.link = model:GetAttributeChangedSignal(StorageConfig.OpenAttribute):Connect(function()
		if published(entry) then
			open(entry)
		elseif active == entry then
			close()
		end
	end)
end

function CaseFolderController.Start()
	folder = workspace

	for _, name in ipairs(StorageConfig.Path) do
		folder = folder:WaitForChild(name, StorageConfig.FolderWait)
		if not folder then
			warn("[CaseFolderController] workspace." .. table.concat(StorageConfig.Path, ".") .. " não encontrado.")
			return
		end
	end

	for _, spec in ipairs(StorageConfig.Drawers) do
		table.insert(drawers, { spec = spec })
	end

	-- Com streaming a gaveta pode chegar depois deste Start e pode ir e voltar; a escuta do atributo
	-- vai junto com o exemplar.
	local function sweep()
		for _, entry in ipairs(drawers) do
			watch(entry)
		end
	end

	folder.DescendantAdded:Connect(function(child)
		if child:IsA("Model") then
			sweep()
		end
	end)
	sweep()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not active then
			return
		end

		if input.KeyCode == CaseConfig.PrevKey then
			KeyHint.Flash(HINT_PREV)
			focus(selected - 1)
		elseif input.KeyCode == CaseConfig.NextKey then
			KeyHint.Flash(HINT_NEXT)
			focus(selected + 1)
		elseif input.KeyCode == CaseConfig.TakeKey then
			KeyHint.Flash(HINT_TAKE)
			if not takeWarned then
				takeWarned = true
				warn("[CaseFolderController] pegar a pasta ainda não existe: falta decidir se ela vai para a mão.")
			end
		end
	end)

	player.CharacterRemoving:Connect(close)
end

return CaseFolderController
