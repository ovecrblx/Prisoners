-- Ventiladores da decoração: a hélice `Rot` de cada Model `Fan` gira, só neste cliente. É enfeite,
-- então nada replica — escrita de CFrame em peça do servidor não subiria de todo jeito. Uma passada
-- no boot e o resto por evento: com streaming a pasta chega vazia, e varrer em loop atrás dela seria
-- gastar quadro para saber o que a engine já avisa.
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FanController = {}

-- Onde varrer, o Model que carrega a hélice, e o nome dela.
local FOLDER = { "Siland_Home", "Decoration" }
local FAN_NAME = "fan"
local ROTOR_NAME = "Rot"

-- graus/s da hélice, e o eixo do giro no espaço da própria peça.
local SPIN_SPEED = 320
local SPIN_AXIS = Vector3.new(0, 0, 1)

-- studs até a câmera para a hélice girar, e s entre as medidas de distância.
local ACTIVE_RADIUS = 120
local CHECK_INTERVAL = 0.5

-- s de espera pela pasta no boot.
local FOLDER_WAIT = 20

-- Todas as hélices achadas, as que estão perto agora, e as listas do movimento em lote.
local rotors = {}
local awake = {}
local parts = {}
local poses = {}
local angle = 0
local sinceCheck = math.huge

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
local function childLike(parent, name)
	local wanted = string.lower(name)
	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end
	return nil
end

-- A pose de repouso entra como PIVÔ, não como CFrame: o pivô da malha sai do centro, e girar em
-- torno do centro faria a hélice bambear em vez de rodar no eixo.
local function register(item)
	local model = item.Parent
	if not (item:IsA("BasePart") and model and string.lower(model.Name) == FAN_NAME) then
		return
	end

	-- Hélice que saiu e voltou pelo streaming é peça NOVA, mas a pasta também reanuncia a que já
	-- está registrada; sem a conferência a mesma entraria duas vezes na lista do lote.
	for _, entry in ipairs(rotors) do
		if entry.part == item then
			return
		end
	end

	table.insert(rotors, {
		part = item,
		pivot = item:GetPivot(),
		offset = item.PivotOffset:Inverse(),
	})
end

local function collect(folder)
	for _, item in ipairs(folder:GetDescendants()) do
		if string.lower(item.Name) == string.lower(ROTOR_NAME) then
			register(item)
		end
	end
end

local function refresh()
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	table.clear(awake)
	table.clear(parts)
	table.clear(poses)

	for index = #rotors, 1, -1 do
		local entry = rotors[index]
		-- Hélice que o streaming levou sai da lista: a varredura é única, e a entrada órfã ficaria
		-- para sempre.
		if entry.part.Parent == nil then
			table.remove(rotors, index)
		elseif eye == nil or (entry.pivot.Position - eye).Magnitude <= ACTIVE_RADIUS then
			table.insert(awake, entry)
			table.insert(parts, entry.part)
		end
	end
end

local function step(delta)
	sinceCheck += delta
	if sinceCheck >= CHECK_INTERVAL then
		sinceCheck = 0
		refresh()
	end
	if #awake == 0 then
		return
	end

	angle = (angle + math.rad(SPIN_SPEED) * delta) % (2 * math.pi)
	local turn = CFrame.fromAxisAngle(SPIN_AXIS, angle)
	for index, entry in ipairs(awake) do
		poses[index] = entry.pivot * turn * entry.offset
	end
	Workspace:BulkMoveTo(parts, poses, Enum.BulkMoveMode.FireCFrameChanged)
end

function FanController.Start()
	local folder = Workspace
	for _, name in ipairs(FOLDER) do
		folder = childLike(folder, name) or folder:WaitForChild(name, FOLDER_WAIT)
		if not folder then
			warn("[Fan] workspace." .. table.concat(FOLDER, ".") .. " não encontrado.")
			return
		end
	end

	collect(folder)
	folder.DescendantAdded:Connect(function(item)
		if string.lower(item.Name) == string.lower(ROTOR_NAME) then
			register(item)
		end
	end)

	RunService.PostSimulation:Connect(step)
end

return FanController
