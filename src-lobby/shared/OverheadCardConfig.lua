-- Parâmetros do cartão acima da cabeça. Lidos pelo servidor e pelo cliente.
local OverheadCardConfig = {}

-- Template: ReplicatedStorage.Client.GUI.BillboardAccessory > Handle > SurfaceGui > Card
OverheadCardConfig.TemplateFolder = "Client"
OverheadCardConfig.TemplateSubfolder = "GUI"
OverheadCardConfig.TemplateName = "BillboardAccessory"

OverheadCardConfig.AccessoryName = "BillboardAccessory"
OverheadCardConfig.WeldName = "AccessoryWeld"
OverheadCardConfig.HandleName = "Handle"
OverheadCardConfig.HatAttachmentName = "HatAttachment"

OverheadCardConfig.CardName = "Card"
OverheadCardConfig.InfoName = "Info"
OverheadCardConfig.ImageName = "Image"
OverheadCardConfig.ClassName = "Class"
OverheadCardConfig.LeaderboardName = "Leaderboard"

-- Manter igual ao SurfaceGui.MaxDistance do template.
OverheadCardConfig.FacingRadius = 100

return OverheadCardConfig
