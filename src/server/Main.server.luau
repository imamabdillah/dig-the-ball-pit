--[[
	Main — seluruh aturan permainan dan SELURUH validasi, di satu file.

	Ditaruh bersama supaya bisa dibaca sekali jalan saat audit. Begitu
	validasi tersebar ke lima file, tidak ada lagi yang bisa menjawab
	"apa saja yang dipercaya dari client?" dengan yakin.

	Jawabannya di sini: client hanya boleh mengusulkan SATU Vector3 dan
	SATU nama jalur upgrade. Semua sisanya dihitung server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local PitService = require(script.Parent:WaitForChild("PitService"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

PitService.build()

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

-- ---------------------------------------------------------------- menggali

--[[
	Empat pemeriksaan, berurutan dari yang termurah.

	Dua yang pertama gagal dalam permainan normal (jitter jaringan), jadi
	diam-diam saja — memberi pesan error di situ hanya membuat HUD berkedip.
	Dua terakhir hanya bisa gagal kalau client berbohong, jadi itu yang
	dilaporkan.
]]
local function validateDig(player: Player, point: Vector3): (boolean, string?)
	local profile = PlayerData.get(player)
	if not profile then
		return false, nil
	end

	local now = os.clock()

	--[[
		1. jendela bergulir, menghitung SETIAP permintaan masuk

		Penghitung ini sengaja naik sebelum pemeriksaan apa pun, termasuk
		untuk permintaan yang akan ditolak. Kalau hanya galian berhasil yang
		dihitung, client bisa membanjiri server dengan permintaan tidak sah
		tanpa batas: tidak ada cash yang bocor, tapi server tetap membayar
		biayanya. Batas jendela harus membatasi lalu lintas, bukan hasil.

		Client sah menembak sekitar 8,6 kali per 3 detik, jadi jatah 12
		masih menyisakan ruang untuk jitter.
	]]
	if now - profile.windowStart > Config.Dig.WindowSeconds then
		profile.windowStart = now
		profile.windowCount = 0
	end
	profile.windowCount += 1
	if profile.windowCount > Config.Dig.MaxRequestsPerWindow then
		return false, nil
	end

	-- 2. jarak sejak galian terakhir yang BERHASIL
	if now - profile.lastDig < Config.Dig.Interval * Config.Dig.IntervalGrace then
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

	-- 4. titiknya memang permukaan kolam
	if not PitService.isPointOnSurface(point) then
		return false, "Itu bukan permukaan kolam"
	end

	--[[
		5. pemain tidak sedang berdiri di zona mati sekitar corong

		Kolom penjualan berdiri di dalam batas kolam, jadi tanpa aturan ini
		pemain bisa berdiri di dalam corong, menggali, dan kantongnya langsung
		terjual tiap 0.25 detik. Langkah "lari ke corong" hilang dari loop.

		Akibat terburuknya bukan cash yang terlalu cepat, tapi jalur upgrade
		kantong yang jadi tidak berguna: kalau jarak lari nol, kapasitas
		kantong tidak menaikkan laju sama sekali, dan salah satu dari tiga
		jalur toko mati.

		Diukur dari posisi pemain, bukan titik galian. Yang ingin dipaksa
		adalah "keluar dari corong untuk menggali", dan pemain yang berdiri
		di tepi zona mati tetap boleh menggali ke arah dalam.
	]]
	local dxs = root.Position.X - Config.Sell.Position.X
	local dzs = root.Position.Z - Config.Sell.Position.Z
	if math.sqrt(dxs * dxs + dzs * dzs) < Config.Sell.NoDigRadius then
		return false, "Menjauh dari corong untuk menggali"
	end

	profile.lastDig = now
	return true, nil
end

Remotes.DigRequest.OnServerEvent:Connect(function(player: Player, point: any)
	-- Argumen remote datang dari client, jadi tipenya diperiksa lebih dulu.
	-- Tanpa baris ini, satu FireServer(nil) melempar error di server.
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
	local capacity = Config.levelValue("bag", profile.levels.bag) or 0
	local perDig = Config.levelValue("tool", profile.levels.tool) or 0

	local room = capacity - profile.bag
	if room <= 0 then
		notify(player, "Kantong penuh — buang dulu")
		return
	end

	local wanted = math.min(perDig, room)
	local taken = PitService.remove(wanted, Config.levelValue("wall", profile.levels.wall))
	if taken <= 0 then
		return
	end

	profile.bag += taken
	profile.ballsDug += taken
	PlayerData.sync(player)
end)

-- ---------------------------------------------------------------- menjual

--[[
	Penjualan otomatis berdasarkan jarak, bukan event Touched.

	Touched bisa dipicu client dengan menggerakkan karakternya, dan
	pemeriksaan jaraknya sama saja — tapi loop ini tidak bisa di-spam,
	dan tidak ada remote yang perlu dijaga.

	Jarak diukur hanya di XZ, jadi kolom penjualan bekerja di ketinggian
	permukaan mana pun tanpa perlu tangga.
]]
local function trySell(player: Player)
	local profile = PlayerData.get(player)
	if not profile or profile.bag <= 0 then
		return
	end

	local root = rootOf(player)
	if not root then
		return
	end

	local dx = root.Position.X - Config.Sell.Position.X
	local dz = root.Position.Z - Config.Sell.Position.Z
	if math.sqrt(dx * dx + dz * dz) > Config.Sell.Radius then
		return
	end

	local earned = profile.bag * Config.Sell.CashPerBall
	profile.cash += earned
	profile.bag = 0
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

	local current = profile.levels[line]
	local nextLevel = Config.nextLevel(line, current)
	if not nextLevel then
		notify(player, definition.Label .. " sudah maksimal")
		return
	end

	if profile.cash < nextLevel.Cost then
		notify(player, string.format("Kurang %d cash", nextLevel.Cost - math.floor(profile.cash)))
		return
	end

	profile.cash -= nextLevel.Cost
	profile.levels[line] = current + 1
	PlayerData.sync(player)
	notify(player, string.format("%s: %s", definition.Label, nextLevel.Name))

	--[[
		Log gerbang. Satu baris per pembelian, cukup untuk menjawab dua
		pertanyaan tuning yang tidak bisa dijawab dari ingatan: berapa lama
		sampai pembelian pertama, dan apakah ada jeda lebih dari empat menit
		di antara dua pembelian.

		Hapus blok ini setelah kurvanya terkunci - print tiap pembelian
		tidak ada gunanya di produksi.
	]]
	local t = math.floor(os.clock() - profile.sessionStart)
	print(string.format(
		"[gerbang] %02d:%02d  %s -> %s (%d)  sisa cash %d  kolam %d  tergali %d",
		math.floor(t / 60),
		t % 60,
		line,
		nextLevel.Name,
		nextLevel.Cost,
		math.floor(profile.cash),
		math.floor(PitService.ballsRemaining),
		profile.ballsDug
	))
end)

-- ---------------------------------------------------------------- heartbeat

local sellAccum = 0
local announced = false

RunService.Heartbeat:Connect(function(dt: number)
	PitService.step(dt)

	sellAccum += dt
	if sellAccum >= Config.Sell.Interval then
		sellAccum = 0
		for _, player in Players:GetPlayers() do
			trySell(player)
		end
	end

	if PitService.cleared and not announced then
		announced = true
		-- Dibulatkan ke bilangan bulat lebih dulu: string.format("%d", x)
		-- menolak angka yang masih punya bagian pecahan.
		local seconds = math.floor(PitService.elapsed())
		Remotes.Notify:FireAllClients(
			string.format("Kolam kosong dalam %d:%02d — reset 5 detik", math.floor(seconds / 60), seconds % 60)
		)
		print(string.format(
			"[gerbang] KOLAM KOSONG %02d:%02d  target 8-12 menit  longsor mengembalikan %d bola",
			math.floor(seconds / 60),
			seconds % 60,
			math.floor(PitService.settledTotal)
		))
		task.delay(5, function()
			PitService.reset()
			announced = false
		end)
	end
end)

print("[DigTheBallPit] server siap — kolam", Config.Pit.TotalBalls, "bola")
