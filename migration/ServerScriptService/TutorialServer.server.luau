--!strict
-- TutorialServer: server-verified combat tutorial with mobile-compatible input handling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TutorialEvents = ReplicatedStorage:WaitForChild("TutorialEvents")
local StartTutorial = TutorialEvents:WaitForChild("StartTutorial")
local CompleteStep = TutorialEvents:WaitForChild("CompleteStep")
local SkipTutorial = TutorialEvents:WaitForChild("SkipTutorial")
local ReplayTutorial = TutorialEvents:WaitForChild("ReplayTutorial")
local TutorialStateUpdate = TutorialEvents:WaitForChild("TutorialStateUpdate")
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
	return DataService.GetProfile(player)
end

local function saveProfile(player)
	if isValidPlayer(player) then
		task.spawn(DataService.SaveProfile, player)
	end
end

local function isTutorialCompleted(player)
	local profile = getProfile(player)
	return profile and profile.TutorialCompleted == true
end

local function setTutorialCompleted(player, completed)
	local profile = getProfile(player)
	if profile then profile.TutorialCompleted = completed end
end

local function setTutorialSkipped(player, skipped)
	local profile = getProfile(player)
	if profile then profile.TutorialSkipped = skipped end
end

local function giveRewardOnce(player)
	local profile = getProfile(player)
	local goldReward = 0
	local tokenReward = 0

	if profile and profile.TutorialRewardClaimed ~= true then
		-- Set the claim flag before changing balances so replay/spam cannot race a second grant.
		profile.TutorialRewardClaimed = true
		DataService.AddGold(player, TUTORIAL_REWARD_GOLD)
		DataService.AddClawTokens(player, TUTORIAL_REWARD_TOKENS)
		goldReward = TUTORIAL_REWARD_GOLD
		tokenReward = TUTORIAL_REWARD_TOKENS
		saveProfile(player)
	end

	if isValidPlayer(player) then
		TutorialComplete:FireClient(player, {
			GoldReward = goldReward,
			TokenReward = tokenReward,
			AlreadyClaimed = goldReward == 0 and tokenReward == 0,
		})
	end
end

local function sendCurrentStep(player)
	local state = tutorialStates[player]
	if not state or not state.active then return end
	local step = STEPS[state.currentStep]
	if not step then return end

	fireState(player, {
		Active = true,
		CurrentStep = state.currentStep,
		TotalSteps = #STEPS,
		StepId = step.Id,
		StepName = step.Name,
		Instruction = step.Instruction,
		Replay = state.replay == true,
	})
end

local function startTutorialForPlayer(player, replay)
	if not isValidPlayer(player) then return false end
	if tutorialStates[player] and tutorialStates[player].active then return false end
	if MatchManager.IsPlayerInMatch(player) then return false end
	if not replay and isTutorialCompleted(player) then return false end

	local arenaName = MatchManager.GetAvailableArena()
	if not arenaName or not _G.StartDummyBattle then
		fireState(player, { Active = false, Error = "No practice arena available" })
		return false
	end

	local started = _G.StartDummyBattle(player, arenaName)
	if started == false then
		fireState(player, { Active = false, Error = "Unable to start practice battle" })
		return false
	end

	tutorialStates[player] = {
		currentStep = 1,
		active = true,
		dummyBattleActive = true,
		replay = replay == true,
		lastDummyHealth = nil,
	}

	sendCurrentStep(player)
	return true
end

local function finishTutorial(player, state)
	state.active = false
	setTutorialCompleted(player, true)
	setTutorialSkipped(player, false)
	giveRewardOnce(player)
	saveProfile(player)

	fireState(player, {
		Active = false,
		Completed = true,
		Replay = state.replay == true,
	})

	-- End from the server API. RemoteEvent:FireServer cannot be called by a server Script.
	task.delay(2, function()
		if isValidPlayer(player) and _G.EndDummyBattle then
			_G.EndDummyBattle(player)
		end
	end)
end

local function advanceStep(player)
	local state = tutorialStates[player]
	if not state or not state.active then return end

	state.currentStep += 1
	state.lastDummyHealth = nil
	if state.currentStep > #STEPS then
		finishTutorial(player, state)
		return
	end

	sendCurrentStep(player)
end

local function onActionDetected(player, actionType)
	local state = tutorialStates[player]
	if not state or not state.active then return end
	local currentStep = STEPS[state.currentStep]
	if currentStep and currentStep.Id == actionType then
		advanceStep(player)
	end
end

-- BlockServer's canonical protocol is boolean. "Start" remains accepted for older clients.
BlockRemote.OnServerEvent:Connect(function(player, status)
	if status == true or status == "Start" then
		local state = tutorialStates[player]
		local step = state and STEPS[state.currentStep]
		if step and step.Id == "block" then
			onActionDetected(player, "block")
		end
	end
end)

DashRequest.OnServerEvent:Connect(function(player)
	local state = tutorialStates[player]
	local step = state and STEPS[state.currentStep]
	if step and step.Id == "dash" then
		onActionDetected(player, "dash")
	end
end)

GrappleRequest.OnServerEvent:Connect(function(player)
	local state = tutorialStates[player]
	local step = state and STEPS[state.currentStep]
	if step and step.Id == "grapple" then
		onActionDetected(player, "grapple")
	end
end)

SoulReapRequest.OnServerEvent:Connect(function(player)
	local state = tutorialStates[player]
	local step = state and STEPS[state.currentStep]
	if step and step.Id == "special" then
		onActionDetected(player, "special")
	end
end)

-- Attack completion is verified by actual dummy health loss, not a trusted client event.
task.spawn(function()
	while true do
		task.wait(0.15)
		for player, state in pairs(tutorialStates) do
			if state.active and isValidPlayer(player) then
				local step = STEPS[state.currentStep]
				if step and step.Id == "attack" then
					local battle = _G.GetActiveDummyBattle and _G.GetActiveDummyBattle(player)
					local humanoid = battle and battle.dummyHumanoid
					if humanoid and humanoid.Parent then
						local health = humanoid.Health
						if state.lastDummyHealth and health < state.lastDummyHealth then
							onActionDetected(player, "attack")
						else
							state.lastDummyHealth = health
						end
					end
				end
			end
		end
	end
end)

-- Legacy clients may still fire CompleteStep. Never trust it for progression;
-- all five tutorial actions are now independently verified by the server above.
CompleteStep.OnServerEvent:Connect(function(_player, _stepId)
	return
end)

StartTutorial.OnServerEvent:Connect(function(player)
	startTutorialForPlayer(player, false)
end)

SkipTutorial.OnServerEvent:Connect(function(player)
	local state = tutorialStates[player]
	if not state or not state.active then return end

	state.active = false
	setTutorialSkipped(player, true)
	setTutorialCompleted(player, true)
	saveProfile(player)

	if state.dummyBattleActive and _G.EndDummyBattle then
		_G.EndDummyBattle(player)
	end

	tutorialStates[player] = nil
	fireState(player, { Active = false, Skipped = true })
end)

ReplayTutorial.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) or MatchManager.IsPlayerInMatch(player) then return end
	tutorialStates[player] = nil
	startTutorialForPlayer(player, true)
end)

Players.PlayerAdded:Connect(function(player)
	task.wait(2)
	if not isValidPlayer(player) then return end

	local profile = getProfile(player)
	if not profile or profile.TutorialCompleted or profile.TutorialSkipped then return end

	player.CharacterAdded:Connect(function()
		task.wait(1)
		startTutorialForPlayer(player, false)
	end)

	if player.Character then
		task.wait(1)
		startTutorialForPlayer(player, false)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	tutorialStates[player] = nil
end)

_G.TutorialServer_States = tutorialStates
_G.TutorialServer_AdvanceStep = advanceStep

print("[TutorialServer] Initialized")
