--!strict
-- Dono único do corpo. Os oito rigs de antes eram o MESMO Model — mesma malha, mesma textura, mesmo
-- Animate, mesmo Humanoid — e diferiam só em Shirt, Pants e um acessório. Agora existe um rig e a
-- classe é aparência aplicada em cima.
--
-- O corpo é o rig DENTRO do pacote, não uma cópia dele: assim "Update Package" feito no Lobby chega
-- ao Match. Uma cópia solta divergia calada — a prévia da loja mudava e o jogo continuava no corpo
-- velho. Mora em ServerStorage porque só o servidor clona; o cliente nunca leu esses templates.
local ServerStorage = game:GetService("ServerStorage")

local RigLibrary = {}

-- ServerStorage.Rigs: `Character` é o pacote com o PackageLink e dá o corpo padrão; `Npc.<Classe>`
-- guarda rig custom de NPC; `Accessories.<chave>` guarda os Accessory autorados aqui.
local RIG_FOLDER = "Rigs"
local BASE_PATH = { "Character", "citizen_class", "Rig" }
local NPC_FOLDER = "Npc"
local ACCESSORY_FOLDER = "Accessories"
local HANDLE_NAME = "Handle"
local RIGID_NAME = "AccessoryRigidConstraint"

export type Look = {
	Shirt: string?,
	Pants: string?,
	Accessories: { string }?,
}

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

-- FindFirstChild e nunca WaitForChild: sem a pasta, a espera pendura o boot.
local function descend(root: Instance, path: { string }): Instance?
	local current: Instance? = root
	for _, name in ipairs(path) do
		current = current and current:FindFirstChild(name)
	end
	return current
end

local function rigsFolder(): Instance?
	return ServerStorage:FindFirstChild(RIG_FOLDER)
end

function RigLibrary.Base(): Model?
	local folder = rigsFolder()
	local base = folder and descend(folder, BASE_PATH)
	if base and base:IsA("Model") then
		return base
	end
	warnOnce(
		"base",
		string.format(
			"[RigLibrary] corpo ausente em ServerStorage.%s.%s; ninguém nasce com rig.",
			RIG_FOLDER,
			table.concat(BASE_PATH, ".")
		)
	)
	return nil
end

-- Corpo da classe de NPC. Rig custom em `Rigs.Npc.<Classe>` é autorado COMPLETO — roupa, acessório e
-- Animate próprios — e por isso não passa por Dress: o catálogo de animação sai dele, então classe
-- com rig custom anima sozinha. Sem pasta, cai no corpo do pacote e a classe é só roupa.
function RigLibrary.Body(class: string): (Model?, boolean)
	local folder = rigsFolder()
	local npc = folder and folder:FindFirstChild(NPC_FOLDER)
	local custom = npc and npc:FindFirstChild(class)
	if custom and custom:IsA("Model") then
		return custom, true
	end
	return RigLibrary.Base(), false
end

local function accessoryTemplate(key: string, name: string): Accessory?
	local folder = rigsFolder()
	local accessories = folder and folder:FindFirstChild(ACCESSORY_FOLDER)
	local bucket = accessories and accessories:FindFirstChild(key)
	local template = bucket and bucket:FindFirstChild(name)
	if template and template:IsA("Accessory") then
		return template
	end
	warnOnce(
		"accessory:" .. key .. ":" .. name,
		string.format(
			"[RigLibrary] acessório %s ausente em ServerStorage.%s.%s.%s; o corpo nasce sem ele.",
			name,
			RIG_FOLDER,
			ACCESSORY_FOLDER,
			key
		)
	)
	return nil
end

-- Clone GUARDA referência para fora da própria árvore. O acessório autorado dentro de um rig sai do
-- Clone ainda apontando para a cabeça DAQUELE rig, e nada avisa: o boné acompanha um corpo parado no
-- ServerStorage, e vira nil no dia em que aquele rig for apagado.
local function unbind(accessory: Accessory)
	for _, descendant in ipairs(accessory:GetDescendants()) do
		if descendant:IsA("Constraint") then
			if descendant.Attachment0 and not descendant.Attachment0:IsDescendantOf(accessory) then
				descendant.Attachment0 = nil
			end
			if descendant.Attachment1 and not descendant.Attachment1:IsDescendantOf(accessory) then
				descendant.Attachment1 = nil
			end
		elseif descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			if descendant.Part0 and not descendant.Part0:IsDescendantOf(accessory) then
				descendant.Part0 = nil
			end
			if descendant.Part1 and not descendant.Part1:IsDescendantOf(accessory) then
				descendant.Part1 = nil
			end
		end
	end
end

-- Prende pelo NOME do attachment, e não por Humanoid:AddAccessory. A doc não descreve o mecanismo do
-- AddAccessory, e MEDIDO em Edit ele só parenteia: o RigidConstraint fica com Attachment1 nil e o
-- acessório cai. O alvo aqui é a forma que o rig de origem já tinha — A0 no Handle, A1 na parte do
-- corpo que carrega um attachment de mesmo nome.
local function attach(character: Model, accessory: Accessory): boolean
	local handle = accessory:FindFirstChild(HANDLE_NAME)
	if not handle or not handle:IsA("BasePart") then
		return false
	end

	for _, hook in ipairs(handle:GetChildren()) do
		if hook:IsA("Attachment") then
			for _, part in ipairs(character:GetChildren()) do
				if part:IsA("BasePart") then
					local mate = part:FindFirstChild(hook.Name)
					if mate and mate:IsA("Attachment") then
						local rigid = handle:FindFirstChildOfClass("RigidConstraint")
						if not rigid then
							rigid = Instance.new("RigidConstraint")
							rigid.Name = RIGID_NAME
							rigid.Parent = handle
						end
						;(rigid :: RigidConstraint).Attachment0 = hook
						;(rigid :: RigidConstraint).Attachment1 = mate
						return true
					end
				end
			end
		end
	end

	return false
end

-- Veste um clone da Base. Sem Shirt ou Pants a classe fica com a roupa da Base, que é a do Citizen —
-- um Guard sem roupa PARECE um civil e nada avisa, então a falta é um aviso alto.
function RigLibrary.Dress(character: Model, key: string, look: Look?)
	if not look then
		warnOnce("look:" .. key, string.format("[RigLibrary] %s sem aparência; nasce com a roupa da Base.", key))
		return
	end

	if look.Shirt then
		local shirt = character:FindFirstChildOfClass("Shirt")
		if shirt then
			shirt.ShirtTemplate = look.Shirt
		end
	end

	if look.Pants then
		local pants = character:FindFirstChildOfClass("Pants")
		if pants then
			pants.PantsTemplate = look.Pants
		end
	end

	for _, name in ipairs(look.Accessories or {}) do
		local template = accessoryTemplate(key, name)
		if template then
			local accessory = template:Clone()
			unbind(accessory)
			if attach(character, accessory) then
				accessory.Parent = character
			else
				accessory:Destroy()
				warnOnce(
					"attach:" .. key .. ":" .. name,
					string.format("[RigLibrary] %s não achou onde prender %s no corpo; nasce sem ele.", key, name)
				)
			end
		end
	end
end

return RigLibrary
