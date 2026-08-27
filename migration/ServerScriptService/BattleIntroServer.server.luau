local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

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
getOrCreateRemote(MatchEvents, "GameStateUpdate")
local RequestBattleIntro = getOrCreateRemote(MatchEvents, "RequestBattleIntro")

local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
local combatRemote = CombatJuice.GetRemote()

local requestCooldown = {}
local COOLDOWN = 2

local function valid(player)
	return player and player.Parent == Players
end

RequestBattleIntro.OnServerEvent:Connect(function(player)
	if not valid(player) or not MatchManager.IsPlayerInMatch(player) then return end

	local now = os.clock()
	if now - (requestCooldown[player] or -math.huge) < COOLDOWN then return end
	requestCooldown[player] = now

	-- Never trust opponent names/ids supplied by a client. Resolve the server's
	-- authoritative match relationship instead.
	local opponent = MatchManager.GetOpponent(player)
	if valid(opponent) and opponent ~= player then
		combatRemote:FireClient(player, "BattleIntroRequest", {
			player1 = player.Name,
			player2 = opponent.Name,
		})
		combatRemote:FireClient(opponent, "BattleIntroRequest", {
			player1 = player.Name,
			player2 = opponent.Name,
		})
		return
	end

	-- Training matches have no Player opponent; only permit the dummy intro when
	-- DummyBattleServer confirms this player owns an active dummy battle.
	local dummyBattle = _G.GetActiveDummyBattle and _G.GetActiveDummyBattle(player)
	if dummyBattle then
		combatRemote:FireClient(player, "BattleIntroRequest", {
			player1 = player.Name,
			player2 = "TRAINING DUMMY",
		})
	end
end)

Players.PlayerRemoving:Connect(function(player)
	requestCooldown[player] = nil
end)
