-- Contrato do caderno: nomes dentro do Model, remotes e tempos, compartilhados entre
-- ManualService e ManualController. O ângulo empilhado é -180 (sinal herdado da pose autorada
-- dos motores); página virada fica em 0. A posição do C1 é própria de cada motor — o código
-- dirige só a rotação em Z.
local ManualConfig = {}

ManualConfig.ModelName = "Manual"
ManualConfig.JointName = "ManualJoint"
ManualConfig.WaistPartName = "LowerTorso"
ManualConfig.HandPartName = "LeftHand"

-- Pose do caderno, escrita no C0 do Motor6D que prende o Handle ao corpo. Offset em studs, no
-- espaço da parte do corpo. Ângulos em graus, ordem Y-X-Z igual ao campo Orientation do Studio,
-- não a de CFrame.Angles: X inclina a capa, Y gira em torno da vertical, Z rola sobre a lombada.
-- Na cintura os ângulos são lidos direto no LowerTorso, que acompanha o personagem. Na mão são
-- lidos na direção que o personagem encara, porque a animação de segurar deixa a mão torta.
ManualConfig.WaistOffset = Vector3.new(-1.0831, -0.2, 0)
ManualConfig.WaistAngles = Vector3.new(0, 0, 90)
ManualConfig.HandOffset = Vector3.new(-0.15, -0.2, -0.5)
ManualConfig.HandAngles = Vector3.new(60, 0, 180)
ManualConfig.HandPoseRate = 0.1 -- segundos entre recomposições do C0 na mão

-- Câmera de leitura, congelada na entrada do modo em uso: mira o livro real na mão, na pose de
-- HandAngles. Offset em studs a partir da cabeça, no frame da direção que o personagem encara
-- (X direita, Y cima, Z para trás). Ângulos em graus, mesma ordem Y-X-Z do campo Orientation:
-- X negativo inclina o olhar para baixo, Y positivo gira para a esquerda, Z rola a tela.
ManualConfig.CameraOffset = Vector3.new(0, 0, 0)
ManualConfig.CameraAngles = Vector3.new(-20, 8, 0)

-- Modo calibração: tira só a tomada de câmera e as travas de movimento. Animação de segurar,
-- capa e virada de página continuam, e o livro fica visível na mão dos dois jeitos.
ManualConfig.CalibrateHand = false

ManualConfig.RemotesFolderName = "Remotes"
ManualConfig.ToggleModeRemote = "ToggleManualMode"
ManualConfig.UnequipRemote = "UnequipManual"
ManualConfig.ToggleButtonRemote = "ToggleManualButton"
ManualConfig.UpdateStateRemote = "UpdateManualState"

-- Ordem de leitura; cada página tem motor "<nome>Motor" no Handle.
ManualConfig.PageOrder = { "Record", "Roster", "Supply" }
ManualConfig.EndpaperName = "Endpaper"
ManualConfig.BackCoverName = "BackCover"
ManualConfig.FrontCoverMotorName = "FrontCoverMotor"

ManualConfig.StackAngle = -180 -- graus; empilhada à direita, não lida
ManualConfig.CoverOpenAngle = -180 -- graus; capa aberta para a esquerda

ManualConfig.HoldTime = 3 -- segundos de botão segurado para remover o caderno
ManualConfig.OpenDelay = 0.5 -- capa abre antes da lógica de páginas ligar
ManualConfig.RaycastRange = 20 -- studs; alcance do clique nas hitboxes

ManualConfig.PageTween = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
ManualConfig.CoverOpenTween = TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
ManualConfig.CoverCloseTween = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

ManualConfig.HoldAnimationId = "rbxassetid://112441741695315"
ManualConfig.IconId = "rbxassetid://106157472383152"
ManualConfig.HotKey = Enum.KeyCode.One -- alterna cintura/mão; rótulo no slot acompanha

return ManualConfig
