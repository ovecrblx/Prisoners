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
FlashlightConfig.HandOffset = Vector3.new(-0.5, -0.25, -0.45)
FlashlightConfig.HandAngles = Vector3.new(0, 0, 0)
FlashlightConfig.HandSettleTime = 0.3

-- Pontaria no corpo: juntas que giram para levar a lanterna até onde a câmera olha, e a fatia do
-- caminho que cabe a cada uma.
-- A ordem na cadeia manda: quem está acima gira o que está abaixo e a de baixo mede o que sobrou.
-- Por isso a última fica em 1 — é ela que fecha a conta — e as de cima ficam em fração.
-- Fatia acima de 1 numa junta do meio faz ela PASSAR do alvo de propósito, e a de baixo devolve o
-- excesso. Foi isso que soltou o braço: só o ombro, ele girava o desvio da câmera menos o que a
-- cintura levou, e um braço dobrado girando 19 graus lê como travado. Com 1.7 no ombro e o cotovelo
-- fechando, o ombro gira 33 e o cotovelo dobra 13 no contrário — o braço articula, e o facho cai no
-- mesmo lugar.
-- Subir mais o ombro abre mais o braço e dobra mais o cotovelo: 2.2 pede 23 graus de cotovelo, e o
-- LeftElbowBallSocket só tem 20 de cone. Daí para cima começa a bater no limite do rig.
FlashlightConfig.AimJoints = {
	Waist = 0.35,
	LeftShoulder = 1.7,
	LeftElbow = 1,
}

-- Segundos que as juntas ficam na pose da animação antes de a mira valer, para se ler ali para onde
-- a lanterna aponta em repouso. É dessa leitura que sai a correção, e ela não é refeita depois: a
-- junta chega ao comando por torque, então remedir daria o próprio comando pela metade, e a
-- correção somando sobre si mesma faz o braço tremer.
FlashlightConfig.AimSettleTime = 0.4

-- Limites em graus, e eles só CORTAM: valor além do que a câmera alcança não estica nada. Em 90 nos
-- quatro sentidos o corte praticamente não existe — o braço vai até onde a vista for. Para o braço
-- andar MAIS que a câmera, o caminho é subir o fator de Pitch ou de Yaw, não abrir mais o limite.
-- Yaw é a diferença entre a vista e o corpo, então o teto dele é o quanto o braço destorce do
-- tronco antes de o personagem virar sozinho.
FlashlightConfig.AimMinPitch = -90
FlashlightConfig.AimMaxPitch = 90
FlashlightConfig.AimMinYaw = -90
FlashlightConfig.AimMaxYaw = 90

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
