local StarterPack = game:GetService("StarterPack")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TrainingDummyAnimator = {}
TrainingDummyAnimator.__index = TrainingDummyAnimator

local FALLBACKS = {
	Dash = "rbxassetid://83398771525907",
	Block = "rbxassetid://103952923479033",
	Spin = "rbxassetid://89608736085843",
	Throw = "rbxassetid://95546671624902",
}

local KEYWORDS = {
	Idle = {"idle"},
	Walk = {"walk"},
	Run = {"run"},
	Jump = {"jump"},
	Fall = {"fall", "freefall"},
	Slash = {"slash", "attack", "swing"},
	Dash = {"dash"},
	Grapple = {"grapple", "hook"},
	Block = {"block", "parry"},
	Throw = {"throw"},
	Spin = {"spin"},
	SoulReap = {"soul reap", "soul", "reap"},
}

local LOCOMOTION_NAMES = {
	Idle = true,
	Walk = true,
	Run = true,
	Jump = true,
	Fall = true,
}

local function lower(value)
	return string.lower(tostring(value or ""))
end

local function validAnimationId(animationId)
	return type(animationId) == "string"
		and animationId ~= ""
		and animationId ~= "rbxassetid://0"
end

function TrainingDummyAnimator.SelectAnimationId(candidates, keywords, fallback)
	local bestId = nil
	local bestScore = 0

	for _, candidate in ipairs(candidates or {}) do
		local name = lower(candidate.Name)
		local animationId = candidate.AnimationId
		if validAnimationId(animationId) then
			local score = 0
			for _, keyword in ipairs(keywords or {}) do
				if string.find(name, lower(keyword), 1, true) then
					score += 1
				end
			end
			if score > bestScore then
				bestScore = score
				bestId = animationId
			end
		end
	end

	if bestId then
		return bestId
	end
	if validAnimationId(fallback) then
		return fallback
	end
	return nil
end

local function collectAnimationCandidates(dummy)
	local candidates = {}
	local seen = {}

	local function collect(root)
		if not root then return end
		if root:IsA("Animation") then
			local id = root.AnimationId
			local key = root.Name .. "|" .. tostring(id)
			if not seen[key] and validAnimationId(id) then
				seen[key] = true
				table.insert(candidates, {Name = root.Name, AnimationId = id})
			end
		end
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("Animation") then
				local id = descendant.AnimationId
				local key = descendant.Name .. "|" .. tostring(id)
				if not seen[key] and validAnimationId(id) then
					seen[key] = true
					table.insert(candidates, {Name = descendant.Name, AnimationId = id})
				end
			end
		end
	end

	collect(dummy)
	collect(StarterPack)
	collect(ReplicatedStorage)
	return candidates
end

local function ensureAnimator(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Name = "TrainingDummyAnimator"
		animator.Parent = humanoid
	end
	return animator
end

local function loadTrack(animator, animationId, priority, looped)
	if not animationId then return nil end
	local animation = Instance.new("Animation")
	animation.Name = "TrainingDummyRuntimeAnimation"
	animation.AnimationId = animationId

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok or not track then
		return nil
	end

	track.Priority = priority
	track.Looped = looped == true
	return track
end

function TrainingDummyAnimator.new(dummy)
	local humanoid = dummy and dummy:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local self = setmetatable({}, TrainingDummyAnimator)
	self.dummy = dummy
	self.humanoid = humanoid
	self.animator = ensureAnimator(humanoid)
	self.tracks = {}
	self.connections = {}
	self.destroyed = false
	self.locomotionEnabled = true
	self.currentLocomotion = nil
	self.currentAction = nil
	self.lastRunningSpeed = 0

	local candidates = collectAnimationCandidates(dummy)

	for name, keywords in pairs(KEYWORDS) do
		local fallback = FALLBACKS[name]
		local animationId = TrainingDummyAnimator.SelectAnimationId(candidates, keywords, fallback)
		local locomotion = LOCOMOTION_NAMES[name] == true
		local priority = locomotion and Enum.AnimationPriority.Movement or Enum.AnimationPriority.Action2
		if name == "Idle" then
			priority = Enum.AnimationPriority.Idle
		end
		self.tracks[name] = loadTrack(self.animator, animationId, priority, name == "Idle" or name == "Walk" or name == "Run" or name == "Fall")
	end

	local function connect(signal, fn)
		local connection = signal:Connect(fn)
		table.insert(self.connections, connection)
	end

	connect(humanoid.Running, function(speed)
		if self.destroyed then return end
		self.lastRunningSpeed = speed
		if not self.locomotionEnabled then return end
		if humanoid:GetState() == Enum.HumanoidStateType.Freefall then return end
		if speed > 13 then
			self:_playLocomotion("Run")
		elseif speed > 0.5 then
			self:_playLocomotion("Walk")
		else
			self:_playLocomotion("Idle")
		end
	end)

	connect(humanoid.StateChanged, function(_, newState)
		if self.destroyed or not self.locomotionEnabled then return end
		if newState == Enum.HumanoidStateType.Jumping then
			self:_playLocomotion("Jump")
		elseif newState == Enum.HumanoidStateType.Freefall then
			self:_playLocomotion("Fall")
		elseif newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.RunningNoPhysics then
			if self.lastRunningSpeed > 13 then
				self:_playLocomotion("Run")
			elseif self.lastRunningSpeed > 0.5 then
				self:_playLocomotion("Walk")
			else
				self:_playLocomotion("Idle")
			end
		end
	end)

	self:_playLocomotion("Idle")
	return self
end

function TrainingDummyAnimator:_stopLocomotion(exceptName)
	for name in pairs(LOCOMOTION_NAMES) do
		if name ~= exceptName then
			local track = self.tracks[name]
			if track and track.IsPlaying then
				track:Stop(0.12)
			end
		end
	end
end

function TrainingDummyAnimator:_playLocomotion(name)
	if self.destroyed or not self.locomotionEnabled then return false end
	local track = self.tracks[name]
	if not track then return false end
	if self.currentLocomotion == name and track.IsPlaying then return true end
	self:_stopLocomotion(name)
	track:Play(0.12)
	self.currentLocomotion = name
	return true
end

function TrainingDummyAnimator:PlayAction(name, speed)
	if self.destroyed then return false end
	local track = self.tracks[name]
	if not track then return false end

	if self.currentAction and self.currentAction ~= track and self.currentAction.IsPlaying then
		self.currentAction:Stop(0.07)
	end
	self.currentAction = track
	track.Looped = false
	track:Play(0.07)
	if type(speed) == "number" and speed > 0 then
		track:AdjustSpeed(speed)
	else
		track:AdjustSpeed(1)
	end
	return true
end

function TrainingDummyAnimator:SetLocomotionEnabled(enabled)
	self.locomotionEnabled = enabled == true
	if not self.locomotionEnabled then
		self:_stopLocomotion(nil)
		self.currentLocomotion = nil
	else
		if self.lastRunningSpeed > 13 then
			self:_playLocomotion("Run")
		elseif self.lastRunningSpeed > 0.5 then
			self:_playLocomotion("Walk")
		else
			self:_playLocomotion("Idle")
		end
	end
end

function TrainingDummyAnimator:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(self.connections)
	for _, track in pairs(self.tracks) do
		if track then
			pcall(function()
				track:Stop(0.05)
				track:Destroy()
			end)
		end
	end
	table.clear(self.tracks)
end

return TrainingDummyAnimator
