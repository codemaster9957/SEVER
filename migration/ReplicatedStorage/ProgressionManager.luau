local ProgressionManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local titles = {
	{id = "Unbroken", name = "The Unbroken", condition = "Win 10 matches in a row"},
	{id = "Clashmaster", name = "Clashmaster", condition = "Win 100 clashes"},
	{id = "OvertimeKing", name = "Overtime King", condition = "Win 5 overdrive matches"}
}

function ProgressionManager.GetPlayerTitle(player)
	-- In a real game this would come from DataStore
	return "Rookie"
end

function ProgressionManager.GetWinStreak(player)
	local streak = player:GetAttribute("WinStreak") or 0
	return streak
end

function ProgressionManager.GetRank(player)
	return "Bronze I"
end

return ProgressionManager
