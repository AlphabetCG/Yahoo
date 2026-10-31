-- BannerMenu: the SUMMON screen (main menu). Lists the open banners (Config.Banners), shows the
-- featured unit, time left, chances (RATES popup) and pity progress, and pulls x1 / x10. The results
-- play in the CHARACTER SUMMON animation (SummonStage module). The server rolls (ServerScriptService.Banners
-- via the Summon remote).
-- ClientMain passes its UI helpers in (ui table), like PlayMenu.

local BannerMenu = {}

function BannerMenu.init(ui)
	local Config, Remote, PixelArt = ui.Config, ui.Remote, ui.PixelArt
	local make, label, pixelButton, pixelPanel, setButtonColor, fmt = ui.make, ui.label, ui.pixelButton, ui.pixelPanel, ui.setButtonColor, ui.fmt
	local C = ui.colors

	local W, H = 800, 560
	local profile = nil
	local selected = nil
	local busy = false

	local function now()
		return math.floor(workspace:GetServerTimeNow())
	end

	local function openBanners()
		local list = {}
		for _, id in ipairs(Config.BannerOrder) do
			if Config.BannerActive(id, now()) then table.insert(list, id) end
		end
		return list
	end

	-- ===== frame =====
	local dim = make("TextButton", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.BLACK, BackgroundTransparency = 0.45,
		BorderSizePixel = 0, Text = "", AutoButtonColor = false, Visible = false,
	}, ui.popupGui)
	local panel = pixelPanel(dim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H), Active = true })
	local scale = make("UIScale", { Scale = 1 }, panel)
	local function fit()
		local size = dim.AbsoluteSize
		if size.X > 0 then scale.Scale = math.min(1, (size.X - 24) / W, (size.Y - 24) / H) end
	end
	dim:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	label(panel, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 40), Text = "SUMMON", TextSize = 34, TextColor3 = C.GOLD })
	local gemsLabel = label(panel, {
		Position = UDim2.fromOffset(24, 20), Size = UDim2.fromOffset(240, 30), Text = "", TextSize = 20,
		TextColor3 = C.rgb(120, 220, 255), TextXAlignment = Enum.TextXAlignment.Left,
	})
	local closeButton = pixelButton(panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -38, 0, 34), 20, C.RED_BTN, C.RED_EDGE, C.WHITE)
	local message = label(panel, { Position = UDim2.new(0, 20, 1, -40), Size = UDim2.new(1, -40, 0, 26), TextSize = 17, TextColor3 = C.TEXT_DIM, Text = "" })
	local function say(text, color)
		message.Text = text or ""
		message.TextColor3 = color or C.TEXT_DIM
	end

	local tabs = make("Frame", { Position = UDim2.fromOffset(20, 72), Size = UDim2.fromOffset(200, 420), BackgroundTransparency = 1 }, panel)
	make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tabs)
	local body = make("Frame", { Position = UDim2.fromOffset(236, 72), Size = UDim2.fromOffset(544, 430), BackgroundTransparency = 1 }, panel)

	-- sprite of a unit, `px` screen pixels per art pixel
	local function sprite(parent, name, px, center)
		local w, h = PixelArt.size(name)
		local holder = make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = center,
			Size = UDim2.fromOffset(w * px, h * px), BackgroundTransparency = 1,
		}, parent)
		local scaler = make("Frame", { Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1 }, holder)
		make("UIScale", { Scale = px }, scaler)
		PixelArt.sprite(name).Parent = scaler
		return holder
	end

	local function percent(x)
		local p = x * 100
		if p >= 10 then return ("%.0f%%"):format(p) end
		if p >= 1 then return (("%.1f"):format(p):gsub("%.0$", "")) .. "%" end
		return (("%.2f"):format(p):gsub("0$", "")) .. "%"
	end

	local function timeLeft(banner)
		if not banner.EndsAt then return "ALWAYS AVAILABLE" end
		local left = math.max(0, banner.EndsAt - now())
		local d, h, m = left // 86400, (left % 86400) // 3600, (left % 3600) // 60
		if d > 0 then return ("ENDS IN %dD %dH"):format(d, h) end
		if h > 0 then return ("ENDS IN %dH %dM"):format(h, m) end
		return ("ENDS IN %dM"):format(m)
	end

	local show -- the banner page; defined below

	-- ===== rates popup =====
	local ratesBox = pixelPanel(panel, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(460, 420), Visible = false, ZIndex = 20 })
	local ratesTitle = label(ratesBox, { Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 30), TextSize = 22, TextColor3 = C.GOLD, Text = "RATES", ZIndex = 21 })
	local ratesList = make("ScrollingFrame", {
		Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 1, -120), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 21,
	}, ratesBox)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, ratesList)
	local ratesClose = pixelButton(ratesBox, "OK", UDim2.fromOffset(140, 44), UDim2.new(0.5, 0, 1, -38), 20)
	ratesClose.ZIndex = 21
	ratesClose.MouseButton1Click:Connect(function() ratesBox.Visible = false end)

	local function showRates(bannerId)
		local banner = Config.Banners[bannerId]
		ratesTitle.Text = string.upper(banner.Name) .. " - RATES"
		for _, c in ipairs(ratesList:GetChildren()) do
			if c:IsA("TextLabel") then c:Destroy() end
		end
		local order = 0
		local function line(text, color, size)
			order += 1
			label(ratesList, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, size + 8), Text = text, TextSize = size, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21 })
		end
		for _, row in ipairs(Config.BannerRates(bannerId)) do
			line(("%s   %s"):format(string.upper(row.Rarity), percent(row.Chance)), Config.Rarities[row.Rarity].Color, 18)
			for _, u in ipairs(row.Units) do
				local featured = banner.Featured and banner.Featured[row.Rarity] == u.Name
				line(("    %s%s   %s"):format(string.upper(u.Name), featured and " (RATE UP)" or "", percent(u.Chance)), C.WHITE, 14)
			end
		end
		for rarity, limit in pairs(banner.Pity or {}) do
			if #Config.BannerPool(bannerId, rarity) > 0 then
				line(("Pity: a %s is guaranteed within %d pulls"):format(rarity, limit), C.TEXT_DIM, 13)
			end
		end
		ratesBox.Visible = true
	end

	-- ===== summon animation (SummonStage module: chest > reels > results) =====
	local pull -- defined below
	local stage = require(script.Parent:WaitForChild("SummonStage")).new(ui, panel, {
		Pull = function(count) pull(selected, count) end,
		Back = function() show() end, -- gems and pity counters changed
	})

	-- ===== banner page =====
	pull = function(bannerId, count)
		if busy then return end
		busy = true
		say("")
		local ok, success, result = pcall(function() return Remote.Summon:InvokeServer(bannerId, count) end)
		busy = false
		if not ok then
			say("Something went wrong, try again", C.RED)
		elseif not success then
			say(tostring(result or "Summon failed"), C.RED)
		elseif typeof(result) == "table" and result.Results then
			stage.play(result.Results, count, bannerId)
		end
	end

	local function showBanner(bannerId)
		for _, c in ipairs(body:GetChildren()) do c:Destroy() end
		local banner = Config.Banners[bannerId]
		local color = banner.Color or C.GOLD

		local art = make("Frame", { Size = UDim2.new(1, 0, 0, 230), BackgroundColor3 = color:Lerp(C.BLACK, 0.55), BorderSizePixel = 0 }, body)
		make("UIStroke", { Color = color, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, art)
		label(art, { Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 34), Text = string.upper(banner.Name), TextSize = 28, TextColor3 = C.WHITE, TextXAlignment = Enum.TextXAlignment.Left })
		label(art, { Position = UDim2.fromOffset(16, 44), Size = UDim2.new(1, -32, 0, 22), Text = timeLeft(banner), TextSize = 16, TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Left })

		-- featured unit (rarest), or a row of what can drop
		local featuredName, featuredRarity = nil, nil
		for rarity, name in pairs(banner.Featured or {}) do
			if Config.Units[name] and (not featuredRarity or Config.Rarities[rarity].Order > Config.Rarities[featuredRarity].Order) then
				featuredName, featuredRarity = name, rarity
			end
		end
		if featuredName then
			sprite(art, featuredName, 6, UDim2.new(0, 120, 0, 150))
			label(art, {
				Position = UDim2.fromOffset(230, 96), Size = UDim2.fromOffset(290, 30), Text = "RATE UP", TextSize = 18,
				TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Left,
			})
			label(art, {
				Position = UDim2.fromOffset(230, 124), Size = UDim2.fromOffset(290, 36), Text = string.upper(featuredName), TextSize = 30,
				TextColor3 = Config.Rarities[featuredRarity].Color, TextXAlignment = Enum.TextXAlignment.Left,
			})
			label(art, {
				Position = UDim2.fromOffset(230, 160), Size = UDim2.fromOffset(290, 24),
				Text = ("%s - %d%% of %s pulls"):format(string.upper(featuredRarity), math.floor((banner.RateUp or 0.5) * 100 + 0.5), featuredRarity), TextSize = 14,
				TextColor3 = C.TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Left,
			})
		else
			local x = 0
			for _, row in ipairs(Config.BannerRates(bannerId)) do
				for _, u in ipairs(row.Units) do
					sprite(art, u.Name, 3, UDim2.new(0, 60 + x * 96, 0, 150))
					x += 1
				end
			end
		end

		-- chances in one line
		local parts = {}
		for _, row in ipairs(Config.BannerRates(bannerId)) do
			table.insert(parts, ('<font color="#%s">%s %s</font>'):format(Config.Rarities[row.Rarity].Color:ToHex(), string.upper(row.Rarity), percent(row.Chance)))
		end
		label(body, { Position = UDim2.fromOffset(0, 240), Size = UDim2.new(1, -110, 0, 26), RichText = true, Text = table.concat(parts, "   "), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left })
		local ratesButton = pixelButton(body, "RATES", UDim2.fromOffset(100, 32), UDim2.new(1, -50, 0, 253), 15)
		ratesButton.MouseButton1Click:Connect(function() showRates(bannerId) end)

		-- pity progress
		local counters = profile and profile.Summon and profile.Summon.Pity and profile.Summon.Pity[bannerId] or {}
		local pityLines = {}
		for _, row in ipairs(Config.BannerRates(bannerId)) do
			local limit = banner.Pity and banner.Pity[row.Rarity]
			if limit then
				table.insert(pityLines, ("%s GUARANTEED WITHIN %d PULLS"):format(string.upper(row.Rarity), limit - (counters[row.Rarity] or 0)))
			end
		end
		label(body, { Position = UDim2.fromOffset(0, 276), Size = UDim2.new(1, 0, 0, 44), Text = table.concat(pityLines, "\n"), TextSize = 15, TextColor3 = C.TEXT_DIM, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })

		-- pull buttons
		local gems = profile and profile.Gems or 0
		local one = pixelButton(body, ("x1   %s GEMS"):format(fmt(banner.Cost)), UDim2.fromOffset(250, 64), UDim2.new(0, 130, 0, 370), 22, C.GREEN_BTN, C.GREEN_EDGE, C.WHITE)
		local ten = pixelButton(body, ("x10   %s GEMS"):format(fmt(banner.Cost10)), UDim2.fromOffset(250, 64), UDim2.new(1, -130, 0, 370), 22, C.GREEN_BTN, C.GREEN_EDGE, C.WHITE)
		setButtonColor(one, gems >= banner.Cost and C.GREEN_BTN or C.GREY_BTN)
		setButtonColor(ten, gems >= banner.Cost10 and C.GREEN_BTN or C.GREY_BTN)
		one.MouseButton1Click:Connect(function() pull(bannerId, 1) end)
		ten.MouseButton1Click:Connect(function() pull(bannerId, 10) end)
	end

	show = function()
		gemsLabel.Text = "GEMS: " .. fmt(profile and profile.Gems or 0)
		for _, c in ipairs(tabs:GetChildren()) do
			if c:IsA("GuiButton") then c:Destroy() end
		end
		local list = openBanners()
		if not table.find(list, selected or "") then selected = list[1] end
		for i, id in ipairs(list) do
			local banner = Config.Banners[id]
			local tab = pixelButton(tabs, string.upper(banner.Name), UDim2.new(1, 0, 0, 56), UDim2.new(), 16)
			tab.AnchorPoint = Vector2.new(0, 0)
			tab.LayoutOrder = i
			tab.TextWrapped = true
			setButtonColor(tab, id == selected and (banner.Color or C.GREEN_BTN) or C.BTN)
			tab.MouseButton1Click:Connect(function()
				selected = id
				ratesBox.Visible = false
				show()
			end)
		end
		if selected then showBanner(selected) end
	end

	local function close()
		dim.Visible = false
		ratesBox.Visible = false
		stage.hide()
	end
	closeButton.MouseButton1Click:Connect(close)

	-- ===== API for ClientMain =====
	local api = {}
	function api.open(bannerId)
		say("")
		selected = bannerId or selected
		dim.Visible = true
		fit()
		show()
	end
	function api.close()
		close()
	end
	function api.setProfile(p)
		profile = p
		if dim.Visible and not stage.isOpen() then show() end
		if dim.Visible then gemsLabel.Text = "GEMS: " .. fmt(p.Gems or 0) end
	end
	return api
end

return BannerMenu
