local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

pcall(function() PhysicsService:RegisterCollisionGroup("Platform") end)
pcall(function() PhysicsService:RegisterCollisionGroup("Dropping") end)
PhysicsService:CollisionGroupSetCollidable("Dropping", "Platform", false)
PhysicsService:CollisionGroupSetCollidable("Dropping", "Default", true)
PhysicsService:CollisionGroupSetCollidable("Default", "Platform", true)

local function applyPlatformGroup(descendant)
	if descendant:IsA("BasePart")
		and descendant.Anchored
		and descendant.CanCollide
		and descendant ~= workspace.Terrain
		and descendant:GetAttribute("IsaPlatform") == true then
		descendant.CollisionGroup = "Platform"
	end
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	applyPlatformGroup(descendant)
end
workspace.DescendantAdded:Connect(applyPlatformGroup)

local dropEvent = ReplicatedStorage:FindFirstChild("DropThroughPlatform")
if not dropEvent then
	dropEvent = Instance.new("RemoteEvent")
	dropEvent.Name = "DropThroughPlatform"
	dropEvent.Parent = ReplicatedStorage
end

local DROP_DURATION = 0.5
local DROP_VELOCITY_BOOST = -8
local DROP_CHECK_DISTANCE = 6
local REQUEST_COOLDOWN = 0.2

local droppingPlayers = {}
local lastRequest = {}

local function findPlatformUnderCharacter(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {character}
	params.IgnoreWater = true

	local result = workspace:Raycast(root.Position, Vector3.new(0, -DROP_CHECK_DISTANCE, 0), params)
	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return nil
	end

	if result.Instance:GetAttribute("IsaPlatform") ~= true then
		return nil
	end

	return result.Instance
end

local function captureAndSetDropping(character)
	local originalGroups = {}
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			originalGroups[part] = part.CollisionGroup
			part.CollisionGroup = "Dropping"
		end
	end
	return originalGroups
end

local function restoreCollisionGroups(originalGroups)
	for part, groupName in pairs(originalGroups) do
		if part and part.Parent and part:IsA("BasePart") then
			part.CollisionGroup = groupName
		end
	end
end

local function onDropThrough(player)
	if not player or player.Parent ~= Players or droppingPlayers[player] then return end

	local now = os.clock()
	if now - (lastRequest[player] or -math.huge) < REQUEST_COOLDOWN then return end
	lastRequest[player] = now

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return end

	-- FloorMaterial only says that *something* is under the player. Require an
	-- actual platform tagged for drop-through so a mobile DOWN tap cannot make the
	-- character phase through unrelated collision setups.
	if not findPlatformUnderCharacter(character) then return end

	local originalGroups = captureAndSetDropping(character)
	droppingPlayers[player] = {
		character = character,
		originalGroups = originalGroups,
	}

	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.min(velocity.Y, DROP_VELOCITY_BOOST), velocity.Z)

	task.delay(DROP_DURATION, function()
		local state = droppingPlayers[player]
		if not state or state.character ~= character then return end
		droppingPlayers[player] = nil
		restoreCollisionGroups(state.originalGroups)
	end)
end

dropEvent.OnServerEvent:Connect(onDropThrough)

local function cleanupPlayer(player)
	local state = droppingPlayers[player]
	if state then
		restoreCollisionGroups(state.originalGroups)
	end
	droppingPlayers[player] = nil
	lastRequest[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterRemoving:Connect(function()
		cleanupPlayer(player)
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function()
		cleanupPlayer(player)
	end)
end)

Players.PlayerRemoving:Connect(cleanupPlayer)
