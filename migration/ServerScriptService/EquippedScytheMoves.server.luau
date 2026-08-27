--!strict
-- Server-authoritative runtime for the loadout-controlled Spin and Scythe Throw moves.
-- Soul Reap keeps its dedicated server implementation and is loadout-gated there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
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

local function performThrow(player: Player)
	local character, _, root = getCharacterState(player)
	if not character or not root then return end
	local direction = horizontalFacing(root)
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local params = getOverlapParams(character)
	character:SetAttribute("AttackActiveUntil", os.clock() + 0.55)
	UseMove:FireAllClients("FX", "scythe_throw", player.UserId, origin, direction, THROW_RANGE)

	for distance = THROW_STEP, THROW_RANGE, THROW_STEP do
		if not canUseMove(player) then return end
		local center = origin + direction * distance
		local parts = workspace:GetPartBoundsInBox(CFrame.new(center), THROW_HALF_SIZE * 2, params)
		local targets = findTargets(player, parts)
		if #targets > 0 then
			local humanoid = targets[1]:FindFirstChildOfClass("Humanoid")
			if humanoid then
				DamageHandler.ApplyDamage(humanoid, THROW_DAMAGE, player)
			end
			return
		end
	end
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
