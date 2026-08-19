--!strict
-- Tuning do sistema de NPCs e do Route Builder. Compartilhado porque o cliente do builder
-- precisa de cores, pastas e limites de GUI; expõe tuning, nunca estado de IA.
local NpcConfig = {}

-- Classes de NPC. Rig em ReplicatedStorage.Client.Npc.<Classe>; cada uma tem árvore própria e
-- pode ter rede de rota própria além da principal (RouteData.RouteType = Main + estas).
NpcConfig.Classes = { "Citizen", "Medic", "Guard", "Detective" }

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
