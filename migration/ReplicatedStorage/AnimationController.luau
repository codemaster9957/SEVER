-- ReplicatedStorage.AnimationController
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationsFolder = ReplicatedStorage:WaitForChild("Animations")

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

-- Internal class: drives Motor6D.Transform per frame, lerping between keyframes.
local AnimationExecutor = {}
AnimationExecutor.__index = AnimationExecutor

function AnimationExecutor.new(character: Model)
	local self = setmetatable({}, AnimationExecutor)

	self.Character = character
	self.Joints = {}
	self.CurrentTime = 0
	self.Connection = nil
	self.IsPlaying = false

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Motor6D") and desc.Part1 then
			self.Joints[desc.Part1.Name] = desc
		elseif desc:IsA("AnimationConstraint") and desc.Attachment1 then
			local part = desc.Attachment1.Parent
			if part:IsA("BasePart") then
				self.Joints[part.Name] = desc
			end
		end
	end

	return self
end

function AnimationExecutor:Stop()
	self.IsPlaying = false
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

function AnimationExecutor:PlayFromTable(animTable, options)
	if self.Connection then self:Stop() end

	self.CurrentTime = 0
	self.IsPlaying = true

	options = options or {}
	local counterRotateLegs = options.counterRotateLegs ~= false  -- default true

	local timestamps = {}
	for t, _ in pairs(animTable.Timestamps) do
		table.insert(timestamps, t)
	end
	table.sort(timestamps)

	local maxTime = timestamps[#timestamps]
	local isLooping = animTable.Settings.Loop

	self.Connection = RunService.Stepped:Connect(function(_, dt)
		if not self.IsPlaying then return end

		self.CurrentTime += dt

		if self.CurrentTime >= maxTime then
			if isLooping then
				self.CurrentTime %= maxTime
			else
				self.CurrentTime = maxTime
				self:Stop()
				return
			end
		end

		local tStart, tEnd = timestamps[1], timestamps[#timestamps]
		for i = 1, #timestamps - 1 do
			if self.CurrentTime >= timestamps[i] and self.CurrentTime < timestamps[i+1] then
				tStart = timestamps[i]
				tEnd = timestamps[i+1]
				break
			end
		end

		local segmentDuration = tEnd - tStart
		local alpha = (segmentDuration > 0) and (self.CurrentTime - tStart) / segmentDuration or 0

		local dataStart = animTable.Timestamps[tStart]
		local dataEnd = animTable.Timestamps[tEnd]

		for partName, joint in pairs(self.Joints) do
			local cfA = dataStart[partName] or joint.Transform
			local cfB = dataEnd[partName] or cfA
			joint.Transform = cfA:Lerp(cfB, alpha)
		end

		-- Counter-rotate legs against LowerTorso (only when caller asks for it)
		if counterRotateLegs then
			local lowerTorso = self.Joints["LowerTorso"]
			if lowerTorso then
				local lt = lowerTorso.Transform
				local invRot = (lt - lt.Position):Inverse()
				for _, legName in ipairs({"LeftUpperLeg", "RightUpperLeg"}) do
					local legJoint = self.Joints[legName]
					if legJoint then
						legJoint.Transform = invRot * legJoint.Transform
					end
				end
			end
		end
	end)
end

-- Public API
local AnimationController = {}

local executor = nil
local currentCharacter = nil

local function ensureExecutor()
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()

	-- Re-create the executor if the character changed (respawn, R6/R15 swap, etc.)
	if character ~= currentCharacter then
		currentCharacter = character
		executor = AnimationExecutor.new(character)
	end
	return executor
end

-- Reset on respawn so we don't reuse joints from the old character
Players.LocalPlayer.CharacterAdded:Connect(function()
	executor = nil
	currentCharacter = nil
end)

function AnimationController.Play(animationName)
	local animModule = AnimationsFolder:FindFirstChild(animationName)
	if not animModule then
		warn("AnimationController: no animation named", animationName)
		return
	end
	local exec = ensureExecutor()
	local skipLegFix = SKIP_LEG_COUNTERROTATE[animationName] == true
	exec:PlayFromTable(require(animModule), { counterRotateLegs = not skipLegFix })
end

function AnimationController.Stop()
	if executor then executor:Stop() end
end

return AnimationController
