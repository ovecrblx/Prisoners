--!strict
-- Estado do turno, publicado como attribute do workspace. Dono único dos nomes: quem lê nunca
-- digita a string, e o serviço de turno, quando existir, é o único a escrever.
local Workspace = game:GetService("Workspace")

local ShiftConfig = {}

-- Turno em andamento (boolean) e número do turno corrente (number).
ShiftConfig.LiveAttribute = "ShiftLive"
ShiftConfig.NumberAttribute = "Shift"

-- Fim do turno corrente, em relógio de servidor (Workspace:GetServerTimeNow()), para o cliente
-- contar sozinho em vez de perguntar de segundo em segundo.
ShiftConfig.EndsAtAttribute = "ShiftEndsAt"

-- Teto do turno, em segundos. É teto, não piso: quem publica pode encerrar antes.
ShiftConfig.Duration = 240

-- Valor de quem lê antes de existir escritor. Ausência vale porta ABERTA: exigir o attribute
-- deixaria o mundo vazio sem uma linha no console, que é a falha mais cara de rastrear.
ShiftConfig.DefaultLive = true
ShiftConfig.DefaultNumber = 1

function ShiftConfig.IsLive(): boolean
	local value = Workspace:GetAttribute(ShiftConfig.LiveAttribute)
	if type(value) == "boolean" then
		return value
	end
	return ShiftConfig.DefaultLive
end

function ShiftConfig.GetNumber(): number
	local value = Workspace:GetAttribute(ShiftConfig.NumberAttribute)
	if type(value) == "number" then
		return value
	end
	return ShiftConfig.DefaultNumber
end

-- Existe alguém publicando o estado, ou tudo que se lê é o padrão?
function ShiftConfig.HasOwner(): boolean
	return Workspace:GetAttribute(ShiftConfig.LiveAttribute) ~= nil
end

-- Segundos que faltam para o fim do turno; 0 quando ninguém publicou prazo.
function ShiftConfig.Remaining(): number
	local value = Workspace:GetAttribute(ShiftConfig.EndsAtAttribute)
	if type(value) ~= "number" then
		return 0
	end
	return math.max(value - Workspace:GetServerTimeNow(), 0)
end

-- Só vale de servidor: attribute escrito no cliente não replica de volta.
function ShiftConfig.Publish(live: boolean, number: number, endsAt: number?)
	Workspace:SetAttribute(ShiftConfig.LiveAttribute, live)
	Workspace:SetAttribute(ShiftConfig.NumberAttribute, number)
	Workspace:SetAttribute(ShiftConfig.EndsAtAttribute, endsAt)
end

return ShiftConfig
