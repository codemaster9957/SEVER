local ServerScriptService = game:GetService("ServerScriptService")

local CombatAI = require(ServerScriptService:WaitForChild("TrainingDummyCombatAI"))
local TrainingDummyAnimator = require(ServerScriptService:WaitForChild("TrainingDummyAnimator"))
local Lifecycle = require(ServerScriptService:WaitForChild("TrainingDummyBattleLifecycle"))

if CombatAI.__SEVERAnimationPatchInstalled then
	return
end
CombatAI.__SEVERAnimationPatchInstalled = true

local INTRO_LOCK_TIME = 2.55

local originalNew = CombatAI.new
local originalDestroy = CombatAI.Destroy
local originalHeartbeat = CombatAI._heartbeat

local function stopIntroMotion(self)
	if self.dummy then
		self.dummy:SetAttribute("AttackActiveUntil", 0)
		self.dummy:SetAttribute("IsBlocking", false)
		self.dummy:SetAttribute("IsParrying", false)
	end
	if self.humanoid then
		self.humanoid:Move(Vector3.zero, false)
	end
	if self.root and self.root.Parent then
		local velocity = self.root.AssemblyLinearVelocity
		self.root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		self.root.AssemblyAngularVelocity = Vector3.zero
	end
	if self._severAnimator then
		self._severAnimator:SetLocomotionEnabled(false)
	end
end

local function unlockCurrentController(battle)
	if not Lifecycle.EnterFighting(battle) then
		return
	end
	local controller = battle.aiController
	if not controller or controller.destroyed then
		return
	end
	if controller.dummy and controller.dummy.Parent then
		controller.dummy:SetAttribute("TrainingFightLive", true)
	end
	if controller._severAnimator then
		controller._severAnimator:SetLocomotionEnabled(controller.level >= 1)
	end
end

CombatAI.new = function(player, battle, level, memory)
	if type(battle) == "table" then
		if battle.fighting ~= true then
			battle.fighting = false
		end
		if not battle._severFightGateScheduled then
			battle._severFightGateScheduled = true
			task.delay(INTRO_LOCK_TIME, function()
				if type(battle) == "table" and battle.finished ~= true then
					unlockCurrentController(battle)
				end
			end)
		end
	end

	if battle and battle.dummyClone then
		battle.dummyClone:SetAttribute("TrainingFightLive", Lifecycle.ShouldRunAI(battle))
	end

	local controller = originalNew(player, battle, level, memory)
	if not controller then
		return controller
	end

	controller._severAnimator = TrainingDummyAnimator.new(controller.dummy)
	if controller._severAnimator then
		controller._severAnimator:SetLocomotionEnabled(Lifecycle.ShouldRunAI(battle) and controller.level >= 1)
	end

	if not Lifecycle.ShouldRunAI(battle) then
		stopIntroMotion(controller)
	end
	return controller
end

CombatAI._heartbeat = function(self, dt)
	if not Lifecycle.ShouldRunAI(self.battle) then
		stopIntroMotion(self)
		return
	end
	if self.dummy then
		self.dummy:SetAttribute("TrainingFightLive", true)
	end
	if self._severAnimator then
		self._severAnimator:SetLocomotionEnabled(self.level >= 1)
	end
	return originalHeartbeat(self, dt)
end

local function wrapAction(methodName, animationName)
	local original = CombatAI[methodName]
	if type(original) ~= "function" then
		return
	end

	CombatAI[methodName] = function(self, ...)
		if not Lifecycle.ShouldRunAI(self.battle) then
			return false
		end
		local result = original(self, ...)
		if result and self._severAnimator then
			self._severAnimator:PlayAction(animationName)
		end
		return result
	end
end

wrapAction("_slash", "Slash")
wrapAction("_dash", "Dash")
wrapAction("_grapple", "Grapple")
wrapAction("_blockOrParry", "Block")
wrapAction("_throw", "Throw")
wrapAction("_spin", "Spin")
wrapAction("_soulReap", "SoulReap")

CombatAI.Destroy = function(self)
	if self._severAnimator then
		self._severAnimator:Destroy()
		self._severAnimator = nil
	end
	return originalDestroy(self)
end
