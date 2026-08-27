local WinstreakData = {}

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService:WaitForChild("DataService"))

local winstreaks = {}

local TIERS = {
	{Name = "None", DisplayName = "NONE", Min = 0},
	{Name = "Spark", DisplayName = "SPARK", Min = 2},
	{Name = "Heated", DisplayName = "HEATED", Min = 6},
	{Name = "Burning", DisplayName = "BURNING", Min = 10},
	{Name = "Void", DisplayName = "VOID FLAME", Min = 16},
	{Name = "Champion", DisplayName = "UNSTOPPABLE", Min = 30},
}

local function normalize(value)
	value = tonumber(value) or 0
	if value ~= value or value == math.huge or value == -math.huge then value = 0 end
	return math.max(0, math.floor(value))
end

local function getTierFromStreak(streak)
	local chosenTier = TIERS[1]
	for _, tier in ipairs(TIERS) do
		if streak >= tier.Min then chosenTier = tier end
	end
	return chosenTier
end

local function getNextTier(streak)
	for _, tier in ipairs(TIERS) do
		if streak < tier.Min then return tier end
	end
	return nil
end

local function setPlayerAttributes(player, streak)
	if not player or player.Parent ~= Players then return end
	streak = normalize(streak)
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

local function persist(player, streak)
	local profile = DataService.GetProfile(player)
	if not profile then return end
	profile.CurrentWinStreak = streak
	profile.BestWinStreak = math.max(normalize(profile.BestWinStreak), streak)
end

function WinstreakData.Get(player)
	if not player then return 0 end
	local cached = winstreaks[player]
	if cached ~= nil then return cached end

	local profile = DataService.GetProfile(player)
	local streak = profile and normalize(profile.CurrentWinStreak) or 0
	winstreaks[player] = streak
	setPlayerAttributes(player, streak)
	return streak
end

function WinstreakData.GetTier(player)
	return getTierFromStreak(WinstreakData.Get(player))
end

function WinstreakData.Set(player, amount)
	if not player then return 0 end
	local streak = normalize(amount)
	winstreaks[player] = streak
	setPlayerAttributes(player, streak)
	persist(player, streak)
	return streak
end

function WinstreakData.Increment(player, amount)
	if not player then return 0 end
	amount = tonumber(amount) or 1
	return WinstreakData.Set(player, WinstreakData.Get(player) + amount)
end

function WinstreakData.Reset(player)
	return WinstreakData.Set(player, 0)
end

function WinstreakData.InitPlayer(player, loadedStreak)
	if not player then return end
	local profile = DataService.GetProfile(player)
	local streak
	if loadedStreak ~= nil then
		streak = normalize(loadedStreak)
	elseif profile then
		streak = normalize(profile.CurrentWinStreak)
	else
		streak = 0
	end
	winstreaks[player] = streak
	setPlayerAttributes(player, streak)
	persist(player, streak)
end

function WinstreakData.Cleanup(player)
	winstreaks[player] = nil
end

local function initialize(player)
	task.spawn(function()
		local profile = DataService.GetProfile(player)
		if player.Parent == Players and profile then
			WinstreakData.InitPlayer(player, profile.CurrentWinStreak)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do initialize(player) end
Players.PlayerAdded:Connect(initialize)
Players.PlayerRemoving:Connect(WinstreakData.Cleanup)

return WinstreakData
