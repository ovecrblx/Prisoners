-- Estado das gavetas dos armários de workspace.Siland_Home.interactive. O servidor só sabe se a
-- gaveta está fora: publica no atributo do Model dela e cria o ProximityPrompt. Correr o trilho é
-- do cliente. Gaveta fora da lista do StorageConfig nem chega aqui.
local StorageService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StorageConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StorageConfig"))

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

	prompt.Triggered:Connect(function()
		if os.clock() < drawer.readyAt then
			return
		end

		drawer.readyAt = os.clock() + drawer.cycle
		drawer.open = not drawer.open
		drawer.model:SetAttribute(StorageConfig.OpenAttribute, drawer.open)
	end)
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
				open = false,
				readyAt = 0,
				cycle = math.max(StorageConfig.OpenTime, StorageConfig.CloseTime),
			}

			model:SetAttribute(StorageConfig.OpenAttribute, false)
			buildPrompt(drawer, rig)
		else
			warn("[StorageService] " .. spec.storage .. "." .. spec.drawer .. " incompleta; sem prompt.")
		end
	end
end

return StorageService
