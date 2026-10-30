-- RateLimit: simple per-player, per-remote request limits.
-- RateLimit.allow(player, "PlaceTower", 10) is true at most 10 times per second for that player.

local Players = game:GetService("Players")

local RateLimit = {}
local windows = {} -- [player] = { [key] = { Start = os.clock(), Count = n } }

function RateLimit.allow(player, key, perSecond)
	local byKey = windows[player]
	if not byKey then
		byKey = {}
		windows[player] = byKey
	end
	local now = os.clock()
	local w = byKey[key]
	if not w or now - w.Start >= 1 then
		byKey[key] = { Start = now, Count = 1 }
		return true
	end
	if w.Count >= perSecond then return false end
	w.Count += 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	windows[player] = nil
end)

return RateLimit
