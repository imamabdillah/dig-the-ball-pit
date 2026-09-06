--[[
	Client — input dan HUD kotak abu-abu minggu 1.

	Client TIDAK menghitung apa pun. Ia hanya:
	  1. menembakkan ray ke kolam dan mengusulkan satu titik ke server
	  2. membaca atribut yang tereplikasi dan menggambarnya

	Tidak ada prediksi lokal di minggu 1. Prediksi membuat galian terasa
	instan, tapi juga menyembunyikan penolakan server — dan penolakan itu
	justru yang perlu kamu lihat saat menguji validasi.
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
local pit = workspace:WaitForChild("Pit")

-- ---------------------------------------------------------------- input

local holding = false
local touchPosition: Vector3? = nil
local lastFire = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { pit }

--[[
	ScreenPointToRay (bukan ViewportPointToRay) karena posisi input dan
	GetMouseLocation sudah memperhitungkan inset GUI di atas layar.
	Memakai yang salah menggeser ray beberapa puluh piksel ke atas —
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
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent: Instance, size: UDim2, position: UDim2, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Size = size
	text.Position = position
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
panel.Size = UDim2.fromOffset(280, 116)
panel.Position = UDim2.fromOffset(16, 16)
panel.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
panel.BackgroundTransparency = 0.25
panel.BorderSizePixel = 0
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = panel

local cashLabel = label(panel, UDim2.new(1, -20, 0, 26), UDim2.fromOffset(12, 8), 20)
local bagLabel = label(panel, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 36), 16)
local pitLabel = label(panel, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 60), 16)
local toolLabel = label(panel, UDim2.new(1, -20, 0, 22), UDim2.fromOffset(12, 84), 14)

local toast = label(gui, UDim2.fromOffset(400, 26), UDim2.new(0, 16, 0, 140), 16)
toast.TextColor3 = Color3.fromRGB(120, 235, 170)

local shop = Instance.new("Frame")
shop.Size = UDim2.new(1, -32, 0, 52)
shop.Position = UDim2.new(0, 16, 1, -68)
shop.BackgroundTransparency = 1
shop.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 10)
layout.Parent = shop

local buttons: { [string]: TextButton } = {}

for _, line in Config.UpgradeOrder do
	local button = Instance.new("TextButton")
	button.Name = line
	button.Size = UDim2.fromOffset(190, 52)
	button.BackgroundColor3 = Color3.fromRGB(28, 32, 40)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 14
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Text = ""
	button.AutoButtonColor = true
	button.Parent = shop

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 6)
	buttonCorner.Parent = button

	button.Activated:Connect(function()
		Remotes.BuyUpgrade:FireServer(line)
	end)

	buttons[line] = button
end

Remotes.Notify.OnClientEvent:Connect(function(message: string)
	toast.Text = message
	task.delay(2.5, function()
		if toast.Text == message then
			toast.Text = ""
		end
	end)
end)

-- Digambar ulang 10 kali per detik. Cukup untuk angka, dan tidak membakar
-- frame budget di HP kelas bawah — target 60 FPS di perangkat terlemah.
task.spawn(function()
	while gui.Parent do
		local cash = player:GetAttribute("Cash") or 0
		local bag = player:GetAttribute("Bag") or 0
		local capacity = player:GetAttribute("BagCapacity") or 0
		local perDig = player:GetAttribute("BallsPerDig") or 0
		local remaining = workspace:GetAttribute("BallsRemaining") or 0
		local total = workspace:GetAttribute("BallsTotal") or Config.Pit.TotalBalls

		cashLabel.Text = string.format("Cash  %d", cash)
		bagLabel.Text = string.format("Kantong  %d / %d", bag, capacity)
		pitLabel.Text = string.format("Kolam  %d / %d bola", remaining, total)

		local toolName = Config.levelName("tool", player:GetAttribute("ToolLevel") or 1) or "?"
		local wallReduction = player:GetAttribute("WallReduction") or 0
		toolLabel.Text = string.format("%s  %d/sedot   dinding %d%%", toolName, perDig, math.floor(wallReduction * 100))

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

		task.wait(0.1)
	end
end)
