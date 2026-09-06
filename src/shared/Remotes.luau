--[[
	Remotes — dibuat oleh server, ditunggu oleh client.

	Empat remote. Setiap remote tambahan adalah permukaan serangan tambahan,
	jadi jangan tambah sebelum benar-benar butuh.

	Rebirth sengaja tanpa argumen sama sekali. Tidak ada yang perlu dikirim
	client - server sudah tahu siapa pemanggilnya, berapa rebirth-nya, dan
	apakah kolamnya kosong.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = { "DigRequest", "BuyUpgrade", "Rebirth", "Notify" }

local Remotes = {}

if RunService:IsServer() then
	local folder = ReplicatedStorage:FindFirstChild("Net")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Net"
		folder.Parent = ReplicatedStorage
	end

	for _, name in NAMES do
		local remote = folder:FindFirstChild(name)
		if not remote then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
		Remotes[name] = remote
	end
else
	local folder = ReplicatedStorage:WaitForChild("Net")
	for _, name in NAMES do
		Remotes[name] = folder:WaitForChild(name)
	end
end

return Remotes
