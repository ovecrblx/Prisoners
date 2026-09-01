-- Pontaria do item: um IKControl puxa a mão de quem segura até um alvo no rumo do mouse, e o solver
-- do engine faz o braço. A cadeia vai do ChainRoot ao EndEffector, os dois inclusive; o item pendura
-- abaixo dela, então guarda a posição e o ângulo do config e não é tocado.
-- O alvo é uma Attachment própria, solta no mundo: só a direção vem do mouse, e a distância é a que
-- o efetor tinha em repouso, para o solver girar o braço em vez de esticá-lo atrás de uma parede.
-- Os limites de junta do rig ficam como vieram: o que segura a mira é o campo à frente do corpo, em
-- AimFieldDistance e AimFieldRadius, para o braço não ir atrás do ponteiro quando ele passa para as
-- costas.
-- Só de quem mira: instância criada no cliente não replica, então os outros veem o braço da
-- animação. Réplica de outro jogador não tem ponteiro para ler, e nem tenta.
local ItemAim = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local EPSILON = 1e-4
local CONTROL_NAME = "ItemAimControl"
local TARGET_NAME = "ItemAimTarget"
local ROOT_PART_NAME = "HumanoidRootPart"

local bound = {}

-- O corpo de quem mira não é alvo: o item pendura nele, e o raio bateria na própria lanterna.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

function ItemAim.Bind(character, config)
	if bound[character] or character ~= player.Character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local chainRoot = character:FindFirstChild(config.AimChainRoot)
	local effector = character:FindFirstChild(config.AimEndEffector)
	local anchor = character:FindFirstChild(config.AimOriginPart)
	if not (humanoid and chainRoot and effector and anchor) then
		warn("[ItemAim] " .. character.Name .. " sem Humanoid, sem cadeia, sem efetor ou sem âncora")
		return
	end

	-- O alvo é uma Attachment solta no mundo, movida a cada quadro. O Terrain é o dono estável dela:
	-- não anda e não morre com o personagem.
	local mark = Instance.new("Attachment")
	mark.Name = TARGET_NAME
	mark.Parent = workspace.Terrain

	local control = Instance.new("IKControl")
	control.Name = CONTROL_NAME
	control.Type = config.AimType
	control.ChainRoot = chainRoot
	control.EndEffector = effector
	control.Target = mark
	control.Weight = config.AimWeight
	control.SmoothTime = config.AimSmoothTime
	control.Parent = humanoid

	bound[character] = {
		config = config,
		control = control,
		mark = mark,
		anchor = anchor,
		reach = (effector.Position - anchor.Position).Magnitude,
	}
end

function ItemAim.Release(character)
	local state = bound[character]
	if not state then
		return
	end
	bound[character] = nil
	state.control:Destroy()
	state.mark:Destroy()
end

-- O campo de mira: um círculo a AimFieldDistance studs à frente do corpo, com AimFieldRadius de
-- raio. O rumo do mouse é levado até o plano desse círculo e, se cair fora, volta para a borda —
-- então a mira anda dentro de uma janela à frente do personagem, e nunca para as costas.
-- Medido em espaço de corpo, onde a frente é o -Z: virar o personagem leva a janela junto.
-- Rumo que aponta para trás não cruza o plano; nesse caso vale a borda do lado para onde ele
-- apontava, o que faz a mira saturar na lateral em vez de saltar de um lado para o outro.
-- O ângulo máximo sai dos dois números: atan(raio / distância). Aproximar o círculo ou aumentar o
-- raio abre a mira; afastar ou apertar o raio fecha.
local function clampToField(direction, root, distance, radius)
	local aimed = root.CFrame:VectorToObjectSpace(direction)
	local forward = -aimed.Z
	local planar = Vector2.new(aimed.X, aimed.Y)

	if forward > EPSILON then
		planar *= distance / forward
	elseif planar.Magnitude > EPSILON then
		planar = planar.Unit * radius
	else
		planar = Vector2.zero
	end

	if planar.Magnitude > radius then
		planar = planar.Unit * radius
	end
	return root.CFrame:VectorToWorldSpace(Vector3.new(planar.X, planar.Y, -distance).Unit)
end

-- O rumo do mouse, já preso ao campo da frente. Só a DIREÇÃO vem do mouse: a distância do alvo é a
-- que o efetor tinha em repouso, para o solver girar o braço em vez de esticá-lo atrás de uma parede.
local function aimDirection(state, character, root)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local location = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(location.X, location.Y)
	rayParams.FilterDescendantsInstances = { character }
	local range = state.config.MouseRange
	local hit = workspace:Raycast(ray.Origin, ray.Direction * range, rayParams)
	local point = if hit then hit.Position else ray.Origin + ray.Direction * range

	local reach = point - state.anchor.Position
	if reach.Magnitude < EPSILON then
		return nil
	end
	return clampToField(reach.Unit, root, state.config.AimFieldDistance, state.config.AimFieldRadius)
end

-- O alvo PERSEGUE o rumo do mouse, não cola nele: a cada quadro anda uma fração do que falta, e a
-- fração vem do tempo, não do quadro, então o passo é o mesmo a 30 ou a 240 fps. Colado, ele levava
-- ao solver todo tranco de ponteiro, e isso vira tremor de braço.
-- O que é guardado entre quadros é a DIREÇÃO no espaço do corpo, não o ponto no mundo: ponto no
-- mundo fica onde estava quando o personagem anda ou vira, e o braço vai atrás dele — para as costas
-- se a virada for grande. Em espaço de corpo, virar o personagem leva a mira junto, e o arrasto
-- corre entre dois rumos que já passaram pelo cone, então nunca sai dele no meio do caminho.
-- A âncora é peça que o solver NÃO move: medida de dentro da cadeia, o alvo andaria junto com o
-- braço que o persegue.
function ItemAim.Step(delta)
	for character, state in pairs(bound) do
		local root = character:FindFirstChild(ROOT_PART_NAME)
		local stale = character.Parent == nil
			or character ~= player.Character
			or root == nil
			or state.anchor.Parent == nil
			or state.control.Parent == nil
		if stale then
			ItemAim.Release(character)
		else
			local wanted = aimDirection(state, character, root)
			if wanted then
				local inBody = root.CFrame:VectorToObjectSpace(wanted)
				local follow = state.config.AimFollowTime
				local settled = state.aim
				if settled and follow > 0 then
					local blend = settled:Lerp(inBody, 1 - math.exp(-delta / follow))
					state.aim = if blend.Magnitude > EPSILON then blend.Unit else inBody
				else
					state.aim = inBody
				end
				local heading = root.CFrame:VectorToWorldSpace(state.aim)
				state.mark.WorldPosition = state.anchor.Position + heading * state.reach
			end
		end
	end
end

return ItemAim
