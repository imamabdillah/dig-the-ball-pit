--[[
	Client - input dan HUD kotak abu-abu.

	Client TIDAK menghitung apa pun. Ia hanya:
	  1. menembakkan ray ke kolam MILIKNYA dan mengusulkan satu titik
	  2. membaca atribut yang tereplikasi dan menggambarnya

	Tidak ada prediksi lokal. Prediksi membuat galian terasa instan, tapi
	juga menyembunyikan penolakan server - dan penolakan itu justru yang
	perlu terlihat saat menguji validasi.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Kolam sendiri, bukan kolam siapa pun. Filter ray dibatasi ke part ini
-- saja, jadi mengarahkan kursor ke kolam tetangga tidak menghasilkan apa-apa
-- di client - jauh sebelum server sempat menolaknya.
local world = workspace:WaitForChild("PitWorld")
local plot = world:WaitForChild("Plot_" .. player.UserId)
local pitPart = plot:WaitForChild("Pit")

-- ---------------------------------------------------------------- input

local holding = false
local touchPosition: Vector3? = nil
local lastFire = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { pitPart }

--[[
	ScreenPointToRay (bukan ViewportPointToRay) karena posisi input dan
	GetMouseLocation sudah memperhitungkan inset GUI di atas layar.
	Memakai yang salah menggeser ray beberapa puluh piksel ke atas -
	terlihat sebagai "galian meleset sedikit" yang sulit dilacak.
]]
local function pointerPosition(): Vector2
	if touchPosition then
		return Vector2.new(touchPosition.X, touchPosition.Y)
	end
	return UserInputService:GetMouseLocation()
end

UserInputService.InputBegan:Connect(function(input, processedByGui)
	if processedByGui then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = true
	elseif input.UserInputType == Enum.UserInputType.Touch then
		holding = true
		touchPosition = input.Position
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		touchPosition = input.Position
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holding = false
	elseif input.UserInputType == Enum.UserInputType.Touch then
		holding = false
		touchPosition = nil
	end
end)

RunService.RenderStepped:Connect(function()
	if not holding then
		return
	end

	local now = os.clock()
	if now - lastFire < Config.Dig.Interval then
		return
	end

	local pointer = pointerPosition()
	local ray = camera:ScreenPointToRay(pointer.X, pointer.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, rayParams)
	if not result then
		return
	end

	lastFire = now
	Remotes.DigRequest:FireServer(result.Position)
end)

-- ---------------------------------------------------------------- HUD

local gui = Instance.new("ScreenGui")
gui.Name = "PitHud"
gui.ResetOnSpawn = false

-- IgnoreGuiInset harus false. Dengan true, panel di (16,16) duduk tepat di
-- bawah tombol menu dan chat milik Roblox sendiri, dan baris Cash tertutup.
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent: Instance, height: number, y: number, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -20, 0, height)
	text.Position = UDim2.fromOffset(12, y)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Code
	text.TextSize = textSize
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.5
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Text = ""
	text.Parent = parent
	return text
end

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(320, 162)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = panel

local cashLabel = label(panel, 26, 8, 20)
local gemsLabel = label(panel, 22, 36, 15)
gemsLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
local bagLabel = label(panel, 22, 58, 16)
local pitLabel = label(panel, 22, 82, 16)
local toolLabel = label(panel, 22, 106, 14)

--[[
	Baris longsor. Ini satu-satunya tempat pemain bisa melihat apa yang
	dibeli upgrade dinding: laju efektif turun 30% ke 19% ke 12%, dan
	penghitung bola yang kembali melambat mengikutinya.

	Sampai lubang dan animasi longsornya ada di minggu 3, angka inilah
	seluruh umpan baliknya.
]]
local settleLabel = label(panel, 22, 130, 14)
settleLabel.TextColor3 = Color3.fromRGB(240, 150, 120)

local toast = label(gui, 26, 0, 16)
toast.Position = UDim2.fromOffset(16, 186)
toast.Size = UDim2.fromOffset(520, 26)
toast.TextColor3 = Color3.fromRGB(120, 235, 170)

-- ---------------------------------------------------------------- tombol

local shop = Instance.new("Frame")
shop.Size = UDim2.new(1, -32, 0, 52)
shop.Position = UDim2.new(0, 16, 1, -68)
shop.BackgroundTransparency = 1
shop.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)

-- Tanpa baris ini UIListLayout memakai SortOrder.Name dan mengurutkan tombol
-- secara alfabet: bag, tool, wall. Config.UpgradeOrder jadi diabaikan.
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = shop

local function styledButton(parent: Instance): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.fromOffset(190, 52)
	button.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = parent

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	return button
end

local buttons: { [string]: TextButton } = {}

for index, line in Config.UpgradeOrder do
	local button = styledButton(shop)
	button.Name = line
	button.LayoutOrder = index

	button.Activated:Connect(function()
		Remotes.BuyUpgrade:FireServer(line)
	end)

	buttons[line] = button
end

--[[
	Tombol rebirth hanya muncul saat kolam kosong.

	Sengaja tidak diletakkan di deret toko: rebirth menghapus seluruh
	belanjaan, dan tombol sebesar itu tidak boleh bersebelahan dengan
	tombol yang ditekan ratusan kali per sesi.
]]
local rebirthButton = styledButton(gui)
rebirthButton.Size = UDim2.fromOffset(360, 52)
rebirthButton.Position = UDim2.new(0.5, -180, 1, -132)
rebirthButton.BackgroundColor3 = Color3.fromRGB(96, 62, 140)
rebirthButton.TextSize = 14
rebirthButton.Visible = false
rebirthButton.Activated:Connect(function()
	Remotes.Rebirth:FireServer()
end)

Remotes.Notify.OnClientEvent:Connect(function(message: string)
	toast.Text = message
	task.delay(3, function()
		if toast.Text == message then
			toast.Text = ""
		end
	end)
end)

-- Digambar ulang 10 kali per detik. Cukup untuk angka, dan tidak membakar
-- frame budget di HP kelas bawah - target 60 FPS di perangkat terlemah.
task.spawn(function()
	while gui.Parent do
		local cash = player:GetAttribute("Cash") or 0
		local gems = player:GetAttribute("Gems") or 0
		local bag = player:GetAttribute("Bag") or 0
		local capacity = player:GetAttribute("BagCapacity") or 0
		local perDig = player:GetAttribute("BallsPerDig") or 0
		local remaining = player:GetAttribute("BallsRemaining") or 0
		local total = player:GetAttribute("BallsTotal") or 1
		local rebirths = player:GetAttribute("Rebirths") or 0
		local multiplier = player:GetAttribute("CashMultiplier") or 1
		local pitName = player:GetAttribute("PitName") or "?"

		if multiplier > 1 then
			cashLabel.Text = string.format("Cash  %d   x%.2f", cash, multiplier)
		else
			cashLabel.Text = string.format("Cash  %d", cash)
		end

		gemsLabel.Text = string.format("Gems  %d   rebirth %d", gems, rebirths)
		bagLabel.Text = string.format("Kantong  %d / %d", bag, capacity)
		pitLabel.Text = string.format("%s  %d / %d", pitName, remaining, total)

		local toolName = Config.levelName("tool", player:GetAttribute("ToolLevel") or 1) or "?"
		toolLabel.Text = string.format("%s  %d/sedot", toolName, perDig)

		-- Laju efektif dihitung di client dari angka yang sama dengan server:
		-- BaseRate dikurangi peredaman dinding. Menampilkan hasilnya, bukan
		-- persen dindingnya, karena yang pemain butuh tahu adalah berapa
		-- banyak bola yang masih hilang - bukan seberapa bagus dindingnya.
		local wallReduction = player:GetAttribute("WallReduction") or 0
		local effectiveRate = Config.Settle.BaseRate * (1 - wallReduction)
		local settled = player:GetAttribute("BallsSettled") or 0
		settleLabel.Text = string.format("Longsor  %d%%   sudah balik %d bola", math.floor(effectiveRate * 100 + 0.5), settled)

		for _, line in Config.UpgradeOrder do
			local definition = Config.Upgrades[line]
			local level = player:GetAttribute(Config.UpgradeAttribute[line]) or 1
			local nextLevel = Config.nextLevel(line, level)
			local button = buttons[line]

			if nextLevel then
				button.Text = string.format("%s\n%s — %d", definition.Label, nextLevel.Name, nextLevel.Cost)
				local affordable = cash >= nextLevel.Cost
				button.BackgroundColor3 = affordable and Color3.fromRGB(22, 92, 58) or Color3.fromRGB(28, 32, 40)
			else
				button.Text = string.format("%s\nmaksimal", definition.Label)
				button.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
			end
		end

		rebirthButton.Visible = remaining <= 0
		if rebirthButton.Visible then
			--[[
				Tombol harus menjawab "saya dapat apa", bukan cuma "saya
				kehilangan apa". Baris kedua menyebut alat dan kantong yang
				sudah terpasang setelah rebirth - itu yang menghapus rasa
				kembali ke nol, dan pemain harus melihatnya SEBELUM menekan.
			]]
			local nextRebirths = rebirths + 1
			local toolStart = Config.levelName("tool", Config.startingLevel("tool", nextRebirths)) or "?"
			local bagStart = Config.levelName("bag", Config.startingLevel("bag", nextRebirths)) or "?"

			local headline
			if Config.nextPitUnlockAt(rebirths) == nextRebirths then
				headline = "REBIRTH — buka kolam berikutnya"
			else
				headline = string.format("REBIRTH — cash x%.2f", Config.cashMultiplier(nextRebirths))
			end

			rebirthButton.Text = string.format("%s\nmulai dari %s + %s", headline, toolStart, bagStart)
		end

		task.wait(0.1)
	end
end)
