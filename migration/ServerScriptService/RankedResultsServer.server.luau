local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchManager = require(script.Parent:WaitForChild("MatchManager"))
local RankedDataService = require(script.Parent:WaitForChild("RankedDataService"))
local events = ReplicatedStorage:WaitForChild("RankedEvents")
local resultsState = events:WaitForChild("ResultsState")
local leaderboardState = events:WaitForChild("LeaderboardState")
local settled = {}

local function send(player, event, data)
	if player and player.Parent == Players then event:FireClient(player, data) end
end

MatchManager.GetMatchEndedSignal():Connect(function(p1, p2, winner, metadata)
	if not metadata or not metadata.Ranked or not metadata.MatchId or settled[metadata.MatchId] then return end
	settled[metadata.MatchId] = true
	for _, player in ipairs({p1, p2}) do
		if player and player.Parent == Players then
			local result = winner == player and "Victory" or "Defeat"
			if not winner then result = "Draw" end
			local reward = result == "Victory" and RankedDataService.ApplyResult(player, metadata.MatchId, result) or nil
			if result == "Defeat" then reward = RankedDataService.ApplyResult(player, metadata.MatchId, result) end
			if result == "Draw" then reward = { Trophies = RankedDataService.GetTrophies(player), Delta = 0 } end
			if reward then
				send(player, resultsState, { Result = result, Delta = reward.Delta, Trophies = reward.Trophies, MatchId = metadata.MatchId })
				send(player, leaderboardState, RankedDataService.GetLeaderboardFor(player, 5))
			end
		end
	end
	task.delay(300, function() settled[metadata.MatchId] = nil end)
end)

print("[RankedResultsServer] Initialized")