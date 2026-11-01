-- WorldView: draws the whole game world as 2D pixel art on a GUI layer:
-- the map (grass, path, trees), enemies, units, shots, effects, the placement preview.
-- The server keeps simple invisible parts for the game logic; this module only draws them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local PixelArt = require(ReplicatedStorage:WaitForChild("PixelArt"))

local WorldView = {}

local PXS = 0.5 -- studs per art pixel
local rect = PixelArt.rect

local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local GRASS = rgb(98, 172, 70)
local GRASS_DARK = rgb(84, 154, 62)
local GRASS_LIGHT = rgb(132, 200, 96)
local DIRT = rgb(168, 128, 82)
local DIRT_EDGE = rgb(92, 64, 42)
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BURN_FX = rgb(255, 150, 60)
local SLOW_FX = rgb(110, 210, 255)

-- state
local rootFrame, mapScaler, entityScaler
local S = 4 -- screen pixels per art pixel
-- the zoom steps S can take. The map starts at the biggest whole step that fits; the steps below 2
-- let small screens (phones) zoom out to see the whole map
local ZOOM_LEVELS = { 1, 1.5, 2, 3, 4, 5, 6, 7, 8 }
local MAX_ZOOM_IN = 3 -- steps above the starting zoom
local baseZoom = 3 -- index in ZOOM_LEVELS of the starting zoom (set by layout)
local zoomDelta = 0
local originX, originY = 0, 0
-- camera pan, in art pixels (so zooming keeps the same spot in view); clamped to the map
local panX, panZ = 0, 0
local PAN_LIMIT_X, PAN_LIMIT_Z = 170, 80
local rightInset = 200
local topInset, bottomInset = 176, 156 -- screen space kept free for the HUD plates / prep panel
local started = false
local alwaysBars = false -- show every enemy's health bar (otherwise only the one under the mouse)
local TAP_BAR_SECONDS = 3 -- touch screens: how long a tapped enemy keeps its health bar
local enemies, towers, effects = {}, {}, {}
local summons = {} -- [Part] = vis: puppets walking the path (Summoner units, workspace.Summons)
local connections = {}
local ghost, selected
-- the castle at the end of the path: where buildMap drew it (art pixels: x0, z0, x1, z1) and the
-- base's health bar over it (always shown)
local castle = nil

local function track(conn)
	table.insert(connections, conn)
	return conn
end

-- A Frame at (x, y) with a UIScale inside, so everything inside is measured in art pixels
local function makeLayer(parent, name)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(0, 0)
	holder.Parent = parent
	local scaler = Instance.new("Frame")
	scaler.Name = "Scaler"
	scaler.BackgroundTransparency = 1
	scaler.BorderSizePixel = 0
	scaler.Size = UDim2.fromOffset(0, 0)
	scaler.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Parent = scaler
	return holder, scaler, scale
end

local mapHolder, entityHolder, mapScale, entityScale

local function layout()
	local size = rootFrame.AbsoluteSize
	if size.X < 10 then return end
	-- The map (about 340 x 140 art pixels incl. the cave and castle) must fit between the
	-- HUD at the top, the shop on the right and the prep panel at the bottom.
	local freeW = size.X - rightInset
	local availW = freeW - 40
	local availH = size.Y - topInset - bottomInset
	local base = math.clamp(math.min(math.floor(availW / 340), math.floor(availH / 140)), 2, 8)
	baseZoom = table.find(ZOOM_LEVELS, base)
	S = ZOOM_LEVELS[math.clamp(baseZoom + zoomDelta, 1, #ZOOM_LEVELS)]
	originX = freeW / 2 + panX * S
	originY = topInset + availH / 2 + panZ * S
	mapHolder.Position = UDim2.fromOffset(originX, originY)
	entityHolder.Position = UDim2.fromOffset(originX, originY)
	mapScale.Scale = S
	entityScale.Scale = S
end

-- ===================== MAP =====================
local function buildMap()
	local rng = Random.new(1337)
	local map = mapScaler
	local path = Config.GetPath()

	-- grass base
	rect(map, -900, -650, 1800, 1300, GRASS)

	local function nearPath(x, z, extra)
		return Config.DistanceToPath(Vector3.new(x, 0, z)) < Config.PathWidth / 2 + extra
	end

	-- grass details: darker patches, light tufts, little flowers
	local flowerColors = { WHITE, rgb(255, 232, 110), rgb(255, 150, 190) }
	for _ = 1, 950 do
		local ax = rng:NextInteger(-330, 330)
		local az = rng:NextInteger(-225, 225)
		if not nearPath(ax * PXS, az * PXS, 1.8) then
			local kind = rng:NextNumber()
			if kind < 0.38 then
				rect(map, ax, az, 4, 2, GRASS_DARK)
			elseif kind < 0.78 then
				rect(map, ax, az, 2, 1, GRASS_LIGHT)
				rect(map, ax, az - 1, 1, 1, GRASS_LIGHT)
			else
				rect(map, ax, az, 1, 1, flowerColors[rng:NextInteger(1, #flowerColors)])
			end
		end
	end

	-- the path: dark edge first, then the dirt on top
	local half = Config.PathWidth / PXS / 2
	local rects = {}
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local ax, az, bx, bz = a.X / PXS, a.Z / PXS, b.X / PXS, b.Z / PXS
		table.insert(rects, {
			x0 = math.floor(math.min(ax, bx) - half),
			x1 = math.ceil(math.max(ax, bx) + half),
			z0 = math.floor(math.min(az, bz) - half),
			z1 = math.ceil(math.max(az, bz) + half),
		})
	end
	for _, r in ipairs(rects) do
		rect(map, r.x0 - 2, r.z0 - 2, r.x1 - r.x0 + 4, r.z1 - r.z0 + 4, DIRT_EDGE)
	end
	for _, r in ipairs(rects) do
		rect(map, r.x0, r.z0, r.x1 - r.x0, r.z1 - r.z0, DIRT)
	end
	-- pebbles and cracks on the path
	local pebble = { rgb(194, 156, 108), rgb(140, 102, 64), rgb(158, 154, 148) }
	for _, r in ipairs(rects) do
		local count = math.floor((r.x1 - r.x0) * (r.z1 - r.z0) / 70)
		for _ = 1, count do
			local px = rng:NextInteger(r.x0 + 1, r.x1 - 3)
			local pz = rng:NextInteger(r.z0 + 1, r.z1 - 2)
			rect(map, px, pz, rng:NextInteger(1, 2), 1, pebble[rng:NextInteger(1, #pebble)])
		end
	end

	-- start: a cave entrance. end: a little castle.
	local first, last = path[1], path[#path]
	if first then
		local cx = math.floor((first.X - Config.PathWidth / 2) / PXS)
		local cz = math.floor(first.Z / PXS)
		rect(map, cx - 12, cz - 14, 14, 28, rgb(88, 84, 96))
		rect(map, cx - 12, cz - 14, 14, 3, rgb(124, 120, 132))
		rect(map, cx - 6, cz - 11, 8, 22, rgb(26, 22, 32))
		rect(map, cx - 4, cz - 8, 4, 2, rgb(80, 220, 110))
		rect(map, cx - 4, cz + 6, 4, 2, rgb(80, 220, 110))
	end
	if last then
		local cx = math.floor((last.X + Config.PathWidth / 2) / PXS)
		local cz = math.floor(last.Z / PXS)
		rect(map, cx - 2, cz - 13, 18, 26, rgb(150, 150, 164))
		rect(map, cx - 2, cz - 13, 18, 3, rgb(190, 190, 204))
		for i = 0, 3 do rect(map, cx - 2 + i * 5, cz - 16, 3, 3, rgb(150, 150, 164)) end
		rect(map, cx + 2, cz - 3, 10, 14, rgb(110, 58, 40))
		rect(map, cx + 4, cz - 1, 6, 12, rgb(70, 36, 28))
		rect(map, cx + 6, cz - 24, 1, 8, rgb(70, 60, 60))
		rect(map, cx + 7, cz - 24, 7, 4, rgb(214, 56, 60))
		castle = { x0 = cx - 2, z0 = cz - 24, x1 = cx + 16, z1 = cz + 13 }
	end

	-- pine trees around the edges (back to front so lower ones draw on top)
	local trees = {}
	for _ = 1, 62 do
		local x, z
		if rng:NextNumber() < 0.5 then
			x = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(86, 150)
			z = rng:NextNumber(-100, 100)
		else
			x = rng:NextNumber(-150, 150)
			z = (rng:NextNumber() < 0.5 and -1 or 1) * rng:NextNumber(56, 100)
			if z < 0 then z = math.min(z, -52) end
		end
		table.insert(trees, { x = x, z = z, alt = rng:NextNumber() < 0.4 })
	end
	table.sort(trees, function(a, b) return a.z < b.z end)
	for _, t in ipairs(trees) do
		local tone = t.alt and { mid = rgb(48, 116, 70), light = rgb(76, 148, 92), dark = rgb(30, 86, 54) } or nil
		local ax, az = math.floor(t.x / PXS), math.floor(t.z / PXS)
		rect(map, ax - 6, az - 2, 12, 3, rgb(60, 124, 54), 0.55)
		local tree = PixelArt.pine(tone)
		tree.Position = UDim2.fromOffset(ax - 7, az - 24)
		tree.Parent = map
	end
end

-- ===================== EFFECTS =====================
local function addEffect(e)
	e.t0 = os.clock()
	table.insert(effects, e)
end

local function burst(x, z, color, count)
	for i = 1, count do
		local f = rect(entityScaler, math.floor(x / PXS), math.floor(z / PXS), 2, 2, (i % 2 == 0) and color or WHITE)
		f.ZIndex = 4200
		local ang = math.random() * math.pi * 2
		local speed = 16 + math.random() * 22
		addEffect({ kind = "part", frame = f, x = x / PXS, z = z / PXS, vx = math.cos(ang) * speed, vz = math.sin(ang) * speed - 14, life = 0.35 })
	end
end

local function spawnShot(x0, z0, x1, z1, color, target, life)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(3, 3)
	f.Position = UDim2.fromOffset(math.floor(x0 / PXS) - 1, math.floor(z0 / PXS) - 1)
	f.ZIndex = 4000
	f.Parent = entityScaler
	rect(f, 0, 0, 3, 3, color)
	rect(f, 1, 1, 1, 1, WHITE)
	addEffect({ kind = "shot", frame = f, x0 = x0 / PXS, z0 = z0 / PXS, x1 = x1 / PXS, z1 = z1 / PXS, target = target, life = life or 0.11 })
end

-- A fading effect frame (art pixels). grow = { From = Vector2, To = Vector2 } changes its size;
-- delay = seconds before it appears (e.g. when the shot lands).
local function addFx(frame, life, grow, delay)
	frame.ZIndex = 3900
	frame.Visible = not delay
	frame.Parent = entityScaler
	addEffect({ kind = "fx", frame = frame, life = life + (delay or 0), delay = delay or 0, grow = grow,
		base = frame.BackgroundTransparency, stroke = frame:FindFirstChildOfClass("UIStroke") })
end

-- a ring (circle outline) centred on (x, z) world studs, growing to `radius` studs
local function ringFx(x, z, radius, color, life, delay)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x / PXS, z / PXS)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.8
	f.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Parent = f
	local d = radius * 2 / PXS
	addFx(f, life, { From = Vector2.new(d * 0.2, d * 0.2), To = Vector2.new(d, d) }, delay)
end

-- a straight beam from (x0, z0) to (x1, z1) world studs, `width` studs wide
local function beamFx(x0, z0, x1, z1, width, color, life)
	local dx, dz = (x1 - x0) / PXS, (z1 - z0) / PXS
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((x0 + x1) / 2 / PXS, (z0 + z1) / 2 / PXS)
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dz * dz), math.max(1, width / PXS))
	f.Rotation = math.deg(math.atan2(dz, dx))
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	addFx(f, life)
end

-- what an area attack looks like (shape = { K, R, W, A, L } from the server)
local function attackFx(fromX, fromZ, toX, toZ, shape, color)
	if shape.K == "Splash" then
		ringFx(toX, toZ, shape.R or 6, color, 0.3, Config.ShotTravel)
	elseif shape.K == "Line" then
		local dx, dz = toX - fromX, toZ - fromZ
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.01 then return end
		local reach = (shape.L or len) + 2
		beamFx(fromX, fromZ, fromX + dx / len * reach, fromZ + dz / len * reach, (shape.W or 4) * 0.6, color, 0.22)
		beamFx(fromX, fromZ, fromX + dx / len * reach, fromZ + dz / len * reach, 0.5, WHITE, 0.12)
	elseif shape.K == "Cone" then
		local base = math.atan2(toZ - fromZ, toX - fromX)
		local half = math.rad((shape.A or 60) / 2)
		local reach = shape.L or 20
		for i = 0, 4 do
			local ang = base - half + (2 * half) * i / 4
			beamFx(fromX, fromZ, fromX + math.cos(ang) * reach, fromZ + math.sin(ang) * reach, 0.6, color, 0.2)
		end
	elseif shape.K == "Circle" then
		ringFx(fromX, fromZ, shape.R or shape.L or 20, color, 0.35)
	end
end

-- ===================== ENEMIES =====================
local function tierColor(tier)
	return Config.Tiers[math.clamp(tier, 1, Config.MaxTier)].Color
end

local function buildEnemySprite(vis)
	if vis.sprite then vis.sprite:Destroy() end
	if vis.boss then
		-- a zero-size holder at the feet with a UIScale, so the wisp grows upward from the ground
		local holder = Instance.new("Frame")
		holder.Name = "BossSprite"
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.fromOffset(0, 0)
		holder.Position = UDim2.fromOffset(6, 12)
		local scale = Instance.new("UIScale")
		scale.Scale = Config.Boss.Scale
		scale.Parent = holder
		rect(holder, -5, -2, 10, 2, BLACK, 0.6) -- shadow
		local sprite = PixelArt.sprite("Wisp", { tier = 99, color = Config.Boss.Color })
		sprite.Position = UDim2.fromOffset(-6, -12)
		sprite.Parent = holder
		vis.sprite = holder
	else
		vis.sprite = PixelArt.sprite(vis.spriteName, { tier = vis.tier, color = tierColor(vis.tier) })
	end
	vis.sprite.Parent = vis.container
end

-- Health bar: the enemy's name on top, then a red bar with "current/max" written inside it
local BAR_FILL, BAR_BACK = rgb(214, 38, 38), rgb(84, 12, 16)
local SHIELD_COLOR = rgb(110, 200, 255)

local function shortNumber(n)
	n = math.floor(n + 0.5)
	if n >= 1000000 then return (("%.1f"):format(n / 1000000):gsub("%.0$", "")) .. "M" end
	if n >= 1000 then return (("%.1f"):format(n / 1000):gsub("%.0$", "")) .. "K" end
	return tostring(n)
end

local function barText(parent, x, y, w, h, text, size)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.Font = Enum.Font.Arcade
	t.Text = text
	t.TextSize = size
	t.TextColor3 = WHITE
	t.TextStrokeTransparency = 0
	t.TextStrokeColor3 = BLACK
	t.Parent = parent
	return t
end

local function buildBar(vis, container)
	local boss = vis.boss
	local bw, bh, nameH, textSize = 32, 8, 8, 6
	if boss then bw, bh, nameH, textSize = 52, 11, 10, 8 end
	local top
	if boss then
		top = math.floor(12 - 12 * Config.Boss.Scale) - bh - nameH - 2
	else
		top = -bh - nameH - 1
	end
	local root = Instance.new("Frame")
	root.Name = "HealthBar"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Position = UDim2.fromOffset((boss and 6 or vis.w / 2) - bw / 2, top)
	root.Size = UDim2.fromOffset(bw, nameH + bh)
	root.Visible = false
	root.Parent = container
	barText(root, 0, 0, bw, nameH, boss and Config.Boss.Name or vis.typeName, textSize)
	rect(root, 0, nameH, bw, bh, BLACK)
	rect(root, 1, nameH + 1, bw - 2, bh - 2, BAR_BACK)
	vis.barFill = rect(root, 1, nameH + 1, bw - 2, bh - 2, BAR_FILL)
	if vis.maxShield then
		-- Shielded: a blue strip over the bar while the shield holds
		vis.shieldFill = rect(root, 1, nameH + 1, bw - 2, 2, SHIELD_COLOR)
	end
	vis.hpLabel = barText(root, 0, nameH, bw, bh, "", textSize)
	vis.barMax = bw - 2
	vis.barH = bh - 2
	vis.barRoot = root
end

local function updateBar(vis)
	if not vis.barFill then return end
	local maxHp = math.max(1, vis.part:GetAttribute("MaxHealth") or vis.tier)
	local hp = math.clamp(vis.part:GetAttribute("Health") or vis.part:GetAttribute("Tier") or maxHp, 0, maxHp)
	vis.barFill.Size = UDim2.fromOffset(math.max(hp > 0 and 1 or 0, math.floor(vis.barMax * hp / maxHp + 0.5)), vis.barH)
	-- health can be fractional (it scales with the round): show it rounded up, so 0.4 HP reads "1"
	vis.hpLabel.Text = shortNumber(math.ceil(hp - 1e-6)) .. "/" .. shortNumber(math.ceil(maxHp - 1e-6))
	if vis.shieldFill then
		local shield = math.max(0, vis.part:GetAttribute("Shield") or 0)
		vis.shieldFill.Size = UDim2.fromOffset(math.floor(vis.barMax * shield / vis.maxShield + 0.5), 2)
		vis.shieldFill.Visible = shield > 0
	end
end

-- the base's health bar ("BASE" + lives left), above the castle on the entity layer
local function buildCastleBar()
	if not castle then return end
	local bw, bh, nameH, textSize = 44, 10, 9, 7
	local root = Instance.new("Frame")
	root.Name = "BaseHealthBar"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Position = UDim2.fromOffset(math.floor((castle.x0 + castle.x1 - bw) / 2), castle.z0 - bh - nameH - 2)
	root.Size = UDim2.fromOffset(bw, nameH + bh)
	root.ZIndex = 2900 -- over the enemies and units, under the placement preview
	root.Parent = entityScaler
	barText(root, 0, 0, bw, nameH, "BASE", textSize)
	rect(root, 0, nameH, bw, bh, BLACK)
	rect(root, 1, nameH + 1, bw - 2, bh - 2, BAR_BACK)
	castle.fill = rect(root, 1, nameH + 1, bw - 2, bh - 2, BAR_FILL)
	castle.label = barText(root, 0, nameH, bw, bh, "", textSize)
	castle.barMax, castle.barH = bw - 2, bh - 2
	castle.root = root
end

-- green, then yellow below half, red below a quarter (like the old HUD lives bar)
local function updateCastleBar()
	local lives = math.max(0, workspace:GetAttribute("Lives") or 0)
	if castle.lives == lives then return end
	castle.lives = lives
	local frac = math.clamp(lives / Config.StartLives, 0, 1)
	castle.fill.Size = UDim2.fromOffset(math.floor(castle.barMax * frac + 0.5), castle.barH)
	castle.fill.BackgroundColor3 = (frac > 0.5) and rgb(84, 204, 84) or ((frac > 0.25) and rgb(230, 190, 60) or rgb(224, 70, 70))
	castle.label.Text = shortNumber(lives) .. "/" .. shortNumber(Config.StartLives)
end

local function removeEnemy(part)
	local vis = enemies[part]
	if not vis then return end
	enemies[part] = nil
	for _, c in ipairs(vis.conns) do c:Disconnect() end
	if vis.container then vis.container:Destroy() end
	-- little pop effect, unless it just reached the end of the path
	if (workspace:GetAttribute("State") or "") == "Playing" then
		local path = Config.GetPath()
		local last = path[#path]
		local leaked = last and (Vector2.new(vis.x, vis.z) - Vector2.new(last.X, last.Z)).Magnitude < 7
		if not leaked then
			if vis.boss then
				burst(vis.x, vis.z - 8, Config.Boss.Color, 40)
			else
				burst(vis.x, vis.z - 3, tierColor(vis.tier), 8)
			end
		end
	end
end

local function addEnemy(part)
	if enemies[part] or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) then return end
	local vis = { part = part, phase = math.random() * 6.28, conns = {}, tier = part:GetAttribute("Tier") or 1, boss = part:GetAttribute("Boss") == true }
	-- enemy type (Config.EnemyTypes): sprite, name, flying, shield
	local typeName = part:GetAttribute("Type") or "Wisp"
	local def = Config.EnemyTypes[typeName] or Config.EnemyTypes.Wisp
	vis.typeName = def.Name or typeName
	vis.spriteName = vis.boss and "Wisp" or (def.Sprite or "Wisp")
	vis.w, vis.h = PixelArt.size(vis.spriteName)
	if vis.boss then vis.w, vis.h = 12, 12 end
	vis.lift = part:GetAttribute("Flying") and 6 or 0 -- flyers float above their shadow
	vis.maxShield = part:GetAttribute("MaxShield")
	vis.ox, vis.oy = vis.w // 2, vis.h - 1 + vis.lift -- container offset from the feet point
	local container = Instance.new("Frame")
	container.Name = "Enemy"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromOffset(vis.w, vis.h + vis.lift)
	local p = part.Position
	local startX, startZ = math.floor(p.X / PXS + 0.5), math.floor(p.Z / PXS + 0.5)
	container.Position = UDim2.fromOffset(startX - vis.ox, startZ - vis.oy)
	container.ZIndex = 2000 + startZ
	container.Parent = entityScaler
	if not vis.boss then
		-- shadow on the ground (smaller under a flyer)
		local inset = vis.lift > 0 and 3 or 1
		rect(container, inset, vis.h - 2 + vis.lift, vis.w - 2 * inset, 2, BLACK, vis.lift > 0 and 0.75 or 0.6)
	end
	vis.container = container
	buildEnemySprite(vis)
	if vis.maxShield then
		-- Shielded: a bubble around it until the shield breaks
		local bubble = Instance.new("Frame")
		bubble.AnchorPoint = Vector2.new(0.5, 0.5)
		bubble.Position = UDim2.fromOffset(vis.w / 2, vis.h / 2)
		local d = math.max(vis.w, vis.h) + 4
		bubble.Size = UDim2.fromOffset(d, d)
		bubble.BackgroundColor3 = SHIELD_COLOR
		bubble.BackgroundTransparency = 0.82
		bubble.BorderSizePixel = 0
		bubble.ZIndex = 3
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = bubble
		local stroke = Instance.new("UIStroke")
		stroke.Color = SHIELD_COLOR
		stroke.Thickness = 1
		stroke.Transparency = 0.25
		stroke.Parent = bubble
		bubble.Parent = container
		vis.bubble = bubble
		table.insert(vis.conns, part:GetAttributeChangedSignal("Shield"):Connect(function()
			updateBar(vis)
			if (part:GetAttribute("Shield") or 0) <= 0 and vis.bubble then
				vis.bubble:Destroy()
				vis.bubble = nil
				burst(vis.x, vis.z - 4, SHIELD_COLOR, 8) -- the shield breaks
			end
		end))
	end
	-- health bar above the enemy; only shown while hovered (or always, if the setting is on)
	buildBar(vis, container)
	vis.barShown = false
	updateBar(vis)
	table.insert(vis.conns, part:GetAttributeChangedSignal("Health"):Connect(function()
		updateBar(vis)
		if vis.boss then burst(vis.x, vis.z - 6, Config.Boss.Color, 3) end
	end))
	vis.x, vis.z = p.X, p.Z
	enemies[part] = vis

	table.insert(vis.conns, part:GetAttributeChangedSignal("Tier"):Connect(function()
		local newTier = part:GetAttribute("Tier") or 1
		if newTier ~= vis.tier then
			burst(vis.x, vis.z - 3, tierColor(vis.tier), 4)
			vis.tier = newTier
			buildEnemySprite(vis)
		end
	end))
	table.insert(vis.conns, part.AncestryChanged:Connect(function(_, parent)
		if not parent then removeEnemy(part) end
	end))
end

-- ===================== UNITS =====================
local function updateTowerLevel(vis)
	local level = vis.model:GetAttribute("Level") or 1
	vis.level = level
	local isMax = level >= Config.MaxLevel(vis.unit)
	vis.label.Text = isMax and "MAX" or ("UP" .. level) -- in-match upgrade level
	vis.label.TextColor3 = isMax and rgb(255, 214, 84) or WHITE
end

local function removeTower(model)
	local vis = towers[model]
	if not vis then return end
	towers[model] = nil
	for _, c in ipairs(vis.conns) do c:Disconnect() end
	if vis.container then vis.container:Destroy() end
	if selected and selected.model == model then WorldView.setSelected(nil) end
end

local function addTower(model)
	if towers[model] or not model:IsA("Model") or not model:IsDescendantOf(workspace) then return end
	local unit = model:GetAttribute("UnitName")
	if not unit or not Config.Units[unit] then return end
	local w, h = PixelArt.size(unit)
	local vis = { model = model, unit = unit, conns = {}, phase = math.random() * 6.28, recoilAt = -10, w = w, h = h }
	local container = Instance.new("Frame")
	container.Name = unit
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromOffset(w, h)
	container.Visible = false -- shown after the first update has put it in the right place
	container.Parent = entityScaler
	rect(container, 2, h - 2, w - 4, 2, BLACK, 0.6) -- shadow
	-- one holder per facing: the owner's colour outline behind the sprite (see Config.PlayerColors)
	local owner = Players:GetPlayerByUserId(model:GetAttribute("OwnerId") or 0)
	local colorIndex = owner and owner:GetAttribute("PlayerColor")
	local outlineColor = colorIndex and Config.PlayerColors[colorIndex]
	local function facing(flip)
		local holder = Instance.new("Frame")
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Size = UDim2.fromOffset(w, h)
		if outlineColor then
			local outline = PixelArt.outline(unit, outlineColor, flip)
			outline.ZIndex = 1
			outline.Parent = holder
		end
		local sprite = PixelArt.sprite(unit, { flip = flip })
		sprite.ZIndex = 2
		sprite.Parent = holder
		holder.Parent = container
		return holder
	end
	vis.right = facing(false)
	vis.left = facing(true)
	vis.left.Visible = false
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(w + 10, 7)
	label.Position = UDim2.fromOffset(-5, -8)
	label.Font = Enum.Font.Arcade
	label.TextSize = 6
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = rgb(20, 16, 30)
	label.Text = ""
	label.Parent = container
	vis.label = label
	vis.container = container
	vis.root = model:FindFirstChild("Root") or model.PrimaryPart
	towers[model] = vis
	updateTowerLevel(vis)

	table.insert(vis.conns, model:GetAttributeChangedSignal("Level"):Connect(function() updateTowerLevel(vis) end))
	table.insert(vis.conns, model.AncestryChanged:Connect(function(_, parent)
		if not parent then removeTower(model) end
	end))
	table.insert(vis.conns, model.ChildAdded:Connect(function(child)
		if child.Name == "Root" then vis.root = child end
	end))
end

-- ===================== SUMMONS =====================
-- A summon (Puppet Ninja's puppet) walks from the castle back along the path. It always shows a
-- green health bar: its HP is what it can still deal.
local SUMMON_FILL, SUMMON_BACK = rgb(70, 200, 80), rgb(16, 64, 24)
local function removeSummon(part)
	local vis = summons[part]
	if not vis then return end
	summons[part] = nil
	for _, c in ipairs(vis.conns) do c:Disconnect() end
	vis.container:Destroy()
	burst(vis.x, vis.z - 3, rgb(230, 230, 240), 6)
end

local function addSummon(part)
	if summons[part] or not part:IsA("BasePart") then return end
	local spriteName = part:GetAttribute("Sprite") or "Wisp"
	local w, h = PixelArt.size(spriteName)
	local vis = { part = part, conns = {}, w = w, h = h, x = part.Position.X, z = part.Position.Z, phase = math.random() * 6.28 }
	local container = Instance.new("Frame")
	container.Name = "Summon"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromOffset(w, h)
	container.Visible = false -- shown after the first update has put it in the right place
	container.Parent = entityScaler
	rect(container, 1, h - 2, w - 2, 2, BLACK, 0.6) -- shadow
	vis.right = PixelArt.sprite(spriteName, { flip = false })
	vis.left = PixelArt.sprite(spriteName, { flip = true })
	vis.right.Parent, vis.left.Parent = container, container
	vis.right.Visible = false
	-- health bar: like an enemy's (name, bar, "hp/max"), but green and always shown
	local bw, bh, nameH, textSize = 32, 8, 8, 6
	local bar = Instance.new("Frame")
	bar.Name = "HealthBar"
	bar.BackgroundTransparency = 1
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(math.floor((w - bw) / 2), -bh - nameH - 1)
	bar.Size = UDim2.fromOffset(bw, nameH + bh)
	bar.Parent = container
	barText(bar, 0, 0, bw, nameH, part:GetAttribute("Name") or "", textSize)
	rect(bar, 0, nameH, bw, bh, BLACK)
	rect(bar, 1, nameH + 1, bw - 2, bh - 2, SUMMON_BACK)
	vis.fill = rect(bar, 1, nameH + 1, bw - 2, bh - 2, SUMMON_FILL)
	local hpLabel = barText(bar, 0, nameH, bw, bh, "", textSize)
	local function updateHealth()
		local maxHp = math.max(1e-6, part:GetAttribute("MaxHealth") or 1)
		local hp = math.clamp(part:GetAttribute("Health") or 0, 0, maxHp)
		vis.fill.Size = UDim2.fromOffset(math.max(hp > 0 and 1 or 0, math.floor((bw - 2) * hp / maxHp + 0.5)), bh - 2)
		hpLabel.Text = shortNumber(math.ceil(hp - 1e-6)) .. "/" .. shortNumber(math.ceil(maxHp - 1e-6))
	end
	updateHealth()
	vis.container = container
	summons[part] = vis
	table.insert(vis.conns, part:GetAttributeChangedSignal("Health"):Connect(updateHealth))
	table.insert(vis.conns, part.AncestryChanged:Connect(function(_, parent)
		if not parent then removeSummon(part) end
	end))
end

-- ===================== RINGS (range circles) =====================
local function makeRing(rangeStuds, color)
	local R = math.floor(rangeStuds / PXS + 0.5)
	local holder = Instance.new("Frame")
	holder.Name = "Ring"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(2 * R + 1, 2 * R + 1)
	holder.ZIndex = 1500
	holder.Visible = false -- shown once it has been positioned
	holder.Parent = entityScaler
	local parts = {}
	for dy = -R, R do
		local xo = math.floor(math.sqrt(R * R - dy * dy) + 0.5)
		local y = dy + R
		if math.abs(dy) <= R - 1 then
			local r2 = R - 1
			local xi = math.floor(math.sqrt(math.max(r2 * r2 - dy * dy, 0)) + 0.5)
			local ow = math.max(1, xo - xi)
			table.insert(parts, rect(holder, R - xo, y, ow, 1, color, 0.3))
			table.insert(parts, rect(holder, R + xo - ow + 1, y, ow, 1, color, 0.3))
			table.insert(parts, rect(holder, R - xi + 0, y, 2 * xi + 1, 1, color, 0.86))
		else
			table.insert(parts, rect(holder, R - xo, y, 2 * xo + 1, 1, color, 0.3))
		end
	end
	return { holder = holder, R = R, parts = parts }
end

local function recolorRing(ring, color)
	for _, p in ipairs(ring.parts) do p.BackgroundColor3 = color end
end

local function placeRing(ring, worldX, worldZ)
	local ax, az = math.floor(worldX / PXS + 0.5), math.floor(worldZ / PXS + 0.5)
	ring.holder.Position = UDim2.fromOffset(ax - ring.R, az - ring.R)
	ring.holder.Visible = true
end

-- ===================== AREA INDICATORS (attack shapes, Config.Units[...].Attack) =====================
-- Shown with the range ring while placing a unit and for the selected unit: what its attack covers.
--   Line   = a strip from the unit to the end of its range     Cone   = a wedge towards the target
--   Splash = a circle around the enemy it hits                 Circle = the whole range around it
-- Drawn as pixel rows (light fill, stronger edge). Line / Cone are built pointing right and turned
-- with Rotation, so they don't have to be rebuilt when the aim changes.
local AREA_FILL, AREA_EDGE = 0.8, 0.3

-- fills `holder` with the pixels where inside(x, y) is true, for x in [x0, x1], y in [y0, y1]
-- (holder-local position = (x - x0, y - y0)). Returns the created frames.
local function rasterize(holder, x0, y0, x1, y1, inside, color)
	local parts = {}
	local function edge(x, y)
		return not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1))
	end
	for y = y0, y1 do
		local x = x0
		while x <= x1 do
			if inside(x, y) then
				local s = x
				while x + 1 <= x1 and inside(x + 1, y) do x += 1 end
				table.insert(parts, rect(holder, s - x0, y - y0, x - s + 1, 1, color, AREA_FILL))
				-- the edge pixels of this run, as horizontal pieces
				local e = s
				while e <= x do
					if edge(e, y) then
						local es = e
						while e + 1 <= x and edge(e + 1, y) do e += 1 end
						table.insert(parts, rect(holder, es - x0, y - y0, e - es + 1, 1, color, AREA_EDGE))
					end
					e += 1
				end
			end
			x += 1
		end
	end
	return parts
end

local function newHolder(w, h)
	local holder = Instance.new("Frame")
	holder.Name = "Area"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(w, h)
	holder.ZIndex = 1490 -- under the range ring and the units
	holder.Visible = false
	holder.Parent = entityScaler
	return holder
end

-- Builds the indicator for an attack (nil for Single). rangeStuds = the unit's range.
local function makeArea(attack, rangeStuds, color)
	local kind = attack and attack.Kind or "Single"
	local area = { kind = kind }
	if kind == "Line" then
		local L = math.floor(rangeStuds / PXS + 0.5)
		local half = math.max(1, math.floor((attack.Width or 4) / PXS / 2 + 0.5))
		-- holder is 2L wide and centred on the unit, the strip fills its right half
		area.holder = newHolder(2 * L + 1, 2 * half + 1)
		area.parts = rasterize(area.holder, -L, -half, L, half, function(x, y)
			return x >= 0 and x <= L and y >= -half and y <= half
		end, color)
		area.rotates, area.at = true, "unit"
	elseif kind == "Cone" then
		local R = math.floor(rangeStuds / PXS + 0.5)
		local halfAngle = math.rad((attack.Angle or 60) / 2)
		area.holder = newHolder(2 * R + 1, 2 * R + 1)
		area.parts = rasterize(area.holder, -R, -R, R, R, function(x, y)
			return x * x + y * y <= R * R and (x > 0 or (x == 0 and y == 0)) and math.abs(math.atan2(y, x)) <= halfAngle
		end, color)
		area.rotates, area.at = true, "unit"
	elseif kind == "Splash" or kind == "Circle" then
		local r = math.floor((kind == "Splash" and (attack.Radius or 6) or (attack.Radius or rangeStuds)) / PXS + 0.5)
		area.holder = newHolder(2 * r + 1, 2 * r + 1)
		area.parts = rasterize(area.holder, -r, -r, r, r, function(x, y)
			return x * x + y * y <= r * r
		end, color)
		area.rotates, area.at = false, kind == "Splash" and "aim" or "unit"
	else
		return nil
	end
	area.range = rangeStuds
	return area
end

-- ux/uz = the unit, ax/az = where it aims (world studs)
local function placeArea(area, ux, uz, ax, az)
	if not area then return end
	local cx, cz = ux, uz
	if area.at == "aim" then cx, cz = ax, az end
	area.holder.Position = UDim2.fromOffset(math.floor(cx / PXS + 0.5), math.floor(cz / PXS + 0.5))
	if area.rotates then
		area.holder.Rotation = math.deg(math.atan2(az - uz, ax - ux))
	end
	area.holder.Visible = true
end

local function recolorArea(area, color)
	if not area then return end
	for _, part in ipairs(area.parts) do part.BackgroundColor3 = color end
end

local function destroyArea(area)
	if area then area.holder:Destroy() end
end

-- the point on the enemy path closest to (x, z): where a unit placed there will mostly shoot
local function nearestPathPoint(x, z)
	local path = Config.GetPath()
	local p = Vector2.new(x, z)
	local best, bestD = nil, math.huge
	for i = 1, #path - 1 do
		local a, b = Vector2.new(path[i].X, path[i].Z), Vector2.new(path[i + 1].X, path[i + 1].Z)
		local ab = b - a
		local t = ab:Dot(ab) > 0 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
		local q = a + ab * t
		local d = (q - p).Magnitude
		if d < bestD then best, bestD = q, d end
	end
	return best
end

-- an aim point for (ux, uz) towards (tx, tz), no further than `range`
local function aimWithin(ux, uz, tx, tz, range)
	local dx, dz = tx - ux, tz - uz
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= range or d < 1e-3 then return tx, tz end
	return ux + dx / d * range, uz + dz / d * range
end

-- ===================== PUBLIC: placement preview =====================
function WorldView.clearGhost()
	if ghost then
		ghost.container:Destroy()
		ghost.ring.holder:Destroy()
		destroyArea(ghost.area)
		ghost = nil
	end
end

-- unitLevel = account level of the copy being placed (its range grows with level)
function WorldView.setGhost(unitName, unitLevel)
	WorldView.clearGhost()
	if not unitName or not Config.Units[unitName] then return end
	local w, h = PixelArt.size(unitName)
	local container = Instance.new("Frame")
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromOffset(w, h)
	container.ZIndex = 3000
	container.Visible = false
	container.Parent = entityScaler
	local sprite = PixelArt.sprite(unitName)
	sprite.Parent = container
	local orig = {}
	for _, d in ipairs(sprite:GetDescendants()) do
		if d:IsA("Frame") then
			orig[d] = d.BackgroundColor3
			d.BackgroundTransparency = 0.3
		end
	end
	-- units drawn from an uploaded image: fade / tint the image itself
	local image = sprite:IsA("ImageLabel") and sprite or nil
	if image then image.ImageTransparency = 0.3 end
	ghost = {
		container = container,
		image = image,
		ring = makeRing(Config.ScaledStats(unitName, 1, unitLevel).Range, WHITE),
		area = makeArea(Config.AttackOf(unitName, 1), Config.ScaledStats(unitName, 1, unitLevel).Range, WHITE),
		orig = orig,
		w = w,
		h = h,
		valid = nil,
	}
end

function WorldView.updateGhost(worldPos, valid)
	if not ghost then return end
	local ax, az = math.floor(worldPos.X / PXS + 0.5), math.floor(worldPos.Z / PXS + 0.5)
	ghost.container.Position = UDim2.fromOffset(ax - ghost.w // 2, az - ghost.h + 1)
	ghost.container.Visible = true
	placeRing(ghost.ring, worldPos.X, worldPos.Z)
	if ghost.area then
		-- aim at the closest bit of the path (that's where it will mostly shoot)
		local target = nearestPathPoint(worldPos.X, worldPos.Z)
		if target then
			local ax, az = aimWithin(worldPos.X, worldPos.Z, target.X, target.Y, ghost.area.range)
			placeArea(ghost.area, worldPos.X, worldPos.Z, ax, az)
		end
	end
	if ghost.valid ~= valid then
		ghost.valid = valid
		local tint = valid and rgb(80, 230, 100) or rgb(240, 70, 70)
		recolorRing(ghost.ring, tint)
		recolorArea(ghost.area, tint)
		for frame, color in pairs(ghost.orig) do
			frame.BackgroundColor3 = color:Lerp(tint, 0.45)
		end
		if ghost.image then ghost.image.ImageColor3 = WHITE:Lerp(tint, 0.45) end
	end
end

-- ===================== PUBLIC: selected unit =====================
function WorldView.setSelected(model)
	if selected then
		if selected.ring then selected.ring.holder:Destroy() end
		destroyArea(selected.area)
		selected.arrow:Destroy()
		selected = nil
	end
	local vis = model and towers[model]
	if not vis then return end
	local arrow = PixelArt.sprite("Arrow")
	arrow.ZIndex = 4500
	arrow.Visible = false
	arrow.Parent = entityScaler
	selected = { model = model, arrow = arrow, level = nil }
end

function WorldView.getTowerAt(worldPos)
	local best, bestD = nil, math.huge
	for model, vis in pairs(towers) do
		local root = vis.root
		if root then
			local p = root.Position
			local dx = worldPos.X - p.X
			local dz = worldPos.Z - (p.Z - 4)
			if math.abs(dx) <= 4 and math.abs(dz) <= 5.5 then
				local d = dx * dx + dz * dz
				if d < bestD then best, bestD = model, d end
			end
		end
	end
	return best
end

-- ===================== PUBLIC: view =====================
function WorldView.screenToWorld(screenPos)
	-- screenPos comes from UserInputService:GetMouseLocation() (includes the top bar inset),
	-- while AbsolutePosition does not, so take the inset off first
	local inset = GuiService:GetGuiInset()
	local pos = rootFrame.AbsolutePosition
	local ax = (screenPos.X - inset.X - pos.X - originX) / S
	local az = (screenPos.Y - inset.Y - pos.Y - originY) / S
	return Vector3.new(ax * PXS, Config.GroundY, az * PXS)
end

function WorldView.setAlwaysHealthBars(on)
	alwaysBars = on and true or false
end

-- the enemy drawn closest to worldPos, within `reach` (x its size) studs of its body
local function enemyNear(worldPos, reach)
	local p = Vector2.new(worldPos.X, worldPos.Z)
	local best, bestDist = nil, math.huge
	for _, vis in pairs(enemies) do
		local k = vis.boss and Config.Boss.Scale or 1
		local d = (p - Vector2.new(vis.x, vis.z - 2.5 * k)).Magnitude
		if d <= reach * k and d < bestDist then
			best, bestDist = vis, d
		end
	end
	return best
end

-- Touch screens have no hover: a tap shows the health bar of the enemy under the finger for a moment
function WorldView.revealHealthBar(worldPos)
	local vis = enemyNear(worldPos, 5)
	if vis then vis.barUntil = os.clock() + TAP_BAR_SECONDS end
end

-- The HUD shrinks on small screens, so the space it covers (in screen pixels) changes with it
function WorldView.setInsets(right, top, bottom)
	rightInset, topInset, bottomInset = right, top, bottom
end

-- The lock button in the HUD: while locked, the view stays as it is (no panning, no zooming)
local viewLocked = false
function WorldView.setViewLocked(on)
	viewLocked = on and true or false
end

function WorldView.zoom(delta)
	if viewLocked then return end
	zoomDelta = math.clamp(zoomDelta + delta, 1 - baseZoom, math.min(MAX_ZOOM_IN, #ZOOM_LEVELS - baseZoom))
end

-- Moves the map by a screen-pixel delta (drag right = the map moves right)
function WorldView.pan(dx, dy)
	if viewLocked then return end
	panX = math.clamp(panX + dx / S, -PAN_LIMIT_X, PAN_LIMIT_X)
	panZ = math.clamp(panZ + dy / S, -PAN_LIMIT_Z, PAN_LIMIT_Z)
end

-- Puts the map back in the middle of the screen
function WorldView.centerView()
	panX, panZ = 0, 0
end

function WorldView.getScale()
	return S
end

-- ===================== UPDATE (every frame) =====================
function WorldView.update(dt)
	if not started then return end
	layout()
	local now = os.clock()
	local alpha = 1 - math.exp(-dt * 18)

	-- enemies glide toward the position the server reports and bob up and down
	for part, vis in pairs(enemies) do
		if not part:IsDescendantOf(workspace) then
			removeEnemy(part)
			continue
		end
		local p = part.Position
		vis.x += (p.X - vis.x) * alpha
		vis.z += (p.Z - vis.z) * alpha
		local px = math.floor(vis.x / PXS + 0.5)
		local pz = math.floor(vis.z / PXS + 0.5)
		local bob = -math.floor(math.abs(math.sin(now * 7 + vis.phase)) * 2.2)
		vis.container.Position = UDim2.fromOffset(px - vis.ox, pz - vis.oy + bob)
		vis.container.ZIndex = 2000 + pz

		-- Refine abilities: burning enemies give off orange sparks, slowed ones blue sparks
		local status = part:GetAttribute("Status")
		if status and status ~= "" and now - (vis.fxAt or 0) >= 0.25 then
			vis.fxAt = now
			local lift = vis.boss and 10 or 4
			if string.find(status, "Burn", 1, true) then burst(vis.x, vis.z - lift, BURN_FX, 2) end
			if string.find(status, "Slow", 1, true) then burst(vis.x, vis.z - lift, SLOW_FX, 2) end
		end
	end

	-- summons glide like enemies and face the way they walk
	for part, vis in pairs(summons) do
		if not part:IsDescendantOf(workspace) then
			removeSummon(part)
			continue
		end
		local p = part.Position
		local dx = p.X - vis.x
		vis.x += dx * alpha
		vis.z += (p.Z - vis.z) * alpha
		if math.abs(dx) > 0.01 then
			vis.right.Visible = dx > 0
			vis.left.Visible = dx <= 0
		end
		local px, pz = math.floor(vis.x / PXS + 0.5), math.floor(vis.z / PXS + 0.5)
		local step = (math.sin(now * 9 + vis.phase) > 0) and -1 or 0
		vis.container.Position = UDim2.fromOffset(px - vis.w // 2, pz - vis.h + 1 + step)
		vis.container.ZIndex = 2000 + pz
		vis.container.Visible = true
	end

	-- health bars: the enemy under the mouse, a tapped one for a moment (or all of them when the
	-- setting is on). With touch there is no hover: the "mouse" would stay where the last finger was.
	local hovered = nil
	if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
		hovered = enemyNear(WorldView.screenToWorld(UserInputService:GetMouseLocation()), 3.5)
	end
	-- the base's bar over the castle is always shown
	if castle and castle.root then updateCastleBar() end
	for _, vis in pairs(enemies) do
		local show = alwaysBars or vis == hovered or (vis.barUntil or 0) > now
		if vis.barShown ~= show then
			vis.barShown = show
			vis.barRoot.Visible = show
		end
	end

	-- units
	for model, vis in pairs(towers) do
		if not model:IsDescendantOf(workspace) then
			removeTower(model)
			continue
		end
		local root = vis.root
		if root then
			local p = root.Position
			local faceLeft = root.CFrame.LookVector.X < -0.2
			vis.right.Visible = not faceLeft
			vis.left.Visible = faceLeft
			local px = math.floor(p.X / PXS + 0.5)
			local pz = math.floor(p.Z / PXS + 0.5)
			local idle = (math.sin(now * 3 + vis.phase) > 0.35) and -1 or 0
			local recoilX, recoilY = 0, 0
			if now - vis.recoilAt < 0.1 then
				recoilX = faceLeft and 1 or -1
				recoilY = -1
			end
			vis.container.Position = UDim2.fromOffset(px - vis.w // 2 + recoilX, pz - vis.h + 1 + idle + recoilY)
			vis.container.ZIndex = 2000 + pz
			vis.container.Visible = true
		end
	end

	-- selected unit: range ring + bobbing arrow
	if selected then
		local vis = towers[selected.model]
		if vis and vis.root then
			local p = vis.root.Position
			if selected.level ~= vis.level then
				selected.level = vis.level
				if selected.ring then selected.ring.holder:Destroy() end
				destroyArea(selected.area)
				local stats = Config.ScaledStats(vis.unit, vis.level, vis.model:GetAttribute("UnitLevel"))
				selected.ring = makeRing(stats and stats.Range or 10, WHITE)
				selected.area = makeArea(Config.AttackOf(vis.unit, vis.level), stats and stats.Range or 10, WHITE)
			end
			placeRing(selected.ring, p.X, p.Z)
			if selected.area then
				-- aim at the enemy it shot last (if recent), otherwise the way it faces
				local ax, az
				local t = vis.lastTarget
				if t and now - (vis.lastShotAt or 0) < 1.5 and t.part and t.part.Parent then
					ax, az = aimWithin(p.X, p.Z, t.x, t.z, selected.area.range)
				else
					local look = vis.root.CFrame.LookVector
					local reach = selected.area.range * 0.7
					ax, az = p.X + look.X * reach, p.Z + look.Z * reach
				end
				placeArea(selected.area, p.X, p.Z, ax, az)
			end
			local ax, az = math.floor(p.X / PXS + 0.5), math.floor(p.Z / PXS + 0.5)
			local bob = (math.sin(now * 6) > 0) and 0 or 1
			selected.arrow.Position = UDim2.fromOffset(ax - 3, az - vis.h - 6 + bob)
			selected.arrow.Visible = true
		else
			WorldView.setSelected(nil)
		end
	end

	-- effects: shots and particles
	for i = #effects, 1, -1 do
		local e = effects[i]
		local age = now - e.t0
		if age >= e.life then
			e.frame:Destroy()
			table.remove(effects, i)
		elseif e.kind == "fx" then
			local a = age - e.delay
			if a >= 0 then
				local t = a / (e.life - e.delay)
				e.frame.Visible = true
				e.frame.BackgroundTransparency = e.base + (1 - e.base) * t
				if e.stroke then e.stroke.Transparency = t end
				if e.grow then
					local size = e.grow.From:Lerp(e.grow.To, math.min(1, t * 1.6))
					e.frame.Size = UDim2.fromOffset(size.X, size.Y)
				end
			end
		elseif e.kind == "part" then
			e.vz += 60 * dt
			e.x += e.vx * dt
			e.z += e.vz * dt
			e.frame.Position = UDim2.fromOffset(math.floor(e.x), math.floor(e.z))
			if age > e.life * 0.6 then
				e.frame.BackgroundTransparency = (age / e.life - 0.6) / 0.4
			end
		else
			local a = age / e.life
			if e.target then
				e.x1 = e.target.x / PXS
				e.z1 = (e.target.z - 2.5) / PXS
			end
			e.frame.Position = UDim2.fromOffset(math.floor(e.x0 + (e.x1 - e.x0) * a) - 1, math.floor(e.z0 + (e.z1 - e.z0) * a) - 1)
		end
	end
end

-- ===================== START / STOP =====================
function WorldView.start(parent, opts)
	opts = opts or {}
	if started then WorldView.stop() end
	rightInset = opts.rightInset or 200
	topInset = opts.topInset or 176
	bottomInset = opts.bottomInset or 156

	rootFrame = Instance.new("Frame")
	rootFrame.Name = "World"
	rootFrame.Size = UDim2.fromScale(1, 1)
	rootFrame.BackgroundColor3 = GRASS
	rootFrame.BorderSizePixel = 0
	rootFrame.ClipsDescendants = true
	rootFrame.Parent = parent

	mapHolder, mapScaler, mapScale = makeLayer(rootFrame, "Map")
	entityHolder, entityScaler, entityScale = makeLayer(rootFrame, "Entities")
	entityHolder.ZIndex = 5
	started = true
	layout()
	castle = nil
	buildMap()
	buildCastleBar()

	if opts.connect ~= false then
		-- enemies and units are the invisible parts the server creates
		local enemiesFolder = workspace:WaitForChild("Enemies")
		local towersFolder = workspace:WaitForChild("Towers")
		for _, e in ipairs(enemiesFolder:GetChildren()) do addEnemy(e) end
		for _, t in ipairs(towersFolder:GetChildren()) do addTower(t) end
		track(enemiesFolder.ChildAdded:Connect(addEnemy))
		local summonsFolder = workspace:WaitForChild("Summons")
		for _, s in ipairs(summonsFolder:GetChildren()) do addSummon(s) end
		track(summonsFolder.ChildAdded:Connect(addSummon))
		track(towersFolder.ChildAdded:Connect(function(model)
			-- wait a moment so the model's parts and attributes have arrived
			task.defer(addTower, model)
		end))

		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local shot = remotes:WaitForChild("Shot")
		track(shot.OnClientEvent:Connect(function(model, enemyPart, targetPos, shape)
			local vis = towers[model]
			if not vis or not vis.root then return end
			vis.recoilAt = os.clock()
			-- only shoot at enemies that are drawn on screen; the bolt follows the drawn sprite
			local target = typeof(enemyPart) == "Instance" and enemies[enemyPart] or nil
			if not target then return end
			vis.lastTarget, vis.lastShotAt = target, os.clock() -- the area indicator follows it
			local p = vis.root.Position
			local color = Config.Units[vis.unit].BeamColor
			-- area attacks (#40): their shape; Line / Cone / Circle replace the bolt
			if typeof(shape) == "table" then
				attackFx(p.X, p.Z, target.x, target.z, shape, color)
				if shape.K ~= "Splash" then return end
			end
			spawnShot(p.X, p.Z - 4.5, target.x, target.z - 2.5, color, target, Config.ShotTravel)
		end))
		track(RunService.RenderStepped:Connect(function(dt)
			WorldView.update(dt)
		end))
	end
end

function WorldView.stop()
	started = false
	for _, c in ipairs(connections) do c:Disconnect() end
	table.clear(connections)
	for _, vis in pairs(enemies) do for _, c in ipairs(vis.conns) do c:Disconnect() end end
	for _, vis in pairs(towers) do for _, c in ipairs(vis.conns) do c:Disconnect() end end
	for _, vis in pairs(summons) do for _, c in ipairs(vis.conns) do c:Disconnect() end end
	table.clear(summons)
	table.clear(enemies)
	table.clear(towers)
	table.clear(effects)
	ghost, selected, castle = nil, nil, nil
	if rootFrame then rootFrame:Destroy() rootFrame = nil end
end

-- Edit-mode helpers so the world can be previewed without playing
function WorldView._addEnemy(part) addEnemy(part) end
function WorldView._addTower(model) addTower(model) end
function WorldView._burst(x, z, color, n) burst(x, z, color, n) end
function WorldView._shot(x0, z0, x1, z1, color) spawnShot(x0, z0, x1, z1, color) end

return WorldView
