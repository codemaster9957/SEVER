local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate")
local MatchFinishRemote = MatchEvents:WaitForChild("MatchFinishRemote")
local TrainingControls = MatchEvents:WaitForChild("TrainingDummyControls")
local SetInfiniteHealthRemote = TrainingControls:WaitForChild("SetInfiniteHealth")
local RespawnDummyRemote = TrainingControls:WaitForChild("RespawnDummy")
local ReturnToLobbyRemote = TrainingControls:WaitForChild("ReturnToLobby")

local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))

local ArenasFolder = workspace:WaitForChild("Arenas")
local TrainingDummy = workspace:WaitForChild("training")

local MATCH_DURATION = 90
local RESULT_DISPLAY_TIME = 1.5

-- [Player] = battleData
local activeDummyBattles = {}

local function isValidPlayer(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function safeDisconnect(connection)
	if connection and connection.Connected then
		connection:Disconnect()
	end
end

local function safeFireClient(player, state, data)
	if isValidPlayer(player) then
		GameStateUpdate:FireClient(player, state, data)
	end
end

local function safeMatchManagerCall(methodName, ...)
	local method = MatchManager[methodName]
	if type(method) ~= "function" then
		warn(string.format("[DummyBattleServer] MatchManager.%s does not exist", methodName))
		return false, nil
	end

	local success, result = pcall(method, ...)
	if not success then
		warn(string.format("[DummyBattleServer] MatchManager.%s failed: %s", methodName, tostring(result)))
		return false, nil
	end

	return true, result
end

-- Searches recursively so arena spawns may be inside folders or models.
local function findSpawn(arena, spawnName)
	for _, descendant in ipairs(arena:GetDescendants()) do
		if descendant:IsA("BasePart")
			and string.sub(descendant.Name, 1, #spawnName) == spawnName then
			return descendant
		end
	end

	return nil
end

local function resolveArena(arenaReference)
	if typeof(arenaReference) == "Instance" then
		if arenaReference:IsDescendantOf(ArenasFolder) or arenaReference.Parent == ArenasFolder then
			return arenaReference
		end
		return nil
	end

	if type(arenaReference) == "string" and arenaReference ~= "" then
		return ArenasFolder:FindFirstChild(arenaReference)
	end

	local success, availableArena = safeMatchManagerCall("GetAvailableArena")
	if not success then
		return nil
	end

	if typeof(availableArena) == "Instance" then
		return availableArena
	end

	if type(availableArena) == "string" then
		return ArenasFolder:FindFirstChild(availableArena)
	end

	return nil
end

local function setInMatch(player, status, arenaZ)
	if not isValidPlayer(player) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	character:SetAttribute("InMatch", status == true)

	if status then
		character:SetAttribute("ArenaZ", arenaZ)
	else
		character:SetAttribute("ArenaZ", nil)
	end
end

local function setDuelPromptEnabled(player, enabled)
	if not isValidPlayer(player) then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChild("DuelChallengePrompt")

	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
end

local function stopDummy(dummyClone)
	if not dummyClone or not dummyClone.Parent then
		return
	end

	dummyClone:SetAttribute("InMatch", false)

	local humanoid = dummyClone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	end
end

local function destroyBattleDummy(battle)
	if battle.dummyClone and battle.dummyClone.Parent then
		battle.dummyClone:Destroy()
	end
	battle.dummyClone = nil
end

local function disconnectBattleConnections(battle)
	safeDisconnect(battle.heartbeatConn)
	safeDisconnect(battle.dummyDiedConn)
	safeDisconnect(battle.playerDiedConn)
	safeDisconnect(battle.characterRemovingConn)

	battle.heartbeatConn = nil
	battle.dummyDiedConn = nil
	battle.playerDiedConn = nil
	battle.characterRemovingConn = nil
end

local function unlockBattleArena(battle)
	if not battle.arenaLocked or not battle.arenaName then
		return
	end

	battle.arenaLocked = false
	safeMatchManagerCall("UnlockArena", battle.arenaName)
end

local function fireBattleResult(player, winnerIsPlayer)
	if not isValidPlayer(player) then
		return
	end

	if winnerIsPlayer == true then
		MatchFinishRemote:FireClient(player, {
			Winner = player.Name,
			Loser = "Training Dummy",
			IsDraw = false,
		})

		-- Dummy battles are private, so do not broadcast this to every server player.
		CombatJuice.EmitTo(player, "Victory", {
			winner = player.Name,
			loser = "Training Dummy",
		})
	elseif winnerIsPlayer == false then
		MatchFinishRemote:FireClient(player, {
			Winner = "Training Dummy",
			Loser = player.Name,
			IsDraw = false,
		})

		CombatJuice.EmitTo(player, "Victory", {
			winner = "Training Dummy",
			loser = player.Name,
		})
	else
		MatchFinishRemote:FireClient(player, {
			Winner = "Draw",
			Loser = "Draw",
			IsDraw = true,
		})

		CombatJuice.EmitTo(player, "Draw", {})
	end
end

local function endDummyBattle(player, battle, winnerIsPlayer)
	if battle.finished then
		return
	end

	battle.finished = true

	if activeDummyBattles[player] == battle then
		activeDummyBattles[player] = nil
	end

	disconnectBattleConnections(battle)
	stopDummy(battle.dummyClone)

	-- Stop the player being treated as an active combatant immediately.
	-- Do not call DamageHandler.SetMatchOver() here because its state is global
	-- in the current DamageHandler and would stop unrelated arena matches too.
	if isValidPlayer(player) then
		setInMatch(player, false)
		setDuelPromptEnabled(player, false)
	end

	fireBattleResult(player, winnerIsPlayer)
	task.wait(RESULT_DISPLAY_TIME)

	destroyBattleDummy(battle)
	unlockBattleArena(battle)

	if isValidPlayer(player) then
		safeMatchManagerCall("SetPlayerState", player, "Lobby")
		safeFireClient(player, "ReturningToLobby")
		task.wait(1)
		safeFireClient(player, "Lobby")
		local reloadSuccess, reloadError = pcall(function()
			player:LoadCharacterAsync()
		end)

		if not reloadSuccess and isValidPlayer(player) then
			warn("[DummyBattleServer] Failed to reload " .. player.Name .. ": " .. tostring(reloadError))
		end
	end
end

local function startDummyBattle(player, arenaReference)
	if not isValidPlayer(player) then
		warn("[DummyBattleServer] Tried to start a dummy battle for an invalid player")
		return false
	end

	if activeDummyBattles[player] then
		warn("[DummyBattleServer] " .. player.Name .. " is already in a dummy battle")
		return false
	end

	local success, isAlreadyInMatch = safeMatchManagerCall("IsPlayerInMatch", player)
	if not success or isAlreadyInMatch then
		return false
	end

	local character = player.Character
	local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")

	if not character or not playerHumanoid or not playerRoot or playerHumanoid.Health <= 0 then
		warn("[DummyBattleServer] " .. player.Name .. " has no usable character")
		return false
	end

	if character:GetAttribute("InMatch") then
		warn("[DummyBattleServer] " .. player.Name .. " already has InMatch enabled")
		return false
	end

	local arena = resolveArena(arenaReference)
	if not arena then
		warn("[DummyBattleServer] No available arena was found")
		return false
	end

	local spawn1 = findSpawn(arena, "ArenaSpawn1")
	local spawn2 = findSpawn(arena, "ArenaSpawn2")

	if not spawn1 or not spawn2 then
		warn(string.format(
			"[DummyBattleServer] Arena %s is missing ArenaSpawn1 or ArenaSpawn2",
			arena.Name
			))
		return false
	end

	-- Build and validate the clone before locking the arena.
	local cloneSuccess, dummyClone = pcall(function()
		return TrainingDummy:Clone()
	end)

	if not cloneSuccess or not dummyClone then
		warn("[DummyBattleServer] Could not clone the training dummy")
		return false
	end

	dummyClone.Name = "Training Dummy"
	dummyClone:SetAttribute("IsTrainingDummy", true)
	dummyClone:SetAttribute("InMatch", true)
	dummyClone:SetAttribute("ArenaZ", spawn2.Position.Z)

	local dummyHumanoid = dummyClone:FindFirstChildOfClass("Humanoid")
	local dummyRoot = dummyClone:FindFirstChild("HumanoidRootPart")

	if not dummyHumanoid or not dummyRoot then
		dummyClone:Destroy()
		warn("[DummyBattleServer] The training dummy needs a Humanoid and HumanoidRootPart")
		return false
	end

	-- Remove cloned prompts. The arena dummy should not start another vote.
	for _, descendant in ipairs(dummyClone:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end

	-- A LocalScript named Animate cannot run for a server-created NPC.
	local animate = dummyClone:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate:Destroy()
	end

	-- Remove the lobby idle animation loop so the battle clone doesn't play it.
	local idleAnimLoop = dummyClone:FindFirstChild("IdleAnimLoop")
	if idleAnimLoop and idleAnimLoop:IsA("Script") then
		idleAnimLoop:Destroy()
	end

	dummyHumanoid.MaxHealth = 100
	dummyHumanoid.Health = 100
	dummyHumanoid.WalkSpeed = 16
	dummyHumanoid.JumpPower = 50
	dummyHumanoid.AutoRotate = true
	dummyClone.PrimaryPart = dummyRoot

	local lockSuccess, lockResult = safeMatchManagerCall("LockArena", arena.Name)
	if not lockSuccess or lockResult == false then
		dummyClone:Destroy()
		warn("[DummyBattleServer] Could not lock arena " .. arena.Name)
		return false
	end

	local battle = {
		arenaName = arena.Name,
		arenaLocked = true,
		dummyClone = dummyClone,
		dummyHumanoid = dummyHumanoid,
		finished = false,
		infiniteHealth = false,
		spawn1 = spawn1,
		spawn2 = spawn2,
		heartbeatConn = nil,
		dummyDiedConn = nil,
		playerDiedConn = nil,
		characterRemovingConn = nil,
		matchStartTime = os.clock(),
		lastTimerSent = 0,
	}

	-- IMPORTANT: reserve the battle before connecting events or starting Heartbeat.
	-- Otherwise an immediate death can call endDummyBattle before this table exists.
	activeDummyBattles[player] = battle

	safeMatchManagerCall("SetPlayerState", player, "InMatch")
	setInMatch(player, true, spawn1.Position.Z)
	setDuelPromptEnabled(player, false)

	DamageHandler.InitializePlayerHealth(player)
	playerHumanoid.Health = playerHumanoid.MaxHealth

	dummyClone.Parent = workspace

	-- Keep NPC physics authoritative on the server.
	for _, descendant in ipairs(dummyClone:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end

	local playerTarget = spawn1.CFrame + Vector3.new(0, spawn1.Size.Y / 2 + 3, 0)
	local dummyTarget = spawn2.CFrame + Vector3.new(0, spawn2.Size.Y / 2 + 3, 0)

	character:PivotTo(playerTarget)
	dummyClone:PivotTo(dummyTarget)

	local function endBattle(winnerIsPlayer)
		if battle.finished then
			return
		end

		endDummyBattle(player, battle, winnerIsPlayer)
	end

	battle.dummyDiedConn = dummyHumanoid.Died:Connect(function()
		endBattle(true)
	end)

	battle.playerDiedConn = playerHumanoid.Died:Connect(function()
		endBattle(false)
	end)

	battle.characterRemovingConn = player.CharacterRemoving:Connect(function(removingCharacter)
		if removingCharacter == character then
			endBattle(false)
		end
	end)

	battle.heartbeatConn = RunService.Heartbeat:Connect(function()
		if battle.finished then
			return
		end

		if not isValidPlayer(player) then
			endBattle(nil)
			return
		end

		if player.Character ~= character or not character.Parent then
			endBattle(false)
			return
		end

		if not dummyClone.Parent or not dummyHumanoid.Parent then
			endBattle(true)
			return
		end

		local playerHealth = DamageHandler.GetPlayerHealth(player)
		if type(playerHealth) ~= "number" then
			playerHealth = 0
		end

		if battle.infiniteHealth then
			DamageHandler.SetPlayerHealth(player, 100)
			playerHealth = 100
		end

		local dummyHealth = math.max(0, dummyHumanoid.Health)
		local intensity = math.clamp((200 - playerHealth - dummyHealth) / 150, 0, 1)

		safeFireClient(player, "UpdateHealth", {
			Health = playerHealth,
			OpponentHealth = dummyHealth,
		})

		CombatJuice.EmitTo(player, "MusicIntensity", {
			intensity = intensity,
		})

		if playerHealth <= 0 then
			endBattle(false)
			return
		end

		if dummyHealth <= 0 then
			endBattle(true)
			return
		end

		local now = os.clock()
		local elapsed = now - battle.matchStartTime
		local remaining = math.max(0, MATCH_DURATION - elapsed)

		if now - battle.lastTimerSent >= 0.1 then
			battle.lastTimerSent = now
			safeFireClient(player, "UpdateTimer", {
				Time = remaining,
			})
		end

		if remaining <= 0 then
			if playerHealth > dummyHealth then
				endBattle(true)
			elseif dummyHealth > playerHealth then
				endBattle(false)
			else
				endBattle(nil)
			end
		end
	end)

	safeFireClient(player, "InMatch", {
		OpponentName = "Training Dummy",
		OpponentUserId = 0,
		PlayerUserId = player.UserId,
		ArenaName = arena.Name,
		MatchDuration = MATCH_DURATION,
	})

	-- Battle intro sequence (plays intro music via MatchAudioManager).
	safeFireClient(player, "BattleIntro", {
		p1 = {Name = player.Name, UserId = player.UserId},
		p2 = {Name = "Training Dummy", UserId = 0},
	})

	task.wait(2.5)

	safeFireClient(player, "Fighting", {
		OpponentName = "Training Dummy",
		OpponentUserId = 0,
		MatchDuration = MATCH_DURATION,
	})

	CombatJuice.EmitTo(player, "Intro", {
		name = player.Name,
		opponent = "Training Dummy",
		rank = "Unranked",
		winStreak = 0,
		scythe = "Reaper",
	})

	print(string.format(
		"[DummyBattleServer] Started %s vs Training Dummy in %s",
		player.Name,
		arena.Name
		))

	return true
end

-- MatchManager assigns the first available arena directly.
_G.StartDummyBattle = startDummyBattle
_G.GetActiveDummyBattle = function(player)
	local battle = activeDummyBattles[player]
	if not battle or battle.finished then
		return nil
	end
	return battle
end
_G.EndDummyBattle = function(player)
	local battle = activeDummyBattles[player]
	if not battle or battle.finished then
		return false
	end
	endDummyBattle(player, battle, nil)
	return true
end

local function setupDummyPrompt()
	local root = TrainingDummy:FindFirstChild("HumanoidRootPart")
	if not root then
		warn("[DummyBattleServer] Training dummy has no HumanoidRootPart")
		return
	end

	local oldPrompt = root:FindFirstChild("DummyChallengePrompt")
	if oldPrompt then
		oldPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DummyChallengePrompt"
	prompt.ActionText = "Practice Combat"
	prompt.ObjectText = "Training Dummy"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 15
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 40)
	prompt.Parent = root

	prompt.Triggered:Connect(function(player)
		if not isValidPlayer(player) then
			return
		end

		if activeDummyBattles[player] then
			return
		end

		local checkSuccess, isInMatch = safeMatchManagerCall("IsPlayerInMatch", player)
		if not checkSuccess or isInMatch then
			return
		end

		local character = player.Character
		if not character or character:GetAttribute("InMatch") then
			return
		end

		local voteSuccess = safeMatchManagerCall("StartMapVote", player, {
			Name = "Training Dummy",
			UserId = 0,
			IsDummy = true,
		})

		if not voteSuccess then
			warn("[DummyBattleServer] Could not start the dummy map vote for " .. player.Name)
		end
	end)
end

setupDummyPrompt()

local function getActiveBattle(player)
	local battle = activeDummyBattles[player]
	if not battle or battle.finished then
		return nil
	end
	return battle
end

SetInfiniteHealthRemote.OnServerEvent:Connect(function(player, enabled)
	if not isValidPlayer(player) then
		return
	end

	local battle = getActiveBattle(player)
	if not battle then
		return
	end

	battle.infiniteHealth = enabled == true

	if battle.infiniteHealth then
		DamageHandler.SetPlayerHealth(player, 100)
	end

	safeFireClient(player, "TrainingControlsSync", {
		InfiniteHealth = battle.infiniteHealth,
	})
end)

RespawnDummyRemote.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then
		return
	end

	local battle = getActiveBattle(player)
	if not battle then
		return
	end

	local dummyClone = battle.dummyClone
	local dummyHumanoid = battle.dummyHumanoid
	local spawn2 = battle.spawn2

	if not dummyClone or not dummyClone.Parent or not dummyHumanoid or not dummyHumanoid.Parent or not spawn2 then
		return
	end

	if dummyHumanoid.Health <= 0 then
		return
	end

	dummyHumanoid.Health = dummyHumanoid.MaxHealth
	dummyClone:PivotTo(spawn2.CFrame + Vector3.new(0, spawn2.Size.Y / 2 + 3, 0))

	local root = dummyClone:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
end)

ReturnToLobbyRemote.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then
		return
	end

	local battle = getActiveBattle(player)
	if not battle then
		return
	end

	endDummyBattle(player, battle, nil)
end)

Players.PlayerRemoving:Connect(function(player)
	local battle = activeDummyBattles[player]
	if not battle then
		return
	end

	battle.finished = true
	activeDummyBattles[player] = nil

	disconnectBattleConnections(battle)
	destroyBattleDummy(battle)
	unlockBattleArena(battle)
end)