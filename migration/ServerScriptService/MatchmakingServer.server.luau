--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchmakingEvents = ReplicatedStorage:WaitForChild("MatchmakingEvents")
local JoinQueue = MatchmakingEvents:WaitForChild("JoinQueue")
local LeaveQueue = MatchmakingEvents:WaitForChild("LeaveQueue")
local QueueStatusUpdate = MatchmakingEvents:WaitForChild("QueueStatusUpdate")
local MatchFound = MatchmakingEvents:WaitForChild("MatchFound")
local AcceptMatch = MatchmakingEvents:WaitForChild("AcceptMatch")
local DeclineMatch = MatchmakingEvents:WaitForChild("DeclineMatch")
local RequestRematch = MatchmakingEvents:WaitForChild("RequestRematch")
local RematchResponse = MatchmakingEvents:WaitForChild("RematchResponse")
local BotMatchRequest = MatchmakingEvents:WaitForChild("BotMatchRequest")

local MatchmakingConfig = require(ReplicatedStorage:WaitForChild("MatchmakingConfig"))
local DataService = require(ServerScriptService:WaitForChild("DataService"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
local WinstreakData = require(ServerScriptService:WaitForChild("WinstreakData"))

local queue = {}
local pendingMatches = {}
local rematchRequests = {}
local recentMatches = {}
local startingPlayers = {}

local function valid(player)
	return player and player.Parent == Players
end

local function getMMR(player)
	local profile = DataService.GetProfile(player)
	return profile and profile.MMR or MatchmakingConfig.BASE_MMR
end

local function fire(player, status)
	if valid(player) then QueueStatusUpdate:FireClient(player, status) end
end

local function remove(player)
	queue[player] = nil
end

local function countQueue(mode)
	local count = 0
	for player, entry in pairs(queue) do
		if valid(player) and (not mode or entry.mode == mode) then
			count += 1
		end
	end
	return count
end

local function updateMMR(player, win, ranked)
	local profile = DataService.GetProfile(player)
	if not profile then return end

	local delta = win
		and (ranked and MatchmakingConfig.RankedWinMMR or MatchmakingConfig.CasualWinMMR)
		or -(ranked and MatchmakingConfig.RankedLossMMR or MatchmakingConfig.CasualLossMMR)

	profile.MMR = math.max(0, (profile.MMR or MatchmakingConfig.BASE_MMR) + delta)
	if win then
		profile.Wins = (profile.Wins or 0) + 1
		if ranked then
			profile.RankedWins = (profile.RankedWins or 0) + 1
		else
			profile.CasualWins = (profile.CasualWins or 0) + 1
		end
	else
		profile.Losses = (profile.Losses or 0) + 1
		if ranked then
			profile.RankedLosses = (profile.RankedLosses or 0) + 1
		else
			profile.CasualLosses = (profile.CasualLosses or 0) + 1
		end
	end
end

local function findOpponent(player, entry)
	local best, bestDiff = nil, math.huge
	local range = math.min(
		MatchmakingConfig.INITIAL_MMR_RANGE
			+ (os.clock() - entry.joinTime) * MatchmakingConfig.MMR_EXPANSION_RATE,
		MatchmakingConfig.MAX_MMR_RANGE
	)

	for other, otherEntry in pairs(queue) do
		if other ~= player
			and valid(other)
			and otherEntry.mode == entry.mode
			and not MatchManager.IsPlayerInMatch(other)
			and not startingPlayers[other] then
			local currentDiff = math.abs(entry.mmr - otherEntry.mmr)
			if currentDiff <= range and currentDiff < bestDiff then
				best, bestDiff = other, currentDiff
			end
		end
	end
	return best
end

local function requeue(player, mode, message)
	if not valid(player) or MatchManager.IsPlayerInMatch(player) then return end
	queue[player] = {
		mode = mode,
		joinTime = os.clock(),
		mmr = getMMR(player),
	}
	fire(player, {Status = message or "Requeued", Mode = mode})
end

local function startMatch(p1, p2, mode)
	if not valid(p1) or not valid(p2) or mode == "Ranked" then return false end
	if startingPlayers[p1] or startingPlayers[p2] then return false end
	if MatchManager.IsPlayerInMatch(p1) or MatchManager.IsPlayerInMatch(p2) then return false end

	startingPlayers[p1] = true
	startingPlayers[p2] = true

	local started = false
	local ok, result = pcall(function()
		-- Pick/lock the arena NOW, not when the accept popup was first shown.
		return MatchManager.StartMapVote(p1, p2)
	end)
	started = ok and result == true

	startingPlayers[p1] = nil
	startingPlayers[p2] = nil

	if started then
		if p1.Character then p1.Character:SetAttribute("MatchMode", mode) end
		if p2.Character then p2.Character:SetAttribute("MatchMode", mode) end
		recentMatches[p1] = {opponent = p2, mode = mode}
		recentMatches[p2] = {opponent = p1, mode = mode}
		return true
	end

	warn(string.format(
		"[MatchmakingServer] Match start failed for %s vs %s%s",
		p1.Name,
		p2.Name,
		ok and "" or (": " .. tostring(result))
	))

	-- Don't strand accepted players on a dead match card.
	requeue(p1, mode, "Requeued")
	requeue(p2, mode, "Requeued")
	return false
end

local function clearPendingPair(player, requeueOpponent)
	local pending = pendingMatches[player]
	if not pending then return end

	local opponent = pending.opponent
	pendingMatches[player] = nil
	if pendingMatches[opponent] and pendingMatches[opponent].opponent == player then
		pendingMatches[opponent] = nil
	end

	if requeueOpponent and valid(opponent) then
		requeue(opponent, pending.mode, "Requeued")
	end
end

local function createMatch(p1, p2, mode)
	if mode == "Ranked" or not valid(p1) or not valid(p2) then return end
	if pendingMatches[p1] or pendingMatches[p2] then return end

	remove(p1)
	remove(p2)
	pendingMatches[p1] = {opponent = p2, mode = mode, accepted = false}
	pendingMatches[p2] = {opponent = p1, mode = mode, accepted = false}

	MatchFound:FireClient(p1, {
		OpponentName = p2.Name,
		OpponentMMR = getMMR(p2),
		Mode = mode,
		Timeout = MatchmakingConfig.MATCH_ACCEPT_TIMEOUT,
	})
	MatchFound:FireClient(p2, {
		OpponentName = p1.Name,
		OpponentMMR = getMMR(p1),
		Mode = mode,
		Timeout = MatchmakingConfig.MATCH_ACCEPT_TIMEOUT,
	})

	task.delay(MatchmakingConfig.MATCH_ACCEPT_TIMEOUT, function()
		local a = pendingMatches[p1]
		local b = pendingMatches[p2]
		if not a or not b or a.opponent ~= p2 or b.opponent ~= p1 then return end

		pendingMatches[p1] = nil
		pendingMatches[p2] = nil

		if a.accepted and b.accepted then
			startMatch(p1, p2, mode)
		elseif a.accepted then
			requeue(p1, mode, "Requeued")
		elseif b.accepted then
			requeue(p2, mode, "Requeued")
		else
			fire(p1, {Status = "MatchCancelled"})
			fire(p2, {Status = "MatchCancelled"})
		end
	end)
end

JoinQueue.OnServerEvent:Connect(function(player, mode)
	if not valid(player)
		or MatchManager.IsPlayerInMatch(player)
		or startingPlayers[player]
		or queue[player]
		or pendingMatches[player] then return end

	-- Ranked owns its own cross-server system; don't put it into this local queue.
	if mode == "Ranked" then
		fire(player, {Status = "UseRankedQueue", Mode = "Ranked"})
		return
	end

	mode = "Casual"
	queue[player] = {mode = mode, joinTime = os.clock(), mmr = getMMR(player)}
	fire(player, {Status = "Joined", Mode = mode})
end)

LeaveQueue.OnServerEvent:Connect(function(player)
	if not valid(player) then return end
	remove(player)
	if pendingMatches[player] then
		clearPendingPair(player, true)
	end
	fire(player, {Status = "LeftQueue"})
end)

AcceptMatch.OnServerEvent:Connect(function(player)
	local pending = pendingMatches[player]
	if not pending or not valid(pending.opponent) then return end
	if MatchManager.IsPlayerInMatch(player) or MatchManager.IsPlayerInMatch(pending.opponent) then
		clearPendingPair(player, false)
		return
	end

	pending.accepted = true
	local opponent = pending.opponent
	local other = pendingMatches[opponent]
	if other and other.opponent == player and other.accepted then
		pendingMatches[player] = nil
		pendingMatches[opponent] = nil
		startMatch(player, opponent, pending.mode)
	end
end)

DeclineMatch.OnServerEvent:Connect(function(player)
	local pending = pendingMatches[player]
	if not pending then return end
	local opponent = pending.opponent
	clearPendingPair(player, false)
	fire(player, {Status = "Declined"})
	if valid(opponent) then
		requeue(opponent, pending.mode, "Requeued")
	end
end)

RequestRematch.OnServerEvent:Connect(function(player)
	local recent = recentMatches[player]
	if not valid(player)
		or not recent
		or not valid(recent.opponent)
		or MatchManager.IsPlayerInMatch(player)
		or MatchManager.IsPlayerInMatch(recent.opponent)
		or startingPlayers[player]
		or startingPlayers[recent.opponent] then return end

	local other = recent.opponent
	if rematchRequests[other] and rematchRequests[other].opponent == player then
		rematchRequests[player] = nil
		rematchRequests[other] = nil
		startMatch(player, other, recent.mode)
	else
		rematchRequests[player] = {opponent = other, createdAt = os.clock()}
		RematchResponse:FireClient(other, {FromPlayer = player.Name, Timeout = 20})
		task.delay(20, function()
			local request = rematchRequests[player]
			if request and request.opponent == other then
				rematchRequests[player] = nil
			end
		end)
	end
end)

BotMatchRequest.OnServerEvent:Connect(function(player)
	if not valid(player) or MatchManager.IsPlayerInMatch(player) or startingPlayers[player] then return end
	remove(player)
	clearPendingPair(player, false)

	local arena = MatchManager.GetAvailableArena()
	if arena and _G.StartDummyBattle then
		local ok, started = pcall(_G.StartDummyBattle, player, arena)
		if ok and started == true then
			fire(player, {Status = "BotMatchStarted"})
		else
			fire(player, {Status = "Error", Message = "Practice arena unavailable"})
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(MatchmakingConfig.QUEUE_TICK_INTERVAL)

		for player, entry in pairs(queue) do
			if not valid(player) or MatchManager.IsPlayerInMatch(player) then
				queue[player] = nil
			else
				local opponent = findOpponent(player, entry)
				if opponent then createMatch(player, opponent, entry.mode) end
			end
		end

		local casualCount = countQueue("Casual")
		for player, entry in pairs(queue) do
			if valid(player) and entry.mode == "Casual" then
				local range = math.min(
					MatchmakingConfig.INITIAL_MMR_RANGE
						+ (os.clock() - entry.joinTime) * MatchmakingConfig.MMR_EXPANSION_RATE,
					MatchmakingConfig.MAX_MMR_RANGE
				)
				fire(player, {
					Status = "Searching",
					WaitTime = os.clock() - entry.joinTime,
					MMRRange = range,
					PlayersInQueue = casualCount,
					Mode = entry.mode,
				})
			end
		end
	end
end)

local signal = MatchManager.GetMatchEndedSignal()
signal:Connect(function(p1, p2, winner, metadata)
	if metadata and metadata.Ranked then return end
	if winner then
		updateMMR(winner, true, false)
		local loser = winner == p1 and p2 or p1
		if valid(loser) then
			updateMMR(loser, false, false)
			WinstreakData.Reset(loser)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	remove(player)
	startingPlayers[player] = nil
	rematchRequests[player] = nil
	recentMatches[player] = nil

	local pending = pendingMatches[player]
	if pending then
		clearPendingPair(player, true)
	end

	for requester, request in pairs(rematchRequests) do
		if request.opponent == player then
			rematchRequests[requester] = nil
		end
	end
end)

print("[MatchmakingServer] Initialized")
