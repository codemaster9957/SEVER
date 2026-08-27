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

local PULL_STOP_DISTANCE = 5
local PULL_MIN_SPEED = 70
local PULL_MAX_SPEED = 130
local PULL_VERTICAL_GAIN = 4
local PULL_MAX_VERTICAL_SPEED = 18

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

	-- Training battle NPCs are explicitly marked InMatch by DummyBattleServer.
	return model:GetAttribute("InMatch") == true
end

local function findTargets(player: Player, parts: {BasePart}): {Model}
	local seen: {[Model]: boolean = {}
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
	-- SEVER's battle movement is side-on. Prefer the X lane, but keep a Z fallback
	-- for arenas whose rig is rotated 90 degrees.
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

local function pullCaughtTarget(player: Player, target: Model, duration: number)
	local targetHumanoid, targetRoot = getLiveTargetState(target)
	if not targetHumanoid or not targetRoot or targetRoot.Anchored then return end

	local targetPlayer = Players:GetPlayerFromCharacter(target)
	local oldWalkSpeed = targetHumanoid.WalkSpeed
	local oldJumpPower = targetHumanoid.JumpPower
	local oldJumpHeight = targetHumanoid.JumpHeight
	local oldAutoRotate = targetHumanoid.AutoRotate
	local finishAt = os.clock() + duration

	-- DamageHandler applies its normal outward knockback first. A hooked throw needs to
	-- take control immediately, otherwise the short-range knockback can win the first frames.
	targetRoot.AssemblyLinearVelocity = Vector3.zero
	targetRoot.AssemblyAngularVelocity = Vector3.zero
	targetHumanoid.WalkSpeed = 0
	targetHumanoid.JumpPower = 0
	targetHumanoid.JumpHeight = 0
	targetHumanoid.AutoRotate = false
	target:SetAttribute("ScytheHookedUntil", finishAt)

	if targetPlayer then
		setServerOwnership(targetRoot, true)
	end

	while os.clock() < finishAt do
		local _, sourceHumanoid, sourceRoot = getCharacterState(player)
		targetHumanoid, targetRoot = getLiveTargetState(target)
		if not sourceHumanoid or not sourceRoot or not targetHumanoid or not targetRoot then
			break
		end
		if targetRoot.Anchored then break end

		local delta = sourceRoot.Position - targetRoot.Position
		local horizontal = Vector3.new(delta.X, 0, delta.Z)
		if horizontal.Magnitude <= PULL_STOP_DISTANCE then
			targetRoot.AssemblyLinearVelocity = Vector3.new(0, targetRoot.AssemblyLinearVelocity.Y, 0)
			break
		end

		local speed = math.clamp(horizontal.Magnitude * 4.2, PULL_MIN_SPEED, PULL_MAX_SPEED)
		local vertical = math.clamp(delta.Y * PULL_VERTICAL_GAIN, -PULL_MAX_VERTICAL_SPEED, PULL_MAX_VERTICAL_SPEED)
		targetRoot.AssemblyLinearVelocity = horizontal.Unit * speed + Vector3.new(0, vertical, 0)
		RunService.Heartbeat:Wait()
	end

	local finalHumanoid, finalRoot = getLiveTargetState(target)
	if finalRoot then
		local velocity = finalRoot.AssemblyLinearVelocity
		finalRoot.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
		if targetPlayer then
			setServerOwnership(finalRoot, false)
		end
	end
	if finalHumanoid then
		finalHumanoid.WalkSpeed = oldWalkSpeed
		finalHumanoid.JumpPower = oldJumpPower
		finalHumanoid.JumpHeight = oldJumpHeight
		finalHumanoid.AutoRotate = oldAutoRotate
	end
	if target.Parent then
		target:SetAttribute("ScytheHookedUntil", nil)
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
		local caughtTarget: Model? = nil

		for step = 1, outwardSteps do
			task.wait(outwardStepTime)

			local currentCharacter, currentHumanoid, currentRoot = getCharacterState(player)
			if currentCharacter ~= character or not currentHumanoid or not currentRoot then
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
					if ScytheThrowPullPolicy.DidHookFromDamageResult(result) then
						caughtTarget = target
						local _, caughtRoot = getLiveTargetState(target)
						if caughtRoot then
							-- Cancel DamageHandler's normal outward throw knockback immediately.
							caughtRoot.AssemblyLinearVelocity = Vector3.zero
							caughtRoot.AssemblyAngularVelocity = Vector3.zero
						end
					end
				end
				-- Any actual contact makes the boomerang reverse. Successful defence prevents the pull.
				break
			end
		end

		local _, returnHumanoid, returnRoot = getCharacterState(player)
		if not returnHumanoid or not returnRoot then
			UseMove:FireAllClients("FX", "scythe_throw_cancel", player.UserId)
			return
		end

		local returnDistance = (returnPosition - returnRoot.Position).Magnitude
		local returnDuration = math.clamp(
			returnDistance / THROW_RETURN_SPEED,
			THROW_MIN_RETURN_DURATION,
			THROW_MAX_RETURN_DURATION
		)
		local pullDuration: number? = nil
		if caughtTarget then
			pullDuration = ScytheThrowPullPolicy.GetPullDuration(returnDuration)
			-- On a hook, keep the visible scythe attached to the same return window as the drag.
			returnDuration = math.max(returnDuration, pullDuration)
		end

		UseMove:FireAllClients(
			"FX",
			"scythe_throw_return",
			player.UserId,
			returnPosition,
			returnDuration
		)

		if caughtTarget and pullDuration then
			pullCaughtTarget(player, caughtTarget, pullDuration)
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

	-- Never trust a move id supplied by the client. The server resolves the move
	-- exclusively from the replicated, server-owned equipped slot.
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
