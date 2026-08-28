--!strict
-- Server-authoritative runtime for the loadout-controlled Spin and Scythe Throw moves.
-- Soul Reap keeps its dedicated server implementation and is loadout-gated there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
local ScytheThrowPullPolicy = require(ServerScriptService:WaitForChild("ScytheThrowPullPolicy"))
local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local LoadoutPolicy = require(ScytheSystems:WaitForChild("LoadoutPolicy"))
local UseMove = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Loadout"):WaitForChild("UseMove") :: RemoteEvent

local SPIN_DURATION = 1.8
local SPIN_TICK = 0.30
local SPIN_RADIUS = 8
local SPIN_DAMAGE = 5

local THROW_RANGE = 48
local THROW_STEP = 4
local THROW_DAMAGE = 18
local THROW_HALF_SIZE = Vector3.new(3.5, 5, 3.5)
local THROW_OUT_DURATION = 0.38
local THROW_RETURN_SPEED = 126
local THROW_MIN_RETURN_DURATION = 0.12
local THROW_MAX_RETURN_DURATION = 0.42
local HOOK_SAFETY_DURATION = 2.0

local cooldowns: {[Player]: {[string]: number}} = {}

local function getCharacterState(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then return nil, nil, nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return character, humanoid, nil
	end
	return character, humanoid, root
end

local function canUseMove(player: Player): boolean
	if player.Parent ~= Players then return false end
	if not MatchManager.CanUseCombat(player) then return false end
	local character, humanoid, root = getCharacterState(player)
	if not character or not humanoid or not root then return false end
	if character:GetAttribute("Stunned") == true then return false end
	if character:GetAttribute("CanAttack") == false then return false end
	return true
end

local function getOpponentPlayer(player: Player): Player?
	local getter = (_G :: any).GetOpponent
	if type(getter) ~= "function" then return nil end
	local ok, opponent = pcall(getter, player)
	if ok and typeof(opponent) == "Instance" and opponent:IsA("Player") then
		return opponent
	end
	return nil
end

local function isValidTarget(player: Player, model: Model): boolean
	if model == player.Character then return false end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	local targetPlayer = Players:GetPlayerFromCharacter(model)
	if targetPlayer then
		local expected = getOpponentPlayer(player)
		if expected then
			return targetPlayer == expected
		end
		return MatchManager.IsPlayerInMatch(targetPlayer)
	end

	return model:GetAttribute("InMatch") == true
end

local function findTargets(player: Player, parts: {BasePart}): {Model}
	local seen: {[Model]: boolean} = {}
	local result = {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] and isValidTarget(player, model) then
			seen[model] = true
			table.insert(result, model)
		end
	end
	return result
end

local function getOverlapParams(character: Model): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.MaxParts = 80
	return params
end

local function horizontalFacing(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	if math.abs(look.X) >= math.abs(look.Z) then
		return Vector3.new(if look.X >= 0 then 1 else -1, 0, 0)
	end
	return Vector3.new(0, 0, if look.Z >= 0 then 1 else -1)
end

local function cooldownReady(player: Player, moveId: string): boolean
	local move = LoadoutPolicy.GetMove(moveId)
	if not move then return false end
	local perPlayer = cooldowns[player]
	if not perPlayer then
		perPlayer = {}
		cooldowns[player] = perPlayer
	end
	local now = os.clock()
	if now < (perPlayer[moveId] or 0) then
		return false
	end
	perPlayer[moveId] = now + move.Cooldown
	return true
end

local function performSpin(player: Player)
	local character, _, root = getCharacterState(player)
	if not character or not root then return end
	local params = getOverlapParams(character)
	local endTime = os.clock() + SPIN_DURATION
	character:SetAttribute("SpecialMoveActive", "spin")
	character:SetAttribute("AttackActiveUntil", endTime)
	UseMove:FireAllClients("FX", "spin", player.UserId, SPIN_DURATION)

	task.spawn(function()
		while os.clock() < endTime and canUseMove(player) do
			local currentCharacter, _, currentRoot = getCharacterState(player)
			if currentCharacter ~= character or not currentRoot then break end
			local parts = workspace:GetPartBoundsInRadius(currentRoot.Position, SPIN_RADIUS, params)
			for _, target in ipairs(findTargets(player, parts)) do
				local humanoid = target:FindFirstChildOfClass("Humanoid")
				if humanoid then
					DamageHandler.ApplyDamage(humanoid, SPIN_DAMAGE, player)
				end
			end
			task.wait(SPIN_TICK)
		end
		if character.Parent and character:GetAttribute("SpecialMoveActive") == "spin" then
			character:SetAttribute("SpecialMoveActive", nil)
		end
	end)
end

local function getLiveTargetState(model: Model): (Humanoid?, BasePart?)
	if not model.Parent then return nil, nil end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return humanoid, nil
	end
	return humanoid, root
end

local function setServerOwnership(root: BasePart, serverOwned: boolean)
	pcall(function()
		if serverOwned then
			root:SetNetworkOwner(nil)
		else
			root:SetNetworkOwnershipAuto()
		end
	end)
end

type HookState = {
	target: Model,
	targetPlayer: Player?,
	attachment: Attachment,
	tether: AlignPosition,
	pathY: number,
	oldWalkSpeed: number,
	oldJumpPower: number,
	oldJumpHeight: number,
	oldAutoRotate: boolean,
	finished: boolean,
}

local function beginHook(target: Model): HookState?
	local humanoid, root = getLiveTargetState(target)
	if not humanoid or not root or root.Anchored then return nil end

	local config = ScytheThrowPullPolicy.GetTetherConfig()
	local targetPlayer = Players:GetPlayerFromCharacter(target)

	local attachment = Instance.new("Attachment")
	attachment.Name = "ScytheHookAttachment"
	attachment.Parent = root

	local tether = Instance.new("AlignPosition")
	tether.Name = "ScytheHookTether"
	tether.Mode = Enum.PositionAlignmentMode.OneAttachment
	tether.Attachment0 = attachment
	tether.ApplyAtCenterOfMass = true
	tether.RigidityEnabled = config.RigidityEnabled == true
	tether.MaxForce = config.MaxForce
	tether.MaxVelocity = config.MaxVelocity
	tether.Responsiveness = config.Responsiveness
	tether.Position = root.Position
	tether.Parent = root

	local state: HookState = {
		target = target,
		targetPlayer = targetPlayer,
		attachment = attachment,
		tether = tether,
		pathY = root.Position.Y,
		oldWalkSpeed = humanoid.WalkSpeed,
		oldJumpPower = humanoid.JumpPower,
		oldJumpHeight = humanoid.JumpHeight,
		oldAutoRotate = humanoid.AutoRotate,
		finished = false,
	}

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero, false)
	target:SetAttribute("ScytheHookedUntil", os.clock() + HOOK_SAFETY_DURATION)

	if targetPlayer then
		setServerOwnership(root, true)
	end

	return state
end

local function updateHookGoal(state: HookState, projectilePosition: Vector3): boolean
	if state.finished or not state.target.Parent or not state.tether.Parent then return false end
	local humanoid, root = getLiveTargetState(state.target)
	if not humanoid or not root or root.Anchored then return false end

	state.tether.Position = ScytheThrowPullPolicy.GetPathGoal(projectilePosition, state.pathY)
	humanoid:Move(Vector3.zero, false)
	return true
end

local function finishHook(state: HookState?)
	if not state or state.finished then return end
	state.finished = true

	if state.tether.Parent then state.tether:Destroy() end
	if state.attachment.Parent then state.attachment:Destroy() end

	local humanoid, root = getLiveTargetState(state.target)
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero
		if state.targetPlayer then
			setServerOwnership(root, false)
		end
	end
	if humanoid then
		humanoid.WalkSpeed = state.oldWalkSpeed
		humanoid.JumpPower = state.oldJumpPower
		humanoid.JumpHeight = state.oldJumpHeight
		humanoid.AutoRotate = state.oldAutoRotate
	end
	if state.target.Parent then
		state.target:SetAttribute("ScytheHookedUntil", nil)
	end
end

local function followHookOutbound(
	player: Player,
	character: Model,
	state: HookState,
	origin: Vector3,
	direction: Vector3,
	startDistance: number
): (boolean, Vector3)
	local remainingDistance = math.max(0, THROW_RANGE - startDistance)
	local duration = THROW_OUT_DURATION * (remainingDistance / THROW_RANGE)
	local startedAt = os.clock()
	local finalPosition = origin + direction * THROW_RANGE

	if duration <= 0.001 then
		return updateHookGoal(state, finalPosition), finalPosition
	end

	while true do
		local currentCharacter, currentHumanoid, currentRoot = getCharacterState(player)
		if currentCharacter ~= character or not currentHumanoid or not currentRoot then
			return false, finalPosition
		end

		local elapsed = os.clock() - startedAt
		local alpha = math.clamp(elapsed / duration, 0, 1)
		local distance = startDistance + remainingDistance * alpha
		local scythePoint = origin + direction * distance

		if not updateHookGoal(state, scythePoint) then
			return false, scythePoint
		end

		if alpha >= 1 then
			return true, finalPosition
		end

		RunService.Heartbeat:Wait()
	end
end

local function followHookReturn(player: Player, state: HookState, returnStart: Vector3, duration: number)
	local config = ScytheThrowPullPolicy.GetTetherConfig()
	local startedAt = os.clock()
	state.target:SetAttribute("ScytheHookedUntil", startedAt + duration + 0.2)

	while os.clock() - startedAt < duration do
		local _, sourceHumanoid, sourceRoot = getCharacterState(player)
		if not sourceHumanoid or not sourceRoot then break end

		local alpha = math.clamp((os.clock() - startedAt) / math.max(duration, 0.01), 0, 1)
		local eased = 1 - (1 - alpha) * (1 - alpha)
		local scythePoint = returnStart:Lerp(sourceRoot.Position, eased)

		local fromSource = Vector3.new(
			scythePoint.X - sourceRoot.Position.X,
			0,
			scythePoint.Z - sourceRoot.Position.Z
		)
		if fromSource.Magnitude < config.StopDistance then
			local approach = Vector3.new(
				returnStart.X - sourceRoot.Position.X,
				0,
				returnStart.Z - sourceRoot.Position.Z
			)
			if approach.Magnitude > 0.001 then
				scythePoint = sourceRoot.Position + approach.Unit * config.StopDistance
			end
		end

		if not updateHookGoal(state, scythePoint) then break end
		RunService.Heartbeat:Wait()
	end
end

local function performThrow(player: Player)
	local character, _, root = getCharacterState(player)
	if not character or not root then return end

	local direction = horizontalFacing(root)
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local params = getOverlapParams(character)
	local outwardSteps = math.max(1, math.ceil(THROW_RANGE / THROW_STEP))
	local outwardStepTime = THROW_OUT_DURATION / outwardSteps

	character:SetAttribute("SpecialMoveActive", "scythe_throw")
	character:SetAttribute("AttackActiveUntil", os.clock() + THROW_OUT_DURATION + 0.9)
	UseMove:FireAllClients("FX", "scythe_throw", player.UserId, origin, direction, THROW_RANGE)

	task.spawn(function()
		local returnPosition = origin + direction * THROW_RANGE
		local hookState: HookState? = nil

		for step = 1, outwardSteps do
			task.wait(outwardStepTime)

			local currentCharacter, currentHumanoid, currentRoot = getCharacterState(player)
			if currentCharacter ~= character or not currentHumanoid or not currentRoot then
				finishHook(hookState)
				UseMove:FireAllClients("FX", "scythe_throw_cancel", player.UserId)
				return
			end

			local distance = math.min(THROW_RANGE, step * THROW_STEP)
			local center = origin + direction * distance
			returnPosition = center

			local parts = workspace:GetPartBoundsInBox(CFrame.new(center), THROW_HALF_SIZE * 2, params)
			local targets = findTargets(player, parts)
			if #targets > 0 then
				local target = targets[1]
				local humanoid = target:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local result = DamageHandler.ApplyDamage(humanoid, THROW_DAMAGE, player)
					local didHook = ScytheThrowPullPolicy.DidHookFromDamageResult(result)

					if didHook then
						hookState = beginHook(target)
						if hookState then
							-- Attach immediately at the exact contact point.
							updateHookGoal(hookState, center)
							currentRoot.AssemblyLinearVelocity = Vector3.new(0, currentRoot.AssemblyLinearVelocity.Y, 0)

							-- Once caught, stop using 4-stud throw ticks. Track the visible
							-- scythe continuously every physics frame through the rest of
							-- its outbound path.
							local followed
							followed, returnPosition = followHookOutbound(
								player,
								character,
								hookState,
								origin,
								direction,
								distance
							)
							if not followed then
								finishHook(hookState)
								hookState = nil
							end
						end
					end

					if not hookState or not ScytheThrowPullPolicy.ShouldContinueOutboundAfterContact(didHook) then
						break
					end

					-- Successful hook already completed the remaining outbound path above.
					break
				end
			end
		end

		local _, returnHumanoid, returnRoot = getCharacterState(player)
		if not returnHumanoid or not returnRoot then
			finishHook(hookState)
			UseMove:FireAllClients("FX", "scythe_throw_cancel", player.UserId)
			return
		end

		local returnDistance = (returnPosition - returnRoot.Position).Magnitude
		local returnDuration = math.clamp(
			returnDistance / THROW_RETURN_SPEED,
			THROW_MIN_RETURN_DURATION,
			THROW_MAX_RETURN_DURATION
		)
		if hookState then
			returnDuration = math.max(returnDuration, ScytheThrowPullPolicy.GetPullDuration(returnDuration))
		end

		UseMove:FireAllClients(
			"FX",
			"scythe_throw_return",
			player.UserId,
			returnPosition,
			returnDuration
		)

		if hookState then
			followHookReturn(player, hookState, returnPosition, returnDuration)
			finishHook(hookState)
		else
			task.wait(returnDuration)
		end

		if character.Parent and character:GetAttribute("SpecialMoveActive") == "scythe_throw" then
			character:SetAttribute("SpecialMoveActive", nil)
		end
	end)
end

UseMove.OnServerEvent:Connect(function(player: Player, slotIndex: any)
	local slot = tonumber(slotIndex)
	if slot ~= 1 and slot ~= 2 then return end
	if not canUseMove(player) then return end

	local moveId = player:GetAttribute("EquippedMove" .. tostring(slot))
	if type(moveId) ~= "string" or not LoadoutPolicy.IsEquipped({
		player:GetAttribute("EquippedMove1"),
		player:GetAttribute("EquippedMove2"),
	}, moveId) then
		return
	end
	if moveId ~= "spin" and moveId ~= "scythe_throw" then
		return
	end
	if not cooldownReady(player, moveId) then return end

	if moveId == "spin" then
		performSpin(player)
	elseif moveId == "scythe_throw" then
		performThrow(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
end)
