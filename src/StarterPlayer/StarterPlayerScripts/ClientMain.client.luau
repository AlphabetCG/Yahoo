-- ClientMain (pixel-art version): menu, HUD, shop, upgrades, settings, input.
-- The game world itself is drawn by the WorldView module.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PixelArt = require(ReplicatedStorage:WaitForChild("PixelArt"))
local WorldView = require(ReplicatedStorage:WaitForChild("WorldView"))

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
local getProfileRemote = remotes:WaitForChild("GetProfile")
local profileUpdatedRemote = remotes:WaitForChild("ProfileUpdated")
local setSettingRemote = remotes:WaitForChild("SetSetting")
local summonRemote = remotes:WaitForChild("Summon")
local stageRewardsRemote = remotes:WaitForChild("StageRewards")

-- the player's saved data (settings, gems, units, items); filled in by the server
-- profile.Units = { [uid] = { Id, Name, Level, ... } }: one entry per owned unit
local profile = nil
local function unitCount(name)
	local n = 0
	if profile then
		for _, u in pairs(profile.Units) do
			if u.Name == name then n += 1 end
		end
	end
	return n
end
local function ownsUnit(name)
	return unitCount(name) > 0
end
-- the owned copy of a unit that gets placed from the shop: highest level, then the oldest
-- (replaced by the loadout later)
local function bestUnitId(name)
	local best
	if profile then
		for _, u in pairs(profile.Units) do
			if u.Name == name and (not best or u.Level > best.Level
				or (u.Level == best.Level and (u.Obtained or 0) < (best.Obtained or 0))) then
				best = u
			end
		end
	end
	return best and best.Id
end

-- the host (longest in the server) controls the match flow
local function isHost()
	return workspace:GetAttribute("HostId") == player.UserId
end
local HOST_ONLY = "Only the host can do that"
local towersFolder = workspace:WaitForChild("Towers")

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)

-- ===== Pixel UI style =====
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local PANEL = rgb(30, 36, 56)
local PANEL_LIGHT = rgb(48, 58, 88)
local PANEL_EDGE = rgb(12, 14, 24)
local BORDER = rgb(104, 120, 168)
local GOLD = rgb(255, 208, 84)
local RED = rgb(255, 104, 104)
local GREEN = rgb(116, 232, 116)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local TEXT_DIM = rgb(190, 200, 224)
local BTN = rgb(58, 70, 106)
local GREEN_BTN, GREEN_EDGE = rgb(62, 160, 84), rgb(20, 70, 36)
local RED_BTN, RED_EDGE = rgb(194, 66, 66), rgb(90, 24, 28)
local GREY_BTN = rgb(98, 100, 116)
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

local function label(parent, props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or FONT
	props.TextColor3 = props.TextColor3 or WHITE
	props.TextStrokeTransparency = props.TextStrokeTransparency or 0
	props.TextStrokeColor3 = props.TextStrokeColor3 or PANEL_EDGE
	return make("TextLabel", props, parent)
end

-- panel: dark fill, dark outline and a light pixel border inside
local function pixelPanel(parent, props)
	props.BackgroundColor3 = props.BackgroundColor3 or PANEL
	props.BorderSizePixel = 0
	local f = make("Frame", props, parent)
	make("UIStroke", { Color = PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local inner = make("Frame", {
		Position = UDim2.fromOffset(3, 3),
		Size = UDim2.new(1, -6, 1, -6),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, f)
	make("UIStroke", { Color = BORDER, Thickness = 2, Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, inner)
	return f
end

-- buttons (hover effect, light top edge and darker bottom edge)
local buttonBase = setmetatable({}, { __mode = "k" })
local buttonShine = setmetatable({}, { __mode = "k" })
local buttonShade = setmetatable({}, { __mode = "k" })

local function setButtonColor(b, color)
	buttonBase[b] = color
	tween(b, 0.12, { BackgroundColor3 = color })
	if buttonShine[b] then buttonShine[b].BackgroundColor3 = color:Lerp(WHITE, 0.3) end
	if buttonShade[b] then buttonShade[b].BackgroundColor3 = color:Lerp(BLACK, 0.35) end
end

local function pixelButton(parent, text, size, position, textSize, base, edge, textColor)
	base = base or BTN
	edge = edge or PANEL_EDGE
	local b = make("TextButton", {
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Text = text,
		Font = FONT,
		TextSize = textSize or 26,
		TextColor3 = textColor or GOLD,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = edge,
		AutoButtonColor = false,
	}, parent)
	make("UIStroke", { Color = edge, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	buttonBase[b] = base
	buttonShine[b] = make("Frame", {
		Size = UDim2.new(1, -6, 0, 4),
		Position = UDim2.fromOffset(3, 3),
		BackgroundColor3 = base:Lerp(WHITE, 0.3),
		BorderSizePixel = 0,
	}, b)
	buttonShade[b] = make("Frame", {
		Size = UDim2.new(1, -6, 0, 4),
		Position = UDim2.new(0, 3, 1, -7),
		BackgroundColor3 = base:Lerp(BLACK, 0.35),
		BorderSizePixel = 0,
	}, b)
	b.MouseEnter:Connect(function()
		tween(b, 0.1, { BackgroundColor3 = buttonBase[b]:Lerp(WHITE, 0.18) })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.1, { BackgroundColor3 = buttonBase[b] })
	end)
	return b
end

-- =====================================================================
--  THE WORLD (2D pixel art map, units, enemies)
-- =====================================================================
local SHOP_W = 200

local worldGui = make("ScreenGui", {
	Name = "TDWorldGui",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 0,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)
WorldView.start(worldGui, { rightInset = SHOP_W, topInset = 176, bottomInset = 156 })

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		WorldView.zoom(input.Position.Z > 0 and 1 or -1)
	end
end)

-- =====================================================================
--  MAIN MENU (pixel forest scene like the reference)
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
	BackgroundColor3 = rgb(190, 222, 230),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, menuGui)
make("UIGradient", {
	Color = ColorSequence.new(rgb(168, 206, 226), rgb(224, 240, 238)),
	Rotation = 90,
}, menu)

local MENU_PX = 6
local sceneHolder = make("Frame", { Name = "Scene", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, menu)
local sceneAnim = {}

local function buildScene()
	sceneHolder:ClearAllChildren()
	table.clear(sceneAnim)
	local size = menu.AbsoluteSize
	if size.X < 10 then return end
	local scaler = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, sceneHolder)
	make("UIScale", { Scale = MENU_PX }, scaler)
	local aw, ah = math.ceil(size.X / MENU_PX), math.ceil(size.Y / MENU_PX)
	local groundY = math.floor(ah * 0.78)
	local rng = Random.new(11)
	local R = PixelArt.rect

	-- blocky clouds
	local function cloudAt(x, y, w)
		R(scaler, x, y + 2, w, 3, WHITE)
		R(scaler, x + 3, y, w - 8, 3, WHITE)
		R(scaler, x + w - 7, y + 1, 4, 2, WHITE)
	end
	cloudAt(math.floor(aw * 0.08), 6, 24)
	cloudAt(math.floor(aw * 0.62), 3, 30)
	cloudAt(math.floor(aw * 0.36), 14, 18)

	-- two rows of pale pine trees, like the distant forest in the reference
	local function pineRow(tone, spacing, baseY, jitter)
		local x = -8
		while x < aw + 8 do
			local pine = PixelArt.pine(tone)
			pine.Position = UDim2.fromOffset(x + rng:NextInteger(-2, 2), baseY - 24 + rng:NextInteger(-jitter, jitter))
			pine.Parent = scaler
			x += spacing
		end
	end
	local far = { mid = rgb(156, 192, 172), light = rgb(164, 200, 180), dark = rgb(146, 182, 164), trunk = rgb(146, 182, 164) }
	local mid = { mid = rgb(122, 166, 138), light = rgb(132, 176, 146), dark = rgb(110, 154, 128), trunk = rgb(110, 154, 128) }
	pineRow(far, 9, groundY - 2, 2)
	pineRow(mid, 11, groundY + 1, 2)

	-- grass with little tufts and flowers
	local grass, grassDark, grassLight = rgb(104, 178, 74), rgb(88, 158, 64), rgb(136, 204, 98)
	R(scaler, 0, groundY + 2, aw, ah - groundY, grass)
	R(scaler, 0, groundY + 2, aw, 2, grassLight)
	for _ = 1, math.floor(aw * (ah - groundY) / 60) do
		local x = rng:NextInteger(0, aw)
		local y = rng:NextInteger(groundY + 5, ah)
		local kind = rng:NextNumber()
		if kind < 0.45 then
			R(scaler, x, y, 4, 2, grassDark)
		elseif kind < 0.85 then
			R(scaler, x, y, 2, 1, grassLight)
			R(scaler, x, y - 1, 1, 1, grassLight)
		else
			R(scaler, x, y, 1, 1, (rng:NextNumber() < 0.5) and WHITE or rgb(255, 232, 110))
		end
	end

	-- the hero on the left, a wisp on the right
	local feetY = groundY + 16
	local function actor(name, cx, bob, opts)
		local w, h = PixelArt.size(name)
		R(scaler, cx - w // 2 + 1, feetY - 1, w - 2, 2, BLACK, 0.6)
		local sprite = PixelArt.sprite(name, opts)
		sprite.Parent = scaler
		table.insert(sceneAnim, { frame = sprite, x = cx - w // 2, y = feetY - h, bob = bob, phase = rng:NextNumber() * 6 })
	end
	actor("Herobrine", math.floor(aw * 0.30), false)
	actor("Wisp", math.floor(aw * 0.66), true, { tier = 3, color = Config.Tiers[3].Color })
end
menu:GetPropertyChangedSignal("AbsoluteSize"):Connect(buildScene)
buildScene()

RunService.RenderStepped:Connect(function()
	if not menuGui.Enabled then return end
	local t = os.clock()
	for _, a in ipairs(sceneAnim) do
		local off
		if a.bob then
			off = -math.floor(math.abs(math.sin(t * 4 + a.phase)) * 2.5)
		else
			off = (math.sin(t * 2 + a.phase) > 0.4) and -1 or 0
		end
		a.frame.Position = UDim2.fromOffset(a.x, a.y + off)
	end
end)

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
	TextColor3 = PANEL_EDGE,
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

local playButton = pixelButton(menu, "PLAY", UDim2.fromOffset(340, 84), UDim2.fromScale(0.5, 0.46), 44, GREEN_BTN, GREEN_EDGE, WHITE)

local inventoryButton = pixelButton(menu, "INVENTORY", UDim2.fromOffset(340, 64), UDim2.new(0.5, 0, 0.46, 150), 30)

label(menu, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.46, 82),
	Size = UDim2.fromOffset(700, 30),
	Text = "Stop the enemies before they reach the end of the path!",
	TextSize = 20,
})


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

-- lives: heart + health bar (like the player bar in the reference)
local livesPlate = pixelPanel(hudGui, { Size = UDim2.fromOffset(236, 44), Position = UDim2.fromOffset(16, 12) })
make("TextLabel", {
	Size = UDim2.fromOffset(40, 44),
	BackgroundTransparency = 1,
	Text = "\u{2764}",
	Font = Enum.Font.SourceSansBold,
	TextSize = 26,
	TextColor3 = rgb(240, 70, 80),
}, livesPlate)
local livesBar = make("Frame", {
	Position = UDim2.fromOffset(44, 11),
	Size = UDim2.new(1, -54, 0, 22),
	BackgroundColor3 = rgb(18, 22, 34),
	BorderSizePixel = 0,
}, livesPlate)
make("UIStroke", { Color = PANEL_EDGE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, livesBar)
local livesFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(84, 204, 84), BorderSizePixel = 0 }, livesBar)
make("Frame", { Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = WHITE, BackgroundTransparency = 0.75, BorderSizePixel = 0 }, livesFill)
local livesText = label(livesBar, { Size = UDim2.fromScale(1, 1), TextSize = 16, ZIndex = 3, Text = "" })

-- cash
local cashPlate = pixelPanel(hudGui, { Size = UDim2.fromOffset(236, 44), Position = UDim2.fromOffset(16, 64) })
make("TextLabel", {
	Size = UDim2.fromOffset(40, 44),
	BackgroundTransparency = 1,
	Text = "\u{1F4B0}",
	Font = Enum.Font.SourceSansBold,
	TextSize = 24,
	TextColor3 = WHITE,
}, cashPlate)
local cashValue = label(cashPlate, {
	Position = UDim2.fromOffset(46, 0),
	Size = UDim2.new(1, -54, 1, 0),
	TextSize = 26,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})

-- round / time (centered over the map area)
local roundPlate = pixelPanel(hudGui, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2 + 26, 0, 12),
	Size = UDim2.fromOffset(230, 44),
})
local roundLabel = label(roundPlate, { Size = UDim2.fromScale(1, 1), TextSize = 26, Text = "" })
local timePlate = pixelPanel(hudGui, {
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2 + 34, 0, 12),
	Size = UDim2.fromOffset(170, 44),
})
local timeLabel = label(timePlate, { Size = UDim2.fromScale(1, 1), TextSize = 24, TextColor3 = GOLD, Text = "TIME 00:00" })

local countdownPlate = pixelPanel(hudGui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2, 0, 64),
	Size = UDim2.fromOffset(300, 34),
	Visible = false,
})
local countdownLabel = label(countdownPlate, { Size = UDim2.fromScale(1, 1), TextSize = 20, TextColor3 = GOLD, Text = "" })

-- prep phase: countdown + START MATCH button
local prepPanel = pixelPanel(hudGui, {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, -SHOP_W / 2, 1, -16),
	Size = UDim2.fromOffset(380, 120),
	Visible = false,
})
local prepTitle = label(prepPanel, {
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 34),
	TextSize = 26,
	TextColor3 = GOLD,
	Text = "",
})
local startMatchButton = pixelButton(prepPanel, "START MATCH", UDim2.fromOffset(300, 56), UDim2.new(0.5, 0, 0, 80), 28, GREEN_BTN, GREEN_EDGE, WHITE)

-- settings (gear) button
local gearButton = pixelButton(hudGui, "\u{2699}", UDim2.fromOffset(48, 48), UDim2.new(1, -(SHOP_W + 36), 0, 36), 28)
gearButton.Font = Enum.Font.SourceSansBold

-- bottom messages
local notice = label(hudGui, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2, 0, 120),
	Size = UDim2.fromOffset(520, 24),
	TextSize = 22,
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
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, -SHOP_W / 2, 0, 98),
	Size = UDim2.fromOffset(600, 22),
	TextSize = 16,
	Text = "Click to place   -   Right-click or Q to cancel",
	Visible = false,
})

-- ===== Shop panel =====
local shop = make("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, SHOP_W, 1, 0),
	BackgroundColor3 = PANEL,
	BorderSizePixel = 0,
}, hudGui)
make("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = PANEL_EDGE, BorderSizePixel = 0 }, shop)
make("Frame", { Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = BORDER, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, shop)
local shopTitle = label(shop, {
	Size = UDim2.new(1, 0, 0, 44),
	Text = "UNITS",
	TextSize = 30,
	TextColor3 = GOLD,
})
local list = make("ScrollingFrame", {
	Position = UDim2.fromOffset(10, 46),
	Size = UDim2.new(1, -18, 1, -46 - 86),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, shop)
make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, list)

local speedButton = pixelButton(shop, "SPEED  X1", UDim2.fromOffset(176, 56), UDim2.new(0.5, 2, 1, -44), 24)

-- =====================================================================
--  Placement / selection state
-- =====================================================================
local selectedUnit = nil            -- unit chosen in the shop (placing mode)
local cards = {}
local placing = false
local selectedTower = nil           -- placed unit chosen for upgrading
local towerConns = {}

-- ===== Refine panel (bottom-left): in-match upgrades, targeting, sell =====
local ABILITY_COLORS = { Burn = rgb(255, 150, 60), Slow = rgb(110, 210, 255) }

local upPanel = pixelPanel(hudGui, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(300, 396),
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
local upClose = pixelButton(upPanel, "X", UDim2.fromOffset(34, 34), UDim2.new(1, -26, 0, 26), 20, RED_BTN, RED_EDGE, WHITE)
make("Frame", { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 3), BackgroundColor3 = BORDER, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, upPanel)

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
	Size = UDim2.new(1, -28, 0, 22),
	TextSize = 18,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
-- the ability the unit has now, or the one the next refine adds
local abilityLabel = label(upPanel, {
	Position = UDim2.fromOffset(14, 172),
	Size = UDim2.new(1, -28, 0, 20),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
local upButton = pixelButton(upPanel, "REFINE", UDim2.new(1, -104, 0, 54), UDim2.new(0, 112, 0, 226), 22, GREEN_BTN, GREEN_EDGE, WHITE)
local upMaxButton = pixelButton(upPanel, "MAX", UDim2.fromOffset(76, 54), UDim2.new(1, -52, 0, 226), 22, GREEN_BTN, GREEN_EDGE, WHITE)

-- targeting selector:  <  TARGET: FIRST  >
local targetPrev = pixelButton(upPanel, "<", UDim2.fromOffset(40, 40), UDim2.new(0, 34, 0, 298), 24)
local targetNext = pixelButton(upPanel, ">", UDim2.fromOffset(40, 40), UDim2.new(1, -34, 0, 298), 24)
local targetLabel = label(upPanel, {
	Position = UDim2.fromOffset(60, 278),
	Size = UDim2.new(1, -120, 0, 40),
	BackgroundTransparency = 0,
	BackgroundColor3 = PANEL_EDGE,
	BorderSizePixel = 0,
	TextSize = 16,
	Text = "",
})

-- sell button
local sellButton = pixelButton(upPanel, "SELL", UDim2.new(1, -28, 0, 50), UDim2.new(0.5, 0, 0, 356), 22, RED_BTN, RED_EDGE, WHITE)

local function statText(name, cur, nxt, fn)
	if nxt ~= nil and nxt ~= cur then
		return ("%s  %s  <font color='#7CFF7C'>&gt;  %s</font>"):format(name, fn(cur), fn(nxt))
	end
	return ("%s  %s"):format(name, fn(cur))
end
local function fmtNum(v) return tostring(v) end

local function sameAbility(a, b)
	if a == nil or b == nil then return a == b end
	return a.Kind == b.Kind and a.Dps == b.Dps and a.Pct == b.Pct and a.Duration == b.Duration
end

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
	rowSpeed.Text = statText("SPA   ", cur.Cooldown, nxt and nxt.Cooldown, function(v)
		local txt = ("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")
		return txt .. "s"
	end)

	-- ability: "NEW: ..." when the next refine adds or changes one, otherwise the current one
	if nxt and nxt.Ability and not sameAbility(cur.Ability, nxt.Ability) then
		abilityLabel.Text = "NEXT: " .. Config.DescribeAbility(nxt.Ability)
		abilityLabel.TextColor3 = GREEN
	elseif cur.Ability then
		abilityLabel.Text = Config.DescribeAbility(cur.Ability)
		abilityLabel.TextColor3 = ABILITY_COLORS[cur.Ability.Kind] or WHITE
	else
		abilityLabel.Text = ""
	end

	local mine = selectedTower:GetAttribute("OwnerId") == player.UserId

	-- targeting + sell info
	local mode = selectedTower:GetAttribute("Targeting") or "First"
	targetLabel.Text = "TARGET: " .. string.upper(mode)
	targetLabel.TextColor3 = (mode == "None") and RED or WHITE
	local spent = selectedTower:GetAttribute("Spent") or 0
	sellButton.Text = mine and ("SELL  $" .. fmt(math.floor(spent * Config.SellRefund))) or "SELL  (NOT YOURS)"
	setButtonColor(sellButton, mine and RED_BTN or GREY_BTN)

	if not nxt then
		upName.Text = "FULLY REFINED!"
		upButton.Text = "MAX LEVEL"
		setButtonColor(upButton, GREY_BTN)
		setButtonColor(upMaxButton, GREY_BTN)
	elseif not mine then
		upName.Text = "Belongs to another player"
		upButton.Text = "LOCKED"
		setButtonColor(upButton, GREY_BTN)
		setButtonColor(upMaxButton, GREY_BTN)
	else
		upName.Text = "NEXT: " .. string.upper(nxt.Name)
		upButton.Text = "REFINE  $" .. fmt(nxt.Cost)
		local affordable = (player:GetAttribute("Money") or 0) >= nxt.Cost
		setButtonColor(upButton, affordable and GREEN_BTN or rgb(150, 80, 70))
		setButtonColor(upMaxButton, affordable and GREEN_BTN or rgb(150, 80, 70))
	end
end

local function deselectTower()
	for _, c in ipairs(towerConns) do c:Disconnect() end
	table.clear(towerConns)
	selectedTower = nil
	WorldView.setSelected(nil)
	upPanel.Visible = false
end

local function selectTower(model)
	if selectedTower == model then return end
	deselectTower()
	selectedTower = model
	WorldView.setSelected(model)
	for _, attr in ipairs({ "Level", "Targeting", "Spent" }) do
		table.insert(towerConns, model:GetAttributeChangedSignal(attr):Connect(refreshUpgradePanel))
	end
	table.insert(towerConns, model.AncestryChanged:Connect(function(_, parent)
		if not parent and selectedTower == model then deselectTower() end
	end))
	refreshUpgradePanel()
end

-- all = true: REFINE MAX (buy as many levels as you can afford)
local upgrading = false
local function tryUpgrade(all)
	if not selectedTower or upgrading then return end
	upgrading = true
	local ok, success, reason = pcall(function()
		return upgradeTowerRemote:InvokeServer(selectedTower, all == true)
	end)
	upgrading = false
	if ok and not success then notify(reason or "Cannot refine") end
end
upButton.MouseButton1Click:Connect(function() tryUpgrade(false) end)
upMaxButton.MouseButton1Click:Connect(function() tryUpgrade(true) end)
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

-- ===== Shop cards (with a pixel-art portrait) =====
-- how many units I have on the map: total, { [unitName] = n }
local function myPlaced()
	local total, byUnit = 0, {}
	for _, m in ipairs(towersFolder:GetChildren()) do
		if m:GetAttribute("OwnerId") == player.UserId then
			total += 1
			local n = m:GetAttribute("UnitName")
			if n then byUnit[n] = (byUnit[n] or 0) + 1 end
		end
	end
	return total, byUnit
end

local function refreshCards()
	local money = player:GetAttribute("Money") or 0
	local placed, byUnit = myPlaced()
	local full = placed >= Config.MaxPlacedPerPlayer
	shopTitle.Text = ("UNITS %d/%d"):format(placed, Config.MaxPlacedPerPlayer)
	shopTitle.TextColor3 = full and RED or GOLD
	for name, card in pairs(cards) do
		local unit = Config.Units[name]
		local limited = unit.PlaceLimit ~= nil and (byUnit[name] or 0) >= unit.PlaceLimit
		local usable = money >= unit.Cost and not full and not limited
		card.Button.Visible = ownsUnit(name)
		card.Cost.Text = "$" .. fmt(unit.Cost)
			.. (unit.PlaceLimit and ("  %d/%d"):format(byUnit[name] or 0, unit.PlaceLimit) or "")
		card.Cost.TextColor3 = usable and GOLD or RED
		card.Button.BackgroundColor3 = usable and PANEL_LIGHT or rgb(36, 42, 62)
		card.Stroke.Color = (selectedUnit == name) and GOLD or PANEL_EDGE
		card.Stroke.Thickness = (selectedUnit == name) and 4 or 3
	end
end
towersFolder.ChildAdded:Connect(function() refreshCards() end)
towersFolder.ChildRemoved:Connect(function() refreshCards() end)

local function updateHint()
	local prep = currentState() == "Playing" and workspace:GetAttribute("Phase") == "Prep"
	if selectedUnit then
		hint.Text = "Click to place   -   Right-click or Q to cancel"
		hint.Visible = true
	elseif prep then
		hint.Text = "Place your units before the match begins!"
		hint.Visible = true
	else
		hint.Visible = false
	end
end

local function selectUnit(name)
	selectedUnit = nil
	WorldView.clearGhost()
	if name and currentState() == "Playing" and Config.Units[name] and ownsUnit(name) then
		deselectTower()
		selectedUnit = name
		WorldView.setGhost(name)
	end
	updateHint()
	refreshCards()
end

local function makePortrait(parent, name)
	local box = make("Frame", {
		Size = UDim2.new(1, -10, 0, 84),
		Position = UDim2.fromOffset(5, 6),
		BackgroundColor3 = rgb(116, 184, 94),
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, parent)
	make("UIStroke", { Color = PANEL_EDGE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
	make("Frame", { Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = rgb(98, 168, 76), BorderSizePixel = 0 }, box)
	local w, h = PixelArt.size(name)
	local scale = math.min(4, math.floor(80 / h)) -- taller sprites shrink to fit the 84 px box
	local holder = make("Frame", {
		Position = UDim2.new(0.5, -(w * scale) / 2, 0.5, -(h * scale) / 2 - 2),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
	}, box)
	local scaler = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, holder)
	make("UIScale", { Scale = scale }, scaler)
	local sprite = PixelArt.sprite(name)
	sprite.Parent = scaler
end

for i, name in ipairs(Config.UnitOrder) do
	local unit = Config.Units[name]
	local base = unit.Levels[1]
	local card = make("TextButton", {
		Name = name,
		LayoutOrder = i,
		Size = UDim2.new(1, 0, 0, 190),
		BackgroundColor3 = PANEL_LIGHT,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, list)
	local stroke = make("UIStroke", { Color = PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	makePortrait(card, name)
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
		TextColor3 = Config.RarityOf(name).Color,
	})
	label(card, {
		Position = UDim2.fromOffset(0, 120),
		Size = UDim2.new(1, 0, 0, 20),
		Text = ("DMG %d   RNG %d"):format(base.Damage, base.Range),
		TextSize = 15,
		TextColor3 = TEXT_DIM,
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
--  POPUPS: settings + stage clear / failed
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
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Visible = false,
}, popupGui)
local resultPanel = pixelPanel(overlay, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(560, 480),
})
local resultScale = make("UIScale", { Scale = 1 }, resultPanel)

local resultBanner = make("Frame", {
	Position = UDim2.fromOffset(3, 3),
	Size = UDim2.new(1, -6, 0, 90),
	BackgroundColor3 = RED_BTN,
	BorderSizePixel = 0,
}, resultPanel)
make("Frame", {
	Position = UDim2.new(0, 0, 1, -6),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundColor3 = PANEL_EDGE,
	BackgroundTransparency = 0.5,
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
	TextColor3 = TEXT_DIM,
	Text = "",
})

local function resultRow(y, name)
	local row = make("Frame", {
		Position = UDim2.fromOffset(40, y),
		Size = UDim2.new(1, -80, 0, 38),
		BackgroundColor3 = PANEL_EDGE,
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
local rewardsLabel = label(resultPanel, {
	Position = UDim2.fromOffset(40, 290),
	Size = UDim2.new(1, -80, 0, 76),
	TextSize = 20,
	TextColor3 = GOLD,
	TextWrapped = true,
	Text = "",
})
local lastRewards = nil
local function rewardsText(r)
	if not r then return "" end
	local parts = {}
	if r.Gems and r.Gems > 0 then table.insert(parts, "+" .. fmt(r.Gems) .. " Gems") end
	for _, key in ipairs(Config.MaterialOrder) do
		local n = r.Materials and r.Materials[key]
		if n and n > 0 then table.insert(parts, "+" .. fmt(n) .. " " .. Config.Materials[key].Name) end
	end
	if #parts == 0 then return "NO REWARDS" end
	return "REWARDS\n" .. table.concat(parts, "   ")
end

local retryButton = pixelButton(resultPanel, "RETRY", UDim2.fromOffset(250, 64), UDim2.new(0.5, -135, 1, -50), 30, GREEN_BTN, GREEN_EDGE, WHITE)
local menuButton = pixelButton(resultPanel, "MAIN MENU", UDim2.fromOffset(250, 64), UDim2.new(0.5, 135, 1, -50), 26)

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
	rewardsLabel.Text = rewardsText(lastRewards)
	if not resultShown then
		resultShown = true
		resultScale.Scale = 0.75
		TweenService:Create(resultScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- settings
local settingsDim = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
}, popupGui)
local settingsPanel = pixelPanel(settingsDim, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 460),
})
label(settingsPanel, {
	Position = UDim2.fromOffset(0, 14),
	Size = UDim2.new(1, 0, 0, 44),
	Text = "SETTINGS",
	TextSize = 36,
	TextColor3 = GOLD,
})

local mainView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, settingsPanel)
local autoSkipButton = pixelButton(mainView, "AUTO SKIP: ON", UDim2.fromOffset(330, 54), UDim2.new(0.5, 0, 0, 94), 22)
local healthBarsButton = pixelButton(mainView, "HEALTH BARS: HOVER", UDim2.fromOffset(330, 54), UDim2.new(0.5, 0, 0, 158), 22)
local resumeButton = pixelButton(mainView, "RESUME", UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 0, 244), 30, GREEN_BTN, GREEN_EDGE, WHITE)
local surrenderButton = pixelButton(mainView, "SURRENDER", UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 0, 324), 30, RED_BTN, RED_EDGE, WHITE)
label(mainView, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 376),
	Size = UDim2.new(1, -40, 0, 50),
	Text = "Surrender ends the stage and shows the stage failed screen.",
	TextSize = 16,
	TextWrapped = true,
	TextColor3 = TEXT_DIM,
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
local yesButton = pixelButton(confirmView, "YES, SURRENDER", UDim2.fromOffset(300, 60), UDim2.new(0.5, 0, 0, 205), 24, RED_BTN, RED_EDGE, WHITE)
local noButton = pixelButton(confirmView, "NO, KEEP PLAYING", UDim2.fromOffset(300, 60), UDim2.new(0.5, 0, 0, 275), 24, GREEN_BTN, GREEN_EDGE, WHITE)

local alwaysHealthBars = false
local function refreshHealthBarsButton()
	healthBarsButton.Text = alwaysHealthBars and "HEALTH BARS: ALWAYS" or "HEALTH BARS: HOVER"
	setButtonColor(healthBarsButton, alwaysHealthBars and GREEN_BTN or BTN)
end
refreshHealthBarsButton()
healthBarsButton.MouseButton1Click:Connect(function()
	alwaysHealthBars = not alwaysHealthBars
	WorldView.setAlwaysHealthBars(alwaysHealthBars)
	refreshHealthBarsButton()
	setSettingRemote:FireServer("AlwaysHealthBars", alwaysHealthBars) -- remembered between sessions
end)

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
	if not isHost() then return end
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
	[1] = BTN,
	[2] = rgb(62, 160, 84),
	[3] = rgb(226, 128, 44),
}

local function refreshHud()
	local lives = workspace:GetAttribute("Lives") or 0
	local frac = math.clamp(lives / Config.StartLives, 0, 1)
	livesFill.Size = UDim2.fromScale(frac, 1)
	livesFill.BackgroundColor3 = (frac > 0.5) and rgb(84, 204, 84) or ((frac > 0.25) and rgb(230, 190, 60) or rgb(224, 70, 70))
	livesText.Text = fmt(lives) .. " / " .. fmt(Config.StartLives)
	cashValue.Text = "$" .. fmt(player:GetAttribute("Money") or 0)
	local round = workspace:GetAttribute("Round") or 0
	roundLabel.Text = ("ROUND %d / %d"):format(round, Config.TotalRounds)
	local cd = workspace:GetAttribute("Countdown") or 0
	local prep = currentState() == "Playing" and workspace:GetAttribute("Phase") == "Prep"
	prepPanel.Visible = prep
	prepTitle.Text = "MATCH STARTS IN " .. (workspace:GetAttribute("PrepLeft") or 0)
	-- Auto Skip OFF: no timer while the wave spawns (shows "WAVE r  x/y"), then "NEXT ROUND IN n"
	local spawning = workspace:GetAttribute("WaveState") == "Spawning" and cd == 0
	countdownPlate.Visible = not prep and (cd > 0 or spawning or round >= Config.TotalRounds) and currentState() == "Playing"
	if round == 0 then
		countdownLabel.Text = "FIRST ROUND IN " .. cd
	elseif round >= Config.TotalRounds then
		countdownLabel.Text = "FINAL ROUND!"
	elseif spawning then
		countdownLabel.Text = ("WAVE %d   %d/%d"):format(round, workspace:GetAttribute("WaveSpawned") or 0, workspace:GetAttribute("WaveCount") or 0)
	else
		countdownLabel.Text = "NEXT ROUND IN " .. cd
	end
	local speed = workspace:GetAttribute("GameSpeed") or 1
	speedButton.Text = "SPEED  X" .. speed
	setButtonColor(speedButton, SPEED_COLORS[speed] or BTN)
	local auto = workspace:GetAttribute("AutoSkip")
	autoSkipButton.Text = auto and "AUTO SKIP: ON" or "AUTO SKIP: OFF"
	setButtonColor(autoSkipButton, auto and GREEN_BTN or rgb(150, 80, 70))
	refreshCards()
	refreshUpgradePanel()
	updateHint()
	if overlay.Visible then showResult(currentState()) end
end

-- =====================================================================
--  INVENTORY (units + materials) and SUMMON. Data comes from the server's saved profile.
-- =====================================================================
local inventoryDim = make("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	Text = "",
	AutoButtonColor = false,
	Visible = false,
}, popupGui)
local inventoryPanel = pixelPanel(inventoryDim, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(660, 520),
})
label(inventoryPanel, {
	Position = UDim2.fromOffset(0, 12),
	Size = UDim2.new(1, 0, 0, 44),
	Text = "INVENTORY",
	TextSize = 36,
	TextColor3 = GOLD,
})
local gemsLabel = label(inventoryPanel, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -20, 0, 20),
	Size = UDim2.fromOffset(200, 30),
	Text = "GEMS: 0",
	TextSize = 22,
	TextColor3 = rgb(120, 220, 255),
	TextXAlignment = Enum.TextXAlignment.Right,
})
local unitsTab = pixelButton(inventoryPanel, "UNITS", UDim2.fromOffset(200, 44), UDim2.new(0.5, -110, 0, 84), 24)
local materialsTab = pixelButton(inventoryPanel, "MATERIALS", UDim2.fromOffset(200, 44), UDim2.new(0.5, 110, 0, 84), 24)

local function newScroll()
	return make("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 116),
		Size = UDim2.new(1, -40, 0, 290),
		BackgroundColor3 = rgb(20, 24, 40),
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
		Visible = false,
	}, inventoryPanel)
end
local unitsScroll = newScroll()
make("UIGridLayout", { CellSize = UDim2.fromOffset(150, 196), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, unitsScroll)
make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, unitsScroll)
local materialsScroll = newScroll()
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, materialsScroll)
make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 10) }, materialsScroll)

local summonResult = label(inventoryPanel, {
	Position = UDim2.fromOffset(20, 410),
	Size = UDim2.new(1, -40, 0, 24),
	Text = "",
	TextSize = 18,
	TextColor3 = TEXT_DIM,
})
local summonButton = pixelButton(inventoryPanel, "SUMMON - " .. Config.Summon.Cost .. " GEMS", UDim2.fromOffset(300, 56), UDim2.new(0.5, -110, 0, 466), 22, GREEN_BTN, GREEN_EDGE, WHITE)
local inventoryClose = pixelButton(inventoryPanel, "CLOSE", UDim2.fromOffset(180, 56), UDim2.new(0.5, 190, 0, 466), 24, RED_BTN, RED_EDGE, WHITE)

local inventoryTab = "Units"
local function clearGui(container)
	for _, child in ipairs(container:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function spaText(v)
	return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")) .. "s"
end

local function refreshInventory()
	unitsScroll.Visible = inventoryTab == "Units"
	materialsScroll.Visible = inventoryTab == "Materials"
	setButtonColor(unitsTab, inventoryTab == "Units" and GREEN_BTN or BTN)
	setButtonColor(materialsTab, inventoryTab == "Materials" and GREEN_BTN or BTN)
	gemsLabel.Text = "GEMS: " .. fmt(profile and profile.Gems or 0)
	local canSummon = profile ~= nil and profile.Gems >= Config.Summon.Cost
	setButtonColor(summonButton, canSummon and GREEN_BTN or GREY_BTN)

	-- one card per owned unit (duplicates are separate units, never stacked),
	-- sorted rarest first, then highest level, then newest; unowned units follow as LOCKED cards
	clearGui(unitsScroll)
	local owned = {}
	if profile then
		for _, u in pairs(profile.Units) do
			if Config.Units[u.Name] then table.insert(owned, u) end
		end
	end
	table.sort(owned, function(a, b)
		local ra, rb = Config.RarityOf(a.Name).Order, Config.RarityOf(b.Name).Order
		if ra ~= rb then return ra > rb end
		if a.Level ~= b.Level then return a.Level > b.Level end
		if (a.Obtained or 0) ~= (b.Obtained or 0) then return (a.Obtained or 0) > (b.Obtained or 0) end
		return a.Id < b.Id
	end)

	local function unitCard(order, name, instance)
		local base = Config.Units[name].Levels[1]
		local rarity = Config.RarityOf(name)
		local card = make("Frame", { LayoutOrder = order, BackgroundColor3 = instance and PANEL_LIGHT or rgb(36, 42, 62), BorderSizePixel = 0 }, unitsScroll)
		make("UIStroke", { Color = instance and rarity.Color or PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		makePortrait(card, name)
		label(card, { Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 24), Text = string.upper(name), TextSize = 20, TextColor3 = rarity.Color })
		label(card, {
			Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 0, 24),
			Text = instance and ("LV " .. instance.Level .. "  " .. string.upper(Config.Units[name].Rarity or "")) or "LOCKED",
			TextSize = 18, TextColor3 = instance and GOLD or RED,
		})
		label(card, { Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 20), Text = ("DMG %d   RNG %d"):format(base.Damage, base.Range), TextSize = 14, TextColor3 = TEXT_DIM })
		label(card, { Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, 0, 0, 20), Text = "SPA " .. spaText(base.Cooldown), TextSize = 14, TextColor3 = TEXT_DIM })
	end

	for i, u in ipairs(owned) do
		unitCard(i, u.Name, u)
	end
	for i, name in ipairs(Config.UnitOrder) do
		if unitCount(name) == 0 then unitCard(#owned + i, name, nil) end
	end
	unitsTab.Text = ("UNITS %d/%d"):format(#owned, Config.MaxUnitsOwned)

	clearGui(materialsScroll)
	for i, key in ipairs(Config.MaterialOrder) do
		local mat = Config.Materials[key]
		local count = profile and profile.Items[key] or 0
		local row = make("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = PANEL_LIGHT, BorderSizePixel = 0 }, materialsScroll)
		make("UIStroke", { Color = PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, row)
		local icon = make("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = mat.Color, BorderSizePixel = 0 }, row)
		make("UIStroke", { Color = PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, icon)
		make("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(12, 6), BackgroundColor3 = mat.Color:Lerp(WHITE, 0.5), BorderSizePixel = 0 }, icon)
		label(row, { Position = UDim2.fromOffset(66, 6), Size = UDim2.new(1, -200, 0, 28), Text = string.upper(mat.Name), TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left })
		label(row, { Position = UDim2.fromOffset(66, 34), Size = UDim2.new(1, -200, 0, 22), Text = mat.Desc, TextSize = 14, TextColor3 = TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Left })
		label(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(120, 36), Text = "x" .. fmt(count), TextSize = 28, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Right })
	end
end

local function openInventory()
	summonResult.Text = ""
	inventoryDim.Visible = true
	refreshInventory()
end
local function closeInventory()
	inventoryDim.Visible = false
end
inventoryButton.MouseButton1Click:Connect(openInventory)
inventoryClose.MouseButton1Click:Connect(closeInventory)
inventoryDim.MouseButton1Click:Connect(closeInventory)
unitsTab.MouseButton1Click:Connect(function() inventoryTab = "Units"; refreshInventory() end)
materialsTab.MouseButton1Click:Connect(function() inventoryTab = "Materials"; refreshInventory() end)

local summoning = false
summonButton.MouseButton1Click:Connect(function()
	if summoning then return end
	summoning = true
	local ok, result = summonRemote:InvokeServer()
	summoning = false
	if ok and typeof(result) == "table" then
		summonResult.TextColor3 = Config.RarityOf(result.Unit).Color
		summonResult.Text = ("Summoned %s %s!  %s"):format(string.upper(result.Rarity or ""), string.upper(result.Unit), result.New and "NEW UNIT" or "ADDED AS A NEW CARD")
	else
		summonResult.TextColor3 = RED
		summonResult.Text = tostring(result or "Summon failed")
	end
end)

-- saved data from the server
local function applyProfile(p)
	profile = p
	if alwaysHealthBars ~= p.Settings.AlwaysHealthBars then
		alwaysHealthBars = p.Settings.AlwaysHealthBars
		WorldView.setAlwaysHealthBars(alwaysHealthBars)
		refreshHealthBarsButton()
	end
	refreshCards()
	if inventoryDim.Visible then refreshInventory() end
end
profileUpdatedRemote.OnClientEvent:Connect(applyProfile)
task.spawn(function()
	local p = getProfileRemote:InvokeServer()
	if p then applyProfile(p) end
end)

stageRewardsRemote.OnClientEvent:Connect(function(rewards)
	lastRewards = rewards
	if overlay.Visible then rewardsLabel.Text = rewardsText(rewards) end
end)

local function refreshState()
	local state = currentState()
	menuGui.Enabled = state == "Menu"
	hudGui.Enabled = state ~= "Menu"
	if state ~= "Menu" then closeInventory() end
	if state == "Playing" then lastRewards = nil end
	showResult(state)
	if state ~= "Playing" then
		selectUnit(nil)
		deselectTower()
		closeSettings()
	end
	refreshHud()
end

workspace:GetAttributeChangedSignal("State"):Connect(refreshState)
for _, attr in ipairs({ "Lives", "Round", "Countdown", "GameSpeed", "AutoSkip", "Phase", "PrepLeft", "EndReason", "WaveState", "WaveSpawned", "WaveCount" }) do
	workspace:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
player:GetAttributeChangedSignal("Money"):Connect(refreshHud)

-- match-flow buttons: only the host's clicks reach the server; everyone else waits for the host
local function refreshHostButtons()
	local host = isHost()
	playButton.Text = host and "PLAY" or "WAITING FOR HOST"
	playButton.TextSize = host and 44 or 26
	setButtonColor(playButton, host and GREEN_BTN or GREY_BTN)
	retryButton.Text = host and "RETRY" or "WAITING..."
	setButtonColor(retryButton, host and GREEN_BTN or GREY_BTN)
	menuButton.Text = host and "MAIN MENU" or "HOST DECIDES"
	startMatchButton.Text = host and "START MATCH" or "HOST STARTS"
	setButtonColor(startMatchButton, host and GREEN_BTN or GREY_BTN)
	surrenderButton.Text = host and "SURRENDER" or "HOST ONLY"
	setButtonColor(surrenderButton, host and RED_BTN or GREY_BTN)
end
workspace:GetAttributeChangedSignal("HostId"):Connect(function()
	refreshHostButtons()
	refreshHud()
end)
refreshHostButtons()

playButton.MouseButton1Click:Connect(function()
	if isHost() then startGameRemote:FireServer() end
end)
retryButton.MouseButton1Click:Connect(function()
	if isHost() then retryRemote:FireServer() end
end)
menuButton.MouseButton1Click:Connect(function()
	if isHost() then returnToMenuRemote:FireServer() end
end)
speedButton.MouseButton1Click:Connect(function()
	if not isHost() then notify(HOST_ONLY) return end
	local speed = workspace:GetAttribute("GameSpeed") or 1
	local options = Config.SpeedOptions
	local idx = table.find(options, speed) or 1
	setSpeedRemote:FireServer(options[idx % #options + 1])
end)
autoSkipButton.MouseButton1Click:Connect(function()
	if not isHost() then notify(HOST_ONLY) return end
	setAutoSkipRemote:FireServer(not workspace:GetAttribute("AutoSkip"))
end)
startMatchButton.MouseButton1Click:Connect(function()
	if not isHost() then notify(HOST_ONLY) return end
	beginMatchRemote:FireServer()
end)

-- the placement preview follows the mouse
RunService.RenderStepped:Connect(function()
	if not selectedUnit then return end
	local pos = WorldView.screenToWorld(UserInputService:GetMouseLocation())
	local unit = Config.Units[selectedUnit]
	local canPlace = Config.CanPlace(pos, towersFolder)
	local affordable = (player:GetAttribute("Money") or 0) >= unit.Cost
	WorldView.updateGhost(pos, canPlace and affordable)
end)

-- ===== Input =====
local UNIT_KEYS = {
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
	Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
}
UserInputService.InputBegan:Connect(function(input, processed)
	if currentState() ~= "Playing" then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if processed then return end
		local pos = WorldView.screenToWorld(UserInputService:GetMouseLocation())
		if selectedUnit then
			if placing then return end
			placing = true
			local ok, success, reason = pcall(function()
				return placeTowerRemote:InvokeServer(bestUnitId(selectedUnit), pos)
			end)
			placing = false
			if ok and success then
				selectUnit(nil)
			elseif ok then
				notify(reason or "Cannot place here")
			end
		else
			local model = WorldView.getTowerAt(pos)
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
		else
			-- 1-6 pick the unit with that [number] in the shop
			local slot = table.find(UNIT_KEYS, input.KeyCode)
			if slot and Config.UnitOrder[slot] then selectUnit(Config.UnitOrder[slot]) end
		end
	end
end)

-- ===== Stage timer (real time, it does not speed up with x2 / x3) =====
local function formatTime(sec)
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return ("%d:%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60), sec % 60)
	end
	return ("%02d:%02d"):format(math.floor(sec / 60), sec % 60)
end

-- The server publishes StageTime (real seconds) + StageSync (server clock) twice a second;
-- between updates we extrapolate in real time.
local function stageSeconds()
	local state = currentState()
	if state == "Menu" then return 0 end
	local t = workspace:GetAttribute("StageTime") or 0
	if state == "Playing" and workspace:GetAttribute("Phase") == "Match" then
		local sync = workspace:GetAttribute("StageSync") or workspace:GetServerTimeNow()
		t += math.max(0, workspace:GetServerTimeNow() - sync)
	end
	return t
end

task.spawn(function()
	while true do
		timeLabel.Text = "TIME " .. formatTime(stageSeconds())
		task.wait(0.1)
	end
end)

refreshState()
