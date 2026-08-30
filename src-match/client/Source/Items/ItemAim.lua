-- Pontaria no corpo: as juntas configuradas giram para levar o item até onde a câmera olha, por cima
-- do que a animação faz.
-- Uma medição por quadro, no alto da cadeia: quanto falta entre o repouso e o alvo, lido no espaço
-- da parte que hospeda a junta mais alta — parte que nenhuma destas escritas move. Cada junta recebe
-- a sua fração dessa conta, fechada no mesmo quadro. Medir cada junta contra a parte física acima
-- dela parece dar no mesmo, mas a parte de cima chega por torque, atrasada: a junta de baixo via o
-- caminho inteiro, comandava demais e devolvia conforme a de cima andava — o braço ia e voltava a
-- cada virada, e comando acima de meia-volta ainda flipava para o lado oposto.
-- O repouso é lido uma vez, com as juntas na pose da animação (AimSettleTime), nunca da medição
-- corrente: reler o próprio efeito fecha um laço, e o braço treme.
-- As frações compõem de cima para baixo: cada junta da cadeia toma share vezes o que restou, e a
-- última, com share 1, fecha a conta. Share maior que 1 no meio passa do alvo de propósito e quem
-- está abaixo devolve o excesso. Junta fora do caminho até o item (Neck) é cosmética: gira share
-- vezes o resto medido no host dela, sem entrar na conta.
-- Só de quem mira: escrita de cliente em instância do servidor não replica, então os outros veem o
-- braço da animação. Réplica de outro jogador não tem câmera para ler, e nem tenta.
local ItemAim = {}

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local EPSILON = 1e-4
-- Acima disto fromAxisAngle equivale ao giro curto pelo outro lado, e o membro flipa.
local MAX_ANGLE = math.rad(170)

local bound = {}

local function jointParts(item)
	if item:IsA("Motor6D") then
		return item.Part0, item.Part1
	end
	if item:IsA("AnimationConstraint") then
		local a0 = item.Attachment0
		local a1 = item.Attachment1
		return a0 and a0.Parent, a1 and a1.Parent
	end
	return nil, nil
end

local function makeEntry(node, prop, host, child, share)
	return { node = node, prop = prop, base = node[prop], host = host, child = child, share = share }
end

-- A cadeia sai das próprias juntas: do item sobe-se de host em host até a raiz, e entra na conta
-- quem gira um trecho desse caminho, ordenada da raiz para fora. O rig deste projeto é de
-- AnimationConstraint, onde o equivalente do C0 é o CFrame do Attachment0 — o do lado do tronco;
-- Motor6D fica como saída para rig clássico.
local function resolve(character, joints, aimPart)
	local found = {}
	local hostOf = {}

	for _, item in ipairs(character:GetDescendants()) do
		local host, child = jointParts(item)
		if host and child then
			hostOf[child] = host
			local share = joints[item.Name]
			if share and not found[item.Name] then
				if item:IsA("Motor6D") then
					found[item.Name] = makeEntry(item, "C0", host, child, share)
				else
					found[item.Name] = makeEntry(item.Attachment0, "CFrame", host, child, share)
				end
			end
		end
	end

	local depth = {}
	local part, steps = aimPart, 0
	while part and not depth[part] do
		depth[part] = steps
		steps += 1
		part = hostOf[part]
	end

	local chain, others = {}, {}
	for name in pairs(joints) do
		local entry = found[name]
		if not entry then
			warn("[ItemAim] junta " .. name .. " ausente em " .. character.Name .. "; a mira a ignora")
		elseif depth[entry.child] then
			table.insert(chain, entry)
		else
			table.insert(others, entry)
		end
	end
	table.sort(chain, function(a, b)
		return depth[a.child] > depth[b.child]
	end)
	return chain, others
end

-- Para onde a mira quer ir: a direção da câmera, presa aos limites em torno do corpo. O yaw é medido
-- contra o corpo, então o teto dele é o quanto o item destorce do tronco antes de o corpo virar.
-- Atrás do personagem os dois lados valem, e a diferença de ângulo embrulha: +179 vira -179 e o alvo
-- salta de um ombro para o outro. O ramo escolhido é o mais perto do quadro anterior, então a mira
-- satura no lado por onde chegou em vez de dar a volta.
local function target(state, character)
	local camera = workspace.CurrentCamera
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (camera and root) then
		return nil
	end

	local config = state.config
	local pitch, cameraYaw = camera.CFrame:ToOrientation()
	local bodyYaw = select(2, root.CFrame:ToOrientation())
	local turn = (cameraYaw - bodyYaw + math.pi) % (2 * math.pi) - math.pi

	local previous = state.turn
	if previous then
		while turn - previous > math.pi do
			turn -= 2 * math.pi
		end
		while previous - turn > math.pi do
			turn += 2 * math.pi
		end
	end
	state.turn = math.clamp(turn, -math.pi, math.pi)

	pitch = math.clamp(pitch, math.rad(config.AimMinPitch), math.rad(config.AimMaxPitch))
	turn = math.clamp(turn, math.rad(config.AimMinYaw), math.rad(config.AimMaxYaw))
	return (CFrame.Angles(0, bodyYaw + turn, 0) * CFrame.Angles(pitch, 0, 0)).LookVector
end

local function settle(state, character)
	local chain, others = resolve(character, state.config.AimJoints, state.aimPart)
	if #chain == 0 then
		warn("[ItemAim] nenhuma junta de AimJoints fica entre o corpo e o item; a mira fica inerte")
		return false
	end
	state.chain = chain
	state.others = others
	state.topHost = chain[1].host
	state.rest = state.topHost.CFrame:VectorToObjectSpace(state.aimPart.CFrame.LookVector)
	return true
end

local function applyEntry(entry, axisWorld, angle)
	local host = entry.host
	if host.Parent == nil then
		return
	end
	if math.abs(angle) < EPSILON then
		entry.node[entry.prop] = entry.base
		return
	end
	angle = math.clamp(angle, -MAX_ANGLE, MAX_ANGLE)
	local axis = host.CFrame:VectorToObjectSpace(axisWorld)
	local pivot = entry.base.Position
	entry.node[entry.prop] = CFrame.new(pivot) * CFrame.fromAxisAngle(axis, angle) * (entry.base - pivot)
end

local function aim(state, character)
	local want = target(state, character)
	if not want then
		return
	end

	local restWorld = state.topHost.CFrame:VectorToWorldSpace(state.rest)
	local axis = restWorld:Cross(want)
	local theta = math.acos(math.clamp(restWorld.Unit:Dot(want.Unit), -1, 1))
	if axis.Magnitude < EPSILON or theta < EPSILON then
		for _, entry in ipairs(state.chain) do
			applyEntry(entry, axis, 0)
		end
		for _, entry in ipairs(state.others) do
			applyEntry(entry, axis, 0)
		end
		return
	end

	axis = axis.Unit
	local remaining = 1
	local afterChild = {}
	for _, entry in ipairs(state.chain) do
		local fraction = remaining * entry.share
		applyEntry(entry, axis, theta * fraction)
		remaining -= fraction
		afterChild[entry.child] = remaining
	end
	for _, entry in ipairs(state.others) do
		local left = afterChild[entry.host] or 1
		applyEntry(entry, axis, theta * left * entry.share)
	end
end

function ItemAim.Bind(character, config, aimPart)
	if bound[character] then
		return
	end
	bound[character] = { config = config, aimPart = aimPart, held = 0, rested = false }
end

function ItemAim.Release(character)
	local state = bound[character]
	if not state then
		return
	end
	bound[character] = nil
	for _, list in ipairs({ state.chain, state.others }) do
		if list then
			for _, entry in ipairs(list) do
				entry.node[entry.prop] = entry.base
			end
		end
	end
end

function ItemAim.Step(delta)
	for character, state in pairs(bound) do
		local aimPart = state.aimPart
		local stale = character.Parent == nil
			or character ~= player.Character
			or aimPart.Parent == nil
			or (state.rested and state.topHost.Parent == nil)
		if stale then
			ItemAim.Release(character)
		elseif not state.rested then
			-- Enquanto lê o repouso as juntas ficam na pose da animação: medir com correção aplicada
			-- mediria a própria correção. A cadeia também se resolve aqui, com o item já jointado.
			state.held += delta
			if state.held >= state.config.AimSettleTime then
				if settle(state, character) then
					state.rested = true
				else
					ItemAim.Release(character)
				end
			end
		else
			aim(state, character)
		end
	end
end

return ItemAim
