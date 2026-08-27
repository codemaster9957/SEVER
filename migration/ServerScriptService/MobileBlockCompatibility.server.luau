--!strict
-- Compatibility for older mobile clients that send "Start"/"Stop" instead of booleans.
-- Boolean input remains owned by BlockServer.server.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlockRemote = ReplicatedStorage:WaitForChild("CombatEvents"):WaitForChild("BlockRemote")
local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))

local PARRY_WINDOW = 0.22
local REQUEST_COOLDOWN = 0.04
local lastRequest = {}
local sessions = {}

local function endBlock(player: Player, character: Model)
	sessions[player] = (sessions[player] or 0) + 1
	character:SetAttribute("IsBlocking", false)
	character:SetAttribute("IsParrying", false)
	character:SetAttribute("ParryExpiresAt", 0)
	DamageHandler.SetBlocking(player, false)
end

local function startBlock(player: Player, character: Model)
	if character:GetAttribute("InMatch") ~= true then return end
	if character:GetAttribute("Stunned") == true then return end
	if character:GetAttribute("CanBlock") == false then return end
	if character:GetAttribute("IsBlocking") == true then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local now = os.clock()
	local session = (sessions[player] or 0) + 1
	sessions[player] = session

	character:SetAttribute("IsBlocking", true)
	character:SetAttribute("IsParrying", true)
	character:SetAttribute("BlockStartedAt", now)
	character:SetAttribute("ParryExpiresAt", now + PARRY_WINDOW)
	DamageHandler.SetBlocking(player, true)

	task.delay(PARRY_WINDOW, function()
		if sessions[player] ~= session then return end
		if player.Character ~= character or not character.Parent then return end
		if character:GetAttribute("IsBlocking") ~= true then return end
		character:SetAttribute("IsParrying", false)
		character:SetAttribute("ParryExpiresAt", 0)
	end)
end

BlockRemote.OnServerEvent:Connect(function(player, status)
	if status ~= "Start" and status ~= "Stop" and status ~= "End" then
		return
	end

	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < REQUEST_COOLDOWN then return end
	lastRequest[player] = now

	local character = player.Character
	if not character then return end

	if status == "Start" then
		startBlock(player, character)
	else
		endBlock(player, character)
	end
end)

local function setupPlayer(player: Player)
	player.CharacterRemoving:Connect(function(character)
		if player.Character == character then
			endBlock(player, character)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end
Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastRequest[player] = nil
	sessions[player] = nil
end)
