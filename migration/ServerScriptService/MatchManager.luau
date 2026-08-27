local MatchManager = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate")
local MapVoteStart = MatchEvents:WaitForChild("MapVoteStart")
local MapVoteSubmit = MatchEvents:WaitForChild("MapVoteSubmit")
local MapVoteResult = MatchEvents:WaitForChild("MapVoteResult")

local ArenasFolder = workspace:WaitForChild("Arenas")
local Lobby = workspace:WaitForChild("Lobby")
local LobbySpawn = Lobby:WaitForChild("LobbySpawn")

local ServerScriptService = game:GetService("ServerScriptService")
local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))
local WinstreakData = require(ServerScriptService:WaitForChild("WinstreakData"))
local OvertimeManager = require(ServerScriptService:WaitForChild("OvertimeManager"))
local MatchStateController = require(ReplicatedStorage:WaitForChild("MatchStateController"))

-- playerStates is authoritative match MEMBERSHIP only: "Lobby" or "InMatch".
-- UI phases such as LoadingArena/Countdown/Fighting are sent to clients separately.
local activeMatches = {}
local playerStates = {}
local endingMatches = {}
local arenaLocks = {}
local matchArenaByPlayer = {}
local votingSessions = {}
local matchVotes = {}
local matchMetadata = {}
local MatchEndedSignal = Instance.new("BindableEvent")
local arenaRandom = Random.new()

local ALL_ARENAS = {"Arena1", "Arena2", "Arena3", "Arena4", "Arena5"}
local MAP_VOTE_TIMEOUT = 10
local MATCH_DURATION = 90
local TIMER_UPDATE_INTERVAL = 0.1
local CHARACTER_READY_TIMEOUT = 3
local TELEPORT_ATTEMPTS = 3
local TELEPORT_VERIFY_RADIUS = 14

local function isValidPlayer(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function getAvailableArena()
	local available = {}
	for _, name in ipairs(ALL_ARENAS) do
		if not arenaLocks[name] then
			local arena = ArenasFolder:FindFirstChild(name)
			if arena then
				table.insert(available, name)
			end
		end
	end
	return available
end

local function chooseRandomAvailableArena()
	local available = getAvailableArena()
	if #available == 0 then return nil end
	return available[arenaRandom:NextInteger(1, #available)]
end

function MatchManager.StartMapVote(p1, p2)
	if not isValidPlayer(p1) then return false end
	if typeof(p2) == "Instance" and not isValidPlayer(p2) then return false end

	local arenaName = chooseRandomAvailableArena()
	if not arenaName then return false end

	if typeof(p2) == "table" and p2.IsDummy then
		local result = _G.StartDummyBattle and _G.StartDummyBattle(p1, arenaName)
		return result == true
	end

	return MatchManager.StartMatch(p1, p2, arenaName) == true
end

function MatchManager.GetAvailableArena()
	return chooseRandomAvailableArena()
end

function MatchManager.UnlockArena(arenaName)
	if arenaName then arenaLocks[arenaName] = false end
end

function MatchManager.LockArena(arenaName)
	if not arenaName or arenaLocks[arenaName] then return false end
	arenaLocks[arenaName] = true
	return true
end

function MatchManager.IsPlayerInMatch(player)
	if not player then return false end
	if playerStates[player] == "InMatch" or activeMatches[player] ~= nil then
		return true
	end
	local character = player.Character
	return character ~= nil and character:GetAttribute("InMatch") == true
end

function MatchManager.SetPlayerState(player, state)
	if player then
		playerStates[player] = state
	end
end

function MatchManager.CanUseCombat(player)
	if not isValidPlayer(player) or not MatchManager.IsPlayerInMatch(player) then
		return false
	end
	local character = player.Character
	return character ~= nil
		and character:GetAttribute("InMatch") == true
		and character:GetAttribute("CanAttack") ~= false
end

function MatchManager.GetOpponent(player)
	return activeMatches[player]
end

local function findSpawn(arena, spawnName)
	for _, descendant in ipairs(arena:GetDescendants()) do
		if descendant:IsA("BasePart") and string.sub(descendant.Name, 1, #spawnName) == spawnName then
			return descendant
		end
	end
	return nil
end

local function safeFireClient(player, state, data)
	if isValidPlayer(player) then
		GameStateUpdate:FireClient(player, state, data)
	end
end

-- IMPORTANT: this function is client/UI state only. It must never overwrite
-- authoritative playerStates, otherwise IsPlayerInMatch becomes false during
-- LoadingArena/BattleIntro/Countdown/Fighting.
local function setMatchState(p1, p2, state, data)
	if isValidPlayer(p1) then
		safeFireClient(p1, state, data)
	end
	if isValidPlayer(p2) then
		safeFireClient(p2, state, data)
	end
end

local function getReadyCharacter(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or CHARACTER_READY_TIMEOUT)

	repeat
		if not isValidPlayer(player) then
			return nil
		end

		local character = player.Character
		if character and character.Parent then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local root = character:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then
				return character, humanoid, root
			end
		end

		task.wait(0.05)
	until os.clock() >= deadline

	return nil
end

local function targetCFrameForSpawn(spawnPart)
	return spawnPart.CFrame + Vector3.new(0, spawnPart.Size.Y / 2 + 3, 0)
end

local function teleportPlayer(player, spawnPart)
	if not isValidPlayer(player) or not spawnPart or not spawnPart:IsA("BasePart") then
		return false
	end

	local targetCFrame = targetCFrameForSpawn(spawnPart)

	for _ = 1, TELEPORT_ATTEMPTS do
		local character, humanoid, root = getReadyCharacter(player, CHARACTER_READY_TIMEOUT)
		if not character or not humanoid or not root then
			continue
		end

		character:PivotTo(targetCFrame)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		if character:GetAttribute("InMatch") then
			character:SetAttribute("ArenaZ", spawnPart.Position.Z)
		else
			character:SetAttribute("ArenaZ", nil)
		end

		task.wait(0.08)

		if player.Character == character and character.Parent then
			local distance = (character:GetPivot().Position - targetCFrame.Position).Magnitude
			if distance <= TELEPORT_VERIFY_RADIUS then
				return true
			end
		end
	end

	warn(string.format("[MatchManager] Failed to place %s at %s", player.Name, spawnPart:GetFullName()))
	return false
end

local function ensureAtSpawn(player, spawnPart)
	if not isValidPlayer(player) or not spawnPart then return false end
	local character = player.Character
	if character and character.Parent then
		local target = targetCFrameForSpawn(spawnPart).Position
		if (character:GetPivot().Position - target).Magnitude <= TELEPORT_VERIFY_RADIUS then
			return true
		end
	end
	return teleportPlayer(player, spawnPart)
end

local function setInMatch(player, status)
	if not isValidPlayer(player) then return end
	playerStates[player] = status and "InMatch" or "Lobby"

	local character = player.Character
	if character then
		character:SetAttribute("InMatch", status == true)
		if not status then
			character:SetAttribute("ArenaZ", nil)
		end
	end
end

local function setControllable(player, controllable)
	if not isValidPlayer(player) then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = controllable and 16 or 0
		if humanoid.UseJumpPower then
			humanoid.JumpPower = controllable and 50 or 0
		else
			humanoid.JumpHeight = controllable and 7.2 or 0
		end
	end
	character:SetAttribute("CanAttack", controllable)
	character:SetAttribute("CanBlock", controllable)
end

local function clearMatchReferences(p1, p2, arenaName)
	for _, player in ipairs({p1, p2}) do
		if player then
			activeMatches[player] = nil
			matchMetadata[player] = nil
			matchArenaByPlayer[player] = nil
			playerStates[player] = "Lobby"
			endingMatches[player] = nil
			DamageHandler.RemovePlayer(player)
		end
	end
	if arenaName then
		arenaLocks[arenaName] = false
	end
end

local function abortMatchStart(p1, p2, arenaName, reason)
	warn(string.format("[MatchManager] Cancelling match start: %s", tostring(reason)))

	for _, player in ipairs({p1, p2}) do
		if isValidPlayer(player) then
			setInMatch(player, false)
			setControllable(player, true)
			safeFireClient(player, "Lobby", { Reason = reason })
		end
	end

	clearMatchReferences(p1, p2, arenaName)

	-- If one player reached the arena before the other failed, return them safely.
	for _, player in ipairs({p1, p2}) do
		if isValidPlayer(player) then
			task.spawn(function()
				teleportPlayer(player, LobbySpawn)
			end)
		end
	end
end

function MatchManager.SetMatchMetadata(p1, p2, matchId, ranked)
	local metadata = { MatchId = matchId, Ranked = ranked == true }
	matchMetadata[p1] = metadata
	matchMetadata[p2] = metadata
end

function MatchManager.GetMatchMetadata(player)
	return matchMetadata[player]
end

function MatchManager.GetMatchEndedSignal()
	return MatchEndedSignal.Event
end

function MatchManager.StartMatch(p1, p2, arenaName, forceOvertime)
	if not isValidPlayer(p1) or not isValidPlayer(p2) or p1 == p2 then return false end
	if MatchManager.IsPlayerInMatch(p1) or MatchManager.IsPlayerInMatch(p2) then return false end

	-- Do not reserve an arena until both rigs are actually ready. Slow mobile joins
	-- and respawns can otherwise produce a real match whose character stays in Lobby.
	if not getReadyCharacter(p1, CHARACTER_READY_TIMEOUT) or not getReadyCharacter(p2, CHARACTER_READY_TIMEOUT) then
		return false
	end

	local arena = arenaName and ArenasFolder:FindFirstChild(arenaName)
	if not arena then
		local fallback = chooseRandomAvailableArena()
		if fallback then arena = ArenasFolder:FindFirstChild(fallback) end
	end
	if not arena or arenaLocks[arena.Name] then return false end

	local s1 = findSpawn(arena, "ArenaSpawn1")
	local s2 = findSpawn(arena, "ArenaSpawn2")
	if not s1 or not s2 then
		warn("[MatchManager] Arena is missing ArenaSpawn1/ArenaSpawn2: " .. arena:GetFullName())
		return false
	end

	arenaLocks[arena.Name] = true
	activeMatches[p1] = p2
	activeMatches[p2] = p1
	matchArenaByPlayer[p1] = arena.Name
	matchArenaByPlayer[p2] = arena.Name
	setInMatch(p1, true)
	setInMatch(p2, true)

	-- Freeze first so client movement/thumbstick scripts cannot race the server teleport.
	setControllable(p1, false)
	setControllable(p2, false)
	setMatchState(p1, p2, "LoadingArena", { ArenaName = arena.Name })

	local p1Placed = teleportPlayer(p1, s1)
	local p2Placed = teleportPlayer(p2, s2)
	if not p1Placed or not p2Placed then
		abortMatchStart(p1, p2, arena.Name, "ArenaTeleportFailed")
		return false
	end

	DamageHandler.InitializePlayerHealth(p1)
	DamageHandler.InitializePlayerHealth(p2)

	task.wait(0.75)

	-- Verify again after replication has had time to settle. This catches a client
	-- controller snapping a player back or a character being replaced mid-transition.
	if not ensureAtSpawn(p1, s1) or not ensureAtSpawn(p2, s2) then
		abortMatchStart(p1, p2, arena.Name, "ArenaPlacementLost")
		return false
	end

	setMatchState(p1, p2, "BattleIntro", {
		p1 = { Name = p1.Name, UserId = p1.UserId },
		p2 = { Name = p2.Name, UserId = p2.UserId },
	})

	task.wait(4)
	if not isValidPlayer(p1) or not isValidPlayer(p2) then
		abortMatchStart(p1, p2, arena.Name, "PlayerLeftDuringIntro")
		return false
	end

	setMatchState(p1, p2, "Countdown")
	task.wait(3.5)

	if not isValidPlayer(p1) or not isValidPlayer(p2) then
		abortMatchStart(p1, p2, arena.Name, "PlayerLeftDuringCountdown")
		return false
	end

	-- Last guard before enabling damage/movement: a fight must never start in Lobby.
	if not ensureAtSpawn(p1, s1) or not ensureAtSpawn(p2, s2) then
		abortMatchStart(p1, p2, arena.Name, "ArenaPlacementLostBeforeFight")
		return false
	end

	setMatchState(p1, p2, "Fighting", {
		MatchDuration = MATCH_DURATION,
		OpponentName = p2.Name,
		OpponentUserId = p2.UserId,
		OpponentStreak = WinstreakData.Get(p2),
		PlayerStreak = WinstreakData.Get(p1),
	})
	setControllable(p1, true)
	setControllable(p2, true)

	local matchFinished = false
	local matchStartTime = os.clock()
	if forceOvertime then matchStartTime -= MATCH_DURATION end
	local lastTimerSent = -math.huge
	local lastH1, lastH2 = nil, nil

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if matchFinished then
			connection:Disconnect()
			return
		end

		if not isValidPlayer(p1) or not isValidPlayer(p2) then
			matchFinished = true
			connection:Disconnect()
			MatchManager.EndMatch(p1, p2, isValidPlayer(p1) and p1 or (isValidPlayer(p2) and p2 or nil), arena.Name)
			return
		end

		local h1 = DamageHandler.GetPlayerHealth(p1)
		local h2 = DamageHandler.GetPlayerHealth(p2)

		if h1 ~= lastH1 or h2 ~= lastH2 then
			lastH1, lastH2 = h1, h2
			safeFireClient(p1, "UpdateHealth", { Health = h1, OpponentHealth = h2 })
			safeFireClient(p2, "UpdateHealth", { Health = h2, OpponentHealth = h1 })
		end

		if h1 <= 0 or h2 <= 0 then
			matchFinished = true
			connection:Disconnect()
			local winner
			if h1 <= 0 and h2 <= 0 then
				winner = nil
			else
				winner = h1 <= 0 and p2 or p1
			end
			MatchManager.Sequence_FinalHit(p1, p2, winner, arena.Name)
			return
		end

		local now = os.clock()
		local remaining = math.max(0, MATCH_DURATION - (now - matchStartTime))
		if now - lastTimerSent >= TIMER_UPDATE_INTERVAL then
			lastTimerSent = now
			safeFireClient(p1, "UpdateTimer", { Time = remaining })
			safeFireClient(p2, "UpdateTimer", { Time = remaining })
		end

		if remaining <= 0 then
			matchFinished = true
			connection:Disconnect()
			local winner = h1 == h2 and nil or (h1 > h2 and p1 or p2)
			MatchManager.EndMatch(p1, p2, winner, arena.Name)
		end
	end)

	return true
end

function MatchManager.Sequence_FinalHit(p1, p2, winner, arenaName)
	MatchManager.EndMatch(p1, p2, winner, arenaName)
end

function MatchManager.EndMatch(p1, p2, winner, arenaName)
	if endingMatches[p1] or endingMatches[p2] then return end
	endingMatches[p1] = true
	endingMatches[p2] = true

	arenaName = arenaName or matchArenaByPlayer[p1] or matchArenaByPlayer[p2]

	if winner and isValidPlayer(winner) then
		WinstreakData.Increment(winner, 1)
		local loser = winner == p1 and p2 or p1
		if isValidPlayer(loser) then WinstreakData.Reset(loser) end
	end

	local metadata = matchMetadata[p1] or matchMetadata[p2]
	setMatchState(p1, p2, "MatchEnded", {
		WinnerUserId = winner and winner.UserId or nil,
		WinnerName = winner and winner.Name or nil,
		MatchId = metadata and metadata.MatchId or nil,
		Ranked = metadata and metadata.Ranked or false,
	})
	MatchEndedSignal:Fire(p1, p2, winner, metadata)

	setInMatch(p1, false)
	setInMatch(p2, false)
	if isValidPlayer(p1) then setControllable(p1, true) end
	if isValidPlayer(p2) then setControllable(p2, true) end

	activeMatches[p1] = nil
	activeMatches[p2] = nil
	matchMetadata[p1] = nil
	matchMetadata[p2] = nil
	matchArenaByPlayer[p1] = nil
	matchArenaByPlayer[p2] = nil
	if p1 then playerStates[p1] = "Lobby" end
	if p2 then playerStates[p2] = "Lobby" end
	if arenaName then arenaLocks[arenaName] = false end
	DamageHandler.RemovePlayer(p1)
	DamageHandler.RemovePlayer(p2)

	task.delay(3, function()
		if isValidPlayer(p1) then teleportPlayer(p1, LobbySpawn) end
		if isValidPlayer(p2) then teleportPlayer(p2, LobbySpawn) end
		endingMatches[p1] = nil
		endingMatches[p2] = nil
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local opponent = activeMatches[player]
	if opponent then
		MatchManager.EndMatch(player, opponent, isValidPlayer(opponent) and opponent or nil, matchArenaByPlayer[player])
	end

	activeMatches[player] = nil
	matchMetadata[player] = nil
	matchArenaByPlayer[player] = nil
	playerStates[player] = nil
	endingMatches[player] = nil
	votingSessions[player] = nil
end)

_G.GetOpponent = function(player)
	return MatchManager.GetOpponent(player)
end

return MatchManager
