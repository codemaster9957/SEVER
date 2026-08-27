local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GrappleEvents = ReplicatedStorage:WaitForChild("GrappleEvents")
local GrappleRequest = GrappleEvents:WaitForChild("GrappleRequest")
local ReleaseRequest = GrappleEvents:WaitForChild("ReleaseRequest")
local PlayPrivateSound = ReplicatedStorage:WaitForChild("PlayPrivateSound")
local MatchManager = require(game:GetService("ServerScriptService"):WaitForChild("MatchManager"))

local MAX_GRAPPLE_DISTANCE = 120
local MIN_GRAPPLE_DISTANCE = 4
local MAX_GRAPPLE_TIME = 2.5
local REQUEST_COOLDOWN = 0.12
local MAX_ARENA_DEPTH_OFFSET = 24

local activeGrapples = {}
local lastRequestAt = {}
local grappleTokens = {}

local function isFiniteNumber(value)
	return type(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

local function isFiniteVector3(value)
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

local function destroyGrappleData(data)
	if not data then return end
	if data.Spring then data.Spring:Destroy() end
	if data.Attachment0 then data.Attachment0:Destroy() end
	if data.Attachment1 then data.Attachment1:Destroy() end
	if data.Beam then data.Beam:Destroy() end
end

local function releaseGrapple(player)
	if not player then return end
	local userId = player.UserId
	local data = activeGrapples[userId]
	if data then
		destroyGrappleData(data)
		activeGrapples[userId] = nil
	end
	grappleTokens[userId] = (grappleTokens[userId] or 0) + 1
end

local function resolveTarget(character, hrp, requestedPosition)
	if not isFiniteVector3(requestedPosition) then
		return nil
	end

	local delta = requestedPosition - hrp.Position
	local distance = delta.Magnitude
	if distance < MIN_GRAPPLE_DISTANCE or distance > MAX_GRAPPLE_DISTANCE then
		return nil
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.IgnoreWater = false

	local hit = workspace:Raycast(hrp.Position, delta, rayParams)
	if not hit then
		return nil
	end

	local hitPosition = hit.Position
	local arenaZ = character:GetAttribute("ArenaZ")
	if typeof(arenaZ) == "number" and math.abs(hitPosition.Z - arenaZ) > MAX_ARENA_DEPTH_OFFSET then
		return nil
	end

	if (hitPosition - hrp.Position).Magnitude < MIN_GRAPPLE_DISTANCE then
		return nil
	end

	return hitPosition
end

local function canGrapple(player, character)
	if not player or player.Parent ~= Players then return false end
	if not character or player.Character ~= character then return false end
	if character:GetAttribute("InMatch") ~= true then return false end
	if character:GetAttribute("Stunned") == true then return false end
	if character:GetAttribute("IsBlocking") == true then return false end
	if character:GetAttribute("CanAttack") == false then return false end
	return MatchManager.IsPlayerInMatch(player)
end

local function createRope(player, targetPosition)
	local character = player.Character
	if not canGrapple(player, character) then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not hrp then return end

	local now = os.clock()
	local previous = lastRequestAt[player.UserId] or -math.huge
	if now - previous < REQUEST_COOLDOWN then return end
	lastRequestAt[player.UserId] = now

	local resolvedTarget = resolveTarget(character, hrp, targetPosition)
	if not resolvedTarget then return end

	releaseGrapple(player)

	local distance = (hrp.Position - resolvedTarget).Magnitude
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "GrappleAttachment"
	attachment0.Parent = hrp

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TargetAttachment"
	attachment1.Parent = workspace.Terrain
	attachment1.WorldPosition = resolvedTarget

	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = attachment0
	spring.Attachment1 = attachment1
	spring.FreeLength = math.max(2, distance * 0.3)
	spring.Stiffness = 1500
	spring.Damping = 50
	spring.LimitsEnabled = true
	spring.MaxLength = distance
	spring.Parent = hrp

	local beam = Instance.new("Beam")
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Width0 = 0.15
	beam.Width1 = 0.15
	beam.Color = ColorSequence.new(Color3.fromRGB(220, 220, 220))
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = hrp

	local token = (grappleTokens[player.UserId] or 0) + 1
	grappleTokens[player.UserId] = token
	activeGrapples[player.UserId] = {
		Spring = spring,
		Attachment0 = attachment0,
		Attachment1 = attachment1,
		Beam = beam,
		Token = token,
	}

	PlayPrivateSound:FireClient(player, "Grapple")
	local opponent = MatchManager.GetOpponent(player)
	if opponent and opponent:IsA("Player") then
		PlayPrivateSound:FireClient(opponent, "Grapple")
	end

	-- TouchEnd can be missed on mobile. Never leave a spring attached forever.
	task.delay(MAX_GRAPPLE_TIME, function()
		local active = activeGrapples[player.UserId]
		if active and active.Token == token then
			releaseGrapple(player)
		end
	end)
end

GrappleRequest.OnServerEvent:Connect(function(player, targetPosition)
	createRope(player, targetPosition)
end)

ReleaseRequest.OnServerEvent:Connect(function(player)
	releaseGrapple(player)
end)

Players.PlayerRemoving:Connect(function(player)
	releaseGrapple(player)
	lastRequestAt[player.UserId] = nil
	grappleTokens[player.UserId] = nil
end)
