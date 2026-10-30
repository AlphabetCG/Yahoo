-- PixelArt: all the pixel-art sprites in the game, drawn with plain colored Frames.
-- (No image uploads needed. One "art pixel" = 1 unit; the screen scales it with a UIScale.)

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
	palette = function(opts)
		local c = opts.color or rgb(70, 190, 70)
		return {
			k = c:Lerp(Color3.new(0, 0, 0), 0.68),
			l = c:Lerp(Color3.new(1, 1, 1), 0.5),
			m = c,
			d = c:Lerp(Color3.new(0, 0, 0), 0.3),
			w = Color3.new(1, 1, 1),
			e = rgb(30, 30, 50),
		}
	end,
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

-- Returns a fresh copy of a sprite. opts: flip (mirror left-right), tier + color (Wisp)
function PixelArt.sprite(name, opts)
	opts = opts or {}
	local def = defs[name]
	assert(def, "PixelArt: unknown sprite " .. tostring(name))
	local key = name .. "|" .. tostring(opts.tier or 0) .. "|" .. (opts.flip and "f" or "n")
	local tpl = templates[key]
	if not tpl then
		local palette = type(def.palette) == "function" and def.palette(opts) or def.palette
		tpl = buildGrid(def.rows, palette, opts.flip)
		templates[key] = tpl
	end
	local copy = tpl:Clone()
	copy.Name = name
	return copy
end

-- Width and height of a sprite in art pixels
function PixelArt.size(name)
	local def = defs[name]
	return #def.rows[1], #def.rows
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
