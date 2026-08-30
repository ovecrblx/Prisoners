-- A mão esquerda e o que ela segura. Só um item por vez fica lá, e cada um traz a própria animação
-- de segurar: quem entra para a animação de quem sai antes de tocar a sua.
-- Quem entra guarda quem estava: sem isso os dois itens ficariam jointados na mesma LeftHand,
-- atravessados, e o modo de leitura do caderno disputaria a câmera com a lanterna acesa.
-- Em personagem de jogador a replicação de animação é cliente -> servidor, nunca o contrário,
-- então quem vê o braço subir nos outros é este track tocando no dono deles.
local ItemHold = {}

local Players = game:GetService("Players")

local player = Players.LocalPlayer

local entries = {}
local holder

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

return ItemHold
