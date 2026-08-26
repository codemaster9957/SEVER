local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Set up collision groups
PhysicsService:RegisterCollisionGroup("Platform")
PhysicsService:RegisterCollisionGroup("Dropping")

-- Dropping characters do NOT collide with platforms (so they fall through)
PhysicsService:CollisionGroupSetCollidable("Dropping", "Platform", false)
-- Dropping characters still collide with Default parts (walls, etc.)
PhysicsService:CollisionGroupSetCollidable("Dropping", "Default", true)
-- Normal characters collide with platforms
PhysicsService:CollisionGroupSetCollidable("Default", "Platform", true)

-- Apply "Platform" collision group only to anchored, collidable BaseParts with the "IsaPlatform" attribute set to true
local function applyPlatformGroup(descendant)
	if descendant:IsA("BasePart") and descendant.Anchored and descendant.CanCollide then
		if descendant ~= workspace.Terrain and descendant:GetAttribute("IsaPlatform") == true then
			descendant.CollisionGroup = "Platform"
		end
	end
end

for _, descendant in workspace:GetDescendants() do
	applyPlatformGroup(descendant)
end

workspace.DescendantAdded:Connect(applyPlatformGroup)

-- Create RemoteEvent if it doesn't exist
local dropEvent = ReplicatedStorage:FindFirstChild("DropThroughPlatform")
if not dropEvent then
	dropEvent = Instance.new("RemoteEvent")
	dropEvent.Name = "DropThroughPlatform"
	dropEvent.Parent = ReplicatedStorage
end

local DROP_DURATION = 0.5
local DROP_VELOCITY_BOOST = -8
local droppingPlayers = {}

local function setCharacterCollisionGroup(character, groupName)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

local function onDropThrough(player)
	-- Don't allow double-dropping
	if droppingPlayers[player] then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Only drop if standing on something
	if humanoid.FloorMaterial == Enum.Material.Air then return end

	droppingPlayers[player] = true
	setCharacterCollisionGroup(character, "Dropping")

	-- Give a small downward velocity boost for a snappy drop feel
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp then
		local vel = hrp.AssemblyLinearVelocity
		hrp.AssemblyLinearVelocity = Vector3.new(vel.X, DROP_VELOCITY_BOOST, vel.Z)
	end

	task.delay(DROP_DURATION, function()
		if droppingPlayers[player] then
			droppingPlayers[player] = nil
			if character and character.Parent then
				setCharacterCollisionGroup(character, "Default")
			end
		end
	end)
end

dropEvent.OnServerEvent:Connect(onDropThrough)

-- Ensure characters start in Default group on spawn
local function onCharacterAdded(character)
	task.wait(0.1)
	setCharacterCollisionGroup(character, "Default")
end

for _, player in Players:GetPlayers() do
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)
end)

Players.PlayerRemoving:Connect(function(player)
	droppingPlayers[player] = nil
end)