--[[
	Config — satu-satunya sumber angka untuk seluruh game.

	Semua tuning ada di sini. Jangan pernah menaruh angka balance
	langsung di dalam service; kalau angkanya tersebar, gerbang minggu 2
	(rekam sesi 30 menit, tandai tiap pembelian) jadi mustahil dikerjakan.
]]

local Config = {}

-- ---------------------------------------------------------------- kolam

--[[
	Tiap pemain punya kolamnya sendiri di petak sendiri.

	Ini bukan kemewahan. Rebirth membuka kolam yang lebih besar per pemain,
	jadi satu kolam bersama tidak bisa mewakili dua pemain di tier berbeda.
	Genre ini juga memang begitu: di game jerami, tumpukan itu milikmu.

	Jejak kolam tetap 60x60 di semua tier. Yang berubah hanya jumlah bola,
	jadi kolam tier 5 turun jauh lebih lambat pada ukuran yang sama.
]]
Config.Pit = {
	SizeXZ = Vector2.new(60, 60),
	MaxHeight = 12,

	-- Kolam tidak pernah benar-benar setipis nol; sisakan pijakan.
	MinVisualHeight = 0.2,

	-- Tier terbuka lewat rebirth. Ambang di RebirthUnlocksPit.
	Tiers = {
		{ Name = "Kolam Anak", TotalBalls = 5000 },
		{ Name = "Pesta Ultah", TotalBalls = 25000 },
		{ Name = "Playground Mal", TotalBalls = 100000 },
		{ Name = "Gudang Bola", TotalBalls = 500000 },
		{ Name = "Stadion", TotalBalls = 2500000 },
	},
}

--[[
	Petak. Kolam pemain ke-n berdiri di x = n * Spacing, semuanya di atas
	satu lantai bersama. Jarak 140 stud memberi ruang aman di antara jejak
	60 stud, jadi tidak ada yang bisa menggali kolam tetangga dari tepi
	petaknya sendiri - MaxDistance hanya 12.
]]
Config.Plot = {
	Spacing = 140,
	MaxPlots = 8,
}

-- ---------------------------------------------------------------- menggali

Config.Dig = {
	Interval = 0.35,

	-- Client tidak pernah setepat server. Terima 15% lebih cepat dari
	-- interval sebelum menolak, supaya pemain berlatensi tinggi tidak dihukum.
	IntervalGrace = 0.85,

	-- Jarak maksimum pemain ke titik galian. Angka ini yang menghentikan
	-- exploiter menggali kolam dari seberang peta.
	MaxDistance = 12,

	-- Titik galian harus dekat permukaan, bukan di dalam badan kolam.
	SurfaceTolerance = 6,
	BoundsTolerance = 3,

	-- Penjaga kedua: rate limit jendela bergulir. Menangkap script yang
	-- mengirim tepat pada interval tapi dari banyak thread sekaligus.
	MaxRequestsPerWindow = 12,
	WindowSeconds = 3,
}

-- ---------------------------------------------------------------- menjual

Config.Sell = {
	-- Offset dari titik tengah petak, bukan koordinat dunia. Kolom berdiri
	-- DI DALAM batas kolam supaya pemain bisa mencapainya di setiap
	-- ketinggian permukaan, tanpa tangga atau ramp.
	Offset = Vector3.new(0, 0, 22),
	Radius = 7,
	Interval = 0.25,
	CashPerBall = 2,

	--[[
		Zona mati: pemain tidak bisa menggali sedekat ini dengan corong.
		Harus lebih besar dari Radius, atau seluruh loop runtuh menjadi
		"berdiri di corong, tahan klik, cash naik selamanya".

		Knob ini yang menentukan biaya lari, dan lewat itu menentukan apakah
		upgrade kantong ada gunanya. Jarak lari sekali jalan minimum adalah
		NoDigRadius dikurangi Radius, di sini 9 stud, sekitar 0,6 detik pada
		WalkSpeed bawaan. Naikkan kalau kapasitas kantong terasa tidak
		berdampak; turunkan kalau bolak-baliknya terasa menyiksa.
	]]
	NoDigRadius = 16,
}

-- ---------------------------------------------------------------- longsor

Config.Settle = {
	-- Fraksi bola yang mengalir balik ke lubang, sebelum dikurangi dinding.
	BaseRate = 0.30,
	TickSeconds = 1.5,
	ReturnPerTick = 0.25,
}

-- ---------------------------------------------------------------- upgrade

--[[
	Value berarti hal berbeda per jalur:
	  tool -> bola per sedotan
	  bag  -> kapasitas kantong
	  wall -> fraksi longsor yang diredam (0 = tidak meredam)

	CATATAN TUNING. Harga di sini lebih murah dari tabel dokumen konsep
	(Ember 150, bukan 250). Alasannya: dengan harga dokumen, pembelian
	PERTAMA butuh ~3 menit. Pembelian pertama harus terasa dalam 60-90 detik,
	atau pemain pergi sebelum loopnya sempat mengikat. Angka di bawah ini
	tetap tebakan — ukur sesi nyata di gerbang minggu 2, lalu geser.
]]
Config.Upgrades = {
	tool = {
		Label = "Alat",
		Levels = {
			{ Name = "Tangan", Value = 1, Cost = 0 },
			{ Name = "Ember", Value = 4, Cost = 150 },
			{ Name = "Jaring", Value = 12, Cost = 1200 },
			{ Name = "Sekop Lebar", Value = 40, Cost = 6500 },
			{ Name = "Vacuum", Value = 150, Cost = 35000 },
			{ Name = "Vacuum Turbo", Value = 600, Cost = 200000 },
			{ Name = "Excavator", Value = 2500, Cost = 1200000 },
		},
	},
	bag = {
		Label = "Kantong",
		Levels = {
			{ Name = "Saku", Value = 10, Cost = 0 },
			{ Name = "Tas", Value = 25, Cost = 400 },
			{ Name = "Karung", Value = 60, Cost = 1800 },
			{ Name = "Gerobak", Value = 150, Cost = 9000 },
			{ Name = "Bak Truk", Value = 400, Cost = 48000 },
			{ Name = "Kontainer", Value = 1000, Cost = 260000 },
		},
	},
	wall = {
		Label = "Dinding",
		Levels = {
			-- Value = fraksi longsor yang diredam. Naiknya sengaja melambat:
			-- tier terakhir cuma menambah 5 poin. Peredaman sempurna akan
			-- menghapus satu-satunya mekanik yang membedakan game ini.
			{ Name = "Tanpa dinding", Value = 0, Cost = 0 },
			{ Name = "Papan", Value = 0.30, Cost = 900 },
			{ Name = "Beton", Value = 0.50, Cost = 4000 },
			{ Name = "Baja", Value = 0.65, Cost = 20000 },
			{ Name = "Sekat Ganda", Value = 0.75, Cost = 100000 },
			{ Name = "Cetakan Penuh", Value = 0.80, Cost = 520000 },
		},
	},
}

--[[
	Rebirth: reset level alat, kantong, dinding, dan cash. Gems dan rekor
	tetap. Tiap rebirth menambah pengali cash permanen dan kumulatif.

	Syaratnya mengosongkan kolam, bukan menumpuk cash. Alasannya: peristiwa
	"kolam kosong" adalah gerbang hadiah yang menahan pemain, dan rebirth
	harus menggantung tepat di baliknya.

	Ambang kolam sengaja tidak rata. Kolam berikutnya datang cepat di awal
	(rebirth 1), lalu makin jarang - itu yang mengubah ekor grinding jadi
	jarak yang terasa layak ditempuh.
]]
Config.Rebirth = {
	CashMultiplierPerRebirth = 0.25,
	RequiresPitCleared = true,

	-- Rebirth ke-N membuka kolam tier berapa. Indeks = jumlah rebirth.
	UnlocksPitAt = {
		[1] = 2,
		[3] = 3,
		[6] = 4,
		[10] = 5,
	},
}

--[[
	Gems dari mengosongkan kolam. Belum ada gunanya sampai barang hilang
	dan buku koleksi masuk di minggu 3 - ini hanya wadah supaya hadiah
	pengosongan sudah ada bentuknya.
]]
Config.ClearReward = {
	GemsPerTier = { 25, 150, 900, 5000, 30000 },
}

-- Urutan tombol di HUD.
Config.UpgradeOrder = { "tool", "bag", "wall" }

-- Nama atribut Player yang menyimpan level tiap jalur. Dipetakan eksplisit,
-- bukan disusun dari string jalur — nama atribut adalah kontrak antara
-- server dan HUD, dan kontrak tidak boleh bergantung pada manipulasi string.
Config.UpgradeAttribute = {
	tool = "ToolLevel",
	bag = "BagLevel",
	wall = "WallLevel",
}

-- ---------------------------------------------------------------- helper

function Config.levelValue(line: string, index: number): number?
	local def = Config.Upgrades[line]
	if not def then
		return nil
	end
	local level = def.Levels[index]
	return level and level.Value or nil
end

function Config.levelName(line: string, index: number): string?
	local def = Config.Upgrades[line]
	if not def then
		return nil
	end
	local level = def.Levels[index]
	return level and level.Name or nil
end

function Config.nextLevel(line: string, index: number)
	local def = Config.Upgrades[line]
	if not def then
		return nil
	end
	return def.Levels[index + 1]
end

function Config.pitTier(index: number)
	return Config.Pit.Tiers[math.clamp(index, 1, #Config.Pit.Tiers)]
end

-- Titik tengah lantai petak ke-index (1 = petak pertama).
function Config.plotOrigin(index: number): Vector3
	return Vector3.new((index - 1) * Config.Plot.Spacing, 0, 0)
end

-- Tier kolam tertinggi yang sudah dibuka pada jumlah rebirth tertentu.
function Config.pitTierForRebirths(rebirths: number): number
	local tier = 1
	for threshold, unlocked in Config.Rebirth.UnlocksPitAt do
		if rebirths >= threshold and unlocked > tier then
			tier = unlocked
		end
	end
	return math.min(tier, #Config.Pit.Tiers)
end

-- Jumlah rebirth terkecil yang masih membuka kolam baru, atau nil kalau
-- semua tier sudah terbuka. Dipakai HUD untuk menjelaskan imbalannya.
function Config.nextPitUnlockAt(rebirths: number): number?
	local best = nil
	for threshold in Config.Rebirth.UnlocksPitAt do
		if threshold > rebirths and (best == nil or threshold < best) then
			best = threshold
		end
	end
	return best
end

return Config
