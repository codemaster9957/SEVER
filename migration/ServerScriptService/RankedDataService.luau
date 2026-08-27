local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
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

local function normalizeTrophies(value)
	value = tonumber(value) or 0
	if value ~= value or value == math.huge or value == -math.huge then value = 0 end
	return math.max(0, math.floor(value))
end

function RankedDataService.InitializePlayer(player)
	local profile = DataService.GetProfile(player)
	if not profile then return false end
	profile.RankedTrophies = normalizeTrophies(profile.RankedTrophies)
	profile.RankedWins = math.max(0, math.floor(tonumber(profile.RankedWins) or 0))
	profile.RankedLosses = math.max(0, math.floor(tonumber(profile.RankedLosses) or 0))
	initialized[player] = true

	-- The persisted player profile remains the gameplay source of truth; the
	-- OrderedDataStore is its global leaderboard projection.
	local saved = retry(function()
		return trophyStore:SetAsync(tostring(player.UserId), profile.RankedTrophies)
	end)
	return saved
end

function RankedDataService.GetTrophies(player)
	local profile = DataService.GetProfile(player)
	return profile and normalizeTrophies(profile.RankedTrophies) or 0
end

function RankedDataService.ApplyResult(player, matchId, result)
	if not player or not matchId or (result ~= "Victory" and result ~= "Defeat") then
		return nil
	end

	local profile = DataService.GetProfile(player)
	if not profile then return nil end

	local key = keyForUserId(player.UserId) .. "_" .. tostring(matchId)
	local claimToken = HttpService:GenerateGUID(false)

	local ok, accepted = retry(function()
		return resultStore:UpdateAsync(key, function(existing)
			if existing then return existing end
			return {
				UserId = player.UserId,
				MatchId = tostring(matchId),
				Result = result,
				Timestamp = os.time(),
				ClaimToken = claimToken,
			}
		end)
	end)

	if not ok or type(accepted) ~= "table" then return nil end

	-- Only the server invocation whose unique token actually won UpdateAsync may
	-- mutate trophies. Timestamp equality is not unique and allowed duplicate
	-- awards whenever two result handlers ran in the same second.
	if accepted.ClaimToken ~= claimToken then
		return {
			Trophies = RankedDataService.GetTrophies(player),
			Delta = 0,
			Duplicate = true,
		}
	end

	if accepted.Result ~= result then
		warn("[RankedDataService] Result mismatch for already-settled match " .. tostring(matchId))
		return nil
	end

	local delta = result == "Victory" and Shared.WinTrophies or -Shared.LossTrophies
	profile.RankedTrophies = normalizeTrophies(RankedDataService.GetTrophies(player) + delta)
	if result == "Victory" then
		profile.RankedWins = (profile.RankedWins or 0) + 1
	else
		profile.RankedLosses = (profile.RankedLosses or 0) + 1
	end

	local savedLeaderboard = retry(function()
		return trophyStore:SetAsync(tostring(player.UserId), profile.RankedTrophies)
	end)
	if not savedLeaderboard then
		warn("[RankedDataService] Leaderboard projection failed for " .. player.Name)
	end

	-- Even if the global projection is temporarily unavailable, keep the real
	-- profile mutation and let normal DataService autosave retry persistence.
	DataService.SaveProfile(player)

	return {
		Trophies = profile.RankedTrophies,
		Delta = delta,
		Duplicate = false,
	}
end

function RankedDataService.GetTopEntries(limit)
	local ok, pages = retry(function()
		return trophyStore:GetSortedAsync(false, math.clamp(limit or 10, 1, 100))
	end)
	if not ok or not pages then return {} end

	local entries = {}
	for _, entry in ipairs(pages:GetCurrentPage()) do
		table.insert(entries, {
			UserId = tonumber(entry.key),
			Trophies = tonumber(entry.value) or 0,
		})
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
		table.insert(result, {
			Rank = index,
			UserId = entry.UserId,
			Trophies = entry.Trophies,
			IsLocal = entry.UserId == player.UserId,
		})
	end
	return {Rank = rank, Trophies = trophies, Entries = result}
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(RankedDataService.InitializePlayer, player)
end)

Players.PlayerRemoving:Connect(function(player)
	initialized[player] = nil
end)

return RankedDataService
