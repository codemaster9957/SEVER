local WinstreakData = {}

local Players = game:GetService("Players")

local winstreaks = {} -- [Player] = number

local TIERS = {
	{
		Name = "None",
		DisplayName = "NONE",
		Min = 0,
	},

	{
		Name = "Spark",
		DisplayName = "SPARK",
		Min = 2,
	},

	{
		Name = "Heated",
		DisplayName = "HEATED",
		Min = 6,
	},

	{
		Name = "Burning",
		DisplayName = "BURNING",
		Min = 10,
	},

	{
		Name = "Void",
		DisplayName = "VOID FLAME",
		Min = 16,
	},

	{
		Name = "Champion",
		DisplayName = "UNSTOPPABLE",
		Min = 30,
	},
}

local function getTierFromStreak(streak)
	local chosenTier = TIERS[1]

	for _, tier in ipairs(TIERS) do
		if streak >= tier.Min then
			chosenTier = tier
		end
	end

	return chosenTier
end

local function getNextTier(streak)
	for _, tier in ipairs(TIERS) do
		if streak < tier.Min then
			return tier
		end
	end

	return nil
end

local function setPlayerAttributes(player, streak)
	if not player or player.Parent ~= Players then
		return
	end

	streak = tonumber(streak) or 0
	streak = math.max(0, math.floor(streak))

	local tier = getTierFromStreak(streak)
	local nextTier = getNextTier(streak)

	player:SetAttribute("WinStreak", streak)
	player:SetAttribute("WinStreakTier", tier.Name)
	player:SetAttribute("WinStreakTierName", tier.DisplayName)

	if nextTier then
		player:SetAttribute("NextWinStreakTier", nextTier.DisplayName)
		player:SetAttribute("NextWinStreakRequired", nextTier.Min)
	else
		player:SetAttribute("NextWinStreakTier", "MAX")
		player:SetAttribute("NextWinStreakRequired", -1)
	end
end

function WinstreakData.Get(player)
	return winstreaks[player] or 0
end

function WinstreakData.GetTier(player)
	local streak = WinstreakData.Get(player)
	return getTierFromStreak(streak)
end

function WinstreakData.Set(player, amount)
	if not player then
		return 0
	end

	local streak = tonumber(amount) or 0
	streak = math.max(0, math.floor(streak))

	winstreaks[player] = streak
	setPlayerAttributes(player, streak)

	return streak
end

function WinstreakData.Increment(player, amount)
	if not player then
		return 0
	end

	amount = tonumber(amount) or 1

	local currentStreak = winstreaks[player] or 0
	local newStreak = currentStreak + amount

	return WinstreakData.Set(player, newStreak)
end

function WinstreakData.Reset(player)
	return WinstreakData.Set(player, 0)
end

function WinstreakData.InitPlayer(player, loadedStreak)
	if not player then
		return
	end

	local streak = tonumber(loadedStreak) or 0
	streak = math.max(0, math.floor(streak))

	winstreaks[player] = streak
	setPlayerAttributes(player, streak)
end

function WinstreakData.Cleanup(player)
	winstreaks[player] = nil
end

return WinstreakData