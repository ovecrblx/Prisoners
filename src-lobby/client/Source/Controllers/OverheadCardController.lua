-- Faz o cartão acima da cabeça encarar a câmera, reescrevendo o C0 do weld. SurfaceGui não tem
-- auto-facing. Roda local: a escrita não replica.
--
-- Escrever custa 14x o que custa decidir, então o laço decide antes: quem OverheadCardConfig.NeedsFacing
-- recusa não paga escrita nenhuma.
local OverheadCardController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))

-- Depois da câmera do quadro: ligado antes, o cartão encararia a posição do quadro anterior.
local BIND_NAME = "OverheadCardFacing"
local BIND_PRIORITY = Enum.RenderPriority.Camera.Value + 1

-- C0 de descanso por weld. Chaves fracas: o weld some no respawn.
local baseC0 = setmetatable({}, { __mode = "k" })

local function faceCamera(weld, head, cameraPosition)
	local base = baseC0[weld]
	if not base then
		base = weld.C0
		baseC0[weld] = base
	end

	local headCF = head.CFrame
	local c1 = weld.C1
	local restPosition = (headCF * c1 * base:Inverse()).Position

	if (cameraPosition - restPosition).Magnitude < Config.FacingNearLimit then
		return
	end

	local target = CFrame.lookAt(restPosition, cameraPosition)
	weld.C0 = target:Inverse() * headCF * c1
end

-- Peças do cartão resolvidas uma vez por personagem, não por quadro: o laço de render rodava quatro
-- FindFirstChild por jogador a 60 fps só para reencontrar as mesmas instâncias.
local tracked = {}
local watching = {}

local function resolve(player, character)
	local accessory = character:FindFirstChild(Config.AccessoryName)
	local handle = accessory and accessory:FindFirstChild(Config.HandleName)
	local head = character:FindFirstChild("Head")
	local weld = handle and handle:FindFirstChild(Config.WeldName)

	if handle and head and weld and weld:IsA("Weld") then
		tracked[player] = { handle = handle, head = head, weld = weld }
		return true
	end
	return false
end

-- O cartão nasce em outra thread, no servidor, e a solda vem depois dele. DescendantAdded espera as
-- duas chegarem e sai de cena assim que o par fecha.
local function watch(player, character)
	tracked[player] = nil
	local previous = watching[player]
	if previous then
		previous:Disconnect()
		watching[player] = nil
	end

	if resolve(player, character) then
		return
	end

	watching[player] = character.DescendantAdded:Connect(function()
		if resolve(player, character) then
			local link = watching[player]
			if link then
				link:Disconnect()
				watching[player] = nil
			end
		end
	end)
end

local function follow(player)
	if player.Character then
		watch(player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watch(player, character)
	end)
end

local function step()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local cameraCF = camera.CFrame

	for player, entry in pairs(tracked) do
		if entry.weld.Parent == nil or entry.head.Parent == nil then
			tracked[player] = nil
		elseif Config.NeedsFacing(cameraCF, entry.handle.CFrame) then
			faceCamera(entry.weld, entry.head, cameraCF.Position)
		end
	end
end

function OverheadCardController.Start()
	for _, player in ipairs(Players:GetPlayers()) do
		follow(player)
	end
	Players.PlayerAdded:Connect(follow)

	Players.PlayerRemoving:Connect(function(player)
		tracked[player] = nil
		local link = watching[player]
		if link then
			link:Disconnect()
			watching[player] = nil
		end
	end)

	RunService:BindToRenderStep(BIND_NAME, BIND_PRIORITY, step)
end

return OverheadCardController
