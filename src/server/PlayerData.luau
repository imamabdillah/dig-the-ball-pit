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

	Penyimpanan memakai ProfileStore, bukan DataStore mentah. Yang dibeli
	dari situ adalah session locking: satu profil hanya boleh aktif di satu
	server pada satu waktu. Tanpa itu, pemain masuk ke dua server sekaligus,
	menghabiskan cash di keduanya, dan yang menyimpan terakhir menang -
	eksploit penggandaan mata uang yang paling umum di genre ini.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ProfileStore = require(script.Parent:WaitForChild("vendor"):WaitForChild("ProfileStore"))

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

-- Pengali cash dari rebirth. Berlipat dan permanen.
function PlayerData.cashMultiplier(profile): number
	return Config.cashMultiplier(profile.data.rebirths)
end

--[[
	Naikkan tiap jalur ke lantai yang seharusnya dimiliki pada jumlah
	rebirth ini. Tidak pernah menurunkan apa pun.

	Dipanggil dua kali: sesudah rebirth, dan sesudah profil dimuat. Yang
	kedua penting - ia membuat aturan lantai berlaku surut, jadi mengubah
	MaxHeadStart nanti langsung terpakai oleh pemain lama tanpa migrasi.
]]
local function applyStartingLevels(data)
	for line in Config.Upgrades do
		local floor = Config.startingLevel(line, data.rebirths)
		if data.levels[line] == nil or data.levels[line] < floor then
			data.levels[line] = floor
		end
	end
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

	-- Reset ke dasar, lalu naikkan ke lantai yang dibuka rebirth baru ini.
	-- Urutannya penting: reset dulu supaya pembelian di atas lantai benar
	-- benar hilang, bukan sekadar dipertahankan.
	data.levels = { tool = 1, bag = 1, wall = 1 }
	applyStartingLevels(data)

	profile.session.bag = 0

	PlayerData.sync(player)
	return Config.pitTierForRebirths(data.rebirths)
end

-- ---------------------------------------------------------------- simpan

local store = ProfileStore.New(Config.Save.StoreName, PlayerData.newData())

--[[
	Mock hidup di memori satu server dan tidak menyentuh DataStore sama
	sekali. Itu membuat seluruh loop bisa diuji tanpa API Services dan
	tanpa place yang dipublikasikan - tapi juga berarti mock TIDAK menguji
	session locking, karena tidak ada server kedua yang bisa melihatnya.
]]
local useMock = RunService:IsStudio() and Config.Save.UseMockInStudio
if useMock then
	store = store.Mock
	warn("[PlayerData] memakai penyimpanan TIRUAN. Session locking tidak diuji di mode ini.")
end

--[[
	Memuat profil. Memblokir sampai sesi didapat, jadi harus dipanggil dari
	thread yang boleh menunggu - PlayerAdded sudah begitu.

	Mengembalikan nil kalau pemain sudah pergi atau sesi tidak bisa didapat.
	Pemanggil wajib memeriksa hasilnya sebelum membangun apa pun untuk
	pemain itu.
]]
function PlayerData.load(player: Player)
	--[[
		CATATAN: Mock.StartSessionAsync(_, profile_key) membuang argumen
		params, jadi Cancel diam-diam TIDAK dipakai di mode tiruan. Tidak
		berbahaya karena mock memuat seketika, dan pemeriksaan
		player.Parent di bawah tetap menangkap pemain yang keluar - tapi
		jangan mengandalkan Cancel untuk kebenaran di mode mana pun.
	]]
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		-- Berhenti mencoba kalau pemainnya sudah keluar duluan. Tanpa ini,
		-- server terus memperebutkan kunci untuk orang yang tidak ada.
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	if profile == nil then
		player:Kick("Gagal memuat data. Coba masuk lagi.")
		return nil
	end

	profile:AddUserId(player.UserId)

	-- Mengisi kunci yang belum ada dari template. Ini yang membuat menambah
	-- field baru ke newData() aman untuk profil lama.
	profile:Reconcile()

	-- Berlaku surut untuk profil yang disimpan sebelum aturan tier awal ada.
	applyStartingLevels(profile.Data)

	--[[
		Sesi berakhir berarti server lain merebut kuncinya, ATAU pemainnya
		keluar secara normal. Yang kedua tidak perlu ditendang, jadi kick
		hanya untuk pemain yang masih ada di server ini.
	]]
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		if player.Parent == Players then
			player:Kick("Data kamu dibuka di server lain.")
		end
	end)

	-- Pemain bisa keluar selama pemuatan. Sesi harus ditutup, atau kuncinya
	-- menggantung dan pemain tidak bisa masuk lagi sampai kedaluwarsa.
	if player.Parent ~= Players then
		profile:EndSession()
		return nil
	end

	local record = {
		profile = profile,
		data = profile.Data,
		session = newSession(),
	}

	profiles[player] = record
	PlayerData.sync(player)
	return record
end

function PlayerData.remove(player: Player)
	local record = profiles[player]
	if record and record.profile then
		record.profile:EndSession()
	end
	profiles[player] = nil
end

Players.PlayerRemoving:Connect(PlayerData.remove)

return PlayerData
