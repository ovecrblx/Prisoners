-- Boot do cliente. Mesmo contrato do servidor: Init em todos, depois Start em todos.
-- Só registra ModuleScript que exporte Init ou Start.
local Source = script.Parent:WaitForChild("Source", 10)

if not Source then
	warn("[Boot] Source do cliente não apareceu em 10s")
	return
end

local loadedControllers = {}

local function LoadModules(folder)
	for _, item in ipairs(folder:GetChildren()) do
		if item:IsA("ModuleScript") then
			local success, result = pcall(require, item)

			if success and type(result) == "table" then
				if type(result.Start) == "function" or type(result.Init) == "function" then
					table.insert(loadedControllers, result)
				end
			elseif not success then
				warn("[Boot] falha ao carregar " .. item.Name .. ": " .. tostring(result))
			end
		elseif item:IsA("Folder") then
			LoadModules(item)
		end
	end
end

LoadModules(Source)

for _, controller in ipairs(loadedControllers) do
	if type(controller.Init) == "function" then
		pcall(controller.Init, controller)
	end
end

for _, controller in ipairs(loadedControllers) do
	if type(controller.Start) == "function" then
		task.spawn(function()
			pcall(controller.Start, controller)
		end)
	end
end
