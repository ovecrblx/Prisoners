-- Boot do servidor. Varre ServerScriptService.Source, carrega todo ModuleScript,
-- e roda Init em TODOS antes de rodar Start em qualquer um — serviço que depende
-- de outro no Init encontra o outro já inicializado.
local ServerScriptService = game:GetService("ServerScriptService")

local Source = ServerScriptService:WaitForChild("Source")
local loadedServices = {}

local function LoadModules(folder)
	for _, item in ipairs(folder:GetChildren()) do
		if item:IsA("ModuleScript") then
			-- pcall isola a falha: um módulo quebrado não derruba o boot inteiro.
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

-- Sinal de saúde do boot: começa otimista; QUALQUER falha de Init/Start abaixo o derruba.
-- NÃO estanca o boot (os pcalls isolam as falhas); só expõe um atributo observável, já que
-- sem isto um serviço crítico podia falhar o Init e o servidor parecer "pronto" mesmo quebrado.
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
