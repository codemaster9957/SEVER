local SOUL_REAP_ANIMATION_ID = ""
local SOUL_REAP_DAMAGE = 30
local SOUL_REAP_COOLDOWN = 9
local SOUL_REAP_DASH_SPEED = 170
local SOUL_REAP_DASH_DURATION = 0.16
local SOUL_REAP_STUN_TIME = 0.5
local SOUL_REAP_STARTUP = 0.15
local SOUL_REAP_IMPACT_DELAY = 0.15
local SOUL_REAP_STARTUP_SOUND_ID = ""
local SOUL_REAP_DASH_SOUND_ID = ""
local SOUL_REAP_IMPACT_SOUND_ID = ""
local SOUL_REAP_VFX_REFERENCE = "ReplicatedStorage/soul reap vfx"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local request = ReplicatedStorage:WaitForChild("GrappleEvents"):WaitForChild("SoulReapRequest")
local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))

local cooldowns = {}
local activeCasts = {}
local SIDE_AXIS = "X"

local function sideVector(side)
	return SIDE_AXIS == "X" and Vector3.new(side, 0, 0) or Vector3.new(0, 0, side)
end

local function facingSide(root)
	local component = SIDE_AXIS == "X" and root.CFrame.LookVector.X or root.CFrame.LookVector.Z
	return component >= 0 and 1 or -1
end

local function makeSound(parent, soundId, volume)
	if soundId == "" then return end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 1
	sound.RollOffMaxDistance = 80
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function chargeVFX(character)
	local highlight = Instance.new("Highlight")
	highlight.Name = "SoulReapCharge"
	highlight.FillColor = Color3.fromRGB(35, 0, 55)
	highlight.OutlineColor = Color3.fromRGB(145, 45, 255)
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = character
	Debris:AddItem(highlight, SOUL_REAP_STARTUP + 0.08)
end

local function soulMark(target)
	local root = target:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local attachment = Instance.new("Attachment")
	attachment.Name = "SoulMark"
	attachment.Parent = root
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "SoulMarkParticles"
	particles.Color = ColorSequence.new(Color3.fromRGB(35, 0, 50), Color3.fromRGB(175, 55, 255))
	particles.LightEmission = 0.25
	particles.Lifetime = NumberRange.new(0.25, 0.45)
	particles.Rate = 28
	particles.Speed = NumberRange.new(0.5, 2)
	particles.SpreadAngle = Vector2.new(180, 180)
	particles.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0)})
	particles.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1)})
	particles.Parent = attachment
	Debris:AddItem(attachment, 1)
end

local function stunTarget(character, duration)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local token = (character:GetAttribute("SoulReapStunToken") or 0) + 1
	character:SetAttribute("SoulReapStunToken", token)
	character:SetAttribute("Stunned", true)
	local oldWalkSpeed, oldJumpPower, oldJumpHeight, oldAutoRotate = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight, humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	task.delay(duration, function()
		if not character.Parent or not humanoid.Parent or character:GetAttribute("SoulReapStunToken") ~= token then return end
		character:SetAttribute("Stunned", false)
		humanoid.WalkSpeed = oldWalkSpeed > 0 and oldWalkSpeed or 16
		humanoid.JumpPower = oldJumpPower
		humanoid.JumpHeight = oldJumpHeight
		humanoid.AutoRotate = oldAutoRotate
	end)
end

local function validTarget(attacker, model)
	if not model or model == attacker.Character then return nil end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root then return nil end
	local targetPlayer = Players:GetPlayerFromCharacter(model)
	local expectedOpponent = _G.GetOpponent and _G.GetOpponent(attacker)
	if expectedOpponent and targetPlayer ~= expectedOpponent then return nil end
	if targetPlayer and model:GetAttribute("InMatch") ~= true then return nil end
	return humanoid, root
end

local function reapTarget(attacker, target, hitSet)
	if hitSet[target] then return end
	local humanoid, root = validTarget(attacker, target)
	if not humanoid then return end
	hitSet[target] = true
	stunTarget(target, SOUL_REAP_STUN_TIME)
	soulMark(target)
	request:FireAllClients("Impact", target)
	task.delay(SOUL_REAP_IMPACT_DELAY, function()
		if not humanoid.Parent or humanoid.Health <= 0 then return end
		local result = DamageHandler.ApplyDamage(humanoid, SOUL_REAP_DAMAGE, attacker)
		if not result or result.dodged or result.parried or result.clashed then return end
		makeSound(root, SOUL_REAP_IMPACT_SOUND_ID, 1.2)
		CombatJuice.Emit("HitImpact", {position = root.Position, power = 95, heavy = true, combo = 1, targetUserId = result.targetPlayer and result.targetPlayer.UserId or 0, attackerUserId = attacker.UserId})
	end)
end

local function cast(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or humanoid.Health <= 0 then return end
	if character:GetAttribute("InMatch") ~= true or character:GetAttribute("Stunned") == true or character:GetAttribute("IsBlocking") == true then return end

	local now = os.clock()
	if activeCasts[player] or (cooldowns[player] and now - cooldowns[player] < SOUL_REAP_COOLDOWN) then return end
	cooldowns[player] = now
	activeCasts[player] = true
	character:SetAttribute("SoulReapActive", true)
	character:SetAttribute("IsAttacking", true)
	chargeVFX(character)
	request:FireAllClients("Startup", character)
	makeSound(root, SOUL_REAP_STARTUP_SOUND_ID, 0.8)

	task.wait(SOUL_REAP_STARTUP)
	if player.Character ~= character or humanoid.Health <= 0 or character:GetAttribute("Stunned") == true then
		activeCasts[player] = nil
		character:SetAttribute("SoulReapActive", false)
		character:SetAttribute("IsAttacking", false)
		return
	end

	local direction = sideVector(facingSide(root))
	local hitSet = {}
	local elapsed = 0
	character:SetAttribute("IsDashing", true)
	character:SetAttribute("IsDashInvulnerable", true)
	request:FireAllClients("Dash", character, direction)

	while elapsed < SOUL_REAP_DASH_DURATION and root.Parent do
		local dt = RunService.Heartbeat:Wait()
		local remaining = SOUL_REAP_DASH_DURATION - elapsed
		dt = math.min(dt, remaining)
		elapsed += dt
		local distance = SOUL_REAP_DASH_SPEED * dt
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {character}
		local wallHit = workspace:Raycast(root.Position, direction * (distance + 2), rayParams)
		if wallHit and wallHit.Instance and wallHit.Instance.CanCollide then
			distance = math.max(0, wallHit.Distance - 2)
		end

		local startPosition = root.Position
		local nextPosition = startPosition + direction * distance
		character:PivotTo(character:GetPivot() + (nextPosition - startPosition))
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)

		local queryParams = OverlapParams.new()
		queryParams.FilterType = Enum.RaycastFilterType.Exclude
		queryParams.FilterDescendantsInstances = {character}
		local center = (startPosition + nextPosition) * 0.5
		local size = SIDE_AXIS == "X" and Vector3.new(math.max(5, distance + 5), 7, 7) or Vector3.new(7, 7, math.max(5, distance + 5))
		for _, part in workspace:GetPartBoundsInBox(CFrame.new(center), size, queryParams) do
			reapTarget(player, part:FindFirstAncestorOfClass("Model"), hitSet)
		end
		if wallHit then break end
	end

	character:SetAttribute("IsDashing", false)
	character:SetAttribute("IsDashInvulnerable", false)
	character:SetAttribute("SoulReapActive", false)
	character:SetAttribute("IsAttacking", false)
	activeCasts[player] = nil
end

request.OnServerEvent:Connect(function(player)
	task.spawn(cast, player)
end)

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
	activeCasts[player] = nil
end)