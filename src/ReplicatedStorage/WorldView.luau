-- WorldView: draws the whole game world as 2D pixel art on a GUI layer:
-- the map (grass, path, trees), enemies, units, shots, effects, the placement preview.
-- The server keeps simple invisible parts for the game logic; this module only draws them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

-- state
local rootFrame, mapScaler, entityScaler
local S = 4 -- screen pixels per art pixel
local zoomDelta = 0
local originX, originY = 0, 0
-- camera pan, in art pixels (so zooming keeps the same spot in view); clamped to the map
local panX, panZ = 0, 0
local PAN_LIMIT_X, PAN_LIMIT_Z = 170, 80
local rightInset = 200
local topInset, bottomInset = 176, 156 -- screen space kept free for the HUD plates / prep panel
local started = false
local alwaysBars = false -- show every enemy's health bar (otherwise only the one under the mouse)
local enemies, towers, effects = {}, {}, {}
local connections = {}
local ghost, selected

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
	local base = math.max(2, math.min(math.floor(availW / 340), math.floor(availH / 140)))
	S = math.clamp(base + zoomDelta, 2, 8)
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
		vis.sprite = PixelArt.sprite("Wisp", { tier = vis.tier, color = tierColor(vis.tier) })
	end
	vis.sprite.Parent = vis.container
end

-- Health bar: the enemy's name on top, then a red bar with "current/max" written inside it
local BAR_FILL, BAR_BACK = rgb(214, 38, 38), rgb(84, 12, 16)

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
	root.Position = UDim2.fromOffset(6 - bw / 2, top)
	root.Size = UDim2.fromOffset(bw, nameH + bh)
	root.Visible = false
	root.Parent = container
	barText(root, 0, 0, bw, nameH, boss and Config.Boss.Name or "Wisp", textSize)
	rect(root, 0, nameH, bw, bh, BLACK)
	rect(root, 1, nameH + 1, bw - 2, bh - 2, BAR_BACK)
	vis.barFill = rect(root, 1, nameH + 1, bw - 2, bh - 2, BAR_FILL)
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
	local container = Instance.new("Frame")
	container.Name = "Enemy"
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Size = UDim2.fromOffset(12, 12)
	local p = part.Position
	local startX, startZ = math.floor(p.X / PXS + 0.5), math.floor(p.Z / PXS + 0.5)
	container.Position = UDim2.fromOffset(startX - 6, startZ - 11)
	container.ZIndex = 2000 + startZ
	container.Parent = entityScaler
	if not vis.boss then
		rect(container, 1, 10, 10, 2, BLACK, 0.6) -- shadow
	end
	vis.container = container
	buildEnemySprite(vis)
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
	vis.label.Text = isMax and "MAX" or ("LV" .. level)
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
	vis.right = PixelArt.sprite(unit)
	vis.right.Parent = container
	vis.left = PixelArt.sprite(unit, { flip = true })
	vis.left.Visible = false
	vis.left.Parent = container
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

-- ===================== PUBLIC: placement preview =====================
function WorldView.clearGhost()
	if ghost then
		ghost.container:Destroy()
		ghost.ring.holder:Destroy()
		ghost = nil
	end
end

function WorldView.setGhost(unitName)
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
	ghost = {
		container = container,
		ring = makeRing(Config.Units[unitName].Levels[1].Range, WHITE),
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
	if ghost.valid ~= valid then
		ghost.valid = valid
		local tint = valid and rgb(80, 230, 100) or rgb(240, 70, 70)
		recolorRing(ghost.ring, tint)
		for frame, color in pairs(ghost.orig) do
			frame.BackgroundColor3 = color:Lerp(tint, 0.45)
		end
	end
end

-- ===================== PUBLIC: selected unit =====================
function WorldView.setSelected(model)
	if selected then
		if selected.ring then selected.ring.holder:Destroy() end
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

function WorldView.zoom(delta)
	zoomDelta = math.clamp(zoomDelta + delta, -1, 3)
end

-- Moves the map by a screen-pixel delta (drag right = the map moves right)
function WorldView.pan(dx, dy)
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
		vis.container.Position = UDim2.fromOffset(px - 6, pz - 11 + bob)
		vis.container.ZIndex = 2000 + pz
	end

	-- health bars: the enemy under the mouse (or all of them when the setting is on)
	local mouse = WorldView.screenToWorld(UserInputService:GetMouseLocation())
	local mouse2 = Vector2.new(mouse.X, mouse.Z)
	local hovered, hoveredDist = nil, math.huge
	for _, vis in pairs(enemies) do
		local k = vis.boss and Config.Boss.Scale or 1
		local d = (mouse2 - Vector2.new(vis.x, vis.z - 2.5 * k)).Magnitude
		if d <= 3.5 * k and d < hoveredDist then
			hovered, hoveredDist = vis, d
		end
	end
	for _, vis in pairs(enemies) do
		local show = alwaysBars or vis == hovered
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
				local stats = Config.GetStats(vis.unit, vis.level)
				selected.ring = makeRing(stats and stats.Range or 10, WHITE)
			end
			placeRing(selected.ring, p.X, p.Z)
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
	buildMap()

	if opts.connect ~= false then
		-- enemies and units are the invisible parts the server creates
		local enemiesFolder = workspace:WaitForChild("Enemies")
		local towersFolder = workspace:WaitForChild("Towers")
		for _, e in ipairs(enemiesFolder:GetChildren()) do addEnemy(e) end
		for _, t in ipairs(towersFolder:GetChildren()) do addTower(t) end
		track(enemiesFolder.ChildAdded:Connect(addEnemy))
		track(towersFolder.ChildAdded:Connect(function(model)
			-- wait a moment so the model's parts and attributes have arrived
			task.defer(addTower, model)
		end))

		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local shot = remotes:WaitForChild("Shot")
		track(shot.OnClientEvent:Connect(function(model, enemyPart, targetPos)
			local vis = towers[model]
			if not vis or not vis.root then return end
			vis.recoilAt = os.clock()
			-- only shoot at enemies that are drawn on screen; the bolt follows the drawn sprite
			local target = typeof(enemyPart) == "Instance" and enemies[enemyPart] or nil
			if not target then return end
			local p = vis.root.Position
			local color = Config.Units[vis.unit].BeamColor
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
	table.clear(enemies)
	table.clear(towers)
	table.clear(effects)
	ghost, selected = nil, nil
	if rootFrame then rootFrame:Destroy() rootFrame = nil end
end

-- Edit-mode helpers so the world can be previewed without playing
function WorldView._addEnemy(part) addEnemy(part) end
function WorldView._addTower(model) addTower(model) end
function WorldView._burst(x, z, color, n) burst(x, z, color, n) end
function WorldView._shot(x0, z0, x1, z1, color) spawnShot(x0, z0, x1, z1, color) end

return WorldView
