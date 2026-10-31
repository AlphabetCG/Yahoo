-- Banners: rolls summons on the server (Config.Banners). Used by PlayerData.Summon.
--   1. every pity counter of the banner goes up by one
--   2. if a counter reached its Pity number, that rarity is guaranteed (the rarest one wins)
--      otherwise the rarity is rolled with Config.BannerRates
--   3. counters of that rarity and every lower one reset to 0
--   4. the unit: the featured unit RateUp of the time, otherwise another unit of that rarity
-- Banners.simulate(bannerId, pulls) checks the real numbers against the config (Studio).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local Banners = {}

-- counters = { [rarity] = pulls since that rarity (or better) dropped } (changed in place)
-- Returns unitName, rarity, pityTriggered
function Banners.roll(bannerId, counters, rng)
	rng = rng or Random.new()
	local banner = Config.Banners[bannerId]
	local rates = Config.BannerRates(bannerId)
	if not banner or #rates == 0 then return nil end

	-- 1 + 2: pity
	local forced = nil
	for rarity, limit in pairs(banner.Pity or {}) do
		counters[rarity] = (counters[rarity] or 0) + 1
		if counters[rarity] >= limit and #Config.BannerPool(bannerId, rarity) > 0
			and (not forced or Config.Rarities[rarity].Order > Config.Rarities[forced].Order) then
			forced = rarity
		end
	end

	-- 2: the rarity
	local row = nil
	if forced then
		for _, r in ipairs(rates) do
			if r.Rarity == forced then row = r end
		end
	end
	if not row then
		local roll = rng:NextNumber()
		for _, r in ipairs(rates) do
			roll -= r.Chance
			if roll <= 0 then
				row = r
				break
			end
		end
		row = row or rates[#rates]
	end

	-- 3: reset the counters this pull satisfied
	local order = Config.Rarities[row.Rarity].Order
	for rarity in pairs(banner.Pity or {}) do
		if Config.Rarities[rarity].Order <= order then counters[rarity] = 0 end
	end

	-- 4: the unit
	local pool = row.Pool
	local featured = banner.Featured and banner.Featured[row.Rarity]
	local name
	if featured and table.find(pool, featured) then
		if #pool == 1 or rng:NextNumber() < (banner.RateUp or 0.5) then
			name = featured
		else
			local others = {}
			for _, n in ipairs(pool) do
				if n ~= featured then table.insert(others, n) end
			end
			name = others[rng:NextInteger(1, #others)]
		end
	else
		name = pool[rng:NextInteger(1, #pool)]
	end
	return name, row.Rarity, forced ~= nil
end

-- Pulls `pulls` times with a fresh pity state and prints how often each rarity / unit came up
-- next to the configured chance, and the longest run without each pity rarity.
function Banners.simulate(bannerId, pulls)
	pulls = pulls or 10000
	local rng = Random.new(12345)
	local counters = {}
	local byRarity, byUnit, longest, since = {}, {}, {}, {}
	for _ = 1, pulls do
		local name, rarity = Banners.roll(bannerId, counters, rng)
		byRarity[rarity] = (byRarity[rarity] or 0) + 1
		byUnit[name] = (byUnit[name] or 0) + 1
		for r in pairs(Config.Banners[bannerId].Pity or {}) do
			if Config.Rarities[rarity].Order >= Config.Rarities[r].Order then
				since[r] = 0
			else
				since[r] = (since[r] or 0) + 1
				longest[r] = math.max(longest[r] or 0, since[r])
			end
		end
	end
	print(("[Banner sim] %s, %d pulls"):format(bannerId, pulls))
	for _, row in ipairs(Config.BannerRates(bannerId)) do
		print(("  %-10s got %6.2f%%   config %6.2f%%"):format(row.Rarity, (byRarity[row.Rarity] or 0) / pulls * 100, row.Chance * 100))
		for _, u in ipairs(row.Units) do
			print(("      %-10s got %6.2f%%   config %6.2f%%"):format(u.Name, (byUnit[u.Name] or 0) / pulls * 100, u.Chance * 100))
		end
	end
	for r, limit in pairs(Config.Banners[bannerId].Pity or {}) do
		print(("  pity %-10s every %d pulls at most; longest run without it: %d"):format(r, limit, longest[r] or 0))
	end
	-- note: pity makes rare rarities slightly MORE common than their base chance
	return byRarity, byUnit, longest
end

return Banners
