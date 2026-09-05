-- Boot do cliente. Mesmo contrato do servidor: Init em todos, depois Start em todos.
-- Só registra ModuleScript que exporte Init ou Start. Falha é isolada por pcall e avisada com o
-- nome do módulo: controller que morre calado no boot é bug invisível.
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
					table.insert(loadedControllers, { name = item.Name, module = result })
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

for _, entry in ipairs(loadedControllers) do
	local controller = entry.module
	if type(controller.Init) == "function" then
		local success, err = pcall(controller.Init, controller)
		if not success then
			warn("[Boot] erro no Init de " .. entry.name .. ": " .. tostring(err))
		end
	end
end

for _, entry in ipairs(loadedControllers) do
	local controller = entry.module
	if type(controller.Start) == "function" then
		task.spawn(function()
			local success, err = pcall(controller.Start, controller)
			if not success then
				warn("[Boot] erro no Start de " .. entry.name .. ": " .. tostring(err))
			end
		end)
	end
end
