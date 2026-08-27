--!strict
-- Restores SEVER's real spinning scythe projectile for loadout-controlled Scythe Throw.
-- The loadout system remains server-authoritative; this script only restores the original
-- weapon presentation and suppresses the temporary neon-line replacement visual.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local UseMove = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Loadout"):WaitForChild("UseMove") :: RemoteEvent

local THROW_DURATION = 0.38
local THROW_SPINS = 3.25
local START_FORWARD_OFFSET = 1.5
local MAX_SOURCE_DISTANCE = 14

local activeTokens: {[number]: number} = {}

local function isScytheTool(instance: Instance): boolean
	return instance:IsA("Tool")
		and string.find(string.lower(instance.Name), "scythe", 1, true) ~= nil
end

local function findScytheTool(player: Player): Tool?
	local character = player.Character
	if character then
		for _, child in ipairs(character:GetChildren()) do
			if isScytheTool(child) then
				return child :: Tool
			end
		end
		for _, descendant in ipairs(character:GetDescendants()) do
			if isScytheTool(descendant) then
				return descendant :: Tool
			end
		end
	end

	-- Other players' Backpacks are not relied upon; the battle scythe should be equipped.
	if player == localPlayer then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			for _, child in ipairs(backpack:GetChildren()) do
				if isScytheTool(child) then
					return child :: Tool
				end
			end
		end
	end

	return nil
end

local function findHandle(tool: Tool): BasePart?
	local named = tool:FindFirstChild("Handle", true)
	if named and named:IsA("BasePart") then
		return named
	end
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function stripRuntimeObjects(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("JointInstance")
			or descendant:IsA("Constraint")
			or descendant:IsA("RemoteEvent")
			or descendant:IsA("RemoteFunction")
			or descendant:IsA("BindableEvent")
			or descendant:IsA("BindableFunction") then
			descendant:Destroy()
		end
	end
end

type VisualPart = {
	clone: BasePart,
	offset: CFrame,
	source: BasePart,
	oldLocalTransparency: number,
}

local function makeVisual(tool: Tool, handle: BasePart): (Model?, {VisualPart})
	local model = Instance.new("Model")
	model.Name = "SEVER_SpinningScytheThrow"

	local visualParts: {VisualPart} = {}
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local sourcePart = descendant
			local clone = sourcePart:Clone()
			stripRuntimeObjects(clone)
			clone.Name = sourcePart.Name
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.Massless = true
			clone.AssemblyLinearVelocity = Vector3.zero
			clone.AssemblyAngularVelocity = Vector3.zero
			clone.Parent = model

			table.insert(visualParts, {
				clone = clone,
				offset = handle.CFrame:ToObjectSpace(sourcePart.CFrame),
				source = sourcePart,
				oldLocalTransparency = sourcePart.LocalTransparencyModifier,
			})
		end
	end

	if #visualParts == 0 then
		model:Destroy()
		return nil, visualParts
	end

	model.Parent = workspace
	return model, visualParts
end

local function setHeldScytheHidden(parts: {VisualPart}, hidden: boolean)
	for _, item in ipairs(parts) do
		if item.source.Parent then
			item.source.LocalTransparencyModifier = hidden and 1 or item.oldLocalTransparency
		end
	end
end

local function destroyReplacementLine(instance: Instance)
	if instance:IsA("BasePart") and instance.Name == "LoadoutThrowFX" then
		-- This is the temporary neon bar introduced by the loadout rewrite.
		-- Kill it immediately so the real scythe is the only throw projectile shown.
		instance.Transparency = 1
		instance:Destroy()
	end
end

workspace.DescendantAdded:Connect(destroyReplacementLine)
for _, descendant in ipairs(workspace:GetDescendants()) do
	destroyReplacementLine(descendant)
end

local function depthAxisFor(direction: Vector3): Vector3
	if math.abs(direction.X) >= math.abs(direction.Z) then
		return Vector3.zAxis
	end
	return Vector3.xAxis
end

local function playThrow(player: Player, origin: Vector3, direction: Vector3, range: number)
	if direction.Magnitude < 0.01 or range <= 0 then return end
	local tool = findScytheTool(player)
	if not tool then return end
	local handle = findHandle(tool)
	if not handle then return end

	local model, visualParts = makeVisual(tool, handle)
	if not model then return end

	local userId = player.UserId
	activeTokens[userId] = (activeTokens[userId] or 0) + 1
	local token = activeTokens[userId]

	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		model:Destroy()
		return
	end
	flatDirection = flatDirection.Unit

	-- Start at the actual held weapon when it is close to the server-authored origin.
	-- This removes the visual pop from the hand into the projectile path.
	local startPosition = origin + flatDirection * START_FORWARD_OFFSET
	if (handle.Position - origin).Magnitude <= MAX_SOURCE_DISTANCE then
		startPosition = handle.Position
	end
	local endPosition = origin + flatDirection * range
	local heldRotation = handle.CFrame.Rotation
	local depthAxis = depthAxisFor(flatDirection)
	local spinSign = if flatDirection.X + flatDirection.Z >= 0 then -1 else 1

	setHeldScytheHidden(visualParts, true)

	local startedAt = os.clock()
	local connection: RBXScriptConnection? = nil
	local cleaned = false

	local function cleanup()
		if cleaned then return end
		cleaned = true
		if connection and connection.Connected then
			connection:Disconnect()
		end
		if activeTokens[userId] == token then
			setHeldScytheHidden(visualParts, false)
		end
		if model.Parent then
			model:Destroy()
		end
	end

	connection = RunService.RenderStepped:Connect(function()
		if activeTokens[userId] ~= token or not model.Parent then
			cleanup()
			return
		end

		local alpha = math.clamp((os.clock() - startedAt) / THROW_DURATION, 0, 1)
		local position = startPosition:Lerp(endPosition, alpha)
		local angle = alpha * math.pi * 2 * THROW_SPINS * spinSign
		local pivot = CFrame.new(position)
			* CFrame.fromAxisAngle(depthAxis, angle)
			* heldRotation

		for _, item in ipairs(visualParts) do
			if item.clone.Parent then
				item.clone.CFrame = pivot * item.offset
			end
		end

		if alpha >= 1 then
			cleanup()
		end
	end)

	-- Safety cleanup if RenderStepped is interrupted by respawn/teleport.
	task.delay(THROW_DURATION + 0.25, cleanup)
end

UseMove.OnClientEvent:Connect(function(kind: any, moveId: any, userId: any, a: any, b: any, c: any)
	if kind ~= "FX" or moveId ~= "scythe_throw" then return end
	if type(userId) ~= "number" or typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" or type(c) ~= "number" then
		return
	end

	local thrower = Players:GetPlayerByUserId(userId)
	if thrower then
		playThrow(thrower, a, b, c)
	end
end)
