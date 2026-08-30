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
-- Estes valores são um chute inicial: a lanterna nunca foi calibrada em Play. Ligue CalibrateHand,
-- posicione, e cole aqui o par que o console imprimir.
FlashlightConfig.WaistOffset = Vector3.new(1, 0, 0)
FlashlightConfig.WaistAngles = Vector3.new(-70, 0, 0)
FlashlightConfig.HandOffset = Vector3.new(-0.5, -0.25, -0.45)
FlashlightConfig.HandAngles = Vector3.new(0, 0, 0)
FlashlightConfig.HandSettleTime = 0.3 -- inerte com HandTracksFacing: nada congela

-- A lanterna mira, não descansa: a pose na mão é refeita todo quadro em vez de congelar em
-- HandSettleTime, então a posição segue a mão e o facho segue o personagem. Congelada, ela
-- acompanharia a torção da animação de segurar e apontaria para os lados.
-- Ligado isto, HandAngles é o desvio a partir da direção que o personagem encara — zero é reto
-- para a frente — e HandC0Offset/HandC0Angles e CalibrateHand ficam sem efeito, porque não existe
-- pose congelada para assar.
FlashlightConfig.HandTracksFacing = true

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

FlashlightConfig.SkinFolderName = "Skins"
FlashlightConfig.SkinOnName = "On"
FlashlightConfig.SkinOffName = "Off"

FlashlightConfig.HoldAnimationId = "rbxassetid://78800081500176"
FlashlightConfig.IconId = "rbxassetid://120425963120676"
FlashlightConfig.HotKey = Enum.KeyCode.Two -- alterna cintura/mão; rótulo no slot acompanha
FlashlightConfig.KeyLabel = "2"
FlashlightConfig.PowerKey = Enum.KeyCode.Q -- liga e desliga a luz, só com a lanterna na mão

return FlashlightConfig
