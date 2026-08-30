-- O que só o caderno sabe fazer com o próprio modelo: empilhar as páginas, abrir a capa e virar
-- folha. O clone, a junta com o corpo e a acomodação na mão são do ItemView — aqui entram os
-- ganchos que ele chama.
-- Capa e páginas giram por um NumberValue em graus, não pelo C1 direto: a meia-volta é de 180
-- exatos, onde a interpolação de rotação não tem lado definido.
local ManualView = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ItemView = require(script.Parent.Parent:WaitForChild("Items"):WaitForChild("ItemView"))
local ManualConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ManualConfig"))

ManualView.ItemId = "Manual"

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

-- Pose de caderno fechado em qualquer clone do template, o da mão e o parado na mesa: páginas
-- empilhadas, capa baixada.
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

local function setPage(view, index)
	for _, page in pairs(view.pages) do
		if page.tween then
			page.tween:Cancel()
		end
		local angle = if page.index < index then 0 else ManualConfig.StackAngle
		page.tween = TweenService:Create(page.proxy, ManualConfig.PageTween, { Value = angle })
		page.tween:Play()
	end
end

function ManualView.SetPage(character, index)
	local view = ItemView.Get(character, ManualView.ItemId)
	if view then
		setPage(view, index)
	end
end

function ManualView.Init()
	ItemView.Define(ManualView.ItemId, {
		config = ManualConfig,

		dress = function(view)
			view.pages, view.cover = ManualView.Dress(view.model, view.handle)
		end,

		pose = function(view, inHand)
			setCover(view, inHand)
			if not inHand then
				setPage(view, 1)
			end
		end,

		clear = function(view)
			if view.coverTween then
				view.coverTween:Cancel()
			end
			for _, page in pairs(view.pages) do
				if page.tween then
					page.tween:Cancel()
				end
			end
		end,
	})
end

return ManualView
