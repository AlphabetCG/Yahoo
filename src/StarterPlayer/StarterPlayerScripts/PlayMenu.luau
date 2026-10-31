-- PlayMenu: the PLAY flow on the main menu.
--   Select Mode > Select Map > Select Stage > Create Lobby (Public / Friends / Invite) or Matchmaking
--   > lobby room: invite players, the host presses START.
-- Also shows lobby invites from other players. The server side is ServerScriptService.Lobby.
-- ClientMain passes its UI helpers in (ui table), so this module looks like the rest of the game.

local Players = game:GetService("Players")

local PlayMenu = {}

function PlayMenu.init(ui)
	local Config, Remote, player = ui.Config, ui.Remote, ui.player
	local make, label, pixelButton, pixelPanel, setButtonColor, fmt = ui.make, ui.label, ui.pixelButton, ui.pixelPanel, ui.setButtonColor, ui.fmt
	local C = ui.colors

	local W, H = 780, 560
	local profile = nil
	local lobby = { MyRoom = nil, Rooms = {} } -- from the server (LobbyState)
	local screen = "Mode"
	local selMode, selMap, selStage = nil, nil, nil
	local privacy = "Public"
	local busy = false

	-- ===== frame =====
	local dim = make("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.BLACK,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
	}, ui.popupGui)
	local panel = pixelPanel(dim, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		Active = true,
	})
	local scale = make("UIScale", { Scale = 1 }, panel)
	local function fit()
		local size = dim.AbsoluteSize
		if size.X > 0 then scale.Scale = math.min(1, (size.X - 24) / W, (size.Y - 24) / H) end
	end
	dim:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)

	local title = label(panel, { Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 40), TextSize = 32, TextColor3 = C.GOLD, Text = "" })
	local backButton = pixelButton(panel, "< BACK", UDim2.fromOffset(110, 40), UDim2.new(0, 78, 0, 34), 18)
	local closeButton = pixelButton(panel, "X", UDim2.fromOffset(40, 40), UDim2.new(1, -38, 0, 34), 20, C.RED_BTN, C.RED_EDGE, C.WHITE)
	local content = make("Frame", { Position = UDim2.fromOffset(24, 72), Size = UDim2.new(1, -48, 0, 440), BackgroundTransparency = 1 }, panel)
	local message = label(panel, { Position = UDim2.new(0, 20, 1, -40), Size = UDim2.new(1, -40, 0, 26), TextSize = 18, TextColor3 = C.TEXT_DIM, Text = "" })

	local function say(text, color)
		message.Text = text or ""
		message.TextColor3 = color or C.TEXT_DIM
	end

	-- calls a lobby RemoteFunction; shows the server's message
	local function call(remote, ...)
		if busy then return false end
		busy = true
		local args = table.pack(...)
		local ok, success, msg = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
		busy = false
		if not ok then
			say("Something went wrong, try again", C.RED)
			return false
		end
		if not success then say(tostring(msg or "Not possible"), C.RED) elseif msg then say(tostring(msg), C.GREEN) end
		return success
	end

	local function clear()
		content:ClearAllChildren()
	end

	-- a big clickable card
	local function card(parent, props)
		local b = make("TextButton", {
			Position = props.Position,
			Size = props.Size,
			BackgroundColor3 = props.Locked and C.rgb(36, 42, 62) or C.PANEL_LIGHT,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
		}, parent)
		make("UIStroke", { Color = props.Color or C.PANEL_EDGE, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
		make("Frame", { Size = UDim2.new(0, 8, 1, 0), BackgroundColor3 = props.Color or C.PANEL_EDGE, BorderSizePixel = 0 }, b)
		label(b, {
			Position = UDim2.fromOffset(22, 8), Size = UDim2.new(1, -30, 0, 30),
			Text = props.Title, TextSize = props.TitleSize or 26, TextColor3 = props.Locked and C.TEXT_DIM or C.WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		if props.Sub then
			label(b, {
				Position = UDim2.fromOffset(22, 40), Size = UDim2.new(1, -30, 1, -46),
				Text = props.Sub, TextSize = 15, TextColor3 = C.TEXT_DIM, TextWrapped = true, RichText = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			})
		end
		if props.OnClick then b.MouseButton1Click:Connect(props.OnClick) end
		return b
	end

	local function rulesText(stage)
		local r = stage.Rules or {}
		local parts = {}
		if r.EnemySpeed then table.insert(parts, ("enemies %d%% faster"):format(math.floor((r.EnemySpeed - 1) * 100 + 0.5))) end
		if r.EnemyHealth then table.insert(parts, ("enemies %d%% tougher"):format(math.floor((r.EnemyHealth - 1) * 100 + 0.5))) end
		if r.StartMoney then table.insert(parts, "start money $" .. fmt(r.StartMoney)) end
		if r.Rarities then
			local list = {}
			for rarity in pairs(r.Rarities) do table.insert(list, rarity) end
			table.sort(list)
			table.insert(parts, "only " .. table.concat(list, " / ") .. " units")
		end
		if r.BossEvery then
			table.insert(parts, r.BossEvery == 1 and "a boss every round" or ("a boss every %d rounds"):format(r.BossEvery))
		end
		return table.concat(parts, ", ")
	end

	local function stageLine(stageId)
		local stage = Config.Stages[stageId]
		local difficulty = Config.Difficulties[stage.Difficulty]
		return ("%s  -  %s  -  %s"):format(
			string.upper(Config.Modes[stage.Mode].Name),
			string.upper(Config.Maps[stage.Map].Name),
			string.upper(stage.Name) .. " (" .. string.upper(difficulty.Name) .. ")")
	end

	local function isLocked(stageId)
		local required = Config.StageRequirement(stageId)
		return required ~= nil and not (profile and profile.Progress and profile.Progress[required])
	end

	local show -- show(screenName), defined below

	-- ===== Select Mode =====
	local function showModes()
		title.Text = "SELECT MODE"
		backButton.Visible = false
		for i, mode in ipairs(Config.ModeOrder) do
			local def = Config.Modes[mode]
			local col, row = (i - 1) % 2, (i - 1) // 2
			card(content, {
				Position = UDim2.fromOffset(col * 372, row * 210),
				Size = UDim2.fromOffset(356, 196),
				Title = string.upper(def.Name),
				TitleSize = 30,
				Sub = def.Desc,
				Color = def.Color,
				OnClick = function()
					selMode = mode
					show("Map")
				end,
			})
		end
	end

	-- ===== Select Map =====
	local function showMaps()
		title.Text = "SELECT MAP"
		backButton.Visible = true
		for i, map in ipairs(Config.MapOrder) do
			local def = Config.Maps[map]
			local count = #Config.StagesFor(selMode, map)
			card(content, {
				Position = UDim2.fromOffset(((i - 1) % 2) * 372, ((i - 1) // 2) * 150),
				Size = UDim2.fromOffset(356, 136),
				Title = string.upper(def.Name),
				Sub = count > 0 and (count .. (count == 1 and " stage" or " stages")) or "No stages in this mode yet",
				Color = def.Color,
				Locked = count == 0,
				OnClick = function()
					if count == 0 then return end
					selMap = map
					show("Stage")
				end,
			})
		end
	end

	-- ===== Select Stage =====
	local function showStages()
		title.Text = string.upper(Config.Modes[selMode].Name) .. ": " .. string.upper(Config.Maps[selMap].Name)
		backButton.Visible = true
		local list = make("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
		}, content)
		make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		make("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4) }, list)
		for i, stageId in ipairs(Config.StagesFor(selMode, selMap)) do
			local stage = Config.Stages[stageId]
			local difficulty = Config.Difficulties[stage.Difficulty]
			local locked = isLocked(stageId)
			local cleared = profile and profile.Progress and profile.Progress[stageId]
			local rewards = (difficulty.Rewards or 1) * (stage.Rewards or 1)
			local lines = {
				('<font color="#%s">%s</font>   %s   rewards x%s%s'):format(
					difficulty.Color:ToHex(), string.upper(difficulty.Name),
					stage.Rounds == 0 and "ENDLESS" or (stage.Rounds .. " ROUNDS"),
					(("%.1f"):format(rewards):gsub("%.0$", "")), cleared and "   CLEARED" or ""),
			}
			local rules = rulesText(stage)
			if rules ~= "" then table.insert(lines, rules) end
			if locked then table.insert(lines, "Clear " .. Config.Stages[Config.StageRequirement(stageId)].Name .. " first") end
			local c = card(list, {
				Size = UDim2.new(1, 0, 0, 96),
				Title = string.upper(stage.Name),
				Sub = table.concat(lines, "\n"),
				Color = difficulty.Color,
				Locked = locked,
				OnClick = function()
					if locked then
						say("Clear " .. Config.Stages[Config.StageRequirement(stageId)].Name .. " first", C.RED)
						return
					end
					selStage = stageId
					show("Lobby")
				end,
			})
			c.LayoutOrder = i
		end
	end

	-- privacy buttons: Public / Friends / Invite
	local function privacyRow(parent, y, current, onPick, enabled)
		label(parent, { Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(120, 36), Text = "PRIVACY", TextSize = 18, TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local names = { Public = "PUBLIC", Friends = "FRIENDS", Invite = "INVITE ONLY" }
		for i, option in ipairs(Config.LobbyPrivacy) do
			local b = pixelButton(parent, names[option], UDim2.fromOffset(160, 36), UDim2.fromOffset(200 + (i - 1) * 172, y + 18), 16)
			setButtonColor(b, option == current and C.GREEN_BTN or (enabled and C.BTN or C.GREY_BTN))
			if enabled then b.MouseButton1Click:Connect(function() onPick(option) end) end
		end
	end

	-- ===== Create Lobby / Matchmaking =====
	local function showLobbyChoice()
		title.Text = "PLAY"
		backButton.Visible = true
		label(content, { Size = UDim2.new(1, 0, 0, 28), Text = stageLine(selStage), TextSize = 18, TextColor3 = C.WHITE })
		privacyRow(content, 44, privacy, function(option)
			privacy = option
			show("Lobby")
		end, true)
		label(content, {
			Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 20), TextSize = 14, TextColor3 = C.TEXT_DIM,
			Text = privacy == "Public" and "Anyone can join, and matchmaking can fill your lobby."
				or (privacy == "Friends" and "Only your friends can see and join your lobby." or "Only players you invite can join."),
		})
		local createButton = pixelButton(content, "CREATE LOBBY", UDim2.fromOffset(330, 60), UDim2.new(0.5, -175, 0, 140), 26, C.GREEN_BTN, C.GREEN_EDGE, C.WHITE)
		local matchButton = pixelButton(content, "MATCHMAKING", UDim2.fromOffset(330, 60), UDim2.new(0.5, 175, 0, 140), 26)
		createButton.MouseButton1Click:Connect(function()
			call(Remote.LobbyCreate, selStage, privacy)
		end)
		matchButton.MouseButton1Click:Connect(function()
			call(Remote.LobbyMatchmake, selStage)
		end)

		-- lobbies for this stage you can join (public ones, your friends', ones you were invited to)
		label(content, { Position = UDim2.fromOffset(0, 190), Size = UDim2.new(1, 0, 0, 26), Text = "OPEN LOBBIES", TextSize = 20, TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local list = make("ScrollingFrame", {
			Position = UDim2.fromOffset(0, 220), Size = UDim2.new(1, 0, 0, 210),
			BackgroundColor3 = C.rgb(20, 24, 40), BorderSizePixel = 0, ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		}, content)
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14) }, list)
		local any = false
		for i, room in ipairs(lobby.Rooms) do
			if room.StageId == selStage then
				any = true
				local row = make("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.PANEL_LIGHT, BorderSizePixel = 0 }, list)
				label(row, {
					Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -150, 1, 0), TextSize = 17,
					Text = ("%s's lobby   %d/%d   %s"):format(room.HostName, #room.Members, Config.MaxPartySize, string.upper(room.Privacy)),
					TextXAlignment = Enum.TextXAlignment.Left,
				})
				local joinButton = pixelButton(row, "JOIN", UDim2.fromOffset(110, 34), UDim2.new(1, -62, 0.5, 0), 18, C.GREEN_BTN, C.GREEN_EDGE, C.WHITE)
				joinButton.MouseButton1Click:Connect(function() call(Remote.LobbyJoin, room.Id) end)
			end
		end
		if not any then
			label(list, { Size = UDim2.new(1, 0, 0, 40), Text = "No open lobbies for this stage yet", TextSize = 16, TextColor3 = C.TEXT_DIM })
		end
	end

	-- ===== Lobby room =====
	local function showRoom()
		local room = lobby.MyRoom
		if not room then return show("Mode") end
		local isHost = room.HostId == player.UserId
		title.Text = isHost and "YOUR LOBBY" or (string.upper(room.HostName) .. "'S LOBBY")
		backButton.Visible = false
		label(content, { Size = UDim2.new(1, 0, 0, 28), Text = stageLine(room.StageId), TextSize = 18, TextColor3 = C.WHITE })
		privacyRow(content, 40, room.Privacy, function(option) Remote.LobbySetPrivacy:FireServer(option) end, isHost)

		-- members
		label(content, { Position = UDim2.fromOffset(0, 92), Size = UDim2.fromOffset(340, 26), Text = ("PLAYERS  %d/%d"):format(#room.Members, Config.MaxPartySize), TextSize = 20, TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		for i = 1, Config.MaxPartySize do
			local m = room.Members[i]
			local row = make("Frame", {
				Position = UDim2.fromOffset(0, 120 + (i - 1) * 46), Size = UDim2.fromOffset(340, 40),
				BackgroundColor3 = (m and m.UserId == player.UserId) and C.PANEL_LIGHT or C.rgb(24, 28, 44), BorderSizePixel = 0,
			}, content)
			if m and m.Color and Config.PlayerColors[m.Color] then
				make("Frame", { Position = UDim2.fromOffset(6, 8), Size = UDim2.fromOffset(8, 24), BackgroundColor3 = Config.PlayerColors[m.Color], BorderSizePixel = 0 }, row)
			end
			label(row, {
				Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -100, 1, 0), TextSize = 17,
				Text = m and m.Name or "- empty -", TextColor3 = m and C.WHITE or C.TEXT_DIM,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
			})
			if m then
				label(row, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(80, 40), TextSize = 14,
					Text = (m.UserId == room.HostId and "HOST" or "") .. (m.UserId == player.UserId and (m.UserId == room.HostId and " YOU" or "YOU") or ""),
					TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Right,
				})
			end
		end

		-- invite players in this server (host only)
		label(content, { Position = UDim2.fromOffset(372, 92), Size = UDim2.fromOffset(360, 26), Text = "INVITE PLAYERS", TextSize = 20, TextColor3 = C.GOLD, TextXAlignment = Enum.TextXAlignment.Left })
		local list = make("ScrollingFrame", {
			Position = UDim2.fromOffset(372, 120), Size = UDim2.fromOffset(360, 178),
			BackgroundColor3 = C.rgb(20, 24, 40), BorderSizePixel = 0, ScrollBarThickness = 6,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		}, content)
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, list)
		make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14) }, list)
		local inRoom = {}
		for _, m in ipairs(room.Members) do inRoom[m.UserId] = true end
		local any = false
		for i, other in ipairs(Players:GetPlayers()) do
			if not inRoom[other.UserId] then
				any = true
				local row = make("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.PANEL_LIGHT, BorderSizePixel = 0 }, list)
				label(row, { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -120, 1, 0), Text = other.DisplayName, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd })
				if isHost then
					local inviteButton = pixelButton(row, "INVITE", UDim2.fromOffset(96, 30), UDim2.new(1, -54, 0.5, 0), 15)
					inviteButton.MouseButton1Click:Connect(function()
						if call(Remote.LobbyInvite, other.UserId) then say("Invite sent to " .. other.DisplayName, C.GREEN) end
					end)
				end
			end
		end
		if not any then
			label(list, { Size = UDim2.new(1, 0, 0, 40), Text = "Nobody else is in this server", TextSize = 15, TextColor3 = C.TEXT_DIM })
		end

		local startButton = pixelButton(content, isHost and "START" or "WAITING FOR HOST", UDim2.fromOffset(360, 60), UDim2.new(0, 552, 0, 350), isHost and 30 or 20,
			isHost and C.GREEN_BTN or C.GREY_BTN, isHost and C.GREEN_EDGE or nil, C.WHITE)
		local leaveButton = pixelButton(content, "LEAVE LOBBY", UDim2.fromOffset(200, 50), UDim2.new(0, 100, 0, 350), 20, C.RED_BTN, C.RED_EDGE, C.WHITE)
		startButton.MouseButton1Click:Connect(function()
			if isHost then call(Remote.LobbyStart) end
		end)
		leaveButton.MouseButton1Click:Connect(function()
			Remote.LobbyLeave:FireServer()
		end)
	end

	show = function(name)
		screen = name
		clear()
		if name == "Mode" then showModes()
		elseif name == "Map" then showMaps()
		elseif name == "Stage" then showStages()
		elseif name == "Lobby" then showLobbyChoice()
		elseif name == "Room" then showRoom()
		end
	end

	backButton.MouseButton1Click:Connect(function()
		say("")
		if screen == "Map" then show("Mode")
		elseif screen == "Stage" then show("Map")
		elseif screen == "Lobby" then show("Stage")
		end
	end)

	local function close()
		dim.Visible = false
	end
	closeButton.MouseButton1Click:Connect(close)

	-- ===== invites (shown even when the PLAY menu is closed) =====
	local invitePanel = pixelPanel(ui.popupGui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(460, 130),
		Visible = false,
		ZIndex = 5,
	})
	local inviteText = label(invitePanel, { Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -24, 0, 56), TextSize = 18, TextWrapped = true, Text = "" })
	local inviteJoin = pixelButton(invitePanel, "JOIN", UDim2.fromOffset(180, 42), UDim2.new(0.5, -100, 1, -32), 20, C.GREEN_BTN, C.GREEN_EDGE, C.WHITE)
	local inviteNo = pixelButton(invitePanel, "NO THANKS", UDim2.fromOffset(180, 42), UDim2.new(0.5, 100, 1, -32), 18)
	local pendingInvite = nil
	local inviteSerial = 0
	inviteJoin.MouseButton1Click:Connect(function()
		local invite = pendingInvite
		invitePanel.Visible = false
		pendingInvite = nil
		if invite and call(Remote.LobbyJoin, invite.RoomId) then
			dim.Visible = true
			fit()
		end
	end)
	inviteNo.MouseButton1Click:Connect(function()
		invitePanel.Visible = false
		pendingInvite = nil
	end)
	Remote.LobbyInvited.OnClientEvent:Connect(function(invite)
		if typeof(invite) ~= "table" or not Config.Stages[invite.StageId] then return end
		if workspace:GetAttribute("State") ~= "Menu" then return end
		pendingInvite = invite
		inviteSerial += 1
		local serial = inviteSerial
		inviteText.Text = ("%s invited you to play\n%s"):format(tostring(invite.HostName), stageLine(invite.StageId))
		invitePanel.Visible = true
		task.delay(20, function()
			if inviteSerial == serial then invitePanel.Visible = false end
		end)
	end)

	-- ===== server state =====
	Remote.LobbyState.OnClientEvent:Connect(function(state)
		if typeof(state) ~= "table" then return end
		local wasInRoom = lobby.MyRoom ~= nil
		lobby = { MyRoom = state.MyRoom, Rooms = state.Rooms or {} }
		if workspace:GetAttribute("State") ~= "Menu" then return end
		if lobby.MyRoom then
			if not dim.Visible then
				dim.Visible = true
				fit()
			end
			show("Room")
		elseif wasInRoom then
			say("You left the lobby")
			show(selStage and "Lobby" or "Mode")
		elseif dim.Visible and screen == "Lobby" then
			show("Lobby") -- refresh the open lobbies list
		end
	end)

	-- ===== API for ClientMain =====
	local api = {}

	-- PLAY button
	function api.open()
		say("")
		dim.Visible = true
		fit()
		if lobby.MyRoom then show("Room") else show("Mode") end
		Remote.LobbyRefresh:FireServer()
	end

	function api.setProfile(p)
		profile = p
		if dim.Visible and screen == "Stage" then show("Stage") end
	end

	-- the match started / ended
	function api.onState(state)
		if state ~= "Menu" then
			close()
			invitePanel.Visible = false
		elseif lobby.MyRoom then
			api.open() -- back from a stage: show the lobby room again
		end
	end

	return api
end

return PlayMenu
