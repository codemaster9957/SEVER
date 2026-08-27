--!strict
-- Bridges the existing scythe Tool activation to authored client VFX.
-- Combat/damage logic remains inside the original Tool scripts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VFXEvent = ReplicatedStorage:WaitForChild("ScytheVFXEvent") :: RemoteEvent

local connectedTools = setmetatable({}, { __mode = "k" })
local lastSlashByPlayer: {[Player]: number} = {}

local MIN_SLASH_INTERVAL = 0.08

local function isScytheTool(instance: Instance): boolean
	if not instance:IsA("Tool") then
		return false
	end

	local lowerName = string.lower(instance.Name)
	return string.find(lowerName, "scythe", 1, true) ~= nil
end

local function getEquippedScythe(character: Model): Tool?
	for _, child in ipairs(character:GetChildren()) do
		if isScytheTool(child) then
			return child :: Tool
		end
	end
	return nil
end

local function canShowSlash(player: Player, character: Model, tool: Tool): boolean
	if player.Character ~= character or tool.Parent ~= character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if character:GetAttribute("Stunned") == true
		or character:GetAttribute("IsBlocking") == true
		or character:GetAttribute("CanAttack") == false then
		return false
	end

	return true
end

local function replicateSlash(player: Player, character: Model, tool: Tool)
	if not canShowSlash(player, character, tool) then
		return
	end

	local now = os.clock()
	local previous = lastSlashByPlayer[player] or 0
	if now - previous < MIN_SLASH_INTERVAL then
		return
	end
	lastSlashByPlayer[player] = now

	-- VFX only: no hitboxes, damage, cooldowns, or substitute geometry.
	VFXEvent:FireAllClients("Slash", player.UserId)
end

local function connectTool(player: Player, character: Model, tool: Tool)
	if connectedTools[tool] then
		return
	end
	connectedTools[tool] = true

	-- Keep server Tool.Activated as a fallback for tools whose activation replicates.
	tool.Activated:Connect(function()
		replicateSlash(player, character, tool)
	end)
end

local function setupCharacter(player: Player, character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if isScytheTool(child) then
			connectTool(player, character, child :: Tool)
		end
	end

	character.ChildAdded:Connect(function(child)
		if isScytheTool(child) then
			connectTool(player, character, child :: Tool)
		end
	end)
end

local function setupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)

	if player.Character then
		setupCharacter(player, player.Character)
	end
end

-- Reliable client-to-server VFX request. The server independently verifies that the
-- player is alive, allowed to attack, and currently holding a scythe before relaying it.
VFXEvent.OnServerEvent:Connect(function(player, action)
	if action ~= "Slash" then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local tool = getEquippedScythe(character)
	if not tool then
		return
	end

	replicateSlash(player, character, tool)
end)

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(function(player)
	lastSlashByPlayer[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(setupPlayer, player)
end
