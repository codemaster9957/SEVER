local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local events = ReplicatedStorage:WaitForChild("RankedEvents")
local queueRequest = events:WaitForChild("QueueRequest")
local queueState = events:WaitForChild("QueueState")
local matchState = events:WaitForChild("MatchState")
local leaderboardState = events:WaitForChild("LeaderboardState")
local leaderboardRequest = events:WaitForChild("LeaderboardRequest")
local rankQuery = events:WaitForChild("RankQuery")

local RankedDataService = require(script.Parent:WaitForChild("RankedDataService"))
local RankedMatchmakingService = require(script.Parent:WaitForChild("RankedMatchmakingService"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

local active = {}
local arrivals = {}
local startingMatches = {}
local leaderboardCooldown = {}
local rankCache = {}

local LEADERBOARD_COOLDOWN = 2
local ARRIVAL_TIMEOUT = 20
local RANK_CACHE_TIME = 2

local function valid(player)
	return player and player.Parent == Players
end

local function send(player, remote, data)
	if valid(player) then remote:FireClient(player, data) end
end

local function publishLeaderboard(player)
	local now = os.clock()
	if now - (leaderboardCooldown[player] or -math.huge) < LEADERBOARD_COOLDOWN then return end
	leaderboardCooldown[player] = now
	send(player, leaderboardState, RankedDataService.GetLeaderboardFor(player, 5))
end

rankQuery.OnServerInvoke = function(player)
	local now = os.clock()
	local cached = rankCache[player]
	if cached and now - cached.time < RANK_CACHE_TIME then
		return cached.value
	end
	local rank, trophies = RankedDataService.GetRank(player)
	local value = {Rank = rank, Trophies = trophies}
	rankCache[player] = {time = now, value = value}
	return value
end

leaderboardRequest.OnServerEvent:Connect(publishLeaderboard)

queueRequest.OnServerEvent:Connect(function(player, action)
	if action == "Cancel" then
		RankedMatchmakingService.Cancel(player)
		active[player] = nil
		send(player, queueState, {State = "Cancelled"})
		return
	end

	if action ~= "Join"
		or active[player]
		or MatchManager.IsPlayerInMatch(player) then
		return
	end

	active[player] = true
	local trophies = RankedDataService.GetTrophies(player)
	if RankedMatchmakingService.Queue(player, trophies) then
		send(player, queueState, {State = "Searching"})
	else
		active[player] = nil
		send(player, queueState, {State = "Error", Message = "Unable to join ranked queue"})
	end
end)

-- This signal fires only on whichever source server actually owns a matched
-- player. A cross-server pair therefore receives the same match notification on
-- both source servers before each half teleports to the shared reserved server.
RankedMatchmakingService.GetMatchDispatchSignal():Connect(function(player, data)
	if not valid(player) then return end
	active[player] = nil

	local opponentUserId = player.UserId == data.A and data.B or data.A
	local opponentName = player.UserId == data.A and data.BName or data.AName

	send(player, queueState, {
		State = "OpponentFound",
		MatchId = data.MatchId,
		OpponentUserId = opponentUserId,
		OpponentName = opponentName or "Opponent",
	})
	send(player, queueState, {State = "JoiningMatch", MatchId = data.MatchId})
	send(player, matchState, {State = "JoiningMatch", MatchId = data.MatchId})
end)

local function returnPlayersToPublic(players, reason)
	local list = {}
	for _, player in ipairs(players) do
		if valid(player) then
			send(player, matchState, {State = "Failed", Message = reason})
			table.insert(list, player)
		end
	end
	if #list == 0 then return end

	task.delay(1, function()
		local stillHere = {}
		for _, player in ipairs(list) do
			if valid(player) then table.insert(stillHere, player) end
		end
		if #stillHere == 0 then return end

		local ok, err = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, stillHere)
		end)
		if not ok then
			warn("[RankedServer] Failed returning players to public server: " .. tostring(err))
		end
	end)
end

local function tryStartArrivalMatch(matchId)
	local bucket = arrivals[matchId]
	if not bucket or startingMatches[matchId] then return end

	local expected = bucket.data.Players
	if type(expected) ~= "table" or #expected ~= 2 then return end
	local p1 = bucket.players[expected[1]]
	local p2 = bucket.players[expected[2]]
	if not valid(p1) or not valid(p2) then return end

	startingMatches[matchId] = true
	arrivals[matchId] = nil

	MatchManager.SetMatchMetadata(p1, p2, matchId, true)
	for _, player in ipairs({p1, p2}) do
		active[player] = nil
		if player.Character then player.Character:SetAttribute("MatchMode", "Ranked") end
		send(player, matchState, {State = "BattleStarted", MatchId = matchId})
	end

	local ok, started = pcall(function()
		return MatchManager.StartMatch(p1, p2, nil)
	end)

	if not ok or started ~= true then
		warn("[RankedServer] Destination ranked match failed: " .. tostring(started))
		startingMatches[matchId] = nil
		returnPlayersToPublic({p1, p2}, "Ranked arena could not start")
	end
end

local function handlePossibleRankedArrival(player)
	if not valid(player) then return end

	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then return end

	local data = joinData.TeleportData
	if not RankedMatchmakingService.ValidateTeleportData(data, player) then return end

	-- GetJoinData provides Roblox-validated source metadata on the server. Reject a
	-- teleport claiming to be ranked if it came from another universe.
	if joinData.SourceGameId and joinData.SourceGameId ~= 0 and joinData.SourceGameId ~= game.GameId then
		warn("[RankedServer] Rejected ranked teleport from unexpected universe")
		return
	end

	local matchId = data.MatchId
	local bucket = arrivals[matchId]
	if not bucket then
		bucket = {data = data, players = {}, createdAt = os.clock()}
		arrivals[matchId] = bucket

		task.delay(ARRIVAL_TIMEOUT, function()
			local current = arrivals[matchId]
			if current ~= bucket or startingMatches[matchId] then return end
			arrivals[matchId] = nil
			local stranded = {}
			for _, arrived in pairs(bucket.players) do
				if valid(arrived) then table.insert(stranded, arrived) end
			end
			returnPlayersToPublic(stranded, "Opponent failed to arrive")
		end)
	end

	bucket.players[player.UserId] = player
	active[player] = nil
	send(player, queueState, {State = "JoiningMatch", MatchId = matchId})
	tryStartArrivalMatch(matchId)
end

Players.PlayerAdded:Connect(function(player)
	task.defer(handlePossibleRankedArrival, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.defer(handlePossibleRankedArrival, player)
end

-- Any public server can coordinate a MemoryStore pair. Once claimed, dispatching
-- through MessagingService reaches the actual source servers for both users.
task.spawn(function()
	while true do
		task.wait(2)
		RankedMatchmakingService.ProcessLocalQueue(function(a, b, matchId)
			local dispatched = RankedMatchmakingService.DispatchMatch(a, b, matchId)
			if not dispatched then
				for _, userId in ipairs({a.UserId, b.UserId}) do
					local player = Players:GetPlayerByUserId(userId)
					if valid(player) then
						active[player] = true
						send(player, queueState, {State = "Searching"})
					end
				end
			end
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	active[player] = nil
	leaderboardCooldown[player] = nil
	rankCache[player] = nil
	RankedMatchmakingService.Cancel(player)

	for matchId, bucket in pairs(arrivals) do
		if bucket.players[player.UserId] then
			bucket.players[player.UserId] = nil
		end
	end
end)

print("[RankedServer] Initialized")
