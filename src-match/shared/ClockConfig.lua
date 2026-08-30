--!strict
-- Relógio do turno: o ciclo de horário que cabe nos ShiftConfig.Duration segundos de um turno, e o
-- que o HUD desenha dele. A hora corre linear da primeira marca até EndHour; o texto salta de marca
-- em marca, o ponteiro e a cor de fundo andam contínuos entre elas.
local ClockConfig = {}

-- Marcas do ciclo, na ordem em que passam. Hora em 24h, e hora menor ou igual à anterior é do dia
-- seguinte — 22, 23, 1, 3, 6 é uma noite só. `Color` vai para Background_01.BackgroundColor3.
ClockConfig.Marks = {
	{ Hour = 22, Color = Color3.fromRGB(60, 96, 168) },
	{ Hour = 23, Color = Color3.fromRGB(40, 62, 130) },
	{ Hour = 1, Color = Color3.fromRGB(22, 32, 82) },
	{ Hour = 3, Color = Color3.fromRGB(46, 40, 96) },
	{ Hour = 6, Color = Color3.fromRGB(226, 146, 92) },
}

-- Hora em que o ciclo termina, junto com o turno. Uma hora depois da última marca de propósito:
-- terminando em cima dela, 06:00 apareceria por um quadro só antes da virada.
ClockConfig.EndHour = 7

-- Ponteiro como ponteiro de horas de mostrador de 12h: 30° por hora dá a volta em 12 e põe 22:00 em
-- 300° e 06:00 em 180°. Mostrador que não seja relógio — arco de noite, meia-lua — muda os dois.
ClockConfig.DegreesPerHour = 30
ClockConfig.PointerOffsetAngle = 0

-- Segundos entre dois redesenhos. Com o padrão o ponteiro anda ~1°/s: redesenhar todo quadro
-- gastaria sem mover pixel.
ClockConfig.UpdateInterval = 0.1

-- Hora em 12h com o período, e o número do turno.
ClockConfig.HourFormat = "%dh %s"
ClockConfig.ShiftFormat = "Shift %d"

-- Marcas com a hora já contínua e a hora final na mesma contagem: 22, 23, 25, 27, 30 e 31 para a
-- noite de 22:00 às 07:00. É essa lista que o HUD percorre; a de cima existe para ser editada com a
-- hora do relógio, não com a soma.
function ClockConfig.Cycle()
	local cycle = {}
	local previous

	for _, mark in ipairs(ClockConfig.Marks) do
		local hour = mark.Hour
		while previous and hour <= previous do
			hour += 24
		end
		table.insert(cycle, { Hour = hour, Color = mark.Color })
		previous = hour
	end

	local endHour = ClockConfig.EndHour
	while previous and endHour <= previous do
		endHour += 24
	end

	return cycle, endHour
end

function ClockConfig.Format(hour: number): string
	local hour24 = math.floor(hour) % 24
	local hour12 = hour24 % 12
	if hour12 == 0 then
		hour12 = 12
	end
	return string.format(ClockConfig.HourFormat, hour12, if hour24 < 12 then "AM" else "PM")
end

return ClockConfig
