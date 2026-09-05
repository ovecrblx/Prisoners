-- Quem está no telefone de workspace.Siland_Home.interactive.Phone, e quem está ligando. O aparelho
-- é um só na sala, então o servidor guarda o dono da chamada e apaga o prompt enquanto ela dura; o
-- fone subindo ao rosto, o toque e a câmera são de cada cliente.
-- A chamada que ENTRA é sorteada aqui, uma por turno: mundo tem um estado só, e cliente sorteando
-- daria um telefone tocando por jogador.
-- Desligar é do cliente porque o gatilho é andar, que só ele vê no quadro do gesto — mas quem
-- escreve o estado é sempre daqui, e pedido de quem não atendeu não passa.
local PhoneService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))
local ShiftService = require(script.Parent.Parent:WaitForChild("Shift"):WaitForChild("ShiftService"))
local PhoneConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PhoneConfig"))

local rng = Random.new()

local model
local prompt
local user
local links = {}

local caller
-- Dois relógios, dois trincos: `ringToken` fecha a janela de 10s do toque, `shiftToken` cancela o
-- sorteio pendente quando o turno vira. Um só cancelaria o outro — quem discasse e desligasse no
-- meio do turno apagaria em silêncio o toque já sorteado para ele.
local ringToken = 0
local shiftToken = 0
local answerListeners = {}

-- Quem atendeu com o aparelho tocando. É por aqui que a task de atender sabe que foi cumprida: o
-- serviço dono do evento avisa, e quem decide o que isso conclui é o TaskService.
function PhoneService.OnAnswer(callback)
	table.insert(answerListeners, callback)
end

-- Posse da corda vai para quem atendeu: cliente simula o que possui, e é a tela dele que tem o fone
-- no rosto. Ancorado não muda de dono, então elo travado sai fora sem derrubar os outros.
local function ownCord(player)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and not child.Anchored
			and string.sub(child.Name, 1, #PhoneConfig.LinkPrefix) == PhoneConfig.LinkPrefix
		then
			local ok, err = pcall(function()
				if player then
					child:SetNetworkOwner(player)
				else
					child:SetNetworkOwnershipAuto()
				end
			end)
			if not ok then
				warn("[PhoneService] posse do cabo recusada em " .. child.Name .. ": " .. tostring(err))
			end
		end
	end
end

local function publish(player)
	user = player
	model:SetAttribute(PhoneConfig.UserAttribute, if player then player.UserId else 0)

	if prompt then
		prompt.Enabled = player == nil
	end
end

-- O toque e quem liga são dois atributos porque têm vidas diferentes: o toque morre no instante em
-- que alguém atende, e quem liga sobrevive à chamada inteira — é ele que diz de quem é a voz.
local function ring(who)
	ringToken += 1
	local mark = ringToken

	caller = who
	model:SetAttribute(PhoneConfig.CallerAttribute, who or "")
	model:SetAttribute(PhoneConfig.RingingAttribute, who ~= nil)

	if not who then
		return
	end

	-- Ninguém atendeu na janela: o telefone desiste e a linha volta a ser de saída.
	task.delay(PhoneConfig.RingDuration, function()
		if ringToken == mark and not user then
			ring(nil)
		end
	end)
end

-- Um sorteio por turno, e só com a linha livre: telefone tocando na mão de quem já está nele não
-- tem como ser atendido.
local function rollShift()
	shiftToken += 1
	if user or caller or rng:NextNumber() >= PhoneConfig.RingChance then
		return
	end

	local mark = shiftToken
	local delay = PhoneConfig.RingDelay
	task.delay(rng:NextNumber(delay.Min, delay.Max), function()
		if shiftToken == mark and not (user or caller) then
			ring(if rng:NextNumber() < PhoneConfig.ManagerChance then "Manager" else "Unknown")
		end
	end)
end

local function release(player)
	if user ~= player then
		return
	end

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)
	publish(nil)
	ring(nil)
	ownCord(nil)
end

local function answer(player)
	if user then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Atender com o aparelho tocando cumpre a task; tirar do gancho para discar não cumpre nada.
	-- O toque cala, mas `caller` fica: a voz do outro lado ainda vai tocar.
	local answered = model:GetAttribute(PhoneConfig.RingingAttribute) == true
	if answered then
		ringToken += 1
		model:SetAttribute(PhoneConfig.RingingAttribute, false)
	end

	publish(player)
	ownCord(player)

	if answered then
		for _, callback in ipairs(answerListeners) do
			task.spawn(callback, player, caller)
		end
	end

	table.insert(links, humanoid.Died:Connect(function()
		release(player)
	end))
	table.insert(links, player.CharacterRemoving:Connect(function()
		release(player)
	end))
end

function PhoneService.Init()
	Remotes.Event(PhoneConfig.HangUpRemote).OnServerEvent:Connect(release)

	Players.PlayerRemoving:Connect(release)
end

function PhoneService.Start()
	local folder = PhoneConfig.Folder(PhoneConfig.ModelWait)
	model = folder and folder:WaitForChild(PhoneConfig.ModelName, PhoneConfig.ModelWait)
	if not model then
		warn("[PhoneService] workspace." .. table.concat(PhoneConfig.Path, ".") .. "." .. PhoneConfig.ModelName .. " não encontrado.")
		return
	end

	local base = model:WaitForChild(PhoneConfig.BaseName, PhoneConfig.ModelWait)
	if not (base and base:IsA("BasePart")) then
		warn("[PhoneService] " .. model:GetFullName() .. " sem " .. PhoneConfig.BaseName .. "; sem prompt.")
		return
	end

	publish(nil)
	ring(nil)

	prompt = Instance.new("ProximityPrompt")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.ActionText = ""
	prompt.ObjectText = PhoneConfig.PromptTitle
	prompt.UIOffset = PhoneConfig.PromptOffset
	prompt.ClickablePrompt = PhoneConfig.PromptClickable
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PhoneConfig.PromptDistance
	prompt.Parent = base

	prompt.Triggered:Connect(answer)

	-- Só depois do Model resolvido: turno que vira durante o boot não tem onde escrever o toque.
	ShiftService.OnShift(rollShift)
	rollShift()
end

return PhoneService
