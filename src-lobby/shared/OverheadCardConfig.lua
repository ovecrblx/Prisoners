-- Cartão acima da cabeça — nomes e medidas compartilhados entre servidor e cliente.
--
-- Servidor anexa o accessory; cliente o faz encarar a câmera. Os dois precisam concordar no
-- nome do accessory e no do weld: divergiu, o servidor anexa e o cliente nunca acha para
-- orientar — o cartão fica congelado apontando para um lado só, sem erro nenhum.
local OverheadCardConfig = {}

-- Template no place (não versionado — vive em ReplicatedStorage.Client.GUI).
OverheadCardConfig.TemplateFolder = "Client"
OverheadCardConfig.TemplateSubfolder = "GUI"
OverheadCardConfig.TemplateName = "BillboardAccessory"

-- Nome da instância clonada no personagem. Igual ao template para não haver dois nomes para a
-- mesma coisa.
OverheadCardConfig.AccessoryName = "BillboardAccessory"

-- SurfaceGui (não BillboardGui): mantém nitidez à distância via PixelsPerStud alto. O preço é
-- não ter auto-facing — daí o controller do cliente existir.
OverheadCardConfig.WeldName = "AccessoryWeld"
OverheadCardConfig.HandleName = "Handle"
OverheadCardConfig.HatAttachmentName = "HatAttachment"

-- Caminho dos campos DENTRO do SurfaceGui. Este módulo não preenche nenhum deles — só diz onde
-- estão, para quem for preencher.
OverheadCardConfig.CardName = "Card"
OverheadCardConfig.InfoName = "Info"
OverheadCardConfig.ImageName = "Image"
OverheadCardConfig.ClassName = "Class"
OverheadCardConfig.LeaderboardName = "Leaderboard"

-- Só personagens dentro deste raio são reorientados. Comparação por distância AO QUADRADO no
-- controller (sem sqrt), já que roda por frame para cada jogador.
--
-- Casado com o SurfaceGui.MaxDistance do template (100). Um raio MENOR que ele cria uma faixa
-- onde o cartão está visível mas parado, congelado na última orientação — o jogador vê um painel
-- de lado ou de costas. Mexeu no MaxDistance no Studio, mexa aqui junto.
OverheadCardConfig.FacingRadius = 100

return OverheadCardConfig
