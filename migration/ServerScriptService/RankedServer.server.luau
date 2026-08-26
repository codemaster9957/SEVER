local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local events = ReplicatedStorage:WaitForChild("RankedEvents")
local queueRequest = events:WaitForChild("QueueRequest")
local queueState = events:WaitForChild("QueueState")
local matchState = events:WaitForChild("MatchState")
local leaderboardState = events:WaitForChild("LeaderboardState")
local resultsState = events:WaitForChild("ResultsState")
local leaderboardRequest = events:WaitForChild("LeaderboardRequest")
local rankQuery = events:WaitForChild("RankQuery")
local RankedDataService = require(script.Parent:WaitForChild("RankedDataService"))
local RankedMatchmakingService = require(script.Parent:WaitForChild("RankedMatchmakingService"))
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))

local active = {}
local function send(player, state, data)
	if player and player.Parent == Players then state:FireClient(player, data) end
end

local function publishLeaderboard(player)
	send(player, leaderboardState, RankedDataService.GetLeaderboardFor(player, 5))
end

rankQuery.OnServerInvoke = function(player)
	local rank, trophies = RankedDataService.GetRank(player)
	return { Rank = rank, Trophies = trophies }
end

leaderboardRequest.OnServerEvent:Connect(function(player)
	publishLeaderboard(player)
end)

queueRequest.OnServerEvent:Connect(function(player, action)
	if action == "Cancel" then
		RankedMatchmakingService.Cancel(player)
		active[player] = nil
		send(player, queueState, { State = "Cancelled" })
		return
	end
	if action ~= "Join" or active[player] then return end
	active[player] = true
	local trophies = RankedDataService.GetTrophies(player)
	if RankedMatchmakingService.Queue(player, trophies) then
		send(player, queueState, { State = "Searching" })
	else
		active[player] = nil
		send(player, queueState, { State = "Error", Message = "Unable to join ranked queue" })
	end
end)

task.spawn(function()
	while true do
		task.wait(2)
		RankedMatchmakingService.ProcessLocalQueue(function(a, b, matchId)
			local p1 = Players:GetPlayerByUserId(a.UserId)
			local p2 = Players:GetPlayerByUserId(b.UserId)
			if p1 and p2 then
				MatchManager.SetMatchMetadata(p1, p2, matchId, true)
				active[p1] = nil
				active[p2] = nil
				send(p1, queueState, { State = "OpponentFound", MatchId = matchId, OpponentUserId = p2.UserId, OpponentName = p2.Name })
				send(p2, queueState, { State = "OpponentFound", MatchId = matchId, OpponentUserId = p1.UserId, OpponentName = p1.Name })
				send(p1, queueState, { State = "JoiningMatch", MatchId = matchId })
				send(p2, queueState, { State = "JoiningMatch", MatchId = matchId })
				matchState:FireClient(p1, { State = "JoiningMatch", MatchId = matchId })
				matchState:FireClient(p2, { State = "JoiningMatch", MatchId = matchId })
				RankedMatchmakingService.TeleportMatchedPlayers({ p1, p2 }, matchId)
			end
		end)
	end
end)

local teleportData = TeleportService:GetLocalPlayerTeleportData()
if teleportData and teleportData.Kind == "RankedMatch" then
	task.defer(function()
		local players = {}
		for _, userId in ipairs(teleportData.Players or {}) do
			local player = Players:GetPlayerByUserId(userId)
			if player then table.insert(players, player) end
		end
		if #players == 2 then
			local arena = MatchManager.GetAvailableArena()
			if arena then
				for _, player in ipairs(players) do
					if player.Character then player.Character:SetAttribute("MatchMode", "Ranked") end
				end
				MatchManager.StartMatch(players[1], players[2], arena)
			end
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	active[player] = nil
	RankedMatchmakingService.Cancel(player)
end)

print("[RankedServer] Initialized")