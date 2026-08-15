-- Config do teleporte de áreas (lado Lobby). Único lugar com número mágico:
-- serviço nenhum abaixo hardcoda id, nome de pad ou tempo.
--
-- Vive em ReplicatedStorage.Shared porque o cliente também precisa de MinPlayers e
-- MaxPlayers para travar o botão Play antes de gastar um round-trip. Nada aqui é
-- segredo — PlaceId é público, e o servidor revalida tudo o que o cliente manda.
local TeleportConfig = {}

-- Place de destino (Prisoners-Match). ReserveServer falha em silêncio com id errado,
-- então AreaTeleportService checa isto no boot e recusa teleportar se estiver zerado.
TeleportConfig.MatchPlaceId = 77228731864152

-- === HANDOFF ===================================================================================
-- SortedMap do MemoryStore onde o lobby deposita o payload da partida. O Match lê a MESMA chave.
-- Trocar o nome aqui exige trocar em src-match/shared/TeleportConfig.lua — são árvores
-- independentes, não há import cruzado entre places.
TeleportConfig.MapName = "ActiveMatches"

-- TTL do payload. Só precisa cobrir o voo do teleporte; sobra vira lixo que expira sozinho.
TeleportConfig.PayloadTtl = 300

-- === PADS ======================================================================================
-- Cada pad é uma "área": um Model em workspace.<PadsFolder> chamado <PadPrefix><i>.
-- Dentro dele, a parte de toque é a chamada <GatePartName>; não achando, cai na primeira
-- BasePart do Model (pad improvisado no Studio ainda funciona).
TeleportConfig.PadsFolder = "Tp"
TeleportConfig.PadPrefix = "Party_"
TeleportConfig.PadCount = 3
TeleportConfig.GatePartName = "Gate"

-- === LOTAÇÃO ===================================================================================
TeleportConfig.MinPlayers = 1
TeleportConfig.MaxPlayers = 5

-- === TEMPOS ====================================================================================
TeleportConfig.Countdown = 30 -- contagem cheia após o Play
TeleportConfig.ReadyCountdown = 10 -- teto quando todos já estão prontos
TeleportConfig.AutoReadyAt = 3 -- marca todo mundo pronto faltando N segundos

-- Colchão pós-teleporte. Enquanto ele corre o pad fica FECHADO: os teleportados ainda estão
-- saindo do servidor, e quem pisasse agora entraria numa party que o wipe seguinte apaga.
TeleportConfig.RecycleWindow = 5

-- Debounce do toque no gate, por jogador. Sem isto um Touched dispara dezenas de vezes por passo.
TeleportConfig.TouchDebounce = 1

-- === RETRY =====================================================================================
-- ReserveServer e TeleportToPrivateServer falham por rate-limit e instabilidade de rede; ambos
-- com backoff linear (i segundos entre tentativas).
TeleportConfig.ReserveAttempts = 3
TeleportConfig.TeleportAttempts = 3

return TeleportConfig
