-- Find-or-create da pasta ReplicatedStorage.Remotes e dos remotes, num lugar só. Nenhum remote
-- é declarado no project file: quem precisa de um o cria no Init, então remote sem dono some do
-- place junto com o código que o criava.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local function build(className, name)
	local folder = Remotes.Folder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
	end
	return remote
end

function Remotes.Folder()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	return folder
end

function Remotes.Event(name)
	return build("RemoteEvent", name)
end

function Remotes.Function(name)
	return build("RemoteFunction", name)
end

return Remotes
