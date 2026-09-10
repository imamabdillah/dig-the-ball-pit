--[[
	PitService - satu kolam per pemain, masing-masing di petaknya sendiri.

	Jebakan #1 dari dokumen konsep masih berlaku dan tidak berubah: kolam
	adalah SATU ANGKA di server, bukan ribuan part fisik. Yang berubah di
	minggu 2 hanyalah jumlah angkanya - satu per pemain, bukan satu global.

	Kenapa per pemain: rebirth membuka kolam yang lebih besar, jadi dua
	pemain di server yang sama bisa berada di tier berbeda. Satu kolam
	bersama tidak bisa mewakili keduanya.

	Semua keadaan kolam tereplikasi ke pemiliknya lewat atribut Player.
	Sebelumnya atribut ini menempel di workspace; itu tidak lagi mungkin
	begitu setiap pemain punya kolam sendiri.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local PitService = {}

-- player -> pit
local pits = {}

-- plotIndex -> player, supaya petak yang ditinggalkan bisa dipakai ulang
local plotOwners = {}

local worldFolder = nil

-- ---------------------------------------------------------------- geometri

function PitService.surfaceY(pit): number
	return pit.origin.Y + Config.Pit.MaxHeight * (pit.ballsRemaining / pit.totalBalls)
end

--[[
	Validasi geometri titik galian, selalu di server.

	Menolak titik di luar jejak kolam dan titik yang jauh dari permukaan.
	Karena kolam sekarang milik pemain tertentu, pemeriksaan ini juga yang
	menghentikan seseorang menggali kolam tetangga: pit yang dipakai adalah
	pit MILIKNYA, jadi titik di petak lain langsung jatuh di luar batas.
]]
function PitService.isPointOnSurface(pit, point: Vector3): boolean
	local halfX = Config.Pit.SizeXZ.X / 2 + Config.Dig.BoundsTolerance
	local halfZ = Config.Pit.SizeXZ.Y / 2 + Config.Dig.BoundsTolerance

	if math.abs(point.X - pit.origin.X) > halfX then
		return false
	end
	if math.abs(point.Z - pit.origin.Z) > halfZ then
		return false
	end

	return math.abs(point.Y - PitService.surfaceY(pit)) <= Config.Dig.SurfaceTolerance
end

function PitService.sellPosition(pit): Vector3
	return pit.origin + Config.Sell.Offset
end

-- ---------------------------------------------------------------- mutasi

--[[
	Ambil bola dari kolam. settleReduction 0..1 datang dari level dinding
	pemiliknya. Mengembalikan jumlah yang benar-benar terambil, yang bisa
	lebih kecil dari yang diminta kalau kolam hampir habis.
]]
function PitService.remove(pit, amount: number, settleReduction: number?): number
	if pit.cleared then
		return 0
	end

	local removed = math.min(amount, pit.ballsRemaining)
	if removed <= 0 then
		return 0
	end

	pit.ballsRemaining -= removed

	local reduction = math.clamp(settleReduction or 0, 0, 1)
	pit.settleDebt += removed * Config.Settle.BaseRate * (1 - reduction)

	if pit.ballsRemaining <= 0 then
		-- Kolam kosong menang atas longsor. Tanpa baris ini, hutang longsor
		-- mengisi ulang kolam dan pemain tidak pernah bisa menyelesaikannya.
		pit.ballsRemaining = 0
		pit.settleDebt = 0
		pit.cleared = true
	end

	PitService.sync(pit)
	return removed
end

local function stepOne(pit, dt: number)
	if pit.cleared then
		return
	end

	pit.settleAccum += dt
	if pit.settleAccum < Config.Settle.TickSeconds then
		return
	end
	pit.settleAccum = 0

	if pit.settleDebt < 1 then
		return
	end

	local headroom = pit.totalBalls - pit.ballsRemaining
	local back = math.max(1, math.floor(pit.settleDebt * Config.Settle.ReturnPerTick))
	back = math.min(back, math.floor(pit.settleDebt), headroom)

	if back <= 0 then
		return
	end

	pit.settleDebt -= back
	pit.ballsRemaining += back
	pit.settledTotal += back
	PitService.sync(pit)
end

function PitService.step(dt: number)
	for _, pit in pits do
		stepOne(pit, dt)
	end
end

function PitService.elapsed(pit): number
	return os.clock() - pit.startedAt
end

--[[
	Isi ulang kolam pada tier tertentu. Dipakai saat kolam kosong dan saat
	rebirth menaikkan tier.
]]
--[[
	Angkat pemilik ke pad spawn-nya.

	Wajib dipanggil setiap kali kolam terisi ulang. Kolam yang kosong hanya
	setinggi MinVisualHeight, jadi pemain berdiri di y sekitar 0.2; mengisi
	ulang menumbuhkan part solid dari y=0 ke y=12 MENGELILINGI karakternya.
	Karakter yang terjebak di dalam part solid didorong keluar lewat bawah
	dan jatuh menembus lantai.

	Tidak melakukan apa-apa saat kolam pertama dibuat, karena karakternya
	memang belum ada.
]]
function PitService.liftOwner(pit)
	local player = pit.player
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not pit.spawnPad then
		return
	end
	root.CFrame = pit.spawnPad.CFrame + Vector3.new(0, 5, 0)
end

function PitService.setTier(pit, tierIndex: number)
	local tier = Config.pitTier(tierIndex)

	pit.tierIndex = math.clamp(tierIndex, 1, #Config.Pit.Tiers)
	pit.tierName = tier.Name
	pit.totalBalls = tier.TotalBalls
	pit.ballsRemaining = tier.TotalBalls
	pit.settleDebt = 0
	pit.settleAccum = 0
	pit.settledTotal = 0
	pit.cleared = false
	pit.startedAt = os.clock()

	-- Wajib ikut direset. Kalau tidak, pengosongan kolam kedua dan
	-- seterusnya tidak pernah diumumkan dan rekor waktunya tidak tercatat.
	pit.announced = false

	PitService.sync(pit)
	PitService.liftOwner(pit)
end

function PitService.reset(pit)
	PitService.setTier(pit, pit.tierIndex)
end

-- ---------------------------------------------------------------- replikasi

function PitService.sync(pit)
	local player = pit.player
	if not player or not player.Parent then
		return
	end

	local part = pit.part
	if part then
		local height = math.max(Config.Pit.MinVisualHeight, PitService.surfaceY(pit) - pit.origin.Y)
		part.Size = Vector3.new(Config.Pit.SizeXZ.X, height, Config.Pit.SizeXZ.Y)
		part.CFrame = CFrame.new(pit.origin.X, pit.origin.Y + height / 2, pit.origin.Z)
	end

	player:SetAttribute("BallsRemaining", math.floor(pit.ballsRemaining))
	player:SetAttribute("BallsTotal", pit.totalBalls)
	player:SetAttribute("BallsSettled", math.floor(pit.settledTotal))
	player:SetAttribute("PitTier", pit.tierIndex)
	player:SetAttribute("PitName", pit.tierName)
end

-- ---------------------------------------------------------------- dunia

-- Lantai bersama, dibuat sekali. Cukup lebar untuk semua petak.
local function ensureWorld()
	if worldFolder and worldFolder.Parent then
		return
	end

	worldFolder = Instance.new("Folder")
	worldFolder.Name = "PitWorld"
	worldFolder.Parent = workspace

	local span = Config.Plot.Spacing * Config.Plot.MaxPlots
	local floor = Instance.new("Part")
	floor.Name = "Baseplate"
	floor.Anchored = true
	floor.Size = Vector3.new(span + 200, 4, 400)
	floor.CFrame = CFrame.new(span / 2 - Config.Plot.Spacing / 2, -2, 0)
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = Color3.fromRGB(74, 78, 86)
	floor.Parent = worldFolder
end

local function claimPlot(player: Player): number
	for index = 1, Config.Plot.MaxPlots do
		if plotOwners[index] == nil then
			plotOwners[index] = player
			return index
		end
	end
	-- Server penuh melebihi MaxPlots. Menumpuk di petak terakhir jelek,
	-- tapi jauh lebih baik daripada gagal memberi pemain kolam sama sekali.
	return Config.Plot.MaxPlots
end

local function buildPitParts(pit)
	local origin = pit.origin

	local part = Instance.new("Part")
	part.Name = "Pit"
	part.Anchored = true
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(158, 158, 158)
	part.Parent = pit.folder
	pit.part = part

	local zone = Instance.new("Part")
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
	local sell = PitService.sellPosition(pit)
	zone.Size = Vector3.new(Config.Sell.Radius * 2, Config.Pit.MaxHeight * 3, Config.Sell.Radius * 2)
	zone.CFrame = CFrame.new(sell.X, origin.Y + Config.Pit.MaxHeight, sell.Z)
	zone.Parent = pit.folder
	pit.sellZone = zone

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromScale(10, 2.2)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, Config.Pit.MaxHeight * 1.6, 0)
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

	-- Spawn menggantung di ketinggian permukaan penuh. Saat kolam menyusut,
	-- pemain menjatuhkan diri ke permukaan; Roblox tidak punya fall damage
	-- bawaan, jadi ini aman dan tidak butuh tangga.
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "PitSpawn"
	spawnPad.Anchored = true
	spawnPad.CanCollide = true
	spawnPad.Neutral = true

	-- Harus tetap Enabled. Player.RespawnLocation diabaikan kalau pad-nya
	-- dinonaktifkan, dan pemain justru dilempar ke spawn acak - persis yang
	-- ingin dicegah. Yang menjaga pemain tetap di petaknya adalah
	-- RespawnLocation per pemain, bukan mematikan pad milik orang lain.
	spawnPad.Enabled = true

	spawnPad.Size = Vector3.new(8, 1, 8)
	spawnPad.CFrame = CFrame.new(
		origin.X,
		origin.Y + Config.Pit.MaxHeight + 0.5,
		origin.Z - Config.Pit.SizeXZ.Y / 2 + 6
	)
	spawnPad.Material = Enum.Material.SmoothPlastic
	spawnPad.Color = Color3.fromRGB(60, 130, 200)
	spawnPad.Parent = pit.folder
	pit.spawnPad = spawnPad
end

--[[
	Buat kolam untuk pemain pada tier tertentu. Tier datang dari jumlah
	rebirth yang tersimpan, jadi pemain yang kembali langsung mendapat
	kolam yang sudah dibukanya.
]]
function PitService.create(player: Player, tierIndex: number)
	ensureWorld()

	local plotIndex = claimPlot(player)

	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. player.UserId
	folder.Parent = worldFolder

	local pit = {
		player = player,
		plotIndex = plotIndex,
		origin = Config.plotOrigin(plotIndex),
		folder = folder,

		tierIndex = 1,
		tierName = "",
		totalBalls = 1,
		ballsRemaining = 0,
		settleDebt = 0,
		settleAccum = 0,
		settledTotal = 0,
		cleared = false,
		announced = false,
		startedAt = os.clock(),
	}

	pits[player] = pit
	buildPitParts(pit)
	PitService.setTier(pit, tierIndex)

	-- Mengarahkan respawn ke petak sendiri. Tanpa ini pemain muncul di titik
	-- acak dan harus berjalan melewati kolam orang lain untuk pulang.
	player.RespawnLocation = pit.spawnPad

	return pit
end

function PitService.get(player: Player)
	return pits[player]
end

function PitService.destroy(player: Player)
	local pit = pits[player]
	if not pit then
		return
	end

	if plotOwners[pit.plotIndex] == player then
		plotOwners[pit.plotIndex] = nil
	end

	if pit.folder then
		pit.folder:Destroy()
	end
	pits[player] = nil
end

Players.PlayerRemoving:Connect(PitService.destroy)

return PitService
