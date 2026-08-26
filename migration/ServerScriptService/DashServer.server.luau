local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local GrappleEvents = ReplicatedStorage:WaitForChild("GrappleEvents")
local DashRequest = GrappleEvents:WaitForChild("DashRequest")
local CombatJuice = require(ReplicatedStorage:WaitForChild("CombatJuice"))
local PlayPrivateSound = ReplicatedStorage:WaitForChild("PlayPrivateSound")

local dashCooldowns = {}

local DASH_COOLDOWN = 0.8
local DASH_FORCE = 95
local DASH_DURATION = 0.18
local PERFECT_DODGE_WINDOW = 0.2

-- Change this if your side-on movement is on Z instead of X
local SIDE_AXIS = "X"

local function getSideDirection(direction, hrp)
	local side = 0

	if typeof(direction) == "Vector3" then
		if SIDE_AXIS == "X" then
			side = direction.X
		else
			side = direction.Z
		end
	elseif typeof(direction) == "number" then
		side = direction
	end

	if math.abs(side) < 0.05 then
		-- Fallback: use facing direction, but only on the side axis
		if SIDE_AXIS == "X" then
			side = hrp.CFrame.LookVector.X
		else
			side = hrp.CFrame.LookVector.Z
		end
	end

	if side >= 0 then
		return 1
	else
		return -1
	end
end

local function makeDashVector(side)
	if SIDE_AXIS == "X" then
		return Vector3.new(side, 0, 0)
	else
		return Vector3.new(0, 0, side)
	end
end

DashRequest.OnServerEvent:Connect(function(player, direction)
	local character = player.Character
	if not character or character:GetAttribute("InMatch") ~= true then return end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local now = os.clock()
	if dashCooldowns[player.UserId] and now - dashCooldowns[player.UserId] < DASH_COOLDOWN then
		return
	end

	dashCooldowns[player.UserId] = now

	local side = getSideDirection(direction, hrp)
	local dashDir = makeDashVector(side)

	character:SetAttribute("PerfectDodgeUntil", os.clock() + PERFECT_DODGE_WINDOW)
	character:SetAttribute("IsDashInvulnerable", true)
	character:SetAttribute("IsDashing", true)

	-- Side-on dash velocity.
	-- Keeps Y velocity so jumping/falling still feels natural.
	local currentVelocity = hrp.AssemblyLinearVelocity

	if SIDE_AXIS == "X" then
		hrp.AssemblyLinearVelocity = Vector3.new(
			dashDir.X * DASH_FORCE,
			currentVelocity.Y,
			0
		)
	else
		hrp.AssemblyLinearVelocity = Vector3.new(
			0,
			currentVelocity.Y,
			dashDir.Z * DASH_FORCE
		)
	end

	CombatJuice.EmitTo(player, "", {
		targetUserId = player.UserId,
		position = hrp.Position,
	})

	-- Play dash sound for the players in battle
	local opponent = _G.GetOpponent and _G.GetOpponent(player)
	if opponent then
		PlayPrivateSound:FireClient(player, "Dash")
		PlayPrivateSound:FireClient(opponent, "Dash")
	end

	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp

	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(
		Color3.fromRGB(200, 240, 255),
		Color3.fromRGB(0, 100, 255)
	)
	particles.Lifetime = NumberRange.new(0.3, 0.5)
	particles.Rate = 200
	particles.Speed = NumberRange.new(15, 25)
	particles.Acceleration = dashDir * -60
	particles.SpreadAngle = Vector2.new(10, 10)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1)
	})
	particles.Parent = attachment

	task.delay(DASH_DURATION, function()
		if character and character.Parent then
			character:SetAttribute("IsDashInvulnerable", false)
			character:SetAttribute("IsDashing", false)
		end

		if hrp and hrp.Parent then
			local v = hrp.AssemblyLinearVelocity

			-- Stop only the side dash, not gravity.
			if SIDE_AXIS == "X" then
				hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			else
				hrp.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
			end
		end

		particles.Enabled = false
		Debris:AddItem(attachment, 1)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	dashCooldowns[player.UserId] = nil
end)