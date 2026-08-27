--!strict
-- Restores SEVER's real spinning scythe projectile for loadout-controlled Scythe Throw.
-- The loadout system remains server-authoritative; this script owns presentation only.
-- The held weapon stays hidden for the entire outbound + return flight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local UseMove = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Loadout"):WaitForChild("UseMove") :: RemoteEvent

local THROW_OUT_DURATION = 0.38
local THROW_SPINS = 3.25
local SPINS_PER_SECOND = THROW_SPINS / THROW_OUT_DURATION
local START_FORWARD_OFFSET = 1.5
local MAX_SOURCE_DISTANCE = 14
local THROW_SAFETY_LIFETIME = 2

local activeTokens: {[number]: number} = {}
local activeThrows: {[number]: any} = {}

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

	local outline = Instance.new("Highlight")
	outline.Name = "SEVER_ThrownScytheOutline"
	outline.Adornee = model
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(255, 35, 45)
	outline.OutlineTransparency = 0
	outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	outline.Parent = model

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

local function cleanupThrow(userId: number, token: number?)
	local state = activeThrows[userId]
	if not state then return end
	if token ~= nil and state.token ~= token then return end

	if state.connection and state.connection.Connected then
		state.connection:Disconnect()
	end
	setHeldScytheHidden(state.visualParts, false)
	if state.model and state.model.Parent then
		state.model:Destroy()
	end
	activeThrows[userId] = nil
end

local function getReturnTargetPosition(player: Player, fallback: Vector3): Vector3
	local tool = findScytheTool(player)
	if tool then
		local handle = findHandle(tool)
		if handle then
			return handle.Position
		end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + Vector3.new(0, 1.5, 0)
	end
	return fallback
end

local function renderVisual(state: any, position: Vector3, now: number)
	state.currentPosition = position
	local spinAngle = (now - state.startedAt) * math.pi * 2 * SPINS_PER_SECOND * state.spinSign
	local pivot = CFrame.new(position)
		* CFrame.fromAxisAngle(state.depthAxis, spinAngle)
		* state.heldRotation

	for _, item in ipairs(state.visualParts) do
		if item.clone.Parent then
			item.clone.CFrame = pivot * item.offset
		end
	end
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
	cleanupThrow(userId)
	activeTokens[userId] = (activeTokens[userId] or 0) + 1
	local token = activeTokens[userId]

	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		model:Destroy()
		return
	end
	flatDirection = flatDirection.Unit

	local startPosition = origin + flatDirection * START_FORWARD_OFFSET
	if (handle.Position - origin).Magnitude <= MAX_SOURCE_DISTANCE then
		startPosition = handle.Position
	end
	local endPosition = origin + flatDirection * range
	local depthAxis = depthAxisFor(flatDirection)
	local spinSign = if flatDirection.X + flatDirection.Z >= 0 then -1 else 1

	local state = {
		token = token,
		player = player,
		model = model,
		visualParts = visualParts,
		heldRotation = handle.CFrame.Rotation,
		depthAxis = depthAxis,
		spinSign = spinSign,
		startPosition = startPosition,
		endPosition = endPosition,
		currentPosition = startPosition,
		startedAt = os.clock(),
		phase = "outbound",
		returnStart = nil,
		returnStartedAt = nil,
		returnDuration = nil,
		connection = nil,
	}
	activeThrows[userId] = state

	setHeldScytheHidden(visualParts, true)

	state.connection = RunService.RenderStepped:Connect(function()
		if activeTokens[userId] ~= token or activeThrows[userId] ~= state or not model.Parent then
			cleanupThrow(userId, token)
			return
		end

		local now = os.clock()
		local position = state.currentPosition

		if state.phase == "outbound" then
			local alpha = math.clamp((now - state.startedAt) / THROW_OUT_DURATION, 0, 1)
			position = state.startPosition:Lerp(state.endPosition, alpha)
			if alpha >= 1 then
				state.phase = "waiting"
			end
		elseif state.phase == "returning" then
			local returnStartedAt = state.returnStartedAt
			local returnDuration = state.returnDuration
			local returnStart = state.returnStart
			if type(returnStartedAt) == "number" and type(returnDuration) == "number" and typeof(returnStart) == "Vector3" then
				local alpha = math.clamp((now - returnStartedAt) / math.max(returnDuration, 0.01), 0, 1)
				local eased = 1 - (1 - alpha) * (1 - alpha)
				local targetPosition = getReturnTargetPosition(player, origin)
				position = returnStart:Lerp(targetPosition, eased)
				if alpha >= 1 then
					renderVisual(state, targetPosition, now)
					cleanupThrow(userId, token)
					return
				end
			end
		end

		renderVisual(state, position, now)
	end)

	task.delay(THROW_SAFETY_LIFETIME, function()
		cleanupThrow(userId, token)
	end)
end

local function startReturn(userId: number, returnPosition: Vector3, returnDuration: number)
	local state = activeThrows[userId]
	if not state then return end
	state.phase = "returning"
	state.returnStart = returnPosition
	state.currentPosition = returnPosition
	state.returnStartedAt = os.clock()
	state.returnDuration = math.max(0.01, returnDuration)
end

UseMove.OnClientEvent:Connect(function(kind: any, moveId: any, userId: any, a: any, b: any, c: any)
	if kind ~= "FX" or type(userId) ~= "number" then return end

	if moveId == "scythe_throw" then
		if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" or type(c) ~= "number" then
			return
		end
		local thrower = Players:GetPlayerByUserId(userId)
		if thrower then
			playThrow(thrower, a, b, c)
		end
	elseif moveId == "scythe_throw_return" then
		if typeof(a) == "Vector3" and type(b) == "number" then
			startReturn(userId, a, b)
		end
	elseif moveId == "scythe_throw_cancel" then
		activeTokens[userId] = (activeTokens[userId] or 0) + 1
		cleanupThrow(userId)
	end
end)
