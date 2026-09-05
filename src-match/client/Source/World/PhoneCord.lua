-- Cabo do telefone de workspace.Siland_Home.interactive.Phone, desenhado em cada cliente. Os elos
-- são ancorados pelo servidor e não têm mais física: aqui cada um vai à pose da fase corrente por
-- percurso, no espaço do Body, e a espiral é desenhada pelos SpringConstraint do place.
-- O laço só corre enquanto há percurso: chegando à pose, ele se solta e o cabo parado não custa
-- nada. Com streaming os elos vão e voltam como instâncias novas, então a lista é refeita por
-- evento em vez de ser resolvida uma vez só.
local PhoneCord = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CordConfig = require(Shared:WaitForChild("CordConfig"))
local PhoneConfig = require(Shared:WaitForChild("PhoneConfig"))

local SPIN = CFrame.fromOrientation(
	math.rad(CordConfig.LinkAngles.X),
	math.rad(CordConfig.LinkAngles.Y),
	math.rad(CordConfig.LinkAngles.Z)
)

local model
local body
local links = {}
local childLink
local moving
local phase = "Idle"

local function release()
	if moving then
		moving:Disconnect()
		moving = nil
	end
end

local function collect()
	table.clear(links)
	body = model and PhoneConfig.Child(model, PhoneConfig.BaseName)
	if not (body and body:IsA("BasePart")) then
		body = nil
		return
	end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #PhoneConfig.LinkPrefix) == PhoneConfig.LinkPrefix then
			local index = tonumber(string.match(child.Name, "%d+$"))
			if index then
				links[index] = child
			end
		end
	end
end

local function poseOf(index)
	local spot = CordConfig.Nodes(phase)[index]
	if not spot then
		return nil
	end
	return body.CFrame * CFrame.new(spot) * SPIN
end

local function step(delta)
	if not (body and body.Parent) then
		release()
		return
	end

	local alpha = 1 - math.exp(-CordConfig.Smoothing * delta)
	local settled = true

	for index, part in pairs(links) do
		local wanted = part.Parent and poseOf(index)
		if wanted then
			local now = part.CFrame
			if (now.Position - wanted.Position).Magnitude <= CordConfig.Settle then
				part.CFrame = wanted
			else
				part.CFrame = now:Lerp(wanted, alpha)
				settled = false
			end
		end
	end

	if settled then
		release()
	end
end

-- Encaixe sem percurso, para o instante em que o Model chega: a pose autorada no place é a da
-- calibragem, não a da fase corrente, e sem isto o cabo entra em cena deslizando.
local function place()
	for index, part in pairs(links) do
		local wanted = part.Parent and poseOf(index)
		if wanted then
			part.CFrame = wanted
		end
	end
end

local function drive()
	if body and not moving then
		moving = RunService.Heartbeat:Connect(step)
	end
end

function PhoneCord.Phase(name)
	if phase == name then
		return
	end
	phase = name
	drive()
end

function PhoneCord.Bind(target)
	PhoneCord.Drop()
	model = target
	collect()
	if body then
		place()
	end
	childLink = model.ChildAdded:Connect(function()
		collect()
		drive()
	end)
end

function PhoneCord.Drop()
	release()
	if childLink then
		childLink:Disconnect()
		childLink = nil
	end
	model = nil
	body = nil
	table.clear(links)
end

return PhoneCord
