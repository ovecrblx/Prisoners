-- Semeia a fila de pastas de caso numa gaveta, uma vez por partida. A gaveta é sorteada entre as que
-- ABREM: pasta em gaveta sem prompt é conteúdo que ninguém alcança. A fila inteira vai numa gaveta
-- só, porque é ela que o jogador percorre com as teclas.
-- As pastas entram como filhas do Model da gaveta, então o PivotTo do cliente as leva junto quando a
-- gaveta corre — sem solda e sem uma segunda animação para manter em sincronia.
local CaseFolderService = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CaseConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CaseConfig"))
local StorageConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("StorageConfig"))

-- O que o molde não tiver vira aviso: pasta com o nome autorado passa por caso de verdade na tela.
local function dress(clone, case, slot)
	local missing = CaseConfig.Dress(clone, case)
	if #missing > 0 then
		warn("[CaseFolderService] molde incompleto, faltou: " .. table.concat(missing, ", "))
	end
	clone:SetAttribute(CaseConfig.SlotAttribute, slot)
end

-- Fisher-Yates sobre uma cópia: o sorteio não pode reordenar a lista que o resto do jogo lê.
local function shuffled(list, random)
	local copy = table.clone(list)
	for index = #copy, 2, -1 do
		local pick = random:NextInteger(1, index)
		copy[index], copy[pick] = copy[pick], copy[index]
	end
	return copy
end

local function resolveFolder()
	local folder = workspace

	for _, name in ipairs(StorageConfig.Path) do
		folder = folder:WaitForChild(name, StorageConfig.FolderWait)
		if not folder then
			warn("[CaseFolderService] workspace." .. table.concat(StorageConfig.Path, ".") .. " não encontrado.")
			return nil
		end
	end

	return folder
end

local function resolveTemplate()
	local template = ReplicatedStorage

	for _, name in ipairs(CaseConfig.TemplatePath) do
		template = template:WaitForChild(name, CaseConfig.TemplateWait)
		if not template then
			warn("[CaseFolderService] ReplicatedStorage." .. table.concat(CaseConfig.TemplatePath, ".") .. " não encontrado.")
			return nil
		end
	end

	return template
end

function CaseFolderService.Start()
	local folder = resolveFolder()
	local template = folder and resolveTemplate()
	if not template then
		return
	end

	if #CaseConfig.Cases == 0 then
		warn("[CaseFolderService] nenhum caso na lista; nenhuma pasta nasce.")
		return
	end

	local random = Random.new()
	local cases = shuffled(CaseConfig.Cases, random)
	local count = math.min(CaseConfig.PerDrawer, #cases)

	-- Sai do molde, não de constante: trocar a arte da pasta reposiciona a fila junto.
	local metrics = CaseConfig.Metrics(template)

	for _, spec in ipairs(shuffled(StorageConfig.Drawers, random)) do
		local model = StorageConfig.Find(folder, spec)
		local rig = model and StorageConfig.Rig(model)

		if rig then
			for slot = 1, count do
				local clone = template:Clone()
				dress(clone, cases[slot], slot)
				clone.Parent = model
				clone:PivotTo(rig.box.CFrame * CaseConfig.PoseAt(rig, slot, count, metrics))
			end
			return
		end
	end

	warn("[CaseFolderService] nenhuma gaveta completa; a fila de pastas não nasceu.")
end

return CaseFolderService
