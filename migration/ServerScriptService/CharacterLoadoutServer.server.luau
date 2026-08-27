--!strict
-- Server-authoritative two-slot scythe loadout persistence/replication.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService:WaitForChild("DataService"))
local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local LoadoutPolicy = require(ScytheSystems:WaitForChild("LoadoutPolicy"))
local LoadoutRemotes = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Loadout")
local EquipMove = LoadoutRemotes:WaitForChild("EquipMove") :: RemoteEvent
local StateUpdate = LoadoutRemotes:WaitForChild("StateUpdate") :: RemoteEvent

local function isLobby(player: Player): boolean
	local character = player.Character
	return character == nil or character:GetAttribute("InMatch") ~= true
end

local function getProfileSlots(player: Player): {string}
	local profile = DataService.GetProfile(player)
	if not profile then
		return LoadoutPolicy.Sanitize(nil, nil)
	end
	return LoadoutPolicy.Sanitize(profile.EquippedMove1, profile.EquippedMove2)
end

local function applyReplicatedState(player: Player, slots: {string})
	player:SetAttribute("EquippedWeapon", LoadoutPolicy.WeaponId)
	player:SetAttribute("EquippedMove1", slots[1])
	player:SetAttribute("EquippedMove2", slots[2])
end

local function pushState(player: Player, slots: {string}, reason: string?)
	if player.Parent ~= Players then
		return
	end
	applyReplicatedState(player, slots)
	StateUpdate:FireClient(player, {
		Weapon = LoadoutPolicy.WeaponId,
		Slots = { slots[1], slots[2] },
		Reason = reason,
	})
end

local function persistSlots(player: Player, slots: {string})
	DataService.UpdateProfile(player, function(profile)
		profile.EquippedMove1 = slots[1]
		profile.EquippedMove2 = slots[2]
	end)
end

local function initializePlayer(player: Player)
	local slots = getProfileSlots(player)
	persistSlots(player, slots)
	pushState(player, slots, "Initialized")
end

EquipMove.OnServerEvent:Connect(function(player: Player, slotIndex: any, requestedMove: any)
	if not isLobby(player) then
		pushState(player, getProfileSlots(player), "LockedInBattle")
		return
	end

	local current = getProfileSlots(player)
	local updated, reason = LoadoutPolicy.Assign(current, slotIndex, requestedMove)
	if not updated then
		pushState(player, current, reason or "Rejected")
		return
	end

	persistSlots(player, updated)
	pushState(player, updated, "Equipped")
end)

Players.PlayerAdded:Connect(function(player)
	task.spawn(initializePlayer, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initializePlayer, player)
end
