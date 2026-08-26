local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(game:GetService("ServerScriptService"):WaitForChild("DataService"))
local Shared = require(ReplicatedStorage:WaitForChild("RankedConfig"))

local RankedDataService = {}
local trophyStore = DataStoreService:GetOrderedDataStore("RankedTrophies_v1")
local resultStore = DataStoreService:GetDataStore("RankedResults_v1")
local MAX_RETRIES = 3
local initialized = {}

local function retry(callback)
	local lastError
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(callback)
		if ok then return true, result end
		lastError = result
		if attempt < MAX_RETRIES then task.wait(attempt * 2) end
	end
	warn("[RankedDataService] datastore operation failed: " .. tostring(lastError))
	return false, nil
end

local function keyForUserId(userId)
	return "Player_" .. tostring(userId)
end

function RankedDataService.InitializePlayer(player)
	local profile = DataService.GetProfile(player)
	if not profile then return false end
	profile.RankedTrophies = math.max(0, tonumber(profile.RankedTrophies) or 0)
	profile.RankedWins = math.max(0, tonumber(profile.RankedWins) or 0)
	profile.RankedLosses = math.max(0, tonumber(profile.RankedLosses) or 0)
	initialized[player] = true
	local saved = retry(function()
		return trophyStore:SetAsync(tostring(player.UserId), profile.RankedTrophies)
	end)
	return saved
end

function RankedDataService.GetTrophies(player)
	local profile = DataService.GetProfile(player)
	return profile and math.max(0, tonumber(profile.RankedTrophies) or 0) or 0
end

function RankedDataService.ApplyResult(player, matchId, result)
	if not player or not matchId or (result ~= "Victory" and result ~= "Defeat") then
		return nil
	end
	local profile = DataService.GetProfile(player)
	if not profile then return nil end
	local key = keyForUserId(player.UserId) .. "_" .. tostring(matchId)
	local ok, accepted = retry(function()
		return resultStore:UpdateAsync(key, function(existing)
			if existing then return existing end
			return { UserId = player.UserId, MatchId = tostring(matchId), Result = result, Timestamp = os.time() }
		end)
	end)
	if not ok or not accepted or accepted.Result ~= result then
		return nil
	end
	if accepted.Timestamp ~= os.time() and accepted.Timestamp < os.time() - Shared.ResultReplayWindow then
		return nil
	end
	if accepted.Timestamp ~= os.time() then
		return { Trophies = RankedDataService.GetTrophies(player), Delta = 0, Duplicate = true }
	end
	local delta = result == "Victory" and Shared.WinTrophies or -Shared.LossTrophies
	profile.RankedTrophies = math.max(0, RankedDataService.GetTrophies(player) + delta)
	if result == "Victory" then profile.RankedWins += 1 else profile.RankedLosses += 1 end
	local saved = retry(function()
		return trophyStore:SetAsync(tostring(player.UserId), profile.RankedTrophies)
	end)
	if not saved then return nil end
	DataService.SaveProfile(player)
	return { Trophies = profile.RankedTrophies, Delta = delta, Duplicate = false }
end

function RankedDataService.GetTopEntries(limit)
	local ok, pages = retry(function()
		return trophyStore:GetSortedAsync(false, math.clamp(limit or 10, 1, 100))
	end)
	if not ok or not pages then return {} end
	local entries = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(entries, { UserId = tonumber(entry.key), Trophies = tonumber(entry.value) or 0 })
	end
	table.sort(entries, function(a, b)
		if a.Trophies == b.Trophies then return a.UserId < b.UserId end
		return a.Trophies > b.Trophies
	end)
	return entries
end

function RankedDataService.GetRank(player)
	local trophies = RankedDataService.GetTrophies(player)
	local entries = RankedDataService.GetTopEntries(100)
	local rank = 1
	for _, entry in ipairs(entries) do
		if entry.Trophies > trophies or (entry.Trophies == trophies and entry.UserId < player.UserId) then
			rank += 1
		end
	end
	return rank, trophies
end

function RankedDataService.GetLeaderboardFor(player, radius)
	local rank, trophies = RankedDataService.GetRank(player)
	local entries = RankedDataService.GetTopEntries(100)
	local startIndex = math.max(1, rank - (radius or 5))
	local result = {}
	for index = startIndex, math.min(#entries, rank + (radius or 5)) do
		local entry = entries[index]
		table.insert(result, { Rank = index, UserId = entry.UserId, Trophies = entry.Trophies, IsLocal = entry.UserId == player.UserId })
	end
	return { Rank = rank, Trophies = trophies, Entries = result }
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(RankedDataService.InitializePlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	initialized[player] = nil
end)

return RankedDataService