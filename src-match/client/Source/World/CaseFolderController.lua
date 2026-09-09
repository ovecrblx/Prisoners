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
local byStorage = {}
local watching = {}
local metrics
local active
local selected = 0
local highlight
local lifting = {}
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

local function mine(entry)
	local userId = entry.model and entry.model:GetAttribute(StorageConfig.UserAttribute)
	return type(userId) == "number" and userId == player.UserId
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

local function apply(entry, case)
	local rest = entry.rest[case.model]

	if not (rest and entry.box and entry.box.Parent) then
		return
	end

	case.model:PivotTo(entry.box.CFrame * rest + Vector3.new(0, case.height, 0))
end

local function poseAll(entry)
	if not entry.cases then
		return
	end

	for _, case in ipairs(entry.cases) do
		apply(entry, case)
	end
end

local function step(delta)
	for case, entry in pairs(lifting) do
		case.elapsed += delta

		local phase = CaseConfig.LiftProgress(case.elapsed, case.delay)
		local eased = TweenService:GetValue(phase, CaseConfig.LiftStyle, CaseConfig.LiftDirection)
		case.height = case.from + (case.goal - case.from) * eased
		apply(entry, case)

		if phase >= 1 then
			lifting[case] = nil
		end
	end

	if not next(lifting) and stepConnection then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function wake()
	if not stepConnection then
		stepConnection = RunService.PreSimulation:Connect(step)
	end
end

-- A pasta destacada só sobe DEPOIS de a gaveta terminar de sair: o levante é mais que o triplo do que
-- ela já sobra acima da borda, e começando junto com o curso ela passa por dentro da boca do móvel.
-- Quem já está com a gaveta aberta não espera nada, e descer nunca espera.
local function play(entry, case, up)
	case.from = case.height
	case.goal = if up then entry.lift else 0
	case.elapsed = 0
	case.delay = if up then math.max(0, (entry.liftAt or 0) - os.clock()) else 0

	if case.goal == case.from then
		return
	end

	lifting[case] = entry
	wake()
end

-- A pose de repouso de cada pasta é CALCULADA do molde e da gaveta, com a mesma conta que o servidor
-- usou para semear — nunca lida do pivô vivo. Lida, ela guarda o que quer que a pasta estivesse
-- fazendo no instante da leitura: já recolhida, já destacada, ou a gaveta já corrida. E o erro é
-- cumulativo, porque cada releitura parte da anterior.
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
				delay = 0,
			})

			cover = cover or coverOf(child)
		end
	end

	table.sort(cases, function(a, b)
		return a.slot < b.slot
	end)

	local rest = {}

	if metrics then
		local rig = { axis = entry.axis, depth = entry.depth, height = entry.height }

		for index, case in ipairs(cases) do
			rest[case.model] = CaseConfig.PoseAt(rig, if case.slot > 0 then case.slot else index, #cases, metrics)
		end
	end

	entry.cases = cases
	entry.rest = rest
	entry.lift = if cover then cover.Size.Y * CaseConfig.Lift else 0
end

-- Resolve a caixa e a fila da gaveta, e serve tanto à varredura quanto à hora do uso: a peça pode
-- chegar depois do Model, e a `DescendantAdded` que acorda a varredura só reage a Model, nunca a
-- peça. Guardar o resultado e confiar nele até o fim da partida deixa a gaveta muda para sempre.
local function resolve(entry)
	local model = entry.model
	local rig = model and model.Parent and StorageConfig.Rig(model)

	if not rig then
		entry.box = nil
		entry.cases = nil
		return false, false
	end

	if entry.box ~= rig.box then
		entry.box = rig.box
		entry.height = rig.height
		entry.axis = rig.axis
		entry.depth = rig.depth
		entry.rest = {}
		entry.cases = nil
	end

	if entry.cases and #entry.cases == counted(model) then
		return true, false
	end

	scan(entry)
	poseAll(entry)
	return true, true
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
	if not (camera and active and active.box and active.box.Parent) then
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

	-- A destacada DESCE, não some do ar: o fechamento leva 0.65 s e o levante desce em 0.18 s, então
	-- ela está deitada bem antes de o móvel a engolir.
	if active and active.cases then
		for _, case in ipairs(active.cases) do
			play(active, case, false)
		end
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

	-- Resolvido na hora do uso, e não no que a varredura guardou: caixa que saiu de cena deixa o
	-- guardado apontando para peça morta, e a vista simplesmente não abriria, sem erro nenhum.
	if not resolve(entry) then
		return
	end

	active = entry
	selected = 0
	entry.liftAt = os.clock() + CaseConfig.LiftDelay

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

-- As escutas nascem do MODEL, não da caixa: com streaming a peça chega depois, e a varredura que
-- acorda esta função só reage a Model. Presas à caixa, a gaveta ficaria sem dono e sem visor até
-- outro Model aparecer na pasta — que pode nunca aparecer.
local function bind(entry)
	local model = StorageConfig.Find(folder, entry.spec)

	if entry.model ~= model then
		entry.model = model
		entry.box = nil
		entry.cases = nil

		if entry.owner then
			entry.owner:Disconnect()
			entry.owner = nil
		end

		if model then
			entry.owner = model:GetAttributeChangedSignal(StorageConfig.UserAttribute):Connect(function()
				if mine(entry) then
					begin(entry)
				elseif active == entry then
					stop()
				end
			end)
		end

		if not model and active == entry then
			stop()
		end
	end

	local first = entry.box == nil
	local ok, rescanned = resolve(entry)

	-- Gaveta nova, ou fila nova numa gaveta que já é desta pessoa. Chamado em toda varredura, `begin`
	-- reabriria a vista no intervalo entre soltar a gaveta e o servidor devolver o `User`.
	if ok and mine(entry) and (first or (rescanned and active == entry)) then
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

	-- O MESMO molde que o servidor mediu para semear a fila: a conta da pose de repouso tem que ser a
	-- mesma dos dois lados, senão a fila que o cliente desenha pousa num lugar e a do servidor noutro.
	local template = ReplicatedStorage

	for _, name in ipairs(CaseConfig.TemplatePath) do
		template = template and template:WaitForChild(name, CaseConfig.TemplateWait)
	end

	if template then
		metrics = CaseConfig.Metrics(template)
	else
		warn(
			"[CaseFolderController] molde ReplicatedStorage."
				.. table.concat(CaseConfig.TemplatePath, ".")
				.. " não apareceu; a fila fica onde o servidor a deixou."
		)
	end

	for _, spec in ipairs(StorageConfig.Drawers) do
		local entry = { spec = spec, rest = {} }
		local list = byStorage[spec.storage] or {}

		table.insert(list, entry)
		byStorage[spec.storage] = list
	end

	-- Uma escuta por armário, e não uma na pasta inteira: com StreamingEnabled as PEÇAS chegam depois
	-- do Model, e reagir só a Model deixa a gaveta resolvida pela metade — sem caixa, sem dono, sem
	-- fila, e nada avisa. É a mesma escuta que o StorageController usa para correr o trilho.
	local function watch(storage)
		local list = byStorage[storage.Name]
		if not list or watching[storage] then
			return
		end

		watching[storage] = storage.DescendantAdded:Connect(function(child)
			if not (child:IsA("BasePart") or child:IsA("Model")) then
				return
			end

			for _, entry in ipairs(list) do
				bind(entry)
			end
		end)

		for _, entry in ipairs(list) do
			bind(entry)
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
			bind(entry)
		end
	end

	folder.ChildAdded:Connect(watch)
	folder.ChildRemoved:Connect(forget)

	for _, storage in ipairs(folder:GetChildren()) do
		watch(storage)
	end

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
