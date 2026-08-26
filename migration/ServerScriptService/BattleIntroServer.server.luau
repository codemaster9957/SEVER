local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder
end

local function getOrCreateRemote(parent, name)
	local remote = parent:FindFirstChild(name)

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
	end

	return remote
end

local MatchEvents = getOrCreateFolder(ReplicatedStorage, "MatchEvents")

local GameStateUpdate = getOrCreateRemote(MatchEvents, "GameStateUpdate")
local RequestBattleIntro = getOrCreateRemote(MatchEvents, "RequestBattleIntro")

local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))
local combatRemote = CombatJuice.GetRemote()

local requestCooldown = {}
local COOLDOWN = 2

local function resolveOpponent(opponentData)
	if typeof(opponentData) == "Instance" and opponentData:IsA("Player") then
		return opponentData, opponentData.Name
	end

	if typeof(opponentData) == "number" then
		local foundPlayer = Players:GetPlayerByUserId(opponentData)
		if foundPlayer then
			return foundPlayer, foundPlayer.Name
		end
	end

	if typeof(opponentData) == "string" then
		local foundPlayer = Players:FindFirstChild(opponentData)

		if foundPlayer then
			return foundPlayer, foundPlayer.Name
		end

		return nil, opponentData
	end

	return nil, "TRAINING DUMMY"
end

RequestBattleIntro.OnServerEvent:Connect(function(player, opponentData)
	if not player or not player.Parent then return end

	local now = os.clock()

	if requestCooldown[player] and now - requestCooldown[player] < COOLDOWN then
		return
	end

	requestCooldown[player] = now

	local opponentPlayer, opponentName = resolveOpponent(opponentData)

	local introData = {
		player1 = player.Name,
		player2 = opponentName or "TRAINING DUMMY"
	}

	combatRemote:FireClient(player, "BattleIntroRequest", introData)

	if opponentPlayer and opponentPlayer ~= player then
		combatRemote:FireClient(opponentPlayer, "BattleIntroRequest", {
			player1 = player.Name,
			player2 = opponentPlayer.Name
		})
	end
end)

Players.PlayerRemoving:Connect(function(player)
	requestCooldown[player] = nil
end)