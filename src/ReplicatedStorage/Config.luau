-- Config: all the numbers you may want to tweak live here.
-- Used by both the server (GameServer) and the client (ClientMain).

local Config = {}

-- ===== Game rules =====
Config.StartMoney = 650
Config.StartLives = 100
Config.TotalRounds = 15
Config.RewardPerPop = 2        -- money per whole enemy health point removed
Config.RoundBonus = 160        -- money for reaching round 2 (each following round adds RoundBonusStep more)
Config.RoundBonusStep = 30     -- (solo full clear: about 13,200 money in total = 2.6 maxed Herobrines)
Config.DebugEconomy = false    -- print every player's income by source (start / pops / round bonus / refunds) when a stage ends
Config.PrepTime = 60           -- seconds of preparation before the match starts (players can also press START MATCH)
Config.MaxSpawnTime = 36       -- a wave spawns all of its enemies within this many seconds (x1 speed); big waves spawn faster
Config.EnemiesBase = 6         -- enemies in a wave = EnemiesBase + round * EnemiesPerRound (rounded)
Config.EnemiesPerRound = 3.2   -- (54 enemies in round 15; fewer but tougher, see HpPerRound)
Config.HpPerRound = 0.09       -- enemy health = Tiers[tier].HP * (1 + HpPerRound * (round - 1))
Config.SkipSpawnMin = 0.6       -- AUTO SKIP ON: the next round starts once this share of the wave has appeared
Config.SkipSpawnMax = 0.7       -- (a random value between Min and Max is picked every round)
Config.WaveClearTime = 20       -- AUTO SKIP OFF: after the last enemy of a wave appears, the next round starts
                                -- when this many seconds (game time) have passed or every enemy is gone
Config.AutoSkipDefault = true   -- AUTO SKIP on/off when the game loads (players can toggle it in game)
Config.SpawnInterval = 1.6     -- seconds between enemies (bigger = slower spawning)
Config.EnemySpacing = 6        -- studs between two enemies: they walk the path center in single file,
                               -- a faster one queues behind a slower one, and spawning waits for room
Config.SpawnGrace = 0.1        -- real seconds a new enemy stays untargetable, so clients have drawn it before units shoot it
Config.ShotTravel = 0.12       -- real seconds a shot takes to land; damage is applied when the bolt arrives
Config.SpeedOptions = { 1, 2, 3 } -- game speed choices (x1, x2, x3)
Config.SellRefund = 0.5        -- selling a unit returns this share of everything spent on it
Config.TargetModes = { "First", "Last", "Strongest", "Weakest", "Closest", "None" }

-- ===== Multiplayer (one server = one match) =====
Config.MaxPartySize = 4        -- players who can play a stage together; anyone else in the server spectates
-- Money is shared: every pop and round bonus pays EVERY player in the match this share of the solo amount
-- (index = number of players), so nobody steals kills. 2 players: 2 x 0.65 = 1.3x the solo income in total.
Config.TeamIncome = { 1.0, 0.65, 0.5, 0.42 }
Config.HpPerExtraPlayer = 0.35 -- enemies get +35% health for every player after the first
-- every player gets one of these colours: their units are outlined in it and it shows in the party panel
Config.PlayerColors = {
	Color3.fromRGB(70, 200, 255),  -- cyan
	Color3.fromRGB(255, 90, 200),  -- pink
	Color3.fromRGB(140, 240, 80),  -- lime
	Color3.fromRGB(255, 160, 50),  -- orange
}

-- ===== Places =====
-- The same scripts run in both places of the experience; they check game.PlaceId to know which one this is.
--   Lobby = the start place: menus, inventory, summon, lobby rooms. No map: START always
--           teleports the room to the Match place. (Synced with default.project.json.)
--   Match = the Match place: the map and the stages. (Synced with match.project.json.)
-- Set Match to 0 to keep everything in one place (needs the map in that place: use match.project.json).
Config.Places = {
	Match = 114181242148498,
}

-- "Lobby", "Match", or "Single" (Config.Places.Match = 0: menus and stages in the same place)
function Config.PlaceRole()
	if Config.Places.Match == 0 then return "Single" end
	return game.PlaceId == Config.Places.Match and "Match" or "Lobby"
end

-- ===== Play: modes > maps > stages =====
-- PLAY opens: Select Mode > Select Map > Select Stage > Create Lobby (Public / Friends / Invite) or
-- Matchmaking > Invite players + Start.
Config.ModeOrder = { "Story", "Infinite", "Challenge", "Raid" }
Config.Modes = {
	Story = { Name = "Story", Color = Color3.fromRGB(90, 170, 255), Desc = "Fixed rounds with a boss at the end. Clear a stage to unlock the next one." },
	Infinite = { Name = "Infinite", Color = Color3.fromRGB(170, 100, 255), Desc = "Endless waves that keep getting stronger. A boss every 10 rounds." },
	Challenge = { Name = "Challenge", Color = Color3.fromRGB(255, 150, 50), Desc = "Stages with special rules. Bigger rewards." },
	Raid = { Name = "Raid", Color = Color3.fromRGB(240, 70, 80), Desc = "A boss every round, each one tougher than the last." },
}

-- Map = which path (Workspace folder of numbered parts) the stage is played on
Config.MapOrder = { "Meadow" }
Config.Maps = {
	Meadow = { Name = "Sunny Meadow", Waypoints = "Waypoints", Color = Color3.fromRGB(110, 190, 80) },
}

-- Difficulty multiplies enemy health / speed and the stage rewards
Config.DifficultyOrder = { "Normal", "Hard", "Nightmare" }
Config.Difficulties = {
	Normal = { Name = "Normal", Color = Color3.fromRGB(120, 220, 120), Health = 1, Speed = 1, Rewards = 1 },
	Hard = { Name = "Hard", Color = Color3.fromRGB(255, 190, 60), Health = 1.6, Speed = 1.1, Rewards = 1.5 },
	Nightmare = { Name = "Nightmare", Color = Color3.fromRGB(240, 70, 80), Health = 2.5, Speed = 1.2, Rewards = 2.2 },
}

-- Stages. Rounds = 0 means endless (Infinite). Order = position in the stage list of its mode + map.
-- Story stages unlock in Order (clear stage 1 to unlock stage 2...).
-- Rules (optional): EnemyHealth / EnemySpeed (multipliers), StartMoney, Rarities = { Epic = true } (only
--   those rarities can be placed), BossEvery (a boss every N rounds), BossHealth (multiplier),
--   EscortShare (Raid: how much of a normal wave walks with each boss).
Config.Stages = {
	Story_Meadow_1 = { Mode = "Story", Map = "Meadow", Order = 1, Name = "Stage 1", Difficulty = "Normal", Rounds = 15 },
	Story_Meadow_2 = { Mode = "Story", Map = "Meadow", Order = 2, Name = "Stage 2", Difficulty = "Hard", Rounds = 15 },
	Story_Meadow_3 = { Mode = "Story", Map = "Meadow", Order = 3, Name = "Stage 3", Difficulty = "Nightmare", Rounds = 15 },
	Infinite_Meadow = { Mode = "Infinite", Map = "Meadow", Order = 1, Name = "Endless", Difficulty = "Normal", Rounds = 0,
		Rules = { BossEvery = 10 } },
	Challenge_Meadow_Speed = { Mode = "Challenge", Map = "Meadow", Order = 1, Name = "Speed Rush", Difficulty = "Hard", Rounds = 10,
		Rules = { EnemySpeed = 1.5 }, Rewards = 1.3 },
	Challenge_Meadow_Epic = { Mode = "Challenge", Map = "Meadow", Order = 2, Name = "Epic Only", Difficulty = "Normal", Rounds = 12,
		Rules = { Rarities = { Epic = true } }, Rewards = 1.3 },
	Challenge_Meadow_Broke = { Mode = "Challenge", Map = "Meadow", Order = 3, Name = "Low Budget", Difficulty = "Normal", Rounds = 12,
		Rules = { StartMoney = 300 }, Rewards = 1.3 },
	Raid_Meadow_1 = { Mode = "Raid", Map = "Meadow", Order = 1, Name = "Wisp King Raid", Difficulty = "Hard", Rounds = 5,
		Rules = { BossEvery = 1, BossHealth = 0.6, EscortShare = 0.3 }, Rewards = 1.6 },
}
Config.DefaultStage = "Story_Meadow_1"

-- Stages of a mode on a map, in Order
function Config.StagesFor(mode, map)
	local list = {}
	for id, stage in pairs(Config.Stages) do
		if stage.Mode == mode and stage.Map == map then
			table.insert(list, id)
		end
	end
	table.sort(list, function(a, b) return Config.Stages[a].Order < Config.Stages[b].Order end)
	return list
end

-- The Story stage that must be cleared first (nil = always open)
function Config.StageRequirement(stageId)
	local stage = Config.Stages[stageId]
	if not stage or stage.Mode ~= "Story" or stage.Order <= 1 then return nil end
	for id, other in pairs(Config.Stages) do
		if other.Mode == stage.Mode and other.Map == stage.Map and other.Order == stage.Order - 1 then
			return id
		end
	end
	return nil
end

-- ===== Lobbies =====
Config.LobbyPrivacy = { "Public", "Friends", "Invite" } -- Public: anyone / matchmaking, Friends: the host's friends, Invite: invited players only

-- ===== Map =====
Config.GroundY = 0
Config.PathTop = 0.4
Config.PathWidth = 10
Config.TowerSpacing = 6        -- minimum distance between two units
Config.DefaultPlaceLimit = 3   -- each unit can be on the map at most this many times per player (a unit can set its own PlaceLimit)
Config.Bounds = { MinX = -78, MaxX = 78, MinZ = -42, MaxZ = 42 }

-- ===== Units (towers) =====
-- Each name must match a sprite in ReplicatedStorage.PixelArt.
-- Levels[1] is the stats when placed. Every following entry is a REFINE (in-match upgrade):
--   Cost = price of that refine, Name = shown in the refine panel,
--   Damage / Range / Cooldown = the unit's NEW stats after buying it (Cooldown is shown as SPA, seconds per attack),
--   Ability = optional effect every hit applies from that level on (see Config.DescribeAbility):
--     { Kind = "Burn", Dps = n, Duration = s }  damage over time (money is paid for burn damage too)
--     { Kind = "Slow", Pct = 0.3, Duration = s } walks Pct slower (the line behind it slows down too)
-- PlaceLimit = optional: overrides Config.DefaultPlaceLimit for this unit (copies on the map per player).
-- CanHitAir = true: the unit can hit Flying enemies (see Config.EnemyTypes).
-- Attack = optional attack shape, on the unit or on an upgrade level (a level keeps the shape of the
--   closest level below it that sets one). Without it the unit hits one enemy ("Single").
--     { Kind = "Splash", Radius = 6, SplashPct = 0.5 }  the target + everyone within Radius studs of it (SplashPct damage)
--     { Kind = "Line", Width = 4, MaxHits = 6 }          a beam to the end of the range through the target
--     { Kind = "Cone", Angle = 70, MaxHits = 4 }         everyone in range inside a cone towards the target
--     { Kind = "Circle", MaxHits = 5 }                    everyone in range around the unit (Radius = optional)
--   The target always takes full damage; MaxHits caps the enemies hit (the ones closest to the castle first).
-- Image = optional: draw the unit from an uploaded image (sprite sheet) instead of its PixelArt grid.
--   Image = {
--     Id = "rbxassetid://123456789",   -- the IMAGE asset id ("" = keep using the PixelArt grid)
--     Size = { 16, 22 },               -- size on screen in art pixels (Herobrine is 14 x 18; 2 art px = 1 stud)
--     FrameSize = { 64, 88 },          -- pixels of ONE frame inside the uploaded file
--     Frames = { Idle = { 0, 0 }, Attack = { 1, 0 } }, -- optional: column / row of each frame in the sheet
--   },
--   Draw the character facing RIGHT (it is mirrored when it faces left). Use a transparent PNG and
--   make FrameSize an exact multiple of Size (e.g. 4x) so the pixels stay sharp.
--   The units below use unitImage: their PNGs are in assets/units/, the ids in Config.UnitImages.
-- Type = optional, what the unit does instead of shooting (see Config.UnitTypes): "Farm", "Buffer",
--   "Summoner" or "Wipe". Without it the unit attacks normally.
-- Unobtainable = true: never drops from a banner (Lord Moon: given to developers only).
Config.UnitOrder = { "Herobrine", "Roy", "Zaruto", "Fluffy", "Ichitoe", "FlowerMage", "Voidseer", "PuppetNinja", "LordMoon" }

-- Uploaded image ids ("rbxassetid://...") of the PNGs in assets/units/ (<Name>_4x.png: the character
-- cropped from artifacts/, 4 image pixels per art pixel). "" = not uploaded yet: the grid is drawn.
Config.UnitImages = {
	Voidseer = "rbxassetid://76702300407156",
	Zaruto = "rbxassetid://123140835797676",
	Fluffy = "rbxassetid://116018563884691",
	Ichitoe = "rbxassetid://99880058622124",
	Roy = "rbxassetid://109673376495230",
	FlowerMage = "rbxassetid://114595170403535",
	PuppetNinja = "rbxassetid://113572590772166",
	PuppetNinjaPuppet = "rbxassetid://136682912365586",
	LordMoon = "rbxassetid://107445243878977",
}
-- An Image table for assets/units/<file>_4x.png, drawn `w` x `h` art pixels (the file is 4x that)
local function unitImage(file, w, h)
	return { Id = Config.UnitImages[file] or "", Size = { w, h }, FrameSize = { w * 4, h * 4 } }
end

-- What the non-attacking unit types do (stats per level are in their Levels):
--   Farm      Income = money paid to the owner when each wave ends (when the next round starts)
--   Buffer    Buff = extra damage (0.2 = +20%) for every unit within its Range (strongest buff counts, no stacking)
--   Summoner  every Cooldown seconds sends a summon (Config.Summons[unit.Summon]) from the castle back
--             along the path. Damage = the summon's max HP: an enemy it touches takes damage up to the
--             summon's remaining HP, and the summon loses that much. It hits Flying enemies too; no cap.
--   Wipe      every Cooldown seconds, every enemy on the map (Flying and the boss too) is killed
Config.UnitTypes = { Farm = true, Buffer = true, Summoner = true, Wipe = true }

-- Summons walking the path (drawn by the client from workspace.Summons)
Config.Summons = {
	Puppet = { Name = "Puppet", Sprite = "PuppetNinjaPuppet", Speed = 7, Radius = 2 },
}
-- Sprites that are not units but are drawn from an uploaded image (PixelArt looks here too)
Config.Sprites = {
	PuppetNinjaPuppet = { Image = unitImage("PuppetNinjaPuppet", 10, 20) },
}
Config.Units = {
	Herobrine = {
		Rarity = "Rare",
		Cost = 400,
		CanHitAir = true, -- can hit Flying enemies
		BeamColor = Color3.fromRGB(255, 255, 255),
		Levels = {
			{ Damage = 2, Range = 30, Cooldown = 0.6 },
			{ Cost = 300, Name = "Longer Gaze", Damage = 2, Range = 36, Cooldown = 0.6 },
			{ Cost = 600, Name = "Rapid Gaze", Damage = 3, Range = 36, Cooldown = 0.45 },
			{ Cost = 1200, Name = "Burning Gaze", Damage = 4, Range = 40, Cooldown = 0.35,
				Ability = { Kind = "Burn", Dps = 1, Duration = 2 } },
			{ Cost = 2500, Name = "Ultimate Herobrine", Damage = 6, Range = 46, Cooldown = 0.25,
				Ability = { Kind = "Burn", Dps = 2, Duration = 2.5 } },
		},
	},
	-- Epic, rapid-fire: tiny hits very fast, short range; final refine sets enemies on fire
	Zaruto = {
		Image = unitImage("Zaruto", 10, 26),
		Rarity = "Epic",
		Cost = 600,
		CanHitAir = true, -- can hit Flying enemies
		BeamColor = Color3.fromRGB(255, 150, 40),
		Levels = {
			{ Damage = 1, Range = 26, Cooldown = 0.2 },
			{ Cost = 500, Name = "Swift Kunai", Damage = 1, Range = 28, Cooldown = 0.16 },
			{ Cost = 1000, Name = "Clone Rush", Damage = 2, Range = 30, Cooldown = 0.18 },
			{ Cost = 2000, Name = "Spiral Strike", Damage = 3, Range = 32, Cooldown = 0.15 },
			{ Cost = 3800, Name = "Fox Fury", Damage = 3, Range = 34, Cooldown = 0.2,
				Ability = { Kind = "Burn", Dps = 2, Duration = 2 }, Attack = { Kind = "Circle", MaxHits = 5 } },
		},
	},
	-- Epic, long reach: stretchy punches from far away; last refines briefly slow enemies
	Fluffy = {
		Image = unitImage("Fluffy", 12, 26),
		Rarity = "Epic",
		Cost = 600,
		BeamColor = Color3.fromRGB(240, 70, 60),
		Levels = {
			{ Damage = 3, Range = 42, Cooldown = 0.6 },
			{ Cost = 500, Name = "Stretch Punch", Damage = 3, Range = 46, Cooldown = 0.55 },
			{ Cost = 1000, Name = "Rapid Fists", Damage = 4, Range = 48, Cooldown = 0.4 },
			{ Cost = 2000, Name = "Giant Fist", Damage = 7, Range = 50, Cooldown = 0.35,
				Ability = { Kind = "Slow", Pct = 0.15, Duration = 0.6 }, Attack = { Kind = "Splash", Radius = 6, SplashPct = 0.5 } },
			{ Cost = 3800, Name = "Rubber King", Damage = 10, Range = 54, Cooldown = 0.25,
				Ability = { Kind = "Slow", Pct = 0.25, Duration = 1 } },
		},
	},
	-- Epic, heavy hitter: big slow sword swings at short range; great against tough enemies and the boss
	Ichitoe = {
		Image = unitImage("Ichitoe", 19, 26),
		Rarity = "Epic",
		Cost = 600,
		BeamColor = Color3.fromRGB(220, 60, 60),
		Levels = {
			{ Damage = 6, Range = 24, Cooldown = 1.0, Attack = { Kind = "Cone", Angle = 60, MaxHits = 3 } },
			{ Cost = 500, Name = "Heavy Slash", Damage = 7, Range = 26, Cooldown = 0.9 },
			{ Cost = 1000, Name = "Crescent Fang", Damage = 10, Range = 30, Cooldown = 0.8 },
			{ Cost = 2000, Name = "Dark Mask", Damage = 16, Range = 32, Cooldown = 0.6 },
			{ Cost = 3800, Name = "Final Release", Damage = 26, Range = 36, Cooldown = 0.6,
				Attack = { Kind = "Cone", Angle = 80, MaxHits = 5 } },
		},
	},
	-- Legendary test unit: strong from the start, about 2.5x Herobrine's damage per second at every level
	Voidseer = {
		Image = unitImage("Voidseer", 12, 26),
		Rarity = "Legendary",
		Cost = 900,
		CanHitAir = true, -- can hit Flying enemies
		BeamColor = Color3.fromRGB(140, 100, 255),
		Levels = {
			{ Damage = 4, Range = 38, Cooldown = 0.5 },
			{ Cost = 700, Name = "Focused Sight", Damage = 5, Range = 42, Cooldown = 0.45 },
			{ Cost = 1400, Name = "Void Pulse", Damage = 7, Range = 46, Cooldown = 0.38 },
			{ Cost = 2800, Name = "Violet Burst", Damage = 10, Range = 50, Cooldown = 0.3,
				Ability = { Kind = "Slow", Pct = 0.2, Duration = 1 }, Attack = { Kind = "Line", Width = 4, MaxHits = 4 } },
			{ Cost = 5000, Name = "Boundless Void", Damage = 15, Range = 56, Cooldown = 0.2,
				Ability = { Kind = "Slow", Pct = 0.35, Duration = 1.5 }, Attack = { Kind = "Line", Width = 5, MaxHits = 6 } },
		},
	},
	-- Rare farm: no attack; pays its owner Income when each wave ends
	Roy = {
		Image = unitImage("Roy", 17, 26),
		Rarity = "Rare",
		Type = "Farm",
		Cost = 300,
		PlaceLimit = 2,
		BeamColor = Color3.fromRGB(190, 150, 90),
		Levels = {
			{ Damage = 0, Range = 8, Cooldown = 1, Income = 60 },
			{ Cost = 250, Name = "Bigger Harvest", Damage = 0, Range = 8, Cooldown = 1, Income = 100 },
			{ Cost = 500, Name = "Second Field", Damage = 0, Range = 8, Cooldown = 1, Income = 180 },
			{ Cost = 1000, Name = "Market Day", Damage = 0, Range = 8, Cooldown = 1, Income = 320 },
			{ Cost = 2000, Name = "Golden Shovel", Damage = 0, Range = 8, Cooldown = 1, Income = 550 },
		},
	},
	-- Epic buffer: no attack; every unit in her range deals Buff more damage
	FlowerMage = {
		DisplayName = "Flower Mage",
		Image = unitImage("FlowerMage", 15, 26),
		Rarity = "Epic",
		Type = "Buffer",
		Cost = 500,
		PlaceLimit = 2,
		BeamColor = Color3.fromRGB(255, 150, 200),
		Levels = {
			{ Damage = 0, Range = 16, Cooldown = 1, Buff = 0.2 },
			{ Cost = 400, Name = "Blooming Aura", Damage = 0, Range = 18, Cooldown = 1, Buff = 0.2 },
			{ Cost = 800, Name = "Sweet Pollen", Damage = 0, Range = 20, Cooldown = 1, Buff = 0.25 },
			{ Cost = 1600, Name = "Spring Chorus", Damage = 0, Range = 22, Cooldown = 1, Buff = 0.3 },
			{ Cost = 3000, Name = "Eternal Garden", Damage = 0, Range = 26, Cooldown = 1, Buff = 0.35 },
		},
	},
	-- Legendary summoner: sends puppets from the castle down the path. Damage = a puppet's max HP
	-- (Range only draws the ring; the puppets go wherever the path goes)
	PuppetNinja = {
		DisplayName = "Puppet Ninja",
		Image = unitImage("PuppetNinja", 11, 26),
		Rarity = "Legendary",
		Type = "Summoner",
		Summon = "Puppet",
		Cost = 900,
		BeamColor = Color3.fromRGB(200, 60, 60),
		Levels = {
			{ Damage = 40, Range = 12, Cooldown = 10 },
			{ Cost = 700, Name = "Chakra Strings", Damage = 60, Range = 12, Cooldown = 10 },
			{ Cost = 1400, Name = "Puppet Army", Damage = 90, Range = 12, Cooldown = 10 },
			{ Cost = 2800, Name = "Iron Puppets", Damage = 140, Range = 12, Cooldown = 10 },
			{ Cost = 5000, Name = "Hundred Puppets", Damage = 200, Range = 12, Cooldown = 10 },
		},
	},
	-- Developer only (Unobtainable, given by GameServer): kills every enemy on the map every 5 seconds
	LordMoon = {
		DisplayName = "Lord Moon",
		Image = unitImage("LordMoon", 27, 30),
		Rarity = "Secret",
		Type = "Wipe",
		Unobtainable = true,
		Cost = 1000,
		PlaceLimit = 1,
		CanHitAir = true,
		BeamColor = Color3.fromRGB(110, 240, 220),
		Levels = {
			{ Damage = 0, Range = 6, Cooldown = 5 },
		},
	},
}

-- The unit's name as shown in the UI, upper case: its DisplayName (e.g. "Flower Mage"), or its key
function Config.DisplayName(unitName)
	local unit = Config.Units[unitName]
	return string.upper(unit and unit.DisplayName or tostring(unitName))
end

-- What a unit does instead of shooting (Config.UnitTypes), or nil for a normal attacking unit
function Config.UnitType(unitName)
	local unit = Config.Units[unitName]
	return unit and unit.Type or nil
end

-- One short line about a unit's main stat at refine level `stats` (shop and inventory cards)
function Config.UnitSummary(unitName, stats)
	local kind = Config.UnitType(unitName)
	local function num(v) return (("%.1f"):format(v):gsub("%.0$", "")) end
	if kind == "Farm" then
		return ("INCOME $%d / WAVE"):format(stats.Income or 0)
	elseif kind == "Buffer" then
		return ("BUFF +%d%%  RNG %s"):format(math.floor((stats.Buff or 0) * 100 + 0.5), num(stats.Range))
	elseif kind == "Summoner" then
		return ("PUPPET %s HP  EVERY %ss"):format(num(stats.Damage), num(stats.Cooldown))
	elseif kind == "Wipe" then
		return ("KILLS ALL EVERY %ss"):format(num(stats.Cooldown))
	end
	return ("DMG %s  RNG %s"):format(num(stats.Damage), num(stats.Range))
end

function Config.GetStats(unitName, level)
	local unit = Config.Units[unitName]
	return unit and unit.Levels[level]
end

-- ===== Rarity =====
-- Every unit in Config.Units needs a Rarity from this list.
--   Short = tag on small cards, Order = sort order (higher = rarer), MaxLevel = account level cap, SellGold = Gold paid when a copy is sold
Config.RarityOrder = { "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Config.Rarities = {
	Rare = { Short = "RARE", Color = Color3.fromRGB(80, 160, 255), Order = 1, MaxLevel = 30, SellGold = 5 },
	Epic = { Short = "EPIC", Color = Color3.fromRGB(180, 90, 255), Order = 2, MaxLevel = 40, SellGold = 15 },
	Legendary = { Short = "LEGEND", Color = Color3.fromRGB(255, 196, 40), Order = 3, MaxLevel = 50, SellGold = 40 },
	Mythic = { Short = "MYTHIC", Color = Color3.fromRGB(255, 70, 110), Order = 4, MaxLevel = 60, SellGold = 100 },
	Secret = { Short = "SECRET", Color = Color3.fromRGB(30, 30, 30), Order = 5, MaxLevel = 60, SellGold = 250 },
}

function Config.RarityOf(unitName)
	local unit = Config.Units[unitName]
	return Config.Rarities[unit and unit.Rarity or "Rare"] or Config.Rarities.Rare
end

-- ===== Unit leveling (account level, kept between stages) =====
-- Separate from Refine: a unit's level is saved on that copy and makes it stronger in every stage.
-- The level cap comes from its rarity (Config.Rarities[r].MaxLevel).
Config.Leveling = {
	XpBase = 20,          -- XP every equipped unit gets when a stage ends...
	XpPerRound = 4,       -- ...plus this much per round reached
	VictoryMult = 2,      -- ...times this on a stage clear (no XP for surrendering)
	XpPerEssence = 10,    -- feeding 1 Wisp Essence gives this much XP
	DamagePerLevel = 0.03, -- +3% damage per level above 1
	RangePerLevel = 0.1,   -- +0.1 range per level above 1...
	MaxRangeBonus = 4,     -- ...up to +4
}

-- XP needed to go from `level` to level + 1
function Config.XpToNext(level)
	return math.floor(20 * level ^ 1.5)
end

function Config.MaxUnitLevel(unitName)
	return Config.RarityOf(unitName).MaxLevel
end

-- Stats of a unit at refine level `refineLevel` (in-match) owned at account level `unitLevel`.
-- Returns a copy of Levels[refineLevel] with Damage / Range scaled (Ability etc. unchanged).
function Config.ScaledStats(unitName, refineLevel, unitLevel)
	local base = Config.GetStats(unitName, refineLevel)
	if not base then return nil end
	local L = Config.Leveling
	local above = math.max(0, (unitLevel or 1) - 1)
	local stats = table.clone(base)
	stats.Damage = base.Damage * (1 + L.DamagePerLevel * above)
	stats.Range = base.Range + math.min(L.RangePerLevel * above, L.MaxRangeBonus)
	return stats
end

-- Attack shape of a unit at an upgrade level (see Attack in Config.Units). Always returns a table.
local SINGLE = { Kind = "Single" }
function Config.AttackOf(unitName, refineLevel)
	local unit = Config.Units[unitName]
	if not unit then return SINGLE end
	for level = math.min(refineLevel or 1, #unit.Levels), 1, -1 do
		if unit.Levels[level].Attack then return unit.Levels[level].Attack end
	end
	return unit.Attack or SINGLE
end

-- Short text for an ability, e.g. "BURN 2/S FOR 2.5S" (nil when there is none)
function Config.DescribeAbility(ability)
	if not ability then return nil end
	local function num(v) return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")) end
	if ability.Kind == "Burn" then
		return ("BURN %s/S FOR %sS"):format(num(ability.Dps), num(ability.Duration))
	elseif ability.Kind == "Slow" then
		return ("SLOW %d%% FOR %sS"):format(math.floor(ability.Pct * 100 + 0.5), num(ability.Duration))
	end
	return string.upper(tostring(ability.Kind))
end

-- How many copies of a unit one player may have on the map at once
function Config.PlaceLimit(unitName)
	local unit = Config.Units[unitName]
	return (unit and unit.PlaceLimit) or Config.DefaultPlaceLimit
end

function Config.MaxLevel(unitName)
	local unit = Config.Units[unitName]
	return unit and #unit.Levels or 0
end

-- ===== Enemy tiers =====
-- The tier an enemy spawns with sets its speed (fixed for its whole life) and its base HP.
-- Health = HP * (1 + HpPerRound * (round - 1)). As it loses health its color steps down through
-- the lower tiers (a tier 4 wisp at half health looks like tier 2). Leaking costs lives equal to
-- the tier it currently shows.
Config.MaxTier = 5
Config.Tiers = {
	[1] = { Color = Color3.fromRGB(220, 60, 60), Speed = 5.5, HP = 1 },
	[2] = { Color = Color3.fromRGB(60, 120, 230), Speed = 6.5, HP = 2 },
	[3] = { Color = Color3.fromRGB(70, 190, 70), Speed = 8, HP = 3 },
	[4] = { Color = Color3.fromRGB(240, 210, 60), Speed = 9, HP = 4 },
	[5] = { Color = Color3.fromRGB(240, 130, 190), Speed = 11, HP = 5 },
}

-- ===== Enemy types =====
-- Every spawned enemy has a tier (colour / base HP / speed, above) AND a type that changes it:
--   Health / Speed = multipliers, Size = how much room it takes in the single-file line,
--   Lives = multiplier on the lives it costs when it reaches the castle,
--   Shield = share of its max HP as a shield that must be broken first (shield damage pays no money),
--   Flying = only units with CanHitAir can hit it; it flies over the line (doesn't queue, nobody queues
--   behind it). Overtakes = walks the path but passes other enemies (no queueing, nobody queues behind it).
--   Sprite = which PixelArt sprite is drawn.
Config.EnemyTypes = {
	Wisp = { Name = "Wisp", Sprite = "Wisp", Health = 1, Speed = 1 },
	Runner = { Name = "Runner", Sprite = "Runner", Health = 0.5, Speed = 1.7, Size = 0.8, Overtakes = true },
	Tank = { Name = "Tank", Sprite = "Tank", Health = 3, Speed = 0.6, Size = 1.3, Lives = 2 },
	Shielded = { Name = "Shielded", Sprite = "Wisp", Health = 1, Speed = 0.9, Shield = 0.5 },
	Flying = { Name = "Flyer", Sprite = "Flyer", Health = 0.8, Speed = 1.2, Flying = true },
}

-- Which types a wave is made of: the last entry whose FromRound <= the round is used.
-- Mix = { Type = weight }. Endless stages keep using the last entry.
Config.WaveMix = {
	{ FromRound = 1, Mix = { Wisp = 100 } },
	{ FromRound = 3, Mix = { Wisp = 80, Runner = 20 } },
	{ FromRound = 5, Mix = { Wisp = 60, Runner = 20, Tank = 20 } },
	{ FromRound = 7, Mix = { Wisp = 45, Runner = 20, Tank = 15, Shielded = 20 } },
	{ FromRound = 9, Mix = { Wisp = 35, Runner = 20, Tank = 15, Shielded = 15, Flying = 15 } },
}

-- A random enemy type for round r (weighted by Config.WaveMix)
function Config.EnemyTypeFor(r, rng)
	local mix = Config.WaveMix[1].Mix
	for _, entry in ipairs(Config.WaveMix) do
		if r >= entry.FromRound then mix = entry.Mix end
	end
	local total = 0
	for _, weight in pairs(mix) do total += weight end
	local roll = (rng and rng:NextNumber() or math.random()) * total
	local last = "Wisp"
	for _, name in ipairs({ "Wisp", "Runner", "Tank", "Shielded", "Flying" }) do
		local weight = mix[name]
		if weight then
			last = name
			roll -= weight
			if roll <= 0 then return name end
		end
	end
	return last
end

-- ===== Boss =====
-- One boss walks the path when round Boss.Round starts. If it reaches the castle it costs
-- its remaining health in lives (so 100+ health = instant defeat).
Config.Boss = {
	Name = "Wisp King",
	Round = Config.TotalRounds,
	Health = 200,
	Speed = 3.6,                        -- slower than every normal enemy
	Scale = 2.4,                        -- how much bigger its sprite is drawn than a normal wisp
	Color = Color3.fromRGB(150, 70, 220),
}

-- ===== Inventory / rewards =====
-- Items players can collect (shown in the inventory, saved in profile.Items). Add new ones here, then
-- hand them out from Config.Rewards or from any server script with PlayerData.AddItem(player, key, amount).
--   Kind = "Material" (crafting / upgrade resource) or "Consumable" (used up by an action)
Config.Materials = {
	WispEssence = { Name = "Wisp Essence", Kind = "Material", Color = Color3.fromRGB(110, 220, 130), Desc = "Dropped by wisps. Used for upgrades later." },
	VoidCrystal = { Name = "Void Crystal", Kind = "Material", Color = Color3.fromRGB(170, 90, 240), Desc = "Dropped by the Wisp King boss." },
}
Config.MaterialOrder = { "WispEssence", "VoidCrystal" }

-- These accounts (UserIds) get one copy of every unit they don't own yet each time they join,
-- Unobtainable ones (Lord Moon) included. For the team's own testing.
Config.AllUnitsUserIds = {
	[2366317550] = "AlphaboCG13",
	[152511219] = "FayMasterGame",
}

-- every new player starts with these units: { UnitName = copies }
Config.StarterUnits = { Herobrine = 1 }
Config.StarterGems = 300
-- Gold: earned by selling units (Config.Rarities[r].SellGold). Never sold for Robux.
-- What it can be spent on is still being decided (issue #50).
Config.GoldColor = Color3.fromRGB(255, 196, 60)
Config.MaxUnitsOwned = 150   -- unit storage; summons are refused once it is full
Config.LoadoutSlots = 6      -- equipped units: only these show up in the in-match shop (keys 1-6)
-- Studio play tests only: every player gets one copy of each of these units if they don't own one yet
Config.StudioGrantUnits = { "Voidseer", "Zaruto", "Fluffy", "Ichitoe" }

-- rewards when a stage ends (granted by the server)
Config.Rewards = {
	VictoryGems = 150,
	DefeatGems = 20,
	GemsPerRound = 5,       -- extra gems for every round reached (any result except surrender)
	EssenceBase = 10,       -- Wisp Essence for clearing the stage
	KillsPerEssence = 8,    -- ...plus 1 Wisp Essence per this many enemies defeated
	BossCrystals = 1,       -- Void Crystals when the boss is defeated
}

-- ===== Summon banners =====
-- A pull first rolls a RARITY (Rates, in %), then a unit of that rarity:
--   * the pool of a rarity = every unit with that Rarity, except Limited units (Limited = true in
--     Config.Units), which only drop from a banner that features them
--   * Featured = { Rarity = "UnitName" }: when that rarity is rolled, the featured unit is picked RateUp
--     of the time (0.5 = 50%); otherwise a random unit of that rarity
--   * a rarity without any unit in its pool (no Mythic units yet) is skipped and its share is spread
--     over the other rarities
-- Pity = { Rarity = N }: the Nth pull in a row without that rarity (or a better one) is guaranteed to
-- give it. Counters are per banner and per player and reset when that rarity (or better) drops.
-- StartsAt / EndsAt: unix time (UTC). Leave them out for a banner that is always on.
Config.BannerOrder = { "Launch", "Standard" }
Config.Banners = {
	Standard = {
		Name = "Standard Summon",
		Color = Color3.fromRGB(90, 170, 255),
		Cost = 100, Cost10 = 900,
		Rates = { Rare = 71, Epic = 24, Legendary = 5 },
		Pity = { Legendary = 60 },
	},
	Launch = {
		Name = "Void Awakening",
		Color = Color3.fromRGB(150, 100, 255),
		StartsAt = 1793491200, EndsAt = 1796083200, -- 1 Nov 2026 - 1 Dec 2026 (UTC)
		Cost = 100, Cost10 = 900,
		Rates = { Rare = 65, Epic = 28, Legendary = 6.5, Mythic = 0.5 },
		Featured = { Legendary = "Voidseer" },
		RateUp = 0.5,
		Pity = { Legendary = 50, Mythic = 300 },
	},
}
Config.DefaultBanner = "Standard"
Config.DebugSummonSim = false -- Studio: print a 10,000-pull simulation of every banner when the server starts

-- Is the banner open at unix time `now`?
function Config.BannerActive(bannerId, now)
	local banner = Config.Banners[bannerId]
	if not banner then return false end
	return (not banner.StartsAt or now >= banner.StartsAt) and (not banner.EndsAt or now < banner.EndsAt)
end

-- Units that can drop for `rarity` on this banner (sorted by name)
function Config.BannerPool(bannerId, rarity)
	local banner = Config.Banners[bannerId]
	local featured = banner and banner.Featured or {}
	local list = {}
	for name, unit in pairs(Config.Units) do
		if unit.Rarity == rarity and not unit.Unobtainable and (not unit.Limited or featured[rarity] == name) then
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

-- The banner's real chances, rarest first: { { Rarity, Chance (0-1), Units = { { Name, Chance } } } }.
-- Rarities with an empty pool are left out and the rest scaled up to 100%.
function Config.BannerRates(bannerId)
	local banner = Config.Banners[bannerId]
	if not banner then return {} end
	local rows, total = {}, 0
	for rarity, percent in pairs(banner.Rates) do
		local pool = Config.BannerPool(bannerId, rarity)
		if #pool > 0 and percent > 0 then
			table.insert(rows, { Rarity = rarity, Weight = percent, Pool = pool })
			total += percent
		end
	end
	table.sort(rows, function(a, b) return Config.Rarities[a.Rarity].Order > Config.Rarities[b.Rarity].Order end)
	for _, row in ipairs(rows) do
		row.Chance = row.Weight / total
		row.Units = {}
		local featured = banner.Featured and banner.Featured[row.Rarity]
		for _, name in ipairs(row.Pool) do
			local share
			if featured and #row.Pool > 1 then
				local rateUp = banner.RateUp or 0.5
				share = name == featured and rateUp or (1 - rateUp) / (#row.Pool - 1)
			else
				share = 1 / #row.Pool
			end
			table.insert(row.Units, { Name = name, Chance = row.Chance * share })
		end
	end
	return rows
end

-- ===== Path helpers =====
-- The path comes from the parts named "1", "2", "3"... inside Workspace.Waypoints.
-- Move those parts in Studio to change where enemies walk.
local cachedPath

function Config.GetPath()
	if cachedPath then return cachedPath end
	local folder = workspace:WaitForChild("Waypoints", 10)
	if not folder then return {} end
	local list = {}
	for _, p in ipairs(folder:GetChildren()) do
		local n = tonumber(p.Name)
		if n and p:IsA("BasePart") then
			table.insert(list, { n = n, pos = p.Position })
		end
	end
	table.sort(list, function(a, b) return a.n < b.n end)
	local result = {}
	for _, e in ipairs(list) do
		table.insert(result, Vector3.new(e.pos.X, Config.GroundY, e.pos.Z))
	end
	cachedPath = result
	return result
end

local function distToSegment(p, a, b)
	local p2 = Vector2.new(p.X, p.Z)
	local a2 = Vector2.new(a.X, a.Z)
	local ab = Vector2.new(b.X, b.Z) - a2
	local lenSq = ab:Dot(ab)
	local t = 0
	if lenSq > 0 then
		t = math.clamp((p2 - a2):Dot(ab) / lenSq, 0, 1)
	end
	return (p2 - (a2 + ab * t)).Magnitude
end

function Config.DistanceToPath(pos)
	local path = Config.GetPath()
	local best = math.huge
	for i = 1, #path - 1 do
		best = math.min(best, distToSegment(pos, path[i], path[i + 1]))
	end
	return best
end

-- Can a unit be placed at this spot? Returns true, or false + reason.
function Config.CanPlace(pos, towersFolder)
	local b = Config.Bounds
	if not (pos.X >= b.MinX and pos.X <= b.MaxX and pos.Z >= b.MinZ and pos.Z <= b.MaxZ) then
		return false, "Out of bounds"
	end
	if Config.DistanceToPath(pos) < Config.PathWidth / 2 + 2.5 then
		return false, "Too close to the path"
	end
	if towersFolder then
		local p2 = Vector2.new(pos.X, pos.Z)
		for _, t in ipairs(towersFolder:GetChildren()) do
			if t:IsA("Model") then
				local tp = t:GetPivot().Position
				if (Vector2.new(tp.X, tp.Z) - p2).Magnitude < Config.TowerSpacing then
					return false, "Too close to another unit"
				end
			end
		end
	end
	return true
end

return Config
