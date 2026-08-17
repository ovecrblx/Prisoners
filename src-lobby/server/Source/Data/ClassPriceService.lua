-- Publica o preço em Robux de cada classe. GetProductInfoAsync não atende DeveloperProduct
-- no cliente, então a consulta é feita aqui e o resultado vira atributo de uma pasta em
-- ReplicatedStorage: chave = Id da classe, valor = PriceInRobux.
local ClassPriceService = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))

local FOLDER_NAME = "ClassPrices"

-- Segundos entre tentativas quando a consulta falha, e teto de tentativas por classe.
local RETRY_DELAY = 5
local MAX_ATTEMPTS = 3

local folder

local function publish(entry)
	for attempt = 1, MAX_ATTEMPTS do
		local ok, info = pcall(
			MarketplaceService.GetProductInfoAsync,
			MarketplaceService,
			entry.ProductId,
			Enum.InfoType.Product
		)

		if ok and type(info) == "table" and info.PriceInRobux then
			folder:SetAttribute(entry.Id, info.PriceInRobux)
			return
		end

		if attempt < MAX_ATTEMPTS then
			task.wait(RETRY_DELAY)
		else
			warn(("[ClassPriceService] preço de %s (produto %d) não veio: %s"):format(entry.Id, entry.ProductId, tostring(info)))
		end
	end
end

function ClassPriceService.Init()
	folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = ReplicatedStorage
end

function ClassPriceService.Start()
	for _, entry in ipairs(ClassConfig.List) do
		if entry.ProductId and entry.ProductId > 0 then
			task.spawn(publish, entry)
		end
	end
end

return ClassPriceService
