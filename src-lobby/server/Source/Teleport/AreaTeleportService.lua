-- Pads do lobby: juntam uma party e teleportam para o place do Match.
-- Estados da party: waiting | teleporting | recycling
-- Remotes em ReplicatedStorage.Remotes:
--   AreaTeleportAction  cliente -> servidor: Play | Cancel | Ready | Leave
--   AreaTeleportUpdate  servidor -> cliente: (instruction, padName, count, status, timer, role)
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

local function findInner(model)
	if Config.PadInnerModel == "" then
		return model
	end
	return model:FindFirstChild(Config.PadInnerModel)
end

local function findGate(inner)
	local gate = inner and inner:FindFirstChild(Config.GatePartName)
	if gate and gate:IsA("BasePart") then
		return gate
	end
	return nil
end

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
		if wasTeleporting then
			party.status = "waiting"
			party.timer = 0
			party.seq += 1
			party.reservedCode = nil
			party.reservedPrivateServerId = nil

			for _, member in ipairs(party.members) do
				member:SetAttribute("IsReady", nil)
			end
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

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local last = touchDebounce[player]
	if last and (now - last) < Config.TouchDebounce then
		return
	end
	touchDebounce[player] = now

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

	local spawnPart = party.spawnPart
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if spawnPart and root then
		root.CFrame = spawnPart.CFrame
	end

	broadcast(index, "Update")
end

-- clearReady: false quando a falha foi de infraestrutura e a party segue íntegra.
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

local function recycle(index, mySeq)
	local party = parties[index]

	party.status = "recycling"
	party.timer = 0
	broadcast(index, "Update")

	task.delay(Config.RecycleWindow, function()
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

-- Ponto de extensão. Só JSON: userdata não serializa e chave de dicionário tem que ser string.
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

	party.reservedCode = nil
	party.reservedPrivateServerId = nil
	task.spawn(function()
		local code, privateServerId = MatchHandoff.ReserveServerAsync()
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
			abortSequence(index, true)
			return
		end

		local code = party.reservedCode
		local privateServerId = party.reservedPrivateServerId
		if not (code and privateServerId) then
			code, privateServerId = MatchHandoff.ReserveServerAsync()
		end

		local intact = code
			and privateServerId
			and party.seq == mySeq
			and party.status == "teleporting"
			and party.leader
			and party.leader.Parent == Players
			and #party.members >= Config.MinPlayers

		if not intact then
			if party.seq == mySeq then
				abortSequence(index, true)
			end
			return
		end

		local snapshot = table.clone(party.members)
		local snapshotCount = #snapshot
		local leaderSnapshot = party.leader

		local payload = buildPayload(snapshot, leaderSnapshot)
		MatchHandoff.PublishPayload(privateServerId, payload)

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

		if not teleported then
			if party.seq == mySeq then
				abortSequence(index, false)
			end
			return
		end

		party.reservedCode = nil
		party.reservedPrivateServerId = nil

		if party.seq ~= mySeq then
			return
		end

		recycle(index, mySeq)
	end)
end

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

		updateSign(index)
	end

	enabled = true
end

function AreaTeleportService.Start()
	if not enabled then
		return
	end

	ActionEvent.OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(function(player)
		touchDebounce[player] = nil
		removeFromParty(player)
	end)
end

return AreaTeleportService
