-- Quem está usando cada gaveta dos armários de workspace.Siland_Home.interactive. A gaveta é de um
-- jogador de cada vez: o servidor guarda o dono, publica o UserId e o aberto/fechado, e apaga o
-- prompt enquanto ela tem dono. Correr o trilho, a câmera e a fila de pastas são de cada cliente.
-- Sair é pedido do cliente porque o gatilho é andar, que só ele vê no quadro do passo; quem escreve
-- o estado é sempre daqui, e pedido de quem não é dono não passa.
local StorageService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))
local StorageConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StorageConfig"))

local drawers = {}

local function publish(drawer, player)
	drawer.user = player
	drawer.model:SetAttribute(StorageConfig.UserAttribute, if player then player.UserId else 0)
	drawer.model:SetAttribute(StorageConfig.OpenAttribute, player ~= nil)

	if drawer.prompt then
		drawer.prompt.Enabled = player == nil
	end
end

local function release(drawer, player)
	if not drawer.user or (player and drawer.user ~= player) then
		return
	end

	for _, link in ipairs(drawer.links) do
		link:Disconnect()
	end
	table.clear(drawer.links)

	drawer.readyAt = os.clock() + drawer.cycle
	publish(drawer, nil)
end

local function take(drawer, player)
	if drawer.user or os.clock() < drawer.readyAt then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	publish(drawer, player)

	table.insert(drawer.links, humanoid.Died:Connect(function()
		release(drawer, player)
	end))
	table.insert(drawer.links, player.CharacterRemoving:Connect(function()
		release(drawer, player)
	end))
end

-- A âncora anda com a caixa, então o prompt acompanha a gaveta que saiu, e não entra em consulta
-- nenhuma.
local function buildPrompt(drawer, rig)
	local mark = Instance.new("Attachment")
	mark.Name = StorageConfig.PromptAnchor
	mark.Position = rig.axis * (rig.depth / 2 + StorageConfig.PromptDepth)
	mark.Parent = rig.box

	local prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = StorageConfig.PromptTitle
	prompt.UIOffset = StorageConfig.PromptOffset
	prompt.ClickablePrompt = StorageConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = StorageConfig.PromptDistance
	prompt.Parent = mark

	drawer.prompt = prompt
	prompt.Triggered:Connect(function(player)
		take(drawer, player)
	end)
end

local function releaseAll(player)
	for _, drawer in ipairs(drawers) do
		release(drawer, player)
	end
end

function StorageService.Init()
	Remotes.Event(StorageConfig.LeaveRemote).OnServerEvent:Connect(releaseAll)
	Players.PlayerRemoving:Connect(releaseAll)
end

function StorageService.Start()
	local folder = workspace

	for _, name in ipairs(StorageConfig.Path) do
		folder = folder:WaitForChild(name, StorageConfig.FolderWait)
		if not folder then
			warn("[StorageService] workspace." .. table.concat(StorageConfig.Path, ".") .. " não encontrado.")
			return
		end
	end

	for _, spec in ipairs(StorageConfig.Drawers) do
		local model = StorageConfig.Find(folder, spec)
		local rig = model and StorageConfig.Rig(model)

		if rig then
			local drawer = {
				model = model,
				links = {},
				readyAt = 0,
				cycle = math.max(StorageConfig.OpenTime, StorageConfig.CloseTime),
			}

			table.insert(drawers, drawer)
			publish(drawer, nil)
			buildPrompt(drawer, rig)
		else
			warn("[StorageService] " .. spec.storage .. "." .. spec.drawer .. " incompleta; sem prompt.")
		end
	end
end

return StorageService
