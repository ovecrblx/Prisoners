--!strict
-- Animação dos NPCs, tocada pelo servidor. O catálogo sai do próprio `Animate` do rig — cada
-- StringValue é um grupo e cada Animation filha uma variante com peso — então trocar um id no
-- Studio basta. A locomoção vem da velocidade REAL do corpo, não da comandada.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NpcConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("NpcConfig"))

local NpcAnimator = {}

-- Grupos dirigidos pelo estado do corpo; o resto do catálogo (emotes, ferramenta) só toca por Play.
local LOCOMOTION = { "idle", "walk", "run", "jump", "fall", "climb", "swim", "swimidle", "sit" }

-- Faixa em que o script Animate toca locomoção; abaixo dela qualquer emote seria coberto.
local LOCOMOTION_PRIORITY = Enum.AnimationPriority.Core
local ACTION_PRIORITY = Enum.AnimationPriority.Action

type Variant = { id: string, weight: number }
type Catalogue = { [string]: { Variant } }

type Entry = {
	agent: any,
	catalogue: Catalogue,
	tracks: { [string]: AnimationTrack },
	current: string?,
	changedAt: number,
}

local catalogues: { [string]: Catalogue } = {}
local entries: { [string]: Entry } = {}
local warned: { [string]: boolean } = {}
local driver: RBXScriptConnection? = nil

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function catalogueOf(class: string, template: Model): Catalogue
	local cached = catalogues[class]
	if cached then
		return cached
	end

	local built: Catalogue = {}
	local animate = template:FindFirstChild("Animate")
	if animate then
		for _, group in ipairs(animate:GetChildren()) do
			local variants: { Variant } = {}
			for _, child in ipairs(group:GetChildren()) do
				if child:IsA("Animation") and child.AnimationId ~= "" then
					local weight = child:FindFirstChild("Weight")
					table.insert(variants, {
						id = child.AnimationId,
						weight = if weight and weight:IsA("NumberValue") then math.max(weight.Value, 0) else 1,
					})
				end
			end
			if #variants > 0 then
				built[string.lower(group.Name)] = variants
			end
		end
	else
		warnOnce("animate:" .. class, string.format("[NpcAnimator] %s sem Animate no template; sem animação.", class))
	end

	catalogues[class] = built
	return built
end

local function pick(variants: { Variant }): string
	local total = 0
	for _, variant in ipairs(variants) do
		total += variant.weight
	end
	if total <= 0 then
		return variants[1].id
	end
	local roll = math.random() * total
	for _, variant in ipairs(variants) do
		roll -= variant.weight
		if roll <= 0 then
			return variant.id
		end
	end
	return variants[#variants].id
end

-- LoadAnimation aceita qualquer id sem erro: asset que não resolve devolve track viva com
-- Length 0, em que Play não estoura e nada se move. Daí o aviso por comprimento.
local function loadTrack(entry: Entry, name: string, priority: Enum.AnimationPriority): AnimationTrack?
	local existing = entry.tracks[name]
	if existing then
		return existing
	end
	local variants = entry.catalogue[name]
	if not variants then
		return nil
	end

	local animator = entry.agent.Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		warnOnce("animator:" .. entry.agent.Class, "[NpcAnimator] Humanoid sem Animator; sem animação.")
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = pick(variants)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		warnOnce("load:" .. name, string.format("[NpcAnimator] falha ao carregar '%s': %s", name, tostring(track)))
		return nil
	end

	local loaded = track :: AnimationTrack
	loaded.Priority = priority
	loaded.Looped = name ~= "jump" and name ~= "fall"
	entry.tracks[name] = loaded
	return loaded
end

local function flatSpeed(agent: any): number
	local root = agent.RootPart
	if not root or not root.Parent then
		return 0
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function desired(agent: any, speed: number): string
	local humanoid = agent.Humanoid
	if humanoid.SeatPart ~= nil or humanoid.Sit then
		return "sit"
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Climbing then
		return "climb"
	elseif state == Enum.HumanoidStateType.Swimming then
		return if speed > NpcConfig.ANIM_IDLE_SPEED then "swim" else "swimidle"
	elseif state == Enum.HumanoidStateType.Jumping then
		return "jump"
	elseif state == Enum.HumanoidStateType.Freefall then
		return "fall"
	end

	if speed <= NpcConfig.ANIM_IDLE_SPEED then
		return "idle"
	elseif speed < NpcConfig.ANIM_RUN_SPEED then
		return "walk"
	end
	return "run"
end

local function apply(entry: Entry, name: string, now: number)
	if entry.current == name then
		return
	end
	-- Tempo mínimo no estado: sem ele o ruído de velocidade do rig de constraint pisca a troca.
	if entry.current and now - entry.changedAt < NpcConfig.ANIM_MIN_DWELL then
		return
	end

	local previous = if entry.current then entry.tracks[entry.current] else nil
	if previous and previous.IsPlaying then
		previous:Stop(NpcConfig.ANIM_FADE)
	end

	-- Idle sorteia variante a cada entrada: é o que faz a pose parada não ser sempre a mesma.
	if name == "idle" and entry.tracks.idle then
		entry.tracks.idle:Destroy()
		entry.tracks.idle = nil
	end

	local track = loadTrack(entry, name, LOCOMOTION_PRIORITY)
	entry.current = name
	entry.changedAt = now
	if not track then
		return
	end
	if track.Length == 0 then
		warnOnce("length:" .. name, string.format("[NpcAnimator] '%s' com duração 0: o asset não resolveu.", name))
	end
	track:Play(NpcConfig.ANIM_FADE)
end

local function step(entry: Entry, now: number)
	local agent = entry.agent
	if not agent.Humanoid.Parent then
		return
	end

	local speed = flatSpeed(agent)
	apply(entry, desired(agent, speed), now)

	local current = entry.current
	local track = if current then entry.tracks[current] else nil
	if track and track.IsPlaying then
		if current == "walk" then
			track:AdjustSpeed(math.clamp(speed / NpcConfig.ANIM_WALK_REFERENCE, 0.4, 2))
		elseif current == "run" then
			track:AdjustSpeed(math.clamp(speed / NpcConfig.ANIM_RUN_REFERENCE, 0.4, 2))
		end
	end
end

-- LoadAnimation pode render esperando o asset, então o vínculo sobe em thread própria.
function NpcAnimator.Attach(agent: any, template: Model)
	local entry: Entry = {
		agent = agent,
		catalogue = catalogueOf(agent.Class, template),
		tracks = {},
		current = nil,
		changedAt = 0,
	}
	entries[agent.Id] = entry

	task.spawn(function()
		if entries[agent.Id] ~= entry or not agent:IsAlive() then
			return
		end
		loadTrack(entry, "idle", LOCOMOTION_PRIORITY)
		apply(entry, "idle", os.clock())
	end)
end

-- Toca um grupo do catálogo uma vez, por cima da locomoção: emote, aceno, ferramenta.
function NpcAnimator.Play(agent: any, name: string): boolean
	local entry = entries[agent.Id]
	if not entry or entry.agent ~= agent then
		return false
	end
	local key = string.lower(name)
	if table.find(LOCOMOTION, key) then
		return false
	end
	local track = loadTrack(entry, key, ACTION_PRIORITY)
	if not track then
		return false
	end
	track.Looped = false
	track:Play(NpcConfig.ANIM_FADE)
	return true
end

function NpcAnimator.Forget(agent: any)
	local entry = entries[agent.Id]
	if not entry or entry.agent ~= agent then
		return
	end
	entries[agent.Id] = nil
	for _, track in pairs(entry.tracks) do
		track:Destroy()
	end
end

function NpcAnimator.Start()
	if driver then
		return
	end
	driver = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, entry in pairs(entries) do
			step(entry, now)
		end
	end)
end

return NpcAnimator
