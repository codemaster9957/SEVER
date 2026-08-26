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

local activeMatches = {} -- [Player] = opponent
local playerStates = {} -- [Player] = StateName
local endingMatches = {} -- prevents match ending twice
local arenaLocks = {} -- [ArenaName] = boolean (true if occupied)
local votingSessions = {} -- [Player] = matchId
local matchVotes = {} -- [matchId] = {[Player] = arenaName}
local matchMetadata = {} -- [Player] = {MatchId = string, Ranked = boolean}
local MatchEndedSignal = Instance.new("BindableEvent")
local arenaRandom = Random.new()

local function isValidPlayer(player)
	return player and player.Parent == Players
end

local ALL_ARENAS = {"Arena1", "Arena2", "Arena3", "Arena4", "Arena5"}
local MAP_VOTE_TIMEOUT = 10
local MATCH_DURATION = 90

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
	if #available == 0 then
		return nil
	end

	return available[arenaRandom:NextInteger(1, #available)]
end

function MatchManager.StartMapVote(p1, p2)
	if not isValidPlayer(p1) then
		return false
	end

	if typeof(p2) == "Instance" and not isValidPlayer(p2) then
		return false
	end

	local arenaName = chooseRandomAvailableArena()
	if not arenaName then
		return false
	end

	if typeof(p2) == "table" and p2.IsDummy then
		local result = _G.StartDummyBattle(p1, arenaName)
		return result ~= false
	end

	MatchManager.StartMatch(p1, p2, arenaName)
	return true
end

function MatchManager.GetAvailableArena()
	return chooseRandomAvailableArena()
end

function MatchManager.UnlockArena(arenaName)
	arenaLocks[arenaName] = false
end

function MatchManager.LockArena(arenaName)
	if arenaLocks[arenaName] then
		return false
	end

	arenaLocks[arenaName] = true
	return true
end

function MatchManager.IsPlayerInMatch(player)
	return playerStates[player] == "InMatch"
end

function MatchManager.SetPlayerState(player, state)
	playerStates[player] = state
end

function MatchManager.CanUseCombat(player)
	return isValidPlayer(player)
		and playerStates[player] == "InMatch"
		and player.Character
		and player.Character:GetAttribute("InMatch") == true
end

function MatchManager.GetOpponent(player)
	return activeMatches[player]
end

-- Finds a spawn part by prefix
local function findSpawn(arena, spawnName)
	for _, child in ipairs(arena:GetChildren()) do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #spawnName) == spawnName then
			return child
		end
	end

	return nil
end

local function safeFireClient(player, state, data)
	if isValidPlayer(player) then
		GameStateUpdate:FireClient(player, state, data)
	end
end

local function setMatchState(p1, p2, state, data)
	if isValidPlayer(p1) then
		playerStates[p1] = state
		safeFireClient(p1, state, data)
	end

	if isValidPlayer(p2) then
		playerStates[p2] = state
		safeFireClient(p2, state, data)
	end
end

local function teleportPlayer(player, spawnPart)
	if not isValidPlayer(player) or not spawnPart then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	end

	if humanoidRootPart then
		local topOffset = spawnPart.Size.Y / 2 + 3
		local targetCFrame = spawnPart.CFrame + Vector3.new(0, topOffset, 0)
		character:PivotTo(targetCFrame)

		if character:GetAttribute("InMatch") then
			character:SetAttribute("ArenaZ", spawnPart.Position.Z)
		else
			character:SetAttribute("ArenaZ", nil)
		end
	end
end

local function setInMatch(player, status)
	if not isValidPlayer(player) then
		return
	end

	local character = player.Character
	if character then
		character:SetAttribute("InMatch", status)
		if not status then
			character:SetAttribute("ArenaZ", nil)
		end
	end
end

-- Controls player movement and combat ability
local function setControllable(player, controllable)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = controllable and 16 or 0
		humanoid.JumpPower = controllable and 50 or 0
	end

	character:SetAttribute("CanAttack", controllable)
	character:SetAttribute("CanBlock", controllable)
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
	if not isValidPlayer(p1) or not isValidPlayer(p2) then
		return
	end

	if p1 == p2 then
		return
	end

	if playerStates[p1] == "InMatch" or playerStates[p2] == "InMatch" then
		return
	end

	local arena
	if arenaName then
		arena = ArenasFolder:FindFirstChild(arenaName)
	end

	if not arena then
		local fallbackArenaName = chooseRandomAvailableArena()
		if fallbackArenaName then
			arena = ArenasFolder:FindFirstChild(fallbackArenaName)
		end
	end

	if not arena then
		return
	end

	if arenaLocks[arena.Name] then
		return
	end

	arenaLocks[arena.Name] = true
	activeMatches[p1] = p2
	activeMatches[p2] = p1

	DamageHandler.InitializePlayerHealth(p1)
	DamageHandler.InitializePlayerHealth(p2)
	setInMatch(p1, true)
	setInMatch(p2, true)

	setMatchState(p1, p2, "LoadingArena", { ArenaName = arena.Name })

	local s1 = findSpawn(arena, "ArenaSpawn1")
	local s2 = findSpawn(arena, "ArenaSpawn2")
	teleportPlayer(p1, s1)
	teleportPlayer(p2, s2)

	task.wait(1)

	setMatchState(p1, p2, "BattleIntro", {
		p1 = { Name = p1.Name, UserId = p1.UserId },
		p2 = { Name = p2.Name, UserId = p2.UserId },
	})

	setControllable(p1, false)
	setControllable(p2, false)

	task.wait(4)

	setMatchState(p1, p2, "Countdown")
	task.wait(3.5)

	setMatchState(p1, p2, "Fighting", {
		MatchDuration = MATCH_DURATION,
		OpponentName = p2.Name,
		OpponentUserId = p2.UserId,
		OpponentStreak = WinstreakData.GetStreak(p2),
		PlayerStreak = WinstreakData.GetStreak(p1),
	})

	setControllable(p1, true)
	setControllable(p2, true)

	local matchFinished = false
	local matchStartTime = os.clock()
	if forceOvertime then
		matchStartTime -= MATCH_DURATION
	end

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if matchFinished then
			connection:Disconnect()
			return
		end

		if not isValidPlayer(p1) or not isValidPlayer(p2) then
			matchFinished = true
			MatchManager.EndMatch(p1, p2, nil, arena.Name)
			return
		end

		local h1 = DamageHandler.GetPlayerHealth(p1)
		local h2 = DamageHandler.GetPlayerHealth(p2)

		safeFireClient(p1, "UpdateHealth", { Health = h1, OpponentHealth = h2 })
		safeFireClient(p2, "UpdateHealth", { Health = h2, OpponentHealth = h1 })

		if h1 <= 0 or h2 <= 0 then
			matchFinished = true
			connection:Disconnect()
			local winner = h1 <= 0 and p2 or p1
			MatchManager.Sequence_FinalHit(p1, p2, winner, arena.Name)
			return
		end

		local elapsed = os.clock() - matchStartTime
		local remaining = math.max(0, MATCH_DURATION - elapsed)
		safeFireClient(p1, "UpdateTimer", { Time = remaining })
		safeFireClient(p2, "UpdateTimer", { Time = remaining })

		if remaining <= 0 and not matchFinished then
			matchFinished = true
			connection:Disconnect()

			if h1 == h2 then
				MatchManager.EndMatch(p1, p2, nil, arena.Name)
			else
				local winner = h1 > h2 and p1 or p2
				MatchManager.EndMatch(p1, p2, winner, arena.Name)
			end
		end
	end)
end

function MatchManager.Sequence_FinalHit(p1, p2, winner, arenaName)
	MatchManager.EndMatch(p1, p2, winner, arenaName)
end

function MatchManager.EndMatch(p1, p2, winner, arenaName)
	if endingMatches[p1] or endingMatches[p2] then
		return
	end

	endingMatches[p1] = true
	endingMatches[p2] = true

	if winner and isValidPlayer(winner) then
		WinstreakData.Increment(winner, 1)
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
	setControllable(p1, true)
	setControllable(p2, true)

	activeMatches[p1] = nil
	activeMatches[p2] = nil
	matchMetadata[p1] = nil
	matchMetadata[p2] = nil
	playerStates[p1] = "Lobby"
	playerStates[p2] = "Lobby"
	arenaLocks[arenaName] = false

	task.delay(3, function()
		teleportPlayer(p1, LobbySpawn)
		teleportPlayer(p2, LobbySpawn)
		endingMatches[p1] = nil
		endingMatches[p2] = nil
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local opponent = activeMatches[player]
	if opponent then
		MatchManager.EndMatch(player, opponent, opponent, nil)
	end

	activeMatches[player] = nil
	matchMetadata[player] = nil
	playerStates[player] = nil
	endingMatches[player] = nil
	votingSessions[player] = nil
end)

_G.GetOpponent = function(player)
	return MatchManager.GetOpponent(player)
end

return MatchManager
