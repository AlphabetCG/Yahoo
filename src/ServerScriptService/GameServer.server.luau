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

-- saved player data: settings, gems, units, materials (adds its own remotes to the Remotes folder)
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
PlayerData.init(remotes)

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
workspace:SetAttribute("GameSpeed", 1)

local enemies = {}        -- list of { Part, Health, Pending, Born, Index, Dist, Dead }
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
local function giveMoney(player, amount)
	if player and player.Parent then
		player:SetAttribute("Money", (player:GetAttribute("Money") or 0) + amount)
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
local function tierInfo(health)
	return Config.Tiers[math.clamp(health, 1, Config.MaxTier)]
end

local function spawnEnemy(tier, isBoss)
	if #path < 2 then return end
	local part = Instance.new("Part")
	part.Name = "Enemy"
	part.Shape = Enum.PartType.Ball
	part.Size = isBoss and Vector3.new(6, 6, 6) or Vector3.new(3, 3, 3)
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 1 -- invisible: every client draws a pixel-art sprite for it
	part.CanQuery = false
	part:SetAttribute("Tier", tier)
	part:SetAttribute("Born", workspace:GetServerTimeNow())
	local startHealth = isBoss and Config.Boss.Health or tier
	part:SetAttribute("MaxHealth", startHealth)
	part:SetAttribute("Health", startHealth)
	if isBoss then
		part.Name = "Boss"
		part:SetAttribute("Boss", true)
	end
	part.Anchored = true
	part.CanCollide = false
	part.Position = path[1] + Vector3.new(0, ENEMY_HEIGHT, 0)
	part.Parent = enemiesFolder
	table.insert(enemies, {
		Part = part,
		Health = isBoss and Config.Boss.Health or tier,
		Boss = isBoss or false,
		Speed = isBoss and Config.Boss.Speed or nil,
		Pending = 0,
		Born = os.clock(),
		Index = 1,
		Dist = 0,
		Dead = false,
	})
end

local function damageEnemy(enemy, damage, owner)
	if enemy.Dead then return end
	local pops = math.min(damage, enemy.Health)
	enemy.Health -= damage
	giveMoney(owner, pops * Config.RewardPerPop)
	if enemy.Health <= 0 then
		enemy.Dead = true
		stageKills += 1
		if enemy.Boss then stageBossKilled = true end
		local idx = table.find(enemies, enemy)
		if idx then table.remove(enemies, idx) end
		enemy.Part:Destroy()
	else
		enemy.Part:SetAttribute("Health", enemy.Health)
		if not enemy.Boss then
			enemy.Part:SetAttribute("Tier", enemy.Health) -- the wisp changes color as it loses health
		end
	end
end

local function updateEnemies(dt)
	for i = #enemies, 1, -1 do
		local e = enemies[i]
		if not e then continue end
		local step = (e.Speed or tierInfo(e.Health).Speed) * dt
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
			-- reached the end of the path: costs lives
			table.remove(enemies, i)
			e.Dead = true
			e.Part:Destroy()
			loseLives(e.Health)
			if workspace:GetAttribute("State") ~= "Playing" then return end
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
				table.insert(pendingHits, { Enemy = best, Damage = t.Stats.Damage, Owner = t.Owner, Due = now + Config.ShotTravel })
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
			end
		end
	end
end

-- Units are invisible markers on the server (a model with one flat part).
-- Every client draws the pixel-art sprite itself from the model's attributes.
local function createTower(player, unitName, pos)
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
	}
	table.insert(towers, entry)
	towerByModel[model] = entry
	return model
end

placeTowerRemote.OnServerInvoke = function(player, unitName, pos)
	if workspace:GetAttribute("State") ~= "Playing" then return false, "Game is not running" end
	if typeof(unitName) ~= "string" or typeof(pos) ~= "Vector3" then return false, "Bad request" end
	local unit = Config.Units[unitName]
	if not unit then return false, "Unknown unit" end
	if not PlayerData.Owns(player, unitName) then return false, "You do not own this unit" end
	local money = player:GetAttribute("Money") or 0
	if money < unit.Cost then return false, "Not enough money" end
	local ok, reason = Config.CanPlace(pos, towersFolder)
	if not ok then return false, reason end
	player:SetAttribute("Money", money - unit.Cost)
	createTower(player, unitName, pos)
	return true
end

upgradeTowerRemote.OnServerInvoke = function(player, model)
	if workspace:GetAttribute("State") ~= "Playing" then return false, "Game is not running" end
	if typeof(model) ~= "Instance" then return false, "Bad request" end
	local t = towerByModel[model]
	if not t or not model.Parent then return false, "Unit not found" end
	if t.Owner ~= player then return false, "This is not your unit" end
	local nextLevel = t.Level + 1
	local nextStats = Config.GetStats(t.UnitName, nextLevel)
	if not nextStats then return false, "Already max level" end
	local money = player:GetAttribute("Money") or 0
	if money < nextStats.Cost then return false, "Not enough money" end

	player:SetAttribute("Money", money - nextStats.Cost)
	t.Level = nextLevel
	t.Spent += nextStats.Cost
	model:SetAttribute("Spent", t.Spent)
	t.Stats = nextStats
	model:SetAttribute("Level", nextLevel)
	if t.LevelLabel then
		t.LevelLabel.Text = (nextLevel >= Config.MaxLevel(t.UnitName)) and "MAX" or ("LV " .. nextLevel)
	end
	return true
end

-- Selling returns Config.SellRefund (50%) of everything spent on the unit (placement + upgrades)
sellTowerRemote.OnServerInvoke = function(player, model)
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
	giveMoney(player, refund)
	return true, refund
end

-- Targeting mode: First / Last / Strongest / Weakest / Closest / None
setTargetingRemote.OnServerEvent:Connect(function(player, model, mode)
	if workspace:GetAttribute("State") ~= "Playing" then return end
	if typeof(model) ~= "Instance" or typeof(mode) ~= "string" then return end
	if not table.find(Config.TargetModes, mode) then return end
	local t = towerByModel[model]
	if not t or t.Owner ~= player then return end
	t.Mode = mode
	model:SetAttribute("Targeting", mode)
end)

-- ===== Rounds =====
local function startGame()
	if workspace:GetAttribute("State") ~= "Menu" then return end
	clearAll()
	session += 1
	local mySession = session

	workspace:SetAttribute("Lives", Config.StartLives)
	workspace:SetAttribute("Round", 0)
	workspace:SetAttribute("Countdown", 0)
	workspace:SetAttribute("GameSpeed", 1)
	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("Money", Config.StartMoney)
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
		task.spawn(function()
			for _ = 1, count do
				if session ~= mySession then return end
				spawnEnemy(math.random(minTier, maxTier))
				progress.Spawned += 1
				if not gameWait(interval, mySession) then return end
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
					giveMoney(p, Config.RoundBonus + (r - 2) * Config.RoundBonusStep)
				end
			end
			if r == Config.Boss.Round then
				spawnEnemy(Config.MaxTier, true) -- the boss leads the final wave
			end
			progress = spawnRound(r)

			-- AUTO SKIP ON : the next round starts once 60-70% of this wave's enemies have appeared.
			-- AUTO SKIP OFF: the next round waits until this wave's timer runs out
			--                (every enemy of the wave has appeared).
			-- Enemies that haven't spawned yet keep spawning during the next round.
			if r < Config.TotalRounds then
				local fraction = Config.SkipSpawnMin + math.random() * (Config.SkipSpawnMax - Config.SkipSpawnMin)
				local need = math.max(1, math.ceil(progress.Count * fraction))
				local thisWave = progress
				local function target()
					if workspace:GetAttribute("AutoSkip") then return need end
					return thisWave.Count
				end
				while thisWave.Spawned < target() do
					local remaining = (target() - thisWave.Spawned) * thisWave.Interval
					workspace:SetAttribute("Countdown", math.max(1, math.ceil(remaining)))
					if not gameWait(0.25, mySession) then return end
				end
			end
		end

		workspace:SetAttribute("Countdown", 0)
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

startGameRemote.OnServerEvent:Connect(startGame)

returnToMenuRemote.OnServerEvent:Connect(function()
	local state = workspace:GetAttribute("State")
	if state == "GameOver" or state == "Victory" then
		goToMenu()
	end
end)

-- Surrender: ends the stage immediately and shows the STAGE FAILED screen
surrenderRemote.OnServerEvent:Connect(function()
	if workspace:GetAttribute("State") == "Playing" then
		endGame("GameOver", "Surrender")
	end
end)

-- Retry (from the stage clear / failed screen): reset everything and start a fresh prep phase
retryRemote.OnServerEvent:Connect(function()
	local state = workspace:GetAttribute("State")
	if state == "GameOver" or state == "Victory" then
		goToMenu()
		startGame()
	end
end)

-- Phase inside a game: "Prep" = place units + START MATCH button / countdown, "Match" = rounds running
workspace:SetAttribute("Phase", "Menu")
workspace:SetAttribute("PrepLeft", 0)
beginMatchRemote.OnServerEvent:Connect(function()
	if workspace:GetAttribute("State") == "Playing" and workspace:GetAttribute("Phase") == "Prep" then
		matchRequested = true
	end
end)

-- Auto skip: ON = next round starts when ~60-70% of the wave has appeared,
--            OFF = next round only starts when the wave's own timer runs out
workspace:SetAttribute("AutoSkip", Config.AutoSkipDefault)
setAutoSkipRemote.OnServerEvent:Connect(function(player, value)
	if typeof(value) == "boolean" then
		workspace:SetAttribute("AutoSkip", value)
		PlayerData.SetSetting(player, "AutoSkip", value) -- remembered between sessions
	end
end)

-- Game speed (x1 / x2 / x3)
setSpeedRemote.OnServerEvent:Connect(function(_, speed)
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
	updateTowers()
end)
