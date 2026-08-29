-- Contrato do caderno: nomes dentro do Model, remotes e tempos, compartilhados entre
-- ManualService e ManualController. O ângulo empilhado é -180 (o sinal escolhe o lado da virada);
-- página virada fica em 0. A posição do C1 é própria de cada motor — o código
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
-- lidos na direção que o personagem encara, porque a animação de segurar deixa a mão torta —
-- e só até HandSettleTime, quando o C0 congela e o livro passa a viver no espaço da mão.
ManualConfig.WaistOffset = Vector3.new(-1, -0.5, 0)
ManualConfig.WaistAngles = Vector3.new(0, 0, -90)
ManualConfig.HandOffset = Vector3.new(-0.15, -0.25, -0.5)
ManualConfig.HandAngles = Vector3.new(60, 0, 180)
ManualConfig.HandSettleTime = 1.5 -- segundos amostrando a mão até o C0 congelar
ManualConfig.HandSettleGrace = 0.2 -- segundos após o congelamento até o readback ler

-- Pose final do livro já no espaço da mão, em studs e graus. Preenchida, o C0 é essa constante
-- e o livro nasce certo no primeiro quadro, sem esperar a animação de segurar replicar — a
-- amostragem acima nem roda. Vazia, vale o caminho de amostragem, que deixa um ajuste visível
-- na entrada. Com CalibrateHand o servidor imprime este par pronto para colar.
ManualConfig.HandC0Offset = Vector3.new(1, 0, 0)
ManualConfig.HandC0Angles = nil

-- Câmera de leitura: orbita o livro real na mão seguindo só a posição dele, com o topo no mundo —
-- a rotação do livro não entra, então o horizonte fica reto. O ponto de mira é o Handle deslocado
-- por CameraFocusOffset, em studs no espaço do livro. Yaw e pitch em graus: yaw é relativo à
-- direção que o personagem encara, congelada na entrada do modo; pitch é do mundo, positivo olha
-- de cima. Distância em studs, do ponto de mira. Estes quatro definem a vista, e fora de
-- CalibrateCamera nenhuma entrada os altera.
ManualConfig.CameraFocusOffset = Vector3.new(0, 0, 0)
ManualConfig.CameraYaw = 6.5
ManualConfig.CameraPitch = -30
ManualConfig.CameraDistance = 0.8
ManualConfig.CameraMinPitch = -85
ManualConfig.CameraMaxPitch = 85
ManualConfig.CameraMinDistance = 0.5
ManualConfig.CameraMaxDistance = 12
ManualConfig.CameraOrbitSpeed = 0.4 -- graus por pixel arrastado
ManualConfig.CameraZoomStep = 0.5 -- studs por clique de roda
ManualConfig.CameraPinchStep = 4 -- studs por unidade de escala da pinça
ManualConfig.CameraSmoothing = 18 -- 1/s; maior gruda mais no livro
ManualConfig.CameraDragThreshold = 8 -- pixels antes do arrasto virar órbita
ManualConfig.CameraPanSpeed = 0.01 -- studs por pixel arrastado com o botão do meio
ManualConfig.CameraDumpKey = Enum.KeyCode.C -- só com CalibrateCamera

-- Modo calibração da câmera: painel vivo com órbita e mira, botão do meio arrasta a mira, e a
-- tecla CameraDumpKey imprime o bloco pronto para colar aqui. Desligado, a vista é exatamente a
-- dos quatro valores acima e nenhuma entrada a move.
ManualConfig.CalibrateCamera = false

-- Modo calibração da mão: readback da pose no servidor.
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

ManualConfig.StackAngle = -180 -- graus; empilhada, não lida. Negativo levanta a página para o leitor
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
