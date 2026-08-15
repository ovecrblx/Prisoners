-- Config do handoff (lado Match). Espelho do src-lobby/shared/TeleportConfig.lua.
--
-- É DUPLICADO de propósito: os dois places têm árvores `shared` independentes, não existe
-- import cruzado. MapName tem que bater com o do lobby — divergiu, o Match busca uma chave
-- que ninguém escreveu e toda partida cai no fallback.
local TeleportConfig = {}

TeleportConfig.MapName = "ActiveMatches"

-- Busca do payload. O SetAsync do lobby acontece ANTES do teleporte, mas o MemoryStore é
-- eventualmente consistente: a primeira leitura pode vir vazia mesmo com a escrita aceita.
-- Por isso retry, não leitura única.
TeleportConfig.FetchRetries = 5
TeleportConfig.FetchRetryDelay = 1

return TeleportConfig
