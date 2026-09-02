-- Compra, equipa e desequipa classe. O cliente só pede: preço, saldo e posse são conferidos
-- aqui, e o resultado volta pelos atributos que o PlayerData publica.
-- Remote em ReplicatedStorage.Remotes.ClassAction: (action, classId).
local ClassService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Remotes = require(script.Parent.Parent:WaitForChild("Util"):WaitForChild("Remotes"))

local EVENT_NAME = "ClassAction"

-- Segundos entre ações aceitas por jogador.
local DEBOUNCE = 0.3

local ActionEvent
local lastAction = setmetatable({}, { __mode = "k" })

-- Compra equipa se o jogador ainda estava na classe padrão: ela é o preenchimento de quem não
-- escolheu, e comprar é escolher. Quem já tinha trocado para outra fica com a dele.
local function buy(player, entry)
	if PlayerData.OwnsClass(player, entry.Id) then
		return
	end
	if not PlayerData.SpendDima(player, entry.Price) then
		return
	end

	PlayerData.AddClass(player, entry.Id)

	local equipped = PlayerData.GetEquippedClass(player)
	if equipped == "" or equipped == ClassConfig.DefaultId then
		PlayerData.SetEquippedClass(player, entry.Id)
	end

	PlayerData.Flush(player)
end

local function onAction(player, action, classId)
	if type(action) ~= "string" then
		return
	end

	local now = os.clock()
	if now - (lastAction[player] or 0) < DEBOUNCE then
		return
	end
	lastAction[player] = now

	-- Desequipar volta para a classe padrão, não para vazio: profissão é requisito do Tp, e ninguém
	-- pode ficar sem uma. Sem gravação: equipar é escolha barata, e o auto-save do ProfileStore mais
	-- o EndSession já a levam — gravar por clique põe um UpdateAsync a cada 0.3s no orçamento do
	-- servidor inteiro. Compra continua gravando na hora, porque ali houve cobrança.
	if action == "Unequip" then
		PlayerData.SetEquippedClass(player, ClassConfig.DefaultId)
		return
	end

	local entry = type(classId) == "string" and ClassConfig.Get(classId)
	if not entry then
		return
	end

	if action == "Buy" then
		buy(player, entry)
	elseif action == "Equip" then
		PlayerData.SetEquippedClass(player, entry.Id)
	end
end

function ClassService.Init()
	ActionEvent = Remotes.Event(EVENT_NAME)
end

function ClassService.Start()
	ActionEvent.OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
	end)
end

return ClassService
