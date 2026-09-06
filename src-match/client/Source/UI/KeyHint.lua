-- Dica de tecla no canto: MainGui.Frame_Info diz que teclas agem no que está em uso. Só fora do
-- aparelho de toque, e só com teclado: no toque quem manda é a MobileGui, e lá o botão já é a
-- própria ação. Quem decide de quem é a vez é MobileHud.IsMobile, para as duas GUIs nunca
-- aparecerem juntas nem sumirem juntas.
-- Duas vidas, e quem chama escolhe. `Show` é lembrete: entra quando o item chega à mão e sai sozinha
-- depois de HINT_TIME, com o item ainda lá; guardar o item também a tira, antes do prazo. `Pin` é
-- painel: fica enquanto a cena durar, e só `Hide` a tira.
local KeyHint = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local MobileHud = require(script.Parent:WaitForChild("MobileHud"))

-- Caminho no place: PlayerGui.MainGui.Frame_Info.Frame.Input. Input guarda as plaquinhas, uma por
-- tecla, cada uma chamada Key. Dentro da plaquinha: `Text` é o rótulo DAQUELA tecla, `Frame.Key` o
-- glifo e `Frame.RoundFrame` a chapa. A primeira vem autorada e nunca morre; as outras são clones
-- dela, então o rótulo, o glifo e a chapa vêm juntos no clone.
local GUI_NAME = "MainGui"
local FRAME_NAME = "Frame_Info"
local ROW_NAME = "Frame"
local SLOT_NAME = "Input"
local CHIP_NAME = "Key"
local LABEL_NAME = "Text"
local GLYPH_PATH = { "Frame", "Key" }
local PLATE_PATH = { "Frame", "RoundFrame" }

-- Cor da chapa enquanto o que a tecla comanda está ligado. A de repouso não está aqui: sai do
-- place, lida no Start, então recolorir a chapa no Studio continua valendo.
local LIT_COLOR = Color3.fromRGB(203, 203, 203)

local WAIT_TIMEOUT = 20 -- segundos esperando a GUI publicada no PlayerGui
local HINT_TIME = 20 -- segundos de dica na tela antes de sair sozinha
local FLASH_TIME = 0.12 -- segundos de chapa acesa a cada piscada

local player = Players.LocalPlayer

local panel
local holder
local template
local restColor
local slots = {}
local flashes = {}
local token = 0

local function nodeIn(root, path)
	local node = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function glyphOf(slot)
	local node = nodeIn(slot, GLYPH_PATH)
	return if node and node:IsA("TextLabel") then node else nil
end

local function plateOf(slot)
	local node = nodeIn(slot, PLATE_PATH)
	return if node and node:IsA("GuiObject") then node else nil
end

local function labelOf(slot)
	local node = slot:FindFirstChild(LABEL_NAME)
	return if node and node:IsA("TextLabel") then node else nil
end

-- LayoutOrder acompanha a ordem da chamada porque o UIListLayout do Input ordena por ela.
local function resize(count)
	for index = #slots + 1, count do
		local extra = template:Clone()
		extra.LayoutOrder = template.LayoutOrder + index - 1
		extra.Parent = holder
		slots[index] = extra
	end
	for index = #slots, count + 1, -1 do
		slots[index]:Destroy()
		slots[index] = nil
	end
end

-- Desenha a linha e devolve se ela entrou. `entries` é uma lista de { key = KeyCode, text = string },
-- na ordem em que aparecem, ou uma só dessas tabelas quando a ação tem uma tecla apenas.
local function draw(entries)
	if not (panel and UserInputService.KeyboardEnabled) or MobileHud.IsMobile() then
		return false
	end

	local list = if entries.key then { entries } else entries

	-- O glifo sai do KeyCode, não de um rótulo à mão: o teclado do jogador decide que letra é aquela
	-- tecla, e a página do GetStringForKeyCode não descreve o retorno. Medido: `Q` devolve "Q" e as
	-- teclas sem letra, como `LeftControl`, devolvem "" — essas não têm o que desenhar aqui.
	local faces = {}
	for _, entry in ipairs(list) do
		local face = UserInputService:GetStringForKeyCode(entry.key)
		if face == "" then
			warn("[KeyHint] tecla sem rótulo: " .. tostring(entry.key))
			return false
		end
		table.insert(faces, face)
	end
	if #faces == 0 then
		return false
	end

	resize(#faces)
	for index, face in ipairs(faces) do
		local slot = slots[index]
		local mark = glyphOf(slot)
		if mark then
			mark.Text = face
		end
		local label = labelOf(slot)
		if label then
			label.Text = list[index].text or ""
		end
		KeyHint.SetOn(false, index)
	end

	panel.Visible = true
	return true
end

-- Lembrete: entra e sai sozinha depois de HINT_TIME, com o item ainda na mão. Enquanto ele estiver
-- lá a dica pode voltar, então o prazo é reiniciado a cada chamada.
function KeyHint.Show(entries)
	if not draw(entries) then
		return
	end

	token += 1
	local stamp = token
	task.delay(HINT_TIME, function()
		if token == stamp then
			panel.Visible = false
		end
	end)
end

-- Dica que FICA. Quem chama é dono de uma cena que dura — a gaveta em uso, com a câmera presa nela —
-- e ali as teclas são o painel de controle, não um lembrete: some quando a cena acaba, e é `Hide`
-- quem a tira. O passo do token cancela um prazo pendente de um `Show` anterior, senão ele apagaria
-- a linha fixada no meio da cena.
function KeyHint.Pin(entries)
	if not draw(entries) then
		return
	end

	token += 1
end

-- A chapa da tecla acompanha o estado do que ela comanda: acesa em LIT_COLOR, apagada na cor que
-- veio do place. Sem índice, é a primeira plaquinha da linha.
function KeyHint.SetOn(value, index)
	local at = index or 1
	flashes[at] = (flashes[at] or 0) + 1
	local slot = slots[at]
	local plate = slot and plateOf(slot)
	if plate and restColor then
		plate.BackgroundColor3 = if value then LIT_COLOR else restColor
	end
end

-- Piscada de uma tecla: acende a chapa e devolve a cor de repouso sozinha. Toque em cima de toque
-- reinicia o prazo em vez de empilhar, e um SetOn no meio cancela a devolução pendente.
function KeyHint.Flash(index)
	if not (panel and panel.Visible) then
		return
	end
	local at = index or 1
	KeyHint.SetOn(true, at)
	local stamp = flashes[at]
	task.delay(FLASH_TIME, function()
		if flashes[at] == stamp then
			KeyHint.SetOn(false, at)
		end
	end)
end

-- Quem apaga o HUD em volta precisa poupar esta linha, e a identifica por instância.
function KeyHint.Panel()
	return panel
end

function KeyHint.Hide()
	token += 1
	if panel then
		panel.Visible = false
	end
end

function KeyHint.Start()
	local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
	local gui = playerGui and playerGui:WaitForChild(GUI_NAME, WAIT_TIMEOUT)
	local frame = gui and gui:WaitForChild(FRAME_NAME, WAIT_TIMEOUT)
	local found = frame and frame:WaitForChild(ROW_NAME, WAIT_TIMEOUT)
	local box = found and found:FindFirstChild(SLOT_NAME)
	local first = box and box:FindFirstChild(CHIP_NAME)

	if not (first and glyphOf(first) and labelOf(first)) then
		warn(
			"[KeyHint] "
				.. GUI_NAME
				.. "."
				.. FRAME_NAME
				.. "."
				.. ROW_NAME
				.. "."
				.. SLOT_NAME
				.. "."
				.. CHIP_NAME
				.. " incompleto; sem dica de tecla."
		)
		return
	end

	local plate = plateOf(first)
	restColor = plate and plate.BackgroundColor3

	template = first:Clone()
	slots[1] = first
	first.Visible = true
	box.Visible = true
	found.Visible = true

	panel = frame
	holder = box
	panel.Visible = false

	-- O aparelho muda em partida: teclado pareado num tablet, e o botão do emulador no Studio. Virou
	-- toque, a MobileGui assume e esta linha sai na hora, sem esperar o prazo.
	for _, name in ipairs({ "TouchEnabled", "MouseEnabled", "KeyboardEnabled" }) do
		UserInputService:GetPropertyChangedSignal(name):Connect(function()
			if MobileHud.IsMobile() then
				KeyHint.Hide()
			end
		end)
	end
end

return KeyHint
