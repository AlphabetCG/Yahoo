-- GameServer: runs the whole game (rounds, enemies, units, upgrades, money, lives, speed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TeleportService = game:GetService("TeleportService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

-- Which place is this? (Config.PlaceRole) The same scripts run in both places.
--   Lobby: menus only, no map. START teleports the lobby room to its own reserved Match server.
--   Match: plays the stage it was sent (TeleportData), then sends players back to the Lobby.
--   Single (Config.Places.Match = 0): stages are played in this server.
local PLACE_ROLE = Config.PlaceRole()
local IS_MATCH_PLACE = PLACE_ROLE == "Match"
local USE_TELEPORT = PLACE_ROLE == "Lobby"
workspace:SetAttribute("IsMatchPlace", IS_MATCH_PLACE)

-- No walking characters in a tower defense game
Players.CharacterAutoLoads = false

-- ===== Remotes (how the client talks to the server) =====
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage

local function newRemote(className, name)
	local r = Instance.new(className)
	r.Name = name
	r.Parent = remotes
	return r
end
local returnToMenuRemote = newRemote("RemoteEvent", "ReturnToMenu")
local surrenderRemote = newRemote("RemoteEvent", "Surrender")
local setSpeedRemote = newRemote("RemoteEvent", "SetSpeed")
local placeTowerRemote = newRemote("RemoteFunction", "PlaceTower")
local upgradeTowerRemote = newRemote("RemoteFunction", "UpgradeTower")
local sellTowerRemote = newRemote("RemoteFunction", "SellTower")
local setTargetingRemote = newRemote("RemoteEvent", "SetTargeting")
local setAutoSkipRemote = newRemote("RemoteEvent", "SetAutoSkip")
local beginMatchRemote = newRemote("RemoteEvent", "BeginMatch")
local retryRemote = newRemote("RemoteEvent", "Retry")
local shotRemote = newRemote("UnreliableRemoteEvent", "Shot") -- tells clients to draw a shot
local skipWaveRemote = newRemote("RemoteEvent", "SkipWave")   -- vote to start the next round now

-- saved player data: settings, gems, units, items (adds its own remotes to the Remotes folder)
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
local Lobby = require(script.Parent:WaitForChild("Lobby"))
PlayerData.init(remotes)

-- ===== Host & votes =====
-- The host is the player who has been in the server the longest (workspace.HostId). Only the host
-- starts the stage, starts the match early, retries and goes back to the menu.
-- starts the stage, starts the match early, sets the game speed, retries and goes back to the menu.
-- The rest is voted on by the players in the match (see recomputeVotes):
--   Skip Wave and Surrender (everyone has to agree; Auto Skip ON players skip by themselves).
--   Each player's vote is a player attribute (VoteAutoSkip / VoteSkip / VoteSurrender); totals are on workspace.
local joinOrder = {}
local recomputeVotes -- defined below (needs the match state)

-- Everyone in the server, longest-present first. Uses Players:GetPlayers() so a player is never
-- missed when several PlayerAdded handlers run in a different order (joinOrder only sorts).
local function playersInOrder()
	local list = {}
	for _, p in ipairs(joinOrder) do
		if p.Parent then table.insert(list, p) end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if not table.find(list, p) then table.insert(list, p) end
	end
	return list
end

local function isHost(player)
	return player.UserId == workspace:GetAttribute("HostId")
end

local matchHost = nil -- the lobby host of the running stage

-- Host = the lobby host of the running stage. If they leave, the next player in the match takes over;
-- outside a stage it is simply the player who has been in the server the longest.
local function updateHost()
	local host = matchHost
	if not (host and host.Parent) then
		host = nil
		for _, p in ipairs(playersInOrder()) do
			if p:GetAttribute("InMatch") then
				host = p
				break
			end
		end
		host = host or joinOrder[1]
		if matchHost then matchHost = host end
	end
	local newId = host and host.UserId or 0
	if workspace:GetAttribute("HostId") ~= newId then
		workspace:SetAttribute("HostId", newId)
	end
end

-- every player gets a colour nobody else in the server has (Config.PlayerColors index)
local function assignColor(player)
	local used = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p:GetAttribute("PlayerColor") then used[p:GetAttribute("PlayerColor")] = true end
	end
	for i = 1, #Config.PlayerColors do
		if not used[i] then
			player:SetAttribute("PlayerColor", i)
			return
		end
	end
	player:SetAttribute("PlayerColor", (#Players:GetPlayers() - 1) % #Config.PlayerColors + 1)
end

local function setupVotes(player)
	assignColor(player)
	player:SetAttribute("VoteAutoSkip", Config.AutoSkipDefault)
	player:SetAttribute("VoteSkip", false)
	player:SetAttribute("VoteSurrender", false)
end

Players.PlayerAdded:Connect(function(player)
	if not table.find(joinOrder, player) then table.insert(joinOrder, player) end
	setupVotes(player)
	updateHost()
	recomputeVotes()
end)
for _, p in ipairs(Players:GetPlayers()) do
	if not table.find(joinOrder, p) then table.insert(joinOrder, p) end
	setupVotes(p)
end
Players.PlayerRemoving:Connect(function(player)
	local idx = table.find(joinOrder, player)
	if idx then table.remove(joinOrder, idx) end
	updateHost()
	task.defer(recomputeVotes) -- after the player is gone
end)
-- a player's saved Auto Skip choice is their vote
PlayerData.OnProfileLoaded(function(player, profile)
	player:SetAttribute("VoteAutoSkip", profile.Settings.AutoSkip)
	recomputeVotes()
end)
workspace:SetAttribute("HostId", 0)
updateHost()

-- Match-flow remotes: only the host, at most 2 requests per second
local function hostRequest(player, key)
	return isHost(player) and RateLimit.allow(player, key, 2)
end

-- ===== World objects =====
local towersFolder = workspace:FindFirstChild("Towers")
if not towersFolder then
	towersFolder = Instance.new("Folder")
	towersFolder.Name = "Towers"
	towersFolder.Parent = workspace
end
local enemiesFolder = workspace:FindFirstChild("Enemies")
if not enemiesFolder then
	enemiesFolder = Instance.new("Folder")
	enemiesFolder.Name = "Enemies"
	enemiesFolder.Parent = workspace
end

-- The game draws everything on the client from parts it must be able to see (waypoints, units,
-- enemies) and players have no character, so Workspace.StreamingEnabled has to be off
-- (default.project.json sets it). New places in Studio start with it on.
if workspace.StreamingEnabled then
	warn("GameServer: Workspace.StreamingEnabled is ON in this place. Turn it off (Rojo sync / Workspace properties), "
		.. "otherwise clients don't see the path, units or enemies.")
end

local path = USE_TELEPORT and {} or Config.GetPath() -- the Lobby has no map
if not USE_TELEPORT and #path < 2 then
	warn("GameServer: Workspace.Waypoints needs at least 2 parts named 1, 2, 3... (is this place synced with Rojo?)")
end

-- ===== Game state (shared with clients through attributes on Workspace) =====
-- State: "Menu" | "Playing" | "GameOver" | "Victory"
workspace:SetAttribute("State", "Menu")
workspace:SetAttribute("Lives", Config.StartLives)
workspace:SetAttribute("Round", 0)
workspace:SetAttribute("Countdown", 0)
workspace:SetAttribute("WaveState", "")   -- "Spawning" | "Clearing" (Auto Skip OFF timer) | ""
workspace:SetAttribute("WaveSpawned", 0)
workspace:SetAttribute("WaveCount", 0)
workspace:SetAttribute("GameSpeed", 1)

local enemies = {}        -- list of enemy entries (see spawnEnemy)
local lastSpawned = nil   -- the newest enemy (the next one spawns once it has walked out of the way)
local stageKills = 0         -- enemies defeated this stage (for the rewards)
local stageBossKilled = false
local pendingHits = {}    -- shots in flight: { Enemy, Damage, Owner, Due } (damage lands when the bolt arrives)
local towers = {}         -- list of tower entries (see createTower)
local towerByModel = {}   -- Model -> tower entry
local matchRequested = false -- set when the host presses START MATCH during the prep phase
local skipRequested = false  -- set when everyone in the match agreed to skip the wave
local autoSkipReady = false  -- the wave reached its auto-skip point: players with Auto Skip ON count as skipping
local session = 0         -- changes every new game so old round loops stop themselves
local stageTime = 0       -- real seconds spent on this stage
local stageSyncTimer = 0
local function publishStage()
	stageSyncTimer = 0
	workspace:SetAttribute("StageTime", stageTime)
	workspace:SetAttribute("StageSync", workspace:GetServerTimeNow())
end
local gameTime = 0        -- game clock; runs faster when game speed is x2 / x3
local lastGdt = 0         -- game seconds that passed in the latest frame

local ENEMY_HEIGHT = Config.GroundY + Config.PathTop + 1.5

-- Waits in *game time*, so x2 / x3 speed also speeds up spawning and countdowns.
-- Returns false if the game was stopped/restarted while waiting.
local function gameWait(seconds, mySession)
	local target = gameTime + seconds
	while gameTime < target do
		if session ~= mySession then return false end
		task.wait()
	end
	return session == mySession
end

-- ===== Money =====
-- income this stage per player and source, printed at the end when Config.DebugEconomy is on
local stageIncome = {} -- [userId] = { Start = n, Pops = n, RoundBonus = n, Refund = n }

local function trackIncome(player, source, amount)
	local byPlayer = stageIncome[player.UserId]
	if not byPlayer then
		byPlayer = {}
		stageIncome[player.UserId] = byPlayer
	end
	byPlayer[source] = (byPlayer[source] or 0) + amount
end

-- source = "Pops" | "RoundBonus" | "Refund" (only used for the economy debug print)
local function giveMoney(player, amount, source)
	if player and player.Parent and amount ~= 0 then
		player:SetAttribute("Money", (player:GetAttribute("Money") or 0) + amount)
		trackIncome(player, source or "Other", amount)
	end
end

local function printEconomy()
	for _, p in ipairs(Players:GetPlayers()) do
		local inc = stageIncome[p.UserId] or {}
		local total = 0
		for _, n in pairs(inc) do total += n end
		print(("[Economy] %s round %d: start %d + pops %d + round bonus %d + refunds %d = %d"):format(
			p.Name, workspace:GetAttribute("Round") or 0, inc.Start or 0, inc.Pops or 0,
			inc.RoundBonus or 0, inc.Refund or 0, total))
	end
end

-- ===== Party (one server = one match) =====
-- Players in the current stage have InMatch = true. When a stage starts, the first
-- Config.MaxPartySize players (by join order) are in it. Anyone who joins later spectates and is
-- let in at the start of the next round (if there is room) with the same money the team has earned.
local teamEarned = 0   -- money every player in the match has earned this stage (start money not included)
local matchRoster = {} -- [userId] = true: the lobby members of the running stage (only they can play)
local currentStage = Config.DefaultStage
local currentRoom = nil -- the lobby room the running stage came from
local stageStartMoney = Config.StartMoney
local stageHealthMult, stageSpeedMult = 1, 1
local moneyCarry = {}  -- [player] = part of a coin earned but not paid out yet

local function participants()
	local list = {}
	for _, p in ipairs(playersInOrder()) do
		if p:GetAttribute("InMatch") then table.insert(list, p) end
	end
	return list
end

local function partySize()
	return math.max(1, #participants())
end

-- Pays `amount` (what a solo player would get) to every player in the match, scaled by
-- Config.TeamIncome for the party size. Fractions are carried over so nothing is lost.
local function giveTeamMoney(amount, source)
	local share = amount * Config.TeamIncome[math.min(partySize(), #Config.TeamIncome)]
	teamEarned += share
	for _, p in ipairs(participants()) do
		local total = (moneyCarry[p] or 0) + share
		local whole = math.floor(total + 1e-6)
		moneyCarry[p] = total - whole
		giveMoney(p, whole, source)
	end
end

-- Lets lobby members who aren't in yet (arrived late / rejoined) into the match while there is room
-- (prep phase / start of a round). Other players in the server just watch.
local function admitPlayers()
	local count = #participants()
	for _, p in ipairs(playersInOrder()) do
		if count >= Config.MaxPartySize then break end
		if not p:GetAttribute("InMatch") and matchRoster[p.UserId] then
			local money = stageStartMoney + math.floor(teamEarned)
			p:SetAttribute("InMatch", true)
			p:SetAttribute("Money", money)
			moneyCarry[p] = 0
			trackIncome(p, "Start", money)
			count += 1
		end
	end
	recomputeVotes()
end

local function setupPlayer(player)
	-- only initialise: another PlayerAdded handler (the Match place start) may already have let them in
	if player:GetAttribute("InMatch") == nil then
		player:SetAttribute("Money", Config.StartMoney)
		player:SetAttribute("InMatch", false)
	end
	-- a lobby member joining during the prep phase plays right away (later: at the next round)
	if workspace:GetAttribute("State") == "Playing" and workspace:GetAttribute("Phase") == "Prep" then
		admitPlayers()
	end
end
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
Players.PlayerAdded:Connect(setupPlayer)

-- ===== Cleanup / game over =====
local function clearEnemies()
	table.clear(pendingHits)
	for _, e in ipairs(enemies) do
		if e.Part then e.Part:Destroy() end
	end
	table.clear(enemies)
	lastSpawned = nil
	enemiesFolder:ClearAllChildren()
end

local function clearAll()
	clearEnemies()
	table.clear(towers)
	table.clear(towerByModel)
	towersFolder:ClearAllChildren()
end

local function endGame(newState, reason)
	if workspace:GetAttribute("State") == "Playing" then
		if Config.DebugEconomy then printEconomy() end
		-- hand out the stage rewards once, before clients see the result screen (spectators get none)
		for _, p in ipairs(participants()) do
			local rewards = PlayerData.GrantStageRewards(p, {
				Won = newState == "Victory",
				Round = workspace:GetAttribute("Round") or 0,
				Kills = stageKills,
				BossKilled = stageBossKilled,
				Surrender = reason == "Surrender",
				StageId = currentStage,
			})
			remotes.StageRewards:FireClient(p, rewards)
		end
	end
	session += 1
	clearEnemies()
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("VoteSkip", false)
		p:SetAttribute("VoteSurrender", false)
	end
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("WaveState", "")
	workspace:SetAttribute("GameSpeed", 1)
	publishStage()
	workspace:SetAttribute("EndReason", reason or "")
	workspace:SetAttribute("State", newState)
	recomputeVotes()
end

local function goToMenu()
	session += 1
	clearAll()
	matchHost = nil
	if currentRoom then
		Lobby.SetStarted(currentRoom, false) -- the room can start again
		currentRoom = nil
	end
	updateHost()
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("GameSpeed", 1)
	workspace:SetAttribute("State", "Menu")
	recomputeVotes()
end

local function loseLives(amount)
	local lives = math.max(0, (workspace:GetAttribute("Lives") or 0) - amount)
	workspace:SetAttribute("Lives", lives)
	if lives <= 0 then
		endGame("GameOver", "Defeat")
	end
end

-- ===== Enemies =====
local function tierInfo(tier)
	return Config.Tiers[math.clamp(tier, 1, Config.MaxTier)]
end

-- the tier an enemy looks like at its current health (its color steps down as it gets hurt)
local function shownTier(e)
	return math.clamp(math.ceil(e.Health / e.MaxHealth * e.Tier - 1e-6), 1, e.Tier)
end

-- Enemies walk the path center in single file. Two enemies keep at least the sum of their
-- radii (Config.EnemySpacing / 2 each, bigger for the boss) between them.
local function enemyRadius(isBoss)
	return Config.EnemySpacing / 2 * (isBoss and Config.Boss.Scale or 1)
end

-- round = the round this enemy belongs to (sets its health); bossHealth = multiplier for a boss
local function spawnEnemy(tier, isBoss, round, bossHealth)
	if #path < 2 then return end
	local health = isBoss and Config.Boss.Health * (bossHealth or 1)
		or tierInfo(tier).HP * (1 + Config.HpPerRound * math.max(0, (round or 1) - 1))
	health *= stageHealthMult -- difficulty and stage rules
	health *= 1 + Config.HpPerExtraPlayer * (partySize() - 1) -- tougher with more players
	local part = Instance.new("Part")
	part.Name = "Enemy"
	part.Shape = Enum.PartType.Ball
	part.Size = isBoss and Vector3.new(6, 6, 6) or Vector3.new(3, 3, 3)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1 -- invisible: every client draws a pixel-art sprite for it
	part.CanQuery = false
	part:SetAttribute("Tier", tier)
	part:SetAttribute("Born", workspace:GetServerTimeNow())
	part:SetAttribute("MaxHealth", health)
	part:SetAttribute("Health", health)
	if isBoss then
		part.Name = "Boss"
		part:SetAttribute("Boss", true)
	end
	part.Anchored = true
	part.CanCollide = false
	part.Position = path[1] + Vector3.new(0, ENEMY_HEIGHT, 0)
	part.Parent = enemiesFolder
	local entry = {
		Part = part,
		Tier = tier,              -- tier it spawned with (fixed speed)
		ShownTier = tier,         -- tier it looks like now
		Health = health,
		MaxHealth = health,
		Carry = 0,                -- damage dealt that has not been paid out as a whole HP yet
		Boss = isBoss or false,
		Speed = (isBoss and Config.Boss.Speed or tierInfo(tier).Speed) * stageSpeedMult,
		Pending = 0,
		Born = os.clock(),
		Radius = enemyRadius(isBoss),
		Index = 1,
		Dist = 0,                 -- studs walked along the path (bigger = closer to the castle)
		Dead = false,
	}
	table.insert(enemies, entry)
	lastSpawned = entry
end

local function damageEnemy(enemy, damage, owner)
	if enemy.Dead then return end
	-- money is paid per whole HP removed; fractions carry over to the next hit
	enemy.Carry += math.min(damage, enemy.Health)
	enemy.Health -= damage
	local pops = math.floor(enemy.Carry + 1e-6)
	enemy.Carry -= pops
	giveTeamMoney(pops * Config.RewardPerPop, "Pops") -- shared: every player in the match is paid
	if enemy.Health <= 1e-6 then
		enemy.Dead = true
		stageKills += 1
		if enemy.Boss then stageBossKilled = true end
		local idx = table.find(enemies, enemy)
		if idx then table.remove(enemies, idx) end
		enemy.Part:Destroy()
	else
		enemy.Part:SetAttribute("Health", enemy.Health)
		if not enemy.Boss then
			local shown = shownTier(enemy)
			if shown ~= enemy.ShownTier then
				enemy.ShownTier = shown
				enemy.Part:SetAttribute("Tier", shown) -- the wisp changes color as it loses health
			end
		end
	end
end

-- Moves every enemy along the path, front of the line first. An enemy that catches up with the
-- one ahead of it waits behind it (single file, no overlapping) until the gap opens again.
local marching = {}
-- ===== Status effects (Refine abilities) =====
-- Burn and Slow last in game time, so x2 / x3 speed also speeds them up.
local function publishStatus(e)
	local burning = (e.BurnUntil or 0) > gameTime
	local slowed = (e.SlowUntil or 0) > gameTime
	local status = (burning and slowed and "BurnSlow") or (burning and "Burn") or (slowed and "Slow") or ""
	if status ~= e.Status then
		e.Status = status
		e.Part:SetAttribute("Status", status)
	end
end

-- a hit with an ability lands on enemy e (a stronger effect replaces a weaker one; the timer refreshes)
local function applyAbility(e, ability, owner)
	if not ability or e.Dead then return end
	if ability.Kind == "Burn" then
		if (e.BurnUntil or 0) <= gameTime or ability.Dps >= (e.BurnDps or 0) then
			e.BurnDps = ability.Dps
			e.BurnOwner = owner
		end
		e.BurnUntil = math.max(e.BurnUntil or 0, gameTime + ability.Duration)
	elseif ability.Kind == "Slow" and not e.Boss then
		if (e.SlowUntil or 0) <= gameTime or ability.Pct >= (e.SlowPct or 0) then
			e.SlowPct = math.clamp(ability.Pct, 0, 0.9)
		end
		e.SlowUntil = math.max(e.SlowUntil or 0, gameTime + ability.Duration)
	end
	publishStatus(e)
end

local function updateStatus(dt)
	for i = #enemies, 1, -1 do
		local e = enemies[i]
		if e and e.Status and e.Status ~= "" then
			if (e.BurnUntil or 0) > gameTime then
				damageEnemy(e, e.BurnDps * dt, e.BurnOwner) -- may remove e from the list
			end
			if not e.Dead then publishStatus(e) end
		end
	end
end

local function updateEnemies(dt)
	table.clear(marching)
	table.move(enemies, 1, #enemies, 1, marching)
	table.sort(marching, function(a, b) return a.Dist > b.Dist end)
	local ahead = nil
	for _, e in ipairs(marching) do
		local speed = e.Speed
		if (e.SlowUntil or 0) > gameTime then speed *= 1 - e.SlowPct end
		local step = speed * dt
		if ahead then
			step = math.min(step, math.max(0, ahead.Dist - (ahead.Radius + e.Radius) - e.Dist))
		end
		while step > 0 and e.Index < #path do
			local target = path[e.Index + 1] + Vector3.new(0, ENEMY_HEIGHT, 0)
			local current = e.Part.Position
			local delta = target - current
			local d = delta.Magnitude
			if d <= step then
				e.Part.Position = target
				step -= d
				e.Dist += d
				e.Index += 1
			else
				e.Part.Position = current + delta.Unit * step
				e.Dist += step
				step = 0
			end
		end
		if e.Index >= #path then
			-- reached the end of the path: costs lives (the tier it shows, or the boss's remaining health)
			local idx = table.find(enemies, e)
			if idx then table.remove(enemies, idx) end
			e.Dead = true
			e.Part:Destroy()
			loseLives(e.Boss and math.ceil(e.Health - 1e-6) or e.ShownTier)
			if workspace:GetAttribute("State") ~= "Playing" then return end
		else
			ahead = e
		end
	end
end

-- ===== Units (towers) =====
local function faceTarget(model, targetPos)
	local p = model:GetPivot().Position
	local dir = Vector3.new(targetPos.X - p.X, 0, targetPos.Z - p.Z)
	if dir.Magnitude > 0.01 then
		model:PivotTo(CFrame.lookAt(p, p + dir))
	end
end


-- Decides if enemy `e` is a better target than the current `best` for a targeting mode.
-- d = distance from the tower to e, bestD = distance to best.
local function isBetter(mode, e, d, best, bestD)
	if not best then return true end
	if mode == "First" then
		return e.Dist > best.Dist
	elseif mode == "Last" then
		return e.Dist < best.Dist
	elseif mode == "Strongest" then
		return e.Health > best.Health or (e.Health == best.Health and e.Dist > best.Dist)
	elseif mode == "Weakest" then
		return e.Health < best.Health or (e.Health == best.Health and e.Dist > best.Dist)
	elseif mode == "Closest" then
		return d < bestD
	end
	return false
end

local function updateTowers()
	for i = #towers, 1, -1 do
		local t = towers[i]
		if not t.Model.Parent then
			table.remove(towers, i)
		elseif t.Mode ~= "None" and gameTime - t.Last >= t.Stats.Cooldown then
			local origin = t.Root.Position
			local o2 = Vector2.new(origin.X, origin.Z)
			local best, bestClose = nil, math.huge
			local now = os.clock()
			for _, e in ipairs(enemies) do
				-- only enemies that clients have had time to draw, and that are not already
				-- going to die from shots in flight, can be targeted
				if not e.Dead and now - e.Born >= Config.SpawnGrace and e.Pending < e.Health then
					local ep = e.Part.Position
					local d = (Vector2.new(ep.X, ep.Z) - o2).Magnitude
					if d <= t.Stats.Range and isBetter(t.Mode, e, d, best, bestClose) then
						best, bestClose = e, d
					end
				end
			end
			if best then
				if t.Last == -math.huge then
					t.Last = gameTime
				else
					t.Last = math.max(t.Last + t.Stats.Cooldown, gameTime - lastGdt)
				end
				local targetPos = best.Part.Position
				faceTarget(t.Model, targetPos)
				best.Pending += t.Stats.Damage -- only the target counts against overkill
				local attack = t.Attack
				table.insert(pendingHits, {
					Enemy = best, Damage = t.Stats.Damage, Ability = t.Stats.Ability,
					Owner = t.Owner, Due = now + Config.ShotTravel,
					Attack = attack, Origin = o2, Aim = Vector2.new(targetPos.X, targetPos.Z), Range = t.Stats.Range,
				})
				-- clients draw the shot; area attacks also get their shape
				local shape = nil
				if attack.Kind ~= "Single" then
					shape = { K = attack.Kind, R = attack.Radius, W = attack.Width, A = attack.Angle, L = t.Stats.Range }
				end
				shotRemote:FireAllClients(t.Model, best.Part, targetPos, shape)
			end
		end
	end
end

local function flatPos(e)
	local p = e.Part.Position
	return Vector2.new(p.X, p.Z)
end

-- Who a landed shot hits: { { Enemy, Mult } }. The target always takes full damage (if still alive);
-- area attacks add every other enemy inside their shape, the ones closest to the castle first, up to
-- MaxHits in total. Positions are taken when the shot lands.
local function victimsOf(h)
	local attack = h.Attack or { Kind = "Single" }
	local main = h.Enemy
	local list = {}
	if not main.Dead then table.insert(list, { Enemy = main, Mult = 1 }) end
	if attack.Kind == "Single" then return list end

	local inside -- function(enemy) -> damage multiplier or nil
	if attack.Kind == "Splash" then
		local center = main.Dead and h.Aim or flatPos(main)
		local radius, pct = attack.Radius or 6, attack.SplashPct or 0.5
		inside = function(e)
			return (flatPos(e) - center).Magnitude <= radius and pct or nil
		end
	elseif attack.Kind == "Line" then
		local dir = h.Aim - h.Origin
		if dir.Magnitude < 1e-3 then return list end
		dir = dir.Unit
		local halfWidth, length = (attack.Width or 4) / 2, h.Range + 2
		inside = function(e)
			local rel = flatPos(e) - h.Origin
			local along = rel:Dot(dir)
			return (along >= 0 and along <= length and (rel - dir * along).Magnitude <= halfWidth) and 1 or nil
		end
	elseif attack.Kind == "Cone" then
		local dir = h.Aim - h.Origin
		if dir.Magnitude < 1e-3 then return list end
		dir = dir.Unit
		local cosHalf = math.cos(math.rad((attack.Angle or 60) / 2))
		inside = function(e)
			local rel = flatPos(e) - h.Origin
			local d = rel.Magnitude
			return (d <= h.Range and (d < 1e-3 or rel.Unit:Dot(dir) >= cosHalf)) and 1 or nil
		end
	elseif attack.Kind == "Circle" then
		local radius = attack.Radius or h.Range
		inside = function(e)
			return (flatPos(e) - h.Origin).Magnitude <= radius and 1 or nil
		end
	else
		return list
	end

	local extra = {}
	for _, e in ipairs(enemies) do
		if e ~= main and not e.Dead then
			local mult = inside(e)
			if mult then table.insert(extra, { Enemy = e, Mult = mult }) end
		end
	end
	table.sort(extra, function(a, b) return a.Enemy.Dist > b.Enemy.Dist end)
	local maxHits = attack.MaxHits or math.huge
	for _, v in ipairs(extra) do
		if #list >= maxHits then break end
		table.insert(list, v)
	end
	return list
end

local function updateHits()
	local now = os.clock()
	for i = #pendingHits, 1, -1 do
		local h = pendingHits[i]
		if h.Due <= now then
			table.remove(pendingHits, i)
			h.Enemy.Pending = math.max(0, h.Enemy.Pending - h.Damage)
			for _, v in ipairs(victimsOf(h)) do
				if not v.Enemy.Dead then
					damageEnemy(v.Enemy, h.Damage * v.Mult, h.Owner)
					applyAbility(v.Enemy, h.Ability, h.Owner)
				end
			end
		end
	end
end

-- Units are invisible markers on the server (a model with one flat part).
-- Every client draws the pixel-art sprite itself from the model's attributes.
local function createTower(player, unitName, pos, instance)
	local unit = Config.Units[unitName]
	if not unit then return nil end
	local model = Instance.new("Model")
	model.Name = unitName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(6, 0.2, 6)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Position = Vector3.new(pos.X, Config.GroundY + 0.1, pos.Z)
	root.Parent = model
	model.PrimaryPart = root

	-- info the client reads to draw the unit and show the upgrade panel
	model:SetAttribute("UnitName", unitName)
	model:SetAttribute("Level", 1)
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("Targeting", "First")
	model:SetAttribute("Spent", unit.Cost)
	model:SetAttribute("UnitId", instance and instance.Id or "")
	-- the copy's account level (kept between stages); scales damage and range, see Config.ScaledStats
	local unitLevel = instance and instance.Level or 1
	model:SetAttribute("UnitLevel", unitLevel)

	model.Parent = towersFolder
	local entry = {
		Model = model,
		Root = root,
		UnitName = unitName,
		Level = 1,
		Stats = Config.ScaledStats(unitName, 1, unitLevel),
		Attack = Config.AttackOf(unitName, 1), -- shape of the attack (Single / Splash / Line / Cone / Circle)
		UnitLevel = unitLevel,
		BeamColor = unit.BeamColor,
		Last = -math.huge,
		Mode = "First",
		Spent = unit.Cost,
		Owner = player,
		UnitId = instance and instance.Id,
	}
	table.insert(towers, entry)
	towerByModel[model] = entry
	return model
end

-- unitId = the id of one of the player's saved unit instances (profile.Units)
placeTowerRemote.OnServerInvoke = function(player, unitId, pos)
	if not RateLimit.allow(player, "PlaceTower", 10) then return false, "Slow down" end
	if workspace:GetAttribute("State") ~= "Playing" then return false, "Game is not running" end
	if not player:GetAttribute("InMatch") then return false, "You join the match at the next round" end
	if typeof(unitId) ~= "string" or typeof(pos) ~= "Vector3" then return false, "Bad request" end
	local instance = PlayerData.GetUnit(player, unitId)
	if not instance then return false, "You do not own this unit" end
	if not PlayerData.IsEquipped(player, unitId) then return false, "Equip this unit in your loadout first" end
	local unitName = instance.Name
	local unit = Config.Units[unitName]
	if not unit then return false, "Unknown unit" end
	local rules = Config.Stages[currentStage].Rules or {}
	if rules.Rarities and not rules.Rarities[unit.Rarity] then
		local allowed = {}
		for rarity in pairs(rules.Rarities) do table.insert(allowed, rarity) end
		return false, "This stage only allows " .. table.concat(allowed, " / ") .. " units"
	end
	local money = player:GetAttribute("Money") or 0
	if money < unit.Cost then return false, "Not enough money" end
	-- each unit can be on the map at most Config.PlaceLimit(unitName) times per player
	local placedOfUnit = 0
	for _, t in ipairs(towers) do
		if t.Owner == player and t.Model.Parent and t.UnitName == unitName then
			placedOfUnit += 1
		end
	end
	local limit = Config.PlaceLimit(unitName)
	if placedOfUnit >= limit then
		return false, ("Only %d %s allowed"):format(limit, unitName)
	end
	local ok, reason = Config.CanPlace(pos, towersFolder)
	if not ok then return false, reason end
	player:SetAttribute("Money", money - unit.Cost)
	createTower(player, unitName, pos, instance)
	return true
end

-- Refine (in-match upgrade). all = true buys as many levels as the player can afford (REFINE MAX).
-- Returns true, levels bought.
upgradeTowerRemote.OnServerInvoke = function(player, model, all)
	if not RateLimit.allow(player, "UpgradeTower", 10) then return false, "Slow down" end
	if workspace:GetAttribute("State") ~= "Playing" then return false, "Game is not running" end
	if typeof(model) ~= "Instance" then return false, "Bad request" end
	local t = towerByModel[model]
	if not t or not model.Parent then return false, "Unit not found" end
	if t.Owner ~= player then return false, "This is not your unit" end
	if not Config.GetStats(t.UnitName, t.Level + 1) then return false, "Already max level" end

	local bought = 0
	while true do
		local nextStats = Config.GetStats(t.UnitName, t.Level + 1)
		local money = player:GetAttribute("Money") or 0
		if not nextStats or money < nextStats.Cost then break end
		player:SetAttribute("Money", money - nextStats.Cost)
		t.Level += 1
		t.Spent += nextStats.Cost
		t.Stats = Config.ScaledStats(t.UnitName, t.Level, t.UnitLevel)
		t.Attack = Config.AttackOf(t.UnitName, t.Level)
		bought += 1
		if all ~= true then break end
	end
	if bought == 0 then return false, "Not enough money" end
	model:SetAttribute("Spent", t.Spent)
	model:SetAttribute("Level", t.Level)
	return true, bought
end

-- A player who leaves mid-stage takes their units off the map (nobody else could upgrade or sell them)
Players.PlayerRemoving:Connect(function(player)
	moneyCarry[player] = nil
	for i = #towers, 1, -1 do
		local t = towers[i]
		if t.Owner == player then
			towerByModel[t.Model] = nil
			t.Model:Destroy()
			table.remove(towers, i)
		end
	end
end)

-- Selling returns Config.SellRefund (50%) of everything spent on the unit (placement + upgrades)
sellTowerRemote.OnServerInvoke = function(player, model)
	if not RateLimit.allow(player, "SellTower", 10) then return false, "Slow down" end
	if workspace:GetAttribute("State") ~= "Playing" then return false, "Game is not running" end
	if typeof(model) ~= "Instance" then return false, "Bad request" end
	local t = towerByModel[model]
	if not t or not model.Parent then return false, "Unit not found" end
	if t.Owner ~= player then return false, "This is not your unit" end
	local refund = math.floor(t.Spent * Config.SellRefund)
	towerByModel[model] = nil
	local idx = table.find(towers, t)
	if idx then table.remove(towers, idx) end
	model:Destroy()
	giveMoney(player, refund, "Refund")
	return true, refund
end

-- Targeting mode: First / Last / Strongest / Weakest / Closest / None
setTargetingRemote.OnServerEvent:Connect(function(player, model, mode)
	if not RateLimit.allow(player, "SetTargeting", 10) then return end
	if workspace:GetAttribute("State") ~= "Playing" then return end
	if typeof(model) ~= "Instance" or typeof(mode) ~= "string" then return end
	if not table.find(Config.TargetModes, mode) then return end
	local t = towerByModel[model]
	if not t or t.Owner ~= player then return end
	t.Mode = mode
	model:SetAttribute("Targeting", mode)
end)

-- ===== Rounds =====
-- Waits (game time) until the newest enemy has walked far enough that a new one fits behind it.
local function waitForRoom(isBoss, mySession)
	while lastSpawned and not lastSpawned.Dead
		and lastSpawned.Dist < lastSpawned.Radius + enemyRadius(isBoss) do
		if not gameWait(0.05, mySession) then return end
	end
end

-- Boss of round r: its health multiplier, or nil when the round has no boss.
-- Rules.BossEvery = a boss every N rounds (Infinite, Raid), otherwise one on the last round.
local function bossFor(stage, r)
	local rules = stage.Rules or {}
	if rules.BossEvery then
		if r % rules.BossEvery ~= 0 then return nil end
		local index = r // rules.BossEvery
		return (rules.BossHealth or 1) * (1 + 0.4 * (index - 1)) -- each boss is tougher than the last
	end
	if stage.Rounds > 0 and r == stage.Rounds then return rules.BossHealth or 1 end
	return nil
end

-- Starts stage `stageId` for `members` (the lobby room); `host` runs the match.
local function startGame(stageId, members, host)
	if workspace:GetAttribute("State") ~= "Menu" then return end
	stageId = Config.Stages[stageId] and stageId or Config.DefaultStage
	local stage = Config.Stages[stageId]
	local rules = stage.Rules or {}
	local difficulty = Config.Difficulties[stage.Difficulty] or Config.Difficulties.Normal
	currentStage = stageId
	stageStartMoney = rules.StartMoney or Config.StartMoney
	stageHealthMult = difficulty.Health * (rules.EnemyHealth or 1)
	stageSpeedMult = difficulty.Speed * (rules.EnemySpeed or 1)
	table.clear(matchRoster)
	for _, p in ipairs(members or Players:GetPlayers()) do matchRoster[p.UserId] = true end
	matchHost = host or (members and members[1]) or joinOrder[1]
	workspace:SetAttribute("StageId", stageId)
	workspace:SetAttribute("Mode", stage.Mode)
	workspace:SetAttribute("TotalRounds", stage.Rounds) -- 0 = endless

	clearAll()
	session += 1
	local mySession = session

	workspace:SetAttribute("Lives", Config.StartLives)
	workspace:SetAttribute("Round", 0)
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("WaveState", "")
	workspace:SetAttribute("GameSpeed", 1)
	table.clear(stageIncome)
	table.clear(moneyCarry)
	teamEarned = 0
	skipRequested = false
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("InMatch", false)
		p:SetAttribute("VoteSkip", false)
		p:SetAttribute("VoteSurrender", false)
	end
	-- stage timer (game time)
	stageTime = 0
	stageKills = 0
	stageBossKilled = false
	publishStage()
	matchRequested = false
	workspace:SetAttribute("PrepLeft", Config.PrepTime)
	workspace:SetAttribute("Phase", "Prep")
	workspace:SetAttribute("State", "Playing")
	admitPlayers() -- the lobby members are in the match
	updateHost()

	-- Spawns one round's enemies, spread over at most Config.MaxSpawnTime seconds.
	-- Returns a progress table so the round timer can watch how many have appeared.
	local function spawnRound(r)
		local count = math.floor(Config.EnemiesBase + r * Config.EnemiesPerRound + 0.5)
		if rules.EscortShare then count = math.max(1, math.floor(count * rules.EscortShare)) end -- Raid: small escort
		-- stronger enemy types appear about twice as fast now that there are half as many rounds
		local maxTier = math.min(Config.MaxTier, 1 + math.floor((2 * r - 1) / 3))
		local minTier = math.max(1, maxTier - 1)
		local interval = math.min(Config.SpawnInterval, Config.MaxSpawnTime / count)
		local progress = { Spawned = 0, Count = count, Interval = interval, Done = false }
		local function publish()
			-- the HUD shows "WAVE r  x/y" for the current round's wave
			if workspace:GetAttribute("Round") == r then
				workspace:SetAttribute("WaveSpawned", progress.Spawned)
				workspace:SetAttribute("WaveCount", count)
			end
		end
		publish()
		task.spawn(function()
			for _ = 1, count do
				if session ~= mySession then return end
				waitForRoom(false, mySession)
				if session ~= mySession then return end
				spawnEnemy(math.random(minTier, maxTier), false, r)
				progress.Spawned += 1
				publish()
				if not gameWait(interval, mySession) then return end
			end
			local bossHealth = bossFor(stage, r)
			if bossHealth then
				-- the boss closes the wave (it is the slowest, so nothing has to queue behind it)
				waitForRoom(true, mySession)
				if session ~= mySession then return end
				spawnEnemy(Config.MaxTier, true, r, bossHealth)
			end
			progress.Done = true
		end)
		return progress
	end

	task.spawn(function()
		-- PREP PHASE: players place units, then press START MATCH (or wait for the timer).
		-- This countdown is real time, it is not affected by the game speed.
		local prepEnd = os.clock() + Config.PrepTime
		while not matchRequested and os.clock() < prepEnd do
			workspace:SetAttribute("PrepLeft", math.ceil(prepEnd - os.clock()))
			task.wait(0.1)
			if session ~= mySession then return end
		end
		workspace:SetAttribute("PrepLeft", 0)
		stageTime = 0
		workspace:SetAttribute("Phase", "Match")
		publishStage()

		-- stage.Rounds rounds, or endless when it is 0 (only losing ends an Infinite stage)
		local total = stage.Rounds
		local progress
		local r = 0
		while total == 0 or r < total do
			r += 1
			workspace:SetAttribute("Round", r)
			skipRequested = false
			autoSkipReady = false
			for _, p in ipairs(Players:GetPlayers()) do p:SetAttribute("VoteSkip", false) end
			recomputeVotes()
			admitPlayers() -- spectators who joined during the last round join now
			if r > 1 then
				-- bonus for reaching the next round (shared like pops)
				giveTeamMoney(Config.RoundBonus + (r - 2) * Config.RoundBonusStep, "RoundBonus")
			end
			progress = spawnRound(r)

			-- When does the next round start? As soon as EVERY player in the match skips:
			--   * a player with Auto Skip ON skips by themselves once 60-70% of the wave has appeared
			--     (the rest keep spawning during the next round)
			--   * a player with Auto Skip OFF presses SKIP
			-- Otherwise: once the wave's last enemy has appeared, a Config.WaveClearTime timer starts and the
			-- next round begins when it runs out or every enemy on the map is gone.
			-- Solo this is exactly "Auto Skip ON: next round at 60-70%, OFF: timer (or press SKIP)".
			if total == 0 or r < total then
				local thisWave = progress
				local fraction = Config.SkipSpawnMin + math.random() * (Config.SkipSpawnMax - Config.SkipSpawnMin)
				local need = math.max(1, math.ceil(thisWave.Count * fraction))
				local deadline = nil
				workspace:SetAttribute("WaveState", "Spawning")
				workspace:SetAttribute("Countdown", 0)
				while not skipRequested do
					if not autoSkipReady and thisWave.Spawned >= need then
						autoSkipReady = true
						recomputeVotes() -- Auto Skip ON players now count as skipping
					end
					if thisWave.Spawned >= thisWave.Count then
						if not deadline then
							deadline = gameTime + Config.WaveClearTime
							workspace:SetAttribute("WaveState", "Clearing")
						end
						if gameTime >= deadline or #enemies == 0 then break end
						workspace:SetAttribute("Countdown", math.max(1, math.ceil(deadline - gameTime)))
					end
					if not gameWait(0.25, mySession) then return end
				end
				autoSkipReady = false
			end
		end

		workspace:SetAttribute("Countdown", 0)
		workspace:SetAttribute("WaveState", "")
		-- the last round has started: you win once all its enemies have appeared and are gone
		while not progress.Done or #enemies > 0 do
			task.wait(0.25)
			if session ~= mySession then return end
		end
		if session == mySession then
			endGame("Victory", "Clear")
		end
	end)
end

-- Lobby: check once that Config.Places.Match really is a place of THIS experience. A place that was
-- made as a separate experience can't receive reserved-server teleports from here.
local matchPlaceProblem = nil -- shown to the host instead of the raw teleport error when set
if USE_TELEPORT and not RunService:IsStudio() then
	task.spawn(function()
		local ok, err = pcall(function()
			local pages = game:GetService("AssetService"):GetGamePlacesAsync()
			local found = {}
			while true do
				for _, place in ipairs(pages:GetCurrentPage()) do
					if place.PlaceId == Config.Places.Match then return end
					table.insert(found, ("%s (%d)"):format(tostring(place.Name), place.PlaceId))
				end
				if pages.IsFinished then break end
				pages:AdvanceToNextPageAsync()
			end
			matchPlaceProblem = ("Place %d is not in this experience (GameId %d)"):format(Config.Places.Match, game.GameId)
			warn(("GameServer: %s. Places in this experience: %s"):format(matchPlaceProblem, table.concat(found, ", ")))
		end)
		if not ok then warn("GameServer: couldn't list this experience's places: " .. tostring(err)) end
	end)
end

-- ===== Lobby rooms start stages =====
-- Live game: the room is teleported to its own reserved Match server (TeleportData tells that server
-- the stage, the host and the members). Studio / Config.Places.Match = 0: the stage runs in this server.
local teleportRetries = {} -- [player] = { Options = TeleportOptions, Tries = n }

local function teleportRoom(room)
	if RunService:IsStudio() then
		return false, "Teleports only work in the published game. To test a stage in Studio, open the Match place."
	end
	local members = table.clone(room.Members)
	local userIds = {}
	for _, p in ipairs(members) do table.insert(userIds, p.UserId) end
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({
		RoomKey = ("%s/%d/%d"):format(game.JobId, room.Id, os.time()), -- this room's Match server only
		StageId = room.StageId,
		HostId = room.Host.UserId,
		Members = userIds,
		ReturnPlaceId = game.PlaceId,
	})
	Lobby.SetStarted(room, true)
	local ok, result = pcall(function()
		return TeleportService:TeleportAsync(Config.Places.Match, members, options)
	end)
	if not ok then
		Lobby.SetStarted(room, false)
		local reason = tostring(result):gsub("^.-:%d+: ", "") -- drop the script location
		warn("GameServer: teleport to the Match place failed: " .. reason)
		local text = "Couldn't start: " .. reason:sub(1, 100)
		if matchPlaceProblem then text ..= "  |  " .. matchPlaceProblem end
		return false, text
	end
	-- if one player's teleport fails, retry them into the same reserved server
	local retryOptions = Instance.new("TeleportOptions")
	retryOptions.ReservedServerAccessCode = result.ReservedServerAccessCode
	retryOptions:SetTeleportData(options:GetTeleportData())
	for _, p in ipairs(members) do
		teleportRetries[p] = { Options = retryOptions, Tries = 0 }
	end
	return true, "Starting..."
end

TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
	local retry = teleportRetries[player]
	warn(("GameServer: teleport failed for %s (%s): %s"):format(player.Name, tostring(result), tostring(errorMessage)))
	if not retry or retry.Tries >= 3 then
		teleportRetries[player] = nil
		local room = Lobby.RoomOf(player)
		if room then Lobby.SetStarted(room, false) end -- they stay in their lobby room and can try again
		return
	end
	retry.Tries += 1
	task.wait(2 * retry.Tries)
	pcall(function()
		TeleportService:TeleportAsync(Config.Places.Match, { player }, retry.Options)
	end)
end)
Players.PlayerRemoving:Connect(function(player)
	teleportRetries[player] = nil
end)

Lobby.init(remotes, {
	CanCreate = function(player, stageId)
		local required = Config.StageRequirement(stageId)
		if required and not PlayerData.HasCleared(player, required) then
			return false, "Clear " .. Config.Stages[required].Name .. " first"
		end
		return true
	end,
	StartRoom = function(room)
		if USE_TELEPORT then
			return teleportRoom(room)
		end
		-- Studio / no Match place: play the stage in this server
		if workspace:GetAttribute("State") ~= "Menu" then
			return false, "A stage is already running in this server"
		end
		currentRoom = room
		Lobby.SetStarted(room, true)
		startGame(room.StageId, room.Members, room.Host)
		return true
	end,
})

local returnPlaceId = nil -- Match place: the Lobby place the players came from (from TeleportData)

-- Match place: sends players back to the Lobby (each player chooses when)
local function sendToLobby(players)
	if not returnPlaceId or RunService:IsStudio() then return false end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(returnPlaceId, players)
	end)
	if not ok then warn("GameServer: teleport back to the lobby failed: " .. tostring(err)) end
	return ok
end

returnToMenuRemote.OnServerEvent:Connect(function(player)
	local state = workspace:GetAttribute("State")
	if IS_MATCH_PLACE then
		-- anyone can go back to the lobby once the stage is over
		if RateLimit.allow(player, "ReturnToMenu", 1) and (state == "GameOver" or state == "Victory") then
			if returnPlaceId and not RunService:IsStudio() then
				sendToLobby({ player })
			elseif isHost(player) then
				goToMenu() -- Studio / opened directly: no lobby to go to, the stage starts again
			end
		end
		return
	end
	if not hostRequest(player, "ReturnToMenu") then return end
	if state == "GameOver" or state == "Victory" then
		goToMenu()
	end
end)

-- Surrender vote (toggles): the stage ends once every player in the match has voted (solo: at once)
surrenderRemote.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player, "Surrender", 2) then return end
	if workspace:GetAttribute("State") ~= "Playing" or not player:GetAttribute("InMatch") then return end
	player:SetAttribute("VoteSurrender", not player:GetAttribute("VoteSurrender"))
	recomputeVotes()
end)

-- Skip Wave vote (toggles): once every player in the match agrees, the next round starts now
skipWaveRemote.OnServerEvent:Connect(function(player)
	if not RateLimit.allow(player, "SkipWave", 2) then return end
	if workspace:GetAttribute("State") ~= "Playing" or workspace:GetAttribute("Phase") ~= "Match" then return end
	if not player:GetAttribute("InMatch") then return end
	player:SetAttribute("VoteSkip", not player:GetAttribute("VoteSkip"))
	recomputeVotes()
end)

-- Retry (from the stage clear / failed screen): reset everything and start a fresh prep phase
retryRemote.OnServerEvent:Connect(function(player)
	if not hostRequest(player, "Retry") then return end
	local state = workspace:GetAttribute("State")
	if state == "GameOver" or state == "Victory" then
		-- same stage, same players (those still here)
		local members = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if matchRoster[p.UserId] then table.insert(members, p) end
		end
		local stageId, host, room = currentStage, matchHost, currentRoom
		goToMenu()
		if room then
			currentRoom = room
			Lobby.SetStarted(room, true)
		end
		startGame(stageId, members, host)
	end
end)

-- Phase inside a game: "Prep" = place units + START MATCH button / countdown, "Match" = rounds running
workspace:SetAttribute("Phase", "Menu")
workspace:SetAttribute("PrepLeft", 0)
beginMatchRemote.OnServerEvent:Connect(function(player)
	if not hostRequest(player, "BeginMatch") then return end
	if workspace:GetAttribute("State") == "Playing" and workspace:GetAttribute("Phase") == "Prep" then
		matchRequested = true
	end
end)

-- ===== Votes =====
-- Who votes: the players in the match during a stage, everyone in the server otherwise.
local function voters()
	if workspace:GetAttribute("State") == "Playing" then
		local list = participants()
		if #list > 0 then return list end
	end
	return playersInOrder()
end

-- Works out the outcome of every vote and publishes the totals:
-- workspace Voters, SkipVotes (players skipping this wave: pressed SKIP, or Auto Skip ON once the wave
-- reached its auto-skip point), SurrenderVotes.
recomputeVotes = function()
	local list = voters()
	local n = #list
	local playing = workspace:GetAttribute("State") == "Playing"

	-- skip wave / surrender: everyone has to agree
	local skip, surrender = 0, 0
	for _, p in ipairs(list) do
		if p:GetAttribute("VoteSkip") or (autoSkipReady and p:GetAttribute("VoteAutoSkip")) then skip += 1 end
		if p:GetAttribute("VoteSurrender") then surrender += 1 end
	end
	workspace:SetAttribute("Voters", n)
	workspace:SetAttribute("SkipVotes", skip)
	workspace:SetAttribute("SurrenderVotes", surrender)

	if playing and n > 0 and skip >= n then
		skipRequested = true
	end
	if playing and n > 0 and surrender >= n then
		endGame("GameOver", "Surrender")
	end
end

-- Auto Skip (each player's own setting): ON = skip by yourself once ~60-70% of the wave has appeared,
-- OFF = press SKIP (or wait for the timer). The round moves on early when every player skips.
setAutoSkipRemote.OnServerEvent:Connect(function(player, value)
	if typeof(value) ~= "boolean" or not RateLimit.allow(player, "SetAutoSkip", 2) then return end
	PlayerData.SetSetting(player, "AutoSkip", value) -- remembered between sessions
	player:SetAttribute("VoteAutoSkip", value)
	recomputeVotes()
end)

-- Game speed (x1 / x2 / x3): the host sets it
setSpeedRemote.OnServerEvent:Connect(function(player, speed)
	if not hostRequest(player, "SetSpeed") then return end
	if workspace:GetAttribute("State") ~= "Playing" then return end
	if not table.find(Config.SpeedOptions, speed) then return end
	publishStage()
	workspace:SetAttribute("GameSpeed", speed)
end)

recomputeVotes()

-- ===== Match place: play the stage the lobby sent =====
-- The first player to arrive carries the TeleportData (room key, stage, host, members, lobby place). The
-- stage starts once every member is here, or after MATCH_WAIT seconds with whoever made it.
-- Live game: only the room's members may be here, in the server the lobby reserved for them. Anyone
-- else (joined the place directly, followed a friend, another room) is kicked.
-- Studio (no TeleportData): Story stage 1 with everyone who joined within a few seconds.
if IS_MATCH_PLACE then
	local MATCH_WAIT = 20
	local STUDIO_WAIT = 3
	local info = nil
	local firstJoin = 0

	local function tryStart()
		if not info or workspace:GetAttribute("State") ~= "Menu" then return end
		local present = {}
		for _, userId in ipairs(info.Members) do
			local p = Players:GetPlayerByUserId(userId)
			if p then table.insert(present, p) end
		end
		local waited = os.clock() - firstJoin
		if #present == 0 then return end
		if info.Direct and waited < STUDIO_WAIT then return end
		if not info.Direct and #present < #info.Members and waited < MATCH_WAIT then return end
		local host = Players:GetPlayerByUserId(info.HostId) or present[1]
		startGame(info.StageId, present, host)
	end

	-- a server the lobby reserved (not a public server, not a bought private server)
	local isReservedServer = game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0

	Players.PlayerAdded:Connect(function(player)
		local data = player:GetJoinData().TeleportData
		local fromLobby = typeof(data) == "table" and typeof(data.RoomKey) == "string"
			and Config.Stages[data.StageId] ~= nil and typeof(data.Members) == "table"
		if not RunService:IsStudio() then
			if not isReservedServer or not fromLobby then
				player:Kick("Stages are started from the lobby: press PLAY there.")
				return
			end
			if not table.find(data.Members, player.UserId) or (info and data.RoomKey ~= info.RoomKey) then
				player:Kick("This stage belongs to another lobby.")
				return
			end
		end
		if not info then
			if fromLobby then
				info = { RoomKey = data.RoomKey, StageId = data.StageId, HostId = data.HostId, Members = data.Members }
				returnPlaceId = typeof(data.ReturnPlaceId) == "number" and data.ReturnPlaceId or nil
			else
				info = { StageId = Config.DefaultStage, HostId = player.UserId, Members = {}, Direct = true }
			end
			firstJoin = os.clock()
		end
		if info.Direct and workspace:GetAttribute("State") == "Menu" and not table.find(info.Members, player.UserId) then
			table.insert(info.Members, player.UserId)
		end
		tryStart()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			tryStart()
		end
	end)
end

-- Studio check of the summon banners (Config.DebugSummonSim): real numbers vs the config
if RunService:IsStudio() and Config.DebugSummonSim then
	task.spawn(function()
		local Banners = require(script.Parent:WaitForChild("Banners"))
		for _, bannerId in ipairs(Config.BannerOrder) do Banners.simulate(bannerId, 10000) end
	end)
end

-- ===== Main loop =====
RunService.Heartbeat:Connect(function(dt)
	if workspace:GetAttribute("State") ~= "Playing" then return end
	if workspace:GetAttribute("Phase") ~= "Match" then return end
	local speed = workspace:GetAttribute("GameSpeed") or 1
	local gdt = dt * speed
	gameTime += gdt
	lastGdt = gdt
	stageTime += dt -- the stage timer is real time (not affected by x2 / x3)
	stageSyncTimer += dt
	if stageSyncTimer >= 0.5 then publishStage() end
	updateEnemies(gdt)
	if workspace:GetAttribute("State") ~= "Playing" then return end
	updateHits()
	if workspace:GetAttribute("State") ~= "Playing" then return end
	updateStatus(gdt)
	if workspace:GetAttribute("State") ~= "Playing" then return end
	updateTowers()
end)
