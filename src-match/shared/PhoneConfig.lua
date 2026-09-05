-- Contrato do telefone de workspace.Siland_Home.interactive.Phone, lido pelo servidor e pelo
-- cliente. O servidor publica só quem atendeu; levar o fone ao rosto, a primeira pessoa e o
-- cancelamento ao sair do lugar são do cliente.
local PhoneConfig = {}

-- Estrutura esperada no place. O prompt mora na base, que é a peça com CanQuery ligado; o fone é a
-- peça que sobe ao rosto, e o que estiver soldado nela vai junto.
PhoneConfig.Path = { "Siland_Home", "interactive" }
PhoneConfig.ModelName = "Phone"
PhoneConfig.BaseName = "Body"
PhoneConfig.HandsetName = "Head"
PhoneConfig.FacePartName = "Head" -- parte do corpo que serve de referência

-- Teclado e visor. Cada tecla do teclado é uma peça cujo NOME é o rótulo dela, com a própria
-- SurfaceGui e o TextButton autorados no place; o visor é uma peça com um só TextButton.
PhoneConfig.PadName = "Control"
PhoneConfig.ScreenName = "Screen"

-- Estado publicado pelo servidor: UserId de quem está no aparelho, 0 livre. Atributo, não remote:
-- quem entra no meio da partida já recebe o retrato junto com o Model.
PhoneConfig.UserAttribute = "User"

-- Chamada que ENTRA, publicada do mesmo jeito: se está tocando, e quem está do outro lado. O toque
-- é de mundo e todo cliente o desenha; o `Caller` sobrevive ao atender, porque é ele que diz de
-- quem é a voz e o que o visor mostra. Vazio quando a linha é de saída.
PhoneConfig.RingingAttribute = "Ringing"
PhoneConfig.CallerAttribute = "Caller"

-- Cliente -> servidor, sem argumento: desliga. Atender é só pelo prompt, e quem decide é o servidor.
PhoneConfig.HangUpRemote = "PhoneHangUp"

-- Style Custom: quem desenha é o PromptDisplay do cliente. Distância curta porque o aparelho é de
-- mesa e o balcão tem outras coisas a poucos studs.
PhoneConfig.PromptDistance = 8
PhoneConfig.PromptOffset = Vector2.new(0, 40)
PhoneConfig.PromptClickable = false
PhoneConfig.PromptTitle = "Phone"

-- Model do assento do posto, dentro da pasta de assentos. Atender senta, como no monitor: o
-- enquadramento é fixo em cima do teclado, e de pé o jogador sai dele andando sem querer.
PhoneConfig.SeatName = "Sec_Seat_1"

-- Pose do fone, no espaço da CÂMERA de quem atende — para quem assiste, no da cabeça dele. Offset em
-- studs, com X à direita, Y para cima e Z para trás: Z negativo é à frente da vista. Ângulos em
-- graus, ordem Y-X-Z igual ao campo Orientation do Studio, não a de CFrame.Angles. Preso à câmera, o
-- fone acompanha o giro horizontal e o vertical, e fica parado na tela de quem está na linha.
PhoneConfig.HandsetOffset = Vector3.new(-0.95, 0.09, -1.3)
PhoneConfig.HandsetAngles = Vector3.new(60, 45, 180)

-- Percurso do fone até o rosto, em 1/s. Não é enfeite: o cabo é uma corrente de RopeConstraint
-- presa nele, e ponta ancorada que salta dá tranco na corda. Na volta o salto é seguro — rope só
-- puxa ao separar, e voltar ao gancho afrouxa.
PhoneConfig.HandsetSmoothing = 8

-- Prefixo dos elos soltos do cabo. Quem está na linha simula a corda: o fone só sobe ao rosto na
-- tela de cada cliente, e quem não simula contra o próprio fone veria o cabo ignorando o aparelho.
PhoneConfig.LinkPrefix = "Cord_Link"

-- Vista de quem atende, solta no mundo: posição em studs e ângulos em graus, ordem Y-X-Z igual ao
-- campo Orientation do Studio. Nasce em cima do teclado olhando para baixo — X é o pitch, e -90 é a
-- vertical. Não segue o jogador: é enquadramento fixo, e o telefone não anda.
-- Smoothing em 1/s, só o tempo de chegar lá: maior endurece até virar corte seco.
-- Enquanto a vista é do telefone o CameraLimit sai da frente sozinho, porque ele só age em Custom.
PhoneConfig.CameraPosition = Vector3.new(-2.8, 6.3, -38.7)
PhoneConfig.CameraAngles = Vector3.new(-65, 90, 0)
PhoneConfig.CameraSmoothing = 12

-- Cancela a chamada: studs/s de caminhada que já contam como sair do lugar. Pulo cancela sempre.
-- SeatWait são os s de graça até chegar à cadeira — dentro deles andar não cancela, senão o passo
-- em direção ao assento desligaria a chamada que acabou de começar.
PhoneConfig.CancelSpeed = 0.1
PhoneConfig.SeatWait = 12

-- Chave de Sfx por rótulo de tecla. Tecla fora daqui não soa e não digita; só as de dígito entram
-- no número.
PhoneConfig.KeySounds = {
	["0"] = "PhoneKey0",
	["1"] = "PhoneKey1",
	["2"] = "PhoneKey2",
	["3"] = "PhoneKey3",
	["4"] = "PhoneKey4",
	["5"] = "PhoneKey5",
	["6"] = "PhoneKey6",
	["7"] = "PhoneKey7",
	["8"] = "PhoneKey8",
	["9"] = "PhoneKey9",
	["*"] = "PhoneKeyStar",
	["#"] = "PhoneKeyHash",
}

-- studs que a tecla afunda pela face de cima, e s de cada perna do curso — o retorno é a mesma
-- perna ao contrário.
PhoneConfig.KeyDepth = 0.008
PhoneConfig.KeyTravel = 0.07

-- Visor. `DateText` é o cartão de abertura e `DateHold` os s que ele fica antes do campo. O campo
-- tem `Digits` casas: as vazias são `SlotChar`, e a próxima a receber é `CaretChar`.
PhoneConfig.DateText = "September 1, 2006"
PhoneConfig.DateHold = 2.2
PhoneConfig.Digits = 6
PhoneConfig.SlotChar = "*"
PhoneConfig.CaretChar = "_"

-- Piscada do cursor, em s por perna e sorteada em cada uma: tela velha não pisca em compasso.
PhoneConfig.CaretBlink = NumberRange.new(0.22, 0.52)

-- s parado com número pela metade antes do aparelho desistir. Conta da ÚLTIMA tecla, não da
-- primeira: quem digita devagar mas sem parar chega ao fim. Campo vazio não expira.
PhoneConfig.EntryTimeout = 3

-- Número cheio: quantas piscadas do visor inteiro confirmam, e os s de cada perna.
PhoneConfig.ConfirmBlinks = 3
PhoneConfig.ConfirmBlink = 0.14

-- Chamada em curso: o rótulo, quantos pontos ele acumula antes de voltar a um, os s de cada um, e
-- os s que ela dura antes do veredito.
PhoneConfig.CallingText = "calling"
PhoneConfig.CallingDots = 3
PhoneConfig.CallingStep = 0.45
PhoneConfig.CallingHold = 4

-- Lista telefônica: os números que existem de verdade. A chave é o que foi discado, com `Digits`
-- casas; `Title` é o que o visor mostra ao atender, e `Sound` a chave de Sfx da fala do outro lado.
-- O que não estiver aqui cai em `UnknownText`, que fica os s de `UnknownHold` e devolve o campo
-- vazio para nova tentativa.
PhoneConfig.Directory = {
	["800800"] = { Title = "Manager", Sound = "PhoneManager" },
}

PhoneConfig.UnknownText = "Unknown..."
PhoneConfig.UnknownHold = 2.5

-- Teto em s da espera pela gravação acabar. Quem normalmente avisa é o `Ended` do Sound; isto só
-- cobre o asset que não carrega, para a linha não ficar presa esperando um fim que não vem.
PhoneConfig.SpeechCap = 60

-- Quem liga de fora. A chave é o que o servidor publica em `CallerAttribute`; `Title` é o que o
-- visor mostra ao atender, e `Sound` a chave de Sfx da voz.
PhoneConfig.Callers = {
	Manager = { Title = "Manager", Sound = "PhoneCallManager" },
	Unknown = { Title = "Unknown", Sound = "PhoneCallUnknown" },
}

-- Sorteio do turno, no servidor: chance de o telefone tocar, e chance de ser o Manager quando toca.
PhoneConfig.RingChance = 0.5
PhoneConfig.ManagerChance = 0.5

-- s dentro do turno até a chamada cair. Turno tem ShiftConfig.Duration s, e a janela fica longe das
-- duas pontas: tocar no primeiro segundo entrega o sorteio, e tocar no último não dá tempo de andar.
PhoneConfig.RingDelay = NumberRange.new(15, 120)

-- s que o aparelho toca antes de desistir. Janela FECHADA: o SFX do toque corre dentro dela e é
-- cortado quando ela vence, não somado a ela.
PhoneConfig.RingDuration = 10

-- s de espera pelo Model e pelas peças dele. Com streaming o Model chega antes das peças, e pode
-- ir e voltar: nada aqui é resolvido uma vez só e guardado para a partida inteira.
PhoneConfig.ModelWait = 20

-- O cenário é publicado à mão e a caixa do nome não tem cobertura de teste.
function PhoneConfig.Child(parent, name)
	local wanted = string.lower(name)

	for _, child in ipairs(parent:GetChildren()) do
		if string.lower(child.Name) == wanted then
			return child
		end
	end

	return nil
end

function PhoneConfig.Folder(timeout)
	local node = workspace

	for _, name in ipairs(PhoneConfig.Path) do
		node = PhoneConfig.Child(node, name) or node:WaitForChild(name, timeout)
		if not node then
			return nil
		end
	end

	return node
end

function PhoneConfig.View()
	local angles = PhoneConfig.CameraAngles
	return CFrame.new(PhoneConfig.CameraPosition)
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

function PhoneConfig.Pose(anchor)
	local angles = PhoneConfig.HandsetAngles
	return anchor
		* CFrame.new(PhoneConfig.HandsetOffset)
		* CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
end

return PhoneConfig
