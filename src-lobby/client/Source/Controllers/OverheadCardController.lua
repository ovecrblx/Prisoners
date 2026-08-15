-- Cartão acima da cabeça — LADO CLIENTE: faz o painel encarar a câmera.
--
-- O cartão usa SurfaceGui, não BillboardGui: mantém nitidez à distância (PixelsPerStud alto),
-- mas perde o auto-facing que o BillboardGui dava de graça. Este controller devolve o facing.
--
-- Mecanismo: o accessory é preso à Head por um Weld "AccessoryWeld" (Part0=Handle, Part1=Head),
-- convertido do RigidConstraint pelo servidor. A cada frame reescrevemos o C0 desse weld para
-- orientar o Handle na direção da câmera.
--
-- Roda LOCAL, por cliente. Escrita de propriedade no cliente não replica, e o servidor nunca
-- toca no C0 — então cada jogador orienta os cartões para a SUA câmera, sem custo de rede e sem
-- um cliente afetar a tela do outro.
local OverheadCardController = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("OverheadCardConfig"))

local RADIUS_SQ = Config.FacingRadius * Config.FacingRadius

-- C0 de descanso por weld — define a POSIÇÃO do cartão (acima da Head) e é capturado na primeira
-- passagem, antes de qualquer reescrita. Sem guardar o original, cada frame calcularia a pose a
-- partir da já rotacionada e o cartão iria derivando.
--
-- Chaves fracas: o weld some ao respawnar ou o jogador sair, e a entrada tem que poder ser
-- coletada junto. Com chave forte esta tabela cresceria por respawn até o fim da sessão.
local baseC0 = setmetatable({}, { __mode = "k" })

local function faceCamera(weld, head, cameraPosition)
	local base = baseC0[weld]
	if not base then
		base = weld.C0
		baseC0[weld] = base
	end

	local headCF = head.CFrame
	local c1 = weld.C1

	-- Posição de descanso do Handle, preservada: só a ORIENTAÇÃO muda. Recalcular a posição aqui
	-- faria o cartão escorregar da cabeça conforme a câmera gira.
	local restPosition = (headCF * c1 * base:Inverse()).Position

	-- Câmera praticamente em cima do cartão: lookAt com direção ~zero produz CFrame degenerado.
	if (cameraPosition - restPosition).Magnitude < 1e-3 then
		return
	end

	-- A face frontal do Handle (-Z, onde mora o SurfaceGui) aponta para a câmera. Resolve o C0
	-- que coloca o Handle (Part0) nesse CFrame, ancorado na Head (Part1): D*C0 == Head*C1.
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
				-- Distância AO QUADRADO: isto roda por jogador, por frame. Uma raiz quadrada por
				-- jogador por frame é gasto puro quando o único uso é comparar com um limite.
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
