--!strict
-- Locomoção dos NPCs em dois relógios: a árvore escreve um destino a cada tick e um driver único no
-- Heartbeat comanda o corpo. `Humanoid:Move` e nunca `MoveTo` — o rig é de constraint (0 Motor6D) e
-- MoveTo não gera locomoção nele. O PathfindingService só PLANEJA waypoints; quem anda é o driver,
-- e este módulo é o dono único de `Humanoid.WalkSpeed`.
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local DoorConfig = require(Shared:WaitForChild("DoorConfig"))
local NpcConfig = require(Shared:WaitForChild("NpcConfig"))

local Movement = {}

export type Progress = "moving" | "arrived" | "stuck" | "idle"

type Entry = {
	agent: any,
	goal: Vector3,
	coast: boolean,
	setAt: number,
	status: Progress,

	points: { Vector3 }?,
	cursor: number,
	pathFor: Vector3?,
	pathObject: Path?,
	blockedConn: RBXScriptConnection?,
	agentParams: { [string]: any }?,
	generation: number,
	computing: boolean,
	computedAt: number,
	lastComputeAt: number,
	failCount: number,
	forceRepath: boolean,

	driveDir: Vector3?,
	moveScale: number,
	coastFrom: Vector3?,
	turnLockPoint: Vector3?,
	turnLockUntil: number,

	stuckTarget: Vector3?,
	stuckBest: number,
	stuckAt: number,
	progressAnchor: Vector3?,
	progressAt: number,
	detourDir: Vector3?,
	detourUntil: number,
	detourFlip: boolean,

	loopPos: Vector3?,
	loopAt: number,
	loopStreak: number,
	loopPinPos: Vector3?,
	loopPinAt: number?,
	loopBackDir: Vector3?,
	loopBackUntil: number,
	loopIdleUntil: number,
	loopPendingRepath: boolean,
}

local TURN_LOCK = math.rad(NpcConfig.MOVE_TURN_LOCK_ANGLE)
local TURN_ALIGNED = math.rad(NpcConfig.MOVE_TURN_ALIGNED_ANGLE)
local ESCAPE_WINDOW = NpcConfig.MOVE_LOOP_BACKSTEP_TIME + NpcConfig.MOVE_LOOP_IDLE_TIME

local entries: { [string]: Entry } = {}
local driver: RBXScriptConnection? = nil

-- ==================================================================== RÉGUAS E SONDAS

-- Toda decisão de chegada é XZ: o Humanoid não anda no eixo Y, e um alvo na mesma coluna ficaria
-- longe para sempre em 3D.
local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Dono único de "chegou": árvore e driver medem com o mesmo predicado e só divergem no raio.
local function arrived(target: Vector3, from: Vector3, radius: number): boolean
	return flatDist(target, from) <= radius and math.abs(target.Y - from.Y) <= NpcConfig.NAV_ARRIVE_Y
end

local probeCache: RaycastParams? = nil
local probeComplete = false

-- Não é mundo para as sondas: o desenho da rota, os corpos vivos e as portas (que abrem sozinhas na
-- aproximação — ver DoorService.Watch).
local function probeParams(): RaycastParams
	local cached = probeCache
	if cached ~= nil and probeComplete then
		return cached
	end

	local exclude: { Instance } = {}
	local complete = true
	for _, name in ipairs({ NpcConfig.NODE_FOLDER_NAME, NpcConfig.BODY_FOLDER }) do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(exclude, folder)
		else
			complete = false
		end
	end
	local doors: Instance? = Workspace
	for _, name in ipairs(DoorConfig.Folder) do
		doors = doors and doors:FindFirstChild(name)
	end
	if doors then
		table.insert(exclude, doors :: Instance)
	else
		complete = false
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	params.IgnoreWater = true
	params.RespectCanCollide = true
	probeCache = params
	probeComplete = complete
	return params
end

-- Slew-rate do esterço: a direção comandada persegue a desejada, nunca salta para ela.
local function turnToward(cur: Vector3?, want: Vector3, maxRad: number): Vector3
	if cur == nil or (cur :: Vector3).Magnitude < 1e-4 then
		return want
	end
	local from = cur :: Vector3
	local angle = math.acos(math.clamp(from:Dot(want), -1, 1))
	if angle <= maxRad then
		return want
	end
	local theta = if from.Z * want.X - from.X * want.Z >= 0 then maxRad else -maxRad
	local c, s = math.cos(theta), math.sin(theta)
	local rotated = Vector3.new(from.X * c + from.Z * s, 0, -from.X * s + from.Z * c)
	return if rotated.Magnitude > 1e-4 then rotated.Unit else want
end

-- O alcance é horizontal, a direção é a linha corpo -> destino em 3D: um raio horizontal apontado
-- ladeira acima lê o próprio chão como parede.
local function straightRay(from: Vector3, target: Vector3, maxProbe: number): Vector3?
	local flat = flatDist(target, from)
	local reach = math.min(flat, maxProbe)
	if reach <= 0.5 then
		return nil
	end
	return (target - from) * (reach / flat)
end

-- O piso do detector é PROPORCIONAL à velocidade comandada: um rig de constraint entrega uma fração
-- dela, e um piso absoluto acusaria loop de um corpo andando devagar por ordem.
local function loopTravelFloor(commanded: number): number
	return math.min(
		NpcConfig.MOVE_LOOP_MIN_TRAVEL,
		commanded * NpcConfig.MOVE_LOOP_INTERVAL * NpcConfig.MOVE_LOOP_TRAVEL_FRACTION
	)
end

-- Passo atrás no primeiro loop; a partir do segundo sai de lado, alternando pela paridade — recuar
-- pela linha por onde veio devolve o mesmo cálculo da mesma origem.
local function loopEscapeDir(driveDir: Vector3?, streak: number): Vector3?
	if driveDir == nil or (driveDir :: Vector3).Magnitude <= 0.1 then
		return nil
	end
	local dir = driveDir :: Vector3
	if streak < NpcConfig.MOVE_LOOP_STREAK_LATERAL then
		return -dir
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude <= 1e-3 then
		return -dir
	end
	local left = Vector3.new(-flat.Z, 0, flat.X).Unit
	return if streak % 2 == 0 then left else -left
end

-- ==================================================================== MARCHA (studs/s por classe)

local function gaitSpeed(class: string, gait: string): number
	local scale = NpcConfig.GAIT[class]
	if scale == nil then
		return NpcConfig.WALK_SPEED
	end
	return if gait == "Run" then scale.Run elseif gait == "Stalk" then scale.Stalk else scale.Walk
end

-- ==================================================================== ROTA: CÁLCULO E VALIDAÇÃO

local function clearPath(entry: Entry)
	entry.points = nil
	entry.cursor = 1
	entry.pathFor = nil
	entry.turnLockPoint = nil
	-- Reancora a janela do detector: a amostra a cavalo entre duas rotas julga a nova pela antiga.
	entry.loopPos = nil
	entry.loopAt = os.clock()

	local conn = entry.blockedConn
	if conn then
		conn:Disconnect()
		entry.blockedConn = nil
	end
	local path = entry.pathObject
	if path then
		path:Destroy()
		entry.pathObject = nil
	end
end

-- AgentRadius/AgentHeight saem da escala REAL do HumanoidRootPart: números fixos descrevem um corpo
-- menor que o do rig e aprovam rota por vão onde ele não cabe.
local function ensureAgentParams(entry: Entry): { [string]: any }
	local cached = entry.agentParams
	if cached ~= nil then
		return cached
	end
	local hrpHeight = (entry.agent.RootPart :: BasePart).Size.Y
	local scale = if hrpHeight > 0.1 then hrpHeight / NpcConfig.MOVE_HRP_REFERENCE else 1
	local params = {
		AgentRadius = math.clamp(
			NpcConfig.MOVE_AGENT_RADIUS * scale * NpcConfig.MOVE_AGENT_RADIUS_FACTOR,
			NpcConfig.MOVE_AGENT_RADIUS,
			NpcConfig.MOVE_AGENT_RADIUS_MAX
		),
		AgentHeight = math.clamp(
			NpcConfig.MOVE_AGENT_HEIGHT * scale,
			NpcConfig.MOVE_AGENT_HEIGHT_MIN,
			NpcConfig.MOVE_AGENT_HEIGHT_MAX
		),
		AgentCanJump = false,
	}
	entry.agentParams = params
	return params
end

local function clearanceNudge(point: Vector3, params: RaycastParams): Vector3
	local origin = point + Vector3.new(0, NpcConfig.MOVE_CHEST_PROBE, 0)
	local nudge = Vector3.zero
	local sides = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
	for _, dir in ipairs(sides) do
		local hit = Workspace:Raycast(origin, dir * NpcConfig.MOVE_WALL_CLEARANCE, params)
		if hit then
			local deficit = NpcConfig.MOVE_WALL_CLEARANCE - (hit.Position - origin).Magnitude
			if deficit > 0 then
				nudge -= dir * deficit
			end
		end
	end
	if nudge.Magnitude > NpcConfig.MOVE_MAX_NUDGE then
		nudge = nudge.Unit * NpcConfig.MOVE_MAX_NUDGE
	end
	return nudge
end

-- O navmesh aprova trecho rasante e simplifica malha; o feixe mede a geometria REAL. Acima da
-- tolerância de sondas obstruídas a rota é VETADA; abaixo dela o traçado só é afastado da parede.
-- Trecho que SOBE dispensa o raio de pé: ele corta o espelho do degrau e reprovaria toda escada.
local function validatePath(points: { Vector3 }, params: RaycastParams): { Vector3 }?
	if #points < 2 then
		return points
	end
	local limit = math.min(#points, NpcConfig.MOVE_MAX_VALIDATED)
	local blocked, tested = 0, 0

	for i = 1, limit - 1 do
		local a, b = points[i], points[i + 1]
		local delta = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		if delta.Magnitude > 0.05 then
			local sideways = Vector3.new(-delta.Unit.Z, 0, delta.Unit.X) * NpcConfig.MOVE_HALF_WIDTH
			local probes = {
				{ offset = Vector3.zero, height = NpcConfig.MOVE_CHEST_PROBE },
				{ offset = sideways, height = NpcConfig.MOVE_CHEST_PROBE },
				{ offset = -sideways, height = NpcConfig.MOVE_CHEST_PROBE },
			}
			if (b.Y - a.Y) <= NpcConfig.MOVE_CLIMB_EPSILON then
				table.insert(probes, { offset = Vector3.zero, height = NpcConfig.MOVE_FOOT_PROBE })
			end
			for _, probe in ipairs(probes) do
				local lift = Vector3.new(0, probe.height, 0)
				local from = a + probe.offset + lift
				local to = b + probe.offset + lift
				tested += 1
				if Workspace:Raycast(from, to - from, params) then
					blocked += 1
				end
			end
		end
	end

	if tested > 0 and blocked / tested > NpcConfig.MOVE_BLOCKED_TOLERANCE then
		return nil
	end

	for i = 1, limit do
		local nudge = clearanceNudge(points[i], params)
		if nudge.Magnitude > 0.01 then
			local probe = points[i] + Vector3.new(0, NpcConfig.MOVE_CHEST_PROBE, 0)
			if not Workspace:Raycast(probe, nudge, params) then
				points[i] = points[i] + nudge
			end
		end
	end
	return points
end

-- Nunca 1: o waypoint 1 é a origem passada ao cálculo, e o corpo andou durante o yield. O filtro de
-- Y é o mesmo do consumo — sem ele o mais próximo em XZ pode ser o lance de cima da escada.
local function pickStartIndex(points: { Vector3 }, from: Vector3): number
	if #points <= 1 then
		return 1
	end
	local bestIndex, bestDist = 1, math.huge
	for i, point in ipairs(points) do
		if math.abs(point.Y - from.Y) <= NpcConfig.MOVE_WAYPOINT_Y then
			local d = flatDist(point, from)
			if d < bestDist then
				bestDist = d
				bestIndex = i
			end
		end
	end
	return math.min(bestIndex + 1, #points)
end

local function computeFailed(entry: Entry)
	clearPath(entry)
	entry.failCount += 1
	entry.computedAt = os.clock()
	entry.computing = false
end

-- Assíncrono e sem yield para quem chama: o corpo segue andando com o que tem. Ao voltar do yield a
-- thread revalida o agente E a geração — o destino pode ter sido abandonado durante o cálculo.
local function beginCompute(entry: Entry, target: Vector3)
	local agent = entry.agent
	entry.generation += 1
	entry.computing = true
	entry.lastComputeAt = os.clock()
	entry.forceRepath = false

	local generation = entry.generation
	local params = ensureAgentParams(entry)

	task.spawn(function()
		local origin = (agent.RootPart :: BasePart).Position
		local path = PathfindingService:CreatePath(params)
		local ok = pcall(function()
			path:ComputeAsync(origin, target)
		end)

		if entries[agent.Id] ~= entry or entry.generation ~= generation or not agent:IsAlive() then
			path:Destroy()
			return
		end
		if not (ok and path.Status == Enum.PathStatus.Success) then
			path:Destroy()
			computeFailed(entry)
			return
		end

		local points: { Vector3 } = {}
		for _, waypoint in ipairs(path:GetWaypoints()) do
			table.insert(points, waypoint.Position)
		end
		local validated = validatePath(points, probeParams())
		if validated == nil then
			path:Destroy()
			computeFailed(entry)
			return
		end

		clearPath(entry)
		entry.points = validated
		entry.cursor = pickStartIndex(validated :: { Vector3 }, (agent.RootPart :: BasePart).Position)
		entry.pathFor = target
		entry.failCount = 0
		entry.pathObject = path
		entry.blockedConn = path.Blocked:Connect(function(blockedIndex: number)
			if entry.generation == generation and blockedIndex >= entry.cursor then
				entry.forceRepath = true
			end
		end)
		entry.computedAt = os.clock()
		entry.computing = false
	end)
end

-- Só olha estado. A ordem é a política: os dois motivos que furam o piso de tempo (rota reprovada e
-- destino trocado) vêm depois das travas que impedem oscilação.
local function needsRepath(entry: Entry, target: Vector3): boolean
	local now = os.clock()

	if entry.lastComputeAt > 0 and now - entry.lastComputeAt < NpcConfig.MOVE_MIN_COMPUTE_GAP then
		return false
	end
	if now < entry.loopIdleUntil then
		return false
	end
	if entry.computing then
		if now - entry.lastComputeAt < NpcConfig.MOVE_COMPUTE_TIMEOUT then
			return false
		end
		entry.computing = false
	end
	if entry.failCount >= NpcConfig.MOVE_MAX_PATH_FAILS then
		if now - entry.lastComputeAt < NpcConfig.MOVE_FAIL_RESET_COOLDOWN then
			return false
		end
		entry.failCount = 0
	end
	if entry.forceRepath then
		return true
	end

	local pathFor = entry.pathFor
	if pathFor ~= nil and flatDist(target, pathFor :: Vector3) > NpcConfig.MOVE_TARGET_DRIFT then
		return true
	end
	if entry.computedAt > 0 and now - entry.computedAt < NpcConfig.MOVE_REPATH_INTERVAL then
		return false
	end
	return entry.points == nil
end

-- ==================================================================== DRIVER (Heartbeat)

local function halt(entry: Entry)
	entry.driveDir = nil
	entry.progressAnchor = nil
	entry.coastFrom = nil
	local humanoid: Humanoid = entry.agent.Humanoid
	if humanoid.Parent then
		humanoid:Move(Vector3.zero, false)
	end
end

-- Passo atrás (ou de lado), parada, e só então rota nova: recalcular de dentro da quina devolve a
-- mesma rota impossível.
local function beginLoopReset(entry: Entry, now: number)
	clearPath(entry)
	entry.generation += 1
	entry.computing = false
	entry.loopStreak += 1
	entry.loopBackDir = loopEscapeDir(entry.driveDir, entry.loopStreak)
	entry.loopBackUntil = now + NpcConfig.MOVE_LOOP_BACKSTEP_TIME
	entry.loopIdleUntil = now + ESCAPE_WINDOW
	entry.loopPendingRepath = true
	entry.driveDir = nil
	entry.detourDir = nil
	entry.detourUntil = 0
	entry.turnLockPoint = nil
	entry.loopPos = nil
	entry.loopAt = now + ESCAPE_WINDOW

	local humanoid: Humanoid = entry.agent.Humanoid
	humanoid:Move(Vector3.zero, false)
end

local function step(entry: Entry, now: number, dt: number)
	local agent = entry.agent
	local humanoid: Humanoid = agent.Humanoid
	local root: BasePart = agent.RootPart
	-- `Sit` junto do assento: a flag sobrevive à solda destruída, e comandar corpo sentado não anda.
	if humanoid.Parent == nil or root.Parent == nil or humanoid.SeatPart ~= nil or humanoid.Sit then
		entry.status = "idle"
		return
	end

	-- Destino não renovado é destino abandonado: sem TTL a árvore que parasse deixaria o corpo
	-- andando para sempre.
	if now - entry.setAt > NpcConfig.GOAL_TTL then
		entry.status = "idle"
		halt(entry)
		return
	end

	local goal = entry.goal
	local myPos = root.Position
	local distToGoal = flatDist(goal, myPos)

	-- Janela de escape FECHADA: nenhuma ordem nova entra enquanto ela corre.
	if entry.loopIdleUntil > 0 then
		if now < entry.loopIdleUntil then
			local back = entry.loopBackDir
			if back ~= nil and now < entry.loopBackUntil then
				humanoid:Move((back :: Vector3) * NpcConfig.MOVE_LOOP_BACKSTEP_SCALE, false)
			else
				humanoid:Move(Vector3.zero, false)
			end
			return
		end
		entry.loopIdleUntil = 0
		entry.loopBackUntil = 0
		entry.loopBackDir = nil
		if entry.loopPendingRepath then
			entry.loopPendingRepath = false
			entry.forceRepath = true
		end
		entry.progressAnchor = myPos
		entry.progressAt = now
		-- A pausa é recuperação em andamento, não fracasso — devolve o tempo dela ao orçamento de
		-- inalcançável. Numa cadeia longa o crédito para, senão o ramo nunca chega a falhar.
		if entry.loopStreak < NpcConfig.MOVE_LOOP_STREAK_NO_CREDIT then
			entry.stuckAt = math.min(entry.stuckAt + ESCAPE_WINDOW, now)
		end
	end

	-- A árvore vê a chegada primeiro (ARRIVE_RADIUS), o driver freia depois (MOVE_DRIVE_RADIUS): o
	-- cursor avança a tempo e o corpo não assenta em cima do ponto esperando ordem.
	if arrived(goal, myPos, NpcConfig.ARRIVE_RADIUS) then
		entry.status = "arrived"
		entry.stuckTarget = nil
	else
		entry.status = "moving"
		local tracked = entry.stuckTarget
		if tracked == nil or flatDist(tracked :: Vector3, goal) > NpcConfig.MOVE_STUCK_TARGET_DELTA then
			entry.stuckTarget = goal
			entry.stuckBest = distToGoal
			entry.stuckAt = now
		elseif distToGoal < entry.stuckBest - NpcConfig.STUCK_PROGRESS then
			-- Só o RECORDE de aproximação zera o relógio: um corpo encravado desliza pelo batente e
			-- um cronômetro que aceitasse deslocamento nunca dispararia.
			entry.stuckBest = distToGoal
			entry.stuckAt = now
		elseif now - entry.stuckAt > NpcConfig.STUCK_TIME then
			entry.status = "stuck"
			entry.stuckTarget = nil
			halt(entry)
			return
		end
	end

	if arrived(goal, myPos, NpcConfig.MOVE_DRIVE_RADIUS) then
		if not (entry.coast and entry.driveDir ~= nil) then
			halt(entry)
			return
		end
		if entry.coastFrom == nil then
			entry.coastFrom = myPos
		end
	end

	-- Ponto de passagem: o corpo atravessa a favor da direção que já vinha, com teto de percurso —
	-- reapontar para um ponto que ficou atrás é meia-volta, pior que a parada.
	local coastFrom = if entry.coast then entry.coastFrom else nil
	if coastFrom ~= nil then
		local carry = entry.driveDir
		if carry ~= nil and flatDist(myPos, coastFrom :: Vector3) < NpcConfig.MOVE_DRIVE_RADIUS then
			humanoid:Move((carry :: Vector3) * entry.moveScale, false)
			return
		end
		halt(entry)
		return
	end

	-- Comandado a andar e sem sair do lugar = rota corrompida. Deslocamento LÍQUIDO entre duas
	-- amostras: raspar a parede percorre metros e não avança.
	if now - entry.loopAt >= NpcConfig.MOVE_LOOP_INTERVAL then
		local prev = entry.loopPos
		local travelled = if prev ~= nil then (myPos - (prev :: Vector3)).Magnitude else math.huge
		entry.loopPos = myPos
		entry.loopAt = now

		local pinAt = entry.loopPinAt
		if pinAt ~= nil and entry.loopStreak > 0 and now - (pinAt :: number) > NpcConfig.MOVE_LOOP_TRAP_FORGET then
			entry.loopStreak = 0
			entry.loopPinPos = nil
			entry.loopPinAt = nil
		end

		if travelled < loopTravelFloor(humanoid.WalkSpeed * entry.moveScale) and humanoid.MoveDirection.Magnitude > 0.05 then
			-- O escalonamento conta loops NO MESMO LUGAR: pino novo contra o anterior, no instante do
			-- loop. Armadilha nova (longe ou velha demais) recomeça a contagem.
			local pin = entry.loopPinPos
			local sameTrap = pin ~= nil
				and entry.loopPinAt ~= nil
				and now - (entry.loopPinAt :: number) <= NpcConfig.MOVE_LOOP_TRAP_FORGET
				and flatDist(pin :: Vector3, myPos) <= NpcConfig.MOVE_LOOP_TRAP_RADIUS
			if not sameTrap then
				entry.loopStreak = 0
			end
			entry.loopPinPos = myPos
			entry.loopPinAt = now
			beginLoopReset(entry, now)
			return
		end
	end

	-- Salto curto não paga cálculo: o driver cobre a diferença esterçando, e a sonda de linha reta
	-- responde pelo obstáculo.
	if distToGoal > NpcConfig.MOVE_SHORT_HOP then
		if needsRepath(entry, goal) then
			beginCompute(entry, goal)
		end
	elseif entry.points ~= nil then
		clearPath(entry)
	end

	local steerPoint = goal
	local points = entry.points
	if points ~= nil then
		local list = points :: { Vector3 }
		local cursor = entry.cursor
		while cursor <= #list do
			local wp = list[cursor]
			if
				flatDist(wp, myPos) <= NpcConfig.MOVE_DRIVE_RADIUS
				and math.abs(wp.Y - myPos.Y) <= NpcConfig.MOVE_WAYPOINT_Y
			then
				cursor += 1
			else
				break
			end
		end
		entry.cursor = cursor
		if cursor <= #list then
			steerPoint = list[cursor]
		else
			clearPath(entry)
			points = nil
		end
	end

	-- Sem rota, a linha reta é VERIFICADA antes de virar comando: bloqueada, o corpo SEGURA a posição
	-- e pede rota nova em vez de empurrar geometria.
	if points == nil then
		local ray = straightRay(myPos, goal, NpcConfig.MOVE_STRAIGHT_PROBE)
		local lift = Vector3.new(0, NpcConfig.MOVE_CHEST_PROBE, 0)
		if ray ~= nil and Workspace:Raycast(myPos + lift, ray :: Vector3, probeParams()) then
			if now - entry.lastComputeAt >= NpcConfig.MOVE_REPATH_INTERVAL then
				entry.forceRepath = true
			end
			humanoid:Move(Vector3.zero, false)
			return
		end
	end

	local detouring = entry.detourDir ~= nil and now < entry.detourUntil
	local wantDir: Vector3
	local turning = false
	if detouring then
		wantDir = entry.detourDir :: Vector3
		entry.turnLockPoint = nil
	else
		-- Curva fechada trava o ponto de esterço até o corpo alinhar: sem isso, ponto novo no meio da
		-- curva reinicia a curva e o corpo gira para sempre.
		local locked = entry.turnLockPoint
		if locked ~= nil and now < entry.turnLockUntil then
			steerPoint = locked :: Vector3
		else
			entry.turnLockPoint = nil
		end

		local toSteer = Vector3.new(steerPoint.X - myPos.X, 0, steerPoint.Z - myPos.Z)
		if toSteer.Magnitude < 0.05 then
			entry.turnLockPoint = nil
			humanoid:Move(Vector3.zero, false)
			return
		end
		wantDir = toSteer.Unit

		local cur = entry.driveDir
		local misalign = if cur ~= nil then math.acos(math.clamp((cur :: Vector3):Dot(wantDir), -1, 1)) else 0
		local nearSteer = toSteer.Magnitude < NpcConfig.MOVE_DRIVE_RADIUS
		if entry.turnLockPoint == nil then
			if misalign > TURN_LOCK and not nearSteer then
				entry.turnLockPoint = steerPoint
				entry.turnLockUntil = now + NpcConfig.MOVE_TURN_LOCK_TIMEOUT
			end
		elseif misalign <= TURN_ALIGNED or nearSteer then
			entry.turnLockPoint = nil
		end
		turning = entry.turnLockPoint ~= nil
	end

	local dir = turnToward(entry.driveDir, wantDir, NpcConfig.MOVE_MAX_TURN_RATE * dt)
	entry.driveDir = dir

	local scale = 1
	if turning then
		scale = NpcConfig.MOVE_TURN_SCALE
	end
	if not entry.coast and distToGoal < NpcConfig.MOVE_SLOWDOWN_RADIUS then
		scale = math.min(scale, math.max(distToGoal / NpcConfig.MOVE_SLOWDOWN_RADIUS, NpcConfig.MOVE_MIN_SCALE))
	end
	entry.moveScale = scale
	humanoid:Move(dir * scale, false)

	-- Destrave local: o raio frontal escolhe o LADO, não decide se desvia — este rig encrava com a
	-- frente parcialmente livre, e "comandado a andar sem deslocamento líquido" já é evidência.
	local anchor = entry.progressAnchor
	if anchor == nil or (myPos - (anchor :: Vector3)).Magnitude > NpcConfig.MOVE_UNSTICK_MIN_TRAVEL then
		entry.progressAnchor = myPos
		entry.progressAt = now
	elseif now - entry.progressAt > NpcConfig.MOVE_UNSTICK_TIMEOUT then
		entry.progressAnchor = myPos
		entry.progressAt = now

		local params = probeParams()
		local ahead = Workspace:Raycast(myPos, dir * NpcConfig.MOVE_UNSTICK_RAY, params)
		local left = Vector3.new(-dir.Z, 0, dir.X).Unit
		local leftFree = Workspace:Raycast(myPos, left * NpcConfig.MOVE_UNSTICK_RAY, params) == nil
		local rightFree = Workspace:Raycast(myPos, -left * NpcConfig.MOVE_UNSTICK_RAY, params) == nil

		local side: number
		if leftFree and not rightFree then
			side = 1
		elseif rightFree and not leftFree then
			side = -1
		else
			side = if entry.detourFlip then -1 else 1
			entry.detourFlip = not entry.detourFlip
		end

		entry.detourDir = left * side
		entry.detourUntil = now + NpcConfig.MOVE_UNSTICK_DETOUR
		entry.forceRepath = true
		if ahead ~= nil then
			clearPath(entry)
		end
	end
end

-- ==================================================================== SUPERFÍCIE PÚBLICA

local function newEntry(agent: any, goal: Vector3, now: number): Entry
	return {
		agent = agent,
		goal = goal,
		coast = false,
		setAt = now,
		status = "moving",
		points = nil,
		cursor = 1,
		pathFor = nil,
		pathObject = nil,
		blockedConn = nil,
		agentParams = nil,
		generation = 0,
		computing = false,
		computedAt = 0,
		lastComputeAt = 0,
		failCount = 0,
		forceRepath = false,
		driveDir = nil,
		moveScale = 1,
		coastFrom = nil,
		turnLockPoint = nil,
		turnLockUntil = 0,
		stuckTarget = nil,
		stuckBest = math.huge,
		stuckAt = now,
		progressAnchor = nil,
		progressAt = now,
		detourDir = nil,
		detourUntil = 0,
		detourFlip = false,
		loopPos = nil,
		loopAt = now,
		loopStreak = 0,
		loopPinPos = nil,
		loopPinAt = nil,
		loopBackDir = nil,
		loopBackUntil = 0,
		loopIdleUntil = 0,
		loopPendingRepath = false,
	}
end

-- Dono único de `Humanoid.WalkSpeed`: a árvore declara a intenção e a tradução para studs/s mora
-- aqui. Marcha ou classe desconhecida cai em Walk, nunca em erro.
function Movement.SetGait(agent: any, gait: string)
	local speed = gaitSpeed(agent.Class, gait)
	local humanoid: Humanoid = agent.Humanoid
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
	agent.Blackboard.Gait = gait
end

-- Destino novo zera a medida de progresso e descarta a rota de outro destino; renovar o MESMO
-- destino não, senão o detector de enguiço reiniciaria a cada tick da árvore e nunca dispararia.
-- `coast` marca ponto de PASSAGEM: a chegada não freia o corpo.
function Movement.SetGoal(agent: any, goal: Vector3, coast: boolean?)
	local now = os.clock()
	local existing = entries[agent.Id]
	if existing == nil or existing.agent ~= agent then
		existing = newEntry(agent, goal, now)
		entries[agent.Id] = existing
	end

	local entry = existing :: Entry
	if entry.goal ~= goal then
		entry.goal = goal
		entry.coastFrom = nil
		entry.status = "moving"
		local pathFor = entry.pathFor
		if pathFor ~= nil and flatDist(goal, pathFor :: Vector3) > NpcConfig.MOVE_TARGET_DRIFT then
			clearPath(entry)
			entry.forceRepath = true
			entry.generation += 1
			entry.computing = false
		end
	end
	entry.coast = coast == true
	entry.setAt = now

	if agent.Blackboard.Gait == nil then
		Movement.SetGait(agent, "Walk")
	end
end

function Movement.Status(agent: any): Progress
	local entry = entries[agent.Id]
	if entry == nil or entry.agent ~= agent then
		return "idle"
	end
	return entry.status
end

function Movement.Stop(agent: any)
	local entry = entries[agent.Id]
	if entry ~= nil then
		clearPath(entry)
		entries[agent.Id] = nil
	end
	local humanoid: Humanoid? = agent.Humanoid
	if humanoid ~= nil and (humanoid :: Humanoid).Parent then
		(humanoid :: Humanoid):Move(Vector3.zero, false)
	end
end

function Movement.Forget(agent: any)
	local entry = entries[agent.Id]
	if entry ~= nil then
		clearPath(entry)
		entries[agent.Id] = nil
	end
end

function Movement.Start()
	if driver then
		return
	end
	driver = RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		for id, entry in pairs(entries) do
			if entry.agent:IsAlive() then
				step(entry, now, dt)
			else
				clearPath(entry)
				entries[id] = nil
			end
		end
	end)
end

return Movement
