-- PixelArt: all the sprites in the game. One "art pixel" = 1 unit; the screen scales it with a UIScale.
-- A sprite is either
--   * a character grid drawn with plain colored Frames (defs below, no uploads needed), or
--   * an uploaded image, for units that set Config.Units[name].Image (see Config) - this wins
--     over the grid, so a unit can switch to its image as soon as the asset id is filled in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local PixelArt = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Creates one solid colored rectangle (in art pixels)
function PixelArt.rect(parent, x, y, w, h, color, transparency)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Parent = parent
	return f
end
local rect = PixelArt.rect
local WHITE_PX = Color3.new(1, 1, 1)

-- Turns a character grid into a Frame made of as few rectangles as possible
local function buildGrid(rows, palette, flip)
	local h = #rows
	local w = #rows[1]
	local grid = {}
	for y = 1, h do
		grid[y] = {}
		for x = 1, w do
			local sx = flip and (w - x + 1) or x
			local ch = rows[y]:sub(sx, sx)
			grid[y][x] = (ch ~= "." and palette[ch]) and ch or false
		end
	end

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(w, h)

	local used = {}
	for y = 1, h do used[y] = {} end
	for y = 1, h do
		for x = 1, w do
			local ch = grid[y][x]
			if ch and not used[y][x] then
				local x2 = x
				while x2 + 1 <= w and grid[y][x2 + 1] == ch and not used[y][x2 + 1] do
					x2 += 1
				end
				local y2 = y
				local grow = true
				while grow and y2 + 1 <= h do
					for xx = x, x2 do
						if grid[y2 + 1][xx] ~= ch or used[y2 + 1][xx] then
							grow = false
							break
						end
					end
					if grow then y2 += 1 end
				end
				for yy = y, y2 do
					for xx = x, x2 do
						used[yy][xx] = true
					end
				end
				rect(root, x - 1, y - 1, x2 - x + 1, y2 - y + 1, palette[ch])
			end
		end
	end
	return root
end

-- ===================== SPRITE DEFINITIONS =====================
local defs = {}

-- Herobrine: blocky figure with glowing white eyes (14 x 18)
defs.Herobrine = {
	rows = {
		"...kkkkkkkk...",
		"..kyyyyyyyyk..",
		"..kyyyyyyyyk..",
		"..kyssssssyk..",
		"..kssssssssk..",
		"..kswwsswwsk..",
		"..ksssSSsssk..",
		"..kssyyyyssk..",
		"...kkkkkkkk...",
		".kcccccccccck.",
		".kssccccccssk.",
		".kssccccccssk.",
		".kssccccccssk.",
		".kkkCCCCCCkkk.",
		"...knnnnnnk...",
		"...knnnnnnk...",
		"...knnkknnk...",
		"...kggkkggk...",
	},
	palette = {
		k = rgb(24, 18, 26), y = rgb(58, 36, 26), s = rgb(156, 108, 78), S = rgb(122, 82, 58),
		w = rgb(255, 255, 255), c = rgb(38, 176, 170), C = rgb(24, 120, 120), n = rgb(62, 52, 168),
		g = rgb(90, 90, 98),
	},
}

-- Voidseer: spiky white hair, black blindfold, dark high-collar coat, one hand raised (16 x 22)
defs.Voidseer = {
	rows = {
		"....k.kk.kk.k...",
		"...khkhhkhhkhk..",
		"..khhhhhhhhhhhk.",
		".khhhhhhhhhhhhhk",
		".khhHhhhhhhHhhhk",
		".khHhhhHhhhhhHhk",
		"..kHHhHHhhHHhHk.",
		".k.kbbbbbbbbbk..",
		"kskkbebbbbbebk..",
		"kskksssssssssk..",
		"kSkkSsssssssSk..",
		"kcckkccccccckk..",
		"kcckcpccccpccck.",
		".kkccccpcccccck.",
		"..kcpccccccpcSk.",
		"..kccccpcccccck.",
		"..kkCCCCCCCCCkk.",
		"...knnnnpnnnnk..",
		"...knnnk.knnnk..",
		"...knpnk.knpnk..",
		"...kgggk.kgggk..",
		"..kggggk.kggggk.",
	},
	palette = {
		k = rgb(20, 16, 28), h = rgb(246, 244, 252), H = rgb(196, 190, 222),
		b = rgb(30, 28, 40), e = rgb(112, 108, 132), s = rgb(246, 206, 170), S = rgb(214, 168, 134),
		c = rgb(40, 38, 58), p = rgb(92, 72, 146), C = rgb(28, 26, 42), n = rgb(34, 32, 48),
		g = rgb(72, 72, 86),
	},
}

-- Zaruto (Epic): spiky blond hair, forehead plate, whisker marks, black-and-orange jacket (16 x 23)
defs.Zaruto = {
	rows = {
		"...k...kk...k...",
		"..kyk.kyyk.kyk..",
		".kyyykyyyykyyyk.",
		".kyyyyyyyyyyyyk.",
		"kyyYyyyyyyyyYyyk",
		"kyybbmmmmmmbbyyk",
		"kyybbmmMMmmbbyyk",
		".kybbbbbbbbbbyk.",
		"..kssssssssssk..",
		"..kseesssseesk..",
		"..kwsssssssswk..",
		"..kSwsssssswSk..",
		"..kkjjjjjjjjkk..",
		"..kjjjjjzjjjjk..",
		"..kjssjjzjssjk..",
		"..kjjjjjzjjjjk..",
		"..kooooozooook..",
		"..kOooooOzooOk..",
		"..kkkkkkkkkkkk..",
		"..kooookkooook..",
		"..kttookkooook..",
		"..kooookkooook..",
		"..kggggkkggggk..",
	},
	palette = { k = rgb(20, 16, 28), y = rgb(250, 218, 70), Y = rgb(222, 170, 40), b = rgb(36, 34, 48), m = rgb(196, 200, 210), M = rgb(110, 114, 130), s = rgb(246, 206, 170), S = rgb(214, 168, 134), e = rgb(50, 90, 210), w = rgb(200, 120, 110), j = rgb(40, 38, 52), z = rgb(150, 150, 162), o = rgb(240, 132, 44), O = rgb(200, 98, 30), t = rgb(236, 236, 240), g = rgb(96, 66, 50) },
}

-- Fluffy (Epic): straw hat with a red band, big grin, red vest, blue shorts, sandals (16 x 22)
defs.Fluffy = {
	rows = {
		"....kkkkkkkk....",
		"...khhhhhhhhk...",
		"...krrrrrrrrk...",
		"..khhhhhhhhhhk..",
		"khhhhhhhhhhhhhhk",
		".kkaaaaaaaaaakk.",
		"..kassssssssak..",
		"..kssdssssdssk..",
		"..kssqwwwwqcsk..",
		"..kssqTTTTqssk..",
		"..ksssqqqqsssk..",
		".ksvvvvssvvvvsk.",
		".ksvvvvyvvvvvsk.",
		".ksvvvvvvvvvvsk.",
		".kssvvvyvvvvssk.",
		"..kvvvvvvvvvvk..",
		"..kbbbbbbbbbbk..",
		"..kbbbbkkbbbbk..",
		"..kwwwwkkwwwwk..",
		"...ksssk.ksssk..",
		"...ksssk.ksssk..",
		"..kgggk..kgggk..",
	},
	palette = { k = rgb(20, 16, 28), h = rgb(240, 196, 70), r = rgb(190, 40, 46), a = rgb(26, 24, 30), s = rgb(246, 206, 170), d = rgb(20, 16, 28), q = rgb(110, 30, 34), w = rgb(255, 255, 255), T = rgb(222, 100, 110), c = rgb(200, 50, 50), v = rgb(186, 40, 46), y = rgb(250, 210, 60), b = rgb(70, 110, 200), g = rgb(110, 72, 50) },
}

-- Ichitoe (Epic): spiky orange hair, black robe with a white sash, huge blade on his back (18 x 21)
defs.Ichitoe = {
	rows = {
		"...k..kk..k.......",
		"..kok.kook.kok....",
		".koookooookoook...",
		".kooooooooooook...",
		"koooOooooooOoook..",
		"kooooooooooooook..",
		".kosssssssssok..kk",
		"..ksdssssdssk..kWk",
		"..ksssssssssk.kWGk",
		"...kssssssskk.kWGk",
		"..kxxxwwwxxxxkkWGk",
		".kxxxxxwxRxxxxkWGk",
		".ksxxxxxRxxxxsxkGk",
		".kkxxxxRxxxxxkkWGk",
		"..kxWWWWWWWxxk.kGk",
		"..kxxxxxxxxxxk..kk",
		"..kxxxxxxxxxxk....",
		"..kxxxxkkxxxxk....",
		"..kxxxxkkxxxxk....",
		"..kxxxk..kxxxk....",
		"..kwggk..kggwk....",
	},
	palette = { k = rgb(20, 16, 28), o = rgb(250, 140, 40), O = rgb(214, 104, 24), s = rgb(246, 206, 170), d = rgb(30, 24, 28), x = rgb(36, 34, 44), w = rgb(240, 240, 244), R = rgb(170, 40, 44), W = rgb(236, 236, 242), G = rgb(150, 152, 164), g = rgb(150, 104, 60) },
}
-- Summon chest, in two pieces so the lid can fly open: lid (20 x 7) above the base (20 x 8)
local CHEST_PALETTE = {
	k = rgb(46, 30, 16), w = rgb(176, 112, 52), W = rgb(140, 86, 38),
	g = rgb(236, 186, 78), G = rgb(196, 146, 52), l = rgb(255, 236, 160),
}
defs.ChestLid = {
	rows = {
		"........kkkk........",
		"........kGGk........",
		".kkkkkkkkkkkkkkkkkk.",
		".kGggggggggggggggGk.",
		".kgwwwwgwwwwgwwwwgk.",
		".kgwwwwgwwwwgwwwwgk.",
		".kkkkkkkkkkkkkkkkkk.",
	},
	palette = CHEST_PALETTE,
}
defs.ChestBase = {
	rows = {
		".kgwwwwgkkkkgwwwwgk.",
		".kgwwwwgkllkgwwwwgk.",
		".kgWwwwgkGGkgwwwWgk.",
		".kgwwwwgkkkkgwwwwgk.",
		".kgwwwwgwwwwgwwwwgk.",
		".kgWwwwgwwwwgwwwWgk.",
		".kGggggggggggggggGk.",
		".kkkkkkkkkkkkkkkkkk.",
	},
	palette = CHEST_PALETTE,
}

-- Colours for every enemy sprite: built from the tier colour (opts.color)
local function enemyPalette(opts)
	local c = opts.color or rgb(70, 190, 70)
	return {
		k = c:Lerp(Color3.new(0, 0, 0), 0.68),
		l = c:Lerp(Color3.new(1, 1, 1), 0.5),
		m = c,
		d = c:Lerp(Color3.new(0, 0, 0), 0.3),
		w = Color3.new(1, 1, 1),
		e = rgb(30, 30, 50),
		a = rgb(118, 124, 140), -- armour (Tank)
		f = rgb(236, 240, 255), -- wings (Flyer)
	}
end

-- Wisp: the enemy. Its color comes from the enemy tier (12 x 12)
defs.Wisp = {
	rows = {
		".....kk.....",
		"....kllk....",
		"....kllk....",
		"...kllmmk...",
		"..kllmmmmk..",
		".klmmmmmmmk.",
		".kmwemmwemk.",
		".kmmmmmmmmk.",
		".kmmmmmmmmk.",
		".kdmmmmmmdk.",
		"..kddddddk..",
		"..kk.kk.kk..",
	},
	palette = function(opts) return enemyPalette(opts) end,
}

-- Enemy types (Config.EnemyTypes): same tier colours as the wisp
-- Runner: small and quick (10 x 9)
defs.Runner = {
	rows = {
		"....kk....",
		"...kllk...",
		"..kllmmk..",
		".klmmmmmk.",
		"kmwemwemmk",
		"kmmmmmmmk.",
		".kdmmmmdk.",
		"..kddddk..",
		"...k.k....",
	},
	palette = function(opts) return enemyPalette(opts) end,
}
-- Tank: big, with grey armour plates (14 x 12)
defs.Tank = {
	rows = {
		"......kk......",
		".....kllk.....",
		"....kllmmk....",
		"..kkllmmmmkk..",
		".kaakmmmmkaak.",
		"kaaamwemwemaak",
		"kaaammmmmmmaak",
		"kaaammmmmmmaak",
		".kaadmmmmmdak.",
		"..kkddddddkk..",
		"..kaak..kaak..",
		"..kkkk..kkkk..",
	},
	palette = function(opts) return enemyPalette(opts) end,
}
-- Flyer: a wisp with wings (12 x 11); drawn floating above its shadow
defs.Flyer = {
	rows = {
		".....kk.....",
		"....kllk....",
		"kk..kllk..kk",
		"kffkllmmkffk",
		"kfffkmmmkffk",
		".kfkmmmmmkfk",
		"..kmwemwemk.",
		"..kmmmmmmmk.",
		"..kdmmmmmdk.",
		"...kddddk...",
		"....kkkk....",
	},
	palette = function(opts) return enemyPalette(opts) end,
}

-- Little gold arrow shown above the selected unit (7 x 4)
defs.Arrow = {
	rows = {
		"ggggggg",
		".ggggg.",
		"..ggg..",
		"...g...",
	},
	palette = { g = rgb(255, 214, 84) },
}

local templates = {}
local PLACEHOLDER_W, PLACEHOLDER_H = 14, 18

-- The unit's uploaded image settings, or nil when it should use its character grid
local function imageDef(name)
	local unit = Config.Units[name]
	local image = unit and unit.Image
	if type(image) == "table" and type(image.Id) == "string" and image.Id ~= "" then
		return image
	end
	return nil
end

-- An ImageLabel showing one frame of an uploaded sprite (sheet). Pixelated, so it stays crisp when zoomed.
local function buildImage(image, opts)
	local frames = image.Frames or {}
	local cell = frames[opts.frame or "Idle"] or frames.Idle or { 0, 0 }
	local fw, fh = image.FrameSize[1], image.FrameSize[2]
	local label = Instance.new("ImageLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = image.Id
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ScaleType = Enum.ScaleType.Stretch
	label.Size = UDim2.fromOffset(image.Size[1], image.Size[2])
	if opts.flip then
		-- a negative rect width mirrors the image: start at the frame's right edge
		label.ImageRectOffset = Vector2.new((cell[1] + 1) * fw, cell[2] * fh)
		label.ImageRectSize = Vector2.new(-fw, fh)
	else
		label.ImageRectOffset = Vector2.new(cell[1] * fw, cell[2] * fh)
		label.ImageRectSize = Vector2.new(fw, fh)
	end
	return label
end

-- Grey "?" box for a unit that has neither an image nor a character grid yet
local function buildPlaceholder()
	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(PLACEHOLDER_W, PLACEHOLDER_H)
	rect(root, 0, 0, PLACEHOLDER_W, PLACEHOLDER_H, rgb(20, 16, 28))
	rect(root, 1, 1, PLACEHOLDER_W - 2, PLACEHOLDER_H - 2, rgb(120, 124, 140))
	rect(root, 5, 4, 4, 1, WHITE_PX)
	rect(root, 8, 5, 1, 3, WHITE_PX)
	rect(root, 6, 8, 2, 1, WHITE_PX)
	rect(root, 6, 9, 1, 2, WHITE_PX)
	rect(root, 6, 12, 1, 1, WHITE_PX)
	return root
end

-- Returns a fresh copy of a sprite.
-- opts: flip (mirror left-right), tier + color (Wisp), frame ("Idle" / "Attack"... for image sprite sheets),
--       silhouette (a Color3: the whole sprite in that one colour; used for player-colour outlines)
function PixelArt.sprite(name, opts)
	opts = opts or {}
	local image = imageDef(name)
	local def = defs[name]
	local key = table.concat({
		name, tostring(opts.tier or 0), opts.flip and "f" or "n",
		image and ("img:" .. image.Id .. ":" .. tostring(opts.frame or "Idle")) or "grid",
		opts.silhouette and opts.silhouette:ToHex() or "",
	}, "|")
	local tpl = templates[key]
	if not tpl then
		if image then
			tpl = buildImage(image, opts)
			if opts.silhouette then tpl.ImageColor3 = opts.silhouette end -- images can only be tinted
		elseif def then
			local palette = type(def.palette) == "function" and def.palette(opts) or def.palette
			if opts.silhouette then
				local color = opts.silhouette
				palette = setmetatable({}, { __index = function() return color end })
			end
			tpl = buildGrid(def.rows, palette, opts.flip)
		else
			warn("PixelArt: no image or character grid for " .. tostring(name) .. ", showing a placeholder")
			tpl = buildPlaceholder()
		end
		templates[key] = tpl
	end
	local copy = tpl:Clone()
	copy.Name = name
	return copy
end

-- A 1-art-pixel outline around a sprite, in `color`: four silhouettes shifted up / down / left / right.
-- Returns a Frame of (w + 2) x (h + 2) to place at (-1, -1) behind the sprite.
function PixelArt.outline(name, color, flip)
	local w, h = PixelArt.size(name)
	local root = Instance.new("Frame")
	root.Name = "Outline"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(w + 2, h + 2)
	root.Position = UDim2.fromOffset(-1, -1)
	for _, offset in ipairs({ { 0, 1 }, { 2, 1 }, { 1, 0 }, { 1, 2 } }) do
		local copy = PixelArt.sprite(name, { flip = flip, silhouette = color })
		copy.Position = UDim2.fromOffset(offset[1], offset[2])
		copy.Parent = root
	end
	return root
end

-- Width and height of a sprite in art pixels
function PixelArt.size(name)
	local image = imageDef(name)
	if image then return image.Size[1], image.Size[2] end
	local def = defs[name]
	if def then return #def.rows[1], #def.rows end
	return PLACEHOLDER_W, PLACEHOLDER_H
end

-- A pine tree (14 x 24). tone = optional { mid, light, dark, trunk } colors
function PixelArt.pine(tone)
	tone = tone or {}
	local mid = tone.mid or rgb(40, 102, 62)
	local light = tone.light or rgb(62, 134, 82)
	local dark = tone.dark or rgb(26, 76, 48)
	local trunk = tone.trunk or rgb(92, 62, 40)

	local root = Instance.new("Frame")
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Size = UDim2.fromOffset(14, 24)

	rect(root, 5, 20, 4, 4, trunk)
	local tiers = {
		{ top = 0, rows = 3, w0 = 2, w1 = 8 },
		{ top = 5, rows = 4, w0 = 4, w1 = 12 },
		{ top = 12, rows = 4, w0 = 6, w1 = 14 },
	}
	for _, t in ipairs(tiers) do
		for r = 0, t.rows - 1 do
			local w = t.w0 + (t.w1 - t.w0) * r / (t.rows - 1)
			w = math.floor(w / 2 + 0.5) * 2
			local x = (14 - w) / 2
			local y = t.top + r * 2
			rect(root, x, y, w, 2, mid)
			if w >= 4 then
				rect(root, x, y, 2, 2, light)
				rect(root, x + w - 2, y, 2, 2, dark)
			end
		end
	end
	return root
end

return PixelArt
