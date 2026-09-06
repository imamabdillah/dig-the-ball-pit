--[[
	PlayerData — profil pemain, DI MEMORI SAJA.

	Minggu 1 sengaja tanpa DataStore. Progres hilang saat pemain keluar,
	dan itu benar untuk sekarang: gerbang minggu 1 hanya menanyakan apakah
	loopnya enak selama 10 menit.

	ProfileStore dan session locking masuk di minggu 2 (jebakan #3).
	Jangan pakai DataStore mentah di sana — tanpa session lock, pemain
	menggandakan mata uang dengan join dua server sekaligus.

	Struktur di bawah sudah dibentuk agar minggu 2 tinggal mengganti
	newProfile() dengan profile yang dimuat, tanpa menyentuh service lain.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PlayerData = {}

local profiles = {}

local function newProfile()
	return {
		-- disimpan nanti
		cash = 0,
		bag = 0,
		levels = { tool = 1, bag = 1, wall = 1 },
		ballsDug = 0,

		-- pembukuan anti-spam, tidak pernah dikirim ke client
		lastDig = 0,
		windowStart = 0,
		windowCount = 0,
	}
end

function PlayerData.get(player: Player)
	return profiles[player]
end

--[[
	Dorong keadaan ke atribut Player. Atribut tereplikasi otomatis, jadi
	HUD tidak butuh remote sama sekali.

	Yang didorong hanya nilai yang memang boleh dilihat client. Pembukuan
	rate limit tetap di server — kalau client tahu jendelanya, client bisa
	mengatur waktunya.
]]
function PlayerData.sync(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	player:SetAttribute("Cash", math.floor(profile.cash))
	player:SetAttribute("Bag", math.floor(profile.bag))
	player:SetAttribute("BallsDug", profile.ballsDug)

	player:SetAttribute("ToolLevel", profile.levels.tool)
	player:SetAttribute("BagLevel", profile.levels.bag)
	player:SetAttribute("WallLevel", profile.levels.wall)

	player:SetAttribute("BallsPerDig", Config.levelValue("tool", profile.levels.tool))
	player:SetAttribute("BagCapacity", Config.levelValue("bag", profile.levels.bag))
	player:SetAttribute("WallReduction", Config.levelValue("wall", profile.levels.wall))
end

function PlayerData.add(player: Player)
	profiles[player] = newProfile()
	PlayerData.sync(player)
end

function PlayerData.remove(player: Player)
	profiles[player] = nil
end

Players.PlayerAdded:Connect(PlayerData.add)
Players.PlayerRemoving:Connect(PlayerData.remove)

-- Pemain yang sudah join sebelum modul ini sempat berjalan.
for _, player in Players:GetPlayers() do
	if not profiles[player] then
		PlayerData.add(player)
	end
end

return PlayerData
