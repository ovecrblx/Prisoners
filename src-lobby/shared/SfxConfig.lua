-- Catálogo de efeitos sonoros do Lobby. Id é o asset; Volume o ganho; Speed o PlaybackSpeed, que é
-- o que faz a mesma gravação servir de toque leve e de toque grave. Duplicado do Match de propósito:
-- os dois places não se importam, e a paleta de cada um é a sua.
-- Todos são grátis da Creator Store. `Loja` é a página, para trocar o Id ouvindo o candidato.
local SfxConfig = {
	-- Menu, cards de classe e o painel de party.
	-- Loja: create.roblox.com/store/asset/88442833509532
	UiHover = { Id = 88442833509532, Volume = 0.18, Speed = 1.6 },
	UiClick = { Id = 88442833509532, Volume = 0.45 },
	UiBack = { Id = 88442833509532, Volume = 0.4, Speed = 0.8 },

	-- Entrar e sair do pad: o par de sinos do elevador, subindo e descendo.
	-- Loja: create.roblox.com/store/asset/91728968749666
	PartyJoin = { Id = 91728968749666, Volume = 0.45 },
	PartyLeave = { Id = 82593634625537, Volume = 0.4 },
}

return SfxConfig
