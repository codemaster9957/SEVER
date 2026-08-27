local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("RankedConfig"))
local MatchManager = require(game:GetService("ServerScriptService"):WaitForChild("MatchManager"))

local RankedMatchmakingService = {}
local queueMap = MemoryStoreService:GetSortedMap("RankedQueue_v2")
local lockMap = MemoryStoreService:GetHashMap("RankedLocks_v2")
local DISPATCH_TOPIC = "RankedMatchDispatch_v2"
local LOCK_TTL = 45

local queued = {}
local inFlight = {}
local lastEntry = {}
local dispatchEvent = Instance.new("BindableEvent")

local function valid(player)
	return player and player.Parent == Players
end

local function safe(call)
	local ok, result = pcall(call)
	if not ok then warn("[RankedMatchmakingService] " .. tostring(result)) end
	return ok, result
end

local function queueKey(userId)
	return tostring(userId)
end

local function userLockKey(userId)
	return "User_" .. tostring(userId)
end

local function buildEntry(player, trophies)
	return {
		UserId = player.UserId,
		Name = player.Name,
		PlaceId = game.PlaceId,
		JobId = game.JobId,
		JoinedAt = os.time(),
		Token = HttpService:GenerateGUID(false),
		Trophies = math.max(0, tonumber(trophies) or 0),
	}
end

local function writeEntry(entry)
	local ok = safe(function()
		queueMap:SetAsync(queueKey(entry.UserId), entry, Shared.QueueEntryTTL, entry.Trophies)
	end)
	return ok
end

local function acquireUserLock(userId, matchId)
	local ok, result = safe(function()
		return lockMap:UpdateAsync(userLockKey(userId), function(existing)
			if existing ~= nil then return existing end
			return {MatchId = matchId, UserId = userId, CreatedAt = os.time()}
		end, LOCK_TTL)
	end)
	return ok and type(result) == "table" and result.MatchId == matchId
end

local function releaseUserLock(userId, matchId)
	local key = userLockKey(userId)
	local ok, existing = safe(function()
		return lockMap:GetAsync(key)
	end)
	if not ok or type(existing) ~= "table" or existing.MatchId ~= matchId then return end

	-- MemoryStore UpdateAsync returning nil aborts the write; RemoveAsync is the
	-- documented deletion path. The read check prevents us removing a newer lock.
	safe(function()
		lockMap:RemoveAsync(key)
	end)
end

local function releaseClaim(entryA, entryB, matchId, requeue)
	releaseUserLock(entryA.UserId, matchId)
	releaseUserLock(entryB.UserId, matchId)
	if requeue then
		writeEntry(entryA)
		writeEntry(entryB)
	end
end

function RankedMatchmakingService.Queue(player, trophies)
	if not valid(player)
		or queued[player.UserId]
		or inFlight[player.UserId]
		or MatchManager.IsPlayerInMatch(player) then
		return false
	end

	local entry = buildEntry(player, trophies)
	if not writeEntry(entry) then return false end
	queued[player.UserId] = entry
	lastEntry[player.UserId] = entry
	return true
end

function RankedMatchmakingService.Cancel(player)
	if not player then return end
	queued[player.UserId] = nil
	safe(function() queueMap:RemoveAsync(queueKey(player.UserId)) end)
end

function RankedMatchmakingService.Claim(entryA, entryB)
	if type(entryA) ~= "table" or type(entryB) ~= "table" or entryA.UserId == entryB.UserId then return nil end
	local matchId = HttpService:GenerateGUID(false)

	if not acquireUserLock(entryA.UserId, matchId) then return nil end
	if not acquireUserLock(entryB.UserId, matchId) then
		releaseUserLock(entryA.UserId, matchId)
		return nil
	end

	local removedA = safe(function() queueMap:RemoveAsync(queueKey(entryA.UserId)) end)
	local removedB = safe(function() queueMap:RemoveAsync(queueKey(entryB.UserId)) end)
	if not removedA or not removedB then
		releaseClaim(entryA, entryB, matchId, true)
		return nil
	end
	return matchId
end

function RankedMatchmakingService.DispatchMatch(entryA, entryB, matchId)
	if not matchId or type(entryA) ~= "table" or type(entryB) ~= "table" then return false end

	local reserveOk, accessCode = pcall(function()
		local code = TeleportService:ReserveServerAsync(game.PlaceId)
		return code
	end)
	if not reserveOk or type(accessCode) ~= "string" or accessCode == "" then
		warn("[RankedMatchmakingService] Failed to reserve ranked server: " .. tostring(accessCode))
		releaseClaim(entryA, entryB, matchId, true)
		return false
	end

	local dispatch = {
		Kind = "RankedMatchDispatch",
		MatchId = matchId,
		AccessCode = accessCode,
		A = entryA.UserId,
		B = entryB.UserId,
		AName = entryA.Name,
		BName = entryB.Name,
		IssuedAt = os.time(),
		CoordinatorJobId = game.JobId,
	}

	local publishOk, publishError = pcall(function()
		MessagingService:PublishAsync(DISPATCH_TOPIC, dispatch)
	end)
	if not publishOk then
		warn("[RankedMatchmakingService] Failed to publish ranked dispatch: " .. tostring(publishError))
		releaseClaim(entryA, entryB, matchId, true)
		return false
	end
	return true
end

function RankedMatchmakingService.GetMatchDispatchSignal()
	return dispatchEvent.Event
end

function RankedMatchmakingService.ValidateTeleportData(data, player)
	if type(data) ~= "table"
		or data.Kind ~= "RankedMatch"
		or type(data.MatchId) ~= "string"
		or type(data.Players) ~= "table"
		or type(data.IssuedAt) ~= "number" then
		return false
	end
	local age = os.time() - data.IssuedAt
	if age < -10 or age > 180 then return false end
	for _, userId in ipairs(data.Players) do
		if userId == player.UserId then return true end
	end
	return false
end

function RankedMatchmakingService.ProcessLocalQueue(onMatch)
	local ok, entries = safe(function()
		return queueMap:GetRangeAsync(Enum.SortDirection.Ascending, 20)
	end)
	if not ok or type(entries) ~= "table" then return end

	for index = 1, #entries - 1 do
		local a = entries[index].value
		local b = entries[index + 1].value
		if a and b and a.UserId ~= b.UserId then
			local matchId = RankedMatchmakingService.Claim(a, b)
			if matchId then
				onMatch(a, b, matchId)
				return
			end
		end
	end
end

local function teleportLocalPlayersForDispatch(data)
	if type(data) ~= "table"
		or data.Kind ~= "RankedMatchDispatch"
		or type(data.MatchId) ~= "string"
		or type(data.AccessCode) ~= "string"
		or type(data.IssuedAt) ~= "number"
		or os.time() - data.IssuedAt > 60 then
		return
	end

	local localPlayers = {}
	for _, userId in ipairs({data.A, data.B}) do
		local numericId = tonumber(userId)
		local player = numericId and Players:GetPlayerByUserId(numericId) or nil
		if valid(player) and not MatchManager.IsPlayerInMatch(player) then
			queued[player.UserId] = nil
			inFlight[player.UserId] = data.MatchId
			dispatchEvent:Fire(player, data)
			table.insert(localPlayers, player)
		end
	end
	if #localPlayers == 0 then return end

	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = data.AccessCode
	options:SetTeleportData({
		Kind = "RankedMatch",
		MatchId = data.MatchId,
		Players = {data.A, data.B},
		IssuedAt = data.IssuedAt,
		CoordinatorJobId = data.CoordinatorJobId,
	})

	local teleportOk, teleportError = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, localPlayers, options)
	end)
	if not teleportOk then
		warn("[RankedMatchmakingService] Ranked teleport failed to start: " .. tostring(teleportError))
		for _, player in ipairs(localPlayers) do
			inFlight[player.UserId] = nil
			local entry = lastEntry[player.UserId]
			if entry and valid(player) then
				entry.JoinedAt = os.time()
				entry.JobId = game.JobId
				entry.Token = HttpService:GenerateGUID(false)
				if writeEntry(entry) then queued[player.UserId] = entry end
			end
		end
	end
end

local subscribeOk, subscription = pcall(function()
	return MessagingService:SubscribeAsync(DISPATCH_TOPIC, function(message)
		teleportLocalPlayersForDispatch(message.Data)
	end)
end)
if not subscribeOk then
	warn("[RankedMatchmakingService] Could not subscribe to ranked dispatches: " .. tostring(subscription))
end

TeleportService.TeleportInitFailed:Connect(function(player)
	local matchId = player and inFlight[player.UserId]
	if not matchId then return end
	inFlight[player.UserId] = nil
	local entry = lastEntry[player.UserId]
	if entry and valid(player) and not MatchManager.IsPlayerInMatch(player) then
		entry.JoinedAt = os.time()
		entry.JobId = game.JobId
		entry.Token = HttpService:GenerateGUID(false)
		if writeEntry(entry) then queued[player.UserId] = entry end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	RankedMatchmakingService.Cancel(player)
	inFlight[player.UserId] = nil
	lastEntry[player.UserId] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if not inFlight[player.UserId] then RankedMatchmakingService.Cancel(player) end
	end
	if typeof(subscription) == "RBXScriptConnection" then subscription:Disconnect() end
end)

return RankedMatchmakingService
