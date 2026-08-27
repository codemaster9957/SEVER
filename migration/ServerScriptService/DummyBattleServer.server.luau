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
local SetDummyLevelRemote = TrainingControls:WaitForChild("SetDummyLevel")

local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
local DataService = require(ServerScriptService:WaitForChild("DataService"))
local TrainingDummyAI = require(ServerScriptService:WaitForChild("TrainingDummyAI"))
local TrainingDummyCombatAI = require(ServerScriptService:WaitForChild("TrainingDummyCombatAI"))

local ArenasFolder = workspace:WaitForChild("Arenas")
local TrainingDummy = workspace:WaitForChild("training")

local RESULT_DISPLAY_TIME = 1.5
local HUD_UPDATE_INTERVAL = 0.1
-- Older hidden HUD code still expects a positive duration. The server never counts
-- this down; the training UI enhancer hides the clock completely.
local TRAINING_COMPAT_DURATION = 86400

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

local function getTrainingProfile(player)
	local profile = DataService.GetProfile(player)
	local level = 1
	local memory = TrainingDummyAI.ReconcileMemory(nil)

	if profile then
		level = TrainingDummyAI.ClampLevel(profile.TrainingDummyLevel or 1)
		memory = TrainingDummyAI.ReconcileMemory(profile.TrainingAIMemory)
		profile.TrainingDummyLevel = level
		profile.TrainingAIMemory = memory
	end

	return profile, level, memory
end

local function savePreferredLevel(player, level)
	DataService.UpdateProfile(player, function(profile)
		profile.TrainingDummyLevel = TrainingDummyAI.ClampLevel(level)
	end)
end

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
	if not success then return nil end
	if typeof(availableArena) == "Instance" then return availableArena end
	if type(availableArena) == "string" then return ArenasFolder:FindFirstChild(availableArena) end
	return nil
end

local function setInMatch(player, status, arenaZ)
	if not isValidPlayer(player) then return end
	local character = player.Character
	if not character then return end
	character:SetAttribute("InMatch", status == true)
	if status then
		character:SetAttribute("ArenaZ", arenaZ)
	else
		character:SetAttribute("ArenaZ", nil)
	end
end

local function setDuelPromptEnabled(player, enabled)
	if not isValidPlayer(player) then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local prompt = root and root:FindFirstChild("DuelChallengePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
end

local function stopDummy(dummyClone)
	if not dummyClone or not dummyClone.Parent then return end
	dummyClone:SetAttribute("InMatch", false)
	dummyClone:SetAttribute("AttackActiveUntil", 0)
	dummyClone:SetAttribute("IsBlocking", false)
	dummyClone:SetAttribute("IsParrying", false)
	local humanoid = dummyClone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
		humanoid:Move(Vector3.zero, false)
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
	if battle.aiController then
		battle.aiController:Destroy()
		battle.aiController = nil
	end
end

local function unlockBattleArena(battle)
	if not battle.arenaLocked or not battle.arenaName then return end
	battle.arenaLocked = false
	safeMatchManagerCall("UnlockArena", battle.arenaName)
end

local function fireBattleResult(player, winnerIsPlayer)
	if not isValidPlayer(player) then return end

	if winnerIsPlayer == true then
		MatchFinishRemote:FireClient(player, {
			Winner = player.Name,
			Loser = "Training Dummy",
			IsDraw = false,
		})
		CombatJuice.EmitTo(player, "Victory", {winner = player.Name, loser = "Training Dummy"})
	elseif winnerIsPlayer == false then
		MatchFinishRemote:FireClient(player, {
			Winner = "Training Dummy",
			Loser = player.Name,
			IsDraw = false,
		})
		CombatJuice.EmitTo(player, "Victory", {winner = "Training Dummy", loser = player.Name})
	else
		MatchFinishRemote:FireClient(player, {Winner = "Draw", Loser = "Draw", IsDraw = true})
		CombatJuice.EmitTo(player, "Draw", {})
	end
end

local function endDummyBattle(player, battle, winnerIsPlayer)
	if battle.finished then return end
	battle.finished = true

	if battle.dummyLevel == 10 and battle.aiMemory and winnerIsPlayer ~= nil then
		-- This is intentionally never sent to the client. Level 10 learns silently.
		TrainingDummyAI.RecordRoundResult(battle.aiMemory, winnerIsPlayer == true)
	end

	if isValidPlayer(player) and DataService.IsPersistent(player) then
		-- Save when a training session ends so Level 10's learning and the chosen
		-- difficulty survive a rejoin even if the normal autosave has not run yet.
		task.spawn(DataService.SaveProfile, player)
	end

	if activeDummyBattles[player] == battle then
		activeDummyBattles[player] = nil
	end

	disconnectBattleConnections(battle)
	stopDummy(battle.dummyClone)

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

local function startAIController(player, battle, level)
	if battle.aiController then
		battle.aiController:Destroy()
		battle.aiController = nil
	end

	local root = battle.dummyClone and battle.dummyClone:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.Anchored = level == 0
		if level == 0 then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end

	local aiSuccess, aiController = pcall(function()
		return TrainingDummyCombatAI.new(player, battle, level, battle.aiMemory)
	end)
	if aiSuccess then
		battle.aiController = aiController
		return true
	end

	warn("[DummyBattleServer] Training AI failed to start: " .. tostring(aiController))
	battle.dummyLevel = 0
	battle.dummyClone:SetAttribute("TrainingLevel", 0)
	if root and root:IsA("BasePart") then root.Anchored = true end
	return false
end

local function startDummyBattle(player, arenaReference)
	if not isValidPlayer(player) then
		warn("[DummyBattleServer] Tried to start a dummy battle for an invalid player")
		return false
	end
	if activeDummyBattles[player] then return false end

	local success, isAlreadyInMatch = safeMatchManagerCall("IsPlayerInMatch", player)
	if not success or isAlreadyInMatch then return false end

	local character = player.Character
	local playerHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	local playerRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not playerHumanoid or not playerRoot or playerHumanoid.Health <= 0 then
		warn("[DummyBattleServer] " .. player.Name .. " has no usable character")
		return false
	end
	if character:GetAttribute("InMatch") then return false end

	local arena = resolveArena(arenaReference)
	if not arena then
		warn("[DummyBattleServer] No available arena was found")
		return false
	end
	local spawn1 = findSpawn(arena, "ArenaSpawn1")
	local spawn2 = findSpawn(arena, "ArenaSpawn2")
	if not spawn1 or not spawn2 then
		warn("[DummyBattleServer] Arena " .. arena.Name .. " is missing ArenaSpawn1 or ArenaSpawn2")
		return false
	end

	local _, preferredLevel, aiMemory = getTrainingProfile(player)

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
	dummyClone:SetAttribute("TrainingLevel", preferredLevel)

	local dummyHumanoid = dummyClone:FindFirstChildOfClass("Humanoid")
	local dummyRoot = dummyClone:FindFirstChild("HumanoidRootPart")
	if not dummyHumanoid or not dummyRoot then
		dummyClone:Destroy()
		warn("[DummyBattleServer] The training dummy needs a Humanoid and HumanoidRootPart")
		return false
	end

	-- The lobby dummy contains its legacy combat brain. The arena clone is controlled
	-- exclusively by TrainingDummyCombatAI so Level 0 can truly do absolutely nothing
	-- and higher levels never have two AIs issuing conflicting actions.
	for _, descendant in ipairs(dummyClone:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant.Disabled = true
		end
	end

	dummyHumanoid.MaxHealth = 100
	dummyHumanoid.Health = 100
	dummyHumanoid.WalkSpeed = 0
	dummyHumanoid.JumpPower = 0
	dummyHumanoid.AutoRotate = false
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
		dummyLevel = preferredLevel,
		aiMemory = aiMemory,
		aiController = nil,
		finished = false,
		infiniteHealth = false,
		spawn1 = spawn1,
		spawn2 = spawn2,
		heartbeatConn = nil,
		dummyDiedConn = nil,
		playerDiedConn = nil,
		characterRemovingConn = nil,
		lastHudSent = 0,
		lastPlayerHealth = nil,
		lastDummyHealth = nil,
	}
	activeDummyBattles[player] = battle

	safeMatchManagerCall("SetPlayerState", player, "InMatch")
	setInMatch(player, true, spawn1.Position.Z)
	setDuelPromptEnabled(player, false)
	DamageHandler.InitializePlayerHealth(player)
	playerHumanoid.Health = playerHumanoid.MaxHealth

	dummyClone.Parent = workspace
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
	startAIController(player, battle, preferredLevel)

	local function endBattle(winnerIsPlayer)
		if not battle.finished then
			endDummyBattle(player, battle, winnerIsPlayer)
		end
	end

	battle.dummyDiedConn = dummyHumanoid.Died:Connect(function()
		endBattle(true)
	end)
	battle.playerDiedConn = playerHumanoid.Died:Connect(function()
		endBattle(false)
	end)
	battle.characterRemovingConn = player.CharacterRemoving:Connect(function(removingCharacter)
		if removingCharacter == character then endBattle(false) end
	end)

	battle.heartbeatConn = RunService.Heartbeat:Connect(function()
		if battle.finished then return end
		if not isValidPlayer(player) then endBattle(nil) return end
		if player.Character ~= character or not character.Parent then endBattle(false) return end
		if not dummyClone.Parent or not dummyHumanoid.Parent then endBattle(true) return end

		local playerHealth = DamageHandler.GetPlayerHealth(player)
		if type(playerHealth) ~= "number" then playerHealth = 0 end
		if battle.infiniteHealth then
			DamageHandler.SetPlayerHealth(player, 100)
			playerHealth = 100
		end
		local dummyHealth = math.max(0, dummyHumanoid.Health)

		if playerHealth <= 0 then endBattle(false) return end
		if dummyHealth <= 0 then endBattle(true) return end

		local now = os.clock()
		if now - battle.lastHudSent >= HUD_UPDATE_INTERVAL
			or playerHealth ~= battle.lastPlayerHealth
			or dummyHealth ~= battle.lastDummyHealth then
			battle.lastHudSent = now
			battle.lastPlayerHealth = playerHealth
			battle.lastDummyHealth = dummyHealth
			safeFireClient(player, "UpdateHealth", {Health = playerHealth, OpponentHealth = dummyHealth})
			local intensity = math.clamp((200 - playerHealth - dummyHealth) / 150, 0, 1)
			CombatJuice.EmitTo(player, "MusicIntensity", {intensity = intensity})
		end
	end)

	safeFireClient(player, "InMatch", {
		OpponentName = "Training Dummy",
		OpponentUserId = 0,
		PlayerUserId = player.UserId,
		ArenaName = arena.Name,
		MatchDuration = TRAINING_COMPAT_DURATION,
		TrainingNoTimer = true,
		DummyLevel = battle.dummyLevel,
	})

	safeFireClient(player, "BattleIntro", {
		p1 = {Name = player.Name, UserId = player.UserId},
		p2 = {Name = "Training Dummy", UserId = 0},
	})
	task.wait(2.5)

	safeFireClient(player, "Fighting", {
		OpponentName = "Training Dummy",
		OpponentUserId = 0,
		MatchDuration = TRAINING_COMPAT_DURATION,
		TrainingNoTimer = true,
		DummyLevel = battle.dummyLevel,
	})
	safeFireClient(player, "TrainingControlsSync", {
		InfiniteHealth = battle.infiniteHealth,
		DummyLevel = battle.dummyLevel,
	})

	CombatJuice.EmitTo(player, "Intro", {
		name = player.Name,
		opponent = "Training Dummy",
		rank = "Unranked",
		winStreak = 0,
		scythe = "Reaper",
	})

	print(string.format("[DummyBattleServer] Started %s vs Training Dummy L%d in %s (untimed)",
		player.Name, battle.dummyLevel, arena.Name))
	return true
end

_G.StartDummyBattle = startDummyBattle
_G.GetActiveDummyBattle = function(player)
	local battle = activeDummyBattles[player]
	if not battle or battle.finished then return nil end
	return battle
end
_G.EndDummyBattle = function(player)
	local battle = activeDummyBattles[player]
	if not battle or battle.finished then return false end
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
	if oldPrompt then oldPrompt:Destroy() end

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
		if not isValidPlayer(player) or activeDummyBattles[player] then return end
		local checkSuccess, isInMatch = safeMatchManagerCall("IsPlayerInMatch", player)
		if not checkSuccess or isInMatch then return end
		local character = player.Character
		if not character or character:GetAttribute("InMatch") then return end
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
	if not battle or battle.finished then return nil end
	return battle
end

SetInfiniteHealthRemote.OnServerEvent:Connect(function(player, enabled)
	if not isValidPlayer(player) then return end
	local battle = getActiveBattle(player)
	if not battle then return end
	battle.infiniteHealth = enabled == true
	if battle.infiniteHealth then DamageHandler.SetPlayerHealth(player, 100) end
	safeFireClient(player, "TrainingControlsSync", {
		InfiniteHealth = battle.infiniteHealth,
		DummyLevel = battle.dummyLevel,
	})
end)

SetDummyLevelRemote.OnServerEvent:Connect(function(player, requestedLevel)
	if not isValidPlayer(player) then return end
	local battle = getActiveBattle(player)
	if not battle then return end

	local level = TrainingDummyAI.ClampLevel(requestedLevel)
	battle.dummyLevel = level
	battle.dummyClone:SetAttribute("TrainingLevel", level)

	-- Recreate rather than mutate the controller so delayed attacks from the old level
	-- see destroyed=true and cannot land after the player has selected a new level.
	startAIController(player, battle, level)
	savePreferredLevel(player, level)

	-- Only the selected level is synchronized. Adaptive memory/counters never leave the server.
	safeFireClient(player, "TrainingControlsSync", {
		InfiniteHealth = battle.infiniteHealth,
		DummyLevel = level,
	})
end)

RespawnDummyRemote.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then return end
	local battle = getActiveBattle(player)
	if not battle then return end
	local dummyClone = battle.dummyClone
	local dummyHumanoid = battle.dummyHumanoid
	local spawn2 = battle.spawn2
	if not dummyClone or not dummyClone.Parent or not dummyHumanoid or not dummyHumanoid.Parent or not spawn2 then return end
	if dummyHumanoid.Health <= 0 then return end

	dummyHumanoid.Health = dummyHumanoid.MaxHealth
	dummyClone:PivotTo(spawn2.CFrame + Vector3.new(0, spawn2.Size.Y / 2 + 3, 0))
	local root = dummyClone:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = battle.dummyLevel == 0
	end
end)

ReturnToLobbyRemote.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then return end
	local battle = getActiveBattle(player)
	if battle then endDummyBattle(player, battle, nil) end
end)

Players.PlayerRemoving:Connect(function(player)
	local battle = activeDummyBattles[player]
	if not battle then return end
	battle.finished = true
	activeDummyBattles[player] = nil
	disconnectBattleConnections(battle)
	destroyBattleDummy(battle)
	unlockBattleArena(battle)
end)
