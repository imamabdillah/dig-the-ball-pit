--[[
	Config — satu-satunya sumber angka untuk seluruh game.

	Semua tuning ada di sini. Jangan pernah menaruh angka balance
	langsung di dalam service; kalau angkanya tersebar, gerbang minggu 2
	(rekam sesi 30 menit, tandai tiap pembelian) jadi mustahil dikerjakan.
]]

local Config = {}

-- ---------------------------------------------------------------- kolam

Config.Pit = {
	TotalBalls = 5000,

	-- Origin = titik tengah LANTAI kolam. Permukaan naik dari sini.
	Origin = Vector3.new(0, 0, 0),
	SizeXZ = Vector2.new(60, 60),
	MaxHeight = 12,

	-- Kolam tidak pernah benar-benar setipis nol; sisakan pijakan.
	MinVisualHeight = 0.2,
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
	-- Kolom penjualan berdiri DI DALAM batas kolam supaya pemain bisa
	-- mencapainya di setiap ketinggian permukaan, tanpa tangga atau ramp.
	Position = Vector3.new(0, 0, 22),
	Radius = 7,
	Interval = 0.25,
	CashPerBall = 2,
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
		},
	},
	bag = {
		Label = "Kantong",
		Levels = {
			{ Name = "Saku", Value = 10, Cost = 0 },
			{ Name = "Tas", Value = 25, Cost = 400 },
			{ Name = "Karung", Value = 60, Cost = 1800 },
		},
	},
	wall = {
		Label = "Dinding",
		Levels = {
			{ Name = "Tanpa dinding", Value = 0, Cost = 0 },
			{ Name = "Papan", Value = 0.35, Cost = 900 },
			{ Name = "Beton", Value = 0.60, Cost = 3500 },
		},
	},
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

return Config
