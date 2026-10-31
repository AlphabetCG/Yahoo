-- SummonStage: the "CHARACTER SUMMON" animation shown over the SUMMON screen (BannerMenu), following
-- the reference in assets/x1_summon.gif and assets/x10_summon.gif:
--   1. a chest opens (x10: two chests)
--   2. x1: one long reel of character cards scrolls under a gold marker and slows down on the result
--      x10: ten small reels (01-10) that stop one after another; the stopped card gets a gold frame
--   3. x1: one big card with the rarity, light rays and sparkles
--      x10: a 5 x 2 grid of cards with rarity tags and a "1 LEGEND + 2 EPIC + 7 RARE" summary
-- SKIP jumps to step 3. Buttons under it: x1 SUMMON / x10 SUMMON (pull again) and BACK.
-- Only visuals: the results come from the server before the animation starts.

local TweenService = game:GetService("TweenService")

local SummonStage = {}

-- ui = the shared ui kit (see ClientMain), parent = the BannerMenu panel,
-- callbacks = { Pull = function(count), Back = function() }
function SummonStage.new(ui, parent, callbacks)
	local Config, PixelArt = ui.Config, ui.PixelArt
	local make, label, pixelButton, setButtonColor = ui.make, ui.label, ui.pixelButton, ui.setButtonColor
	local C = ui.colors
	local GOLD_LINE = C.rgb(176, 128, 64)
	local CARD_BG = C.rgb(36, 44, 64)

	local function tween(obj, seconds, props, style)
		local t = TweenService:Create(obj, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		t:Play()
		return t
	end

	-- ===== frame =====
	local stage = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.rgb(14, 18, 28), BorderSizePixel = 0, Visible = false, ZIndex = 30, Active = true }, parent)
	label(stage, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 40), Text = "CHARACTER SUMMON", TextSize = 34 })
	local subtitle = label(stage, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 22), Text = "", TextSize = 16, TextColor3 = C.TEXT_DIM })
	make("Frame", { Position = UDim2.fromOffset(30, 62), Size = UDim2.fromOffset(170, 3), BackgroundColor3 = GOLD_LINE, BorderSizePixel = 0 }, stage)
	make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 62), Size = UDim2.fromOffset(170, 3), BackgroundColor3 = GOLD_LINE, BorderSizePixel = 0 }, stage)
	local area = make("Frame", {
		Position = UDim2.fromOffset(20, 84), Size = UDim2.new(1, -40, 0, 390),
		BackgroundColor3 = C.rgb(24, 30, 46), BorderSizePixel = 0, ClipsDescendants = true,
	}, stage)
	make("UIStroke", { Color = C.rgb(60, 72, 100), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, area)
	local AREA_W, AREA_H = 760, 390

	local skipButton = pixelButton(stage, "SKIP", UDim2.fromOffset(90, 30), UDim2.new(1, -70, 0, 100), 15)
	local oneButton = pixelButton(stage, "X1 SUMMON", UDim2.fromOffset(220, 48), UDim2.new(0.5, -240, 1, -38), 20)
	local tenButton = pixelButton(stage, "X10 SUMMON", UDim2.fromOffset(220, 48), UDim2.new(0.5, 0, 1, -38), 20)
	local backButton = pixelButton(stage, "BACK", UDim2.fromOffset(180, 48), UDim2.new(0.5, 230, 1, -38), 20, C.RED_BTN, C.RED_EDGE, C.WHITE)

	local run = 0           -- changes every play; old animation steps stop themselves
	local skip = false
	local animating = false
	local lastCount = 1

	local function setButtons()
		local gold, idle = C.rgb(244, 196, 90), C.rgb(36, 46, 72)
		setButtonColor(oneButton, animating and C.GREY_BTN or (lastCount == 1 and gold or idle))
		setButtonColor(tenButton, animating and C.GREY_BTN or (lastCount == 10 and gold or idle))
		oneButton.TextColor3 = C.WHITE
		tenButton.TextColor3 = C.WHITE
		skipButton.Visible = animating
	end

	local function clear()
		area:ClearAllChildren()
	end

	-- a unit sprite at `px` screen pixels per art pixel, centred on `center`
	local function sprite(container, name, px, center)
		local w, h = PixelArt.size(name)
		local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.fromOffset(w * px, h * px), BackgroundTransparency = 1 }, container)
		local scaler = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, holder)
		make("UIScale", { Scale = px }, scaler)
		PixelArt.sprite(name).Parent = scaler
		return holder
	end

	-- a character card: sprite, (name), rarity-coloured bar at the bottom
	local function card(container, name, rarity, w, h, px, withName)
		local f = make("Frame", { Size = UDim2.fromOffset(w, h), BackgroundColor3 = CARD_BG, BorderSizePixel = 0 }, container)
		local stroke = make("UIStroke", { Color = C.rgb(70, 82, 110), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
		sprite(f, name, px, UDim2.new(0.5, 0, 0, withName and h * 0.44 or h * 0.45))
		if withName then
			label(f, { Position = UDim2.new(0, 0, 1, -34), Size = UDim2.new(1, 0, 0, 24), Text = string.upper(name), TextSize = 16 })
		end
		make("Frame", { Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Config.Rarities[rarity].Color, BorderSizePixel = 0 }, f)
		return f, stroke
	end

	-- a random unit for the reel filler, weighted by the banner's real chances (looks like the drops)
	local function fillerUnit(bannerId)
		local roll = math.random()
		local last
		for _, row in ipairs(Config.BannerRates(bannerId)) do
			for _, u in ipairs(row.Units) do
				last = { u.Name, row.Rarity }
				roll -= u.Chance
				if roll <= 0 then return u.Name, row.Rarity end
			end
		end
		return last[1], last[2]
	end

	-- waits in small steps; returns false if a newer play started
	local function wait(my, seconds)
		local t0 = os.clock()
		while os.clock() - t0 < seconds and not skip do
			task.wait(0.03)
			if run ~= my then return false end
		end
		return run == my
	end

	local function sparkles(container, center, count, color, radius)
		for _ = 1, count do
			local size = math.random(4, 8)
			local s = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = center, Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, BorderSizePixel = 0 }, container)
			local angle = math.random() * math.pi * 2
			local dist = radius * (0.5 + math.random() * 0.6)
			tween(s, 0.8 + math.random() * 0.5, {
				Position = center + UDim2.fromOffset(math.cos(angle) * dist, math.sin(angle) * dist),
				BackgroundTransparency = 1,
			})
		end
	end

	-- ===== 1. chest =====
	local function chestPhase(my, count)
		clear()
		local PX = 7
		local cx, cy = AREA_W / 2, 150
		local function chest(dx, dy, dark)
			local base = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(cx + dx, cy + dy), Size = UDim2.fromOffset(20 * PX, 8 * PX), BackgroundTransparency = 1 }, area)
			local bs = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, base)
			make("UIScale", { Scale = PX }, bs)
			PixelArt.sprite("ChestBase").Parent = bs
			local lid = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(cx + dx, cy + dy), Size = UDim2.fromOffset(20 * PX, 7 * PX), BackgroundTransparency = 1 }, area)
			local ls = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, lid)
			make("UIScale", { Scale = PX }, ls)
			PixelArt.sprite("ChestLid").Parent = ls
			if dark then
				make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.BLACK, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 5 }, base)
				make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.BLACK, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 5 }, lid)
			end
			return lid
		end
		if count == 10 then chest(-22, 14, true) end
		local lid = chest(0, 0, false)
		local text = label(area, { Position = UDim2.fromOffset(0, cy + 8 * PX + 34), Size = UDim2.new(1, 0, 0, 26), Text = ("X%d SUMMON"):format(count), TextSize = 20 })
		if not wait(my, 0.45) then return false end
		-- open: the lid jumps up, light rays and sparkles
		text.Text = "OPENING"
		text.TextColor3 = C.GOLD
		tween(lid, 0.35, { Position = lid.Position - UDim2.fromOffset(0, 26), Rotation = -6 }, Enum.EasingStyle.Back)
		for i = 0, 9 do
			local ray = make("Frame", {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(4, 10),
				Rotation = -70 + i * 15.5, BackgroundColor3 = C.GOLD, BorderSizePixel = 0,
			}, area)
			tween(ray, 0.6, { Size = UDim2.fromOffset(4, 70 + math.random(0, 40)), BackgroundTransparency = 0.4 })
		end
		sparkles(area, UDim2.fromOffset(cx, cy), 18, C.GOLD, 150)
		return wait(my, 1.0)
	end

	-- ===== 2. reels =====
	local function reelX1(my, result, bannerId)
		clear()
		local W, H, GAP = 150, 190, 12
		local STEP = W + GAP
		local COUNT, TARGET = 40, 34
		local strip = make("Frame", { Position = UDim2.fromOffset(0, 95), Size = UDim2.fromOffset(COUNT * STEP, H), BackgroundTransparency = 1 }, area)
		local targetStroke
		for i = 1, COUNT do
			local name, rarity = fillerUnit(bannerId)
			if i == TARGET then name, rarity = result.Unit, result.Rarity end
			local f, stroke = card(strip, name, rarity, W, H, 4, true)
			f.Position = UDim2.fromOffset((i - 1) * STEP, 0)
			if i == TARGET then targetStroke = stroke end
		end
		-- gold marker in the middle
		make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(AREA_W / 2, 70), Size = UDim2.fromOffset(4, H + 50), BackgroundColor3 = C.GOLD, BorderSizePixel = 0, ZIndex = 5 }, area)
		for _, y in ipairs({ 66, H + 120 }) do
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(AREA_W / 2, y), Size = UDim2.fromOffset(18, 10), BackgroundColor3 = C.GOLD, BorderSizePixel = 0, ZIndex = 5 }, area)
		end
		local jitter = math.random(-W / 3, W / 3)
		local finalX = AREA_W / 2 - ((TARGET - 1) * STEP + W / 2) + jitter
		tween(strip, 3.4, { Position = UDim2.fromOffset(finalX, 95) }, Enum.EasingStyle.Quint)
		if not wait(my, 3.5) then return false end
		if targetStroke then
			targetStroke.Color = C.GOLD
			targetStroke.Thickness = 4
		end
		return wait(my, 0.5)
	end

	local function reelX10(my, results, bannerId)
		clear()
		local W, H, GAP = 64, 52, 6
		local STEP = W + GAP
		local COUNT, TARGET = 26, 20
		local REEL_W = 312
		local longest = 0
		for i, result in ipairs(results) do
			local col, row = (i - 1) % 2, (i - 1) // 2
			local x0, y0 = 12 + col * 376, 14 + row * 74
			label(area, { Position = UDim2.fromOffset(x0, y0), Size = UDim2.fromOffset(34, H), Text = ("%02d"):format(i), TextSize = 16, TextColor3 = C.TEXT_DIM })
			local window = make("Frame", { Position = UDim2.fromOffset(x0 + 38, y0), Size = UDim2.fromOffset(REEL_W, H), BackgroundTransparency = 1, ClipsDescendants = true }, area)
			local strip = make("Frame", { Size = UDim2.fromOffset(COUNT * STEP, H), BackgroundTransparency = 1 }, window)
			local targetStroke
			for k = 1, COUNT do
				local name, rarity = fillerUnit(bannerId)
				if k == TARGET then name, rarity = result.Unit, result.Rarity end
				local f, stroke = card(strip, name, rarity, W, H, 2, false)
				f.Position = UDim2.fromOffset((k - 1) * STEP, 0)
				if k == TARGET then targetStroke = stroke end
			end
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(REEL_W / 2, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C.GOLD, BorderSizePixel = 0, ZIndex = 5 }, window)
			local finalX = REEL_W / 2 - ((TARGET - 1) * STEP + W / 2) + math.random(-W / 4, W / 4)
			local duration = 1.8 + (i - 1) * 0.18 -- they stop one after another
			longest = math.max(longest, duration)
			local t = tween(strip, duration, { Position = UDim2.fromOffset(finalX, 0) }, Enum.EasingStyle.Quint)
			t.Completed:Connect(function()
				if targetStroke and targetStroke.Parent then
					targetStroke.Color = C.GOLD
					targetStroke.Thickness = 3
				end
			end)
		end
		if not wait(my, longest + 0.1) then return false end
		return wait(my, 0.6)
	end

	-- ===== 3. results =====
	local function finalX1(result)
		clear()
		subtitle.Text = "SUMMON COMPLETE"
		local rarity = Config.Rarities[result.Rarity]
		local box = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(AREA_W / 2, AREA_H / 2), Size = UDim2.fromOffset(320, 330), BackgroundColor3 = C.rgb(16, 20, 32), BorderSizePixel = 0 }, area)
		make("UIStroke", { Color = rarity.Color:Lerp(C.BLACK, 0.3), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, box)
		make("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 3), BackgroundColor3 = rarity.Color, BorderSizePixel = 0 }, box)
		make("Frame", { Position = UDim2.new(0, 14, 1, -17), Size = UDim2.new(1, -28, 0, 3), BackgroundColor3 = rarity.Color, BorderSizePixel = 0 }, box)
		label(box, { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28), Text = string.upper(result.Rarity), TextSize = 22, TextColor3 = rarity.Color })
		-- slowly turning light rays behind the character
		local rays = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(160, 165), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, box)
		for i = 0, 7 do
			make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(4, 110), Rotation = i * 45, BackgroundColor3 = C.rgb(70, 80, 110), BackgroundTransparency = 0.3, BorderSizePixel = 0 }, rays)
		end
		TweenService:Create(rays, TweenInfo.new(12, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
		local art = sprite(box, result.Unit, 8, UDim2.fromOffset(160, 168))
		local pop = make("UIScale", { Scale = 0.4 }, art)
		tween(pop, 0.5, { Scale = 1 }, Enum.EasingStyle.Back)
		label(box, { Position = UDim2.new(0, 0, 1, -54), Size = UDim2.new(1, 0, 0, 28), Text = string.upper(result.Unit), TextSize = 22 })
		if result.New then
			label(box, { Position = UDim2.fromOffset(20, 50), Size = UDim2.fromOffset(60, 20), Text = "NEW!", TextSize = 16, TextColor3 = C.GREEN })
		end
		if result.Pity then
			label(box, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 50), Size = UDim2.fromOffset(60, 20), Text = "PITY", TextSize = 16, TextColor3 = C.GOLD })
		end
		sparkles(area, UDim2.fromOffset(AREA_W / 2, AREA_H / 2), rarity.Order >= 3 and 26 or 12, rarity.Color, 260)
	end

	local function finalX10(results)
		clear()
		subtitle.Text = ("%d CHARACTERS SUMMONED"):format(#results)
		local W, H, GAP = 136, 140, 10
		local x0 = (AREA_W - (5 * W + 4 * GAP)) / 2
		local counts = {}
		for i, r in ipairs(results) do
			local rarity = Config.Rarities[r.Rarity]
			counts[r.Rarity] = (counts[r.Rarity] or 0) + 1
			local col, row = (i - 1) % 5, (i - 1) // 5
			local f = make("Frame", { Position = UDim2.fromOffset(x0 + col * (W + GAP), 18 + row * (H + 14)), Size = UDim2.fromOffset(W, H), BackgroundColor3 = CARD_BG, BorderSizePixel = 0 }, area)
			make("UIStroke", { Color = rarity.Color, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
			make("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = C.rgb(20, 26, 40), BorderSizePixel = 0 }, f)
			label(f, { Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(80, 20), Text = rarity.Short or string.upper(r.Rarity), TextSize = 13, TextColor3 = rarity.Color, TextXAlignment = Enum.TextXAlignment.Left })
			if r.New then
				label(f, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.fromOffset(40, 20), Text = "NEW", TextSize = 12, TextColor3 = C.GREEN, TextXAlignment = Enum.TextXAlignment.Right })
			end
			sprite(f, r.Unit, 3, UDim2.new(0.5, 0, 0, 72))
			label(f, { Position = UDim2.new(0, 0, 1, -26), Size = UDim2.new(1, 0, 0, 22), Text = string.upper(r.Unit), TextSize = 15 })
			local pop = make("UIScale", { Scale = 0 }, f)
			task.delay((i - 1) * 0.06, function()
				tween(pop, rarity.Order >= 3 and 0.45 or 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end)
			if rarity.Order >= 3 then
				sparkles(area, UDim2.fromOffset(x0 + col * (W + GAP) + W / 2, 18 + row * (H + 14) + H / 2), 10, rarity.Color, 90)
			end
		end
		-- "1 LEGEND + 2 EPIC + 7 RARE", rarest first
		local parts = {}
		for _, name in ipairs(Config.RarityOrder) do
			if counts[name] then table.insert(parts, 1, ("%d %s"):format(counts[name], Config.Rarities[name].Short or name)) end
		end
		label(area, { Position = UDim2.new(0, 0, 1, -40), Size = UDim2.new(1, 0, 0, 26), Text = table.concat(parts, "  +  "), TextSize = 18, TextColor3 = C.TEXT_DIM })
	end

	-- ===== play =====
	local api = {}

	-- results from the server; count = 1 or 10
	function api.play(results, count, bannerId)
		run += 1
		local my = run
		skip = false
		animating = true
		lastCount = count
		stage.Visible = true
		subtitle.Text = ("X%d - SUMMONING"):format(count)
		setButtons()
		task.spawn(function()
			local ok = chestPhase(my, count)
			if run ~= my then return end
			if ok and not skip then
				if count == 1 then reelX1(my, results[1], bannerId) else reelX10(my, results, bannerId) end
			end
			if run ~= my then return end
			if count == 1 then finalX1(results[1]) else finalX10(results) end
			animating = false
			setButtons()
		end)
	end

	function api.hide()
		run += 1
		animating = false
		stage.Visible = false
		clear()
	end

	function api.isOpen()
		return stage.Visible
	end

	skipButton.MouseButton1Click:Connect(function() skip = true end)
	oneButton.MouseButton1Click:Connect(function()
		if not animating then callbacks.Pull(1) end
	end)
	tenButton.MouseButton1Click:Connect(function()
		if not animating then callbacks.Pull(10) end
	end)
	backButton.MouseButton1Click:Connect(function()
		api.hide()
		callbacks.Back()
	end)
	setButtons()
	return api
end

return SummonStage
