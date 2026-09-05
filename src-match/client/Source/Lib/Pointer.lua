-- Ponteiro e gesto de tecla para GUI de mundo. O ponteiro é DESENHADO por nós: a referência do
-- MouseIcon diz que o ícone é ignorado enquanto o cursor está sobre botão de GUI, e os cursores de
-- sistema só valem em plugin. Um ScreenGui seguindo o mouse não depende de nenhum dos dois.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Pointer = {}

-- Desenho do ponteiro: asset, lado em pixels e ordem acima das telas do jogo.
local CURSOR_NAME = "WorldCursor"
local CURSOR_IMAGE = "rbxassetid://284663799"
local CURSOR_SIZE = 32
local CURSOR_ORDER = 100

-- Apertar e soltar valem para todo aparelho: InputBegan e InputEnded do GuiObject trazem o dedo e o
-- mouse pelo mesmo caminho. MouseButton1Down/Up e MouseEnter/Leave são de mouse — no celular a tecla
-- ficava muda.
local POINTERS = {
	[Enum.UserInputType.MouseButton1] = true,
	[Enum.UserInputType.Touch] = true,
}

local cursorGui = nil
local cursorPointer = nil
local cursorMove = nil
local hovering = 0

local function build()
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if cursorGui or not playerGui then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = CURSOR_NAME
	gui.ResetOnSpawn = false
	gui.DisplayOrder = CURSOR_ORDER
	gui.Enabled = false

	local image = Instance.new("ImageLabel")
	image.Name = "Pointer"
	image.BackgroundTransparency = 1
	-- Sem âncora no centro: o ponto de contato do ponteiro é o canto superior esquerdo do desenho, e
	-- centrar deixaria o clique caindo abaixo da ponta.
	image.AnchorPoint = Vector2.zero
	image.Size = UDim2.fromOffset(CURSOR_SIZE, CURSOR_SIZE)
	image.Image = CURSOR_IMAGE
	image.Parent = gui

	gui.Parent = playerGui
	cursorGui = gui
	cursorPointer = image
end

function Pointer.Hide()
	hovering = 0
	if cursorMove then
		cursorMove:Disconnect()
		cursorMove = nil
	end
	if cursorGui then
		cursorGui.Enabled = false
	end
	UserInputService.MouseIconEnabled = true
end

function Pointer.Show()
	-- Sem mouse não há ponteiro a desenhar, e esconder o ícone do sistema não teria o que esconder.
	if not UserInputService.MouseEnabled then
		return
	end

	build()
	if not cursorGui then
		return
	end

	local mouse = Players.LocalPlayer:GetMouse()
	local function follow()
		cursorPointer.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	end

	follow()
	cursorGui.Enabled = true
	UserInputService.MouseIconEnabled = false

	cursorMove = mouse.Move:Connect(follow)
end

function Pointer.Drop()
	Pointer.Hide()
	if cursorGui then
		cursorGui:Destroy()
		cursorGui = nil
		cursorPointer = nil
	end
end

-- Soltar longe da tecla não chega ao objeto — arrastar para fora e largar deixaria o gesto preso.
-- Quem vê isso é o serviço, e daí as duas escutas do fim. O trinco `held` é o que impede a de fora
-- de soltar tecla que ninguém apertou: sem ele, todo dedo levantado na tela mexeria em todas.
function Pointer.Press(object, press, release, links)
	local held = false

	table.insert(links, object.InputBegan:Connect(function(input)
		if POINTERS[input.UserInputType] and not held then
			held = true
			press()
		end
	end))

	local function finish(input)
		if POINTERS[input.UserInputType] and held then
			held = false
			release()
		end
	end

	table.insert(links, object.InputEnded:Connect(finish))
	table.insert(links, UserInputService.InputEnded:Connect(finish))
end

-- Contar quantos alvos estão sob o ponteiro, em vez de esconder no primeiro MouseLeave: passando
-- direto de um botão para o vizinho, a saída de um chega depois da entrada do outro e apagaria o
-- cursor com o mouse ainda em cima.
-- Só de mouse: dedo não paira, e o ponteiro desenhado não existe fora dele.
function Pointer.Hover(object, links)
	table.insert(links, object.MouseEnter:Connect(function()
		hovering += 1
		Pointer.Show()
	end))
	table.insert(links, object.MouseLeave:Connect(function()
		hovering = math.max(0, hovering - 1)
		if hovering == 0 then
			Pointer.Hide()
		end
	end))
end

return Pointer
