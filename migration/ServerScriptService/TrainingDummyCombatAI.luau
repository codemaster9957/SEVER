local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local TrainingDummyAI = require(script.Parent:WaitForChild("TrainingDummyAI"))

local VFXEvent = ReplicatedStorage:WaitForChild("ScytheVFXEvent")

local CombatAI = {}
CombatAI.__index = CombatAI

local AI_TICK = 0.08
local OBSERVATION_TICK = 0.45
local SLASH_RANGE = 7.25
local SPIN_RANGE = 8.5
local MAX_THROW_RANGE = 38
local MAX_GRAPPLE_RANGE = 42

local function isAlive(model)
	if not model or not model.Parent then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function getRoot(model)
	return model and model:FindFirstChild("HumanoidRootPart")
end

local function cooldownReady(self, name)
	return os.clock() >= (self.cooldowns[name] or 0)
end

local function setCooldown(self, name, duration)
	self.cooldowns[name] = os.clock() + duration
end

local function safeDirectionX(fromPosition, toPosition)
	local delta = toPosition.X - fromPosition.X
	if math.abs(delta) < 0.05 then
		return 0
	end
	return delta > 0 and 1 or -1
end

local function clearDefense(model)
	if not model then return end
	model:SetAttribute("IsBlocking", false)
	model:SetAttribute("IsParrying", false)
end

function CombatAI.new(player, battle, level, memory)
	local self = setmetatable({}, CombatAI)
	self.player = player
	self.battle = battle
	self.dummy = battle.dummyClone
	self.humanoid = battle.dummyHumanoid
	self.root = getRoot(self.dummy)
	self.level = 1
	self.capabilities = TrainingDummyAI.GetCapabilities(1)
	self.memory = memory
	self.cooldowns = {}
	self.destroyed = false
	self.accumulator = 0
	self.observationAccumulator = 0
	self.lastDummyHealth = self.humanoid and self.humanoid.Health or 100
	self.lastPlayerAttackUntil = 0
	self.lastDashObservation = 0
	self.pendingDefense = false
	self.arenaZ = battle.spawn2 and battle.spawn2.Position.Z or (self.root and self.root.Position.Z or 0)
	self.adaptiveProfile = TrainingDummyAI.GetAdaptiveProfile(memory)
	self:SetLevel(level)

	self.connection = RunService.Heartbeat:Connect(function(dt)
		self:_heartbeat(dt)
	end)

	return self
end

function CombatAI:SetLevel(level)
	self.level = TrainingDummyAI.ClampLevel(level)
	self.capabilities = TrainingDummyAI.GetCapabilities(self.level)
	self.adaptiveProfile = TrainingDummyAI.GetAdaptiveProfile(self.memory)

	if self.dummy then
		self.dummy:SetAttribute("TrainingLevel", self.level)
	end

	clearDefense(self.dummy)
	self.pendingDefense = false

	if self.humanoid then
		if self.capabilities.Move then
			self.humanoid.WalkSpeed = self.level >= 10 and 18 or 16
			self.humanoid.JumpPower = 50
			self.humanoid.AutoRotate = true
		else
			self.humanoid.WalkSpeed = 0
			self.humanoid.JumpPower = 0
			self.humanoid.AutoRotate = false
			self.humanoid:Move(Vector3.zero, false)
		end
	end

	if self.root and not self.capabilities.Move then
		self.root.AssemblyLinearVelocity = Vector3.new(0, self.root.AssemblyLinearVelocity.Y, 0)
	end
end

function CombatAI:Destroy()
	if self.destroyed then return end
	self.destroyed = true
	if self.connection and self.connection.Connected then
		self.connection:Disconnect()
	end
	clearDefense(self.dummy)
	if self.dummy then
		self.dummy:SetAttribute("AttackActiveUntil", 0)
	end
end

function CombatAI:_validCombatants()
	if self.destroyed or not self.player or not self.player.Parent then
		return nil
	end
	if not isAlive(self.dummy) then
		return nil
	end
	local character = self.player.Character
	if not isAlive(character) then
		return nil
	end
	local playerRoot = getRoot(character)
	local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
	if not playerRoot or not playerHumanoid or not self.root or not self.root.Parent then
		return nil
	end
	return character, playerRoot, playerHumanoid
end

function CombatAI:_distanceToPlayer(playerRoot)
	return math.abs(playerRoot.Position.X - self.root.Position.X)
end

function CombatAI:_recordAttackResult(result)
	if self.level ~= 10 or type(self.memory) ~= "table" then
		return
	end
	TrainingDummyAI.RecordObservation(self.memory, "DummyAttackAttempt")
	if result and (result.blocked or result.parried) then
		TrainingDummyAI.RecordObservation(self.memory, "BlockedDummyAttack")
	elseif result and result.dodged then
		TrainingDummyAI.RecordObservation(self.memory, "DodgedDummyAttack")
	end
	self.adaptiveProfile = TrainingDummyAI.GetAdaptiveProfile(self.memory)
end

function CombatAI:_damagePlayer(playerHumanoid, damage, knockback)
	local result = DamageHandler.ApplyDamage(playerHumanoid, damage, nil)
	self:_recordAttackResult(result)

	if result and (result.damage or 0) > 0 and knockback and knockback > 0 then
		local playerRoot = getRoot(playerHumanoid.Parent)
		if playerRoot and self.root then
			local direction = safeDirectionX(self.root.Position, playerRoot.Position)
			local velocity = playerRoot.AssemblyLinearVelocity
			playerRoot.AssemblyLinearVelocity = Vector3.new(direction * knockback, math.max(velocity.Y, 8), 0)
		end
	end

	return result
end

function CombatAI:_playVFX(action, ...)
	if self.player and self.player.Parent and self.dummy and self.dummy.Parent then
		VFXEvent:FireClient(self.player, action, self.dummy, ...)
	end
end

function CombatAI:_slash(playerRoot, playerHumanoid)
	if not cooldownReady(self, "Slash") then return false end
	local distance = self:_distanceToPlayer(playerRoot)
	if distance > SLASH_RANGE then return false end

	local cooldown = 1.25
	if self.level >= 5 then cooldown = 0.92 end
	if self.level >= 9 then cooldown = 0.72 end
	if self.level == 10 then
		cooldown = 0.62 - (self.adaptiveProfile.AdaptationStrength - 0.62) * 0.16
	end
	setCooldown(self, "Slash", cooldown)
	self.dummy:SetAttribute("AttackActiveUntil", os.clock() + 0.32)
	self:_playVFX("NPCSlash")

	task.delay(0.13, function()
		if self.destroyed then return end
		local _, currentRoot, currentHumanoid = self:_validCombatants()
		if currentRoot and currentHumanoid and self:_distanceToPlayer(currentRoot) <= SLASH_RANGE + 0.75 then
			self:_damagePlayer(currentHumanoid, self.level >= 9 and 10 or 8, 42)
		end
	end)
	return true
end

function CombatAI:_dash(playerRoot, away)
	if not self.capabilities.Dash or not cooldownReady(self, "Dash") then return false end
	local direction = safeDirectionX(self.root.Position, playerRoot.Position)
	if direction == 0 then direction = 1 end
	if away then direction = -direction end

	local cooldown = self.level >= 9 and 1.65 or (self.level >= 5 and 2.05 or 2.7)
	if self.level == 10 then cooldown = 1.35 end
	setCooldown(self, "Dash", cooldown)

	local speed = self.level == 10 and 92 or (self.level >= 9 and 82 or 70)
	local velocity = self.root.AssemblyLinearVelocity
	self.root.AssemblyLinearVelocity = Vector3.new(direction * speed, velocity.Y, 0)
	return true
end

function CombatAI:_grapple(playerRoot)
	if not self.capabilities.Grapple or not cooldownReady(self, "Grapple") then return false end
	local distance = self:_distanceToPlayer(playerRoot)
	if distance < 12 or distance > MAX_GRAPPLE_RANGE then return false end

	setCooldown(self, "Grapple", self.level >= 9 and 2.9 or (self.level >= 5 and 3.6 or 4.8))

	local dummyAttachment = Instance.new("Attachment")
	dummyAttachment.Name = "TrainingGrappleOrigin"
	dummyAttachment.Parent = self.root
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Name = "TrainingGrappleTarget"
	targetAttachment.Parent = playerRoot
	local beam = Instance.new("Beam")
	beam.Name = "TrainingGrappleBeam"
	beam.Attachment0 = dummyAttachment
	beam.Attachment1 = targetAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.08
	beam.Width1 = 0.04
	beam.Parent = dummyAttachment
	Debris:AddItem(dummyAttachment, 0.34)
	Debris:AddItem(targetAttachment, 0.34)

	local direction = safeDirectionX(self.root.Position, playerRoot.Position)
	self.root.AssemblyLinearVelocity = Vector3.new(direction * 88, 14, 0)
	return true
end

function CombatAI:_blockOrParry(playerCharacter)
	if not self.capabilities.Block or self.pendingDefense or not cooldownReady(self, "Defense") then
		return false
	end

	local attackUntil = playerCharacter:GetAttribute("AttackActiveUntil")
	if typeof(attackUntil) ~= "number" or attackUntil <= os.clock() then
		return false
	end

	self.pendingDefense = true
	local reaction = 0.24
	if self.level >= 5 then reaction = 0.17 end
	if self.level >= 9 then reaction = 0.115 end
	if self.level == 10 then
		reaction = math.max(0.075, 0.13 - self.adaptiveProfile.AdaptationStrength * 0.055)
	end

	task.delay(reaction, function()
		self.pendingDefense = false
		if self.destroyed or not isAlive(self.dummy) or not isAlive(playerCharacter) then return end
		local currentAttackUntil = playerCharacter:GetAttribute("AttackActiveUntil")
		if typeof(currentAttackUntil) ~= "number" or currentAttackUntil <= os.clock() then return end

		local useParry = self.level >= 9 and math.random() < (self.level == 10 and 0.58 or 0.32)
		self.dummy:SetAttribute(useParry and "IsParrying" or "IsBlocking", true)
		setCooldown(self, "Defense", self.level == 10 and 0.55 or 0.8)
		task.delay(useParry and 0.13 or 0.24, function()
			if self.dummy then
				clearDefense(self.dummy)
			end
		end)
	end)
	return true
end

function CombatAI:_throw(playerRoot, playerHumanoid)
	if not self.capabilities.Throw or not cooldownReady(self, "Throw") then return false end
	local distance = self:_distanceToPlayer(playerRoot)
	if distance < 9 or distance > MAX_THROW_RANGE then return false end

	setCooldown(self, "Throw", self.level >= 9 and 2.8 or 4.0)
	self.dummy:SetAttribute("AttackActiveUntil", os.clock() + 0.4)

	local travelTime = math.clamp(distance / 95, 0.09, 0.42)
	local prediction = self.level >= 9 and math.min(0.32, travelTime) or math.min(0.12, travelTime)
	if self.level == 10 then
		prediction = math.min(0.38, travelTime + self.adaptiveProfile.DodgeRate * 0.12)
	end
	local predictedX = playerRoot.Position.X + playerRoot.AssemblyLinearVelocity.X * prediction
	local direction = safeDirectionX(self.root.Position, Vector3.new(predictedX, playerRoot.Position.Y, playerRoot.Position.Z))
	self:_playVFX("NPCThrow", direction, travelTime)

	task.delay(travelTime, function()
		if self.destroyed then return end
		local _, currentRoot, currentHumanoid = self:_validCombatants()
		if not currentRoot or not currentHumanoid then return end
		if math.abs(currentRoot.Position.X - predictedX) <= 4.5 then
			self:_damagePlayer(currentHumanoid, self.level >= 9 and 13 or 11, 55)
		else
			if self.level == 10 then
				TrainingDummyAI.RecordObservation(self.memory, "DodgedDummyAttack")
			end
		end
	end)
	return true
end

function CombatAI:_spin(playerRoot, playerHumanoid)
	if not self.capabilities.Spin or not cooldownReady(self, "Spin") then return false end
	local distance = self:_distanceToPlayer(playerRoot)
	if distance > SPIN_RANGE then return false end

	setCooldown(self, "Spin", self.level >= 9 and 3.2 or 4.8)
	self.dummy:SetAttribute("AttackActiveUntil", os.clock() + 0.7)
	self:_playVFX("NPCSpin")

	task.delay(0.24, function()
		if self.destroyed then return end
		local _, currentRoot, currentHumanoid = self:_validCombatants()
		if currentRoot and currentHumanoid and self:_distanceToPlayer(currentRoot) <= SPIN_RANGE + 0.75 then
			self:_damagePlayer(currentHumanoid, self.level >= 9 and 14 or 11, 65)
		end
	end)
	return true
end

function CombatAI:_soulReap(playerRoot, playerHumanoid)
	if not self.capabilities.SoulReap or not cooldownReady(self, "SoulReap") then return false end
	local distance = self:_distanceToPlayer(playerRoot)
	if distance < 5 or distance > 21 then return false end

	setCooldown(self, "SoulReap", self.level >= 9 and 5.4 or 7.0)
	self.dummy:SetAttribute("AttackActiveUntil", os.clock() + 0.42)
	local direction = safeDirectionX(self.root.Position, playerRoot.Position)
	self:_playVFX("NPCSoulReap", direction)
	self.root.AssemblyLinearVelocity = Vector3.new(direction * (self.level == 10 and 145 or 125), 0, 0)

	task.delay(0.14, function()
		if self.destroyed then return end
		local _, currentRoot, currentHumanoid = self:_validCombatants()
		if currentRoot and currentHumanoid and self:_distanceToPlayer(currentRoot) <= 6.25 then
			self:_damagePlayer(currentHumanoid, self.level >= 9 and 20 or 17, 78)
		end
	end)
	return true
end

function CombatAI:_observe(playerCharacter, playerRoot)
	if self.level ~= 10 or type(self.memory) ~= "table" then return end

	local distance = self:_distanceToPlayer(playerRoot)
	TrainingDummyAI.RecordObservation(self.memory, "DistanceSample", distance)
	if distance <= 8 then
		TrainingDummyAI.RecordObservation(self.memory, "AggressiveSample")
	end

	local dashSpeed = math.abs(playerRoot.AssemblyLinearVelocity.X)
	if dashSpeed >= 70 and os.clock() - self.lastDashObservation >= 0.55 then
		self.lastDashObservation = os.clock()
		TrainingDummyAI.RecordObservation(self.memory, "DashBurst")
	end

	local health = self.humanoid.Health
	if health < self.lastDummyHealth - 0.1 then
		TrainingDummyAI.RecordObservation(self.memory, distance <= 10 and "CloseHit" or "RangedHit")
	end
	self.lastDummyHealth = health
	self.adaptiveProfile = TrainingDummyAI.GetAdaptiveProfile(self.memory)
end

function CombatAI:_move(playerRoot)
	if not self.capabilities.Move then return end

	local distance = self:_distanceToPlayer(playerRoot)
	local toward = safeDirectionX(self.root.Position, playerRoot.Position)
	local desiredRange = self.capabilities.Advanced and 7.5 or 5.5
	if self.level == 10 then
		if self.adaptiveProfile.AggressionRate > 0.52 or self.adaptiveProfile.CloseHitRate > 0.58 then
			desiredRange = 9.0
		elseif self.adaptiveProfile.AverageDistance > 14 then
			desiredRange = 6.0
		else
			desiredRange = 7.2
		end
	end

	local moveX = 0
	if distance > desiredRange + 1.1 then
		moveX = toward
	elseif self.capabilities.Advanced and distance < desiredRange - 1.2 then
		moveX = -toward
	end
	self.humanoid:Move(Vector3.new(moveX, 0, 0), false)

	local velocity = self.root.AssemblyLinearVelocity
	self.root.AssemblyLinearVelocity = Vector3.new(velocity.X, velocity.Y, 0)
	local zError = self.arenaZ - self.root.Position.Z
	if math.abs(zError) > 0.8 then
		self.root.CFrame = self.root.CFrame + Vector3.new(0, 0, math.clamp(zError, -0.4, 0.4))
	end
end

function CombatAI:_decide(playerCharacter, playerRoot, playerHumanoid)
	local distance = self:_distanceToPlayer(playerRoot)
	local playerAttacking = typeof(playerCharacter:GetAttribute("AttackActiveUntil")) == "number"
		and playerCharacter:GetAttribute("AttackActiveUntil") > os.clock()
	local playerBlocking = playerCharacter:GetAttribute("IsBlocking") == true
	local playerDodging = playerCharacter:GetAttribute("IsDashInvulnerable") == true

	if self.capabilities.Block and playerAttacking and distance <= 9.5 then
		self:_blockOrParry(playerCharacter)
		if self.capabilities.Advanced and cooldownReady(self, "Dash") and math.random() < 0.24 then
			self:_dash(playerRoot, true)
		end
	end

	if self.level == 10 then
		local adaptation = self.adaptiveProfile

		-- A player who repeatedly blocks gets baited rather than fed free blocks.
		if playerBlocking and adaptation.BlockRate > 0.28 then
			if distance > 11 and self.capabilities.Grapple and math.random() < adaptation.AdaptationStrength then
				if self:_grapple(playerRoot) then return end
			end
			self:_move(playerRoot)
			return
		end

		-- A player who relies on dash invulnerability is pressured after the dash,
		-- not hit by impossible input-reading during it.
		if playerDodging and adaptation.DodgeRate > 0.2 then
			if distance < 9 then
				self:_dash(playerRoot, true)
			end
			return
		end

		if adaptation.AggressionRate > 0.5 and distance <= SPIN_RANGE and math.random() < adaptation.AdaptationStrength then
			if self:_spin(playerRoot, playerHumanoid) then return end
		end

		if adaptation.AverageDistance > 13 and distance >= 12 then
			if math.random() < 0.55 and self:_grapple(playerRoot) then return end
			if self:_throw(playerRoot, playerHumanoid) then return end
		end
	end

	if self.capabilities.SoulReap and self.level >= 9 and distance >= 6 and distance <= 18 then
		if math.random() < (self.level == 10 and 0.23 or 0.13) and self:_soulReap(playerRoot, playerHumanoid) then return end
	end

	if self.capabilities.Spin and distance <= SPIN_RANGE then
		local chance = self.level >= 9 and 0.3 or 0.17
		if math.random() < chance and self:_spin(playerRoot, playerHumanoid) then return end
	end

	if self.capabilities.Throw and distance >= 10 then
		local chance = self.level >= 9 and 0.36 or 0.22
		if math.random() < chance and self:_throw(playerRoot, playerHumanoid) then return end
	end

	if self.capabilities.Grapple and distance >= 14 then
		local chance = self.level >= 9 and 0.31 or 0.18
		if math.random() < chance and self:_grapple(playerRoot) then return end
	end

	if self.capabilities.Dash and distance > 9 then
		local chance = self.capabilities.Advanced and 0.34 or 0.2
		if math.random() < chance and self:_dash(playerRoot, false) then return end
	end

	self:_slash(playerRoot, playerHumanoid)
end

function CombatAI:_heartbeat(dt)
	if self.destroyed then return end
	self.accumulator += dt
	self.observationAccumulator += dt
	if self.accumulator < AI_TICK then return end
	self.accumulator = 0

	local playerCharacter, playerRoot, playerHumanoid = self:_validCombatants()
	if not playerCharacter then return end

	if self.level == 0 then
		self.humanoid:Move(Vector3.zero, false)
		local velocity = self.root.AssemblyLinearVelocity
		self.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		return
	end

	if self.observationAccumulator >= OBSERVATION_TICK then
		self.observationAccumulator = 0
		self:_observe(playerCharacter, playerRoot)
	end

	self:_move(playerRoot)
	self:_decide(playerCharacter, playerRoot, playerHumanoid)
end

return CombatAI
