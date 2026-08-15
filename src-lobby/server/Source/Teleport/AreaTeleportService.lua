-- Teleporte de áreas: os pads do lobby que juntam uma party e a mandam para o place do Match.
--
-- A party é FÍSICA: quem está em pé no pad está na party. Não há convite nem lista — entrar é
-- pisar, sair é pedir para sair (ou desconectar). O cliente só recebe contagem e estado para
-- desenhar a HUD; toda decisão é do servidor.
--
-- === O TOKEN DE SEQUÊNCIA ======================================================================
-- Toda a orquestração abaixo tem yields (contagem de 1 em 1s, reserva, SetAsync, teleporte). Em
-- cada um deles a party pode mudar embaixo da thread: o líder sai, alguém cancela, um Play novo
-- começa. Por isso cada sequência nasce com um `seq`, e TODA thread dela revalida
-- `party.seq == mySeq` depois de CADA yield, abortando calada se foi superada.
--
-- Sem esse token, uma contagem velha re-adere a uma sequência nova: timer contando em dobro,
-- teleporte duplicado, servidor reservado órfão.
local AreaTeleportService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TeleportConfig"))
local MatchHandoff = require(script.Parent:WaitForChild("MatchHandoff"))

local parties = {}
local touchDebounce = {}
local partyOfPlayer = {}
local enabled = false

local ActionEvent
local UpdateEvent

-- === REMOTES ===================================================================================
-- Criados via código, não à mão no Studio: instância esquecida no place vira erro de boot que
-- só aparece em produção, e o place não é versionado (é artefato).
local function ensureRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	ActionEvent = remotes:FindFirstChild("AreaTeleportAction")
	if not ActionEvent then
		ActionEvent = Instance.new("RemoteEvent")
		ActionEvent.Name = "AreaTeleportAction"
		ActionEvent.Parent = remotes
	end

	UpdateEvent = remotes:FindFirstChild("AreaTeleportUpdate")
	if not UpdateEvent then
		UpdateEvent = Instance.new("RemoteEvent")
		UpdateEvent.Name = "AreaTeleportUpdate"
		UpdateEvent.Parent = remotes
	end
end

-- === PADS ======================================================================================
-- A parte de toque preferida é a de nome Config.GatePartName; sem ela, a primeira BasePart do
-- Model serve. Pad sem BasePart nenhuma é ignorado com aviso — melhor um pad morto do que o
-- serviço inteiro caindo no boot.
local function findGate(model)
	local named = model:FindFirstChild(Config.GatePartName)
	if named and named:IsA("BasePart") then
		return named
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function broadcast(index, instruction)
	local party = parties[index]
	local count = #party.members

	for _, member in ipairs(party.members) do
		local role = (member == party.leader) and "Leader" or "Member"
		UpdateEvent:FireClient(member, instruction, party.name, count, party.status, party.timer, role)
	end
end

local function removeFromParty(player)
	local index = partyOfPlayer[player]
	if not index then
		return
	end

	local party = parties[index]
	partyOfPlayer[player] = nil
	player:SetAttribute("IsReady", nil)

	for position, member in ipairs(party.members) do
		if member == player then
			table.remove(party.members, position)
			break
		end
	end

	UpdateEvent:FireClient(player, "Hide", party.name, 0, "waiting", 0, nil)

	if party.leader == player then
		-- Líder saindo durante a contagem MATA a sequência: bumpar o seq faz a thread em voo
		-- abortar no próximo yield, senão ela teleportaria o snapshot montado antes da saída.
		if party.status == "teleporting" then
			party.status = "waiting"
			party.timer = 0
			party.seq += 1
			party.reservedCode = nil
			party.reservedPrivateServerId = nil
		end

		party.leader = party.members[1]
	end

	if #party.members == 0 and party.status ~= "recycling" then
		party.status = "waiting"
		party.timer = 0
	end

	broadcast(index, "Update")
end

local function onGateTouched(index, hit)
	local character = hit and hit.Parent
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	-- Só "waiting" admite entrada. "teleporting" barra quem chega no meio da contagem (o
	-- snapshot já foi prometido); "recycling" barra durante o colchão pós-teleporte.
	local party = parties[index]
	if party.status ~= "waiting" then
		return
	end

	if partyOfPlayer[player] or #party.members >= Config.MaxPlayers then
		return
	end

	if touchDebounce[player] then
		return
	end
	touchDebounce[player] = true
	task.delay(Config.TouchDebounce, function()
		touchDebounce[player] = nil
	end)

	table.insert(party.members, player)
	partyOfPlayer[player] = index

	if not party.leader then
		party.leader = player
	end

	broadcast(index, "Update")
end

-- Devolve a party a um estado jogável depois de uma sequência abortada.
local function abortSequence(index)
	local party = parties[index]
	party.status = "waiting"
	party.timer = 0
	party.reservedCode = nil
	party.reservedPrivateServerId = nil

	for _, member in ipairs(party.members) do
		member:SetAttribute("IsReady", nil)
	end

	broadcast(index, "Update")
end

-- Esvazia o pad depois de um teleporte bem-sucedido e reabre para novos jogadores.
local function recycle(index, mySeq)
	local party = parties[index]

	-- "recycling" mantém o gate fechado enquanto os teleportados saem do servidor.
	party.status = "recycling"
	party.timer = 0
	broadcast(index, "Update")

	task.delay(Config.RecycleWindow, function()
		-- Superada durante o colchão: a sequência nova é dona do estado agora.
		if party.seq ~= mySeq then
			return
		end

		for _, member in ipairs(party.members) do
			partyOfPlayer[member] = nil
			member:SetAttribute("IsReady", nil)
		end

		table.clear(party.members)
		party.leader = nil
		party.status = "waiting"
		broadcast(index, "Update")
	end)
end

local function everyoneReady(party)
	for _, member in ipairs(party.members) do
		if member ~= party.leader and not member:GetAttribute("IsReady") then
			return false
		end
	end
	return true
end

-- Monta o payload que o Match vai ler. É AQUI que a lógica do Prisoners entra: o que a partida
-- precisa saber sobre cada jogador (papel, loadout, cosmético) vira campo deste dicionário.
--
-- Só JSON: MemoryStore e TeleportData recusam userdata. Um Color3 ou Vector3 solto aqui faz o
-- SetAsync falhar em silêncio e a partida inteira cair no fallback. Serialize antes (Color3
-- vira :ToHex(), por exemplo). Chaves de UserId como STRING — dicionário do MemoryStore não
-- aceita chave numérica.
local function buildPayload(members, leader)
	local payload = {
		LeaderId = leader.UserId,
		MembersData = {},
	}

	for _, member in ipairs(members) do
		payload.MembersData[tostring(member.UserId)] = {
			DisplayName = member.DisplayName,
		}
	end

	return payload
end

local function startSequence(index)
	local party = parties[index]

	if party.status ~= "waiting" or #party.members < Config.MinPlayers then
		return
	end

	if Config.MatchPlaceId == 0 then
		warn("[AreaTeleportService] MatchPlaceId não configurado — Play ignorado.")
		return
	end

	party.status = "teleporting"
	party.timer = Config.Countdown
	party.seq += 1

	local mySeq = party.seq

	if party.leader then
		party.leader:SetAttribute("IsReady", true)
	end

	-- Reserva DURANTE a contagem, não depois: tira a latência do ReserveServer do caminho
	-- crítico, então o teleporte dispara assim que o timer zera.
	party.reservedCode = nil
	party.reservedPrivateServerId = nil
	task.spawn(function()
		local code, privateServerId = MatchHandoff.ReserveServer()
		if code and privateServerId and party.seq == mySeq and party.status == "teleporting" then
			party.reservedCode = code
			party.reservedPrivateServerId = privateServerId
		end
	end)

	broadcast(index, "Update")

	task.spawn(function()
		while party.timer > 0 and party.status == "teleporting" and party.seq == mySeq do
			if #party.members < Config.MinPlayers then
				break
			end

			-- Todos prontos encurta a espera. Vale para solo também (o líder já entra pronto),
			-- então quem joga sozinho não fica preso a contagem inteira.
			if everyoneReady(party) and party.timer > Config.ReadyCountdown then
				party.timer = Config.ReadyCountdown
			end

			if party.timer == Config.AutoReadyAt then
				for _, member in ipairs(party.members) do
					member:SetAttribute("IsReady", true)
				end
			end

			broadcast(index, "Update")
			task.wait(1)

			if party.status == "teleporting" and party.seq == mySeq then
				party.timer -= 1
			end
		end

		if party.seq ~= mySeq then
			return
		end

		if party.status ~= "teleporting" or #party.members < Config.MinPlayers then
			abortSequence(index)
			return
		end

		-- Reserva pode não ter chegado a tempo: tenta uma vez em linha antes de desistir.
		local code = party.reservedCode
		local privateServerId = party.reservedPrivateServerId
		if not (code and privateServerId) then
			code, privateServerId = MatchHandoff.ReserveServer()
		end

		-- Revalida TUDO depois do yield da reserva. Qualquer divergência aborta sem teleportar.
		local intact = code
			and privateServerId
			and party.seq == mySeq
			and party.status == "teleporting"
			and party.leader
			and party.leader.Parent == Players
			and #party.members >= Config.MinPlayers

		if not intact then
			if party.seq == mySeq then
				abortSequence(index)
			end
			return
		end

		-- SNAPSHOT congelado: a MESMA lista alimenta o payload e o teleporte, então o que a
		-- partida lê descreve exatamente quem foi teleportado.
		local snapshot = table.clone(party.members)
		local snapshotCount = #snapshot
		local leaderSnapshot = party.leader

		local payload = buildPayload(snapshot, leaderSnapshot)
		MatchHandoff.PublishPayload(privateServerId, payload)

		-- Revalida DE NOVO depois do yield do SetAsync, colado no teleporte: se a composição
		-- mudou, snapshot e payload já não descrevem a party viva. O SetAsync órfão expira só.
		local stable = party.seq == mySeq
			and party.status == "teleporting"
			and party.leader == leaderSnapshot
			and leaderSnapshot.Parent == Players
			and #party.members == snapshotCount

		if not stable then
			if party.seq == mySeq then
				abortSequence(index)
			end
			return
		end

		local teleported = MatchHandoff.Teleport(code, snapshot, payload, nil, function()
			return party.seq == mySeq
		end)

		if not teleported then
			if party.seq == mySeq then
				abortSequence(index)
			end
			return
		end

		party.reservedCode = nil
		party.reservedPrivateServerId = nil

		-- Cancelada durante o teleporte? O cancelador já ajustou o estado; sobrescrever com
		-- "recycling" deixaria o pad travado, não-joinável.
		if party.seq ~= mySeq then
			return
		end

		recycle(index, mySeq)
	end)
end

-- Toda ação do cliente é uma SUGESTÃO. O servidor decide a partir do seu próprio estado: em que
-- party o jogador está (partyOfPlayer), se ele lidera, se o status permite. O cliente não manda
-- índice de pad nem lista de membros — não há o que forjar.
local function onAction(player, action)
	if typeof(action) ~= "string" then
		return
	end

	local index = partyOfPlayer[player]
	if not index then
		return
	end

	local party = parties[index]

	if action == "Play" then
		if player == party.leader then
			startSequence(index)
		end
	elseif action == "Ready" then
		if party.status == "teleporting" then
			player:SetAttribute("IsReady", true)
			broadcast(index, "Update")
		end
	elseif action == "Leave" then
		removeFromParty(player)
	end
end

function AreaTeleportService.Init()
	ensureRemotes()

	if Config.MatchPlaceId == 0 then
		warn("[AreaTeleportService] MatchPlaceId = 0 em TeleportConfig — os pads sobem, mas o Play é recusado.")
	end

	local padsFolder = workspace:WaitForChild(Config.PadsFolder, 10)
	if not padsFolder then
		warn(string.format("[AreaTeleportService] workspace.%s não apareceu em 10s — teleporte de áreas desligado.", Config.PadsFolder))
		return
	end

	for index = 1, Config.PadCount do
		local padName = Config.PadPrefix .. index
		local model = padsFolder:FindFirstChild(padName)

		parties[index] = {
			name = padName,
			model = model,
			leader = nil,
			members = {},
			status = "waiting",
			timer = 0,
			seq = 0,
			reservedCode = nil,
			reservedPrivateServerId = nil,
		}

		if not model then
			warn(string.format("[AreaTeleportService] pad %s não encontrado em workspace.%s.", padName, Config.PadsFolder))
		else
			local gate = findGate(model)
			if gate then
				gate.Touched:Connect(function(hit)
					onGateTouched(index, hit)
				end)
			else
				warn(string.format("[AreaTeleportService] pad %s sem BasePart de toque.", padName))
			end
		end
	end

	enabled = true
end

function AreaTeleportService.Start()
	if not enabled then
		return
	end

	ActionEvent.OnServerEvent:Connect(onAction)

	-- Desconectar tem que limpar a party: sem isto o pad conta um fantasma para sempre e nunca
	-- volta a bater MaxPlayers nem esvazia.
	Players.PlayerRemoving:Connect(function(player)
		touchDebounce[player] = nil
		removeFromParty(player)
	end)
end

return AreaTeleportService
