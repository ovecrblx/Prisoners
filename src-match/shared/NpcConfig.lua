--!strict
-- Tuning do sistema de NPCs e do Route Builder. Compartilhado porque o cliente do builder
-- precisa de cores, pastas e limites de GUI; expõe tuning, nunca estado de IA.
local NpcConfig = {}

-- Classes de NPC. Rig em ReplicatedStorage.Client.Npc.<Classe>; cada uma tem árvore própria e
-- pode ter rede de rota própria além da principal (RouteData.RouteType = Main + estas).
NpcConfig.Classes = { "Citizen", "Medic", "Guard", "Detective" }

-- ============================================================== CORPOS E NASCIMENTO

-- Caminho do template a partir de ReplicatedStorage: Model DIRETO com o nome da classe. O rig do
-- jogador, em Client.Character, tem um filho "Rig" — aqui não tem, e os dois não compartilham
-- resolvedor.
NpcConfig.BODY_SOURCE = { "Client", "Npc" }

-- Pasta em workspace que recebe os corpos vivos; entra no filtro de raycast do builder.
NpcConfig.BODY_FOLDER = "NpcBodies"

-- Caminho da pasta de marcadores a partir de workspace; o marcador é a BasePart com o nome da classe.
NpcConfig.SPAWN_FOLDER = { "Siland_Home", "Spawn" }

-- Classe -> corpos vivos. Há um marcador por classe, então contagem acima de 1 nasce empilhada
-- enquanto ninguém anda.
NpcConfig.SPAWN = {
	Citizen = 1,
} :: { [string]: number }

-- studs do raycast que assenta o corpo no chão sob o marcador; s até repor quem morreu.
NpcConfig.SPAWN_GROUND_RANGE = 60
NpcConfig.SPAWN_RESPAWN_DELAY = 5

-- ================================================================ COMPORTAMENTO E LOCOMOÇÃO

-- s entre ticks da árvore. O driver de locomoção é à parte, no Heartbeat.
NpcConfig.TICK_INTERVAL = 0.2

-- studs/s andando; studs de chegada, medidos em XZ; s até o driver soltar destino não renovado.
NpcConfig.WALK_SPEED = 10
NpcConfig.ARRIVE_RADIUS = 3
NpcConfig.GOAL_TTL = 0.5

-- Enguiço: studs de aproximação que contam como avanço, e s sem avanço até desistir do destino.
NpcConfig.STUCK_PROGRESS = 0.5
NpcConfig.STUCK_TIME = 3

-- studs acima e abaixo do nó na sonda que separa superfície de aéreo.
NpcConfig.PROBE_UP = 4
NpcConfig.PROBE_DOWN = 60

-- Redes que cada classe percorre, na ordem de preferência; a primeira com nó vence. Sem entrada,
-- a classe anda a malha Main.
NpcConfig.ROUTE_PREFERENCE = {
	Citizen = { "Citizen", "Main" },
} :: { [string]: { string } }

-- s entre retratos que o painel de IA envia a quem está olhando.
NpcConfig.BRAIN_PUSH_INTERVAL = 0.2

-- ================================================================= MARCHA PELO GRAFO (trajetos)

-- studs: até onde vale caminhar para alcançar a rede, e a folga além do nó mais próximo em que
-- outro nó ainda conta como porta de entrada.
NpcConfig.NAV_ENTRY_MAX = 120
NpcConfig.NAV_ENTRY_BAND = 8

-- studs; faixa de altura que ainda conta como o mesmo andar, e subida que o corpo vence para
-- entrar na rede (o teto absoluto do degrau curto; acima dele quem decide é AGENT_MAX_CLIMB_SLOPE).
NpcConfig.NAV_ARRIVE_Y = 10
NpcConfig.NAV_ENTRY_RISE = 4

-- studs; altura do raio que pergunta "dá para ir reto daqui até lá?".
NpcConfig.NAV_PROBE_EYE = 3

-- studs; ergação e folga do raio que separa borda de laje ao entrar na rede por descida.
NpcConfig.NAV_DROP_PROBE_LIFT = 0.5
NpcConfig.NAV_DROP_PROBE_MARGIN = 2

-- Trajetos gerados por planejamento (tronco + galhos); s de validade de um trajeto; studs de
-- deriva do alvo que o invalidam; s de espera depois de um planejamento recusado.
NpcConfig.NAV_VARIANT_COUNT = 3
NpcConfig.NAV_VARIANT_TTL = 12
NpcConfig.NAV_REPLAN_DRIFT = 70
NpcConfig.NAV_PLAN_RETRY = 0.75

-- studs; a que distância do alvo a marcha solta o corpo.
NpcConfig.NAV_DIRECT_RADIUS = 2

-- Tetos do desvio: studs A MAIS que a linha reta, e fator sobre ela. O par BLOCKED vale quando há
-- geometria entre corpo e alvo — sem linha reta não há escolha a calibrar, e contornar é a única
-- opção. Abaixo do piso, a distância direta deixa de ser régua e só o teto absoluto decide.
NpcConfig.NAV_VARIANT_DETOUR_OPEN = 180
NpcConfig.NAV_VARIANT_RATIO_OPEN = 1.8
NpcConfig.NAV_VARIANT_DETOUR_BLOCKED = 400
NpcConfig.NAV_VARIANT_RATIO_BLOCKED = 4
NpcConfig.NAV_RATIO_FLOOR = 20

-- =========================================================== MOTOR DE LOCOMOÇÃO (driver do corpo)

-- studs; onde o DRIVER freia e onde um waypoint conta como consumido — o mesmo número por desenho.
-- Tem que ser MENOR que ARRIVE_RADIUS: a árvore precisa ver "cheguei" antes do driver, senão o corpo
-- assenta em cima do ponto esperando ordem que só vem no tick seguinte.
NpcConfig.MOVE_DRIVE_RADIUS = 2

-- studs; tolerância vertical do consumo de waypoint. Sem teto em Y, escada de dois lances (waypoints
-- quase na mesma coluna XZ) é consumida de uma vez e o corpo atravessa o vão.
NpcConfig.MOVE_WAYPOINT_Y = 8

-- studs; acima disto o trecho vale um cálculo de rota, abaixo vai na sonda de linha reta.
NpcConfig.MOVE_SHORT_HOP = 15

-- s entre recálculos do mesmo destino, piso absoluto entre dois cálculos, e prazo até dar um cálculo
-- em voo por perdido.
NpcConfig.MOVE_REPATH_INTERVAL = 1
NpcConfig.MOVE_MIN_COMPUTE_GAP = 0.25
NpcConfig.MOVE_COMPUTE_TIMEOUT = 5

-- studs de deriva do destino que furam o piso de tempo; falhas seguidas de cálculo até desistir; s
-- desde a última tentativa até perdoar o contador.
NpcConfig.MOVE_TARGET_DRIFT = 15
NpcConfig.MOVE_MAX_PATH_FAILS = 3
NpcConfig.MOVE_FAIL_RESET_COOLDOWN = 4

-- studs; deslocamento do alvo que ainda conta como o MESMO alvo para o rastreador de inalcançável.
NpcConfig.MOVE_STUCK_TARGET_DELTA = 6

-- Geometria do agente para o planejador, derivada da escala REAL do HumanoidRootPart: altura de HRP
-- de um R15 escala 1, raio e altura base, fator do raio e a caixa de clamp de cada um.
NpcConfig.MOVE_HRP_REFERENCE = 2
NpcConfig.MOVE_AGENT_RADIUS = 2
NpcConfig.MOVE_AGENT_HEIGHT = 5
NpcConfig.MOVE_AGENT_RADIUS_FACTOR = 0.9
NpcConfig.MOVE_AGENT_RADIUS_MAX = 6
NpcConfig.MOVE_AGENT_HEIGHT_MIN = 3
NpcConfig.MOVE_AGENT_HEIGHT_MAX = 20

-- Validação da rota calculada: studs de folga desejada até a parede, teto do empurrão por waypoint,
-- altura do raio de pé e do de tronco, meia-largura do corpo nas diagonais, ganho de altura que
-- caracteriza subida, teto de waypoints validados e fração de sondas obstruídas que veta a rota.
NpcConfig.MOVE_WALL_CLEARANCE = 3.5
NpcConfig.MOVE_MAX_NUDGE = 3
NpcConfig.MOVE_FOOT_PROBE = 1
NpcConfig.MOVE_CHEST_PROBE = 3
NpcConfig.MOVE_HALF_WIDTH = 2.5
NpcConfig.MOVE_CLIMB_EPSILON = 0.5
NpcConfig.MOVE_MAX_VALIDATED = 48
NpcConfig.MOVE_BLOCKED_TOLERANCE = 0.2

-- studs; alcance da sonda que aprova a linha reta antes de ela virar comando.
NpcConfig.MOVE_STRAIGHT_PROBE = 14

-- Frenagem: studs de aproximação do destino em que começa, fração mínima da velocidade, e teto da
-- velocidade angular da direção comandada em rad/s.
NpcConfig.MOVE_SLOWDOWN_RADIUS = 9
NpcConfig.MOVE_MIN_SCALE = 0.25
NpcConfig.MOVE_MAX_TURN_RATE = 10

-- Trava de curva fechada: graus que a acionam, graus de folga que a soltam, s de teto duro, e fração
-- da velocidade enquanto o corpo gira.
NpcConfig.MOVE_TURN_LOCK_ANGLE = 45
NpcConfig.MOVE_TURN_ALIGNED_ANGLE = 12
NpcConfig.MOVE_TURN_LOCK_TIMEOUT = 1
NpcConfig.MOVE_TURN_SCALE = 0.35

-- Detector de loop: s entre amostras, teto do piso em studs de deslocamento líquido, e a fração da
-- velocidade COMANDADA que um rig de constraint de fato entrega. O piso é o menor dos dois.
NpcConfig.MOVE_LOOP_INTERVAL = 0.5
NpcConfig.MOVE_LOOP_MIN_TRAVEL = 2
NpcConfig.MOVE_LOOP_TRAVEL_FRACTION = 0.2

-- Escape: s de passo atrás, fração da velocidade nele, e s de parada total antes da rota nova.
NpcConfig.MOVE_LOOP_BACKSTEP_TIME = 0.25
NpcConfig.MOVE_LOOP_BACKSTEP_SCALE = 0.6
NpcConfig.MOVE_LOOP_IDLE_TIME = 0.5

-- Armadilha: studs e s em que dois loops contam como o mesmo lugar; streak que troca o passo atrás
-- por escape lateral, e streak em que a pausa deixa de ser devolvida ao orçamento de inalcançável.
NpcConfig.MOVE_LOOP_TRAP_RADIUS = 25
NpcConfig.MOVE_LOOP_TRAP_FORGET = 20
NpcConfig.MOVE_LOOP_STREAK_LATERAL = 2
NpcConfig.MOVE_LOOP_STREAK_NO_CREDIT = 3

-- Destrave local: s comandado a andar sem deslocamento líquido, studs que contam como ter andado,
-- studs do raio frontal e s andando de lado.
NpcConfig.MOVE_UNSTICK_TIMEOUT = 1.5
NpcConfig.MOVE_UNSTICK_MIN_TRAVEL = 4
NpcConfig.MOVE_UNSTICK_RAY = 8
NpcConfig.MOVE_UNSTICK_DETOUR = 0.8

-- studs/s por classe. A árvore declara a intenção (Stalk/Walk/Run) e a tradução para número mora
-- aqui; classe ou marcha sem entrada cai em WALK_SPEED.
NpcConfig.GAIT = {
	Citizen = { Stalk = 6, Walk = 10, Run = 14 },
	Medic = { Stalk = 6, Walk = 11, Run = 18 },
	Guard = { Stalk = 7, Walk = 11, Run = 20 },
	Detective = { Stalk = 6, Walk = 11, Run = 17 },
} :: { [string]: { Stalk: number, Walk: number, Run: number } }

-- ============================================================================= ANIMAÇÃO

-- studs/s: até o primeiro valor o corpo está parado; a partir do segundo, correndo.
NpcConfig.ANIM_IDLE_SPEED = 0.6
NpcConfig.ANIM_RUN_SPEED = 14

-- studs/s em que cada animação foi autorada, para a track acompanhar o passo e o pé não deslizar.
NpcConfig.ANIM_WALK_REFERENCE = 16
NpcConfig.ANIM_RUN_REFERENCE = 16

-- s mínimos num estado antes de trocar, e s de mistura entre duas locomoções.
NpcConfig.ANIM_MIN_DWELL = 0.15
NpcConfig.ANIM_FADE = 0.2

-- ============================================================================== ASSENTOS

-- Caminho da pasta de assentos a partir de workspace.
NpcConfig.SEAT_FOLDER = { "Siland_Home", "Seats" }

-- studs; distância em que um assento livre atrai o NPC.
NpcConfig.SEAT_SENSE_RADIUS = 45

-- studs; quão longe do nó de rota mais próximo um assento ainda conta como servido pela rota. Só
-- este último trecho sai do traçado — assento mais longe que isto é ignorado em vez de virar
-- linha reta pelo mapa.
NpcConfig.SEAT_ANCHOR_RADIUS = 12

-- s sentado (faixa sorteada) e s até o mesmo corpo querer sentar de novo. O motor tem carência
-- própria por personagem e assento, e a doc pede para não depender do valor dela.
NpcConfig.SEAT_REST_MIN = 8
NpcConfig.SEAT_REST_MAX = 16
NpcConfig.SEAT_COOLDOWN = 25

-- ============================================================ ROUTE BUILDER (autoria de rotas)

-- Pasta em workspace com os nós visuais; entra em todo filtro de raycast do sistema.
NpcConfig.NODE_FOLDER_NAME = "RouteNodes"

-- Cores por tipo de rota — só representação; a lógica usa RouteData.RouteType.
NpcConfig.NODE_COLORS = {
	Main = Color3.fromRGB(60, 120, 255),
	Citizen = Color3.fromRGB(235, 180, 60),
	Medic = Color3.fromRGB(72, 196, 132),
	Guard = Color3.fromRGB(214, 70, 55),
	Detective = Color3.fromRGB(160, 85, 235),
}

-- Esfera da área de escuta e o botão do modo que a edita.
NpcConfig.SENSE_AREA_COLOR = Color3.fromRGB(85, 220, 235)
NpcConfig.SENSE_AREA_TRANSPARENCY = 0

-- studs; raio de escuta de nó que o autor não configurou (o valor por nó vive no grafo).
NpcConfig.NODE_SENSE_RADIUS = 40

-- studs; diâmetro da esfera, ergação do desenho acima do ponto de chão, espessura do cabo.
NpcConfig.NODE_SIZE = 2
NpcConfig.NODE_VISUAL_LIFT = 3
NpcConfig.LINK_THICKNESS = 0.35

-- Fator de tamanho do sub-ponto (nó de passagem pura: exatamente 2 links) em relação ao nó cheio.
NpcConfig.NODE_SUB_SCALE = 0.5

-- studs acima do Terrain que ainda contam como "chão do mapa" (nó acima disso é aéreo e não é
-- porta de entrada na rede); graus de inclinação que o corpo vence andando.
NpcConfig.NODE_SURFACE_MAX_RISE = 1
NpcConfig.AGENT_MAX_CLIMB_SLOPE = 55

-- ======================================================================= PERSISTÊNCIA (slots)

-- Migração de última instância é versionar o nome; a normal é schemaVersion no registro.
NpcConfig.ROUTE_DATASTORE_NAME = "NpcRoutes_v1"
NpcConfig.ROUTE_RECORD_KEY = "routes"
NpcConfig.ROUTE_AUTOSAVE_KEY = "__autosave"

NpcConfig.MAX_ROUTE_SLOTS = 12
NpcConfig.ROUTE_SLOT_NAME_MAX = 32

-- Tetos de sanidade; quem manda é a validação do servidor.
NpcConfig.MAX_NODES_PER_SLOT = 2000
NpcConfig.MAX_NODES_PER_ROUTE = NpcConfig.MAX_NODES_PER_SLOT
NpcConfig.MAX_ROUTES_PER_SLOT = 40

-- Slot carregado no boot do servidor ("" = nenhum); slot inexistente é ignorado.
NpcConfig.ROUTE_AUTOLOAD_NAME = "default"

-- ============================================================================ AUTORIZAÇÃO

-- UserId -> true. Em Studio o dono sempre pode; a lista vale em servidor publicado.
NpcConfig.BUILDER_ALLOWLIST = {
	[4040308] = true, -- ovec
} :: { [number]: boolean }

-- ops/s de edição por jogador; s mínimo entre saves por jogador; s do autosave.
NpcConfig.BUILDER_MAX_OPS_PER_SECOND = 20
NpcConfig.BUILDER_SAVE_MIN_INTERVAL = 6
NpcConfig.BUILDER_AUTOSAVE_INTERVAL = 60

-- Caixa de sanidade das posições vindas do cliente, em studs. Siland_Home medido:
-- centro (-64, 36, -19), tamanho 444 x 72 x 400.
NpcConfig.MAP_BOUNDS = {
	center = Vector3.new(-64, 40, -19),
	size = Vector3.new(600, 300, 600),
}

-- ==================================================================== GESTOS DO BUILDER

-- studs; passo inicial da trilha arrastada, faixa e degraus do ajuste em runtime.
NpcConfig.BUILDER_TRAIL_SPACING = 5
NpcConfig.BUILDER_TRAIL_SPACING_MIN = 0.5
NpcConfig.BUILDER_TRAIL_SPACING_MAX = 40
NpcConfig.BUILDER_TRAIL_SPACING_STEP = 2
NpcConfig.BUILDER_TRAIL_SPACING_FINE = 4
NpcConfig.BUILDER_TRAIL_SPACING_STEP_FINE = 0.5

-- Teto de nós por arrasto (o teto do grafo é MAX_NODES_PER_SLOT).
NpcConfig.BUILDER_MAX_TRAIL_NODES = 40

-- Quantos pontos o Mover arrasta junto no máximo (0 desliga a corrente).
NpcConfig.BUILDER_MOVE_CHAIN_MAX = 12

-- studs; raio lateral da mira para emendar linha nova em ponto existente.
NpcConfig.BUILDER_SNAP_RADIUS = 5

return NpcConfig
