-- Contrato da lanterna: ponto de coleta, pose e os dois skins. O que é comum a todo item
-- equipável — parte do corpo, remotes, ordem no HUD, tempo do hold — está no ItemConfig.
-- A luz sai pelo -Z local do Handle: é para lá que o Beam corre e para onde o SpotLight de Face
-- Front aponta. Por isso os ângulos de mão saem de zero — zero já é apontar para onde o
-- personagem encara.
local FlashlightConfig = {}

FlashlightConfig.PickupPosition = Vector3.new(-3.27, 5.26, -35.178)
FlashlightConfig.PickupAngles = Vector3.new(0, -135, 0)

-- Mesma leitura de pose do caderno: offset em studs no espaço da parte do corpo, ângulos em graus
-- na ordem Y-X-Z do campo Orientation do Studio. Na mão os ângulos são relativos à direção que o
-- personagem encara, e valem até HandSettleTime, quando o C0 congela.
FlashlightConfig.WaistOffset = Vector3.new(1, 0, 0)
FlashlightConfig.WaistAngles = Vector3.new(-70, 0, 0)
FlashlightConfig.HandOffset = Vector3.new(-0.2, -0.2, -0.25)
FlashlightConfig.HandAngles = Vector3.new(-12, 5, 0)
FlashlightConfig.HandSettleTime = 0.3

-- Pontaria: um IKControl puxa a mão até um alvo no rumo do mouse, e o solver faz o braço. A cadeia é
-- do ChainRoot ao EndEffector, os dois inclusive, e a lanterna fica fora dela: o que ela faz na mão
-- continua sendo HandOffset e HandAngles.
FlashlightConfig.AimChainRoot = "LeftUpperArm"
FlashlightConfig.AimEndEffector = "LeftHand"
FlashlightConfig.AimType = Enum.IKControlType.Position

-- De onde o rumo do mouse é medido, e a que distância o alvo fica: a do efetor em repouso até aqui.
-- Tem de ser peça que o solver NÃO move — medida de dentro da cadeia, o alvo andaria junto com o
-- braço que o persegue, e o braço treme atrás de si mesmo.
FlashlightConfig.AimOriginPart = "UpperTorso"

-- O campo de mira: um círculo a AimFieldDistance studs à frente do corpo, com AimFieldRadius de
-- raio. É a janela em que o mouse manda — rumo que cai fora volta para a borda dela, então a mira
-- satura na lateral em vez de ir para as costas.
-- Os dois juntos dão a abertura: atan(raio / distância). 6 e 8 dão cerca de 37 graus de meia-
-- abertura. Aproximar o círculo ou abrir o raio solta a mira; afastar ou apertar o raio fecha.
-- Medido em espaço de corpo, então virar o personagem leva a janela junto.
FlashlightConfig.AimFieldDistance = 8
FlashlightConfig.AimFieldRadius = 6

-- Quanto da pose vem da mira, de 0 a 1: abaixo de 1 a animação de segurar volta a pesar.
FlashlightConfig.AimWeight = 1

-- Segundos que o peso leva de 0 a AimWeight ao sacar, e de volta a 0 ao guardar. É o que faz a mira
-- ENTRAR junto com a animação de segurar em vez de depois dela: sem rampa o braço salta para o rumo
-- do mouse no quadro em que o controle nasce. Perto do fade da animação, que é de 0.1.
FlashlightConfig.AimBlendTime = 0.25

-- Segundos que o efetor leva para alcançar o alvo, por mola criticamente amortecida do solver.
FlashlightConfig.AimSmoothTime = 0.03

-- Segundos para o alvo da mira fechar a maior parte da distância até o rumo do mouse. É o quanto
-- ela PERSEGUE em vez de colar: em 0 ela cola, e todo tranco de ponteiro vira tranco de braço. O
-- arrasto corre no espaço do corpo, então virar o personagem leva a mira junto em vez de deixá-la
-- para trás.
-- Some com o AimSmoothTime: este atrasa o alvo, aquele atrasa o solver atrás do alvo.
FlashlightConfig.AimFollowTime = 0.18

FlashlightConfig.HandC0Offset = nil
FlashlightConfig.HandC0Angles = nil

FlashlightConfig.CalibrateHand = false

-- Os dois SurfaceAppearance vivem prontos em Flashlight.Skins, um por estado: ColorMap é Plugin
-- Security e nenhum script de runtime a escreve, então a troca é de instância, reparentando o skin
-- certo no Handle. Trocar o asset é trocar o ColorMap desses dois no template, não aqui.
-- Teto do feixe em studs, e o mesmo número do SpotLight.Range do template — os dois desenham o
-- mesmo alcance, e divergir deixa a luz acesa onde o feixe já acabou. O comprimento autorado das
-- attachments não manda: o feixe vai até aqui, ou até a primeira superfície antes disso.
FlashlightConfig.BeamRange = 24

-- Alcance em studs do raio que sai do ponteiro, e só dele: é o quanto se procura superfície para
-- saber a DIREÇÃO da mira. A distância da ponta continua sendo BeamRange.
FlashlightConfig.MouseRange = 500

FlashlightConfig.SkinFolderName = "Skins"
FlashlightConfig.SkinOnName = "On"
FlashlightConfig.SkinOffName = "Off"

-- Chaves do SfxConfig. Coleta, equipar e guardar são lidas pela camada de item, então todo item que
-- as preencher toca sozinho; as do interruptor são desta lanterna, que é quem tem luz.
FlashlightConfig.PickupSfx = "FlashlightPickup"
FlashlightConfig.EquipSfx = "FlashlightEquip"
FlashlightConfig.StowSfx = "FlashlightStow"
FlashlightConfig.PowerOnSfx = "FlashlightOn"
FlashlightConfig.PowerOffSfx = "FlashlightOff"

FlashlightConfig.HoldAnimationId = "rbxassetid://78800081500176"
FlashlightConfig.IconId = "rbxassetid://120425963120676"
FlashlightConfig.HotKey = Enum.KeyCode.Two -- alterna cintura/mão; rótulo no slot acompanha
FlashlightConfig.KeyLabel = "2"
FlashlightConfig.PowerKey = Enum.KeyCode.Q -- liga e desliga a luz, só com a lanterna na mão

return FlashlightConfig
