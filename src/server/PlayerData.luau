--[[
	PlayerData - profil pemain.

	Minggu 2 memisahkan profil jadi dua bagian dengan tegas:

	  profile.data     yang disimpan. Bentuknya dibuat persis seperti yang
	                   akan dituliskan ke penyimpanan, jadi memasang
	                   ProfileStore nanti tidak menyentuh service lain.

	  profile.session  yang tidak pernah disimpan: pembukuan rate limit,
	                   penanda waktu, kantong yang sedang dibawa.

	Kantong sengaja masuk sesi, bukan data. Kalau kantong ikut tersimpan,
	pemain bisa keluar dengan kantong penuh dan masuk lagi ke server lain
	untuk menjualnya dua kali. Bola dalam kantong adalah bola yang sudah
	keluar dari kolam tapi belum jadi cash - satu-satunya tempat aman
	untuk keadaan itu adalah sesi yang mati bersama servernya.

	Penyimpanan sungguhan menyusul dengan ProfileStore. Sebelum itu
	terpasang, profil masih hilang saat keluar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PlayerData = {}

local profiles = {}

function PlayerData.newData()
	return {
		cash = 0,
		gems = 0,
		levels = { tool = 1, bag = 1, wall = 1 },
		rebirths = 0,

		-- statistik seumur akun, dipakai leaderboard nanti
		ballsDug = 0,
		pitsCleared = 0,
		bestClearSeconds = 0,
	}
end

local function newSession()
	return {
		bag = 0,

		-- pembukuan anti-spam, tidak pernah dikirim ke client
		lastDig = 0,
		windowStart = 0,
		windowCount = 0,

		-- Penanda waktu untuk log gerbang. Gerbang minggu 2 menuntut satu
		-- sesi panjang dengan tiap pembelian ditandai, dan mencatatnya
		-- otomatis jauh lebih dapat dipercaya daripada mengingat sambil main.
		sessionStart = os.clock(),
	}
end

function PlayerData.get(player: Player)
	return profiles[player]
end

-- Pengali cash dari rebirth. Kumulatif dan permanen.
function PlayerData.cashMultiplier(profile): number
	return 1 + profile.data.rebirths * Config.Rebirth.CashMultiplierPerRebirth
end

--[[
	Dorong keadaan ke atribut Player. Atribut tereplikasi otomatis, jadi
	HUD tidak butuh remote sama sekali.

	Yang didorong hanya nilai yang memang boleh dilihat client. Pembukuan
	rate limit tetap di server - kalau client tahu jendelanya, client bisa
	mengatur waktunya.
]]
function PlayerData.sync(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end

	local data = profile.data

	player:SetAttribute("Cash", math.floor(data.cash))
	player:SetAttribute("Gems", math.floor(data.gems))
	player:SetAttribute("Bag", math.floor(profile.session.bag))
	player:SetAttribute("BallsDug", data.ballsDug)
	player:SetAttribute("Rebirths", data.rebirths)
	player:SetAttribute("CashMultiplier", PlayerData.cashMultiplier(profile))

	player:SetAttribute("ToolLevel", data.levels.tool)
	player:SetAttribute("BagLevel", data.levels.bag)
	player:SetAttribute("WallLevel", data.levels.wall)

	player:SetAttribute("BallsPerDig", Config.levelValue("tool", data.levels.tool))
	player:SetAttribute("BagCapacity", Config.levelValue("bag", data.levels.bag))
	player:SetAttribute("WallReduction", Config.levelValue("wall", data.levels.wall))
end

--[[
	Rebirth: reset seluruh belanjaan dan cash, simpan gems dan rekor.

	Mengembalikan tier kolam yang berlaku setelahnya, supaya pemanggil bisa
	langsung mengisi ulang kolam pada tier itu.
]]
function PlayerData.rebirth(player: Player): number
	local profile = profiles[player]
	local data = profile.data

	data.rebirths += 1
	data.cash = 0
	data.levels = { tool = 1, bag = 1, wall = 1 }
	profile.session.bag = 0

	PlayerData.sync(player)
	return Config.pitTierForRebirths(data.rebirths)
end

function PlayerData.add(player: Player)
	profiles[player] = {
		data = PlayerData.newData(),
		session = newSession(),
	}
	PlayerData.sync(player)
	return profiles[player]
end

function PlayerData.remove(player: Player)
	profiles[player] = nil
end

Players.PlayerRemoving:Connect(PlayerData.remove)

return PlayerData
