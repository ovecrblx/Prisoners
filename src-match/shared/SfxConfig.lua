-- Catálogo de efeitos sonoros do Match. Id é o asset; Volume o ganho; Speed o PlaybackSpeed, que é
-- o que faz a mesma gravação servir de tecla leve e de tecla pesada. Range só vale em som de mundo,
-- preso na peça — em som de UI a engine ignora. Region é o trecho do arquivo que toca, em s: serve
-- para pular silêncio de cabeça e para cortar o rabo. A chave sem ela toca a gravação inteira.
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

	-- Tecla de luz de parede: estalo seco, preso na peça e de alcance curto.
	SwitchOn = { Id = 130452431655432, Volume = 0.45, Range = 25 },
	SwitchOff = { Id = 12222170, Volume = 0.45, Range = 25 },

	-- Prompt do cenário, no instante em que o jogador segura.
	Prompt = { Id = 9119730203, Volume = 0.35, Speed = 1.35 },

	-- Lanterna: interruptor e a troca cintura/mão, presos no Handle. Tocam em toda réplica, a do dono
	-- e a dos outros, então quem passa perto ouve o clique de quem acendeu — sem nada a mais na rede.
	FlashlightOn = { Id = 116902184912832, Volume = 0.5, Range = 30 },
	FlashlightOff = { Id = 136626313475686, Volume = 0.5, Range = 30 },
	FlashlightEquip = { Id = 85940558580144, Volume = 0.5, Range = 25 },
	FlashlightStow = { Id = 104955812643358, Volume = 0.5, Range = 25 },

	-- Caderno: folha virando e a troca cintura/mão, presos no Handle. Só o dono vira página — os
	-- outros nem desenham isso; a troca eles veem, e ouvem.
	ManualPage = { Id = 128266063262896, Volume = 0.5, Range = 20 },
	ManualEquip = { Id = 7244308623, Volume = 0.5, Range = 25 },
	ManualStow = { Id = 7244593699, Volume = 0.5, Range = 25 },

	-- Coleta no cenário, uma chave por item. Sem peça, porque o exemplar some no mesmo quadro e
	-- levaria o som junto; e o som é só de quem pegou, como a coleta inteira.
	FlashlightPickup = { Id = 3834495137, Volume = 0.5 },
	ManualPickup = { Id = 2886410788, Volume = 0.5 },

	-- Telefone da sala. Tirar do gancho e devolver saem do fone, e todo cliente os toca: o aparelho
	-- sobe ao rosto na tela de todos. PhoneRing ainda não tem gatilho.
	-- Quase toda gravação do telefone abre com silêncio, e é ele que a Region corta: medido por
	-- PlaybackLoudness, o som entra em 0,115s no toque e 0,366s no pousar. PhonePick é a exceção,
	-- entra em 0,017s — e a região dele também é o RELÓGIO do tom de espera, que entra quando ele sai.
	-- O toque chama de longe, e por isso tem o maior Range do aparelho. Em laço porque telefone
	-- tocando não para sozinho: quem o corta é atender. Ainda sem gatilho, e sem Region medida.
	PhoneRing = { Id = 9117305259, Volume = 0.9, Range = 35, Looped = true },
	PhonePick = { Id = 9125716553, Volume = 0.9, Range = 25, Region = NumberRange.new(0, 0.4) },
	PhoneDrop = { Id = 9117155140, Volume = 0.9, Range = 25, Region = NumberRange.new(0.35, 1.6) },

	-- Aguardando discagem: entra quando o fone acaba de subir e morre na primeira tecla. Em laço,
	-- porque esperar não tem duração. PhoneReset é o número abandonado no meio, e a região dele é o
	-- relógio da volta do tom de espera.
	PhoneWaiting = { Id = 9119453203, Volume = 0.9, Range = 20, Region = NumberRange.new(0.2, 5.2), Looped = true },
	PhoneReset = { Id = 9113665420, Volume = 0.9, Range = 20, Region = NumberRange.new(0, 1) },

	-- Fala do outro lado, uma chave por número da lista telefônica e uma por quem liga de fora.
	-- Presa à chamada, não ao relógio: desligar corta, e gravação longa não esbarra no teto do
	-- Debris — a do desconhecido tem 41s, quatro vezes esse teto.
	PhoneManager = { Id = 9125987169, Volume = 0.9, Range = 20 },
	PhoneCallManager = { Id = 9119452434, Volume = 0.9, Range = 20 },
	PhoneCallUnknown = { Id = 9112853287, Volume = 0.9, Range = 20 },

	-- A chamada em curso: o tom de linha abre, e o chamando entra em laço até desligar. `Looped`
	-- respeita a Region (medido): o arquivo do chamando tem quatro rajadas espalhadas em 21s, e a
	-- região devolve só a primeira, repetindo a cada 3s.
	PhoneDialTone = { Id = 9119452434, Volume = 7, Range = 20, Region = NumberRange.new(0, 1.5) },
	PhoneVoice = { Id = 9117145120, Volume = 0.6, Range = 20, Region = NumberRange.new(0, 3), Looped = true },

	-- Uma gravação por tecla, de 1 a 9, cada uma com o próprio silêncio de cabeça — de 0,033s na 3 a
	-- 0,101s na 8. O aparelho não tem gravação de 0, * e #: a da tecla 1 serve de base, com a altura
	-- trocada para que nenhuma soe igual a ela nem entre si.
	PhoneKey1 = { Id = 9113742812, Volume = 1.2, Range = 15, Region = NumberRange.new(0.085, 1) },
	PhoneKey2 = { Id = 9113742939, Volume = 1.2, Range = 15, Region = NumberRange.new(0.07, 1) },
	PhoneKey3 = { Id = 9113742941, Volume = 1.2, Range = 15, Region = NumberRange.new(0.02, 1) },
	PhoneKey4 = { Id = 9113742948, Volume = 1.2, Range = 15, Region = NumberRange.new(0.055, 1) },
	PhoneKey5 = { Id = 9113742238, Volume = 1.2, Range = 15, Region = NumberRange.new(0.02, 1) },
	PhoneKey6 = { Id = 9113743074, Volume = 1.2, Range = 15, Region = NumberRange.new(0.055, 1) },
	PhoneKey7 = { Id = 9113743081, Volume = 1.2, Range = 15, Region = NumberRange.new(0.085, 1) },
	PhoneKey8 = { Id = 9113743258, Volume = 1.2, Range = 15, Region = NumberRange.new(0.085, 1) },
	PhoneKey9 = { Id = 9113743252, Volume = 1.2, Range = 15, Region = NumberRange.new(0.07, 1) },
	PhoneKey0 = { Id = 9113742812, Volume = 1.2, Speed = 0.82, Range = 15, Region = NumberRange.new(0.085, 1) },
	PhoneKeyStar = { Id = 9113742812, Volume = 1.2, Speed = 1.27, Range = 15, Region = NumberRange.new(0.085, 1) },
	PhoneKeyHash = { Id = 9113742812, Volume = 1.2, Speed = 0.66, Range = 15, Region = NumberRange.new(0.085, 1) },
}

return SfxConfig
