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

-- Graus de folga antes de reescrever o giro. MEDIDO no place: a escrita em Weld.C0 custa 4.368 us e
-- a conta que decide custa 0.299 us, então cada escrita evitada paga 14 contas.
OverheadCardConfig.FacingEpsilonDegrees = 0.5

-- studs abaixo dos quais câmera e cartão coincidem e o lookAt fica indefinido.
OverheadCardConfig.FacingNearLimit = 0.001

local RADIUS_SQ = OverheadCardConfig.FacingRadius * OverheadCardConfig.FacingRadius
local NEAR_SQ = OverheadCardConfig.FacingNearLimit * OverheadCardConfig.FacingNearLimit
local FACING_COS = math.cos(math.rad(OverheadCardConfig.FacingEpsilonDegrees))

-- Decide se o cartão precisa girar neste quadro, lendo o estado REAL da peça em vez de um cache: o
-- giro certo depende da cabeça e da câmera juntas, e a peça já carrega o resultado das duas.
-- Recusa em quatro casos, do mais barato ao mais caro de descobrir:
--   fora do alcance de render, atrás do olho, em cima da câmera, ou já encarando dentro da folga.
function OverheadCardConfig.NeedsFacing(cameraCFrame, handleCFrame)
	local toCamera = cameraCFrame.Position - handleCFrame.Position
	local distanceSq = toCamera:Dot(toCamera)

	if distanceSq > RADIUS_SQ then
		return false
	end

	-- toCamera aponta do cartão para o olho; concordar com o LookVector da câmera é estar atrás dela.
	if toCamera:Dot(cameraCFrame.LookVector) >= 0 then
		return false
	end

	if distanceSq <= NEAR_SQ then
		return false
	end

	return handleCFrame.LookVector:Dot(toCamera / math.sqrt(distanceSq)) < FACING_COS
end

return OverheadCardConfig
