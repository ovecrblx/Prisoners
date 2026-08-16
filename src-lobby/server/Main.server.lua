-- Boot do servidor. Carrega ServerScriptService.Source e roda Init em todos antes de Start em
-- qualquer um. Start roda em task.spawn, então pode render.
-- Falha isolada por pcall; derruba o atributo ServerScriptService.BootHealthy.
local ServerScriptService = game:GetService("ServerScriptService")

local Source = ServerScriptService:WaitForChild("Source")
local loadedServices = {}

local function LoadModules(folder)
	for _, item in ipairs(folder:GetChildren()) do
		if item:IsA("ModuleScript") then
			local success, result = pcall(require, item)

			if success then
				if type(result) == "table" then
					table.insert(loadedServices, result)
				end
			else
				warn("[Boot] falha ao carregar " .. item.Name .. ": " .. tostring(result))
			end
		elseif item:IsA("Folder") then
			LoadModules(item)
		end
	end
end

LoadModules(Source)

ServerScriptService:SetAttribute("BootHealthy", true)

for _, service in ipairs(loadedServices) do
	if type(service.Init) == "function" then
		local success, err = pcall(service.Init, service)
		if not success then
			ServerScriptService:SetAttribute("BootHealthy", false)
			warn("[Boot] erro no Init: " .. tostring(err))
		end
	end
end

for _, service in ipairs(loadedServices) do
	if type(service.Start) == "function" then
		task.spawn(function()
			local success, err = pcall(service.Start, service)
			if not success then
				ServerScriptService:SetAttribute("BootHealthy", false)
				warn("[Boot] erro no Start: " .. tostring(err))
			end
		end)
	end
end
