-- Réplica local do caderno, uma por personagem: o dono monta a sua e monta também a dos outros
-- jogadores, a partir do template em ReplicatedStorage.Client. Nada disso existe no servidor,
-- então nenhuma junta, pose ou tween passa pela rede — o dono vê a resposta no mesmo quadro.
-- A pose sai do C0 do Motor6D que prende o Handle ao corpo. Na mão o C0 é amostrado enquanto a
-- animação de segurar levanta o braço e congela em HandSettleTime; dali o livro é rígido no
-- espaço da mão. Capa e páginas giram por um NumberValue em graus, não pelo C1 direto: a
-- meia-volta é de 180 exatos, onde a interpolação de rotação não tem lado definido.
-- Template e pose de livro fechado saem daqui para o exemplar da mesa também, por Template e Dress.
local ManualView = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ManualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ManualConfig"))

local TEMPLATE_TIMEOUT = 10 -- segundos esperando o template aparecer no boot
local WAIST_TIMEOUT = 5 -- segundos esperando a parte da cintura no personagem

local player = Players.LocalPlayer

local views = {}
local pending = {}
local template
local settleLink

local function poseC0(character, part0)
	if part0.Name ~= ManualConfig.HandPartName then
		local angles = ManualConfig.WaistAngles
		return CFrame.new(ManualConfig.WaistOffset)
			* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	end

	local baked = ManualConfig.HandC0Angles
	if ManualConfig.HandC0Offset and baked then
		return CFrame.new(ManualConfig.HandC0Offset)
			* CFrame.fromOrientation(math.rad(baked.X), math.rad(baked.Y), math.rad(baked.Z))
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local angles = ManualConfig.HandAngles
	local facing = CFrame.Angles(0, select(2, root.CFrame:ToOrientation()), 0)
	local wanted = facing
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	local place = CFrame.new((part0.CFrame * CFrame.new(ManualConfig.HandOffset)).Position) * wanted.Rotation
	return part0.CFrame:Inverse() * place
end

-- O NumberValue mora dentro do motor: morre junto com o Model, sem lista de limpeza própria.
local function angleProxy(motor, angle)
	local base = CFrame.new(motor.C1.Position)
	motor.C1 = base * CFrame.Angles(0, 0, math.rad(angle))
	local proxy = Instance.new("NumberValue")
	proxy.Name = motor.Name .. "Angle"
	proxy.Value = angle
	proxy.Changed:Connect(function(value)
		motor.C1 = base * CFrame.Angles(0, 0, math.rad(value))
	end)
	proxy.Parent = motor
	return proxy
end

local function readback(joint)
	local x, y, z = joint.C0:ToOrientation()
	warn(("[Manual] pose travada da mão\n"
		.. "ManualConfig.HandC0Offset = Vector3.new(%.4f, %.4f, %.4f)\n"
		.. "ManualConfig.HandC0Angles = Vector3.new(%.2f, %.2f, %.2f)"):format(
		joint.C0.Position.X, joint.C0.Position.Y, joint.C0.Position.Z,
		math.deg(x), math.deg(y), math.deg(z)))
end

local function settle(delta)
	for character, view in pairs(views) do
		if character.Parent == nil or view.model.Parent == nil then
			ManualView.Hide(character)
		elseif view.inHand and not view.handC0 then
			local part0 = view.joint.Part0
			local c0 = part0 and poseC0(character, part0)
			if c0 then
				view.joint.C0 = c0
				view.held += delta
				if view.held >= ManualConfig.HandSettleTime then
					view.handC0 = c0
					if ManualConfig.CalibrateHand and character == player.Character then
						readback(view.joint)
					end
				end
			end
		end
	end
end

local function setCover(view, open)
	if view.coverTween then
		view.coverTween:Cancel()
		view.coverTween = nil
	end
	if not view.cover then
		return
	end
	if not open then
		view.coverTween = TweenService:Create(view.cover, ManualConfig.CoverCloseTween, { Value = 0 })
		view.coverTween:Play()
		return
	end
	view.cover.Value = 0
	task.delay(ManualConfig.OpenDelay, function()
		if not view.inHand or view.model.Parent == nil then
			return
		end
		local info = ManualConfig.CoverOpenTween
		view.coverTween = TweenService:Create(view.cover, info, { Value = ManualConfig.CoverOpenAngle })
		view.coverTween:Play()
	end)
end

function ManualView.Template()
	return template
end

-- Pose de caderno fechado em qualquer clone do template, o da mão e o parado na mesa: páginas
-- empilhadas, capa baixada. Devolve os proxies de ângulo, que é por onde a virada anda.
function ManualView.Dress(model, handle)
	local pages = {}

	for index, pageName in ipairs(ManualConfig.PageOrder) do
		local part = model:FindFirstChild(pageName)
		local motor = handle:FindFirstChild(pageName .. "Motor")
		if part and part:IsA("BasePart") and motor and motor:IsA("Motor6D") then
			pages[pageName] = {
				index = index,
				part = part,
				proxy = angleProxy(motor, ManualConfig.StackAngle),
			}
		else
			warn("[Manual] página " .. pageName .. " ou motor ausente no template")
		end
	end

	-- A guarda é autorada invertida (geometria espelhada, SurfaceGuis com Face trocada): na pilha
	-- ela fica em rotação zero, não em StackAngle.
	local endMotor = handle:FindFirstChild(ManualConfig.EndpaperName .. "Motor")
	if endMotor and endMotor:IsA("Motor6D") then
		endMotor.C1 = CFrame.new(endMotor.C1.Position)
	end

	local cover
	local coverMotor = handle:FindFirstChild(ManualConfig.FrontCoverMotorName)
	if coverMotor and coverMotor:IsA("Motor6D") then
		cover = angleProxy(coverMotor, 0)
	end

	return pages, cover
end

local function build(character, waist)
	local model = template:Clone()
	model.Name = ManualConfig.ModelName
	local handle = model:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		model:Destroy()
		warn("[Manual] template sem Handle")
		return nil
	end

	local view = { model = model, handle = handle, inHand = false, held = 0 }
	view.pages, view.cover = ManualView.Dress(model, handle)

	local joint = Instance.new("Motor6D")
	joint.Name = ManualConfig.JointName
	joint.Part0 = waist
	joint.Part1 = handle
	joint.C1 = CFrame.identity
	joint.C0 = poseC0(character, waist)
	joint.Parent = handle

	view.joint = joint
	model.Parent = character
	return view
end

function ManualView.Get(character)
	return views[character]
end

function ManualView.Show(character)
	if views[character] then
		return views[character]
	end
	if not template then
		return nil
	end
	-- CharacterAdded chega antes das partes: esperar aqui deixa Show seguro de chamar de
	-- qualquer evento, e `pending` impede que dois avisos seguidos montem dois cadernos.
	if pending[character] then
		repeat
			task.wait()
		until not pending[character]
		return views[character]
	end

	pending[character] = true
	local waist = character:WaitForChild(ManualConfig.WaistPartName, WAIST_TIMEOUT)
	pending[character] = nil
	if character.Parent == nil then
		return nil
	end
	if not waist or not waist:IsA("BasePart") then
		warn("[Manual] " .. ManualConfig.WaistPartName .. " ausente em " .. character.Name)
		return nil
	end

	local view = build(character, waist)
	if not view then
		return nil
	end
	views[character] = view
	if not settleLink then
		settleLink = RunService.RenderStepped:Connect(settle)
	end
	return view
end

function ManualView.Hide(character)
	local view = views[character]
	if not view then
		return
	end
	views[character] = nil
	if view.coverTween then
		view.coverTween:Cancel()
	end
	for _, page in pairs(view.pages) do
		if page.tween then
			page.tween:Cancel()
		end
	end
	view.model:Destroy()
	if next(views) == nil and settleLink then
		settleLink:Disconnect()
		settleLink = nil
	end
end

function ManualView.SetPose(character, inHand)
	local view = views[character]
	if not view then
		return
	end
	local partName = if inHand then ManualConfig.HandPartName else ManualConfig.WaistPartName
	local part0 = character:FindFirstChild(partName)
	if not part0 or not part0:IsA("BasePart") then
		warn("[Manual] " .. partName .. " ausente em " .. character.Name)
		return
	end

	view.inHand = inHand
	view.held = 0
	view.handC0 = nil
	view.joint.Part0 = part0
	local c0 = poseC0(character, part0)
	if c0 then
		view.joint.C0 = c0
	end
	-- Com HandC0 preenchido a pose já é final: nada a amostrar, nada a acomodar.
	if inHand and ManualConfig.HandC0Offset and ManualConfig.HandC0Angles then
		view.handC0 = view.joint.C0
	end

	setCover(view, inHand)
	if not inHand then
		ManualView.SetPage(character, 1)
	end
end

function ManualView.SetPage(character, index)
	local view = views[character]
	if not view then
		return
	end
	for _, page in pairs(view.pages) do
		if page.tween then
			page.tween:Cancel()
		end
		local angle = if page.index < index then 0 else ManualConfig.StackAngle
		page.tween = TweenService:Create(page.proxy, ManualConfig.PageTween, { Value = angle })
		page.tween:Play()
	end
end

function ManualView.Init()
	local client = ReplicatedStorage:WaitForChild("Client", TEMPLATE_TIMEOUT)
	local folder = client and client:WaitForChild(ManualConfig.TemplateFolder, TEMPLATE_TIMEOUT)
	template = folder and folder:FindFirstChild(ManualConfig.ModelName)
	if not template then
		warn("[Manual] ReplicatedStorage.Client." .. ManualConfig.TemplateFolder .. "."
			.. ManualConfig.ModelName .. " ausente — ninguém desenha o caderno")
	end
end

return ManualView
