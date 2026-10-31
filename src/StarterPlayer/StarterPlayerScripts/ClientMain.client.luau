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
local PLACE_ROLE = Config.PlaceRole() -- "Lobby" (menus only), "Match" (stages) or "Single"
local IS_MATCH_PLACE = PLACE_ROLE == "Match"

-- If the server scripts fail to start, the remotes below never appear and the screen would stay
-- empty. After 10 seconds, say so (and what is missing) instead of showing nothing.
local waitingFor = "Remotes"
local startupGui = nil
task.delay(10, function()
	if not waitingFor then return end
	startupGui = Instance.new("ScreenGui")
	startupGui.Name = "TDStartupGui"
	startupGui.ResetOnSpawn = false
	startupGui.DisplayOrder = 100
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
	text.TextColor3 = Color3.fromRGB(255, 208, 84)
	text.Font = Enum.Font.Arcade
	text.TextSize = 24
	text.TextWrapped = true
	text.Text = "The game didn't finish loading (stuck at: " .. tostring(waitingFor) .. ")\n"
		.. "Check the logs: View > Output in Studio, or press F9 in the game (Client and Server tabs)."
	text.Parent = startupGui
	startupGui.Parent = playerGui
end)
local function waitRemote(parent, name)
	waitingFor = name
	return parent:WaitForChild(name)
end

local remotes = waitRemote(ReplicatedStorage, "Remotes")
-- every RemoteEvent / RemoteFunction the client uses, by name (Remote.PlaceTower, ...)
local Remote = {}
for _, name in ipairs({
	"ReturnToMenu",
	"Surrender",
	"SetSpeed",
	"SetAutoSkip",
	"BeginMatch",
	"Retry",
	"PlaceTower",
	"UpgradeTower",
	"SellTower",
	"SetTargeting",
	"GetProfile",
	"ProfileUpdated",
	"SetSetting",
	"Summon",
	"StageRewards",
	"SkipWave",
	"LobbyState",
	"LobbyInvited",
	"LobbyCreate",
	"LobbyJoin",
	"LobbyLeave",
	"LobbyInvite",
	"LobbySetPrivacy",
	"LobbyStart",
	"LobbyMatchmake",
	"LobbyRefresh",
	"EquipUnit",
	"LockUnit",
	"SellUnits",
	"FeedUnit",
}) do
	Remote[name] = waitRemote(remotes, name)
end
waitingFor = "loading the UI" -- cleared at the very end of this script

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
-- the unit copy in loadout slot `slot` (nil when the slot is empty)
local function slotUnit(slot)
	local uid = profile and profile.Loadout and profile.Loadout[slot]
	return (uid and uid ~= "" and profile.Units[uid]) or nil
end
-- the loadout slot a unit copy is in (nil when it isn't equipped)
local function loadoutSlotOf(uid)
	if not profile or not profile.Loadout then return nil end
	return table.find(profile.Loadout, uid)
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
-- the Lobby place has no map (stages are played in the Match place), so nothing to draw there
if PLACE_ROLE ~= "Lobby" then
	waitingFor = "drawing the map: this place has no Workspace.Waypoints. Sync it with match.project.json (Rojo port 34873) and publish"
	WorldView.start(worldGui, { rightInset = SHOP_W, topInset = 176, bottomInset = 156 })
	waitingFor = "loading the UI"
end

-- ===== Map camera: mouse wheel zooms; right/middle-drag, WASD / arrow keys or a finger drag pan; C re-centers
local DRAG_THRESHOLD = 6   -- pixels a right-drag must move before it counts as panning (a plain right-click cancels)
local KEY_PAN_SPEED = 700  -- screen pixels per second for WASD / arrow keys
local mapDrag = nil        -- { Last = Vector2, Moved = bool } while a right/middle mouse button is held

local function isPanButton(t)
	return t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.MouseButton3
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not isPanButton(input.UserInputType) then return end
	mapDrag = { Last = UserInputService:GetMouseLocation(), Start = UserInputService:GetMouseLocation(), Moved = false }
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		WorldView.zoom(input.Position.Z > 0 and 1 or -1)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and mapDrag then
		local pos = UserInputService:GetMouseLocation()
		if not mapDrag.Moved and (pos - mapDrag.Start).Magnitude >= DRAG_THRESHOLD then
			mapDrag.Moved = true
		end
		if mapDrag.Moved then
			local d = pos - mapDrag.Last
			WorldView.pan(d.X, d.Y)
		end
		mapDrag.Last = pos
	end
end)

-- one-finger drag on touch screens (a tap does not pan, so tapping to place still works)
local lastTouchPan = nil
UserInputService.TouchPan:Connect(function(_, translation, _, state, processed)
	if processed or state == Enum.UserInputState.Begin then
		lastTouchPan = translation
		return
	end
	if lastTouchPan then
		local d = translation - lastTouchPan
		WorldView.pan(d.X, d.Y)
	end
	lastTouchPan = (state == Enum.UserInputState.End) and nil or translation
end)

local PAN_KEYS = {
	[Enum.KeyCode.A] = Vector2.new(1, 0), [Enum.KeyCode.Left] = Vector2.new(1, 0),
	[Enum.KeyCode.D] = Vector2.new(-1, 0), [Enum.KeyCode.Right] = Vector2.new(-1, 0),
	[Enum.KeyCode.W] = Vector2.new(0, 1), [Enum.KeyCode.Up] = Vector2.new(0, 1),
	[Enum.KeyCode.S] = Vector2.new(0, -1), [Enum.KeyCode.Down] = Vector2.new(0, -1),
}
RunService.RenderStepped:Connect(function(dt)
	if UserInputService:GetFocusedTextBox() then return end
	local dir = Vector2.zero
	for key, v in pairs(PAN_KEYS) do
		if UserInputService:IsKeyDown(key) then dir += v end
	end
	if dir.Magnitude > 0 then
		local d = dir.Unit * KEY_PAN_SPEED * dt
		WorldView.pan(d.X, d.Y)
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
local summonMenuButton = pixelButton(menu, "SUMMON", UDim2.fromOffset(340, 64), UDim2.new(0.5, 0, 0.46, 230), 30)

-- currencies, top-right of the main menu (filled in by applyProfile)
local menuCurrency = label(menu, {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -24, 0, 64),
	Size = UDim2.fromOffset(360, 28),
	TextSize = 22,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "",
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
-- SKIP: vote to start the next round now (everyone in the match has to agree)
local skipWaveButton = pixelButton(hudGui, "SKIP", UDim2.fromOffset(110, 34), UDim2.new(0.5, -SHOP_W / 2 + 214, 0, 81), 18)
skipWaveButton.Visible = false

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
	Size = UDim2.fromOffset(820, 22),
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
label(shop, {
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
local selectedUnit = nil            -- unit name chosen in the shop (placing mode)
local selectedUid = nil             -- ...the saved copy that will be placed
local selectedSlot = nil            -- ...and its loadout slot
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
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
})
make("UITextSizeConstraint", { MaxTextSize = 15 }, abilityLabel)
local upButton = pixelButton(upPanel, "UPGRADE", UDim2.new(1, -104, 0, 54), UDim2.new(0, 112, 0, 226), 20, GREEN_BTN, GREEN_EDGE, WHITE)
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
local function fmtNum(v) return (("%.1f"):format(v):gsub("%.0$", "")) end

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
	local unitLevel = selectedTower:GetAttribute("UnitLevel") or 1
	local cur = Config.ScaledStats(unitName, level, unitLevel)
	if not cur then return end
	local nxt = Config.ScaledStats(unitName, level + 1, unitLevel)

	upPanel.Visible = true
	upTitle.Text = ("%s  LV%d  UP%d"):format(string.upper(unitName), unitLevel, level)
	rowDamage.Text = statText("DAMAGE", cur.Damage, nxt and nxt.Damage, fmtNum)
	rowRange.Text = statText("RANGE ", cur.Range, nxt and nxt.Range, fmtNum)
	rowSpeed.Text = statText("SPA   ", cur.Cooldown, nxt and nxt.Cooldown, function(v)
		local txt = ("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")
		return txt .. "s"
	end)

	-- attack shape + ability: "NEXT: ..." when the next upgrade adds or changes one, otherwise the current one
	local parts, upcoming = {}, false
	local curAttack = Config.DescribeAttack(Config.AttackOf(unitName, level))
	local nxtAttack = nxt and Config.DescribeAttack(Config.AttackOf(unitName, level + 1))
	if nxtAttack and nxtAttack ~= curAttack then
		table.insert(parts, nxtAttack)
		upcoming = true
	elseif curAttack ~= "SINGLE" then
		table.insert(parts, curAttack)
	end
	if nxt and nxt.Ability and not sameAbility(cur.Ability, nxt.Ability) then
		table.insert(parts, Config.DescribeAbility(nxt.Ability))
		upcoming = true
	elseif cur.Ability then
		table.insert(parts, Config.DescribeAbility(cur.Ability))
	end
	abilityLabel.Text = (upcoming and "NEXT: " or "") .. table.concat(parts, "  |  ")
	abilityLabel.TextColor3 = upcoming and GREEN or (cur.Ability and ABILITY_COLORS[cur.Ability.Kind] or WHITE)

	local mine = selectedTower:GetAttribute("OwnerId") == player.UserId

	-- targeting + sell info
	local mode = selectedTower:GetAttribute("Targeting") or "First"
	targetLabel.Text = "TARGET: " .. string.upper(mode)
	targetLabel.TextColor3 = (mode == "None") and RED or WHITE
	local spent = selectedTower:GetAttribute("Spent") or 0
	sellButton.Text = mine and ("SELL  $" .. fmt(math.floor(spent * Config.SellRefund))) or "SELL  (NOT YOURS)"
	setButtonColor(sellButton, mine and RED_BTN or GREY_BTN)

	upName.TextColor3 = GOLD
	if not nxt and mine then
		upName.Text = "FULLY UPGRADED!"
		upButton.Text = "MAX LEVEL"
		setButtonColor(upButton, GREY_BTN)
		setButtonColor(upMaxButton, GREY_BTN)
	elseif not mine then
		local owner = Players:GetPlayerByUserId(selectedTower:GetAttribute("OwnerId") or 0)
		upName.Text = "Belongs to " .. (owner and owner.DisplayName or "a player who left")
		local colorIndex = owner and owner:GetAttribute("PlayerColor")
		if colorIndex and Config.PlayerColors[colorIndex] then upName.TextColor3 = Config.PlayerColors[colorIndex] end
		upButton.Text = "LOCKED"
		setButtonColor(upButton, GREY_BTN)
		setButtonColor(upMaxButton, GREY_BTN)
	else
		upName.Text = "NEXT: " .. string.upper(nxt.Name)
		upButton.Text = "UPGRADE  $" .. fmt(nxt.Cost)
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
		return Remote.UpgradeTower:InvokeServer(selectedTower, all == true)
	end)
	upgrading = false
	if ok and not success then notify(reason or "Cannot upgrade") end
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
		return Remote.SellTower:InvokeServer(model)
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
	Remote.SetTargeting:FireServer(selectedTower, modes[idx])
end
targetPrev.MouseButton1Click:Connect(function() cycleTarget(-1) end)
targetNext.MouseButton1Click:Connect(function() cycleTarget(1) end)

-- ===== Shop cards (with a pixel-art portrait) =====
-- how many of each unit I have on the map: { [unitName] = n }
local function myPlaced()
	local byUnit = {}
	for _, m in ipairs(towersFolder:GetChildren()) do
		local n = m:GetAttribute("UnitName")
		if n and m:GetAttribute("OwnerId") == player.UserId then
			byUnit[n] = (byUnit[n] or 0) + 1
		end
	end
	return byUnit
end

local function refreshCards()
	local money = player:GetAttribute("Money") or 0
	local byUnit = myPlaced()
	for slot, card in pairs(cards) do
		local unit = Config.Units[card.Name]
		local limit = Config.PlaceLimit(card.Name)
		local usable = money >= unit.Cost and (byUnit[card.Name] or 0) < limit
		card.Cost.Text = ("$%s  %d/%d"):format(fmt(unit.Cost), byUnit[card.Name] or 0, limit)
		card.Cost.TextColor3 = usable and GOLD or RED
		card.Button.BackgroundColor3 = usable and PANEL_LIGHT or rgb(36, 42, 62)
		card.Stroke.Color = (selectedSlot == slot) and GOLD or PANEL_EDGE
		card.Stroke.Thickness = (selectedSlot == slot) and 4 or 3
	end
end
towersFolder.ChildAdded:Connect(function() refreshCards() end)
towersFolder.ChildRemoved:Connect(function() refreshCards() end)

local function updateHint()
	local prep = currentState() == "Playing" and workspace:GetAttribute("Phase") == "Prep"
	if currentState() == "Playing" and not player:GetAttribute("InMatch") then
		hint.Text = "SPECTATING  -  you join the match at the next round"
		hint.Visible = true
	elseif selectedUnit then
		hint.Text = "Click to place   -   Right-click or Q to cancel"
		hint.Visible = true
	elseif prep then
		hint.Text = "Place your units before the match begins!   (Right-drag / WASD: move map   C: center)"
		hint.Visible = true
	else
		hint.Visible = false
	end
end

-- slot = loadout slot to place from (nil = stop placing)
local function selectUnit(slot)
	selectedUnit, selectedUid, selectedSlot = nil, nil, nil
	WorldView.clearGhost()
	local unit = slot and slotUnit(slot)
	if unit and currentState() == "Playing" and Config.Units[unit.Name] then
		deselectTower()
		selectedUnit, selectedUid, selectedSlot = unit.Name, unit.Id, slot
		WorldView.setGhost(unit.Name, unit.Level)
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

-- One shop card per filled loadout slot ([1]-[6] = hotkeys). Rebuilt when the loadout changes.
local emptyShopLabel = label(list, {
	LayoutOrder = 99,
	Size = UDim2.new(1, 0, 0, 80),
	Text = "No units equipped.\nOpen the INVENTORY\nfrom the main menu.",
	TextSize = 16,
	TextWrapped = true,
	TextColor3 = TEXT_DIM,
	Visible = false,
})
local shopSignature = nil

local function rebuildShop()
	local parts = {}
	for slot = 1, Config.LoadoutSlots do
		local u = slotUnit(slot)
		table.insert(parts, u and (u.Id .. ":" .. u.Level) or "-")
	end
	local signature = table.concat(parts, ",")
	if signature == shopSignature then
		refreshCards()
		return
	end
	shopSignature = signature
	if selectedSlot then selectUnit(nil) end
	for _, c in pairs(cards) do c.Button:Destroy() end
	table.clear(cards)

	for slot = 1, Config.LoadoutSlots do
		local u = slotUnit(slot)
		if u and Config.Units[u.Name] then
			local name = u.Name
			local unit = Config.Units[name]
			local stats = Config.ScaledStats(name, 1, u.Level)
			local card = make("TextButton", {
				Name = name,
				LayoutOrder = slot,
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
				Text = "[" .. slot .. "]",
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
				Text = ("LV%d  DMG %s  RNG %s"):format(u.Level, fmtNum(stats.Damage), fmtNum(stats.Range)),
				TextSize = 14,
				TextColor3 = TEXT_DIM,
			})
			local costLabel = label(card, {
				Position = UDim2.fromOffset(0, 146),
				Size = UDim2.new(1, 0, 0, 30),
				Text = "$" .. fmt(unit.Cost),
				TextSize = 24,
				TextColor3 = GOLD,
			})
			cards[slot] = { Cost = costLabel, Stroke = stroke, Button = card, Name = name }
			card.MouseButton1Click:Connect(function()
				if selectedSlot == slot then selectUnit(nil) else selectUnit(slot) end
			end)
		end
	end
	emptyShopLabel.Visible = next(cards) == nil
	refreshCards()
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
	Size = UDim2.fromOffset(560, 520),
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
	Size = UDim2.new(1, -80, 0, 116),
	TextSize = 18,
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
	local text = "REWARDS\n" .. table.concat(parts, "   ")
	if r.UnitXP and r.UnitXP > 0 then
		text ..= "\n+" .. fmt(r.UnitXP) .. " XP to every equipped unit"
	end
	if r.LevelUps and #r.LevelUps > 0 then
		local ups = {}
		for _, up in ipairs(r.LevelUps) do
			table.insert(ups, ("%s LV%d"):format(string.upper(up.Name), up.Level))
		end
		text ..= "\nLEVEL UP: " .. table.concat(ups, ", ")
	end
	return text
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
		resultSub.Text = ("All %d rounds survived!"):format(workspace:GetAttribute("TotalRounds") or 0)
	elseif reason == "Surrender" then
		resultSub.Text = "You surrendered."
	else
		resultSub.Text = "The enemies broke through!"
	end
	local totalRounds = workspace:GetAttribute("TotalRounds") or 0
	rowRound.Text = totalRounds > 0 and ("%d / %d"):format(workspace:GetAttribute("Round") or 0, totalRounds)
		or tostring(workspace:GetAttribute("Round") or 0)
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
	Size = UDim2.fromOffset(420, 484),
})
label(settingsPanel, {
	Position = UDim2.fromOffset(0, 14),
	Size = UDim2.new(1, 0, 0, 44),
	Text = "SETTINGS",
	TextSize = 36,
	TextColor3 = GOLD,
})

local mainView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, settingsPanel)
-- AUTO SKIP shows MY choice; the line under it explains what it does
local autoSkipButton = pixelButton(mainView, "AUTO SKIP: ON", UDim2.fromOffset(330, 54), UDim2.new(0.5, 0, 0, 94), 22)
local autoSkipTeamLabel = label(mainView, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 126),
	Size = UDim2.new(1, -40, 0, 20),
	Text = "",
	TextSize = 14,
	TextColor3 = TEXT_DIM,
})
local healthBarsButton = pixelButton(mainView, "HEALTH BARS: HOVER", UDim2.fromOffset(330, 54), UDim2.new(0.5, 0, 0, 182), 22)
local resumeButton = pixelButton(mainView, "RESUME", UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 0, 268), 30, GREEN_BTN, GREEN_EDGE, WHITE)
local surrenderButton = pixelButton(mainView, "SURRENDER", UDim2.fromOffset(300, 64), UDim2.new(0.5, 0, 0, 348), 30, RED_BTN, RED_EDGE, WHITE)
label(mainView, {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 400),
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
	Remote.SetSetting:FireServer("AlwaysHealthBars", alwaysHealthBars) -- remembered between sessions
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
	if not player:GetAttribute("InMatch") then return end
	if player:GetAttribute("VoteSurrender") then
		Remote.Surrender:FireServer() -- take the vote back
		return
	end
	mainView.Visible = false
	confirmView.Visible = true
end)
noButton.MouseButton1Click:Connect(closeSettings)
yesButton.MouseButton1Click:Connect(function()
	closeSettings()
	Remote.Surrender:FireServer()
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
	local totalRounds = workspace:GetAttribute("TotalRounds") or 0
	local lastRound = totalRounds > 0 and round >= totalRounds
	roundLabel.Text = totalRounds > 0 and ("ROUND %d / %d"):format(round, totalRounds) or ("ROUND %d"):format(round)
	local cd = workspace:GetAttribute("Countdown") or 0
	local prep = currentState() == "Playing" and workspace:GetAttribute("Phase") == "Prep"
	prepPanel.Visible = prep
	prepTitle.Text = "MATCH STARTS IN " .. (workspace:GetAttribute("PrepLeft") or 0)
	-- Auto Skip OFF: no timer while the wave spawns (shows "WAVE r  x/y"), then "NEXT ROUND IN n"
	local spawning = workspace:GetAttribute("WaveState") == "Spawning" and cd == 0
	countdownPlate.Visible = not prep and (cd > 0 or spawning or lastRound) and currentState() == "Playing"
	if round == 0 then
		countdownLabel.Text = "FIRST ROUND IN " .. cd
	elseif lastRound then
		countdownLabel.Text = "FINAL ROUND!"
	elseif spawning then
		countdownLabel.Text = ("WAVE %d   %d/%d"):format(round, workspace:GetAttribute("WaveSpawned") or 0, workspace:GetAttribute("WaveCount") or 0)
	else
		countdownLabel.Text = "NEXT ROUND IN " .. cd
	end
	-- votes: with more than one player the buttons show how many agree ("2/3")
	local voters = workspace:GetAttribute("Voters") or 1
	local multi = voters > 1
	local inMatch = player:GetAttribute("InMatch") == true
	local speed = workspace:GetAttribute("GameSpeed") or 1
	speedButton.Text = "SPEED  X" .. speed -- set by the host
	setButtonColor(speedButton, SPEED_COLORS[speed] or BTN)
	-- Auto Skip ON = this player skips every wave by themselves (once most of it is out);
	-- OFF = they press SKIP. The next round starts early once every player skips.
	local mineAuto = player:GetAttribute("VoteAutoSkip") == true
	autoSkipButton.Text = mineAuto and "AUTO SKIP: ON" or "AUTO SKIP: OFF"
	setButtonColor(autoSkipButton, mineAuto and GREEN_BTN or rgb(150, 80, 70))
	autoSkipTeamLabel.Text = mineAuto and "You skip each wave once most of it is out"
		or "Press SKIP next to the round timer to move on"

	-- skip wave: for players with Auto Skip OFF (Auto Skip ON players skip by themselves and are counted)
	local myVoteSkip = player:GetAttribute("VoteSkip") == true
	skipWaveButton.Visible = currentState() == "Playing" and workspace:GetAttribute("Phase") == "Match"
		and inMatch and not mineAuto and round >= 1 and not lastRound
	skipWaveButton.Text = multi and ("SKIP %d/%d"):format(workspace:GetAttribute("SkipVotes") or 0, voters) or "SKIP"
	setButtonColor(skipWaveButton, myVoteSkip and GREEN_BTN or BTN)

	-- surrender: everyone in the match has to agree (solo: at once)
	local myVoteSurrender = player:GetAttribute("VoteSurrender") == true
	if not inMatch then
		surrenderButton.Text = "SPECTATING"
	elseif not multi then
		surrenderButton.Text = "SURRENDER"
	else
		surrenderButton.Text = (myVoteSurrender and "CANCEL VOTE %d/%d" or "SURRENDER %d/%d")
			:format(workspace:GetAttribute("SurrenderVotes") or 0, voters)
	end
	setButtonColor(surrenderButton, (inMatch and not myVoteSurrender) and RED_BTN or GREY_BTN)
	refreshCards()
	refreshUpgradePanel()
	updateHint()
	if overlay.Visible then showResult(currentState()) end
end

-- =====================================================================
--  INVENTORY: loadout, unit list (sort / filter), unit details (equip, feed Essence, lock, sell),
--  materials and SUMMON. Data comes from the server's saved profile; every action goes through
--  a RemoteFunction and the server sends the updated profile back.
-- =====================================================================
-- Built inside its own function: Luau allows only 200 locals per function, and the main
-- chunk of this script is close to that limit.
local function buildInventory()

	local INV_W, INV_H = 780, 620
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
		Size = UDim2.fromOffset(INV_W, INV_H),
		Active = true, -- clicks on the panel must not reach the dim background (which closes it)
	})
	-- the panel shrinks on small screens
	local inventoryScale = make("UIScale", { Scale = 1 }, inventoryPanel)
	local function fitInventory()
		local size = inventoryDim.AbsoluteSize
		if size.X > 0 then
			inventoryScale.Scale = math.min(1, (size.X - 24) / INV_W, (size.Y - 24) / INV_H)
		end
	end
	inventoryDim:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitInventory)

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
	local goldLabel = label(inventoryPanel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -20, 0, 46),
		Size = UDim2.fromOffset(200, 30),
		Text = "GOLD: 0",
		TextSize = 18,
		TextColor3 = Config.GoldColor,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	local unitsTab = pixelButton(inventoryPanel, "UNITS", UDim2.fromOffset(220, 44), UDim2.new(0, 140, 0, 82), 22)
	local materialsTab = pixelButton(inventoryPanel, "MATERIALS", UDim2.fromOffset(200, 44), UDim2.new(0, 370, 0, 82), 22)

	local unitsView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, inventoryPanel)
	local materialsView = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, inventoryPanel)

	-- message line above the bottom buttons (summon results, errors, "pick a slot"...)
	local invMessage = label(inventoryPanel, {
		Position = UDim2.fromOffset(20, 532),
		Size = UDim2.new(1, -40, 0, 24),
		Text = "",
		TextSize = 18,
		TextColor3 = TEXT_DIM,
	})
	local function invNotify(text, color)
		invMessage.Text = text
		invMessage.TextColor3 = color or TEXT_DIM
	end

	local inventoryClose = pixelButton(inventoryPanel, "CLOSE", UDim2.fromOffset(420, 56), UDim2.new(0.5, 0, 0, 584), 28, RED_BTN, RED_EDGE, WHITE)

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

	-- small sprite (for loadout slots); fits a box of `boxSize` pixels
	local function miniSprite(parent, name, boxSize)
		local w, h = PixelArt.size(name)
		local scale = math.max(1, math.floor((boxSize - 8) / math.max(w, h)))
		local holder = make("Frame", {
			Position = UDim2.new(0.5, -(w * scale) / 2, 0.5, -(h * scale) / 2),
			Size = UDim2.fromOffset(0, 0),
			BackgroundTransparency = 1,
		}, parent)
		local scaler = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, holder)
		make("UIScale", { Scale = scale }, scaler)
		PixelArt.sprite(name).Parent = scaler
	end

	-- ===== state =====
	local inventoryTab = "Units"
	local SORT_MODES = { "Rarity", "Level", "Newest" }
	local sortMode = "Rarity"
	local filterMode = "All"          -- "All" or a rarity name
	local selectedInvUid = nil        -- unit shown in the detail panel
	local pickingSlotFor = nil        -- unit waiting for the player to pick a loadout slot (loadout full)
	local sellConfirmUntil = 0
	local invBusy = false

	-- calls an inventory RemoteFunction; shows the server's message when it says no
	local function invCall(remote, ...)
		if invBusy then return false end
		invBusy = true
		local args = table.pack(...)
		local ok, success, a, b = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		invBusy = false
		if not ok then
			invNotify("Something went wrong, try again", RED)
			return false
		end
		if not success then invNotify(tostring(a or "Not possible"), RED) end
		return success, a, b
	end

	-- ===== loadout strip =====
	label(unitsView, {
		Position = UDim2.fromOffset(20, 108),
		Size = UDim2.fromOffset(300, 20),
		Text = "LOADOUT  (used in stages, keys 1-" .. Config.LoadoutSlots .. ")",
		TextSize = 15,
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	local slotButtons = {}
	for slot = 1, Config.LoadoutSlots do
		local b = make("TextButton", {
			Position = UDim2.fromOffset(20 + (slot - 1) * 76, 132),
			Size = UDim2.fromOffset(68, 68),
			BackgroundColor3 = rgb(20, 24, 40),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
		}, unitsView)
		local stroke = make("UIStroke", { Color = PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		local content = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, b)
		slotButtons[slot] = { Button = b, Stroke = stroke, Content = content }
	end

	-- ===== sort / filter =====
	local sortButton = pixelButton(unitsView, "SORT: RARITY", UDim2.fromOffset(200, 32), UDim2.new(0, 120, 0, 222), 15)
	local filterButton = pixelButton(unitsView, "SHOW: ALL", UDim2.fromOffset(200, 32), UDim2.new(0, 330, 0, 222), 15)

	-- ===== unit grid =====
	local unitsScroll = make("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 246),
		Size = UDim2.fromOffset(470, 280),
		BackgroundColor3 = rgb(20, 24, 40),
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
	}, unitsView)
	make("UIGridLayout", { CellSize = UDim2.fromOffset(140, 176), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, unitsScroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, unitsScroll)

	-- ===== detail panel =====
	local detail = make("Frame", {
		Position = UDim2.fromOffset(505, 108),
		Size = UDim2.fromOffset(255, 418),
		BackgroundColor3 = PANEL_LIGHT,
		BorderSizePixel = 0,
	}, unitsView)
	make("UIStroke", { Color = PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, detail)
	local detailEmpty = label(detail, {
		Size = UDim2.fromScale(1, 1),
		Text = "SELECT A UNIT",
		TextSize = 20,
		TextColor3 = TEXT_DIM,
	})
	local detailContent = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, detail)
	local detailPortrait = make("Frame", { Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1 }, detailContent)
	local function detailLine(y, size, color)
		return label(detailContent, {
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.new(1, -28, 0, size + 4),
			Text = "",
			TextSize = size,
			TextColor3 = color or WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	local dName = detailLine(98, 22)
	local dSub = detailLine(124, 16, GOLD)
	local xpBack = make("Frame", { Position = UDim2.fromOffset(14, 148), Size = UDim2.new(1, -28, 0, 16), BackgroundColor3 = rgb(18, 22, 34), BorderSizePixel = 0 }, detailContent)
	make("UIStroke", { Color = PANEL_EDGE, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, xpBack)
	local xpFill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = rgb(110, 200, 255), BorderSizePixel = 0 }, xpBack)
	local xpText = label(xpBack, { Size = UDim2.fromScale(1, 1), Text = "", TextSize = 13, ZIndex = 3 })
	local dDamage = detailLine(170, 16, TEXT_DIM)
	local dRange = detailLine(190, 16, TEXT_DIM)
	local dSpeed = detailLine(210, 16, TEXT_DIM)
	local dAbility = detailLine(230, 14, GREEN)
	local dState = detailLine(250, 15, TEXT_DIM)
	local equipButton = pixelButton(detailContent, "EQUIP", UDim2.new(1, -28, 0, 40), UDim2.new(0.5, 0, 0, 294), 20, GREEN_BTN, GREEN_EDGE, WHITE)
	local feed1Button = pixelButton(detailContent, "FEED 1", UDim2.fromOffset(108, 36), UDim2.new(0, 68, 0, 340), 16)
	local feed10Button = pixelButton(detailContent, "FEED 10", UDim2.fromOffset(108, 36), UDim2.new(1, -68, 0, 340), 16)
	local dEssence = label(detailContent, {
		Position = UDim2.fromOffset(0, 360),
		Size = UDim2.new(1, 0, 0, 16),
		Text = "",
		TextSize = 12,
		TextColor3 = TEXT_DIM,
	})
	local lockButton = pixelButton(detailContent, "LOCK", UDim2.fromOffset(108, 34), UDim2.new(0, 68, 0, 394), 16)
	local sellButtonInv = pixelButton(detailContent, "SELL", UDim2.fromOffset(108, 34), UDim2.new(1, -68, 0, 394), 16, RED_BTN, RED_EDGE, WHITE)

	-- ===== materials =====
	local materialsScroll = make("ScrollingFrame", {
		Position = UDim2.fromOffset(20, 110),
		Size = UDim2.new(1, -40, 0, 416),
		BackgroundColor3 = rgb(20, 24, 40),
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
	}, materialsView)
	make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, materialsScroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 10) }, materialsScroll)

	-- ===== refresh =====
	local refreshInventory -- defined below; the buttons call it

	local function ownedUnitsSorted()
		local owned = {}
		if profile then
			for _, u in pairs(profile.Units) do
				if Config.Units[u.Name] and (filterMode == "All" or Config.Units[u.Name].Rarity == filterMode) then
					table.insert(owned, u)
				end
			end
		end
		table.sort(owned, function(a, b)
			local ra, rb = Config.RarityOf(a.Name).Order, Config.RarityOf(b.Name).Order
			if sortMode == "Level" and a.Level ~= b.Level then return a.Level > b.Level end
			if sortMode == "Newest" and (a.Obtained or 0) ~= (b.Obtained or 0) then return (a.Obtained or 0) > (b.Obtained or 0) end
			if ra ~= rb then return ra > rb end
			if a.Level ~= b.Level then return a.Level > b.Level end
			if (a.Obtained or 0) ~= (b.Obtained or 0) then return (a.Obtained or 0) > (b.Obtained or 0) end
			return a.Id < b.Id
		end)
		return owned
	end

	local function refreshLoadoutStrip()
		for slot, s in pairs(slotButtons) do
			s.Content:ClearAllChildren()
			local u = slotUnit(slot)
			local picking = pickingSlotFor ~= nil
			s.Stroke.Color = picking and GOLD or ((u and u.Id == selectedInvUid) and WHITE or (u and Config.RarityOf(u.Name).Color or PANEL_EDGE))
			s.Stroke.Thickness = (picking or (u and u.Id == selectedInvUid)) and 4 or 3
			label(s.Content, { Position = UDim2.fromOffset(3, 2), Size = UDim2.fromOffset(20, 14), Text = tostring(slot), TextSize = 12, ZIndex = 3 })
			if u then
				miniSprite(s.Content, u.Name, 60)
				label(s.Content, { Position = UDim2.new(0, 0, 1, -15), Size = UDim2.new(1, 0, 0, 14), Text = "LV" .. u.Level, TextSize = 12, TextColor3 = GOLD, ZIndex = 3 })
			else
				label(s.Content, { Size = UDim2.fromScale(1, 1), Text = "EMPTY", TextSize = 12, TextColor3 = TEXT_DIM })
			end
		end
	end

	local function unitCard(order, name, instance)
		local rarity = Config.RarityOf(name)
		local selected = instance ~= nil and instance.Id == selectedInvUid
		local card = make("TextButton", {
			LayoutOrder = order,
			BackgroundColor3 = instance and PANEL_LIGHT or rgb(36, 42, 62),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
		}, unitsScroll)
		make("UIStroke", {
			Color = selected and WHITE or (instance and rarity.Color or PANEL_EDGE),
			Thickness = selected and 4 or 3,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}, card)
		makePortrait(card, name)
		label(card, { Position = UDim2.fromOffset(0, 92), Size = UDim2.new(1, 0, 0, 22), Text = string.upper(name), TextSize = 18, TextColor3 = rarity.Color })
		if instance then
			label(card, {
				Position = UDim2.fromOffset(0, 114), Size = UDim2.new(1, 0, 0, 20),
				Text = ("LV %d/%d"):format(instance.Level, Config.MaxUnitLevel(name)),
				TextSize = 16, TextColor3 = GOLD,
			})
			local stats = Config.ScaledStats(name, 1, instance.Level)
			label(card, { Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 0, 18), Text = ("DMG %s  RNG %s"):format(fmtNum(stats.Damage), fmtNum(stats.Range)), TextSize = 13, TextColor3 = TEXT_DIM })
			local slot = loadoutSlotOf(instance.Id)
			if slot then
				label(card, { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(30, 16), Text = "E" .. slot, TextSize = 14, TextColor3 = GREEN, ZIndex = 3 })
			end
			if instance.Locked then
				label(card, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(44, 16), Text = "LOCK", TextSize = 13, TextColor3 = RED, ZIndex = 3 })
			end
			card.MouseButton1Click:Connect(function()
				selectedInvUid = instance.Id
				pickingSlotFor = nil
				sellConfirmUntil = 0
				refreshInventory()
			end)
		end
	end

	local function refreshUnitGrid()
		clearGui(unitsScroll)
		local owned = ownedUnitsSorted()
		for i, u in ipairs(owned) do unitCard(i, u.Name, u) end
		local total = 0
		if profile then for _ in pairs(profile.Units) do total += 1 end end
		unitsTab.Text = ("UNITS %d/%d"):format(total, Config.MaxUnitsOwned)
		sortButton.Text = "SORT: " .. string.upper(sortMode)
		filterButton.Text = "SHOW: " .. string.upper(filterMode)
	end

	-- slot holding ANOTHER copy of the same unit type as u (the loadout allows one copy per unit)
	local function sameTypeSlot(u)
		for slot, id in ipairs(profile.Loadout) do
			local other = id ~= u.Id and profile.Units[id]
			if other and other.Name == u.Name then return slot end
		end
		return nil
	end

	local function firstAbility(name)
		for i, lv in ipairs(Config.Units[name].Levels) do
			if lv.Ability then return i, lv.Ability end
		end
		return nil
	end

	local function refreshDetail()
		local u = profile and selectedInvUid and profile.Units[selectedInvUid]
		detailEmpty.Visible = not u
		detailContent.Visible = u ~= nil
		if not u then return end
		local name = u.Name
		local rarity = Config.RarityOf(name)
		local maxLevel = Config.MaxUnitLevel(name)

		detailPortrait:ClearAllChildren()
		makePortrait(detailPortrait, name)
		dName.Text = string.upper(name)
		dName.TextColor3 = rarity.Color
		dSub.Text = ("%s   LV %d/%d"):format(string.upper(Config.Units[name].Rarity or ""), u.Level, maxLevel)

		if u.Level >= maxLevel then
			xpFill.Size = UDim2.fromScale(1, 1)
			xpText.Text = "MAX LEVEL"
		else
			local need = Config.XpToNext(u.Level)
			xpFill.Size = UDim2.fromScale(math.clamp((u.XP or 0) / need, 0, 1), 1)
			xpText.Text = ("%s / %s XP"):format(fmt(u.XP or 0), fmt(need))
		end

		local stats = Config.ScaledStats(name, 1, u.Level)
		local nextStats = u.Level < maxLevel and Config.ScaledStats(name, 1, u.Level + 1)
		dDamage.Text = "DAMAGE  " .. fmtNum(stats.Damage) .. (nextStats and ("  (next " .. fmtNum(nextStats.Damage) .. ")") or "")
		dRange.Text = "RANGE   " .. fmtNum(stats.Range)
		dSpeed.Text = "SPA     " .. spaText(stats.Cooldown)
		local abilityLevel, ability = firstAbility(name)
		dAbility.Text = ability and ("UP%d: %s"):format(abilityLevel, Config.DescribeAbility(ability)) or ""

		local slot = loadoutSlotOf(u.Id)
		local sameType = not slot and sameTypeSlot(u) -- another copy of this unit is equipped
		if pickingSlotFor == u.Id then
			dState.Text = "PICK A LOADOUT SLOT ABOVE"
			dState.TextColor3 = GOLD
		elseif slot then
			dState.Text = "EQUIPPED IN SLOT " .. slot
			dState.TextColor3 = GREEN
		elseif sameType then
			dState.Text = ("ANOTHER %s IS IN SLOT %d"):format(string.upper(name), sameType)
			dState.TextColor3 = GOLD
		else
			dState.Text = "NOT EQUIPPED"
			dState.TextColor3 = TEXT_DIM
		end
		equipButton.Text = slot and "UNEQUIP" or (sameType and ("SWAP (SLOT %d)"):format(sameType))
			or (pickingSlotFor == u.Id and "CANCEL" or "EQUIP")
		setButtonColor(equipButton, slot and RED_BTN or GREEN_BTN)

		local essence = profile.Items.WispEssence or 0
		local canFeed = essence > 0 and u.Level < maxLevel
		setButtonColor(feed1Button, canFeed and BTN or GREY_BTN)
		setButtonColor(feed10Button, canFeed and BTN or GREY_BTN)
		dEssence.Text = ("WISP ESSENCE x%s  (+%d XP EACH)"):format(fmt(essence), Config.Leveling.XpPerEssence)

		lockButton.Text = u.Locked and "UNLOCK" or "LOCK"
		local sellable = not u.Locked and not slot
		if os.clock() < sellConfirmUntil and sellable then
			sellButtonInv.Text = "CONFIRM?"
		else
			sellButtonInv.Text = ("SELL +%dG"):format(rarity.SellGold)
		end
		setButtonColor(sellButtonInv, sellable and RED_BTN or GREY_BTN)
	end

	local function refreshMaterials()
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

	refreshInventory = function()
		unitsView.Visible = inventoryTab == "Units"
		materialsView.Visible = inventoryTab == "Materials"
		setButtonColor(unitsTab, inventoryTab == "Units" and GREEN_BTN or BTN)
		setButtonColor(materialsTab, inventoryTab == "Materials" and GREEN_BTN or BTN)
		gemsLabel.Text = "GEMS: " .. fmt(profile and profile.Gems or 0)
		goldLabel.Text = "GOLD: " .. fmt(profile and profile.Gold or 0)
		if selectedInvUid and not (profile and profile.Units[selectedInvUid]) then
			selectedInvUid, pickingSlotFor = nil, nil -- sold
		end
		refreshLoadoutStrip()
		refreshUnitGrid()
		refreshDetail()
		refreshMaterials()
	end

	-- ===== actions =====
	for slot, s in pairs(slotButtons) do
		s.Button.MouseButton1Click:Connect(function()
			if pickingSlotFor then
				local uid = pickingSlotFor
				pickingSlotFor = nil
				if invCall(Remote.EquipUnit, uid, slot) then invNotify("Equipped in slot " .. slot, GREEN) end
				refreshInventory()
			else
				local u = slotUnit(slot)
				if u then
					selectedInvUid = u.Id
					refreshInventory()
				end
			end
		end)
	end

	equipButton.MouseButton1Click:Connect(function()
		local u = profile and selectedInvUid and profile.Units[selectedInvUid]
		if not u then return end
		local slot = loadoutSlotOf(u.Id)
		local sameType = sameTypeSlot(u)
		if slot then
			if invCall(Remote.EquipUnit, "", slot) then invNotify("Removed from slot " .. slot) end
		elseif sameType then
			-- only one copy of each unit in the loadout: this copy replaces the other one
			if invCall(Remote.EquipUnit, u.Id, sameType) then invNotify(("Swapped into slot %d"):format(sameType), GREEN) end
		elseif pickingSlotFor == u.Id then
			pickingSlotFor = nil
			invNotify("")
		elseif table.find(profile.Loadout, "") then
			if invCall(Remote.EquipUnit, u.Id, nil) then invNotify(string.upper(u.Name) .. " equipped", GREEN) end
		else
			pickingSlotFor = u.Id
			invNotify("Loadout full: click the slot to replace", GOLD)
		end
		refreshInventory()
	end)

	local function feed(amount)
		local u = profile and selectedInvUid and profile.Units[selectedInvUid]
		if not u then return end
		local ok, used, gained = invCall(Remote.FeedUnit, u.Id, amount)
		if ok then
			invNotify(("Fed %d Wisp Essence%s"):format(used, (gained or 0) > 0 and ("  -  LEVEL UP! (+" .. gained .. ")") or ""), GREEN)
		end
	end
	feed1Button.MouseButton1Click:Connect(function() feed(1) end)
	feed10Button.MouseButton1Click:Connect(function() feed(10) end)

	lockButton.MouseButton1Click:Connect(function()
		local u = profile and selectedInvUid and profile.Units[selectedInvUid]
		if u then invCall(Remote.LockUnit, u.Id, not u.Locked) end
	end)

	-- selling needs a second click within 3 seconds
	sellButtonInv.MouseButton1Click:Connect(function()
		local u = profile and selectedInvUid and profile.Units[selectedInvUid]
		if not u then return end
		if u.Locked or loadoutSlotOf(u.Id) then
			invNotify(u.Locked and "Unlock this unit first" or "Unequip this unit first", RED)
			return
		end
		if os.clock() < sellConfirmUntil then
			sellConfirmUntil = 0
			local ok, gold = invCall(Remote.SellUnits, { u.Id })
			if ok then invNotify(("Sold %s for %d Gold"):format(string.upper(u.Name), gold), Config.GoldColor) end
		else
			sellConfirmUntil = os.clock() + 3
			refreshDetail()
			task.delay(3.05, function()
				if inventoryDim.Visible then refreshDetail() end
			end)
		end
	end)

	sortButton.MouseButton1Click:Connect(function()
		local i = table.find(SORT_MODES, sortMode) or 1
		sortMode = SORT_MODES[i % #SORT_MODES + 1]
		refreshInventory()
	end)
	filterButton.MouseButton1Click:Connect(function()
		local modes = { "All" }
		for _, r in ipairs(Config.RarityOrder) do table.insert(modes, r) end
		local i = table.find(modes, filterMode) or 1
		filterMode = modes[i % #modes + 1]
		refreshInventory()
	end)

	local function openInventory()
		invNotify("")
		pickingSlotFor = nil
		inventoryDim.Visible = true
		fitInventory()
		refreshInventory()
	end
	local function closeInventory()
		inventoryDim.Visible = false
		pickingSlotFor = nil
	end
	inventoryButton.MouseButton1Click:Connect(openInventory)
	inventoryClose.MouseButton1Click:Connect(closeInventory)
	unitsTab.MouseButton1Click:Connect(function() inventoryTab = "Units"; refreshInventory() end)
	materialsTab.MouseButton1Click:Connect(function() inventoryTab = "Materials"; refreshInventory() end)


	return inventoryDim, refreshInventory, closeInventory
end
local inventoryDim, refreshInventory, closeInventory = buildInventory()

-- PLAY: mode > map > stage > lobby (PlayMenu module next to this script)
-- UI helpers shared with the menu modules next to this script (BannerMenu, PlayMenu)
local uiKit = {
	Config = Config, Remote = Remote, player = player, popupGui = popupGui, PixelArt = PixelArt,
	make = make, label = label, pixelButton = pixelButton, pixelPanel = pixelPanel,
	setButtonColor = setButtonColor, fmt = fmt,
	colors = {
		PANEL = PANEL, PANEL_LIGHT = PANEL_LIGHT, PANEL_EDGE = PANEL_EDGE, GOLD = GOLD, RED = RED, GREEN = GREEN,
		WHITE = WHITE, BLACK = BLACK, TEXT_DIM = TEXT_DIM, BTN = BTN, GREY_BTN = GREY_BTN,
		GREEN_BTN = GREEN_BTN, GREEN_EDGE = GREEN_EDGE, RED_BTN = RED_BTN, RED_EDGE = RED_EDGE, rgb = rgb,
	},
}
waitingFor = "the BannerMenu module"
local bannerMenu = require(script.Parent:WaitForChild("BannerMenu")).init(uiKit) -- the SUMMON screen
summonMenuButton.MouseButton1Click:Connect(function()
	bannerMenu.open()
end)

waitingFor = "the PlayMenu module"
local playMenu = require(script.Parent:WaitForChild("PlayMenu")).init(uiKit)

waitingFor = "loading the UI"

-- saved data from the server
local function applyProfile(p)
	profile = p
	if alwaysHealthBars ~= p.Settings.AlwaysHealthBars then
		alwaysHealthBars = p.Settings.AlwaysHealthBars
		WorldView.setAlwaysHealthBars(alwaysHealthBars)
		refreshHealthBarsButton()
	end
	menuCurrency.Text = ('<font color="#78DCFF">GEMS %s</font>   <font color="#FFC43C">GOLD %s</font>'):format(fmt(p.Gems or 0), fmt(p.Gold or 0))
	playMenu.setProfile(p)
	bannerMenu.setProfile(p)
	rebuildShop()
	if inventoryDim.Visible then refreshInventory() end
end
Remote.ProfileUpdated.OnClientEvent:Connect(applyProfile)
task.spawn(function()
	local p = Remote.GetProfile:InvokeServer()
	if p then applyProfile(p) end
end)

Remote.StageRewards.OnClientEvent:Connect(function(rewards)
	lastRewards = rewards
	if overlay.Visible then rewardsLabel.Text = rewardsText(rewards) end
end)

-- Match place: there is no main menu. Until the stage starts, show a waiting screen.
local function buildWaitingScreen()
	local gui = make("ScreenGui", { Name = "TDWaitingGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 3, Enabled = false }, playerGui)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = rgb(20, 22, 34), BorderSizePixel = 0 }, gui)
	label(back, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(700, 60),
		Text = "GETTING READY...", TextSize = 40, TextColor3 = GOLD,
	})
	label(back, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(700, 30),
		Text = "Waiting for the rest of your lobby", TextSize = 20, TextColor3 = TEXT_DIM,
	})
	return gui
end
local waitingGui = buildWaitingScreen()

local function refreshState()
	local state = currentState()
	menuGui.Enabled = state == "Menu" and not IS_MATCH_PLACE
	waitingGui.Enabled = state == "Menu" and IS_MATCH_PLACE
	hudGui.Enabled = state ~= "Menu"
	if state ~= "Menu" then closeInventory() end
	playMenu.onState(state)
	if state ~= "Menu" then bannerMenu.close() end
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
for _, attr in ipairs({ "Lives", "Round", "TotalRounds", "Countdown", "GameSpeed", "Phase", "PrepLeft", "EndReason", "WaveState", "WaveSpawned", "WaveCount",
	"Voters", "SkipVotes", "SurrenderVotes" }) do
	workspace:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
for _, attr in ipairs({ "Money", "InMatch", "VoteAutoSkip", "VoteSkip", "VoteSurrender" }) do
	player:GetAttributeChangedSignal(attr):Connect(refreshHud)
end

-- host-only buttons (start, start match, speed, retry, menu); auto skip, skip and surrender are votes
local function refreshHostButtons()
	local host = isHost()
	retryButton.Text = host and "RETRY" or "WAITING..."
	setButtonColor(retryButton, host and GREEN_BTN or GREY_BTN)
	if IS_MATCH_PLACE then
		menuButton.Text = "BACK TO LOBBY" -- anyone can leave once the stage is over
	else
		menuButton.Text = host and "MAIN MENU" or "HOST DECIDES"
	end
	startMatchButton.Text = host and "START MATCH" or "HOST STARTS"
	setButtonColor(startMatchButton, host and GREEN_BTN or GREY_BTN)
end
workspace:GetAttributeChangedSignal("HostId"):Connect(function()
	refreshHostButtons()
	refreshHud()
end)
refreshHostButtons()

playButton.MouseButton1Click:Connect(function()
	playMenu.open()
end)
retryButton.MouseButton1Click:Connect(function()
	if isHost() then Remote.Retry:FireServer() end
end)
menuButton.MouseButton1Click:Connect(function()
	if IS_MATCH_PLACE or isHost() then Remote.ReturnToMenu:FireServer() end
end)
-- speed: the host sets it. auto skip: change MY choice (the match goes with the majority)
speedButton.MouseButton1Click:Connect(function()
	if not isHost() then notify(HOST_ONLY) return end
	local speed = workspace:GetAttribute("GameSpeed") or 1
	local options = Config.SpeedOptions
	local idx = table.find(options, speed) or 1
	Remote.SetSpeed:FireServer(options[idx % #options + 1])
end)
autoSkipButton.MouseButton1Click:Connect(function()
	Remote.SetAutoSkip:FireServer(not player:GetAttribute("VoteAutoSkip"))
end)
skipWaveButton.MouseButton1Click:Connect(function()
	Remote.SkipWave:FireServer()
end)
startMatchButton.MouseButton1Click:Connect(function()
	if not isHost() then notify(HOST_ONLY) return end
	Remote.BeginMatch:FireServer()
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
-- a right-click that did not drag the map cancels placing / closes the refine panel
UserInputService.InputEnded:Connect(function(input)
	if not isPanButton(input.UserInputType) then return end
	local wasDrag = mapDrag and mapDrag.Moved
	mapDrag = nil
	if not wasDrag and input.UserInputType == Enum.UserInputType.MouseButton2 and currentState() == "Playing" then
		selectUnit(nil)
		deselectTower()
	end
end)

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
				return Remote.PlaceTower:InvokeServer(selectedUid, pos)
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
	elseif not processed and input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Q then
			selectUnit(nil)
			deselectTower()
		elseif input.KeyCode == Enum.KeyCode.C then
			WorldView.centerView()
		elseif input.KeyCode == Enum.KeyCode.U then
			tryUpgrade()
		else
			-- 1-6 pick the unit in that loadout slot ([number] on the shop card)
			local slot = table.find(UNIT_KEYS, input.KeyCode)
			if slot then selectUnit(slot) end
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
-- fully loaded: no "didn't finish loading" message
waitingFor = nil
if startupGui then startupGui:Destroy() end
