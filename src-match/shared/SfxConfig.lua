-- Catálogo de efeitos sonoros do Match. Id é o asset; Volume o ganho; Speed o PlaybackSpeed, que é
-- o que faz a mesma gravação servir de tecla leve e de tecla pesada. Range só vale em som de mundo,
-- preso na peça — em som de UI a engine ignora.
-- Todos são grátis da Creator Store. `Loja` é a página, para trocar o Id ouvindo o candidato.
local SfxConfig = {
	-- Interface do monitor. A tecla física `Power` tem gravação própria: ela é a única que afunda no
	-- mundo, e o estalo das teclas de tela não dá o peso dela.
	UiHover = { Id = 88442833509532, Volume = 0.18, Speed = 1.6 },
	UiClick = { Id = 9119730203, Volume = 0.45, Speed = 1.15 },
	Power = { Id = 9083627113, Volume = 0.7 },

	-- Sentar e levantar, de qualquer corpo, por Model de assento. Preso na peça e de alcance curto:
	-- range de ruído de cadeira, não de evento de sala.
	-- Speed alto de propósito: sentar e levantar são quase instantâneos em NPC e jogador, e gravação
	-- no ritmo autorado ainda estaria tocando com o corpo já parado.
	Sit = { Id = 9117143754, Volume = 0.5, Speed = 2.89, Range = 25 },
	Stand = { Id = 9117143500, Volume = 0.5, Speed = 2.89, Range = 25 },

	-- Sofá do `Home`. HomeStand deveria ser HomeSit ao contrário, e a engine NÃO toca som invertido:
	-- PlaybackSpeed negativo é fixado em 0 (medido). Até subir um asset já invertido, os dois usam a
	-- mesma gravação, com o levantar mais lento e mais baixo para não soar idêntico ao sentar.
	HomeSit = { Id = 9120294836, Volume = 0.5, Speed = 2.89, Range = 25 },
	HomeStand = { Id = 9120294836, Volume = 0.4, Speed = 2.457, Range = 25 },

	-- O leito de chiado do posto: entra ao sentar e só sai ao levantar, mosaico ou tela expandida.
	-- Gravação própria, feita para emendar em laço — a dos estouros corta e denuncia a volta.
	-- Loja: create.roblox.com/store/asset/172906410
	ScreenNoise = { Id = 172906410, Volume = 0.05, Looped = true },

	-- Chiado avulso, por cima do leito: o estouro da troca de janela, e o da tela que cai.
	-- Loja: create.roblox.com/store/asset/372770465
	CamSwitch = { Id = 372770465, Volume = 0.042, Speed = 1.5 },
	Glitch = { Id = 372770465, Volume = 0.063, Speed = 0.8 },
	MonitorOn = { Id = 372770465, Volume = 0.07, Speed = 0.95 },

	-- Servo da lente. Nasce no clique da tecla e vive até ela soltar; sem `Looped`, toca a gravação
	-- inteira uma vez e cala, mesmo com a tecla ainda segurada.
	CamServo = { Id = 9118329067, Volume = 0.22, Speed = 1.1 },

	-- Mundo: preso na peça, então tem distância. Porta e volume vêm do Code-Egg, que já tem o par
	-- separado em abrir e fechar — os do catálogo traziam os dois movimentos no mesmo arquivo.
	DoorOpen = { Id = 18922530082, Volume = 0.5, Range = 40 },
	DoorClose = { Id = 18922533539, Volume = 0.5, Range = 40 },

	-- A porta dupla fecha com batida própria: ela abre por aproximação e fecha sozinha, e o estalo da
	-- porta comum não dá o peso das duas folhas encontrando.
	DualDoorClose = { Id = 9114603534, Volume = 0.5, Range = 40 },
	-- Dois eventos por acionamento, com gravação e lugar próprios. A alavanca é o estalo do gesto e
	-- sai da `Right Root`, onde o jogador interage; a cortina é o curso das barras e sai delas,
	-- esticada para durar o movimento inteiro.
	LeverUp = { Id = 104661469840733, Volume = 0.5, Range = 35 },
	LeverDown = { Id = 120822095725244, Volume = 0.5, Range = 35 },
	CurtainUp = { Id = 9114020474, Volume = 0.5, Range = 45 },
	CurtainDown = { Id = 9113423722, Volume = 0.5, Range = 45 },

	-- Ambiente da hélice, em laço preso nela: quem chega perto ouve, e o "perto" é a atenuação do
	-- próprio Sound. Loja: create.roblox.com/store/asset/124398148205753
	FanLoop = { Id = 124398148205753, Volume = 0.105, Range = 40, Looped = true },

	-- Prompt do cenário, no instante em que o jogador segura.
	Prompt = { Id = 9119730203, Volume = 0.35, Speed = 1.35 },
}

return SfxConfig
