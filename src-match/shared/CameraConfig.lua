-- Regras da câmera do jogador, valendo para todos. Só de cliente: câmera é local e nada disto passa
-- pela rede.
local CameraConfig = {}

-- Teto e piso da vista em primeira pessoa, em graus. Positivo olha para cima. A engine deixa quase
-- 90 para cada lado; estes números só apertam, nunca abrem. Fora da primeira pessoa não valem.
CameraConfig.FirstPersonMaxPitch = 30
CameraConfig.FirstPersonMinPitch = -30

-- Studs entre a câmera e a cabeça que ainda contam como primeira pessoa. A engine entra nela com a
-- câmera a menos de 1 stud do assunto; a folga cobre o quadro em que o zoom ainda está chegando lá.
CameraConfig.FirstPersonDistance = 1.5

CameraConfig.HeadPartName = "Head"

return CameraConfig
