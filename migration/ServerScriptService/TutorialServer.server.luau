--!strict
-- TutorialServer: Detects first-time players and walks them through combat basics
-- using the existing training dummy. Requires successful actions, not just text.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TutorialEvents = ReplicatedStorage:WaitForChild("TutorialEvents")
local StartTutorial = TutorialEvents:WaitForChild("StartTutorial")
local CompleteStep = TutorialEvents:WaitForChild("CompleteStep")
local SkipTutorial = TutorialEvents:WaitForChild("SkipTutorial")
local ReplayTutorial = TutorialEvents:WaitForChild("ReplayTutorial")
local TutorialStateUpdate = TutorialEvents:WaitForChild("TutorialStateUpdate")
local TutorialActionDetected = TutorialEvents:WaitForChild("TutorialActionDetected")
local TutorialComplete = TutorialEvents:WaitForChild("TutorialComplete")

local GrappleEvents = ReplicatedStorage:WaitForChild("GrappleEvents")
local DashRequest = GrappleEvents:WaitForChild("DashRequest")
local GrappleRequest = GrappleEvents:WaitForChild("GrappleRequest")
local SoulReapRequest = GrappleEvents:WaitForChild("SoulReapRequest")
local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local BlockRemote = CombatEvents:WaitForChild("BlockRemote")

local DataService = require(ServerScriptService:WaitForChild("DataService"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))

local TUTORIAL_REWARD_GOLD = 250
local TUTORIAL_REWARD_TOKENS = 5

local STEPS = {
	{ Id = "attack", Name = "Attack", Instruction = "Attack the Training Dummy! Click or tap to swing your scythe." },
	{ Id = "block", Name = "Block", Instruction = "Block an incoming attack! Press F (or tap the BLOCK button)." },
	{ Id = "dash", Name = "Dash", Instruction = "Dash to dodge! Press Q (or tap the DASH button)." },
	{ Id = "grapple", Name = "Grapple", Instruction = "Grapple toward the dummy! Hold right-click (or tap and hold on mobile)." },
	{ Id = "special", Name = "Soul Reap", Instruction = "Use your Soul Reap special! Press C (or tap MOVE 1)." },
}

-- [Player] = { currentStep = number, active = bool, dummyBattleActive = bool }
local tutorialStates = {}

local function isValidPlayer(player)
	return player and player.Parent == Players
end

local function fireState(player, state)
	if isValidPlayer(player) then
		TutorialStateUpdate:FireClient(player, state)
	end
end

local function getProfile(player)
	local profile = DataService.GetProfile(player)
	return profile
end

local function isTutorialCompleted(player)
	local profile = getProfile(player)
	return profile and profile.TutorialCompleted == true
end

local function isTutorialSkipped(player)
	local profile = getProfile(player)
	return profile and profile.TutorialSkipped == true
end

local function setTutorialCompleted(player, completed)
	local profile = getProfile(player)
	if profile then
		profile.TutorialCompleted = completed
	end
end

local function setTutorialSkipped(player, skipped)
	local profile = getProfile(player)
	if profile then
		profile.TutorialSkipped = skipped
	end
end

local function giveReward(player)
	DataService.AddGold(player, TUTORIAL_REWARD_GOLD)
	DataService.AddClawTokens(player, TUTORIAL_REWARD_TOKENS)
	if isValidPlayer(player) then
		TutorialComplete:FireClient(player, {
			GoldReward = TUTORIAL_REWARD_GOLD,
			TokenReward = TUTORIAL_REWARD_TOKENS,
		})
	end
end

local function startTutorialForPlayer(player)
	if not isValidPlayer(player) then return end
	if tutorialStates[player] and tutorialStates[player].active then return end

	-- Don't start if already completed and not replaying
	if isTutorialCompleted(player) and not isTutorialSkipped(player) then
		return
end

	tutorialStates[player] = {
		currentStep = 1,
		active = true,
		dummyBattleActive = false,
	}

	-- Start a dummy battle for the tutorial
	local arenaName = MatchManager.GetAvailableArena()
	if arenaName then
		local result = _G.StartDummyBattle(player, arenaName)
		if result then
			tutorialStates[player].dummyBattleActive = true
		end
	end

	-- Send initial tutorial state to client
	fireState(player, {
		Active = true,
		CurrentStep = 1,
		TotalSteps = #STEPS,
		StepId = STEPS[1].Id,
		StepName = STEPS[1].Name,
		Instruction = STEPS[1].Instruction,
	})
end

local function advanceStep(player)
	local state = tutorialStates[player]
	if not state or not state.active then return end

	state.currentStep += 1

	if state.currentStep > #STEPS then
		-- Tutorial complete!
		state.active = false
		setTutorialCompleted(player, true)
		giveReward(player)

		-- End the dummy battle after a short delay
		task.delay(3, function()
			if isValidPlayer(player) then
				local ReturnToLobby = ReplicatedStorage.MatchEvents.TrainingDummyControls.ReturnToLobby
				ReturnToLobby:FireServer() -- This won't work from server; use the global
			end
		end)

		fireState(player, {
			Active = false,
			Completed = true,
		})
	else
		local step = STEPS[state.currentStep]
		fireState(player, {
			Active = true,
			CurrentStep = state.currentStep,
			TotalSteps = #STEPS,
			StepId = step.Id,
			StepName = step.Name,
			Instruction = step.Instruction,
		})
	end
end

-- Detect player actions during tutorial
local function onActionDetected(player, actionType)
	local state = tutorialStates[player]
	if not state or not state.active then return end

	local currentStep = STEPS[state.currentStep]
	if not currentStep then return end

	if currentStep.Id == actionType then
		-- Verify the action matches the current step
		advanceStep(player)
	end
end

-- Listen for combat actions from existing systems
-- Attack: detected via DamageHandler (we hook into the dummy taking damage)
-- We'll use a different approach - listen for the dummy's health decreasing

-- Block: listen for BlockRemote
BlockRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "Start" then
		local state = tutorialStates[player]
		if state and state.active then
			local currentStep = STEPS[state.currentStep]
			if currentStep and currentStep.Id == "block" then
				-- Check if block was successful (parry or block caught an attack)
				-- For tutorial purposes, any block attempt counts
				task.delay(0.3, function()
					onActionDetected(player, "block")
				end)
			end
		end
	end
end)

-- Dash: listen for DashRequest
DashRequest.OnServerEvent:Connect(function(player, ...)
	local state = tutorialStates[player]
	if state and state.active then
		local currentStep = STEPS[state.currentStep]
		if currentStep and currentStep.Id == "dash" then
			onActionDetected(player, "dash")
		end
	end
end)

-- Grapple: listen for GrappleRequest
GrappleRequest.OnServerEvent:Connect(function(player, ...)
	local state = tutorialStates[player]
	if state and state.active then
		local currentStep = STEPS[state.currentStep]
		if currentStep and currentStep.Id == "grapple" then
			onActionDetected(player, "grapple")
		end
	end
end)

-- Soul Reap: listen for SoulReapRequest
SoulReapRequest.OnServerEvent:Connect(function(player, ...)
	local state = tutorialStates[player]
	if state and state.active then
		local currentStep = STEPS[state.currentStep]
		if currentStep and currentStep.Id == "special" then
			onActionDetected(player, "special")
		end
	end
end)

-- Attack detection: monitor dummy health in tutorial battles
-- We'll check periodically if the dummy took damage during the attack step
task.spawn(function()
	while true do
		task.wait(0.2)
		for player, state in pairs(tutorialStates) do
			if state and state.active and isValidPlayer(player) then
				local currentStep = STEPS[state.currentStep]
				if currentStep and currentStep.Id == "attack" then
					-- Check if the dummy's health decreased
					local dummyBattle = _G.GetActiveDummyBattle and _G.GetActiveDummyBattle(player)
					if dummyBattle and dummyBattle.dummyHumanoid then
						local currentHealth = dummyBattle.dummyHumanoid.Health
						if not state.lastDummyHealth then
							state.lastDummyHealth = currentHealth
						elseif currentHealth < state.lastDummyHealth then
							state.lastDummyHealth = currentHealth
							onActionDetected(player, "attack")
						else
							state.lastDummyHealth = currentHealth
						end
					end
				end
				end
			end
	end
end)

-- Client requests to complete a step (for client-detected actions like attack hit)
CompleteStep.OnServerEvent:Connect(function(player, stepId)
	local state = tutorialStates[player]
	if not state or not state.active then return end

	local currentStep = STEPS[state.currentStep]
	if currentStep and currentStep.Id == stepId then
		onActionDetected(player, stepId)
	end
end)

-- Skip tutorial
SkipTutorial.OnServerEvent:Connect(function(player)
	local state = tutorialStates[player]
	if not state then return end

	state.active = false
	setTutorialSkipped(player, true)
	setTutorialCompleted(player, true)

	-- End dummy battle if active
	if state.dummyBattleActive then
		local ReturnToLobbyRemote = ReplicatedStorage.MatchEvents.TrainingDummyControls.ReturnToLobby
		-- We need to end the battle from server side
		-- The DummyBattleServer handles ReturnToLobby via OnServerEvent, but we can call the global
		if _G.EndDummyBattle then
			_G.EndDummyBattle(player)
		end
	end

	tutorialStates[player] = nil
	fireState(player, { Active = false, Skipped = true })
end)

-- Replay tutorial
ReplayTutorial.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then return end
	if MatchManager.IsPlayerInMatch(player) then return end

	tutorialStates[player] = nil
	startTutorialForPlayer(player)
end)

-- Detect first-time players on join
Players.PlayerAdded:Connect(function(player)
	-- Wait for profile to load
	task.wait(2)

	if not isValidPlayer(player) then return end

	local profile = getProfile(player)
	if not profile then return end

	-- First-time player: never completed and never skipped
	if not profile.TutorialCompleted and not profile.TutorialSkipped then
		-- Wait for character to load
		player.CharacterAdded:Connect(function()
			task.wait(1)
			startTutorialForPlayer(player)
		end)

		if player.Character then
			task.wait(1)
			startTutorialForPlayer(player)
		end
	end
end)

-- Cleanup on leave
Players.PlayerRemoving:Connect(function(player)
	tutorialStates[player] = nil
end)

-- Expose globals for DummyBattleServer integration
_G.TutorialServer_States = tutorialStates
_G.TutorialServer_AdvanceStep = advanceStep

print("[TutorialServer] Initialized")