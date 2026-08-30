-- Catálogo das tasks e as regras do sorteio. Duas dimensões independentes, porque uma não decide a
-- outra: Kind diz se a task volta ao monte depois de feita, Scope diz quem pode recebê-la.
--
-- Kind:  Loop  volta ao monte quando o ciclo zera
--        Canon sai do monte para sempre na partida, mesmo depois do ciclo zerar
--        Event nunca entra no sorteio; quem a entrega é um evento do jogo
--
-- Scope: Global qualquer classe recebe
--        Class  só as classes listadas em Classes
--
-- O sorteio é por jogador, não por servidor: task de classe só faz sentido contra a classe de
-- alguém, então o monte e o histórico são de cada um.
-- Ciclo: sorteia entre as não feitas; quando acaba o que sortear, o histórico do ciclo zera e as
-- Loop voltam ao monte. As Canon feitas não voltam.
local TaskConfig = {}

TaskConfig.Kind = {
	Loop = "Loop",
	Canon = "Canon",
	Event = "Event",
}

TaskConfig.Scope = {
	Global = "Global",
	Class = "Class",
}

-- O que faz a task se dar por cumprida. Cada tipo é lido por um serviço: CollectItem é do
-- ItemService, que avisa quem pegou o quê.
TaskConfig.Trigger = {
	CollectItem = "CollectItem",
}

TaskConfig.DrawPerShift = 4 -- teto por turno; sorteia menos se não houver o que sortear

TaskConfig.StateRemote = "TaskState" -- servidor -> dono; sem argumento, cliente pede o retrato

-- Contorno de posição no alvo da task, montado no cliente e morto junto com o objeto.
TaskConfig.HighlightName = "TaskHighlight"
TaskConfig.HighlightFillColor = Color3.fromRGB(255, 214, 102)
TaskConfig.HighlightFillTransparency = 0.7
TaskConfig.HighlightOutlineColor = Color3.fromRGB(255, 240, 194)
TaskConfig.HighlightOutlineTransparency = 0
TaskConfig.HighlightDepthMode = Enum.HighlightDepthMode.AlwaysOnTop

-- Highlight.ItemId aponta o exemplar de coleta daquele item, que é quem o cliente contorna
-- enquanto a task estiver ativa.
TaskConfig.List = {
	{
		Id = "collect_flashlight",
		Kind = "Canon",
		Scope = "Global",
		Title = "Pegue a lanterna",
		Description = "Uma lanterna espera na delegacia. Serve o turno inteiro, e qualquer função "
			.. "pode carregá-la.",
		Trigger = { Type = "CollectItem", ItemId = "Flashlight" },
		Highlight = { ItemId = "Flashlight" },
	},
}

TaskConfig.ById = {}

for order, entry in ipairs(TaskConfig.List) do
	entry.Order = order
	TaskConfig.ById[entry.Id] = entry
end

function TaskConfig.Get(id)
	return TaskConfig.ById[id]
end

-- Entra no sorteio do turno? Event fica de fora por definição: ela chega por outro caminho.
function TaskConfig.IsDrawable(entry)
	return entry.Kind ~= TaskConfig.Kind.Event
end

-- Uma vez feita, a Canon não volta nem quando o ciclo zera.
function TaskConfig.IsPermanent(entry)
	return entry.Kind == TaskConfig.Kind.Canon
end

function TaskConfig.Allows(entry, classId)
	if entry.Scope ~= TaskConfig.Scope.Class then
		return true
	end
	if not (entry.Classes and classId) then
		return false
	end
	for _, allowed in ipairs(entry.Classes) do
		if allowed == classId then
			return true
		end
	end
	return false
end

return TaskConfig
