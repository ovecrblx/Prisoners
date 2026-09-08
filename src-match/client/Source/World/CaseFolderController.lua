-- A fila de pastas de caso das gavetas: onde cada pasta pousa, o recolhimento dela dentro da caixa,
-- e — na gaveta deste jogador — a vista, o destaque e o levante da escolhida.
-- Quem decide de quem é a gaveta é o servidor, e publica no atributo dela; aqui só se lê. Percorrer
-- a fila não muda estado de mundo, então não passa pela rede — só sair passa, porque quem fecha a
-- gaveta é o servidor.
-- Andar larga a gaveta, como largar o telefone: o gatilho é do cliente porque só ele vê o passo no
-- quadro em que acontece.
-- O recolhimento vale em TODA gaveta da lista, não só na deste jogador: a gaveta do outro é vista
-- daqui, e a pasta é mais alta que a caixa. Toda pose de pasta é escrita AQUI, num lugar só: sai da
-- pose de repouso guardada no referencial da caixa, e o recolhimento e o destaque somam no mesmo
-- eixo do MUNDO. A gaveta corre enquanto a fila está viva, e pose absoluta guardada uma vez ficaria
-- para trás no primeiro puxão.
local CaseFolderController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CaseConfig = require(Shared:WaitForChild("CaseConfig"))
local StorageConfig = require(Shared:WaitForChild("StorageConfig"))

local UI = script.Parent.Parent:WaitForChild("UI")
local KeyHint = require(UI:WaitForChild("KeyHint"))
local Sfx = require(script.Parent.Parent:WaitForChild("Lib"):WaitForChild("Sfx"))

local HINT_PREV = 1
local HINT_TAKE = 2
local HINT_NEXT = 3

-- Depois do módulo de câmera, pelo mesmo motivo do telefone: ele escreve a CFrame em
-- RenderPriority.Camera, e escrever antes dele seria escrever no quadro passado.
local RENDER_BIND = "CaseFolderView"
local RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 2

local player = Players.LocalPlayer

local folder
local leaveRemote
local drawers = {}
local active
local selected = 0
local highlight
local lifting = {}
local rising = {}
local links = {}
local stepConnection
local render = false
local settled = false
local token = 0
local takeWarned = false

local function coverOf(model)
	local part = model:FindFirstChild(CaseConfig.CoverName)
	return if part and part:IsA("BasePart") then part else nil
end

local function apply(entry, case)
	local rest = entry.rest[case.model]
	if not rest then
		return
	end

	local sunk = entry.stow * (1 - entry.rise)
	case.model:PivotTo(entry.box.CFrame * rest + Vector3.new(0, case.height - sunk, 0))
end

local function poseAll(entry)
	if not (entry.cases and entry.box and entry.box.Parent) then
		return
	end

	for _, case in ipairs(entry.cases) do
		apply(entry, case)
	end
end

local function step(delta)
	for entry in pairs(rising) do
		entry.riseElapsed += delta

		local phase = CaseConfig.RiseProgress(entry.riseElapsed, entry.riseOpen)
		local eased = TweenService:GetValue(phase, CaseConfig.RiseStyle, CaseConfig.RiseDirection)
		entry.rise = entry.riseFrom + (entry.riseGoal - entry.riseFrom) * eased
		poseAll(entry)

		if phase >= 1 then
			rising[entry] = nil
		end
	end

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

	if not (next(lifting) or next(rising)) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function wake()
	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

local function play(entry, case, up)
	case.from = case.height
	case.goal = if up then entry.lift else 0
	case.elapsed = 0

	if case.goal == case.from then
		return
	end

	lifting[case] = entry
	wake()
end

-- A fila sobe depois do curso e desce durante o fechamento. `animate` falso é para quem chega com a
-- gaveta já parada: streaming trazendo o móvel de volta não é um puxão.
local function setRise(entry, open, animate)
	local goal = if open then 1 else 0

	if not entry.cases then
		entry.rise = goal
		return
	end

	if not animate then
		rising[entry] = nil
		entry.rise = goal
		poseAll(entry)
		return
	end

	if entry.rise == goal and not rising[entry] then
		return
	end

	entry.riseFrom = entry.rise
	entry.riseGoal = goal
	entry.riseOpen = open
	entry.riseElapsed = 0

	rising[entry] = true
	wake()
end

-- A pose de repouso de cada pasta é lida NO MOMENTO em que ela aparece, que é a pose semeada pelo
-- servidor. Relida depois do recolhimento, ela guardaria o afundamento junto, e a fila desceria de
-- novo a cada varredura.
local function scan(entry)
	local cases = {}
	local cover

	for _, child in ipairs(entry.model:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(CaseConfig.IdAttribute) then
			table.insert(cases, {
				model = child,
				slot = child:GetAttribute(CaseConfig.SlotAttribute) or 0,
				height = 0,
				from = 0,
				goal = 0,
				elapsed = 0,
			})

			if not entry.rest[child] then
				entry.rest[child] = entry.box.CFrame:ToObjectSpace(child:GetPivot())
			end

			cover = cover or coverOf(child)
		end
	end

	table.sort(cases, function(a, b)
		return a.slot < b.slot
	end)

	entry.cases = cases
	entry.lift = if cover then cover.Size.Y * CaseConfig.Lift else 0
	entry.stow = if cover then CaseConfig.StowDepth(entry.height, cover.Size) else 0
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
	Sfx.Play("CaseSelect", coverOf(case.model))
end

-- Em Scriptable o módulo de câmera larga o volante. O enquadramento chega por percurso e não por
-- corte, e sai da caixa da gaveta, então acompanha o trilho enquanto ela abre.
local function aim(delta)
	local camera = Workspace.CurrentCamera
	if not (camera and active and active.box.Parent) then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(
		CaseConfig.View(active.box),
		1 - math.exp(-CaseConfig.CameraSmoothing * delta)
	)
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

local function stop()
	token += 1

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)

	if render then
		render = false
		RunService:UnbindFromRenderStep(RENDER_BIND)
		restoreCamera()
	end

	if active then
		for _, case in ipairs(active.cases) do
			lifting[case] = nil
			case.height = 0
		end
		poseAll(active)
	end

	if highlight then
		highlight.Adornee = nil
		highlight.Parent = nil
	end

	KeyHint.Hide()
	active = nil
	selected = 0
	settled = false
end

-- Pedido de saída. Quem fecha a gaveta é o servidor: solta a vista na hora para o gesto não engasgar,
-- e o resto chega pelo atributo.
local function leave()
	if not active then
		return
	end

	stop()
	if leaveRemote then
		leaveRemote:FireServer()
	end
end

local function begin(entry)
	stop()

	if not (entry.cases and entry.box and entry.box.Parent) then
		return
	end

	active = entry
	selected = 0

	render = true
	RunService:BindToRenderStep(RENDER_BIND, RENDER_PRIORITY, aim)

	-- Gaveta vazia continua sendo uso exclusivo e continua tendo vista: o que ela não tem é fila para
	-- percorrer, então a dica de tecla também não entra.
	if #entry.cases > 0 then
		KeyHint.Pin({
			{ key = CaseConfig.PrevKey, text = CaseConfig.PrevHint },
			{ key = CaseConfig.TakeKey, text = CaseConfig.TakeHint },
			{ key = CaseConfig.NextKey, text = CaseConfig.NextHint },
		})
		focus(1)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	-- Quem acabou de acionar o prompt ainda carrega a velocidade do último passo; sem a janela a
	-- gaveta se fecharia no quadro seguinte ao gesto que a abriu.
	local mark = token
	settled = false
	task.delay(CaseConfig.SettleWait, function()
		if token == mark then
			settled = true
		end
	end)

	table.insert(links, humanoid.Running:Connect(function(speed)
		if settled and speed > CaseConfig.CancelSpeed then
			leave()
		end
	end))
	table.insert(links, humanoid.Jumping:Connect(function(jumping)
		if jumping then
			leave()
		end
	end))
	table.insert(links, humanoid.Died:Connect(leave))
end

local function mine(entry)
	local userId = entry.model and entry.model:GetAttribute(StorageConfig.UserAttribute)
	return type(userId) == "number" and userId == player.UserId
end

local function published(entry)
	return entry.model ~= nil and entry.model:GetAttribute(StorageConfig.OpenAttribute) == true
end

local function counted(model)
	local total = 0

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute(CaseConfig.IdAttribute) then
			total += 1
		end
	end

	return total
end

-- Com streaming a gaveta pode chegar depois deste Start, pode ir e voltar, e as pastas podem chegar
-- depois da gaveta. Caixa nova é referencial novo, então a pose de repouso guardada morre com ela.
local function bind(entry)
	local model = StorageConfig.Find(folder, entry.spec)
	local rig = model and StorageConfig.Rig(model)

	if not rig then
		rising[entry] = nil
		entry.box = nil
		entry.cases = nil
		return
	end

	local fresh = entry.box ~= rig.box

	if fresh then
		entry.model = model
		entry.box = rig.box
		entry.height = rig.height
		entry.rest = {}
		entry.cases = nil
		entry.rise = 0
		entry.stow = 0
		rising[entry] = nil

		if entry.link then
			entry.link:Disconnect()
		end

		entry.link = model:GetAttributeChangedSignal(StorageConfig.OpenAttribute):Connect(function()
			setRise(entry, published(entry), true)
		end)

		if entry.owner then
			entry.owner:Disconnect()
		end

		entry.owner = model:GetAttributeChangedSignal(StorageConfig.UserAttribute):Connect(function()
			if mine(entry) then
				begin(entry)
			elseif active == entry then
				stop()
			end
		end)
	end

	local rescanned = false

	if not entry.cases or #entry.cases ~= counted(model) then
		scan(entry)
		setRise(entry, published(entry), false)
		rescanned = true
	end

	-- Gaveta nova, ou fila nova numa gaveta que já é desta pessoa. Chamado em toda varredura, `begin`
	-- reabriria a vista no intervalo entre soltar a gaveta e o servidor devolver o `User`.
	if mine(entry) and (fresh or (rescanned and active == entry)) then
		begin(entry)
	end
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

	local remotes = ReplicatedStorage:WaitForChild("Remotes", StorageConfig.FolderWait)
	leaveRemote = remotes and remotes:WaitForChild(StorageConfig.LeaveRemote, StorageConfig.FolderWait)
	if not leaveRemote then
		warn("[CaseFolderController] remote " .. StorageConfig.LeaveRemote .. " não apareceu; sair não sai do cliente.")
	end

	for _, spec in ipairs(StorageConfig.Drawers) do
		table.insert(drawers, { spec = spec, rise = 0, stow = 0, rest = {} })
	end

	local function sweep()
		for _, entry in ipairs(drawers) do
			bind(entry)
		end
	end

	folder.DescendantAdded:Connect(function(child)
		if child:IsA("Model") then
			sweep()
		end
	end)
	sweep()

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not (active and #active.cases > 0) then
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
				warn("[CaseFolderController] coletar a pasta ainda não existe: falta definir o que coletar faz.")
			end
		end
	end)

	player.CharacterRemoving:Connect(stop)
end

return CaseFolderController
