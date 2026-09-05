-- Dica de tecla no canto: MainGui.Frame_Info diz que teclas agem no que está em uso. Só em teclado
-- — no toque quem manda é o painel do MobileHud, e lá o botão já é a própria ação.
-- É lembrete, não HUD: entra quando o item chega à mão e sai sozinha depois de HINT_TIME, com o
-- item ainda lá. Guardar o item também a tira, antes do prazo.
local KeyHint = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Caminho no place: PlayerGui.MainGui.Frame_Info.Frame.{Text, Input}. Input guarda as plaquinhas,
-- uma por tecla, cada uma chamada Key, com o glifo em Frame.Key e a chapa em Frame.RoundFrame. A
-- primeira vem autorada e nunca
-- morre; as outras são clones dela.
local GUI_NAME = "MainGui"
local FRAME_NAME = "Frame_Info"
local ROW_NAME = "Frame"
local TEXT_NAME = "Text"
local SLOT_NAME = "Input"
local CHIP_NAME = "Key"
local GLYPH_PATH = { "Frame", "Key" }
local PLATE_PATH = { "Frame", "RoundFrame" }

-- Cor da chapa enquanto o que a tecla comanda está ligado. A de repouso não está aqui: sai do
-- place, lida no Start, então recolorir a chapa no Studio continua valendo.
local LIT_COLOR = Color3.fromRGB(203, 203, 203)

local WAIT_TIMEOUT = 20 -- segundos esperando a GUI publicada no PlayerGui
local HINT_TIME = 20 -- segundos de dica na tela antes de sair sozinha

local player = Players.LocalPlayer

local panel
local holder
local title
local template
local restColor
local slots = {}
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

-- Enquanto o item estiver na mão a dica pode voltar, então o prazo é reiniciado a cada chamada.
-- `keys` é um KeyCode ou uma lista deles, na ordem em que aparecem na linha.
function KeyHint.Show(text, keys)
	if not (panel and UserInputService.KeyboardEnabled) then
		return
	end

	-- Sai do KeyCode, não de um rótulo à mão: o teclado do jogador decide que letra é aquela tecla,
	-- e a página do GetStringForKeyCode não descreve o retorno. Medido: `Q` devolve "Q" e as teclas
	-- sem letra, como `LeftControl`, devolvem "" — essas não têm o que desenhar aqui.
	local faces = {}
	for _, keyCode in ipairs(if type(keys) == "table" then keys else { keys }) do
		local face = UserInputService:GetStringForKeyCode(keyCode)
		if face == "" then
			warn("[KeyHint] tecla sem rótulo: " .. tostring(keyCode))
			return
		end
		table.insert(faces, face)
	end
	if #faces == 0 then
		return
	end

	resize(#faces)
	for index, face in ipairs(faces) do
		local mark = glyphOf(slots[index])
		if mark then
			mark.Text = face
		end
		KeyHint.SetOn(false, index)
	end
	title.Text = text
	panel.Visible = true

	token += 1
	local stamp = token
	task.delay(HINT_TIME, function()
		if token == stamp then
			panel.Visible = false
		end
	end)
end

-- A chapa da tecla acompanha o estado do que ela comanda: acesa em LIT_COLOR, apagada na cor que
-- veio do place. Sem índice, é a primeira plaquinha da linha.
function KeyHint.SetOn(value, index)
	local slot = slots[index or 1]
	local plate = slot and plateOf(slot)
	if plate and restColor then
		plate.BackgroundColor3 = if value then LIT_COLOR else restColor
	end
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
	local label = found and found:FindFirstChild(TEXT_NAME)
	local box = found and found:FindFirstChild(SLOT_NAME)
	local first = box and box:FindFirstChild(CHIP_NAME)

	if not (label and label:IsA("TextLabel") and first and glyphOf(first)) then
		warn("[KeyHint] " .. GUI_NAME .. "." .. FRAME_NAME .. "." .. ROW_NAME .. " incompleto; sem dica de tecla.")
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
	title = label
	panel.Visible = false
end

return KeyHint
