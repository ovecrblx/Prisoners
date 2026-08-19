--!strict
-- Find-or-create da pasta ReplicatedStorage.Remotes e dos eventos, num lugar só.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	return folder :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	local folder = getFolder()
	local event = folder:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
	return event :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	local folder = getFolder()
	local fn = folder:FindFirstChild(name)
	if not fn then
		fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
	end
	return fn :: RemoteFunction
end

return Remotes
