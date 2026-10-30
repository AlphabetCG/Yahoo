-- ClientMain: menu, HUD, shop, upgrades, settings, speed button, camera and unit placement.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local startGameRemote = remotes:WaitForChild("StartGame")
local returnToMenuRemote = remotes:WaitForChild("ReturnToMenu")
local surrenderRemote = remotes:WaitForChild("Surrender")
local setSpeedRemote = remotes:WaitForChild("SetSpeed")
local setAutoSkipRemote = remotes:WaitForChild("SetAutoSkip")
local beginMatchRemote = remotes:WaitForChild("BeginMatch")
local retryRemote = remotes:WaitForChild("Retry")
local placeTowerRemote = remotes:WaitForChild("PlaceTower")
local upgradeTowerRemote = remotes:WaitForChild("UpgradeTower")
local sellTowerRemote = remotes:WaitForChild("SellTower")
local setTargetingRemote = remotes:WaitForChild("SetTargeting")
local towerModels = ReplicatedStorage:WaitForChild("TowerModels")
local towersFolder = workspace:WaitForChild("Towers")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- ===== Style =====
local WOOD = Color3.fromRGB(176, 118, 62)
local WOOD_LIGHT = Color3.fromRGB(205, 150, 90)
local WOOD_DARK = Color3.fromRGB(96, 58, 28)
local WOOD_DEEP = Color3.fromRGB(62, 36, 16)
local GOLD = Color3.fromRGB(255, 205, 70)
local RED = Color3.fromRGB(255, 100, 100)
local GREEN = Color3.fromRGB(120, 235, 120)
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.Arcade

local function make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function tween(obj, seconds, props)
	TweenService:Create(obj, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function fmt(n)
	local s = tostring(math.floor(n))
	local k
	repeat
		s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return s
end

local function currentState()
	return workspace:GetAttribute("State") or "Menu"
end

-- ===== Buttons (wooden, with hover effect) =====
local buttonBase = setmetatable({}, { __mode = "k" })
local buttonShine = setmetatable({}, { __mode = "k" })

local function setButtonColor(b, color)
	buttonBase[b] = color
	tween(b, 0.12, { BackgroundColor3 = color })
	if buttonShine[b] then
		buttonShine[b].BackgroundColor3 = color:Lerp(WHITE, 0.3)
	end
end

local function woodButton(parent, text, size, position, textSize, base, edge)
	base = base or WOOD
	edge = edge or WOOD_DARK
	local b = make("TextButton", {
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Text = text,
		Font = FONT,
		TextSize = textSize or 30,
		TextColor3 = GOLD,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = edge,
		AutoButtonColor = false,
	}, parent)
	make("UIStroke", { Color = edge, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	buttonBase[b] = base
	buttonShine[b] = make("Frame", {
		Size = UDim2.new(1, -8, 0, 5),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = base:Lerp(WHITE, 0.3),
		BorderSizePixel = 0,
	}, b)
	b.MouseEnter:Connect(function()
		tween(b, 0.1, { BackgroundColor3 = buttonBase[b]:Lerp(WHITE, 0.2) })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.1, { BackgroundColor3 = buttonBase[b] })
	end)
	return b
end

local RED_BTN = Color3.fromRGB(180, 62, 52)
local RED_EDGE = Color3.fromRGB(92, 26, 22)
local GREEN_BTN = Color3.fromRGB(86, 160, 70)
local GREEN_EDGE = Color3.fromRGB(40, 84, 34)

local function woodPanel(parent, props)
	props.BackgroundColor3 = props.BackgroundColor3 or WOOD
	props.BorderSizePixel = 0
	local f = make("Frame", props, parent)
	make("UIStroke", { Color = WOOD_DEEP, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	return f
end

local function label(parent, props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0
	props.TextStrokeColor3 = props.TextStrokeColor3 or WOOD_DEEP
	return make("TextLabel", props, parent)
end

-- ===== Top-down camera =====
local camHeight = 75
local CAMERA_X = 10 -- shifts the map a little left so the shop panel does not cover it

RunService:BindToRenderStep("TopDownCamera", Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 70
	local target = Vector3.new(CAMERA_X, Config.GroundY, 0)
	cam.CFrame = CFrame.lookAt(target + Vector3.new(0, camHeight, 0), target, Vector3.new(0, 0, -1))
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		camHeight = math.clamp(camHeight - input.Position.Z * 5, 50, 95)
	end
end)

-- =====================================================================
--  MAIN MENU
-- =====================================================================
local menuGui = make("ScreenGui", {
	Name = "TDMenuGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 1,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local menu = make("Frame", {
	Name = "Menu",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(120, 190, 240),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, menuGui)
make("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(70, 150, 235), Color3.fromRGB(200, 234, 247)),
	Rotation = 90,
}, menu)

-- drifting pixel clouds
local function cloud(startX, y, w, seconds)
	local c = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(w, w * 0.35),
		Position = UDim2.fromScale(startX, y),
	}, menu)
	make("Frame", { Size = UDim2.fromScale(1, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, c)
	make("Frame", { Size = UDim2.fromScale(0.6, 0.5), Position = UDim2.fromScale(0.15, 0.15), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, c)
	make("Frame", { Size = UDim2.fromScale(0.3, 0.5), Position = UDim2.fromScale(0.55, 0), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, c)
	task.spawn(function()
		local x = startX
		while true do
			local t = TweenService:Create(c, TweenInfo.new(seconds * (1.1 - x) / 1.4, Enum.EasingStyle.Linear), { Position = UDim2.fromScale(1.05, y) })
			c.Position = UDim2.fromScale(x, y)
			t:Play()
			t.Completed:Wait()
			x = -0.3
		end
	end)
end
cloud(0.05, 0.08, 220, 90)
cloud(0.6, 0.05, 280, 110)
cloud(0.3, 0.6, 180, 75)

-- ground strip + dirt
make("Frame", { Position = UDim2.fromScale(0, 0.84), Size = UDim2.fromScale(1, 0.04), BackgroundColor3 = Color3.fromRGB(84, 170, 64), BorderSizePixel = 0 }, menu)
make("Frame", { Position = UDim2.fromScale(0, 0.88), Size = UDim2.fromScale(1, 0.12), BackgroundColor3 = Color3.fromRGB(121, 85, 72), BorderSizePixel = 0 }, menu)

local function pine(x, h)
	local tone = Color3.fromRGB(140, 200, 150)
	local t = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(x, 0.84),
		Size = UDim2.fromOffset(h * 0.6, h),
		BackgroundTransparency = 1,
	}, menu)
	for i = 0, 2 do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, i * 0.28),
			Size = UDim2.fromScale(1 - (2 - i) * 0.28, 0.32),
			BackgroundColor3 = tone,
			BorderSizePixel = 0,
		}, t)
	end
	make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.14, 0.14), BackgroundColor3 = tone, BorderSizePixel = 0 }, t)
end
pine(0.12, 190)
pine(0.2, 150)
pine(0.3, 210)
pine(0.8, 170)
pine(0.9, 220)

-- title (with a pixel drop shadow, gently bobbing)
local titleBox = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.2),
	Size = UDim2.fromScale(0.9, 0.16),
	BackgroundTransparency = 1,
}, menu)
label(titleBox, {
	Position = UDim2.fromOffset(5, 6),
	Size = UDim2.fromScale(1, 1),
	Text = "ANIME TOWER DEFENSE",
	TextScaled = true,
	TextColor3 = WOOD_DEEP,
	TextStrokeTransparency = 1,
})
label(titleBox, {
	Size = UDim2.fromScale(1, 1),
	Text = "ANIME TOWER DEFENSE",
	TextScaled = true,
	TextColor3 = GOLD,
	ZIndex = 2,
})
TweenService:Create(titleBox, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = UDim2.fromScale(0.5, 0.215),
}):Play()

local playButton = woodButton(menu, "PLAY", UDim2.fromOffset(340, 84), UDim2.fromScale(0.5, 0.5), 44, GREEN_BTN, GREEN_EDGE)
local howButton = woodButton(menu, "HOW TO PLAY", UDim2.fromOffset(340, 60), UDim2.new(0.5, 0, 0.5, 90), 26)

label(menu, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 160),
	Size = UDim2.fromOffset(700, 30),
	Text = "Stop the enemies before they reach the end of the path!",
	TextSize = 20,
})

-- how-to-play popup
local howDim = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
	ZIndex = 20,
}, menu)
local howPanel = woodPanel(howDim, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(620, 400),
	ZIndex = 21,
})
label(howPanel, {
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, 0, 0, 44),
	Text = "HOW TO PLAY",
	TextSize = 34,
	TextColor3 = GOLD,
	ZIndex = 22,
})
label(howPanel, {
	Position = UDim2.fromOffset(28, 66),
	Size = UDim2.new(1, -56, 1, -150),
	Text = "- Press PLAY. You get 60 seconds to prepare (START MATCH skips the wait). Pick a unit on the right (or press 1 / 2).\n"
		.. "- Click on the grass to place it. Right-click cancels.\n"
		.. "- Click a placed unit to upgrade it, change its target, or sell it (you get half back).\n"
		.. "- Units shoot the enemy that is furthest along the path.\n"
		.. "- A new round starts once most enemies have appeared (AUTO SKIP). Turn it off to wait for the full wave.\n"
		.. "- Use the SPEED button to fast-forward (x1 / x2 / x3).\n"
		.. "- Scroll the mouse wheel to zoom the camera.",
	TextSize = 22,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 22,
})
local howClose = woodButton(howPanel, "GOT IT", UDim2.fromOffset(200, 56), UDim2.new(0.5, 0, 1, -42), 26, GREEN_BTN, GREEN_EDGE)
howClose.ZIndex = 22
howButton.MouseButton1Click:Connect(function() howDim.Visible = true end)
howClose.MouseButton1Click:Connect(function() howDim.Visible = false end)

-- =====================================================================
--  HUD (respects the Roblox top bar so nothing is hidden under it)
-- =====================================================================
local hudGui = make("ScreenGui", {
	Name = "TDHudGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	DisplayOrder = 2,
	Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local SHOP_W = 200

local function statPlate(parent, icon, color, y)
	local f = woodPanel(parent, { Size = UDim2.fromOffset(220, 44), Position = UDim2.fromOffset(16, y) })
	make("TextLabel", {
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = WOOD_DARK,
		BorderSizePixel = 0,
		Text = icon,
		Font = Enum.Font.SourceSansBold,
		TextSize = 26,
		TextColor3 = WHITE,
	}, f)
	return label(f, {
		Position = UDim2.fromOffset(54, 0),
		Size = UDim2.new(1, -62, 1, 0),
		TextSize = 26,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
end
local livesValue = statPlate(hudGui, "❤", RED, 12)
local cashValue = statPlate(hudGui, "💰", GOLD, 64)

-- round / countdown (centered over the map area)
local roundPlate = woodPanel(hudGui, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2 + 26, 0, 12),
	Size = UDim2.fromOffset(230, 44),
})
local roundLabel = label(roundPlate, { Size = UDim2.fromScale(1, 1), TextSize = 26, Text = "" })

-- stage timer (time spent on this stage), right next to the round counter
local timePlate = woodPanel(hudGui, {
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2 + 34, 0, 12),
	Size = UDim2.fromOffset(170, 44),
})
local timeLabel = label(timePlate, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = GOLD, Text = "TIME 00:00" })
local countdownPlate = woodPanel(hudGui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2, 0, 64),
	Size = UDim2.fromOffset(300, 34),
	Visible = false,
})
local countdownLabel = label(countdownPlate, { Size = UDim2.fromScale(1, 1), TextSize = 20, TextColor3 = GOLD, Text = "" })

-- prep phase: countdown + START MATCH button
local prepPanel = woodPanel(hudGui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2, 0, 70),
	Size = UDim2.fromOffset(380, 142),
	Visible = false,
})
local prepTitle = label(prepPanel, {
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 34),
	TextSize = 26,
	TextColor3 = GOLD,
	Text = "",
})
label(prepPanel, {
	Position = UDim2.fromOffset(0, 42),
	Size = UDim2.new(1, 0, 0, 22),
	TextSize = 16,
	TextColor3 = Color3.fromRGB(240, 225, 200),
	Text = "Place your units before the match begins!",
})
local startMatchButton = woodButton(prepPanel, "START MATCH", UDim2.fromOffset(300, 58), UDim2.new(0.5, 0, 0, 104), 28, GREEN_BTN, GREEN_EDGE)

-- settings (gear) button
local gearButton = woodButton(hudGui, "⚙", UDim2.fromOffset(48, 48), UDim2.new(1, -(SHOP_W + 36), 0, 36), 28)
gearButton.Font = Enum.Font.SourceSansBold

-- bottom messages
local notice = label(hudGui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, -SHOP_W / 2, 1, -52),
	Size = UDim2.fromOffset(520, 36),
	TextSize = 26,
	TextColor3 = RED,
	Text = "",
	Visible = false,
	ZIndex = 5,
})
local noticeId = 0
local function notify(msg)
	noticeId += 1
	local id = noticeId
	notice.Text = msg
	notice.Visible = true
	task.delay(1.6, function()
		if noticeId == id then notice.Visible = false end
	end)
end

local hint = label(hudGui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, -SHOP_W / 2, 1, -14),
	Size = UDim2.fromOffset(600, 30),
	TextSize = 20,
	Text = "Click to place   -   Right-click or Q to cancel",
	Visible = false,
})

-- ===== Shop panel =====
local shop = make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, SHOP_W, 1, 0),
	BackgroundColor3 = WOOD_DARK,
	BorderSizePixel = 0,
}, hudGui)
make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = WOOD_DEEP, BorderSizePixel = 0 }, shop)
label(shop, {
	Size = UDim2.new(1, 0, 0, 44),
	Text = "UNITS",
	TextSize = 30,
	TextColor3 = GOLD,
})
local list = make("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 46),
	Size = UDim2.new(1, -18, 1, -46 - 150),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, shop)
make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, list)

local speedButton = woodButton(shop, "SPEED  X1", UDim2.fromOffset(176, 56), UDim2.new(0.5, 2, 1, -44), 24)
local autoSkipButton = woodButton(shop, "AUTO SKIP: ON", UDim2.fromOffset(176, 52), UDim2.new(0.5, 2, 1, -108), 20)

-- =====================================================================
--  Placement / selection state
-- =====================================================================
local selectedUnit = nil            -- unit chosen in the shop (placing mode)
local ghost, ring, tint             -- placement preview
local ghostOffset = 0
local cards = {}
local placing = false

local selectedTower = nil           -- placed unit chosen for upgrading
local towerRing, towerHighlight
local towerConns = {}

local function makeRing(range, color, transparency)
	return make("Part", {
		Name = "RangeRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, range * 2, range * 2),
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = transparency,
		Material = Enum.Material.SmoothPlastic,
		Color = color,
		CFrame = CFrame.new(0, Config.GroundY + 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
	}, workspace)
end

local function ringCFrame(x, z)
	return CFrame.new(x, Config.GroundY + 0.5, z) * CFrame.Angles(0, 0, math.rad(90))
end

-- ===== Upgrade panel (bottom-left) =====
local upPanel = woodPanel(hudGui, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(300, 356),
	Visible = false,
})
local upTitle = label(upPanel, {
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -64, 0, 34),
	TextSize = 24,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
local upClose = woodButton(upPanel, "X", UDim2.fromOffset(34, 34), UDim2.new(1, -26, 0, 26), 20, RED_BTN, RED_EDGE)
make("Frame", { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 3), BackgroundColor3 = WOOD_DARK, BorderSizePixel = 0 }, upPanel)

local function statRow(y)
	return label(upPanel, {
		Position = UDim2.fromOffset(14, y),
		Size = UDim2.new(1, -28, 0, 26),
		TextSize = 20,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
	})
end
local rowDamage = statRow(58)
local rowRange = statRow(88)
local rowSpeed = statRow(118)
local upName = label(upPanel, {
	Position = UDim2.fromOffset(14, 148),
	Size = UDim2.new(1, -28, 0, 26),
	TextSize = 18,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
local upButton = woodButton(upPanel, "UPGRADE", UDim2.new(1, -28, 0, 54), UDim2.new(0.5, 0, 0, 202), 24, GREEN_BTN, GREEN_EDGE)

-- targeting selector:  <  TARGET: FIRST  >
local targetPrev = woodButton(upPanel, "<", UDim2.fromOffset(40, 40), UDim2.new(0, 34, 0, 258), 24)
local targetNext = woodButton(upPanel, ">", UDim2.fromOffset(40, 40), UDim2.new(1, -34, 0, 258), 24)
local targetLabel = label(upPanel, {
	Position = UDim2.fromOffset(60, 238),
	Size = UDim2.new(1, -120, 0, 40),
	BackgroundTransparency = 0,
	BackgroundColor3 = WOOD_DARK,
	BorderSizePixel = 0,
	TextSize = 16,
	Text = "",
})

-- sell button
local sellButton = woodButton(upPanel, "SELL", UDim2.new(1, -28, 0, 50), UDim2.new(0.5, 0, 0, 316), 22, RED_BTN, RED_EDGE)

local function statText(name, cur, nxt, fn)
	if nxt ~= nil and nxt ~= cur then
		return ("%s  %s  <font color='#7CFF7C'>&gt;  %s</font>"):format(name, fn(cur), fn(nxt))
	end
	return ("%s  %s"):format(name, fn(cur))
end
local function fmtNum(v) return tostring(v) end
local function fmtRate(cooldown) return ("%.1f/s"):format(1 / cooldown) end

local function refreshUpgradePanel()
	if not selectedTower or not selectedTower.Parent then
		upPanel.Visible = false
		return
	end
	local unitName = selectedTower:GetAttribute("UnitName")
	local level = selectedTower:GetAttribute("Level") or 1
	local cur = Config.GetStats(unitName, level)
	if not cur then return end
	local nxt = Config.GetStats(unitName, level + 1)

	upPanel.Visible = true
	upTitle.Text = string.upper(unitName) .. "  LV " .. level
	rowDamage.Text = statText("DAMAGE", cur.Damage, nxt and nxt.Damage, fmtNum)
	rowRange.Text = statText("RANGE ", cur.Range, nxt and nxt.Range, fmtNum)
	rowSpeed.Text = statText("SPEED ", 1 / cur.Cooldown, nxt and (1 / nxt.Cooldown), function(v) return ("%.1f/s"):format(v) end)

	local mine = selectedTower:GetAttribute("OwnerId") == player.UserId

	-- targeting + sell info
	local mode = selectedTower:GetAttribute("Targeting") or "First"
	targetLabel.Text = "TARGET: " .. string.upper(mode)
	targetLabel.TextColor3 = (mode == "None") and RED or WHITE
	local spent = selectedTower:GetAttribute("Spent") or 0
	sellButton.Text = mine and ("SELL  $" .. fmt(math.floor(spent * Config.SellRefund))) or "SELL  (NOT YOURS)"
	setButtonColor(sellButton, mine and RED_BTN or Color3.fromRGB(110, 110, 110))
	if not nxt then
		upName.Text = "FULLY UPGRADED!"
		upButton.Text = "MAX LEVEL"
		setButtonColor(upButton, Color3.fromRGB(110, 110, 110))
	elseif not mine then
		upName.Text = "Belongs to another player"
		upButton.Text = "LOCKED"
		setButtonColor(upButton, Color3.fromRGB(110, 110, 110))
	else
		upName.Text = "NEXT: " .. string.upper(nxt.Name)
		upButton.Text = "UPGRADE  $" .. fmt(nxt.Cost)
		local affordable = (player:GetAttribute("Money") or 0) >= nxt.Cost
		setButtonColor(upButton, affordable and GREEN_BTN or Color3.fromRGB(150, 80, 70))
	end
end

local function updateTowerRing()
	if towerRing then towerRing:Destroy() towerRing = nil end
	if not selectedTower or not selectedTower.Parent then return end
	local stats = Config.GetStats(selectedTower:GetAttribute("UnitName"), selectedTower:GetAttribute("Level") or 1)
	if not stats then return end
	towerRing = makeRing(stats.Range, WHITE, 0.72)
	local p = selectedTower:GetPivot().Position
	towerRing.CFrame = ringCFrame(p.X, p.Z)
end

local function deselectTower()
	for _, c in ipairs(towerConns) do c:Disconnect() end
	table.clear(towerConns)
	selectedTower = nil
	if towerRing then towerRing:Destroy() towerRing = nil end
	if towerHighlight then towerHighlight:Destroy() towerHighlight = nil end
	upPanel.Visible = false
end

local function selectTower(model)
	if selectedTower == model then return end
	deselectTower()
	selectedTower = model
	towerHighlight = make("Highlight", {
		FillTransparency = 1,
		OutlineColor = WHITE,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Adornee = model,
	}, workspace)
	table.insert(towerConns, model:GetAttributeChangedSignal("Level"):Connect(function()
		updateTowerRing()
		refreshUpgradePanel()
	end))
	for _, attr in ipairs({ "Targeting", "Spent" }) do
		table.insert(towerConns, model:GetAttributeChangedSignal(attr):Connect(refreshUpgradePanel))
	end
	table.insert(towerConns, model.AncestryChanged:Connect(function(_, parent)
		if not parent and selectedTower == model then deselectTower() end
	end))
	updateTowerRing()
	refreshUpgradePanel()
end

local upgrading = false
local function tryUpgrade()
	if not selectedTower or upgrading then return end
	upgrading = true
	local ok, success, reason = pcall(function()
		return upgradeTowerRemote:InvokeServer(selectedTower)
	end)
	upgrading = false
	if ok and not success then notify(reason or "Cannot upgrade") end
end
upButton.MouseButton1Click:Connect(tryUpgrade)
upClose.MouseButton1Click:Connect(deselectTower)

-- sell (returns half of everything spent on the unit)
local selling = false
sellButton.MouseButton1Click:Connect(function()
	if not selectedTower or selling then return end
	local model = selectedTower
	selling = true
	local ok, success, result = pcall(function()
		return sellTowerRemote:InvokeServer(model)
	end)
	selling = false
	if ok and not success then notify(result or "Cannot sell") end
end)

-- targeting mode arrows
local function cycleTarget(step)
	if not selectedTower then return end
	local modes = Config.TargetModes
	local current = selectedTower:GetAttribute("Targeting") or "First"
	local idx = table.find(modes, current) or 1
	idx = (idx - 1 + step) % #modes + 1
	setTargetingRemote:FireServer(selectedTower, modes[idx])
end
targetPrev.MouseButton1Click:Connect(function() cycleTarget(-1) end)
targetNext.MouseButton1Click:Connect(function() cycleTarget(1) end)

-- ===== Shop cards + placement preview =====
local function refreshCards()
	local money = player:GetAttribute("Money") or 0
	for name, card in pairs(cards) do
		local affordable = money >= Config.Units[name].Cost
		card.Cost.TextColor3 = affordable and GOLD or RED
		card.Button.BackgroundColor3 = affordable and WOOD or Color3.fromRGB(128, 92, 66)
		card.Stroke.Color = (selectedUnit == name) and WHITE or WOOD_DEEP
		card.Stroke.Thickness = (selectedUnit == name) and 5 or 4
	end
end

local function clearGhost()
	if ghost then ghost:Destroy() ghost = nil end
	if ring then ring:Destroy() ring = nil end
	tint = nil
end

local function selectUnit(name)
	clearGhost()
	selectedUnit = nil
	if name and currentState() == "Playing" then
		local template = towerModels:FindFirstChild(name)
		local unit = Config.Units[name]
		if template and unit then
			deselectTower()
			selectedUnit = name
			ghost = template:Clone()
			local hum = ghost:FindFirstChildOfClass("Humanoid")
			if hum then hum:Destroy() end
			ghost:ScaleTo(Config.TowerScale)
			for _, d in ipairs(ghost:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			ghost:PivotTo(CFrame.new(0, 50, 0))
			local bcf, bsize = ghost:GetBoundingBox()
			ghostOffset = 50 - (bcf.Position.Y - bsize.Y / 2)
			tint = make("Highlight", {
				Name = "Tint",
				FillTransparency = 0.5,
				OutlineTransparency = 0,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			}, ghost)
			ghost.Parent = workspace
			ring = makeRing(unit.Levels[1].Range, WHITE, 0.65)
		end
	end
	hint.Visible = selectedUnit ~= nil
	refreshCards()
end

local function getMouseGroundPos()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local loc = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then return nil end
	local t = (Config.GroundY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then return nil end
	return ray.Origin + ray.Direction * t
end

local towerRayParams = RaycastParams.new()
towerRayParams.FilterType = Enum.RaycastFilterType.Include
towerRayParams.FilterDescendantsInstances = { towersFolder }

local function getTowerUnderMouse()
	local cam = workspace.CurrentCamera
	if not cam then return nil end
	local loc = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(loc.X, loc.Y)
	local result = workspace:Raycast(ray.Origin, ray.Direction * 500, towerRayParams)
	if result then
		local m = result.Instance:FindFirstAncestorWhichIsA("Model")
		if m and m.Parent == towersFolder then return m end
	end
	return nil
end

-- unit preview inside a shop card
local function makePreview(parent, name)
	local vp = make("ViewportFrame", {
		Size = UDim2.new(1, -10, 0, 84),
		Position = UDim2.fromOffset(5, 6),
		BackgroundColor3 = Color3.fromRGB(120, 190, 235),
		BorderSizePixel = 0,
	}, parent)
	local template = towerModels:FindFirstChild(name)
	if not template then return end
	local m = template:Clone()
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then hum:Destroy() end
	m:PivotTo(CFrame.new(0, 0, 0))
	m.Parent = vp
	local cam = make("Camera", {
		FieldOfView = 30,
		CFrame = CFrame.lookAt(Vector3.new(5, 0.5, -17), Vector3.new(0, -0.5, 0)),
	}, vp)
	vp.CurrentCamera = cam
end

for i, name in ipairs(Config.UnitOrder) do
	local unit = Config.Units[name]
	local base = unit.Levels[1]
	local card = make("TextButton", {
		Name = name,
		LayoutOrder = i,
		Size = UDim2.new(1, 0, 0, 190),
		BackgroundColor3 = WOOD,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, list)
	local stroke = make("UIStroke", { Color = WOOD_DEEP, Thickness = 4, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	makePreview(card, name)
	label(card, {
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(30, 18),
		Text = "[" .. i .. "]",
		TextSize = 16,
		ZIndex = 3,
	})
	label(card, {
		Position = UDim2.fromOffset(0, 94),
		Size = UDim2.new(1, 0, 0, 26),
		Text = string.upper(name),
		TextSize = 22,
	})
	label(card, {
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 20),
		Text = ("DMG %d   RNG %d"):format(base.Damage, base.Range),
		TextSize = 15,
		TextColor3 = Color3.fromRGB(240, 225, 200),
	})
	local costLabel = label(card, {
		Position = UDim2.fromOffset(0, 146),
		Size = UDim2.new(1, 0, 0, 30),
		Text = "$" .. fmt(unit.Cost),
		TextSize = 26,
		TextColor3 = GOLD,
	})
	cards[name] = { Cost = costLabel, Stroke = stroke, Button = card }
	card.MouseButton1Click:Connect(function()
		if selectedUnit == name then selectUnit(nil) else selectUnit(name) end
	end)
end

-- =====================================================================
--  POPUPS: settings + game over
-- =====================================================================
local popupGui = make("ScreenGui", {
	Name = "TDPopupGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 20,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

-- stage clear / stage failed popup
local overlay = make("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Visible = false,
}, popupGui)
local resultPanel = woodPanel(overlay, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(560, 410),
})
local resultScale = make("UIScale", { Scale = 1 }, resultPanel)

local resultBanner = make("Frame", {
	Size = UDim2.new(1, 0, 0, 92),
	BackgroundColor3 = RED_BTN,
	BorderSizePixel = 0,
}, resultPanel)
make("Frame", {
	Position = UDim2.new(0, 0, 1, -6),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = WOOD_DEEP,
	BorderSizePixel = 0,
}, resultBanner)
local resultTitle = label(resultBanner, {
	Position = UDim2.fromOffset(0, 4),
	Size = UDim2.new(1, 0, 1, -10),
	TextSize = 52,
	TextColor3 = WHITE,
	Text = "",
})
local resultSub = label(resultPanel, {
	Position = UDim2.fromOffset(0, 104),
	Size = UDim2.new(1, 0, 0, 30),
	TextSize = 20,
	TextColor3 = Color3.fromRGB(240, 225, 200),
	Text = "",
})

local function resultRow(y, name)
	local row = make("Frame", {
		Position = UDim2.fromOffset(40, y),
		Size = UDim2.new(1, -80, 0, 38),
		BackgroundColor3 = WOOD_DARK,
		BorderSizePixel = 0,
	}, resultPanel)
	label(row, {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		Text = name,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	return label(row, {
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0.5, -14, 1, 0),
		Text = "",
		TextSize = 24,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end
local rowRound = resultRow(150, "ROUND REACHED")
local rowTime = resultRow(196, "TIME")
local rowLives = resultRow(242, "LIVES LEFT")

local retryButton = woodButton(resultPanel, "RETRY", UDim2.fromOffset(250, 64), UDim2.new(0.5, -135, 1, -50), 30, GREEN_BTN, GREEN_EDGE)
local menuButton = woodButton(resultPanel, "MAIN MENU", UDim2.fromOffset(250, 64), UDim2.new(0.5, 135, 1, -50), 26)

local function formatClock(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
	end
	return ("%02d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local resultShown = false
local function showResult(state)
	local show = state == "GameOver" or state == "Victory"
	overlay.Visible = show
	if not show then
		resultShown = false
		return
	end
	local won = state == "Victory"
	local reason = workspace:GetAttribute("EndReason")
	resultTitle.Text = won and "STAGE CLEAR!" or "STAGE FAILED"
	resultBanner.BackgroundColor3 = won and GREEN_BTN or RED_BTN
	if won then
		resultSub.Text = ("All %d rounds survived!"):format(Config.TotalRounds)
	elseif reason == "Surrender" then
		resultSub.Text = "You surrendered."
	else
		resultSub.Text = "The enemies broke through!"
	end
	rowRound.Text = ("%d / %d"):format(workspace:GetAttribute("Round") or 0, Config.TotalRounds)
	rowTime.Text = formatClock(workspace:GetAttribute("StageTime") or 0)
	rowLives.Text = fmt(workspace:GetAttribute("Lives") or 0)
	if not resultShown then
		resultShown = true
		resultScale.Scale = 0.75
		TweenService:Create(resultScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- settings
local settingsDim = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
}, popupGui)
local settingsPanel = woodPanel(settingsDim, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 330),
})
label(settingsPanel, {
	Position = UDim2.fromOffset(0, 14),
	Size = UDim2.new(1, 0, 0, 44),
	Text = "SETTINGS",
	TextSize = 36,
	TextColor3 = GOLD,
})

local mainView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, settingsPanel)
local resumeButton = woodButton(mainView, "RESUME", UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 0, 120), 30, GREEN_BTN, GREEN_EDGE)
local surrenderButton = woodButton(mainView, "SURRENDER", UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 0, 200), 30, RED_BTN, RED_EDGE)
label(mainView, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 252),
	Size = UDim2.new(1, -40, 0, 50),
	Text = "Surrender ends the stage and shows the stage failed screen.",
	TextSize = 16,
	TextWrapped = true,
	TextColor3 = Color3.fromRGB(240, 225, 200),
})

local confirmView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, settingsPanel)
label(confirmView, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.new(1, -50, 0, 90),
	Text = "Are you sure?\nYour progress will be lost.",
	TextSize = 26,
	TextWrapped = true,
})
local yesButton = woodButton(confirmView, "YES, SURRENDER", UDim2.fromOffset(300, 60), UDim2.new(0.5, 0, 0, 205), 24, RED_BTN, RED_EDGE)
local noButton = woodButton(confirmView, "NO, KEEP PLAYING", UDim2.fromOffset(300, 60), UDim2.new(0.5, 0, 0, 275), 24, GREEN_BTN, GREEN_EDGE)

local function closeSettings()
	settingsDim.Visible = false
	mainView.Visible = true
	confirmView.Visible = false
end
local function openSettings()
	mainView.Visible = true
	confirmView.Visible = false
	settingsDim.Visible = true
end

gearButton.MouseButton1Click:Connect(function()
	if settingsDim.Visible then closeSettings() else openSettings() end
end)
resumeButton.MouseButton1Click:Connect(closeSettings)
surrenderButton.MouseButton1Click:Connect(function()
	mainView.Visible = false
	confirmView.Visible = true
end)
noButton.MouseButton1Click:Connect(closeSettings)
yesButton.MouseButton1Click:Connect(function()
	closeSettings()
	surrenderRemote:FireServer()
end)

-- =====================================================================
--  Refresh + wiring
-- =====================================================================
local SPEED_COLORS = {
	[1] = WOOD,
	[2] = Color3.fromRGB(86, 160, 70),
	[3] = Color3.fromRGB(226, 128, 44),
}

local function refreshHud()
	livesValue.Text = fmt(workspace:GetAttribute("Lives") or 0)
	cashValue.Text = "$" .. fmt(player:GetAttribute("Money") or 0)
	local round = workspace:GetAttribute("Round") or 0
	roundLabel.Text = ("ROUND %d / %d"):format(round, Config.TotalRounds)
	local cd = workspace:GetAttribute("Countdown") or 0
	local prep = currentState() == "Playing" and workspace:GetAttribute("Phase") == "Prep"
	prepPanel.Visible = prep
	prepTitle.Text = "MATCH STARTS IN " .. (workspace:GetAttribute("PrepLeft") or 0)
	countdownPlate.Visible = not prep and (cd > 0 or round >= Config.TotalRounds) and currentState() == "Playing"
	if round == 0 then
		countdownLabel.Text = "FIRST ROUND IN " .. cd
	elseif round >= Config.TotalRounds then
		countdownLabel.Text = "FINAL ROUND!"
	else
		countdownLabel.Text = "NEXT ROUND IN " .. cd
	end
	local speed = workspace:GetAttribute("GameSpeed") or 1
	speedButton.Text = "SPEED  X" .. speed
	setButtonColor(speedButton, SPEED_COLORS[speed] or WOOD)
	local auto = workspace:GetAttribute("AutoSkip")
	autoSkipButton.Text = auto and "AUTO SKIP: ON" or "AUTO SKIP: OFF"
	setButtonColor(autoSkipButton, auto and GREEN_BTN or Color3.fromRGB(150, 80, 70))
	refreshCards()
	refreshUpgradePanel()
	if overlay.Visible then showResult(currentState()) end
end

local function refreshState()
	local state = currentState()
	menuGui.Enabled = state == "Menu"
	hudGui.Enabled = state ~= "Menu"
	showResult(state)
	if state ~= "Playing" then
		selectUnit(nil)
		deselectTower()
		closeSettings()
	end
	refreshHud()
end

workspace:GetAttributeChangedSignal("State"):Connect(refreshState)
for _, attr in ipairs({ "Lives", "Round", "Countdown", "GameSpeed", "AutoSkip", "Phase", "PrepLeft", "EndReason" }) do
	workspace:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
player:GetAttributeChangedSignal("Money"):Connect(refreshHud)

playButton.MouseButton1Click:Connect(function()
	startGameRemote:FireServer()
end)
retryButton.MouseButton1Click:Connect(function()
	retryRemote:FireServer()
end)
menuButton.MouseButton1Click:Connect(function()
	returnToMenuRemote:FireServer()
end)
speedButton.MouseButton1Click:Connect(function()
	local speed = workspace:GetAttribute("GameSpeed") or 1
	local options = Config.SpeedOptions
	local idx = table.find(options, speed) or 1
	setSpeedRemote:FireServer(options[idx % #options + 1])
end)

autoSkipButton.MouseButton1Click:Connect(function()
	setAutoSkipRemote:FireServer(not workspace:GetAttribute("AutoSkip"))
end)

startMatchButton.MouseButton1Click:Connect(function()
	beginMatchRemote:FireServer()
end)

-- ghost follows the mouse
RunService.RenderStepped:Connect(function()
	if not ghost or not selectedUnit then return end
	local pos = getMouseGroundPos()
	if not pos then return end
	local unit = Config.Units[selectedUnit]
	local canPlace = Config.CanPlace(pos, towersFolder)
	local affordable = (player:GetAttribute("Money") or 0) >= unit.Cost
	local color = (canPlace and affordable) and Color3.fromRGB(80, 230, 100) or Color3.fromRGB(240, 70, 70)
	ghost:PivotTo(CFrame.new(pos.X, Config.GroundY + ghostOffset, pos.Z))
	if ring then
		ring.CFrame = ringCFrame(pos.X, pos.Z)
		ring.Color = color
	end
	if tint then
		tint.FillColor = color
		tint.OutlineColor = color
	end
end)

-- ===== Input =====
UserInputService.InputBegan:Connect(function(input, processed)
	if currentState() ~= "Playing" then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if processed then return end
		if selectedUnit then
			if placing then return end
			local pos = getMouseGroundPos()
			if not pos then return end
			placing = true
			local ok, success, reason = pcall(function()
				return placeTowerRemote:InvokeServer(selectedUnit, pos)
			end)
			placing = false
			if ok and success then
				selectUnit(nil)
			elseif ok then
				notify(reason or "Cannot place here")
			end
		else
			local model = getTowerUnderMouse()
			if model then selectTower(model) else deselectTower() end
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		selectUnit(nil)
		deselectTower()
	elseif not processed and input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Q then
			selectUnit(nil)
			deselectTower()
		elseif input.KeyCode == Enum.KeyCode.U then
			tryUpgrade()
		elseif input.KeyCode == Enum.KeyCode.One then
			selectUnit(Config.UnitOrder[1])
		elseif input.KeyCode == Enum.KeyCode.Two then
			selectUnit(Config.UnitOrder[2])
		end
	end
end)

-- ===== Stage timer (real time spent on this stage) =====
local function formatTime(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
	end
	return ("%02d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- The stage timer runs in GAME time, so it counts faster at x2 / x3 speed.
-- The server publishes StageTime (game seconds) + StageSync (server clock) twice a second;
-- between updates we extrapolate using the current game speed.
local function stageSeconds()
	local state = currentState()
	if state == "Menu" then return 0 end
	local t = workspace:GetAttribute("StageTime") or 0
	if state == "Playing" and workspace:GetAttribute("Phase") == "Match" then
		local sync = workspace:GetAttribute("StageSync") or workspace:GetServerTimeNow()
		local speed = workspace:GetAttribute("GameSpeed") or 1
		t += math.max(0, workspace:GetServerTimeNow() - sync) * speed
	end
	return t
end

task.spawn(function()
	while true do
		local t = formatTime(stageSeconds())
		timeLabel.Text = "TIME " .. t
		task.wait(0.1)
	end
end)

refreshState()
