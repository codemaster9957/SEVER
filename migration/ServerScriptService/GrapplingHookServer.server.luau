local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GrappleEvents = ReplicatedStorage:WaitForChild("GrappleEvents")
local GrappleRequest = GrappleEvents:WaitForChild("GrappleRequest")
local ReleaseRequest = GrappleEvents:WaitForChild("ReleaseRequest")
local PlayPrivateSound = ReplicatedStorage:WaitForChild("PlayPrivateSound")
local MatchManager = require(game:GetService("ServerScriptService"):WaitForChild("MatchManager"))

local activeGrapples = {}

local function createRope(player, targetPosition)
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- Clean up existing grapple
	if activeGrapples[player.UserId] then
		local data = activeGrapples[player.UserId]
		if data.Spring then data.Spring:Destroy() end
		if data.Attachment0 then data.Attachment0:Destroy() end
		if data.Attachment1 then data.Attachment1:Destroy() end
		if data.Beam then data.Beam:Destroy() end
		activeGrapples[player.UserId] = nil
	end
	
	-- Play sound for the players in battle
	PlayPrivateSound:FireClient(player, "Grapple")
	local opponent = MatchManager.GetOpponent(player)
	if opponent and opponent:IsA("Player") then
		PlayPrivateSound:FireClient(opponent, "Grapple")
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "GrappleAttachment"
	attachment0.Parent = hrp

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TargetAttachment"
	attachment1.Parent = workspace.Terrain
	attachment1.WorldPosition = targetPosition

	-- Use a SpringConstraint for smoother, elastic movement that maintains momentum better
	local spring = Instance.new("SpringConstraint")
	spring.Attachment0 = attachment0
	spring.Attachment1 = attachment1
	spring.FreeLength = (hrp.Position - targetPosition).Magnitude * 0.3 -- Pull in slightly
	spring.Stiffness = 1500
	spring.Damping = 50
	spring.LimitsEnabled = true
	spring.MaxLength = (hrp.Position - targetPosition).Magnitude
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

	activeGrapples[player.UserId] = {
		Spring = spring,
		Attachment0 = attachment0,
		Attachment1 = attachment1,
		Beam = beam
	}
end

local function releaseGrapple(player)
	local data = activeGrapples[player.UserId]
	if data then
		if data.Spring then data.Spring:Destroy() end
		if data.Attachment0 then data.Attachment0:Destroy() end
		if data.Attachment1 then data.Attachment1:Destroy() end
		if data.Beam then data.Beam:Destroy() end
		activeGrapples[player.UserId] = nil
	end
end

GrappleRequest.OnServerEvent:Connect(function(player, targetPosition)
	createRope(player, targetPosition)
end)

ReleaseRequest.OnServerEvent:Connect(function(player)
	releaseGrapple(player)
end)

game:GetService("Players").PlayerRemoving:Connect(function(player)
	releaseGrapple(player)
end)
