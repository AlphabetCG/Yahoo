-- PlayerData: loads and saves every player's profile (settings, gems, units, items, stats)
-- in a DataStore, and hands out rewards / summons. Used by GameServer.
--
-- Profile layout (Version 2, saved as one table under "Player_<UserId>"):
--   Settings  = { AlwaysHealthBars = bool, AutoSkip = bool }
--   Gems      = number
--   Units     = { [uid] = { Id, Name, Level, XP, Trait, Locked, Obtained } }   (one entry per owned unit)
--   Loadout   = { uid or "", ... }                   (Config.LoadoutSlots entries; "" = empty slot)
--   Items     = { [itemKey] = amount }              (keys come from Config.Materials)
--   Summon    = { Total, Pity = { [bannerId] = { [rarity] = pulls } } }
--   Daily     = { Streak, LastClaimDay }
--   Codes     = { [CODE] = true }
--   Purchases = { [purchaseId] = os.time() }        (receipt idempotency)
--   Flags     = { StarterPack = bool }
--   Stats     = { StagesCleared, BossesKilled, Kills, Summons, RobuxSpent, FirstJoin }
-- The saved copy also carries Lock = { JobId, Time }: the session lock (never kept in memory).
--
-- To add a new setting: add it to defaultProfile() and to SETTING_TYPES below.
-- To change the layout: bump PROFILE_VERSION and add a MIGRATIONS[oldVersion] function.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))

local STORE_NAME = "PlayerData_v1" -- same store as before: v1 saves are migrated in place
local PROFILE_VERSION = 2
local AUTOSAVE_SECONDS = 60      -- every loaded profile is written this often (also refreshes the lock)
local MIN_SAVE_GAP = 7           -- DataStore allows one write per key about every 6 seconds
local LOCK_STALE_SECONDS = 180   -- a lock not refreshed for this long belongs to a dead server
local LOCK_WAIT_TRIES = 6        -- how often to retry while another server holds the lock...
local LOCK_WAIT_SECONDS = 5      -- ...and how long to wait between tries
local IS_STUDIO = RunService:IsStudio()
local JOB_ID =(game.JobId ~= "" and game.JobId) or ("studio-" .. HttpService:GenerateGUID(false))

local SETTING_TYPES = {
	AlwaysHealthBars = "boolean",
	AutoSkip = "boolean",
}

-- tables whose keys are open-ended (reconcile must not fill them with defaults)
local OPEN_TABLES = { Units = true, Items = true, Loadout = true, Codes = true, Purchases = true, Pity = true }

local store = DataStoreService:GetDataStore(STORE_NAME)

local PlayerData = {}
local profiles = {}   -- [player] = profile
local loadFailed = {} -- [player] = true when the saved data could not be read or is locked (we never save then)
local dirty = {}      -- [player] = true when there is something new to save
local lastSave = {}   -- [player] = os.clock() of the last save
local saving = {}     -- [player] = true while a save is running
local remotes = {}    -- filled by PlayerData.init
local loadedCallbacks = {}

local function deepCopy(t)
	if typeof(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepCopy(v) end
	return c
end

-- ===== unit instances =====
local function newUnitId(units)
	local id
	repeat
		id = "u_" .. HttpService:GenerateGUID(false):gsub("-", ""):sub(1, 12):lower()
	until units[id] == nil
	return id
end

local function newUnit(units, unitName)
	local id = newUnitId(units)
	local unit = {
		Id = id,
		Name = unitName,
		Level = 1,
		XP = 0,
		Trait = nil,
		Locked = false,
		Obtained = os.time(),
	}
	units[id] = unit
	return unit
end

local function countUnits(units, unitName)
	local total, ofName = 0, 0
	for _, u in pairs(units) do
		total += 1
		if u.Name == unitName then ofName += 1 end
	end
	return total, ofName
end

-- ===== loadout =====
-- Loadout is always an array of Config.LoadoutSlots strings: a unit id, or "" for an empty slot
-- (no holes, so it saves to the DataStore and travels over remotes cleanly).
local function normalizeLoadout(profile)
	local old = typeof(profile.Loadout) == "table" and profile.Loadout or {}
	local seen = {}
	local loadout = {}
	for slot = 1, Config.LoadoutSlots do
		local uid = old[slot]
		if typeof(uid) ~= "string" or not profile.Units[uid] or seen[uid] then uid = "" end
		if uid ~= "" then seen[uid] = true end
		loadout[slot] = uid
	end
	profile.Loadout = loadout
end

local function loadoutSlotOf(profile, uid)
	for slot, id in ipairs(profile.Loadout) do
		if id == uid then return slot end
	end
	return nil
end

local function firstEmptySlot(profile)
	for slot, id in ipairs(profile.Loadout) do
		if id == "" then return slot end
	end
	return nil
end

-- the best copy of a unit type: highest level, then the oldest
local function betterCopy(a, b)
	if a.Level ~= b.Level then return a.Level > b.Level end
	return (a.Obtained or 0) < (b.Obtained or 0)
end

-- Puts the best copy of every unit type that isn't equipped yet into the empty slots, rarest first.
local function fillLoadout(profile)
	local equippedNames = {}
	for _, uid in ipairs(profile.Loadout) do
		if uid ~= "" then equippedNames[profile.Units[uid].Name] = true end
	end
	local best = {}
	for _, u in pairs(profile.Units) do
		if Config.Units[u.Name] and not equippedNames[u.Name] and (not best[u.Name] or betterCopy(u, best[u.Name])) then
			best[u.Name] = u
		end
	end
	local list = {}
	for _, u in pairs(best) do table.insert(list, u) end
	table.sort(list, function(a, b)
		local ra, rb = Config.RarityOf(a.Name).Order, Config.RarityOf(b.Name).Order
		if ra ~= rb then return ra > rb end
		return a.Name < b.Name
	end)
	for _, u in ipairs(list) do
		local slot = firstEmptySlot(profile)
		if not slot then break end
		profile.Loadout[slot] = u.Id
	end
end

-- ===== unit leveling =====
-- Adds XP to a unit copy, levelling it up (capped by its rarity). Returns the number of levels gained.
local function addXp(unit, xp)
	local maxLevel = Config.MaxUnitLevel(unit.Name)
	if unit.Level >= maxLevel then
		unit.XP = 0
		return 0
	end
	unit.XP = (unit.XP or 0) + math.max(0, math.floor(xp))
	local gained = 0
	while unit.Level < maxLevel and unit.XP >= Config.XpToNext(unit.Level) do
		unit.XP -= Config.XpToNext(unit.Level)
		unit.Level += 1
		gained += 1
	end
	if unit.Level >= maxLevel then unit.XP = 0 end
	return gained
end

-- XP still needed to reach the level cap
local function xpToCap(unit)
	local maxLevel = Config.MaxUnitLevel(unit.Name)
	local need = 0
	for level = unit.Level, maxLevel - 1 do need += Config.XpToNext(level) end
	return math.max(0, need - (unit.XP or 0))
end

local function defaultProfile()
	local units = {}
	for name, copies in pairs(Config.StarterUnits) do
		if Config.Units[name] then
			for _ = 1, copies do newUnit(units, name) end
		end
	end
	return {
		Version = PROFILE_VERSION,
		Settings = { AlwaysHealthBars = false, AutoSkip = Config.AutoSkipDefault },
		Gems = Config.StarterGems,
		Units = units,
		Loadout = {}, -- filled by normalizeLoadout / fillLoadout when the profile loads
		Items = {},
		Summon = { Total = 0, Pity = {} },
		Daily = { Streak = 0, LastClaimDay = -1 },
		Codes = {},
		Purchases = {},
		Flags = { StarterPack = false },
		Stats = { StagesCleared = 0, BossesKilled = 0, Kills = 0, Summons = 0, RobuxSpent = 0, FirstJoin = os.time() },
	}
end

-- ===== migrations: MIGRATIONS[v] turns a version v profile into version v + 1 =====
local MIGRATIONS = {}

-- v1 -> v2: unit copy counts become unit instances, Materials becomes Items
MIGRATIONS[1] = function(data)
	local oldUnits = typeof(data.Units) == "table" and data.Units or {}
	local units = {}
	for name, copies in pairs(oldUnits) do
		if typeof(name) == "string" and typeof(copies) == "number" then
			for _ = 1, math.max(0, math.floor(copies)) do newUnit(units, name) end
		end
	end
	data.Units = units
	data.Items = typeof(data.Materials) == "table" and data.Materials or {}
	data.Materials = nil
	data.Stats = typeof(data.Stats) == "table" and data.Stats or {}
	data.Stats.FirstJoin = data.Stats.FirstJoin or os.time()
	data.Version = 2
end

local function migrate(data)
	local version = tonumber(data.Version) or 1
	while version < PROFILE_VERSION do
		local step = MIGRATIONS[version]
		if not step then
			error(("PlayerData: no migration from version %d"):format(version))
		end
		step(data)
		version += 1
		data.Version = version
	end
end

-- fills in anything missing from older saves (open-ended tables are left alone)
local function reconcile(data, default)
	for k, v in pairs(default) do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif typeof(v) == "table" and typeof(data[k]) == "table" and not OPEN_TABLES[k] then
			reconcile(data[k], v)
		end
	end
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- ===== session lock =====
-- Returns true when `lock` belongs to another server that is still alive.
-- In Studio, locks left by earlier Studio play tests are ignored (stopping a test can cut the last save short).
local function lockedByOther(lock)
	if typeof(lock) ~= "table" or lock.JobId == JOB_ID or typeof(lock.Time) ~= "number" then return false end
	if IS_STUDIO and typeof(lock.JobId) == "string" and lock.JobId:sub(1, 7) == "studio-" then return false end
	return os.time() - lock.Time < LOCK_STALE_SECONDS
end

-- ===== saving / loading =====
-- release = true drops the session lock (player leaving / server closing)
function PlayerData.Save(player, release)
	local profile = profiles[player]
	if not profile or loadFailed[player] then return false end
	-- wait for a running save instead of skipping, so the final save on leave is never lost
	local t0 = os.clock()
	while saving[player] and os.clock() - t0 < 30 do task.wait(0.1) end
	if saving[player] then return false end
	saving[player] = true
	local ok, err
	local stolen = false
	for attempt = 1, 3 do
		ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function(old)
				if typeof(old) == "table" and lockedByOther(old.Lock) then
					stolen = true
					return nil -- another server took the profile over: never overwrite its data
				end
				local out = deepCopy(profile)
				out.Lock = (not release) and { JobId = JOB_ID, Time = os.time() } or nil
				return out
			end)
		end)
		if ok then break end
		warn(("PlayerData: save failed for %s (try %d): %s"):format(player.Name, attempt, tostring(err)))
		task.wait(2 * attempt)
	end
	saving[player] = nil
	if stolen then
		warn(("PlayerData: %s's profile is locked by another server; this server stops saving it"):format(player.Name))
		loadFailed[player] = true
		return false
	end
	if ok then
		dirty[player] = nil
		lastSave[player] = os.clock()
	end
	return ok
end

-- saves soon, without breaking the DataStore write limit (the autosave loop covers the rest)
local function saveSoon(player)
	dirty[player] = true
	if os.clock() - (lastSave[player] or -math.huge) >= MIN_SAVE_GAP then
		task.spawn(PlayerData.Save, player)
	end
end

local function replicate(player)
	local profile = profiles[player]
	if profile and remotes.ProfileUpdated and player.Parent then
		remotes.ProfileUpdated:FireClient(player, deepCopy(profile))
	end
end

-- Reads the profile and takes the session lock in one UpdateAsync.
-- Returns status ("ok" | "locked" | "error"), data (table or nil), err
local function tryAcquire(player)
	local status, result = "ok", nil
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if typeof(old) == "table" and lockedByOther(old.Lock) then
				status = "locked"
				return nil -- leave it untouched
			end
			status = "ok"
			local data = typeof(old) == "table" and old or defaultProfile()
			data.Lock = { JobId = JOB_ID, Time = os.time() }
			result = data
			return data
		end)
	end)
	if not ok then return "error", nil, err end
	return status, result
end

local function releaseLock(player)
	pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if typeof(old) ~= "table" or typeof(old.Lock) ~= "table" or old.Lock.JobId ~= JOB_ID then
				return nil
			end
			old.Lock = nil
			return old
		end)
	end)
end

local function loadProfile(player)
	local status, data, err
	local errors, lockedTries = 0, 0
	while true do
		status, data, err = tryAcquire(player)
		if status == "ok" then break end
		if player.Parent == nil then return end
		if status == "error" then
			errors += 1
			warn(("PlayerData: load failed for %s (try %d): %s"):format(player.Name, errors, tostring(err)))
			if errors >= 3 then break end
			task.wait(errors)
		else
			lockedTries += 1
			if lockedTries >= LOCK_WAIT_TRIES then break end
			task.wait(LOCK_WAIT_SECONDS) -- the other server is probably still saving: wait for it to let go
		end
	end
	if player.Parent == nil then
		if status == "ok" then releaseLock(player) end
		return
	end

	local profile
	if status ~= "ok" then
		-- play with defaults, but never save over the real data
		warn(("PlayerData: %s plays without saving (%s)"):format(player.Name, status))
		loadFailed[player] = true
		profile = defaultProfile()
	else
		data.Lock = nil
		local migrated, migrateErr = pcall(migrate, data)
		if not migrated then
			warn(("PlayerData: migration failed for %s: %s"):format(player.Name, tostring(migrateErr)))
			loadFailed[player] = true
			releaseLock(player)
			profile = defaultProfile()
		else
			reconcile(data, defaultProfile())
			profile = data
		end
	end
	-- Studio play tests: hand out the test units listed in Config.StudioGrantUnits
	if IS_STUDIO then
		for _, name in ipairs(Config.StudioGrantUnits or {}) do
			if Config.Units[name] and select(2, countUnits(profile.Units, name)) == 0 then
				newUnit(profile.Units, name)
			end
		end
	end
	normalizeLoadout(profile)
	local anyEquipped = false
	for _, uid in ipairs(profile.Loadout) do
		if uid ~= "" then anyEquipped = true end
	end
	if not anyEquipped then fillLoadout(profile) end -- new players / saves from before the loadout existed
	profiles[player] = profile
	replicate(player)
	if not loadFailed[player] then saveSoon(player) end
	for _, callback in ipairs(loadedCallbacks) do
		task.spawn(callback, player, profile)
	end
end

-- ===== public API =====
function PlayerData.Get(player)
	return profiles[player]
end

function PlayerData.WaitForProfile(player, timeout)
	local t0 = os.clock()
	while not profiles[player] and player.Parent and os.clock() - t0 < (timeout or 15) do
		task.wait(0.1)
	end
	return profiles[player]
end

-- callback(player, profile) runs every time a profile finishes loading
function PlayerData.OnProfileLoaded(callback)
	table.insert(loadedCallbacks, callback)
end

-- Returns the unit instance with this id if the player owns it
function PlayerData.GetUnit(player, uid)
	local profile = profiles[player]
	if not profile or typeof(uid) ~= "string" then return nil end
	return profile.Units[uid]
end

-- Is this unit copy in the player's loadout? (only equipped units can be placed)
function PlayerData.IsEquipped(player, uid)
	local profile = profiles[player]
	return profile ~= nil and typeof(uid) == "string" and uid ~= "" and loadoutSlotOf(profile, uid) ~= nil
end

-- Does the player own at least one unit called unitName?
function PlayerData.Owns(player, unitName)
	local profile = profiles[player]
	if not profile then return false end
	local _, n = countUnits(profile.Units, unitName)
	return n > 0
end

local function touch(player)
	dirty[player] = true
	replicate(player)
end

function PlayerData.AddGems(player, amount)
	local profile = profiles[player]
	if not profile or typeof(amount) ~= "number" then return false end
	profile.Gems = math.max(0, profile.Gems + math.floor(amount))
	touch(player)
	return true
end

function PlayerData.AddItem(player, key, amount)
	local profile = profiles[player]
	if not profile or not Config.Materials[key] or typeof(amount) ~= "number" then return false end
	profile.Items[key] = math.max(0, (profile.Items[key] or 0) + math.floor(amount))
	touch(player)
	return true
end
PlayerData.AddMaterial = PlayerData.AddItem -- old name

-- Adds `copies` new instances of a unit. Returns the list of new instances (nil if storage is full).
function PlayerData.AddUnit(player, unitName, copies)
	local profile = profiles[player]
	if not profile or not Config.Units[unitName] then return nil end
	copies = copies or 1
	local total = countUnits(profile.Units, unitName)
	if total + copies > Config.MaxUnitsOwned then return nil end
	local added = {}
	for _ = 1, copies do table.insert(added, newUnit(profile.Units, unitName)) end
	touch(player)
	return added
end

function PlayerData.SetSetting(player, key, value)
	local profile = profiles[player]
	if not profile or SETTING_TYPES[key] == nil or typeof(value) ~= SETTING_TYPES[key] then return false end
	profile.Settings[key] = value
	saveSoon(player)
	return true
end

-- Summon: spend gems, get one random unit from Config.Summon.Pool
function PlayerData.Summon(player)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading" end
	if profile.Gems < Config.Summon.Cost then return false, "Not enough gems" end
	if countUnits(profile.Units, "") >= Config.MaxUnitsOwned then return false, "Unit storage is full" end
	local total = 0
	for name, weight in pairs(Config.Summon.Pool) do
		if Config.Units[name] then total += weight end
	end
	if total <= 0 then return false, "Nothing to summon yet" end
	local roll = math.random() * total
	local picked
	for name, weight in pairs(Config.Summon.Pool) do
		if Config.Units[name] then
			roll -= weight
			if roll <= 0 then picked = name break end
		end
	end
	picked = picked or next(Config.Summon.Pool)
	local _, before = countUnits(profile.Units, picked)
	profile.Gems -= Config.Summon.Cost
	local unit = newUnit(profile.Units, picked)
	if before == 0 and firstEmptySlot(profile) then
		profile.Loadout[firstEmptySlot(profile)] = unit.Id -- first copy of a new unit: equip it right away
	end
	profile.Summon.Total += 1
	profile.Stats.Summons += 1
	touch(player)
	saveSoon(player)
	return true, {
		Unit = picked,
		UnitId = unit.Id,
		Rarity = Config.Units[picked].Rarity,
		Copies = before + 1,
		New = before == 0,
		Gems = profile.Gems,
	}
end

-- Rewards for a finished stage. result = { Won, Round, Kills, BossKilled, Surrender }
-- Returns { Gems = n, Materials = { key = n }, UnitXP = n, LevelUps = { { Name, Level } } }
-- (also saved to the profile). Every equipped unit gets UnitXP.
function PlayerData.GrantStageRewards(player, result)
	local profile = profiles[player]
	local rewards = { Gems = 0, Materials = {} }
	if not profile or result.Surrender then return rewards end
	local R = Config.Rewards
	rewards.Gems = (result.Won and R.VictoryGems or R.DefeatGems) + result.Round * R.GemsPerRound
	local essence = (result.Won and R.EssenceBase or 0) + math.floor(result.Kills / R.KillsPerEssence)
	if essence > 0 then rewards.Materials.WispEssence = essence end
	if result.BossKilled then rewards.Materials.VoidCrystal = R.BossCrystals end

	profile.Gems += rewards.Gems
	for key, n in pairs(rewards.Materials) do
		profile.Items[key] = (profile.Items[key] or 0) + n
	end
	profile.Stats.Kills += result.Kills
	if result.Won then profile.Stats.StagesCleared += 1 end
	if result.BossKilled then profile.Stats.BossesKilled += 1 end

	local L = Config.Leveling
	local xp = (L.XpBase + L.XpPerRound * result.Round) * (result.Won and L.VictoryMult or 1)
	rewards.UnitXP = xp
	rewards.LevelUps = {}
	for _, uid in ipairs(profile.Loadout) do
		local unit = profile.Units[uid]
		if unit and addXp(unit, xp) > 0 then
			table.insert(rewards.LevelUps, { Name = unit.Name, Level = unit.Level })
		end
	end
	touch(player)
	saveSoon(player)
	return rewards
end

-- ===== inventory actions (only outside a stage) =====
local function busy()
	return workspace:GetAttribute("State") == "Playing"
end

-- Puts unit `uid` into loadout `slot` (moving it if it is already in another slot).
-- uid = "" empties the slot. slot = nil uses the first empty slot.
function PlayerData.Equip(player, uid, slot)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading" end
	if busy() then return false, "You can't change your loadout during a stage" end
	if typeof(uid) ~= "string" then return false, "Bad request" end
	if slot ~= nil and (typeof(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > Config.LoadoutSlots) then
		return false, "Bad slot"
	end
	if uid == "" then
		if not slot then return false, "Bad slot" end
		profile.Loadout[slot] = ""
	else
		if not profile.Units[uid] then return false, "You do not own this unit" end
		local current = loadoutSlotOf(profile, uid)
		slot = slot or current or firstEmptySlot(profile)
		if not slot then return false, "Your loadout is full: pick a slot" end
		if current then profile.Loadout[current] = "" end
		profile.Loadout[slot] = uid
	end
	touch(player)
	saveSoon(player)
	return true
end

function PlayerData.SetLocked(player, uid, locked)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading" end
	local unit = typeof(uid) == "string" and profile.Units[uid]
	if not unit or typeof(locked) ~= "boolean" then return false, "Bad request" end
	unit.Locked = locked
	touch(player)
	saveSoon(player)
	return true
end

-- Sells unit copies for gems (Config.Rarities[r].SellValue). Locked and equipped units are skipped.
-- Returns true, gems earned, units sold.
function PlayerData.SellUnits(player, uids)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading" end
	if busy() then return false, "You can't sell units during a stage" end
	if typeof(uids) ~= "table" or #uids == 0 or #uids > Config.MaxUnitsOwned then return false, "Bad request" end
	local owned = countUnits(profile.Units, "")
	local gems, sold = 0, 0
	for _, uid in ipairs(uids) do
		local unit = typeof(uid) == "string" and profile.Units[uid]
		if unit and not unit.Locked and not loadoutSlotOf(profile, uid) and owned - sold > 1 then
			profile.Units[uid] = nil
			gems += Config.RarityOf(unit.Name).SellValue
			sold += 1
		end
	end
	if sold == 0 then return false, "Nothing to sell (locked, equipped, or your last unit)" end
	profile.Gems += gems
	touch(player)
	saveSoon(player)
	return true, gems, sold
end

-- Feeds up to `amount` Wisp Essence to a unit (never more than it needs to reach its level cap).
-- Returns true, essence used, levels gained.
function PlayerData.FeedUnit(player, uid, amount)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading" end
	if busy() then return false, "You can't level units during a stage" end
	local unit = typeof(uid) == "string" and profile.Units[uid]
	if not unit or typeof(amount) ~= "number" or amount < 1 then return false, "Bad request" end
	local have = profile.Items.WispEssence or 0
	if have <= 0 then return false, "No Wisp Essence" end
	local need = math.ceil(xpToCap(unit) / Config.Leveling.XpPerEssence)
	if need <= 0 then return false, "Already max level" end
	local use = math.min(math.floor(amount), have, need)
	profile.Items.WispEssence = have - use
	local gained = addXp(unit, use * Config.Leveling.XpPerEssence)
	touch(player)
	saveSoon(player)
	return true, use, gained
end

-- ===== setup =====
function PlayerData.init(remotesFolder)
	local function newRemote(className, name)
		local r = Instance.new(className)
		r.Name = name
		r.Parent = remotesFolder
		remotes[name] = r
		return r
	end
	newRemote("RemoteEvent", "ProfileUpdated")
	newRemote("RemoteEvent", "StageRewards")
	local getProfile = newRemote("RemoteFunction", "GetProfile")
	local setSetting = newRemote("RemoteEvent", "SetSetting")
	local summon = newRemote("RemoteFunction", "Summon")
	local equipUnit = newRemote("RemoteFunction", "EquipUnit")
	local lockUnit = newRemote("RemoteFunction", "LockUnit")
	local sellUnits = newRemote("RemoteFunction", "SellUnits")
	local feedUnit = newRemote("RemoteFunction", "FeedUnit")

	equipUnit.OnServerInvoke = function(player, uid, slot)
		if not RateLimit.allow(player, "EquipUnit", 5) then return false, "Please wait" end
		return PlayerData.Equip(player, uid, slot)
	end
	lockUnit.OnServerInvoke = function(player, uid, locked)
		if not RateLimit.allow(player, "LockUnit", 5) then return false, "Please wait" end
		return PlayerData.SetLocked(player, uid, locked)
	end
	sellUnits.OnServerInvoke = function(player, uids)
		if not RateLimit.allow(player, "SellUnits", 3) then return false, "Please wait" end
		return PlayerData.SellUnits(player, uids)
	end
	feedUnit.OnServerInvoke = function(player, uid, amount)
		if not RateLimit.allow(player, "FeedUnit", 5) then return false, "Please wait" end
		return PlayerData.FeedUnit(player, uid, amount)
	end

	getProfile.OnServerInvoke = function(player)
		if not RateLimit.allow(player, "GetProfile", 2) then return nil end
		local profile = PlayerData.WaitForProfile(player, 60)
		return profile and deepCopy(profile) or nil
	end
	setSetting.OnServerEvent:Connect(function(player, key, value)
		if not RateLimit.allow(player, "SetSetting", 5) then return end
		if typeof(key) == "string" then PlayerData.SetSetting(player, key, value) end
	end)
	local summoning = {}
	summon.OnServerInvoke = function(player)
		if summoning[player] or not RateLimit.allow(player, "Summon", 3) then return false, "Please wait" end
		summoning[player] = true
		local ok, result = PlayerData.Summon(player)
		task.delay(0.4, function() summoning[player] = nil end)
		return ok, result
	end

	Players.PlayerAdded:Connect(function(player) task.spawn(loadProfile, player) end)
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(loadProfile, player) end

	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then PlayerData.Save(player, true) end
		profiles[player], loadFailed[player], dirty[player], lastSave[player], saving[player] = nil, nil, nil, nil, nil
	end)

	-- autosave: every loaded profile is written, even when nothing changed, so its lock stays fresh
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in pairs(profiles) do
				if player.Parent and not loadFailed[player] then task.spawn(PlayerData.Save, player) end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if profiles[player] then
				pending += 1
				task.spawn(function()
					PlayerData.Save(player, true)
					pending -= 1
				end)
			end
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
	end)
end

return PlayerData
