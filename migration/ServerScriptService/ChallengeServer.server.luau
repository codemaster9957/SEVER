local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local ChallengeRequest = MatchEvents:WaitForChild("ChallengeRequest")
local ChallengeResponse = MatchEvents:WaitForChild("ChallengeResponse")

local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))

local CHALLENGE_TIMEOUT = 20
local CHALLENGE_COOLDOWN = 2

local setupPlayers = {}
local pendingChallenges = {} -- [targetPlayer] = {[challenger] = expiryTime}
local lastChallengeTime = {} -- [challenger] = os.clock()
local startingPlayers = {} -- prevents two accepted challenges starting around the same player

local function isValidPlayer(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player.Parent == Players
end

local function clearChallenge(targetPlayer, challenger)
	if pendingChallenges[targetPlayer] then
		pendingChallenges[targetPlayer][challenger] = nil
		if next(pendingChallenges[targetPlayer]) == nil then
			pendingChallenges[targetPlayer] = nil
		end
	end
end

local function clearChallengesForPlayer(player)
	pendingChallenges[player] = nil
	for targetPlayer, challenges in pairs(pendingChallenges) do
		challenges[player] = nil
		if next(challenges) == nil then
			pendingChallenges[targetPlayer] = nil
		end
	end
end

local function isBusy(player)
	return startingPlayers[player] == true or MatchManager.IsPlayerInMatch(player)
end

local function createPromptForCharacter(targetPlayer, character)
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then return end

	local oldPrompt = hrp:FindFirstChild("DuelChallengePrompt")
	if oldPrompt then oldPrompt:Destroy() end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DuelChallengePrompt"
	prompt.ActionText = "Challenge to Duel"
	prompt.ObjectText = targetPlayer.Name
	prompt.HoldDuration = 1
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Enabled = not isBusy(targetPlayer)
	prompt.Parent = hrp

	prompt.Triggered:Connect(function(challenger)
		if not isValidPlayer(challenger) or not isValidPlayer(targetPlayer) then return end
		if challenger == targetPlayer then return end
		if isBusy(challenger) or isBusy(targetPlayer) then return end

		local now = os.clock()
		if lastChallengeTime[challenger] and now - lastChallengeTime[challenger] < CHALLENGE_COOLDOWN then
			return
		end
		lastChallengeTime[challenger] = now

		pendingChallenges[targetPlayer] = pendingChallenges[targetPlayer] or {}
		pendingChallenges[targetPlayer][challenger] = now + CHALLENGE_TIMEOUT
		ChallengeRequest:FireClient(targetPlayer, challenger, CHALLENGE_TIMEOUT)

		task.delay(CHALLENGE_TIMEOUT, function()
			clearChallenge(targetPlayer, challenger)
		end)
	end)
end

local function setupPromptsForPlayer(player)
	if setupPlayers[player] then return end
	setupPlayers[player] = true

	player.CharacterAdded:Connect(function(character)
		createPromptForCharacter(player, character)
	end)

	if player.Character then
		task.defer(function()
			createPromptForCharacter(player, player.Character)
		end)
	end
end

Players.PlayerAdded:Connect(setupPromptsForPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPromptsForPlayer(player)
end

ChallengeResponse.OnServerEvent:Connect(function(targetPlayer, challenger, accepted)
	if not isValidPlayer(targetPlayer) or not isValidPlayer(challenger) then return end
	if challenger == targetPlayer then return end

	local targetChallenges = pendingChallenges[targetPlayer]
	if not targetChallenges then return end
	local expiryTime = targetChallenges[challenger]
	if not expiryTime then return end

	clearChallenge(targetPlayer, challenger)
	if not accepted or os.clock() > expiryTime then return end

	-- Re-check at ACCEPT time; either player may have entered another match while
	-- the challenge UI was open.
	if isBusy(targetPlayer) or isBusy(challenger) then return end

	startingPlayers[targetPlayer] = true
	startingPlayers[challenger] = true
	clearChallengesForPlayer(targetPlayer)
	clearChallengesForPlayer(challenger)

	local ok, started = pcall(function()
		return MatchManager.StartMapVote(challenger, targetPlayer)
	end)

	startingPlayers[targetPlayer] = nil
	startingPlayers[challenger] = nil

	if not ok then
		warn("[ChallengeServer] Failed to start duel:", started)
	elseif started ~= true then
		warn(string.format("[ChallengeServer] Duel could not start for %s vs %s", challenger.Name, targetPlayer.Name))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	setupPlayers[player] = nil
	lastChallengeTime[player] = nil
	startingPlayers[player] = nil
	clearChallengesForPlayer(player)
end)
