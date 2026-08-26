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

local function valid(player) return player and player.Parent == Players end
local function getMMR(player)
	local profile = DataService.GetProfile(player)
	return profile and profile.MMR or MatchmakingConfig.BASE_MMR
end
local function fire(player, status)
	if valid(player) then QueueStatusUpdate:FireClient(player, status) end
end
local function remove(player) queue[player] = nil end
local function updateMMR(player, win, ranked)
	local profile = DataService.GetProfile(player)
	if not profile then return end
	local delta = win and (ranked and MatchmakingConfig.RankedWinMMR or MatchmakingConfig.CasualWinMMR) or -(ranked and MatchmakingConfig.RankedLossMMR or MatchmakingConfig.CasualLossMMR)
	profile.MMR = math.max(0, (profile.MMR or MatchmakingConfig.BASE_MMR) + delta)
	if win then
		profile.Wins = (profile.Wins or 0) + 1
		if ranked then profile.RankedWins = (profile.RankedWins or 0) + 1 else profile.CasualWins = (profile.CasualWins or 0) + 1 end
	else
		profile.Losses = (profile.Losses or 0) + 1
		if ranked then profile.RankedLosses = (profile.RankedLosses or 0) + 1 else profile.CasualLosses = (profile.CasualLosses or 0) + 1 end
	end
end
local function findOpponent(player, entry)
	local best, diff = nil, math.huge
	for other, otherEntry in pairs(queue) do
		if other ~= player and valid(other) and otherEntry.mode == entry.mode then
			local currentDiff = math.abs(entry.mmr - otherEntry.mmr)
			local range = math.min(MatchmakingConfig.INITIAL_MMR_RANGE + (os.clock() - entry.joinTime) * MatchmakingConfig.MMR_EXPANSION_RATE, MatchmakingConfig.MAX_MMR_RANGE)
			if currentDiff <= range and currentDiff < diff then best, diff = other, currentDiff end
		end
	end
	return best
end
local function startMatch(p1, p2, mode, arena)
	if not valid(p1) or not valid(p2) or mode == "Ranked" or MatchManager.IsPlayerInMatch(p1) or MatchManager.IsPlayerInMatch(p2) then return end
	if p1.Character then p1.Character:SetAttribute("MatchMode", mode) end
	if p2.Character then p2.Character:SetAttribute("MatchMode", mode) end
	recentMatches[p1] = { opponent = p2, mode = mode }
	recentMatches[p2] = { opponent = p1, mode = mode }
	MatchManager.StartMatch(p1, p2, arena)
end
local function createMatch(p1, p2, mode)
	if mode == "Ranked" then return end
	remove(p1); remove(p2)
	local arena = MatchManager.GetAvailableArena()
	if not arena then fire(p1, {Status="Error", Message="No arenas available"}); fire(p2, {Status="Error", Message="No arenas available"}); return end
	pendingMatches[p1] = {opponent=p2, arena=arena, mode=mode, accepted=false}
	pendingMatches[p2] = {opponent=p1, arena=arena, mode=mode, accepted=false}
	MatchFound:FireClient(p1, {OpponentName=p2.Name, OpponentMMR=getMMR(p2), Mode=mode, Timeout=MatchmakingConfig.MATCH_ACCEPT_TIMEOUT})
	MatchFound:FireClient(p2, {OpponentName=p1.Name, OpponentMMR=getMMR(p1), Mode=mode, Timeout=MatchmakingConfig.MATCH_ACCEPT_TIMEOUT})
	task.delay(MatchmakingConfig.MATCH_ACCEPT_TIMEOUT, function()
		local a,b = pendingMatches[p1], pendingMatches[p2]
		if not a or not b then return end
		pendingMatches[p1], pendingMatches[p2] = nil, nil
		if a.accepted and b.accepted then startMatch(p1,p2,mode,a.arena)
		elseif a.accepted then queue[p1] = {mode=mode,joinTime=os.clock(),mmr=getMMR(p1)}; fire(p1,{Status="Requeued"})
		elseif b.accepted then queue[p2] = {mode=mode,joinTime=os.clock(),mmr=getMMR(p2)}; fire(p2,{Status="Requeued"})
		else fire(p1,{Status="MatchCancelled"}); fire(p2,{Status="MatchCancelled"}) end
	end)
end
JoinQueue.OnServerEvent:Connect(function(player, mode)
	if not valid(player) or MatchManager.IsPlayerInMatch(player) or queue[player] or pendingMatches[player] then return end
	mode = mode == "Ranked" and "Ranked" or "Casual"
	queue[player] = {mode=mode, joinTime=os.clock(), mmr=getMMR(player)}
	fire(player,{Status="Joined",Mode=mode})
end)
LeaveQueue.OnServerEvent:Connect(function(player)
	if not valid(player) then return end
	remove(player); pendingMatches[player] = nil; fire(player,{Status="LeftQueue"})
end)
AcceptMatch.OnServerEvent:Connect(function(player)
	local pending = pendingMatches[player]
	if not pending then return end
	pending.accepted = true
	local other = pendingMatches[pending.opponent]
	if other and other.accepted then pendingMatches[player], pendingMatches[pending.opponent] = nil, nil; startMatch(player,pending.opponent,pending.mode,pending.arena) end
end)
DeclineMatch.OnServerEvent:Connect(function(player)
	local pending = pendingMatches[player]
	if not pending then return end
	pendingMatches[player], pendingMatches[pending.opponent] = nil, nil
	fire(player,{Status="Declined"})
	if valid(pending.opponent) then queue[pending.opponent] = {mode=pending.mode,joinTime=os.clock(),mmr=getMMR(pending.opponent)}; fire(pending.opponent,{Status="Requeued"}) end
end)
RequestRematch.OnServerEvent:Connect(function(player)
	local recent = recentMatches[player]
	if not valid(player) or not recent or not valid(recent.opponent) or MatchManager.IsPlayerInMatch(player) or MatchManager.IsPlayerInMatch(recent.opponent) then return end
	local other = recent.opponent
	if rematchRequests[other] and rematchRequests[other].opponent == player then
		rematchRequests[player], rematchRequests[other] = nil, nil
		local arena = MatchManager.GetAvailableArena()
		if arena then startMatch(player,other,recent.mode,arena) end
	else
		rematchRequests[player] = {opponent=other}
		RematchResponse:FireClient(other,{FromPlayer=player.Name,Timeout=20})
		task.delay(20,function() rematchRequests[player] = nil end)
	end
end)
BotMatchRequest.OnServerEvent:Connect(function(player)
	if not valid(player) or MatchManager.IsPlayerInMatch(player) then return end
	remove(player)
	local arena = MatchManager.GetAvailableArena()
	if arena and _G.StartDummyBattle then _G.StartDummyBattle(player,arena); fire(player,{Status="BotMatchStarted"}) end
end)
task.spawn(function()
	while true do
		task.wait(MatchmakingConfig.QUEUE_TICK_INTERVAL)
		for player, entry in pairs(queue) do
			if valid(player) then
				local opponent = findOpponent(player,entry)
				if opponent then createMatch(player,opponent,entry.mode) end
			else queue[player] = nil end
		end
		for player, entry in pairs(queue) do
			if valid(player) and entry.mode == "Casual" then fire(player,{Status="Searching",WaitTime=os.clock()-entry.joinTime,MMRRange=MatchmakingConfig.MAX_MMR_RANGE,PlayersInQueue=1,Mode=entry.mode}) end
		end
	end
end)
local signal = MatchManager.GetMatchEndedSignal()
signal:Connect(function(p1,p2,winner,metadata)
	if metadata and metadata.Ranked then return end
	if winner then updateMMR(winner,true,false); local loser = winner == p1 and p2 or p1; if valid(loser) then updateMMR(loser,false,false); WinstreakData.Reset(loser) end end
end)
Players.PlayerRemoving:Connect(function(player)
	remove(player); pendingMatches[player]=nil; rematchRequests[player]=nil; recentMatches[player]=nil
	for p,pending in pairs(pendingMatches) do if pending.opponent == player then pendingMatches[p]=nil; if valid(p) then queue[p]={mode=pending.mode,joinTime=os.clock(),mmr=getMMR(p)}; fire(p,{Status="Requeued"}) end end end
end)
print("[MatchmakingServer] Initialized")