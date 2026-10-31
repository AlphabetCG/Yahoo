-- Lobby: rooms that players create before a stage (PLAY > mode > map > stage > Create Lobby / Matchmaking).
-- A room has a host, a stage, up to Config.MaxPartySize members and a privacy setting:
--   Public  = anyone can join, and matchmaking fills it
--   Friends = only the host's friends can see and join it
--   Invite  = only players the host invited can join
-- The host starts the room; GameServer decides how (a match in this server, or a teleport).
--
-- Every player gets their own view of the lobby through the LobbyState remote:
--   { MyRoom = room or nil, Rooms = { rooms this player could join } }
-- Invites arrive through LobbyInvited.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local RateLimit = require(script.Parent:WaitForChild("RateLimit"))

local Lobby = {}

local rooms = {}      -- [id] = { Id, Host, StageId, Privacy, Members = { player }, Invited = { [userId] = true }, Started }
local roomOf = {}     -- [player] = room
local nextId = 0
local remotes = {}
local hooks = {}      -- StartRoom(room) -> ok, message ; CanCreate(player, stageId) -> ok, message
local friendCache = {} -- ["a:b"] = bool

local function isFriend(player, otherUserId)
	if player.UserId == otherUserId then return true end
	local key = player.UserId .. ":" .. otherUserId
	if friendCache[key] == nil then
		local ok, result = pcall(function() return player:IsFriendsWith(otherUserId) end)
		friendCache[key] = ok and result or false
	end
	return friendCache[key]
end

-- Can `player` see / join `room`?
local function canJoin(player, room)
	if room.Started or #room.Members >= Config.MaxPartySize or roomOf[player] == room then return false end
	if room.Privacy == "Public" then return true end
	if room.Invited[player.UserId] then return true end
	return room.Privacy == "Friends" and isFriend(player, room.Host.UserId)
end

-- what a client gets to know about a room
local function describe(room)
	local members = {}
	for _, p in ipairs(room.Members) do
		table.insert(members, { UserId = p.UserId, Name = p.DisplayName, Color = p:GetAttribute("PlayerColor") })
	end
	return {
		Id = room.Id,
		HostId = room.Host.UserId,
		HostName = room.Host.DisplayName,
		StageId = room.StageId,
		Privacy = room.Privacy,
		Members = members,
		Started = room.Started,
	}
end

-- sends every player their own view of the lobby
local function broadcast()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			local visible = {}
			for _, room in pairs(rooms) do
				if canJoin(player, room) then table.insert(visible, describe(room)) end
			end
			table.sort(visible, function(a, b) return a.Id < b.Id end)
			local mine = roomOf[player]
			if player.Parent then
				remotes.LobbyState:FireClient(player, { MyRoom = mine and describe(mine) or nil, Rooms = visible })
			end
		end)
	end
end
Lobby.Broadcast = broadcast

local function leave(player)
	local room = roomOf[player]
	if not room then return end
	roomOf[player] = nil
	local idx = table.find(room.Members, player)
	if idx then table.remove(room.Members, idx) end
	if #room.Members == 0 then
		rooms[room.Id] = nil
	elseif room.Host == player then
		room.Host = room.Members[1] -- the next member becomes the host
	end
end

local function join(player, room)
	leave(player)
	table.insert(room.Members, player)
	roomOf[player] = room
end

local function create(player, stageId, privacy)
	if not Config.Stages[stageId] then return nil, "Unknown stage" end
	if not table.find(Config.LobbyPrivacy, privacy) then privacy = "Public" end
	if hooks.CanCreate then
		local ok, msg = hooks.CanCreate(player, stageId)
		if not ok then return nil, msg end
	end
	nextId += 1
	local room = { Id = nextId, Host = player, StageId = stageId, Privacy = privacy, Members = {}, Invited = {}, Started = false }
	rooms[room.Id] = room
	join(player, room)
	return room
end

-- ===== used by GameServer =====
function Lobby.RoomOf(player)
	return roomOf[player]
end

-- the room's match is over (single-server mode): it can be started again
function Lobby.SetStarted(room, started)
	if rooms[room.Id] then
		room.Started = started
		broadcast()
	end
end

-- the room's players have been teleported away: the room is gone
function Lobby.Close(room)
	for _, p in ipairs(room.Members) do roomOf[p] = nil end
	rooms[room.Id] = nil
	broadcast()
end

-- hooks = { StartRoom = function(room) -> ok, msg, CanCreate = function(player, stageId) -> ok, msg }
function Lobby.init(remotesFolder, hookTable)
	hooks = hookTable or {}
	local function newRemote(className, name)
		local r = Instance.new(className)
		r.Name = name
		r.Parent = remotesFolder
		remotes[name] = r
		return r
	end
	newRemote("RemoteEvent", "LobbyState")
	newRemote("RemoteEvent", "LobbyInvited")
	local createR = newRemote("RemoteFunction", "LobbyCreate")
	local joinR = newRemote("RemoteFunction", "LobbyJoin")
	local leaveR = newRemote("RemoteEvent", "LobbyLeave")
	local inviteR = newRemote("RemoteFunction", "LobbyInvite")
	local privacyR = newRemote("RemoteEvent", "LobbySetPrivacy")
	local startR = newRemote("RemoteFunction", "LobbyStart")
	local matchmakeR = newRemote("RemoteFunction", "LobbyMatchmake")
	local refreshR = newRemote("RemoteEvent", "LobbyRefresh")

	createR.OnServerInvoke = function(player, stageId, privacy)
		if not RateLimit.allow(player, "LobbyCreate", 2) then return false, "Please wait" end
		if typeof(stageId) ~= "string" or typeof(privacy) ~= "string" then return false, "Bad request" end
		local room, msg = create(player, stageId, privacy)
		broadcast()
		return room ~= nil, msg
	end

	joinR.OnServerInvoke = function(player, roomId)
		if not RateLimit.allow(player, "LobbyJoin", 3) then return false, "Please wait" end
		local room = typeof(roomId) == "number" and rooms[roomId]
		if not room then return false, "That lobby is gone" end
		if not canJoin(player, room) then return false, "You can't join that lobby" end
		join(player, room)
		broadcast()
		return true
	end

	leaveR.OnServerEvent:Connect(function(player)
		if not RateLimit.allow(player, "LobbyLeave", 3) then return end
		local room = roomOf[player]
		if room and room.Started then return end
		leave(player)
		broadcast()
	end)

	inviteR.OnServerInvoke = function(player, userId)
		if not RateLimit.allow(player, "LobbyInvite", 5) then return false, "Please wait" end
		local room = roomOf[player]
		if not room or room.Host ~= player then return false, "Only the lobby host can invite" end
		local target = typeof(userId) == "number" and Players:GetPlayerByUserId(userId)
		if not target or target == player then return false, "That player isn't here" end
		if roomOf[target] == room then return false, "Already in your lobby" end
		if #room.Members >= Config.MaxPartySize then return false, "Your lobby is full" end
		room.Invited[target.UserId] = true
		remotes.LobbyInvited:FireClient(target, { RoomId = room.Id, HostName = player.DisplayName, StageId = room.StageId })
		broadcast()
		return true
	end

	privacyR.OnServerEvent:Connect(function(player, privacy)
		if not RateLimit.allow(player, "LobbySetPrivacy", 3) then return end
		local room = roomOf[player]
		if room and room.Host == player and table.find(Config.LobbyPrivacy, privacy) then
			room.Privacy = privacy
			broadcast()
		end
	end)

	startR.OnServerInvoke = function(player)
		if not RateLimit.allow(player, "LobbyStart", 2) then return false, "Please wait" end
		local room = roomOf[player]
		if not room or room.Host ~= player then return false, "Only the lobby host can start" end
		if room.Started then return false, "Already starting" end
		if not hooks.StartRoom then return false, "Not available" end
		local ok, msg = hooks.StartRoom(room)
		broadcast()
		return ok, msg
	end

	-- Matchmaking: join a public lobby for this stage that has room, or open a new public one
	matchmakeR.OnServerInvoke = function(player, stageId)
		if not RateLimit.allow(player, "LobbyMatchmake", 2) then return false, "Please wait" end
		if typeof(stageId) ~= "string" or not Config.Stages[stageId] then return false, "Unknown stage" end
		local best
		for _, room in pairs(rooms) do
			if room.StageId == stageId and room.Privacy == "Public" and canJoin(player, room)
				and (not best or #room.Members > #best.Members) then
				best = room
			end
		end
		local found = best ~= nil
		if best then
			join(player, best)
		else
			local room, msg = create(player, stageId, "Public")
			if not room then return false, msg end
		end
		broadcast()
		return true, found and "Joined a lobby" or "No open lobby: created a public one"
	end

	refreshR.OnServerEvent:Connect(function(player)
		if RateLimit.allow(player, "LobbyRefresh", 1) then broadcast() end
	end)

	Players.PlayerAdded:Connect(function() task.defer(broadcast) end)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		for key in pairs(friendCache) do
			if key:find("^" .. player.UserId .. ":") then friendCache[key] = nil end
		end
		task.defer(broadcast)
	end)
end

return Lobby
