-- Grupos de colisão do place, registrados num lugar só: a ordem entre scripts não é garantida,
-- e atribuir Part a grupo ainda não registrado é erro.
local CollisionService = {}

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

-- Character: todo Part de personagem. Block: barreira que só o personagem sente; contra
-- Default ela é atravessável, então prop, detrito e qualquer coisa fora do grupo passa.
CollisionService.Groups = {
	Character = "Character",
	Block = "PlayerBlock",
}

local function ensure(name)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

local function assign(instance)
	if instance:IsA("BasePart") then
		instance.CollisionGroup = CollisionService.Groups.Character
	end
end

local function watch(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		assign(descendant)
	end

	-- Acessório e ferramenta entram depois do personagem.
	character.DescendantAdded:Connect(assign)
end

local function onPlayerAdded(player)
	if player.Character then
		watch(player.Character)
	end

	player.CharacterAdded:Connect(watch)
end

function CollisionService.Init()
	local character, block = CollisionService.Groups.Character, CollisionService.Groups.Block

	ensure(character)
	ensure(block)

	PhysicsService:CollisionGroupSetCollidable(block, "Default", false)
	PhysicsService:CollisionGroupSetCollidable(block, block, false)
	PhysicsService:CollisionGroupSetCollidable(block, character, true)
end

function CollisionService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return CollisionService
