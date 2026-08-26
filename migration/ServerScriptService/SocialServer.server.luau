--!strict
-- SocialServer: Parties, private matches, spectating, clans, post-match reactions,
-- friends leaderboard, shareable winstreak stats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SocialEvents = ReplicatedStorage:WaitForChild("SocialEvents")
local PartyInvite = SocialEvents:WaitForChild("PartyInvite")
local PartyInviteResponse = SocialEvents:WaitForChild("PartyInviteResponse")
local PartyUpdate = SocialEvents:WaitForChild("PartyUpdate")
local LeaveParty = SocialEvents:WaitForChild("LeaveParty")
local KickFromParty = SocialEvents:WaitForChild("KickFromParty")
local SetPartyLeader = SocialEvents:WaitForChild("SetPartyLeader")
local StartPrivateMatch = SocialEvents:WaitForChild("StartPrivateMatch")
local PrivateMatchInvite = SocialEvents:WaitForChild("PrivateMatchInvite")
local PrivateMatchResponse = SocialEvents:WaitForChild("PrivateMatchResponse")
local SpectateMatch = SocialEvents:WaitForChild("SpectateMatch")
local StopSpectating = SocialEvents:WaitForChild("StopSpectating")
local SpectateUpdate = SocialEvents:WaitForChild("SpectateUpdate")
local SendReaction = SocialEvents:WaitForChild("SendReaction")
local ReactionUpdate = SocialEvents:WaitForChild("ReactionUpdate")
local ClanCreate = SocialEvents:WaitForChild("ClanCreate")
local ClanDisband = SocialEvents:WaitForChild("ClanDisband")
local ClanInvite = SocialEvents:WaitForChild("ClanInvite")
local ClanInviteResponse = SocialEvents:WaitForChild("ClanInviteResponse")
local ClanLeave = SocialEvents:WaitForChild("ClanLeave")
local ClanKick = SocialEvents:WaitForChild("ClanKick")
local ClanUpdate = SocialEvents:WaitForChild("ClanUpdate")
local FriendsLeaderboardUpdate = SocialEvents:WaitForChild("FriendsLeaderboardUpdate")
local ShareWinStreak = SocialEvents:WaitForChild("ShareWinStreak")

local DataService = require(ServerScriptService:WaitForChild("DataService"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
local WinstreakData = require(ServerScriptService:WaitForChild("WinstreakData"))

-- Party data: [Player] = { leader = Player, members = { [Player] = true }, invites = { [Player] = expiry } }
local parties = {}

-- Clan data: [clanId] = { name = string, leader = Player, members = { [Player] = role }, invites = { [Player] = expiry } }
local clans = {}
local playerClans = {} -- [Player] = clanId

-- Spectating: [Player] = { target = Player, matchP1 = Player, matchP2 = Player }
local spectators = {}

-- Post-match reactions: [matchId] = { [Player] = reactionString }
local matchReactions = {}

-- Private match invites: [Player] = { from = Player, expiry = number }
local privateMatchInvites = {}

local function isValidPlayer(player)
	return player and player.Parent == Players
end

local function firePartyUpdate(party)
	if not party then return end
	local memberList = {}
	for member in pairs(party.members) do
		if isValidPlayer(member) then
			table.insert(memberList, { Name = member.Name, UserId = member.UserId, IsLeader = member == party.leader })
		end
	end
	for member in pairs(party.members) do
		if isValidPlayer(member) then
			PartyUpdate:FireClient(member, { Members = memberList, Leader = party.leader.Name })
		end
	end
end

local function getParty(player)
	for _, party in pairs(parties) do
		if party.members[player] then
			return party
		end
	end
	return nil
end

local function removePlayerFromParty(player)
	local party = getParty(player)
	if not party then return end

	party.members[player] = nil

	if party.leader == player then
		-- Assign new leader
		local newLeader = next(party.members)
		if newLeader then
			party.leader = newLeader
		else
			-- No members left, remove party
			parties[party] = nil
			return
		end
	end

	firePartyUpdate(party)
end

-- Party invite
PartyInvite.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	if player == targetPlayer then return end

	local party = getParty(player)
	if not party then
		-- Create a new party
		party = { leader = player, members = { [player] = true } }
		parties[party] = true
	end

	-- Only leader can invite
	if party.leader ~= player then return end

	-- Don't invite if already in a party
	if getParty(targetPlayer) then return end

	PartyInvite:FireClient(targetPlayer, { FromPlayer = player.Name, FromUserId = player.UserId })
end)

-- Party invite response
PartyInviteResponse.OnServerEvent:Connect(function(player, inviter, accepted)
	if not isValidPlayer(player) or not isValidPlayer(inviter) then return end
	if not accepted then return end

	local party = getParty(inviter)
	if not party then return end

	-- Check if player is already in a party
	if getParty(player) then return end

	party.members[player] = true
	firePartyUpdate(party)
end)

-- Leave party
LeaveParty.OnServerEvent:Connect(function(player)
	removePlayerFromParty(player)
	PartyUpdate:FireClient(player, { Members = {}, Left = true })
end)

-- Kick from party (leader only)
KickFromParty.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	local party = getParty(player)
	if not party or party.leader ~= player then return end

	party.members[targetPlayer] = nil
	PartyUpdate:FireClient(targetPlayer, { Members = {}, Kicked = true })
	firePartyUpdate(party)
end)

-- Set party leader
SetPartyLeader.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	local party = getParty(player)
	if not party or party.leader ~= player then return end
	if not party.members[targetPlayer] then return end

	party.leader = targetPlayer
	firePartyUpdate(party)
end)

-- Private match invite
StartPrivateMatch.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	if player == targetPlayer then return end
	if MatchManager.IsPlayerInMatch(player) or MatchManager.IsPlayerInMatch(targetPlayer) then return end

	privateMatchInvites[targetPlayer] = { from = player, expiry = os.clock() + 20 }
	PrivateMatchInvite:FireClient(targetPlayer, { FromPlayer = player.Name, FromUserId = player.UserId })

	task.delay(20, function()
		if privateMatchInvites[targetPlayer] and privateMatchInvites[targetPlayer].from == player then
			privateMatchInvites[targetPlayer] = nil
		end
	end)
end)

-- Private match response
PrivateMatchResponse.OnServerEvent:Connect(function(player, inviter, accepted)
	if not isValidPlayer(player) or not isValidPlayer(inviter) then return end

	local invite = privateMatchInvites[player]
	if not invite or invite.from ~= inviter then return end

	privateMatchInvites[player] = nil

	if not accepted then return end

	if MatchManager.IsPlayerInMatch(player) or MatchManager.IsPlayerInMatch(inviter) then return end

	local arenaName = MatchManager.GetAvailableArena()
	if arenaName then
		MatchManager.StartMatch(inviter, player, arenaName)
	end
end)

-- Spectating
SpectateMatch.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	if player == targetPlayer then return end

	-- Check if target is in a match
	local opponent = MatchManager.GetOpponent(targetPlayer)
	if not opponent then
		SpectateUpdate:FireClient(player, { Error = "Target is not in a match" })
		return
	end

	-- Remove from existing spectate
	if spectators[player] then
		spectators[player] = nil
	end

	spectators[player] = { target = targetPlayer, matchP1 = targetPlayer, matchP2 = opponent }
	SpectateUpdate:FireClient(player, { Spectating = true, Target = targetPlayer.Name, Opponent = opponent.Name })
end)

-- Stop spectating
StopSpectating.OnServerEvent:Connect(function(player)
	spectators[player] = nil
	SpectateUpdate:FireClient(player, { Spectating = false })
end)

-- Spectator update loop - send health/timer updates to spectators
task.spawn(function()
	while true do
		task.wait(0.2)
		for spectator, data in pairs(spectators) do
			if not isValidPlayer(spectator) then
				spectators[spectator] = nil
			elseif not isValidPlayer(data.target) or not MatchManager.IsPlayerInMatch(data.target) then
				-- Match ended
				spectators[spectator] = nil
				SpectateUpdate:FireClient(spectator, { Spectating = false, MatchEnded = true })
			else
				-- Send spectate update with positions
				local targetChar = data.target.Character
				local opponentChar = data.matchP2 and data.matchP2.Character
				if targetChar and targetChar:FindFirstChild("HumanoidRootPart") then
					SpectateUpdate:FireClient(spectator, {
						Spectating = true,
						Target = data.target.Name,
						Opponent = data.matchP2 and data.matchP2.Name or "Unknown",
					})
				end
			end
		end
	end
end)

-- Post-match reactions
SendReaction.OnServerEvent:Connect(function(player, reaction)
	if not isValidPlayer(player) then return end
	reaction = tostring(reaction):sub(1, 50) -- Sanitize and limit length

	local opponent = MatchManager.GetOpponent(player)
	if not opponent then
		-- Check recent match
		local recent = recentMatches and recentMatches[player]
		if recent and recent.opponent and isValidPlayer(recent.opponent) then
			opponent = recent.opponent
		end
	end

	if opponent and isValidPlayer(opponent) then
		ReactionUpdate:FireClient(opponent, { FromPlayer = player.Name, Reaction = reaction })
	end
end)

-- Share winstreak
ShareWinStreak.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then return end
	local streak = WinstreakData.Get(player)
	local profile = DataService.GetProfile(player)
	local bestStreak = profile and profile.BestWinStreak or 0

	-- Broadcast to all players
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			ShareWinStreak:FireClient(p, { Player = player.Name, CurrentStreak = streak, BestStreak = bestStreak })
		end
	end
end)

-- Clan system
ClanCreate.OnServerEvent:Connect(function(player, clanName)
	if not isValidPlayer(player) then return end
	if playerClans[player] then return end

	clanName = tostring(clanName):sub(1, 20)
	if clanName == "" then return end

	local clanId = tostring(player.UserId) .. "_" .. tostring(os.time())
	local clan = {
		name = clanName,
		leader = player,
		members = { [player] = "Leader" },
		invites = {},
	}
	clans[clanId] = clan
	playerClans[player] = clanId

	local profile = DataService.GetProfile(player)
	if profile then
		profile.ClanId = clanId
		profile.ClanRole = "Leader"
	end

	ClanUpdate:FireClient(player, { ClanName = clanName, Role = "Leader", Members = { { Name = player.Name, Role = "Leader" } } })
end)

ClanDisband.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then return end
	local clanId = playerClans[player]
	if not clanId then return end
	local clan = clans[clanId]
	if not clan or clan.leader ~= player then return end

	for member in pairs(clan.members) do
		if isValidPlayer(member) then
			ClanUpdate:FireClient(member, { Disbanded = true })
			local profile = DataService.GetProfile(member)
			if profile then
				profile.ClanId = nil
				profile.ClanRole = nil
			end
			playerClans[member] = nil
		end
	end
	clans[clanId] = nil
end)

ClanInvite.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	local clanId = playerClans[player]
	if not clanId then return end
	local clan = clans[clanId]
	if not clan then return end

	-- Only leader or officers can invite
	local role = clan.members[player]
	if role ~= "Leader" and role ~= "Officer" then return end

	if playerClans[targetPlayer] then return end

	clan.invites[targetPlayer] = os.clock() + 30
	ClanInvite:FireClient(targetPlayer, { FromPlayer = player.Name, ClanName = clan.name })

	task.delay(30, function()
		if clan.invites[targetPlayer] then
			clan.invites[targetPlayer] = nil
		end
	end)
end)

ClanInviteResponse.OnServerEvent:Connect(function(player, inviter, accepted)
	if not isValidPlayer(player) or not isValidPlayer(inviter) then return end
	local clanId = playerClans[inviter]
	if not clanId then return end
	local clan = clans[clanId]
	if not clan then return end
	if not clan.invites[player] then return end

	clan.invites[player] = nil

	if not accepted then return end
	if playerClans[player] then return end

	clan.members[player] = "Member"
	playerClans[player] = clanId

	local profile = DataService.GetProfile(player)
	if profile then
		profile.ClanId = clanId
		profile.ClanRole = "Member"
	end

	-- Notify all members
	local memberList = {}
	for member, role in pairs(clan.members) do
		if isValidPlayer(member) then
			table.insert(memberList, { Name = member.Name, Role = role })
		end
	end
	for member in pairs(clan.members) do
		if isValidPlayer(member) then
			ClanUpdate:FireClient(member, { ClanName = clan.name, Members = memberList })
		end
	end
end)

ClanLeave.OnServerEvent:Connect(function(player)
	if not isValidPlayer(player) then return end
	local clanId = playerClans[player]
	if not clanId then return end
	local clan = clans[clanId]
	if not clan then return end

	if clan.leader == player then
		-- Leader leaving = disband
		for member in pairs(clan.members) do
			if isValidPlayer(member) then
				ClanUpdate:FireClient(member, { Disbanded = true })
				local profile = DataService.GetProfile(member)
				if profile then
					profile.ClanId = nil
					profile.ClanRole = nil
				end
				playerClans[member] = nil
			end
		end
		clans[clanId] = nil
	else
		clan.members[player] = nil
		playerClans[player] = nil

		local profile = DataService.GetProfile(player)
		if profile then
			profile.ClanId = nil
			profile.ClanRole = nil
		end

		ClanUpdate:FireClient(player, { Left = true })

		-- Update remaining members
		local memberList = {}
		for member, role in pairs(clan.members) do
			if isValidPlayer(member) then
				table.insert(memberList, { Name = member.Name, Role = role })
			end
		end
		for member in pairs(clan.members) do
			if isValidPlayer(member) then
				ClanUpdate:FireClient(member, { ClanName = clan.name, Members = memberList })
			end
		end
	end
end)

ClanKick.OnServerEvent:Connect(function(player, targetPlayer)
	if not isValidPlayer(player) or not isValidPlayer(targetPlayer) then return end
	local clanId = playerClans[player]
	if not clanId then return end
	local clan = clans[clanId]
	if not clan or clan.leader ~= player then return end

	clan.members[targetPlayer] = nil
	playerClans[targetPlayer] = nil

	local profile = DataService.GetProfile(targetPlayer)
	if profile then
		profile.ClanId = nil
		profile.ClanRole = nil
	end

	ClanUpdate:FireClient(targetPlayer, { Kicked = true })

	-- Update remaining members
	local memberList = {}
	for member, role in pairs(clan.members) do
		if isValidPlayer(member) then
			table.insert(memberList, { Name = member.Name, Role = role })
		end
	end
	for member in pairs(clan.members) do
		if isValidPlayer(member) then
			ClanUpdate:FireClient(member, { ClanName = clan.name, Members = memberList })
		end
	end
end)

-- Friends leaderboard - send updates periodically
task.spawn(function()
	while true do
		task.wait(10)
		for _, player in ipairs(Players:GetPlayers()) do
			local leaderboard = {}
			for _, otherPlayer in ipairs(Players:GetPlayers()) do
				if otherPlayer ~= player then
					local streak = WinstreakData.Get(otherPlayer)
					local profile = DataService.GetProfile(otherPlayer)
					table.insert(leaderboard, {
						Name = otherPlayer.Name,
						UserId = otherPlayer.UserId,
						WinStreak = streak,
						BestStreak = profile and profile.BestWinStreak or 0,
						MMR = profile and profile.MMR or 1000,
					})
				end
			end
			table.sort(leaderboard, function(a, b)
				return (a.BestStreak or 0) > (b.BestStreak or 0)
			end)
			FriendsLeaderboardUpdate:FireClient(player, { Leaderboard = leaderboard })
		end
	end
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	-- Remove from party
	removePlayerFromParty(player)

	-- Remove from clan
	local clanId = playerClans[player]
	if clanId and clans[clanId] then
		local clan = clans[clanId]
		if clan.leader == player then
			-- Disband clan
			for member in pairs(clan.members) do
				if isValidPlayer(member) then
					ClanUpdate:FireClient(member, { Disbanded = true })
					playerClans[member] = nil
				end
			end
			clans[clanId] = nil
		else
			clan.members[player] = nil
			local memberList = {}
			for member, role in pairs(clan.members) do
				if isValidPlayer(member) then
					table.insert(memberList, { Name = member.Name, Role = role })
				end
			end
			for member in pairs(clan.members) do
				if isValidPlayer(member) then
					ClanUpdate:FireClient(member, { ClanName = clan.name, Members = memberList })
				end
			end
		end
	end
	playerClans[player] = nil

	-- Remove spectating
	spectators[player] = nil

	-- Remove private match invites
	privateMatchInvites[player] = nil

	-- Remove any pending party invites
	for _, party in pairs(parties) do
		party.invites = party.invites or {}
		party.invites[player] = nil
	end
end)

print("[SocialServer] Initialized")