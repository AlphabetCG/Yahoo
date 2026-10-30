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
Config.UnitOrder = { "Herobrine", "Voidseer" }
Config.Units = {
	Herobrine = {
		Rarity = "Rare",
		Cost = 400,
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
	-- Legendary test unit: strong from the start, about 2.5x Herobrine's damage per second at every level
	Voidseer = {
		Rarity = "Legendary",
		Cost = 900,
		BeamColor = Color3.fromRGB(140, 100, 255),
		Levels = {
			{ Damage = 4, Range = 38, Cooldown = 0.5 },
			{ Cost = 700, Name = "Focused Sight", Damage = 5, Range = 42, Cooldown = 0.45 },
			{ Cost = 1400, Name = "Void Pulse", Damage = 7, Range = 46, Cooldown = 0.38 },
			{ Cost = 2800, Name = "Violet Burst", Damage = 10, Range = 50, Cooldown = 0.3,
				Ability = { Kind = "Slow", Pct = 0.2, Duration = 1 } },
			{ Cost = 5000, Name = "Boundless Void", Damage = 15, Range = 56, Cooldown = 0.2,
				Ability = { Kind = "Slow", Pct = 0.35, Duration = 1.5 } },
		},
	},
}

function Config.GetStats(unitName, level)
	local unit = Config.Units[unitName]
	return unit and unit.Levels[level]
end

-- ===== Rarity =====
-- Every unit in Config.Units needs a Rarity from this list.
--   Order = sort order (higher = rarer), MaxLevel = account level cap, SellValue = gems when sold
Config.RarityOrder = { "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Config.Rarities = {
	Rare = { Color = Color3.fromRGB(80, 160, 255), Order = 1, MaxLevel = 30, SellValue = 5 },
	Epic = { Color = Color3.fromRGB(180, 90, 255), Order = 2, MaxLevel = 40, SellValue = 15 },
	Legendary = { Color = Color3.fromRGB(255, 196, 40), Order = 3, MaxLevel = 50, SellValue = 40 },
	Mythic = { Color = Color3.fromRGB(255, 70, 110), Order = 4, MaxLevel = 60, SellValue = 100 },
	Secret = { Color = Color3.fromRGB(30, 30, 30), Order = 5, MaxLevel = 60, SellValue = 250 },
}

function Config.RarityOf(unitName)
	local unit = Config.Units[unitName]
	return Config.Rarities[unit and unit.Rarity or "Rare"] or Config.Rarities.Rare
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

-- every new player starts with these units: { UnitName = copies }
Config.StarterUnits = { Herobrine = 1 }
Config.StarterGems = 300
Config.MaxUnitsOwned = 150   -- unit storage; summons are refused once it is full
Config.LoadoutSlots = 6      -- equipped units (used by the loadout, coming later)
-- Studio play tests only: every player gets one copy of each of these units if they don't own one yet
Config.StudioGrantUnits = { "Voidseer" }

-- rewards when a stage ends (granted by the server)
Config.Rewards = {
	VictoryGems = 150,
	DefeatGems = 20,
	GemsPerRound = 5,       -- extra gems for every round reached (any result except surrender)
	EssenceBase = 10,       -- Wisp Essence for clearing the stage
	KillsPerEssence = 8,    -- ...plus 1 Wisp Essence per this many enemies defeated
	BossCrystals = 1,       -- Void Crystals when the boss is defeated
}

-- Summon: spend Gems to get a random unit. Pool = { UnitName = weight }; every unit in the pool
-- must exist in Config.Units. New units show up in the summon as soon as you add them here.
Config.Summon = {
	Cost = 100,
	Pool = { Herobrine = 95, Voidseer = 5 },
}

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
