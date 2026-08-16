-- Faz o cartão acima da cabeça encarar a câmera, reescrevendo o C0 do weld por frame.
-- SurfaceGui não tem auto-facing. Roda local: a escrita não replica.
local OverheadCardController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))

local RADIUS_SQ = Config.FacingRadius * Config.FacingRadius

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

	if (cameraPosition - restPosition).Magnitude < 1e-3 then
		return
	end

	local target = CFrame.lookAt(restPosition, cameraPosition)
	weld.C0 = target:Inverse() * headCF * c1
end

function OverheadCardController.Start()
	RunService.RenderStepped:Connect(function()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		local cameraPosition = camera.CFrame.Position

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local accessory = character and character:FindFirstChild(Config.AccessoryName)
			local handle = accessory and accessory:FindFirstChild(Config.HandleName)
			local head = character and character:FindFirstChild("Head")

			if handle and head then
				local delta = handle.Position - cameraPosition
				if delta:Dot(delta) <= RADIUS_SQ then
					local weld = handle:FindFirstChild(Config.WeldName)
					if weld and weld:IsA("Weld") then
						faceCamera(weld, head, cameraPosition)
					end
				end
			end
		end
	end)
end

return OverheadCardController
