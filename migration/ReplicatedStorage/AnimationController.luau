-- ReplicatedStorage.AnimationController
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AnimationsFolder = ReplicatedStorage:WaitForChild("Animations")

local IS_TOUCH_DEVICE = UserInputService.TouchEnabled
local MOBILE_UPDATE_STEP = 1 / 30

-- Animations in this set play WITHOUT leg counter-rotation, because their leg
-- keyframes are intentional (kicks, sits, swims, etc.). Everything else gets the
-- counter-rotation applied to keep legs vertical when the torso rotates.
local SKIP_LEG_COUNTERROTATE = {
	["Leg Kick Animation"] = true,
	["Double Jump Backflip Animation"] = true,
	["Driving Steering Animation"] = true,
	["Flying Animation"] = true,
	["Gun Shooting Position Animation"] = true,
	["Injured Hurting Animation"] = true,
	["Injured Walk Animation"] = true,
	["Item Pickup Animation"] = true,
	["Level Up Celebration Animation"] = true,
	["Seating Animation"] = true,
	["Sliding Animation"] = true,
	["Sneak Walk Animation"] = true,
	["Spell Cast Fireball Animation"] = true,
	["Swimming Animation"] = true,
	["Zombie Walk Animation"] = true,
}

-- Internal class: drives Motor6D.Transform using interpolation between authored keyframes.
local AnimationExecutor = {}
AnimationExecutor.__index = AnimationExecutor

function AnimationExecutor.new(character: Model)
	local self = setmetatable({}, AnimationExecutor)

	self.Character = character
	self.Joints = {}
	self.CurrentTime = 0
	self.Connection = nil
	self.IsPlaying = false
	self.UpdateAccumulator = 0

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Motor6D") and desc.Part1 then
			self.Joints[desc.Part1.Name] = desc
		elseif desc:IsA("AnimationConstraint") and desc.Attachment1 then
			local part = desc.Attachment1.Parent
			if part and part:IsA("BasePart") then
				self.Joints[part.Name] = desc
			end
		end
	end

	return self
end

function AnimationExecutor:Stop()
	self.IsPlaying = false
	self.UpdateAccumulator = 0
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

function AnimationExecutor:PlayFromTable(animTable, options)
	if self.Connection then self:Stop() end

	if type(animTable) ~= "table" or type(animTable.Timestamps) ~= "table" then
		warn("AnimationController: malformed animation table (missing Timestamps)")
		return false
	end

	local timestamps = {}
	for timestamp in pairs(animTable.Timestamps) do
		if type(timestamp) == "number" then
			table.insert(timestamps, timestamp)
		end
	end
	table.sort(timestamps)

	if #timestamps == 0 then
		warn("AnimationController: animation contains no numeric timestamps")
		return false
	end

	local maxTime = timestamps[#timestamps]
	if type(maxTime) ~= "number" or maxTime < 0 then
		warn("AnimationController: animation has an invalid duration")
		return false
	end

	local settings = type(animTable.Settings) == "table" and animTable.Settings or {}
	local isLooping = settings.Loop == true

	self.CurrentTime = 0
	self.UpdateAccumulator = 0
	self.IsPlaying = true

	options = options or {}
	local counterRotateLegs = options.counterRotateLegs ~= false

	self.Connection = RunService.Stepped:Connect(function(_, dt)
		if not self.IsPlaying then return end

		-- The custom Motor6D executor is CPU-heavy on phones. Keep desktop at native
		-- frame rate, while touch devices evaluate at a stable ~30 Hz.
		if IS_TOUCH_DEVICE then
			self.UpdateAccumulator += dt
			if self.UpdateAccumulator < MOBILE_UPDATE_STEP then
				return
			end
			dt = self.UpdateAccumulator
			self.UpdateAccumulator = 0
		end

		self.CurrentTime += dt

		if maxTime == 0 then
			self.CurrentTime = 0
			if not isLooping then
				self:Stop()
			end
			return
	end

		if self.CurrentTime >= maxTime then
			if isLooping then
				self.CurrentTime %= maxTime
			else
				self.CurrentTime = maxTime
			end
		end

		local tStart, tEnd = timestamps[1], timestamps[#timestamps]
		for i = 1, #timestamps - 1 do
			if self.CurrentTime >= timestamps[i] and self.CurrentTime < timestamps[i + 1] then
				tStart = timestamps[i]
				tEnd = timestamps[i + 1]
				break
			end
		end

		local dataStart = animTable.Timestamps[tStart]
		local dataEnd = animTable.Timestamps[tEnd]
		if type(dataStart) ~= "table" then
			warn("AnimationController: malformed keyframe at", tStart)
			self:Stop()
			return
		end
		if type(dataEnd) ~= "table" then
			dataEnd = dataStart
		end

		local segmentDuration = tEnd - tStart
		local alpha = segmentDuration > 0 and math.clamp((self.CurrentTime - tStart) / segmentDuration, 0, 1) or 0

		for partName, joint in pairs(self.Joints) do
			if not joint.Parent then
				self.Joints[partName] = nil
				continue
			end

			local cfA = dataStart[partName]
			if typeof(cfA) ~= "CFrame" then
				cfA = joint.Transform
			end

			local cfB = dataEnd[partName]
			if typeof(cfB) ~= "CFrame" then
				cfB = cfA
			end

			joint.Transform = cfA:Lerp(cfB, alpha)
		end

		if counterRotateLegs then
			local lowerTorso = self.Joints["LowerTorso"]
			if lowerTorso and lowerTorso.Parent then
				local lt = lowerTorso.Transform
				local invRot = (lt - lt.Position):Inverse()
				for _, legName in ipairs({"LeftUpperLeg", "RightUpperLeg"}) do
					local legJoint = self.Joints[legName]
					if legJoint and legJoint.Parent then
						legJoint.Transform = invRot * legJoint.Transform
					end
				end
			end
		end

		if not isLooping and self.CurrentTime >= maxTime then
			self:Stop()
		end
	end)

	return true
end

local AnimationController = {}
local executor = nil
local currentCharacter = nil

local function ensureExecutor()
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()

	if character ~= currentCharacter then
		if executor then executor:Stop() end
		currentCharacter = character
		executor = AnimationExecutor.new(character)
	end
	return executor
end

Players.LocalPlayer.CharacterAdded:Connect(function()
	if executor then executor:Stop() end
	executor = nil
	currentCharacter = nil
end)

function AnimationController.Play(animationName)
	local animModule = AnimationsFolder:FindFirstChild(animationName)
	if not animModule or not animModule:IsA("ModuleScript") then
		warn("AnimationController: no animation named", animationName)
		return false
	end

	local ok, animTable = pcall(require, animModule)
	if not ok then
		warn("AnimationController: failed to load", animationName, animTable)
		return false
	end

	local exec = ensureExecutor()
	local skipLegFix = SKIP_LEG_COUNTERROTATE[animationName] == true
	return exec:PlayFromTable(animTable, { counterRotateLegs = not skipLegFix })
end

function AnimationController.Stop()
	if executor then executor:Stop() end
end

return AnimationController
