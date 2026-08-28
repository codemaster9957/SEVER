-- Arena-aware wrapper around the existing match lifecycle.
-- Keeps the battle flow intact while making arena discovery dynamic and reservations race-safe.

local MatchManager = require(script.Parent:WaitForChild("MatchManagerLegacy"))
local ArenaSelectionPolicy = require(script.Parent:WaitForChild("ArenaSelectionPolicy"))

local ArenasFolder = workspace:WaitForChild("Arenas")
local arenaRandom = Random.new()

local legacyStartMatch = MatchManager.StartMatch
local legacyEndMatch = MatchManager.EndMatch
local legacyLockArena = MatchManager.LockArena
local legacyUnlockArena = MatchManager.UnlockArena

-- Reservation state covers both matches waiting for characters and arenas already locked
-- by the legacy lifecycle. This closes the window where two starts could pick one arena.
local reservations = {}
local arenaByPlayer = {}

local function findSpawn(arena, spawnName)
	for _, descendant in ipairs(arena:GetDescendants()) do
		if descendant:IsA("BasePart") and string.sub(descendant.Name, 1, #spawnName) == spawnName then
			return descendant
		end
	end
	return nil
end

local function isArenaUsable(arena)
	return arena ~= nil
		and findSpawn(arena, "ArenaSpawn1") ~= nil
		and findSpawn(arena, "ArenaSpawn2") ~= nil
end

local function getAvailableArenas()
	return ArenaSelectionPolicy.FilterAvailable(
		ArenasFolder:GetChildren(),
		function(arena)
			return reservations[arena.Name] ~= nil
		end,
		isArenaUsable
	)
end

local function chooseRandomAvailableArena()
	return ArenaSelectionPolicy.ChooseRandom(getAvailableArenas(), function(minimum, maximum)
		return arenaRandom:NextInteger(minimum, maximum)
	end)
end

local function reserveArena(preferredName, state)
	if preferredName then
		local preferred = ArenasFolder:FindFirstChild(preferredName)
		if preferred and reservations[preferred.Name] == nil and isArenaUsable(preferred) then
			reservations[preferred.Name] = state
			return preferred
		end
	end

	local arena = chooseRandomAvailableArena()
	if not arena then
		return nil
	end

	reservations[arena.Name] = state
	return arena
end

local function releaseReservation(arenaName)
	if arenaName then
		reservations[arenaName] = nil
	end
end

function MatchManager.GetAvailableArena()
	local arena = chooseRandomAvailableArena()
	return arena and arena.Name or nil
end

function MatchManager.LockArena(arenaName)
	if not arenaName then
		return false
	end

	local arena = ArenasFolder:FindFirstChild(arenaName)
	if not arena or not isArenaUsable(arena) then
		return false
	end

	local state = reservations[arenaName]
	if state == "pendingDummy" then
		local locked = legacyLockArena(arenaName)
		if locked then
			reservations[arenaName] = "locked"
		else
			releaseReservation(arenaName)
		end
		return locked
	end

	if state ~= nil then
		return false
	end

	local locked = legacyLockArena(arenaName)
	if locked then
		reservations[arenaName] = "locked"
	end
	return locked
end

function MatchManager.UnlockArena(arenaName)
	releaseReservation(arenaName)
	legacyUnlockArena(arenaName)
end

function MatchManager.StartMatch(p1, p2, arenaName, forceOvertime)
	local arena = reserveArena(arenaName, "pendingMatch")
	if not arena then
		return false
	end

	local ok, started = pcall(legacyStartMatch, p1, p2, arena.Name, forceOvertime)
	if not ok then
		releaseReservation(arena.Name)
		legacyUnlockArena(arena.Name)
		error(started, 0)
	end

	if started ~= true then
		releaseReservation(arena.Name)
		legacyUnlockArena(arena.Name)
		return false
	end

	reservations[arena.Name] = "locked"
	arenaByPlayer[p1] = arena.Name
	arenaByPlayer[p2] = arena.Name
	return true
end

function MatchManager.StartMapVote(p1, p2)
	if typeof(p2) == "table" and p2.IsDummy then
		local arena = reserveArena(nil, "pendingDummy")
		if not arena then
			return false
		end

		local ok, result = pcall(function()
			return _G.StartDummyBattle and _G.StartDummyBattle(p1, arena.Name)
		end)

		if not ok or result ~= true then
			releaseReservation(arena.Name)
			legacyUnlockArena(arena.Name)
			if not ok then
				warn("[MatchManager] Dummy battle start failed: " .. tostring(result))
			end
			return false
		end

		return true
	end

	-- Normal PvP chooses/reserves inside StartMatch instead of preselecting an arena
	-- before character-readiness waits.
	return MatchManager.StartMatch(p1, p2, nil) == true
end

function MatchManager.EndMatch(p1, p2, winner, arenaName)
	local resolvedArenaName = arenaName or arenaByPlayer[p1] or arenaByPlayer[p2]
	local result = legacyEndMatch(p1, p2, winner, arenaName)

	releaseReservation(resolvedArenaName)
	arenaByPlayer[p1] = nil
	arenaByPlayer[p2] = nil

	return result
end

return MatchManager
