-- Teclado e visor do telefone, montados só na tela de quem está na linha. O número digitado não sai
-- daqui: o servidor guarda apenas quem atendeu, e o visor é peça de mundo escrita localmente — quem
-- assiste vê o texto autorado, e o aparelho é pequeno demais para que isso apareça de longe.
-- Nada é resolvido no boot: com streaming as teclas vão e voltam como instâncias novas, então cada
-- chamada refaz a ligação e devolve o que mudou ao largar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PhoneConfig = require(Shared:WaitForChild("PhoneConfig"))
-- Só pela duração do tom de linha, que é onde a voz emenda: o número mora na chave que o publica, e
-- uma segunda cópia dele aqui é como os dois lados divergem em silêncio.
local SfxConfig = require(Shared:WaitForChild("SfxConfig"))
local Lib = script.Parent.Parent:WaitForChild("Lib")
local Pointer = require(Lib:WaitForChild("Pointer"))
local Sfx = require(Lib:WaitForChild("Sfx"))

local PhoneDial = {}

-- Curso da tecla: uma perna só. A página do TweenInfo não descreve `Reverses`; medido, ele devolve a
-- peça à pose em que o tween começou e fecha em 2x `Time`.
local KEY_TWEEN = TweenInfo.new(PhoneConfig.KeyTravel, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true)

local links = {}
local homes = {}
local queries = {}
local tweens = {}

local screen
local label
local framing
local quitting
local labelHome
local calling
local waiting
local digits = ""
local typing = false
local touched = false
local lastKey = 0
local token = 0

local function hush()
	if waiting then
		waiting:Destroy()
		waiting = nil
	end
end

local function span(region)
	return region.Max - region.Min
end

-- O tom de espera entra quando o som que o antecede acaba: tirar do gancho no começo, o número
-- abandonado ou recusado no recomeço. `touched` cobre a tecla apertada ANTES do prazo vencer — sem
-- ele o tom nasceria já cancelado, tocando para sempre.
local function waitTone(mark, delay)
	task.delay(delay, function()
		if token == mark and not touched then
			hush()
			waiting = Sfx.Hold("PhoneWaiting", screen)
		end
	end)
end

-- O som da chamada é um só de cada vez: o chamando em laço, depois a fala de quem atendeu.
local function silence()
	if calling then
		calling:Destroy()
		calling = nil
	end
end

-- A vista do número cheio é do PhoneController: daqui sai só o aviso de que o campo encheu, e o de
-- que ele recomeçou. Requerer o controlador aqui fecharia ciclo — é ele que requer este módulo.
local function frame(active)
	if framing then
		framing(active)
	end
end

local function render(text)
	if label and label.Parent then
		label.Text = text
	end
end

-- O campo tem sempre `Digits` casas: o que já foi digitado, o cursor na casa da vez, e o resto
-- fechado. Cheio, o cursor sai e sobra só o número.
local function field(caret)
	local left = PhoneConfig.Digits - #digits
	if left <= 0 then
		return digits
	end

	return digits
		.. (if caret then PhoneConfig.CaretChar else " ")
		.. string.rep(PhoneConfig.SlotChar, left - 1)
end

-- Campo de digitação: fica aqui até o número encher, e devolve `false` se a chamada morreu no meio.
-- Parar com número pela metade não sai daqui — o aparelho zera o campo, avisa, e a espera recomeça.
local function enter(mark)
	typing = true
	local lit = true
	local blink = PhoneConfig.CaretBlink

	while token == mark and #digits < PhoneConfig.Digits do
		render(field(lit))
		lit = not lit

		-- A espera do prazo é encurtada pela piscada, senão o abandono chegaria com o atraso de uma
		-- perna inteira — até meio segundo depois dos 3s.
		local pause = blink.Min + math.random() * (blink.Max - blink.Min)
		if #digits > 0 then
			pause = math.min(pause, math.max(0, lastKey + PhoneConfig.EntryTimeout - os.clock()))
		end
		task.wait(pause)

		-- Campo vazio não expira: não há tentativa a abandonar.
		if #digits > 0 and os.clock() - lastKey >= PhoneConfig.EntryTimeout then
			digits = ""
			touched = false
			hush()
			Sfx.Play("PhoneReset", screen)
			waitTone(mark, span(SfxConfig.PhoneReset.Region))
		end
	end

	typing = false
	return token == mark
end

local function confirm(mark)
	for _ = 1, PhoneConfig.ConfirmBlinks do
		render("")
		task.wait(PhoneConfig.ConfirmBlink)
		render(digits)
		task.wait(PhoneConfig.ConfirmBlink)
		if token ~= mark then
			return false
		end
	end
	return true
end

-- Discagem: o tom abre, o chamando entra em laço, e o veredito vem quando o prazo fecha.
local function dial(mark)
	Sfx.Play("PhoneDialTone", screen)
	task.delay(span(SfxConfig.PhoneDialTone.Region), function()
		if token == mark then
			calling = Sfx.Hold("PhoneVoice", screen)
		end
	end)

	local dots = 0
	local deadline = os.clock() + PhoneConfig.CallingHold
	while token == mark and os.clock() < deadline do
		dots = dots % PhoneConfig.CallingDots + 1
		render(PhoneConfig.CallingText .. string.rep(".", dots))
		task.wait(math.min(PhoneConfig.CallingStep, math.max(0, deadline - os.clock())))
	end

	return token == mark
end

-- A fala do outro lado, do começo ao fim dela. `Ended` é quem avisa — medido, ele dispara também no
-- fim da Region, mas NÃO dispara em Destroy: por isso o token entra no laço, senão desligar no meio
-- prenderia esta corrotina esperando um aviso que não vem. O teto cobre o asset que não carrega.
local function speak(mark, key)
	calling = Sfx.Hold(key, screen)
	if not calling then
		return token == mark
	end

	local ended = false
	calling.Ended:Once(function()
		ended = true
	end)

	local deadline = os.clock() + PhoneConfig.SpeechCap
	while token == mark and not ended and os.clock() < deadline do
		task.wait(PhoneConfig.CallingStep)
	end

	silence()
	return token == mark
end

-- Linha que ENTROU já começa conectada; a de saída abre no cartão de data. Dos dois jeitos, quando
-- a fala acaba o aparelho volta ao campo de digitação: chamada encerrada não prende o teclado.
local function run(mark, caller)
	if caller then
		render(caller.Title)
		if not speak(mark, caller.Sound) then
			return
		end
		digits = ""
		touched = false
		waitTone(mark, 0)
	else
		render(PhoneConfig.DateText)
		task.wait(PhoneConfig.DateHold)
	end

	while token == mark do
		if not enter(mark) then
			return
		end
		frame(true)
		if not confirm(mark) then
			return
		end

		local number = digits
		if not dial(mark) then
			return
		end
		silence()

		local listed = PhoneConfig.Directory[number]
		if listed then
			render(listed.Title)
			if not speak(mark, listed.Sound) then
				return
			end
		else
			render(PhoneConfig.UnknownText)
			task.wait(PhoneConfig.UnknownHold)
			if token ~= mark then
				return
			end
		end

		digits = ""
		touched = false
		frame(false)
		waitTone(mark, 0)
	end
end

-- Um curso por tecla: o anterior é cancelado, senão dois tweens brigam pela mesma CFrame e o
-- segundo toma a pose afundada como repouso, afundando a tecla de vez.
local function press(part, glyph)
	touched = true
	lastKey = os.clock()
	hush()

	local home = homes[part]
	if home then
		if tweens[part] then
			tweens[part]:Cancel()
		end
		local sink = TweenService:Create(part, KEY_TWEEN, { CFrame = home * CFrame.new(0, -PhoneConfig.KeyDepth, 0) })
		tweens[part] = sink
		sink:Play()
	end

	if glyph == PhoneConfig.QuitName then
		Sfx.Play(PhoneConfig.QuitSound, part)
		if quitting then
			quitting()
		end
		return
	end

	Sfx.Play(PhoneConfig.KeySounds[glyph], part)

	if not (typing and string.match(glyph, "^%d$")) or #digits >= PhoneConfig.Digits then
		return
	end

	digits ..= glyph
	render(field(true))
end

-- Clique em GUI de mundo sai de um raio do mouse contra a peça adornada, e as teclas são publicadas
-- com CanQuery desligado — o raio atravessa e nenhum botão recebe nada. Escrita local, devolvida ao
-- largar: `Active` da SurfaceGui já vem ligado (medido), então só a consulta falta.
local function bindPad(pad)
	for _, part in ipairs(pad:GetChildren()) do
		local button = part:IsA("BasePart") and part:FindFirstChildWhichIsA("GuiButton", true)
		if button and (PhoneConfig.KeySounds[part.Name] or part.Name == PhoneConfig.QuitName) then
			local glyph = part.Name
			homes[part] = part.CFrame
			queries[part] = part.CanQuery
			part.CanQuery = true

			Pointer.Press(button, function()
				press(part, glyph)
			end, function() end, links)
			Pointer.Hover(button, links)
		end
	end
end

function PhoneDial.Open(model, caller, onFrame, onQuit)
	PhoneDial.Close()

	local pad = PhoneConfig.Child(model, PhoneConfig.PadName)
	screen = PhoneConfig.Child(model, PhoneConfig.ScreenName)
	label = screen
		and (screen:FindFirstChildWhichIsA("TextLabel", true) or screen:FindFirstChildWhichIsA("TextButton", true))
	labelHome = label and label.Text

	if not (pad and label) then
		warn("[PhoneDial] " .. model:GetFullName() .. " sem teclado ou visor; a chamada fica muda.")
		return
	end

	token += 1
	digits = ""
	touched = false
	framing = onFrame
	quitting = onQuit
	bindPad(pad)

	local mark = token

	-- Só a linha de saída espera o tom: quem atendeu já tem alguém falando do outro lado.
	if not caller then
		waitTone(mark, span(SfxConfig.PhonePick.Region))
	end

	task.spawn(function()
		run(mark, caller)
	end)
end

function PhoneDial.Close()
	token += 1
	typing = false
	touched = false
	framing = nil
	quitting = nil
	hush()

	silence()

	for _, link in ipairs(links) do
		link:Disconnect()
	end
	table.clear(links)
	Pointer.Drop()

	-- O tween não morre com a conexão: sem cancelar, uma tecla no meio do curso continua escrevendo
	-- por cima da pose devolvida aqui.
	for _, tween in pairs(tweens) do
		tween:Cancel()
	end
	table.clear(tweens)

	for part, home in pairs(homes) do
		if part.Parent then
			part.CFrame = home
		end
	end
	table.clear(homes)

	for part, query in pairs(queries) do
		if part.Parent then
			part.CanQuery = query
		end
	end
	table.clear(queries)

	if label and label.Parent and labelHome then
		label.Text = labelHome
	end

	screen = nil
	label = nil
	labelHome = nil
	digits = ""
end

return PhoneDial
