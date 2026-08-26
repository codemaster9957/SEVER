local RankedShared = {
	QueueStates = {
		Idle = "Idle",
		Searching = "Searching",
		OpponentFound = "OpponentFound",
		JoiningMatch = "JoiningMatch",
		Cancelled = "Cancelled",
		Error = "Error",
	},
	MatchStates = {
		OpponentFound = "OpponentFound",
		JoiningMatch = "JoiningMatch",
		BattleStarted = "BattleStarted",
		Completed = "Completed",
		Failed = "Failed",
	},
	Results = {
		Victory = "Victory",
		Defeat = "Defeat",
		Draw = "Draw",
	},
	QueueEntryTTL = 45,
	QueuePollInterval = 2,
	WinTrophies = 10,
	LossTrophies = 5,
	LeaderboardPageSize = 100,
	ResultReplayWindow = 300,
}

function RankedShared.IsQueueAction(value)
	return value == "Join" or value == "Cancel"
end

return RankedShared