-- A mão esquerda e o que ela segura. Só um item por vez fica lá, e cada um traz a própria animação
-- de segurar: quem entra para a animação de quem sai antes de tocar a sua.
-- Quem entra guarda quem estava: sem isso os dois itens ficariam jointados na mesma LeftHand,
-- atravessados, e o modo de leitura do caderno disputaria a câmera com a lanterna acesa.
-- Em personagem de jogador a replicação de animação é cliente -> servidor, nunca o contrário,
-- então quem vê o braço subir nos outros é este track tocando no dono deles.
-- Sentado a mão fica vazia: sentar tem animação própria e o item guarda sozinho, e enquanto o
-- jogador não levantar nenhum sai da cintura.
local ItemHold = {}

local Players = game:GetService("Players")

local HUMANOID_WAIT = 10 -- segundos esperando o Humanoid do personagem novo

local player = Players.LocalPlayer

local entries = {}
local holder
local seated = false
local seatLink
local seatHooks = {}

local function entryOf(itemId)
	local entry = entries[itemId]
	if not entry then
		entry = {}
		entries[itemId] = entry
	end
	return entry
end

function ItemHold.Bind(itemId, animationId, stow)
	local entry = entryOf(itemId)
	entry.animationId = animationId
	entry.stow = stow
end

-- Carregada ao equipar, não no primeiro uso: um track que só busca o asset no toggle chega depois
-- de a amostragem da mão já ter congelado o C0.
function ItemHold.Preload(itemId, character)
	local entry = entries[itemId]
	if not (entry and entry.animationId) then
		return nil
	end
	if entry.track and entry.character == character then
		return entry.track
	end
	entry.track = nil

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = entry.animationId
	local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
	if not ok then
		return nil
	end
	loaded.Priority = Enum.AnimationPriority.Action
	loaded.Looped = true
	entry.character = character
	entry.track = loaded
	return loaded
end

-- `holder` já é o novo quando o stow do anterior roda: o Release que esse stow dispara cai fora
-- sozinho, em vez de desfazer a posse que acabou de mudar. Por isso o track do anterior para aqui.
function ItemHold.Claim(itemId)
	if holder == itemId then
		return
	end
	local previous = holder and entries[holder]
	holder = itemId
	if previous then
		if previous.track then
			previous.track:Stop()
		end
		if previous.stow then
			previous.stow()
		end
	end

	local character = player.Character
	local track = character and ItemHold.Preload(itemId, character)
	if track then
		track:Play()
	end
end

function ItemHold.Release(itemId)
	if holder ~= itemId then
		return
	end
	holder = nil
	local entry = entries[itemId]
	if entry and entry.track then
		entry.track:Stop()
	end
end

-- Esvazia a mão pelo mesmo caminho da troca de item: quem devolve o item à cintura e avisa o
-- servidor é o stow do dono. `holder` cai antes, senão o Release que esse stow dispara desfaria uma
-- posse que já não existe.
function ItemHold.Stow()
	local entry = holder and entries[holder]
	holder = nil
	if not entry then
		return
	end
	if entry.track then
		entry.track:Stop()
	end
	if entry.stow then
		entry.stow()
	end
end

function ItemHold.Seated()
	return seated
end

-- Quem mais depende de estar sentado se pendura aqui, e recebe o estado de agora ao se pendurar: o
-- assento pode já estar ocupado quando o ouvinte chega.
function ItemHold.OnSeat(hook)
	table.insert(seatHooks, hook)
	hook(seated)
end

local function setSeated(active)
	seated = active
	if active then
		ItemHold.Stow()
	end
	for _, hook in ipairs(seatHooks) do
		hook(active)
	end
end

-- Humanoid.Seated e não o Occupant do assento: ele dispara no quadro do gesto, e o Occupant só muda
-- depois da volta do servidor — o item ficaria na mão durante a animação de sentar.
-- Uma conexão por vez: personagem novo traz Humanoid novo, e morrer sentado tem de zerar o estado.
local function watch(character)
	if seatLink then
		seatLink:Disconnect()
		seatLink = nil
	end

	local humanoid = character:WaitForChild("Humanoid", HUMANOID_WAIT)
	if not humanoid then
		warn("[ItemHold] personagem sem Humanoid; sentar não guarda o item")
		return
	end

	setSeated(humanoid.Sit)
	seatLink = humanoid.Seated:Connect(setSeated)
end

function ItemHold.Start()
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(watch)
end

return ItemHold
