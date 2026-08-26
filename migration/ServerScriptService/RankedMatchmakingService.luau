local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("RankedConfig"))
local MatchManager = require(game:GetService("ServerScriptService"):WaitForChild("MatchManager"))

local RankedMatchmakingService = {}
local queueMap = MemoryStoreService:GetSortedMap("RankedQueue_v1")
local lockMap = MemoryStoreService:GetHashMap("RankedLocks_v1")
local queued = {}
local inFlight = {}

local function valid(player)
	return player and player.Parent == Players
end

local function safe(call)
	local ok, result = pcall(call)
	if not ok then warn("[RankedMatchmakingService] " .. tostring(result)) end
	return ok, result
end

function RankedMatchmakingService.Queue(player, trophies)
	if not valid(player) or queued[player.UserId] or MatchManager.IsPlayerInMatch(player) then return false end
	local entry = { UserId = player.UserId, PlaceId = game.PlaceId, JobId = game.JobId, JoinedAt = os.time(), Token = HttpService:GenerateGUID(false), Trophies = trophies }
	local ok = safe(function()
		queueMap:SetAsync(tostring(player.UserId), entry, Shared.QueueEntryTTL, trophies)
	end)
	if ok then queued[player.UserId] = entry end
	return ok
end

function RankedMatchmakingService.Cancel(player)
	if not player then return end
	queued[player.UserId] = nil
	safe(function() queueMap:RemoveAsync(tostring(player.UserId)) end)
end

function RankedMatchmakingService.Claim(entryA, entryB)
	local matchId = HttpService:GenerateGUID(false)
	local lockKey = "Match_" .. matchId
	local ok = safe(function()
		return lockMap:SetAsync(lockKey, { MatchId = matchId, A = entryA.UserId, B = entryB.UserId, CreatedAt = os.time() }, 30)
	end)
	if not ok then return nil end
	safe(function() queueMap:RemoveAsync(tostring(entryA.UserId)) end)
	safe(function() queueMap:RemoveAsync(tostring(entryB.UserId)) end)
	return matchId
end

function RankedMatchmakingService.TeleportMatchedPlayers(players, matchId)
	if #players ~= 2 or not matchId then return false end
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true
	options:SetTeleportData({
		Kind = "RankedMatch",
		MatchId = matchId,
		Players = { players[1].UserId, players[2].UserId },
		IssuedAt = os.time(),
		IssuerJobId = game.JobId,
	})
	local ok = safe(function()
		TeleportService:TeleportAsync(game.PlaceId, players, options)
	end)
	if ok then
		for _, player in ipairs(players) do inFlight[player.UserId] = matchId end
	end
	return ok
end

function RankedMatchmakingService.ValidateTeleportData(data, player)
	if type(data) ~= "table" or data.Kind ~= "RankedMatch" or type(data.MatchId) ~= "string" or type(data.Players) ~= "table" then return false end
	if data.IssuedAt == nil or os.time() - data.IssuedAt > 120 then return false end
	for _, userId in ipairs(data.Players) do
		if userId == player.UserId then return true end
	end
	return false
end

function RankedMatchmakingService.ProcessLocalQueue(onMatch)
	local ok, entries = safe(function()
		return queueMap:GetRangeAsync(Enum.SortDirection.Ascending, 20)
	end)
	if not ok or not entries then return end
	for index = 1, #entries - 1 do
		local a = entries[index].value
		local b = entries[index + 1].value
		if a and b and a.UserId ~= b.UserId then
			local matchId = RankedMatchmakingService.Claim(a, b)
			if matchId then onMatch(a, b, matchId) return end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	RankedMatchmakingService.Cancel(player)
	inFlight[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do RankedMatchmakingService.Cancel(player) end
end)

return RankedMatchmakingService