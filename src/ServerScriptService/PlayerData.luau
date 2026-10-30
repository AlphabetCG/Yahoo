-- PlayerData: loads and saves every player's profile (settings, gems, units, materials, stats)
-- in a DataStore, and hands out rewards / summons. Used by GameServer.
--
-- Profile layout (saved as one table under "Player_<UserId>"):
--   Settings  = { AlwaysHealthBars = bool, AutoSkip = bool }
--   Gems      = number
--   Units     = { [unitName] = copies owned }
--   Materials = { [materialKey] = amount }      (keys come from Config.Materials)
--   Stats     = { StagesCleared, BossesKilled, Kills }
-- To add a new setting: add it to defaultProfile() and to SETTING_TYPES below.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))

local STORE_NAME = "PlayerData_v1"
local AUTOSAVE_SECONDS = 60
local MIN_SAVE_GAP = 7 -- DataStore allows one write per key about every 6 seconds

local SETTING_TYPES = {
	AlwaysHealthBars = "boolean",
	AutoSkip = "boolean",
}

local store = DataStoreService:GetDataStore(STORE_NAME)

local PlayerData = {}
local profiles = {}   -- [player] = profile
local loadFailed = {} -- [player] = true when the saved data could not be read (we never overwrite it then)
local dirty = {}      -- [player] = true when there is something new to save
local lastSave = {}   -- [player] = os.clock() of the last save
local saving = {}     -- [player] = true while a save is running
local remotes = {}    -- filled by PlayerData.init

local function deepCopy(t)
	if typeof(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepCopy(v) end
	return c
end

local function defaultProfile()
	return {
		Version = 1,
		Settings = { AlwaysHealthBars = false, AutoSkip = Config.AutoSkipDefault },
		Gems = Config.StarterGems,
		Units = deepCopy(Config.StarterUnits),
		Materials = {},
		Stats = { StagesCleared = 0, BossesKilled = 0, Kills = 0 },
	}
end

-- fills in anything missing from older saves (Units / Materials are open-ended, so left alone)
local function reconcile(data, default)
	for k, v in pairs(default) do
		if data[k] == nil then
			data[k] = deepCopy(v)
		elseif typeof(v) == "table" and typeof(data[k]) == "table" and k ~= "Units" and k ~= "Materials" then
			reconcile(data[k], v)
		end
	end
end

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- ===== saving / loading =====
function PlayerData.Save(player)
	local profile = profiles[player]
	if not profile or loadFailed[player] or saving[player] then return false end
	saving[player] = true
	local ok, err
	for attempt = 1, 3 do
		ok, err = pcall(function()
			store:UpdateAsync(keyFor(player), function() return profile end)
		end)
		if ok then break end
		warn(("PlayerData: save failed for %s (try %d): %s"):format(player.Name, attempt, tostring(err)))
		task.wait(2 * attempt)
	end
	saving[player] = nil
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

local function applySettings(player)
	local profile = profiles[player]
	if profile then
		-- single-player style game: the saved Auto Skip choice drives the shared round logic
		workspace:SetAttribute("AutoSkip", profile.Settings.AutoSkip)
	end
end

local function loadProfile(player)
	local data, ok
	for attempt = 1, 3 do
		ok, data = pcall(function() return store:GetAsync(keyFor(player)) end)
		if ok then break end
		warn(("PlayerData: load failed for %s (try %d): %s"):format(player.Name, attempt, tostring(data)))
		task.wait(attempt)
	end
	if player.Parent == nil then return end
	local profile
	if not ok then
		-- play with defaults, but never save over the real data
		loadFailed[player] = true
		profile = defaultProfile()
	elseif typeof(data) == "table" then
		reconcile(data, defaultProfile())
		profile = data
	else
		profile = defaultProfile()
		dirty[player] = true -- brand new player: write the starter profile
	end
	profiles[player] = profile
	applySettings(player)
	replicate(player)
	if dirty[player] then saveSoon(player) end
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

function PlayerData.Owns(player, unitName)
	local profile = profiles[player]
	return profile ~= nil and (profile.Units[unitName] or 0) > 0
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

function PlayerData.AddMaterial(player, key, amount)
	local profile = profiles[player]
	if not profile or not Config.Materials[key] or typeof(amount) ~= "number" then return false end
	profile.Materials[key] = math.max(0, (profile.Materials[key] or 0) + math.floor(amount))
	touch(player)
	return true
end

function PlayerData.AddUnit(player, unitName, copies)
	local profile = profiles[player]
	if not profile or not Config.Units[unitName] then return false end
	profile.Units[unitName] = (profile.Units[unitName] or 0) + (copies or 1)
	touch(player)
	return true
end

function PlayerData.SetSetting(player, key, value)
	local profile = profiles[player]
	if not profile or SETTING_TYPES[key] == nil or typeof(value) ~= SETTING_TYPES[key] then return false end
	profile.Settings[key] = value
	if key == "AutoSkip" then applySettings(player) end
	saveSoon(player)
	return true
end

-- Summon: spend gems, get one random unit from Config.Summon.Pool
function PlayerData.Summon(player)
	local profile = profiles[player]
	if not profile then return false, "Your data is still loading" end
	if profile.Gems < Config.Summon.Cost then return false, "Not enough gems" end
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
	profile.Gems -= Config.Summon.Cost
	local isNew = (profile.Units[picked] or 0) == 0
	profile.Units[picked] = (profile.Units[picked] or 0) + 1
	touch(player)
	saveSoon(player)
	return true, { Unit = picked, Copies = profile.Units[picked], New = isNew, Gems = profile.Gems }
end

-- Rewards for a finished stage. result = { Won, Round, Kills, BossKilled, Surrender }
-- Returns { Gems = n, Materials = { key = n } } (also saved to the profile).
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
		profile.Materials[key] = (profile.Materials[key] or 0) + n
	end
	profile.Stats.Kills += result.Kills
	if result.Won then profile.Stats.StagesCleared += 1 end
	if result.BossKilled then profile.Stats.BossesKilled += 1 end
	touch(player)
	saveSoon(player)
	return rewards
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

	getProfile.OnServerInvoke = function(player)
		local profile = PlayerData.WaitForProfile(player, 20)
		return profile and deepCopy(profile) or nil
	end
	setSetting.OnServerEvent:Connect(function(player, key, value)
		if typeof(key) == "string" then PlayerData.SetSetting(player, key, value) end
	end)
	local summoning = {}
	summon.OnServerInvoke = function(player)
		if summoning[player] then return false, "Please wait" end
		summoning[player] = true
		local ok, result = PlayerData.Summon(player)
		task.delay(0.4, function() summoning[player] = nil end)
		return ok, result
	end

	Players.PlayerAdded:Connect(function(player) task.spawn(loadProfile, player) end)
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(loadProfile, player) end

	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then PlayerData.Save(player) end
		profiles[player], loadFailed[player], dirty[player], lastSave[player], saving[player] = nil, nil, nil, nil, nil
	end)

	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player in pairs(dirty) do
				if player.Parent then task.spawn(PlayerData.Save, player) end
			end
		end
	end)

	game:BindToClose(function()
		local pending = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if profiles[player] then
				pending += 1
				task.spawn(function()
					PlayerData.Save(player)
					pending -= 1
				end)
			end
		end
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < 25 do task.wait(0.1) end
	end)
end

return PlayerData
