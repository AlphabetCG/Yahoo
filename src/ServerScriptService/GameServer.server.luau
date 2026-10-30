-- GameServer: runs the whole game (rounds, enemies, units, upgrades, money, lives, speed).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

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
local startGameRemote = newRemote("RemoteEvent", "StartGame")
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

-- saved player data: settings, gems, units, items (adds its own remotes to the Remotes folder)
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))
PlayerData.init(remotes)

-- ===== Host =====
-- The host is the player who has been in the server the longest. Only the host controls the match
-- flow (start, retry, menu, surrender, speed, auto skip). Shown to clients as workspace.HostId.
local joinOrder = {}

local function isHost(player)
	return player.UserId == workspace:GetAttribute("HostId")
end

-- the match follows the host's saved Auto Skip choice
local function applyHostSettings()
	local host = joinOrder[1]
	local profile = host and PlayerData.Get(host)
	if profile then
		workspace:SetAttribute("AutoSkip", profile.Settings.AutoSkip)
	end
end

local function updateHost()
	local host = joinOrder[1]
	local newId = host and host.UserId or 0
	if workspace:GetAttribute("HostId") ~= newId then
		workspace:SetAttribute("HostId", newId)
		applyHostSettings()
	end
end

Players.PlayerAdded:Connect(function(player)
	if not table.find(joinOrder, player) then table.insert(joinOrder, player) end
	updateHost()
end)
for _, p in ipairs(Players:GetPlayers()) do
	if not table.find(joinOrder, p) then table.insert(joinOrder, p) end
end
Players.PlayerRemoving:Connect(function(player)
	local idx = table.find(joinOrder, player)
	if idx then table.remove(joinOrder, idx) end
	updateHost()
end)
PlayerData.OnProfileLoaded(function(player)
	if isHost(player) then applyHostSettings() end
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

local path = Config.GetPath()
if #path < 2 then
	warn("GameServer: Workspace.Waypoints needs at least 2 parts named 1, 2, 3...")
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
local matchRequested = false -- set when a player presses START MATCH during the prep phase
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

local function setupPlayer(player)
	player:SetAttribute("Money", Config.StartMoney)
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
		-- hand out the stage rewards once, before clients see the result screen
		for _, p in ipairs(Players:GetPlayers()) do
			local rewards = PlayerData.GrantStageRewards(p, {
				Won = newState == "Victory",
				Round = workspace:GetAttribute("Round") or 0,
				Kills = stageKills,
				BossKilled = stageBossKilled,
				Surrender = reason == "Surrender",
			})
			remotes.StageRewards:FireClient(p, rewards)
		end
	end
	session += 1
	clearEnemies()
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("WaveState", "")
	workspace:SetAttribute("GameSpeed", 1)
	publishStage()
	workspace:SetAttribute("EndReason", reason or "")
	workspace:SetAttribute("State", newState)
end

local function goToMenu()
	session += 1
	clearAll()
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("GameSpeed", 1)
	workspace:SetAttribute("State", "Menu")
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

-- round = the round this enemy belongs to (sets its health)
local function spawnEnemy(tier, isBoss, round)
	if #path < 2 then return end
	local health = isBoss and Config.Boss.Health
		or tierInfo(tier).HP * (1 + Config.HpPerRound * math.max(0, (round or 1) - 1))
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
		Speed = isBoss and Config.Boss.Speed or tierInfo(tier).Speed,
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
	giveMoney(owner, pops * Config.RewardPerPop, "Pops")
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
				best.Pending += t.Stats.Damage
				table.insert(pendingHits, {
					Enemy = best, Damage = t.Stats.Damage, Ability = t.Stats.Ability,
					Owner = t.Owner, Due = now + Config.ShotTravel,
				})
				shotRemote:FireAllClients(t.Model, best.Part, targetPos)
			end
		end
	end
end

local function updateHits()
	local now = os.clock()
	for i = #pendingHits, 1, -1 do
		local h = pendingHits[i]
		if h.Due <= now then
			table.remove(pendingHits, i)
			local e = h.Enemy
			e.Pending = math.max(0, e.Pending - h.Damage)
			if not e.Dead then
				damageEnemy(e, h.Damage, h.Owner)
				applyAbility(e, h.Ability, h.Owner)
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

	model.Parent = towersFolder
	local entry = {
		Model = model,
		Root = root,
		UnitName = unitName,
		Level = 1,
		Stats = Config.GetStats(unitName, 1),
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
	if typeof(unitId) ~= "string" or typeof(pos) ~= "Vector3" then return false, "Bad request" end
	local instance = PlayerData.GetUnit(player, unitId)
	if not instance then return false, "You do not own this unit" end
	local unitName = instance.Name
	local unit = Config.Units[unitName]
	if not unit then return false, "Unknown unit" end
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
		t.Stats = nextStats
		bought += 1
		if all ~= true then break end
	end
	if bought == 0 then return false, "Not enough money" end
	model:SetAttribute("Spent", t.Spent)
	model:SetAttribute("Level", t.Level)
	return true, bought
end

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

local function startGame()
	if workspace:GetAttribute("State") ~= "Menu" then return end
	clearAll()
	session += 1
	local mySession = session

	workspace:SetAttribute("Lives", Config.StartLives)
	workspace:SetAttribute("Round", 0)
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("WaveState", "")
	workspace:SetAttribute("GameSpeed", 1)
	table.clear(stageIncome)
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("Money", Config.StartMoney)
		trackIncome(p, "Start", Config.StartMoney)
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

	-- Spawns one round's enemies, spread over at most Config.MaxSpawnTime seconds.
	-- Returns a progress table so the round timer can watch how many have appeared.
	local function spawnRound(r)
		local count = math.floor(Config.EnemiesBase + r * Config.EnemiesPerRound + 0.5)
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
			if r == Config.Boss.Round then
				-- the boss closes the final wave (it is the slowest, so nothing has to queue behind it)
				waitForRoom(true, mySession)
				if session ~= mySession then return end
				spawnEnemy(Config.MaxTier, true, r)
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

		local progress
		for r = 1, Config.TotalRounds do
			workspace:SetAttribute("Round", r)
			if r > 1 then
				-- bonus for reaching the next round
				for _, p in ipairs(Players:GetPlayers()) do
					giveMoney(p, Config.RoundBonus + (r - 2) * Config.RoundBonusStep, "RoundBonus")
				end
			end
			progress = spawnRound(r)

			-- AUTO SKIP ON : the next round starts once 60-70% of this wave's enemies have appeared
			--                (the rest keep spawning during the next round).
			-- AUTO SKIP OFF: no timer while the wave spawns. Once its last enemy has appeared a
			--                Config.WaveClearTime timer starts; the next round begins when it runs out
			--                or when every enemy on the map is gone.
			-- The setting is read once per round, so toggling it mid-wave applies from the next round.
			if r < Config.TotalRounds then
				local thisWave = progress
				workspace:SetAttribute("WaveState", "Spawning")
				if workspace:GetAttribute("AutoSkip") then
					local fraction = Config.SkipSpawnMin + math.random() * (Config.SkipSpawnMax - Config.SkipSpawnMin)
					local need = math.max(1, math.ceil(thisWave.Count * fraction))
					while thisWave.Spawned < need do
						local remaining = (need - thisWave.Spawned) * thisWave.Interval
						workspace:SetAttribute("Countdown", math.max(1, math.ceil(remaining)))
						if not gameWait(0.25, mySession) then return end
					end
				else
					workspace:SetAttribute("Countdown", 0)
					while thisWave.Spawned < thisWave.Count do
						if not gameWait(0.25, mySession) then return end
					end
					workspace:SetAttribute("WaveState", "Clearing")
					local deadline = gameTime + Config.WaveClearTime
					while gameTime < deadline and #enemies > 0 do
						workspace:SetAttribute("Countdown", math.max(1, math.ceil(deadline - gameTime)))
						if not gameWait(0.25, mySession) then return end
					end
				end
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

startGameRemote.OnServerEvent:Connect(function(player)
	if hostRequest(player, "StartGame") then startGame() end
end)

returnToMenuRemote.OnServerEvent:Connect(function(player)
	if not hostRequest(player, "ReturnToMenu") then return end
	local state = workspace:GetAttribute("State")
	if state == "GameOver" or state == "Victory" then
		goToMenu()
	end
end)

-- Surrender: ends the stage immediately and shows the STAGE FAILED screen
surrenderRemote.OnServerEvent:Connect(function(player)
	if not hostRequest(player, "Surrender") then return end
	if workspace:GetAttribute("State") == "Playing" then
		endGame("GameOver", "Surrender")
	end
end)

-- Retry (from the stage clear / failed screen): reset everything and start a fresh prep phase
retryRemote.OnServerEvent:Connect(function(player)
	if not hostRequest(player, "Retry") then return end
	local state = workspace:GetAttribute("State")
	if state == "GameOver" or state == "Victory" then
		goToMenu()
		startGame()
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

-- Auto skip: ON = next round starts when ~60-70% of the wave has appeared,
--            OFF = next round only starts when the wave's own timer runs out
-- Everyone's choice is saved; only the host's choice drives the match.
if workspace:GetAttribute("AutoSkip") == nil then
	workspace:SetAttribute("AutoSkip", Config.AutoSkipDefault)
end
setAutoSkipRemote.OnServerEvent:Connect(function(player, value)
	if typeof(value) ~= "boolean" or not RateLimit.allow(player, "SetAutoSkip", 2) then return end
	PlayerData.SetSetting(player, "AutoSkip", value) -- remembered between sessions
	if isHost(player) then
		workspace:SetAttribute("AutoSkip", value)
	end
end)

-- Game speed (x1 / x2 / x3)
setSpeedRemote.OnServerEvent:Connect(function(player, speed)
	if not hostRequest(player, "SetSpeed") then return end
	if workspace:GetAttribute("State") ~= "Playing" then return end
	if table.find(Config.SpeedOptions, speed) then
		publishStage()
		workspace:SetAttribute("GameSpeed", speed)
	end
end)

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
