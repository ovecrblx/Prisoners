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
local mainSpawn

local ActionEvent
local UpdateEvent
local RemotesFolder

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

	RemotesFolder = remotes

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
-- As peças funcionais vivem num sub-Model (Config.PadInnerModel), não soltas no pad: o resto é
-- decoração (Union, Beams, Zone). Buscar a partir do pad inteiro pegaria a Union primeiro.
local function findInner(model)
	if Config.PadInnerModel == "" then
		return model
	end
	return model:FindFirstChild(Config.PadInnerModel)
end

-- SEM fallback para "primeira BasePart". O pad tem várias (Union, Zone, spawn), e escolher a
-- errada liga o Touched numa peça decorativa — falha silenciosa, o pior tipo. Nome não bateu,
-- avisa e deixa o pad morto.
local function findGate(inner)
	local gate = inner and inner:FindFirstChild(Config.GatePartName)
	if gate and gate:IsA("BasePart") then
		return gate
	end
	return nil
end

-- Cartaz físico do pad. Cada campo é buscado com FindFirstChild e testado: indexação direta
-- derrubaria o Init inteiro se um campo sumisse da GUI. Faltando um, só aquele campo não
-- atualiza.
local function findSign(inner)
	local billboardPart = inner and inner:FindFirstChild(Config.BillboardPartName)
	local gui = billboardPart and billboardPart:FindFirstChild(Config.BillboardGuiName)
	local frame = gui and gui:FindFirstChild(Config.BillboardFrameName)
	if not frame then
		return nil
	end

	return {
		players = frame:FindFirstChild(Config.BillboardPlayersLabel),
		timer = frame:FindFirstChild(Config.BillboardTimerLabel),
	}
end

-- Lotação e contagem no cartaz. Fora da contagem o Timer volta a "0s" — lotação e tempo já
-- dizem o estado do pad, não há rótulo de status separado.
local function updateSign(index)
	local party = parties[index]
	local sign = party.sign
	if not sign then
		return
	end

	if sign.players then
		sign.players.Text = #party.members .. "/" .. Config.MaxPlayers
	end

	if sign.timer then
		sign.timer.Text = (party.status == "teleporting") and (party.timer .. "s") or "0s"
	end
end

local function broadcast(index, instruction)
	local party = parties[index]
	local count = #party.members

	updateSign(index)

	for _, member in ipairs(party.members) do
		local role = (member == party.leader) and "Leader" or "Member"
		UpdateEvent:FireClient(member, instruction, party.name, count, party.status, party.timer, role)
	end
end

-- Devolve o jogador ao spawn principal. Sem isto ele continua em pé no pad depois de sair, e o
-- próximo Touched do gate o readmite no mesmo instante — sair vira impossível.
local function sendToMainSpawn(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (root and mainSpawn) then
		return
	end
	root.CFrame = mainSpawn.CFrame + Vector3.new(0, Config.MainSpawnOffset, 0)
end

local function removeFromParty(player)
	local index = partyOfPlayer[player]
	if not index then
		return
	end

	local party = parties[index]
	local wasLeader = (party.leader == player)
	local wasTeleporting = (party.status == "teleporting")

	partyOfPlayer[player] = nil
	player:SetAttribute("IsReady", nil)

	for position, member in ipairs(party.members) do
		if member == player then
			table.remove(party.members, position)
			break
		end
	end

	UpdateEvent:FireClient(player, "Hide", party.name, 0, "waiting", 0, nil)
	sendToMainSpawn(player)

	if wasLeader then
		-- Líder saindo durante a contagem MATA a sequência: bumpar o seq faz a thread em voo
		-- abortar no próximo yield, senão ela teleportaria o snapshot montado antes da saída.
		if wasTeleporting then
			party.status = "waiting"
			party.timer = 0
			party.seq += 1
			party.reservedCode = nil
			party.reservedPrivateServerId = nil

			-- Limpa o pronto de TODOS, não só de quem saiu: a contagem morreu junto com o líder,
			-- e quem ficou marcado pronto entraria já pronto na PRÓXIMA contagem — que encurta
			-- para ReadyCountdown assim que todos estão prontos. Na prática, um Play seguinte
			-- teleportaria quase instantaneamente, sem ninguém ter confirmado nada.
			for _, member in ipairs(party.members) do
				member:SetAttribute("IsReady", nil)
			end
		end

		party.leader = party.members[1]
	end

	-- NÃO reabrir o gate durante o colchão. Se o último a sair flipasse o status para "waiting",
	-- o gate reabriria no meio da reciclagem, um jogador NOVO entraria no pad e o wipe o
	-- apagaria — vira fantasma: em pé no pad, com painel aberto, fora de party.members. A thread
	-- de reciclagem é a única dona da volta para "waiting".
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

	-- Personagem morto não entra. Sem esta guarda, partes de um corpo caído/ragdoll roçando o
	-- gate inscrevem o jogador — que reaparece no spawn logo depois, membro de uma party em que
	-- nunca pisou conscientemente.
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Debounce ANTES das outras checagens: Touched dispara dezenas de vezes por passo, e barrar
	-- cedo evita repetir o trabalho todo. Timestamp em vez de flag + task.delay — a versão com
	-- delay abre uma thread por toque, e numa tempestade de Touched isso é milhares de threads.
	local now = os.clock()
	local last = touchDebounce[player]
	if last and (now - last) < Config.TouchDebounce then
		return
	end
	touchDebounce[player] = now

	-- Só "waiting" admite entrada. "teleporting" barra quem chega no meio da contagem (o
	-- snapshot já foi prometido); "recycling" barra durante o colchão pós-teleporte.
	local party = parties[index]
	if party.status ~= "waiting" then
		return
	end

	if partyOfPlayer[player] or #party.members >= Config.MaxPlayers then
		return
	end

	table.insert(party.members, player)
	partyOfPlayer[player] = index

	if not party.leader then
		party.leader = player
	end

	-- Posicionar vem DEPOIS de inscrever, e é tolerante a falta da peça. Se um erro aqui
	-- abortasse a função, o jogador ficaria dentro de party.members com o cartaz e o painel
	-- desatualizados (o broadcast abaixo nunca rodaria). Sem a peça `spawn` ele só não é puxado;
	-- a party continua consistente.
	local spawnPart = party.spawnPart
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if spawnPart and root then
		root.CFrame = spawnPart.CFrame
	end

	broadcast(index, "Update")
end

-- Devolve a party a um estado jogável depois de uma sequência abortada.
--
-- `clearReady` distingue de quem foi a culpa:
--   true  -> a party mudou (cancelou, caiu abaixo do mínimo, líder saiu). O pronto de cada um
--            já não vale, porque a composição não é mais a mesma.
--   false -> falhou a INFRAESTRUTURA (ReserveServer, MemoryStore, teleporte). A party continua
--            igual e ninguém errou nada; zerar o pronto obrigaria todo mundo a reconfirmar por
--            causa de uma instabilidade da Roblox. Mantém, e o líder tenta de novo direto.
local function abortSequence(index, clearReady)
	local party = parties[index]
	party.status = "waiting"
	party.timer = 0
	party.reservedCode = nil
	party.reservedPrivateServerId = nil

	if clearReady then
		for _, member in ipairs(party.members) do
			member:SetAttribute("IsReady", nil)
		end
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
		-- Exige seq E status. O seq sozinho não basta: a party pode ter voltado a "waiting" por
		-- outro caminho dentro do colchão (o último membro saiu, por exemplo) e já ter recebido
		-- um jogador novo — que este wipe apagaria. O wipe é o fim DESTE ciclo, não um reset cego.
		if party.seq ~= mySeq or party.status ~= "recycling" then
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

		-- A party mudou (cancelada, ou caiu abaixo do mínimo): pronto de todos deixa de valer.
		if party.status ~= "teleporting" or #party.members < Config.MinPlayers then
			abortSequence(index, true)
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

		-- Pode ser falha de reserva OU party desfeita; não dá para separar aqui, então trata como
		-- mudança de composição (o caso mais perigoso de manter pronto obsoleto).
		if not intact then
			if party.seq == mySeq then
				abortSequence(index, true)
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
				abortSequence(index, false)
			end
			return
		end

		local teleported = MatchHandoff.Teleport(code, snapshot, payload, nil, function()
			return party.seq == mySeq
		end)

		-- Teleporte falhou de vez: infraestrutura, não a party. Mantém o pronto para o líder poder
		-- tentar de novo sem todo mundo reconfirmar.
		if not teleported then
			if party.seq == mySeq then
				abortSequence(index, false)
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
	elseif action == "Cancel" then
		-- Líder cancela a contagem inteira; membro só desmarca o próprio pronto.
		--
		-- Bumpar o seq é o que MATA a thread em voo: ela revalida o token no próximo yield e
		-- aborta. Só trocar o status não bastaria — a thread ainda estaria entre dois yields e
		-- poderia reservar servidor ou teleportar depois do cancelamento.
		if party.status ~= "teleporting" then
			return
		end

		if player == party.leader then
			party.seq += 1
			party.status = "waiting"
			party.timer = 0
			party.reservedCode = nil
			party.reservedPrivateServerId = nil

			for _, member in ipairs(party.members) do
				member:SetAttribute("IsReady", nil)
			end

			broadcast(index, "Update")
		else
			player:SetAttribute("IsReady", nil)
			broadcast(index, "Update")
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

	-- Publica a lotação como atributo do Remotes: o cliente lê daqui em vez de duplicar os
	-- números. Atributo replica sozinho, então não precisa de remote nem de handshake.
	RemotesFolder:SetAttribute("MinPlayers", Config.MinPlayers)
	RemotesFolder:SetAttribute("MaxPlayers", Config.MaxPlayers)

	mainSpawn = workspace:FindFirstChild(Config.MainSpawnName)
	if not mainSpawn then
		warn(string.format("[AreaTeleportService] workspace.%s não encontrado — quem sair da party fica em pé no pad.", Config.MainSpawnName))
	end

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
			sign = nil,
			spawnPart = nil,
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
			local inner = findInner(model)

			if not inner then
				warn(string.format("[AreaTeleportService] pad %s sem o sub-Model '%s'.", padName, Config.PadInnerModel))
			else
				parties[index].sign = findSign(inner)
				if not parties[index].sign then
					warn(string.format("[AreaTeleportService] pad %s sem cartaz (%s.%s.%s) — lotação e timer não aparecem.", padName, Config.BillboardPartName, Config.BillboardGuiName, Config.BillboardFrameName))
				end

				local spawnPart = inner:FindFirstChild(Config.SpawnPartName)
				if spawnPart and spawnPart:IsA("BasePart") then
					parties[index].spawnPart = spawnPart
				else
					warn(string.format("[AreaTeleportService] pad %s sem a BasePart '%s' — quem entrar não é posicionado.", padName, Config.SpawnPartName))
				end

				local gate = findGate(inner)
				if gate then
					gate.Touched:Connect(function(hit)
						onGateTouched(index, hit)
					end)
				else
					warn(string.format("[AreaTeleportService] pad %s sem a BasePart '%s' — pad inativo.", padName, Config.GatePartName))
				end
			end
		end

		-- Cartaz zerado no boot: sem isto ele fica com o texto autorado no Studio até o primeiro
		-- jogador pisar, mostrando lotação mentirosa num pad vazio.
		updateSign(index)
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
