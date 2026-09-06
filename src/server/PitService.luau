--[[
	PitService — seluruh keadaan kolam, di server, sebagai SATU ANGKA.

	Jebakan #1 dari dokumen konsep: jangan pernah spawn kolam sebagai
	ribuan part fisik. Server mati sekitar 2.000 part, dan HP Android
	kelas bawah jauh lebih awal dari itu.

	Yang benar-benar ada:
	  ballsRemaining : satu angka di server
	  Pit            : SATU part yang tingginya adalah fungsi angka itu

	Lapisan bola collidable di permukaan (maks 300 sesuai anggaran di
	dokumen) baru ditambahkan di minggu 4, saat art pass. Minggu 1 adalah
	kotak abu-abu, dan memang harus begitu.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PitService = {}

PitService.ballsRemaining = Config.Pit.TotalBalls
PitService.settleDebt = 0
PitService.settleAccum = 0
PitService.startedAt = os.clock()
PitService.cleared = false
PitService.part = nil
PitService.sellZone = nil

-- ---------------------------------------------------------------- geometri

function PitService.surfaceY(): number
	local pit = Config.Pit
	local fraction = PitService.ballsRemaining / pit.TotalBalls
	return pit.Origin.Y + pit.MaxHeight * fraction
end

--[[
	Validasi geometri titik galian. Dipanggil server, tidak pernah client.
	Menolak titik di luar kolam dan titik yang jauh dari permukaan —
	tanpa ini, exploiter bisa "menggali" dari dalam badan kolam.
]]
function PitService.isPointOnSurface(point: Vector3): boolean
	local pit = Config.Pit
	local halfX = pit.SizeXZ.X / 2 + Config.Dig.BoundsTolerance
	local halfZ = pit.SizeXZ.Y / 2 + Config.Dig.BoundsTolerance

	if math.abs(point.X - pit.Origin.X) > halfX then
		return false
	end
	if math.abs(point.Z - pit.Origin.Z) > halfZ then
		return false
	end

	return math.abs(point.Y - PitService.surfaceY()) <= Config.Dig.SurfaceTolerance
end

-- ---------------------------------------------------------------- mutasi

--[[
	Ambil bola dari kolam. settleReduction 0..1 datang dari level dinding
	pemain yang menggali. Mengembalikan jumlah yang benar-benar terambil,
	yang bisa lebih kecil dari yang diminta kalau kolam hampir habis.
]]
function PitService.remove(amount: number, settleReduction: number?): number
	if PitService.cleared then
		return 0
	end

	local removed = math.min(amount, PitService.ballsRemaining)
	if removed <= 0 then
		return 0
	end

	PitService.ballsRemaining -= removed

	local reduction = math.clamp(settleReduction or 0, 0, 1)
	PitService.settleDebt += removed * Config.Settle.BaseRate * (1 - reduction)

	if PitService.ballsRemaining <= 0 then
		-- Kolam kosong menang atas longsor. Tanpa baris ini, hutang longsor
		-- mengisi ulang kolam dan pemain tidak pernah bisa menyelesaikannya.
		PitService.ballsRemaining = 0
		PitService.settleDebt = 0
		PitService.cleared = true
	end

	PitService.updateVisual()
	return removed
end

-- Kembalikan sebagian hutang longsor ke kolam. Dipanggil dari heartbeat.
function PitService.step(dt: number)
	if PitService.cleared then
		return
	end

	PitService.settleAccum += dt
	if PitService.settleAccum < Config.Settle.TickSeconds then
		return
	end
	PitService.settleAccum = 0

	if PitService.settleDebt < 1 then
		return
	end

	local headroom = Config.Pit.TotalBalls - PitService.ballsRemaining
	local back = math.max(1, math.floor(PitService.settleDebt * Config.Settle.ReturnPerTick))
	back = math.min(back, math.floor(PitService.settleDebt), headroom)

	if back <= 0 then
		return
	end

	PitService.settleDebt -= back
	PitService.ballsRemaining += back
	PitService.updateVisual()
end

function PitService.reset()
	PitService.ballsRemaining = Config.Pit.TotalBalls
	PitService.settleDebt = 0
	PitService.settleAccum = 0
	PitService.cleared = false
	PitService.startedAt = os.clock()
	PitService.updateVisual()
end

function PitService.elapsed(): number
	return os.clock() - PitService.startedAt
end

-- ---------------------------------------------------------------- visual

function PitService.updateVisual()
	local pit = Config.Pit
	local part = PitService.part

	if part then
		local height = math.max(pit.MinVisualHeight, PitService.surfaceY() - pit.Origin.Y)
		part.Size = Vector3.new(pit.SizeXZ.X, height, pit.SizeXZ.Y)
		part.CFrame = CFrame.new(pit.Origin.X, pit.Origin.Y + height / 2, pit.Origin.Z)
	end

	-- Atribut workspace tereplikasi ke semua client secara otomatis.
	-- Ini satu-satunya cara client tahu isi kolam — tidak ada remote per-frame.
	workspace:SetAttribute("BallsRemaining", math.floor(PitService.ballsRemaining))
	workspace:SetAttribute("BallsTotal", pit.TotalBalls)
end

-- ---------------------------------------------------------------- dunia

-- Membangun kotak abu-abu minggu 1 saat runtime, jadi tidak ada yang perlu
-- disusun tangan di Studio. Hapus fungsi ini di minggu 4.
function PitService.build()
	local pit = Config.Pit

	-- Place hasil `rojo build` tidak punya lantai bawaan. Tanpa ini pemain
	-- jatuh selamanya di sana, walau di template Studio bawaan aman.
	if not workspace:FindFirstChild("Baseplate") then
		local floor = Instance.new("Part")
		floor.Name = "Baseplate"
		floor.Anchored = true
		floor.Size = Vector3.new(512, 4, 512)
		floor.CFrame = CFrame.new(pit.Origin.X, pit.Origin.Y - 2, pit.Origin.Z)
		floor.Material = Enum.Material.SmoothPlastic
		floor.Color = Color3.fromRGB(74, 78, 86)
		floor.Parent = workspace
	end

	-- Spawn menggantung di ketinggian permukaan kolam saat penuh. Ketika
	-- kolam menyusut, pemain menjatuhkan diri ke permukaan — Roblox tidak
	-- punya fall damage bawaan, jadi ini aman dan tidak butuh tangga.
	if not workspace:FindFirstChild("PitSpawn") then
		local spawnPad = Instance.new("SpawnLocation")
		spawnPad.Name = "PitSpawn"
		spawnPad.Anchored = true
		spawnPad.CanCollide = true
		spawnPad.Size = Vector3.new(8, 1, 8)
		spawnPad.CFrame = CFrame.new(
			pit.Origin.X,
			pit.Origin.Y + pit.MaxHeight + 0.5,
			pit.Origin.Z - pit.SizeXZ.Y / 2 + 6
		)
		spawnPad.Material = Enum.Material.SmoothPlastic
		spawnPad.Color = Color3.fromRGB(60, 130, 200)
		spawnPad.Parent = workspace
	end

	local part = workspace:FindFirstChild("Pit")
	if not part then
		part = Instance.new("Part")
		part.Name = "Pit"
		part.Anchored = true
		part.CanCollide = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.Material = Enum.Material.SmoothPlastic
		part.Color = Color3.fromRGB(158, 158, 158)
		part.Parent = workspace
	end
	PitService.part = part

	local zone = workspace:FindFirstChild("SellZone")
	if not zone then
		zone = Instance.new("Part")
		zone.Name = "SellZone"
		zone.Anchored = true
		zone.CanCollide = false
		zone.CanQuery = false
		zone.CanTouch = false
		zone.Transparency = 0.65
		zone.Material = Enum.Material.Neon
		zone.Color = Color3.fromRGB(90, 200, 130)

		-- Kolom tinggi, bukan pad. Pemain menyentuhnya di ketinggian permukaan
		-- mana pun, jadi tidak perlu tangga saat kolam menyusut.
		zone.Size = Vector3.new(Config.Sell.Radius * 2, pit.MaxHeight * 3, Config.Sell.Radius * 2)
		zone.CFrame = CFrame.new(Config.Sell.Position.X, pit.Origin.Y + pit.MaxHeight, Config.Sell.Position.Z)
		zone.Parent = workspace

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "Label"
		billboard.Size = UDim2.fromScale(10, 2.2)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, pit.MaxHeight * 1.6, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = zone

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = 0.4
		label.Text = "BUANG DI SINI"
		label.Parent = billboard
	end
	PitService.sellZone = zone

	PitService.updateVisual()
end

return PitService
