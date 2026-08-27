--!strict
-- Authored scythe VFX controller.
-- Uses the existing ReplicatedStorage assets; it does not generate replacement slash geometry.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local VFXEvent = ReplicatedStorage:WaitForChild("ScytheVFXEvent") :: RemoteEvent
local SlashTemplate = ReplicatedStorage:WaitForChild("scythe slash (NEW)")

local SLASH_FOLLOW_TIME = 0.34
local SLASH_MIN_LIFETIME = 0.65
local SLASH_MAX_LIFETIME = 2.5
local SLASH_DEDUPE = 0.07
local THROW_FLATTEN_ROTATION = CFrame.Angles(math.rad(90), 0, 0)

local lastSlashByUserId: {[number]: number} = {}
local trackedThrows: {[Instance]: any} = {}

local function isScytheTool(instance: Instance): boolean
	return instance:IsA("Tool")
		and string.find(string.lower(instance.Name), "scythe", 1, true) ~= nil
end

local function collectParts(root: Instance): {BasePart}
	local result = {}
	if root:IsA("BasePart") then
		table.insert(result, root)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(result, descendant)
		end
	end
	return result
end

local function makeDriver(root: Instance, visualOnly: boolean)
	local parts = collectParts(root)
	if #parts == 0 then
		return nil
	end

	if visualOnly then
		for _, part in ipairs(parts) do
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
		end
	end

	if root:IsA("Model") then
		local representative = parts[1]
		return {
			getCFrame = function()
				return root:GetPivot()
			end,
			getPosition = function()
				return root:GetPivot().Position
			end,
			getVelocity = function()
				return representative.Parent and representative.AssemblyLinearVelocity or Vector3.zero
			end,
			apply = function(cframe: CFrame)
				if root.Parent then
					root:PivotTo(cframe)
				end
			end,
		}
	end

	if root:IsA("BasePart") then
		return {
			getCFrame = function()
				return root.CFrame
			end,
			getPosition = function()
				return root.Position
			end,
			getVelocity = function()
				return root.AssemblyLinearVelocity
			end,
			apply = function(cframe: CFrame)
				if root.Parent then
					root.CFrame = cframe
				end
			end,
		}
	end

	-- Folder/other container: preserve every authored part's local offset.
	local originPart = parts[1]
	local originCFrame = originPart.CFrame
	local relative = {}
	for _, part in ipairs(parts) do
		relative[part] = originCFrame:ToObjectSpace(part.CFrame)
	end

	return {
		getCFrame = function()
			return originPart.Parent and originPart.CFrame or originCFrame
		end,
		getPosition = function()
			return originPart.Parent and originPart.Position or originCFrame.Position
		end,
		getVelocity = function()
			return originPart.Parent and originPart.AssemblyLinearVelocity or Vector3.zero
		end,
		apply = function(cframe: CFrame)
			for part, offset in pairs(relative) do
				if part.Parent then
					part.CFrame = cframe * offset
				end
			end
		end,
	}
end

local function getSlashTargetCFrame(character: Model): CFrame?
	for _, child in ipairs(character:GetChildren()) do
		if isScytheTool(child) then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				return handle.CFrame
			end
		end
	end

	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if rightHand and rightHand:IsA("BasePart") then
		return rightHand.CFrame
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root.CFrame or nil
end

local function authoredLifetime(root: Instance): number
	local lifetime = SLASH_MIN_LIFETIME
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			lifetime = math.max(lifetime, descendant.Lifetime.Max + SLASH_FOLLOW_TIME)
		elseif descendant:IsA("Trail") then
			lifetime = math.max(lifetime, descendant.Lifetime + SLASH_FOLLOW_TIME)
		end
	end
	return math.clamp(lifetime, SLASH_MIN_LIFETIME, SLASH_MAX_LIFETIME)
end

local function startAuthoredEmitters(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") and not descendant.Enabled then
			local authoredCount = tonumber(descendant:GetAttribute("EmitCount"))
			local count = authoredCount or math.max(1, math.floor(descendant.Rate * 0.12))
			descendant:Emit(count)
		end
	end
end

local function playSlash(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local targetCFrame = getSlashTargetCFrame(character)
	if not targetCFrame then
		return
	end

	local effect = SlashTemplate:Clone()
	effect.Name = "SEVER_AuthoredSlashVFX"
	effect.Parent = workspace

	local driver = makeDriver(effect, true)
	if not driver then
		effect:Destroy()
		return
	end

	driver.apply(targetCFrame)
	startAuthoredEmitters(effect)

	local followConnection
	local startedAt = os.clock()
	followConnection = RunService.RenderStepped:Connect(function()
		if not effect.Parent or not character.Parent then
			followConnection:Disconnect()
			return
		end

		if os.clock() - startedAt >= SLASH_FOLLOW_TIME then
			followConnection:Disconnect()
			return
		end

		local currentTarget = getSlashTargetCFrame(character)
		if currentTarget then
			driver.apply(currentTarget)
		end
	end)

	task.delay(authoredLifetime(effect), function()
		if followConnection and followConnection.Connected then
			followConnection:Disconnect()
		end
		if effect.Parent then
			effect:Destroy()
		end
	end)
end

local function flattenedDirection(cframe: CFrame, velocity: Vector3): Vector3
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	if flatVelocity.Magnitude > 1 then
		return flatVelocity.Unit
	end

	local look = cframe.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.01 then
		return flatLook.Unit
	end

	return Vector3.xAxis
end

local function findThrowRoot(instance: Instance): Instance?
	local current: Instance? = instance
	local candidate: Instance? = nil

	while current and current ~= workspace do
		local lowerName = string.lower(current.Name)
		if string.find(lowerName, "throw", 1, true)
			and string.find(lowerName, "vfx", 1, true) then
			candidate = current
		end
		current = current.Parent
	end

	return candidate
end

local function trackThrow(root: Instance)
	if trackedThrows[root] or not root:IsDescendantOf(workspace) then
		return
	end

	local driver = makeDriver(root, false)
	if not driver then
		return
	end

	trackedThrows[root] = {
		driver = driver,
		direction = flattenedDirection(driver.getCFrame(), driver.getVelocity()),
	}
end

workspace.DescendantAdded:Connect(function(instance)
	local root = findThrowRoot(instance)
	if root then
		task.defer(trackThrow, root)
	end
end)

for _, instance in ipairs(workspace:GetDescendants()) do
	local root = findThrowRoot(instance)
	if root then
		trackThrow(root)
	end
end

-- Apply after normal visual updates so the authored throw effect lies flat like a frisbee
-- even if the original throw script keeps moving the VFX every frame.
RunService:BindToRenderStep("SEVER_FrisbeeThrowVFX", Enum.RenderPriority.Last.Value + 20, function()
	for root, state in pairs(trackedThrows) do
		if not root.Parent or not root:IsDescendantOf(workspace) then
			trackedThrows[root] = nil
			continue
		end

		local driver = state.driver
		local velocity = driver.getVelocity()
		local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		if flatVelocity.Magnitude > 1 then
			state.direction = flatVelocity.Unit
		end

		local position = driver.getPosition()
		local direction = state.direction
		local base = CFrame.lookAt(position, position + direction, Vector3.yAxis)
		driver.apply(base * THROW_FLATTEN_ROTATION)
	end
end)

VFXEvent.OnClientEvent:Connect(function(action, userId)
	if action ~= "Slash" or typeof(userId) ~= "number" then
		return
	end

	local now = os.clock()
	local previous = lastSlashByUserId[userId] or 0
	if now - previous < SLASH_DEDUPE then
		return
	end
	lastSlashByUserId[userId] = now

	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if character then
		playSlash(character)
	end
end)
