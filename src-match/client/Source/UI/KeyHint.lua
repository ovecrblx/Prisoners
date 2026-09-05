-- Dica de tecla no canto: MainGui.Frame_Info.Input diz qual tecla age no item que está na mão. Só
-- em teclado — no toque quem manda é o painel do MobileHud, e lá o botão já é a própria ação.
-- É lembrete, não HUD: entra quando o item chega à mão e sai sozinha depois de HINT_TIME, com o
-- item ainda lá. Guardar o item também a tira, antes do prazo.
local KeyHint = {}

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Caminho no place: PlayerGui.MainGui.Frame_Info.Input.{Text, InputFrame.Frame.Key}.
local GUI_NAME = "MainGui"
local FRAME_NAME = "Frame_Info"
local ROW_NAME = "Input"
local TEXT_NAME = "Text"
local KEY_PATH = { "InputFrame", "Frame", "Key" }

local WAIT_TIMEOUT = 20 -- segundos esperando a GUI publicada no PlayerGui
local HINT_TIME = 20 -- segundos de dica na tela antes de sair sozinha

local player = Players.LocalPlayer

local row
local title
local glyph
local token = 0

local function labelIn(root, path)
	local node = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	if node and (node:IsA("TextLabel") or node:IsA("TextButton")) then
		return node
	end
	return nil
end

-- Enquanto o item estiver na mão a dica pode voltar, então o prazo é reiniciado a cada chamada.
function KeyHint.Show(text, keyCode)
	if not (row and UserInputService.KeyboardEnabled) then
		return
	end

	-- Sai do KeyCode, não de um rótulo à mão: o teclado do jogador decide que letra é aquela tecla,
	-- e a página do GetStringForKeyCode não descreve o retorno. Medido: `Q` devolve "Q" e as teclas
	-- sem letra, como `LeftControl`, devolvem "" — essas não têm o que desenhar aqui.
	local face = UserInputService:GetStringForKeyCode(keyCode)
	if face == "" then
		warn("[KeyHint] tecla sem rótulo: " .. tostring(keyCode))
		return
	end

	glyph.Text = face
	title.Text = text
	row.Visible = true

	token += 1
	local mark = token
	task.delay(HINT_TIME, function()
		if token == mark then
			row.Visible = false
		end
	end)
end

function KeyHint.Hide()
	token += 1
	if row then
		row.Visible = false
	end
end

function KeyHint.Start()
	local playerGui = player:WaitForChild("PlayerGui", WAIT_TIMEOUT)
	local gui = playerGui and playerGui:WaitForChild(GUI_NAME, WAIT_TIMEOUT)
	local frame = gui and gui:WaitForChild(FRAME_NAME, WAIT_TIMEOUT)
	local found = frame and frame:WaitForChild(ROW_NAME, WAIT_TIMEOUT)

	title = found and labelIn(found, { TEXT_NAME })
	glyph = found and labelIn(found, KEY_PATH)

	if not (title and glyph) then
		warn("[KeyHint] " .. GUI_NAME .. "." .. FRAME_NAME .. "." .. ROW_NAME .. " incompleto; sem dica de tecla.")
		return
	end

	row = found
	row.Visible = false
end

return KeyHint
