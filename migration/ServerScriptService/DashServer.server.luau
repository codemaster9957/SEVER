local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local GrappleEvents = ReplicatedStorage:WaitForChild("GrappleEvents")
local DashRequest = GrappleEvents:WaitForChild("DashRequest")
local PlayPrivateSound = ReplicatedStorage:WaitForChild("PlayPrivateSound")

local dashCooldowns = {}
local dashTokens = {}

local DASH_COOLDOWN = 0.8
local DASH_FORCE = 95
local DASH_DURATION = 0.18
local DASH_EXIT_SPEED = 28
local PERFECT_DODGE_WINDOW = 0.2
local SIDE_AXIS = "X"

local function getSideDirection(direction, hrp)
	local side = 0

	if typeof(direction) == "Vector3" then
		side = SIDE_AXIS == "X" and direction.X or direction.Z
	elseif typeof(direction) == "number" then
		side = direction
	end

	if math.abs(side) < 0.05 then
		side = SIDE_AXIS == "X" and hrp.CFrame.LookVector.X or hrp.CFrame.LookVector.Z
	end

	return side >= 0 and 1 or -1
end

local function makeDashVector(side)
	return SIDE_AXIS == "X" and Vector3.new(side, 0, 0) or Vector3.new(0, 0, side)
end

local function getDashEmitter(hrp)
	local attachment = hrp:FindFirstChild("SEVER_DashVFXAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "SEVER_DashVFXAttachment"
		attachment.Parent = hrp
	end

	local particles = attachment:FindFirstChild("DashParticles")
	if not particles then
		particles = Instance.new("ParticleEmitter")
		particles.Name = "DashParticles"
		particles.Enabled = false
		particles.Color = ColorSequence.new(
			Color3.fromRGB(200, 240, 255),
			Color3.fromRGB(0, 100, 255)
		)
		particles.Lifetime = NumberRange.new(0.22, 0.35)
		particles.Rate = 85
		particles.Speed = NumberRange.new(12, 20)
		particles.SpreadAngle = Vector2.new(8, 8)
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 0),
		})
		particles.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 1),
		})
		particles.Parent = attachment
	end

	return particles
end

local function canDash(character)
	if not character or character:GetAttribute("InMatch") ~= true then return false end
	if character:GetAttribute("Stunned") == true then return false end
	if character:GetAttribute("IsBlocking") == true then return false end
	if character:GetAttribute("CanAttack") == false then return false end
	return true
end

DashRequest.OnServerEvent:Connect(function(player, direction)
	local character = player.Character
	if not canDash(character) then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then return end

	local now = os.clock()
	local previous = dashCooldowns[player.UserId] or -math.huge
	if now - previous < DASH_COOLDOWN then return end
	dashCooldowns[player.UserId] = now

	local side = getSideDirection(direction, hrp)
	local dashDir = makeDashVector(side)
	local currentVelocity = hrp.AssemblyLinearVelocity

	character:SetAttribute("PerfectDodgeUntil", now + PERFECT_DODGE_WINDOW)
	character:SetAttribute("IsDashInvulnerable", true)
	character:SetAttribute("IsDashing", true)

	if SIDE_AXIS == "X" then
		hrp.AssemblyLinearVelocity = Vector3.new(side * DASH_FORCE, currentVelocity.Y, 0)
	else
		hrp.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, side * DASH_FORCE)
	end

	local particles = getDashEmitter(hrp)
	particles.Acceleration = dashDir * -45
	particles.Enabled = true

	-- Always let the player hear their own dash (including dummy/tutorial matches).
	PlayPrivateSound:FireClient(player, "Dash")
	local opponent = _G.GetOpponent and _G.GetOpponent(player)
	if opponent and opponent:IsA("Player") then
		PlayPrivateSound:FireClient(opponent, "Dash")
	end

	local token = (dashTokens[player.UserId] or 0) + 1
	dashTokens[player.UserId] = token

	task.delay(DASH_DURATION, function()
		if dashTokens[player.UserId] ~= token then return end

		if character.Parent then
			character:SetAttribute("IsDashInvulnerable", false)
			character:SetAttribute("IsDashing", false)
		end

		if hrp.Parent then
			local velocity = hrp.AssemblyLinearVelocity
			local along = SIDE_AXIS == "X" and velocity.X or velocity.Z

			-- Only trim leftover dash velocity. Preserve knockback/grapple momentum in
			-- the opposite direction instead of snapping the player to a full stop.
			if along * side > DASH_EXIT_SPEED then
				along = side * DASH_EXIT_SPEED
			end

			if SIDE_AXIS == "X" then
				hrp.AssemblyLinearVelocity = Vector3.new(along, velocity.Y, 0)
			else
				hrp.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, along)
			end
		end

		if particles.Parent then
			particles.Enabled = false
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	dashCooldowns[player.UserId] = nil
	dashTokens[player.UserId] = nil
end)
