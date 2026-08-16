-- Parâmetros do teleporte de áreas (Lobby).
-- MapName precisa ser igual ao de src-match/shared/TeleportConfig.lua.
local TeleportConfig = {}

TeleportConfig.MatchPlaceId = 77228731864152

TeleportConfig.MapName = "ActiveMatches"
TeleportConfig.PayloadTtl = 300 -- segundos

-- Pads: workspace.Tp.Party_N.Model.{gate, spawn, billboardPart/billboardGui/Frame/{Players,Timer}}
-- Nomes case-sensitive. PadInnerModel = "" para peças direto no pad.
TeleportConfig.PadsFolder = "Tp"
TeleportConfig.PadPrefix = "Party_"
TeleportConfig.PadCount = 3
TeleportConfig.PadInnerModel = "Model"
TeleportConfig.GatePartName = "gate"
TeleportConfig.SpawnPartName = "spawn"

TeleportConfig.BillboardPartName = "billboardPart"
TeleportConfig.BillboardGuiName = "billboardGui"
TeleportConfig.BillboardFrameName = "Frame"
TeleportConfig.BillboardPlayersLabel = "Players"
TeleportConfig.BillboardTimerLabel = "Timer"

TeleportConfig.MainSpawnName = "SpawnLocation"
TeleportConfig.MainSpawnOffset = 3

TeleportConfig.MinPlayers = 1
TeleportConfig.MaxPlayers = 5

-- Segundos
TeleportConfig.Countdown = 30
TeleportConfig.ReadyCountdown = 10 -- teto com todos prontos
TeleportConfig.AutoReadyAt = 3 -- marca todos prontos faltando N
TeleportConfig.RecycleWindow = 5 -- pad fechado após teleporte
TeleportConfig.TouchDebounce = 1

-- Backoff linear: i segundos entre tentativas.
TeleportConfig.ReserveAttempts = 3
TeleportConfig.TeleportAttempts = 3

return TeleportConfig
