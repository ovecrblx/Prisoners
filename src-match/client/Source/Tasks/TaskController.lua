-- As tasks do turno, do lado do dono. Guarda a lista que o servidor manda e deriva dela o que é
-- visual: por ora o contorno no alvo das que pedem um. Como exibir a lista em si ainda não está
-- definido, nada aqui desenha GUI.
-- Quem cumpre a task não é este módulo, e nem o cliente: o servidor decide e reenvia a lista.
local TaskController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemPickup = require(script.Parent.Parent:WaitForChild("Items"):WaitForChild("ItemPickup"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemConfig = require(Shared:WaitForChild("ItemConfig"))
local TaskConfig = require(Shared:WaitForChild("TaskConfig"))

local tasks = {}

function TaskController.Active(taskId)
	for _, task in ipairs(tasks) do
		if task.Id == taskId then
			return not task.Done
		end
	end
	return false
end

function TaskController.List()
	return tasks
end

-- Contorno de todo item que alguma task ativa aponte. Varre a lista inteira e apaga o resto, para
-- que task cumprida ou trocada de turno apague o contorno sem ninguém precisar lembrar disso.
local function refreshHighlights()
	local wanted = {}
	for _, task in ipairs(tasks) do
		local entry = TaskConfig.Get(task.Id)
		local highlight = entry and entry.Highlight
		if highlight and highlight.ItemId and not task.Done then
			wanted[highlight.ItemId] = true
		end
	end

	for _, itemId in ipairs(ItemConfig.Order) do
		ItemPickup.Highlight(itemId, wanted[itemId] == true)
	end
end

function TaskController.Start()
	local remotes = ReplicatedStorage:WaitForChild(ItemConfig.RemotesFolderName)
	local stateRemote = remotes:WaitForChild(TaskConfig.StateRemote)

	stateRemote.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then
			return
		end
		tasks = payload
		refreshHighlights()
	end)

	-- Sem argumento o servidor devolve a lista do turno corrente.
	stateRemote:FireServer()
end

return TaskController
