-- Parâmetros do handoff (Match).
-- MapName precisa ser igual ao de src-lobby/shared/TeleportConfig.lua.
local TeleportConfig = {}

TeleportConfig.MapName = "ActiveMatches"

-- MemoryStore é eventualmente consistente: a primeira leitura pode vir vazia.
TeleportConfig.FetchRetries = 5
TeleportConfig.FetchRetryDelay = 1

return TeleportConfig
