-- Spawna o jogador como o Rig da classe equipada, lido do perfil. Sem classe, cai no avatar
-- padrão. CharacterAutoLoads fica desligado: o spawn automático apareceria com o avatar do
-- jogador antes da troca.
local ClassMorphService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local PlayerData = require(script.Parent.Parent:WaitForChild("Data"):WaitForChild("PlayerData"))

-- Segundos até renascer depois da morte.
local RESPAWN_DELAY = 5

-- Studs acima do SpawnLocation, para o rig não nascer dentro dele.
local SPAWN_OFFSET = 4

-- O perfil carrega em outra thread; PlayerData.Get devolve nil até lá.
local POLL_INTERVAL = 0.25
local POLL_TIMEOUT = 15

local warnedMissingRig = {}

local function rigTemplate(classId)
	local entry = ClassConfig.Get(classId)
	if not entry then
		return nil
	end

	local client = ReplicatedStorage:FindFirstChild("Client")
	local characters = client and client:FindFirstChild("Character")
	local folder = characters and characters:FindFirstChild(entry.Rig)
	local template = folder and folder:FindFirstChild("Rig")

	if not template and not warnedMissingRig[entry.Rig] then
		warnedMissingRig[entry.Rig] = true
		warn("[ClassMorphService] Rig ausente em Client.Character." .. entry.Rig .. "; usando o avatar padrão.")
	end

	return template
end

local function spawnCFrame()
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		return spawnLocation.CFrame + Vector3.new(0, SPAWN_OFFSET, 0)
	end
	return CFrame.new(0, SPAWN_OFFSET, 0)
end

local function awaitProfile(player)
	local deadline = os.clock() + POLL_TIMEOUT

	while os.clock() < deadline do
		if not player:IsDescendantOf(Players) then
			return false
		end
		if PlayerData.Get(player) then
			return true
		end
		task.wait(POLL_INTERVAL)
	end

	warn("[ClassMorphService] perfil de " .. player.Name .. " não carregou; spawn com avatar padrão")
	return false
end

local spawnFor

local function watchDeath(player, humanoid)
	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			if player:IsDescendantOf(Players) then
				spawnFor(player)
			end
		end)
	end)
end

-- O template vem ancorado, de servir ao viewer do Lobby; em jogo precisa cair no chão.
local function buildCharacter(player, template)
	local rig = template:Clone()
	rig.Name = player.Name

	for _, descendant in ipairs(rig:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
		end
	end

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root then
		rig.PrimaryPart = root
	end

	rig:PivotTo(spawnCFrame())
	local previous = player.Character
	rig.Parent = workspace
	player.Character = rig
	if previous and previous ~= rig then
		previous:Destroy()
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		watchDeath(player, humanoid)
	end
end

function spawnFor(player)
	awaitProfile(player)

	local classId = PlayerData.GetEquippedClass(player)
	player:SetAttribute(ClassConfig.EquippedAttribute, classId)

	local template = rigTemplate(classId)
	if not template then
		local ok, err = pcall(player.LoadCharacterAsync, player)
		if not ok then
			warn("[ClassMorphService] LoadCharacterAsync falhou para " .. player.Name .. ": " .. tostring(err))
		end
		return
	end

	buildCharacter(player, template)
end

function ClassMorphService.Init()
	Players.CharacterAutoLoads = false
end

function ClassMorphService.Start()
	-- A engine não destrói o Player nem o corpo de quem saiu, e conexão neles fica de pé. Depois dos
	-- outros PlayerRemoving, que ainda leem o jogador.
	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		task.defer(function()
			if character then
				character:Destroy()
			end
			player:Destroy()
		end)
	end)

	Players.PlayerAdded:Connect(function(player)
		task.spawn(spawnFor, player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(spawnFor, player)
	end
end

return ClassMorphService
