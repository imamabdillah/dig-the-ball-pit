--[[
	Main - seluruh aturan permainan dan SELURUH validasi, di satu file.

	Ditaruh bersama supaya bisa dibaca sekali jalan saat audit. Begitu
	validasi tersebar ke lima file, tidak ada lagi yang bisa menjawab
	"apa saja yang dipercaya dari client?" dengan yakin.

	Jawabannya di sini: client hanya boleh mengusulkan SATU Vector3, SATU
	nama jalur upgrade, dan permintaan rebirth tanpa argumen. Semua sisanya
	dihitung server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PitService = require(script.Parent:WaitForChild("PitService"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

--[[
	Karakter dimuat manual. Kolam dan RespawnLocation harus sudah ada
	SEBELUM karakter pertama muncul, atau Roblox melempar pemain ke petak
	acak dan mereka mendarat di kolam orang lain.
]]
Players.CharacterAutoLoads = false

-- ---------------------------------------------------------------- util

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function notify(player: Player, message: string)
	Remotes.Notify:FireClient(player, message)
end

local function stamp(profile): string
	local t = math.floor(os.clock() - profile.session.sessionStart)
	return string.format("%02d:%02d", math.floor(t / 60), t % 60)
end

-- ---------------------------------------------------------------- join

--[[
	Pemuatan profil memblokir sampai session lock didapat, jadi kolam dan
	karakter baru dibangun SETELAH datanya ada. Urutan ini penting: tier
	kolam ditentukan oleh jumlah rebirth yang tersimpan, dan membangun
	kolam sebelum data dimuat akan selalu memberi tier 1.

	load() mengembalikan nil kalau pemain keluar duluan atau sesinya tidak
	bisa didapat - keduanya sudah menendang pemainnya sendiri, jadi di sini
	cukup berhenti.
]]
local function onPlayerAdded(player: Player)
	local profile = PlayerData.load(player)
	if not profile then
		return
	end

	PitService.create(player, Config.pitTierForRebirths(profile.data.rebirths))
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(onPlayerAdded)

for _, player in Players:GetPlayers() do
	if not PlayerData.get(player) then
		task.spawn(onPlayerAdded, player)
	end
end

-- ---------------------------------------------------------------- menggali

--[[
	Enam pemeriksaan, berurutan dari yang termurah.

	Yang gagal dalam permainan normal (jitter jaringan) ditolak diam-diam;
	memberi pesan error di situ hanya membuat HUD berkedip. Yang hanya bisa
	gagal kalau client berbohong, atau kalau pemain memang salah posisi,
	itu yang dilaporkan.
]]
local function validateDig(player: Player, point: Vector3): (boolean, string?)
	local profile = PlayerData.get(player)
	if not profile then
		return false, nil
	end

	local pit = PitService.get(player)
	if not pit then
		return false, nil
	end

	local session = profile.session
	local now = os.clock()

	--[[
		1. jendela bergulir, menghitung SETIAP permintaan masuk

		Penghitung ini sengaja naik sebelum pemeriksaan apa pun, termasuk
		untuk permintaan yang akan ditolak. Kalau hanya galian berhasil yang
		dihitung, client bisa membanjiri server dengan permintaan tidak sah
		tanpa batas: tidak ada cash yang bocor, tapi server tetap membayar
		biayanya. Batas jendela harus membatasi lalu lintas, bukan hasil.
	]]
	if now - session.windowStart > Config.Dig.WindowSeconds then
		session.windowStart = now
		session.windowCount = 0
	end
	session.windowCount += 1
	if session.windowCount > Config.Dig.MaxRequestsPerWindow then
		return false, nil
	end

	-- 2. jarak sejak galian terakhir yang BERHASIL
	if now - session.lastDig < Config.Dig.Interval * Config.Dig.IntervalGrace then
		return false, nil
	end

	-- 3. pemain benar-benar ada di dekat titik itu
	local root = rootOf(player)
	if not root then
		return false, nil
	end
	if (root.Position - point).Magnitude > Config.Dig.MaxDistance then
		return false, "Terlalu jauh dari titik galian"
	end

	--[[
		4. titiknya permukaan kolam MILIK PEMAIN INI

		Pit yang diperiksa selalu milik pemanggil, jadi menggali kolam
		tetangga otomatis jatuh di luar batas. Petak berjarak 140 stud
		sementara MaxDistance hanya 12, jadi tidak ada posisi berdiri yang
		bisa menjangkau dua kolam sekaligus.
	]]
	if not PitService.isPointOnSurface(pit, point) then
		return false, "Itu bukan permukaan kolammu"
	end

	--[[
		5. pemain tidak sedang berdiri di zona mati sekitar corong

		Kolom penjualan berdiri di dalam batas kolam, jadi tanpa aturan ini
		pemain bisa berdiri di dalam corong, menggali, dan kantongnya langsung
		terjual tiap 0.25 detik. Langkah "lari ke corong" hilang dari loop.

		Akibat terburuknya bukan cash yang terlalu cepat, tapi jalur upgrade
		kantong yang jadi tidak berguna: kalau jarak lari nol, kapasitas
		kantong tidak menaikkan laju sama sekali.
	]]
	local sell = PitService.sellPosition(pit)
	local dxs = root.Position.X - sell.X
	local dzs = root.Position.Z - sell.Z
	if math.sqrt(dxs * dxs + dzs * dzs) < Config.Sell.NoDigRadius then
		return false, "Menjauh dari corong untuk menggali"
	end

	session.lastDig = now
	return true, nil
end

Remotes.DigRequest.OnServerEvent:Connect(function(player: Player, point: any)
	-- Argumen remote datang dari client, jadi tipenya diperiksa lebih dulu.
	if typeof(point) ~= "Vector3" then
		return
	end

	local ok, reason = validateDig(player, point)
	if not ok then
		if reason then
			notify(player, reason)
		end
		return
	end

	local profile = PlayerData.get(player)
	local pit = PitService.get(player)
	local data = profile.data

	local capacity = Config.levelValue("bag", data.levels.bag) or 0
	local perDig = Config.levelValue("tool", data.levels.tool) or 0

	local room = capacity - profile.session.bag
	if room <= 0 then
		notify(player, "Kantong penuh — buang dulu")
		return
	end

	local taken = PitService.remove(pit, math.min(perDig, room), Config.levelValue("wall", data.levels.wall))
	if taken <= 0 then
		return
	end

	profile.session.bag += taken
	data.ballsDug += taken
	PlayerData.sync(player)
end)

-- ---------------------------------------------------------------- menjual

--[[
	Penjualan otomatis berdasarkan jarak, bukan event Touched.

	Jarak diukur hanya di XZ, jadi kolom penjualan bekerja di ketinggian
	permukaan mana pun tanpa perlu tangga.
]]
local function trySell(player: Player)
	local profile = PlayerData.get(player)
	if not profile or profile.session.bag <= 0 then
		return
	end

	local pit = PitService.get(player)
	local root = rootOf(player)
	if not pit or not root then
		return
	end

	local sell = PitService.sellPosition(pit)
	local dx = root.Position.X - sell.X
	local dz = root.Position.Z - sell.Z
	if math.sqrt(dx * dx + dz * dz) > Config.Sell.Radius then
		return
	end

	local earned = math.floor(profile.session.bag * Config.Sell.CashPerBall * PlayerData.cashMultiplier(profile))
	profile.data.cash += earned
	profile.session.bag = 0
	PlayerData.sync(player)
	notify(player, string.format("+%d cash", earned))
end

-- ---------------------------------------------------------------- toko

Remotes.BuyUpgrade.OnServerEvent:Connect(function(player: Player, line: any)
	if type(line) ~= "string" then
		return
	end

	local definition = Config.Upgrades[line]
	if not definition then
		return
	end

	local profile = PlayerData.get(player)
	if not profile then
		return
	end

	local data = profile.data
	local current = data.levels[line]
	local nextLevel = Config.nextLevel(line, current)
	if not nextLevel then
		notify(player, definition.Label .. " sudah maksimal")
		return
	end

	if data.cash < nextLevel.Cost then
		notify(player, string.format("Kurang %d cash", nextLevel.Cost - math.floor(data.cash)))
		return
	end

	data.cash -= nextLevel.Cost
	data.levels[line] = current + 1
	PlayerData.sync(player)
	notify(player, string.format("%s: %s", definition.Label, nextLevel.Name))

	--[[
		Log gerbang. Satu baris per pembelian, cukup untuk menjawab dua
		pertanyaan tuning yang tidak bisa dijawab dari ingatan: berapa lama
		sampai pembelian pertama, dan apakah ada jeda lebih dari empat menit
		di antara dua pembelian.

		Hapus blok ini setelah kurvanya terkunci.
	]]
	local pit = PitService.get(player)
	print(string.format(
		"[gerbang] %s  %s -> %s (%d)  sisa cash %d  kolam %d  tergali %d",
		stamp(profile),
		line,
		nextLevel.Name,
		nextLevel.Cost,
		math.floor(data.cash),
		pit and math.floor(pit.ballsRemaining) or -1,
		data.ballsDug
	))
end)

-- ---------------------------------------------------------------- rebirth

Remotes.Rebirth.OnServerEvent:Connect(function(player: Player)
	local profile = PlayerData.get(player)
	local pit = PitService.get(player)
	if not profile or not pit then
		return
	end

	--[[
		Syaratnya mengosongkan kolam, bukan menumpuk cash.

		"Kolam kosong" adalah gerbang hadiah yang menahan pemain sampai
		akhir sesi. Menggantung rebirth tepat di baliknya berarti hadiah
		terbesar dan alasan terkuat untuk lanjut tiba di saat yang sama.
	]]
	if Config.Rebirth.RequiresPitCleared and not pit.cleared then
		notify(player, "Kosongkan kolam dulu untuk rebirth")
		return
	end

	local before = profile.data.rebirths
	local tier = PlayerData.rebirth(player)
	PitService.setTier(pit, tier)

	local unlocked = Config.Rebirth.UnlocksPitAt[profile.data.rebirths]
	if unlocked then
		notify(player, string.format("Rebirth %d — kolam baru: %s", profile.data.rebirths, pit.tierName))
	else
		notify(player, string.format("Rebirth %d — cash x%.2f", profile.data.rebirths, PlayerData.cashMultiplier(profile)))
	end

	print(string.format(
		"[gerbang] %s  REBIRTH %d -> %d  kolam tier %d (%s)  pengali x%.2f",
		stamp(profile),
		before,
		profile.data.rebirths,
		pit.tierIndex,
		pit.tierName,
		PlayerData.cashMultiplier(profile)
	))
end)

-- ---------------------------------------------------------------- heartbeat

local sellAccum = 0

local function onPitCleared(player: Player, pit)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end

	local data = profile.data
	local seconds = math.floor(PitService.elapsed(pit))
	local gems = Config.ClearReward.GemsPerTier[pit.tierIndex] or 0

	data.gems += gems
	data.pitsCleared += 1
	if data.bestClearSeconds == 0 or seconds < data.bestClearSeconds then
		data.bestClearSeconds = seconds
	end
	PlayerData.sync(player)

	notify(player, string.format(
		"%s kosong dalam %d:%02d — +%d gems. Rebirth sekarang.",
		pit.tierName,
		math.floor(seconds / 60),
		seconds % 60,
		gems
	))

	print(string.format(
		"[gerbang] %s  KOLAM KOSONG %s dalam %02d:%02d  target 8-12 menit  longsor mengembalikan %d bola",
		stamp(profile),
		pit.tierName,
		math.floor(seconds / 60),
		seconds % 60,
		math.floor(pit.settledTotal)
	))
end

RunService.Heartbeat:Connect(function(dt: number)
	PitService.step(dt)

	sellAccum += dt
	if sellAccum >= Config.Sell.Interval then
		sellAccum = 0
		for _, player in Players:GetPlayers() do
			trySell(player)
		end
	end

	for _, player in Players:GetPlayers() do
		local pit = PitService.get(player)
		--[[
			Kolam yang kosong TIDAK di-reset otomatis lagi.

			Di minggu 1 reset otomatis masuk akal karena tidak ada apa pun
			setelah pengosongan. Sekarang pengosongan adalah gerbang rebirth,
			jadi kolam harus tetap kosong sampai pemain menekan rebirth -
			kalau tidak, gerbangnya lewat begitu saja tanpa sempat dipakai.
		]]
		if pit and pit.cleared and not pit.announced then
			pit.announced = true
			onPitCleared(player, pit)
		end
	end
end)

print("[DigTheBallPit] server siap — kolam per pemain, tier 1..", #Config.Pit.Tiers)
