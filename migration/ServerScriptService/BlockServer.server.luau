local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local BlockRemote = CombatEvents:WaitForChild("BlockRemote")

local DamageHandler = require(
	ReplicatedStorage:WaitForChild("DamageHandler")
)

--// SETTINGS

local STUN_TIME = 1

-- How long a newly raised block counts as a parry.
local PARRY_WINDOW = 0.22

-- Prevents repeatedly tapping block to create endless parries.
local PARRY_REARM_TIME = 0.45

-- Prevents the remote being spammed every frame.
local REMOTE_COOLDOWN = 0.04

local DEFAULT_WALKSPEED = 16
local DEFAULT_JUMPPOWER = 50
local DEFAULT_JUMPHEIGHT = 7.2

local SHIELD_DISTANCE = 2.75
local SHIELD_DIAMETER = 9
local SHIELD_THICKNESS = 0.18

--// PLAYER STATE

local stunning = {}
local stunTokens = {}
local blockSessions = {}
local lastBlockEnded = {}
local lastRemoteUse = {}

--// DAMAGE HANDLER

local function setDamageHandlerBlocking(player, isBlocking)
	local success, result = pcall(function()
		return DamageHandler.SetBlocking(player, isBlocking)
	end)

	if not success then
		warn(
			"[BlockHandler] DamageHandler.SetBlocking failed:",
			result
		)
	end
end

--// SHIELD

local function removeShield(character)
	if not character then
		return
	end

	local shield = character:FindFirstChild("BlockShield")

	if shield then
		shield:Destroy()
	end
end

local function createShieldLayer(
	model,
	root,
	name,
	diameter,
	thickness,
	material,
	color,
	transparency,
	offset
)
	local shieldPart = Instance.new("Part")
	shieldPart.Name = name
	shieldPart.Shape = Enum.PartType.Cylinder

	-- Cylinder thickness runs along its local X-axis.
	shieldPart.Size = Vector3.new(
		thickness,
		diameter * 0.65,
		diameter * 0.65
	)

	shieldPart.Material = material
	shieldPart.Color = color
	shieldPart.Transparency = transparency

	shieldPart.CastShadow = false
	shieldPart.CanCollide = false
	shieldPart.CanTouch = false
	shieldPart.CanQuery = false
	shieldPart.Massless = true
	shieldPart.Anchored = false

	-- Rotating 90 degrees around Y makes the cylinder face forwards.
	shieldPart.CFrame =
		root.CFrame
		* CFrame.new(0, 0, -SHIELD_DISTANCE + offset)
		* CFrame.Angles(0, math.rad(90), 0)

	shieldPart.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Name = "ShieldWeld"
	weld.Part0 = root
	weld.Part1 = shieldPart
	weld.Parent = shieldPart

	local growTween = TweenService:Create(
		shieldPart,
		TweenInfo.new(
			0.14,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out
		),
		{
			Size = Vector3.new(
				thickness,
				diameter,
				diameter
			),
		}
	)

	growTween:Play()

	return shieldPart
end

local function setShieldAppearance(character, isParrying)
	if not character then
		return
	end

	local shield = character:FindFirstChild("BlockShield")
	if not shield then
		return
	end

	local core = shield:FindFirstChild("Core")
	local glow = shield:FindFirstChild("Glow")
	local highlight = shield:FindFirstChildOfClass("Highlight")
	local light = core and core:FindFirstChildOfClass("PointLight")

	local coreColor
	local glowColor
	local coreTransparency
	local glowTransparency

	if isParrying then
		coreColor = Color3.fromRGB(190, 250, 255)
		glowColor = Color3.fromRGB(70, 225, 255)
		coreTransparency = 0.3
		glowTransparency = 0.16
	else
		coreColor = Color3.fromRGB(225, 235, 245)
		glowColor = Color3.fromRGB(120, 170, 210)
		coreTransparency = 0.58
		glowTransparency = 0.62
	end

	if core then
		TweenService:Create(
			core,
			TweenInfo.new(0.12),
			{
				Color = coreColor,
				Transparency = coreTransparency,
			}
		):Play()
	end

	if glow then
		TweenService:Create(
			glow,
			TweenInfo.new(0.12),
			{
				Color = glowColor,
				Transparency = glowTransparency,
			}
		):Play()
	end

	if highlight then
		highlight.OutlineColor = glowColor
		highlight.OutlineTransparency = isParrying and 0.05 or 0.55
	end

	if light then
		TweenService:Create(
			light,
			TweenInfo.new(0.12),
			{
				Brightness = isParrying and 3.5 or 0.8,
				Range = isParrying and 13 or 7,
				Color = glowColor,
			}
		):Play()
	end
end

local function createShield(character, isParrying)
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	removeShield(character)

	local shield = Instance.new("Model")
	shield.Name = "BlockShield"
	shield.Parent = character

	local glow = createShieldLayer(
		shield,
		root,
		"Glow",
		SHIELD_DIAMETER + 0.8,
		SHIELD_THICKNESS,
		Enum.Material.Neon,
		Color3.fromRGB(70, 225, 255),
		isParrying and 0.16 or 0.62,
		0.04
	)

	local core = createShieldLayer(
		shield,
		root,
		"Core",
		SHIELD_DIAMETER,
		SHIELD_THICKNESS + 0.04,
		Enum.Material.ForceField,
		Color3.fromRGB(190, 250, 255),
		isParrying and 0.3 or 0.58,
		0
	)

	local highlight = Instance.new("Highlight")
	highlight.Name = "ShieldHighlight"
	highlight.Adornee = shield
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 1
	highlight.OutlineColor = Color3.fromRGB(70, 225, 255)
	highlight.OutlineTransparency = isParrying and 0.05 or 0.55
	highlight.Parent = shield

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(70, 225, 255)
	light.Brightness = isParrying and 3.5 or 0.8
	light.Range = isParrying and 13 or 7
	light.Shadows = false
	light.Parent = core

	if isParrying then
		local pulseTween = TweenService:Create(
			glow,
			TweenInfo.new(
				PARRY_WINDOW,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			),
			{
				Transparency = 0.45,
				Size = Vector3.new(
					SHIELD_THICKNESS,
					SHIELD_DIAMETER + 1.7,
					SHIELD_DIAMETER + 1.7
				),
			}
		)

		pulseTween:Play()
	end
end

--// STUN EFFECT

local function createStunEffect(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local flash = Instance.new("Part")
	flash.Name = "StunFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(1.5, 1.5, 1.5)
	flash.CFrame = root.CFrame
	flash.Color = Color3.fromRGB(130, 230, 255)
	flash.Material = Enum.Material.Neon
	flash.Transparency = 0.15
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.Parent = workspace

	TweenService:Create(
		flash,
		TweenInfo.new(
			0.32,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			Size = Vector3.new(8, 8, 8),
			Transparency = 1,
		}
	):Play()

	Debris:AddItem(flash, 0.4)
end

--// BLOCKING

local function invalidateBlockSession(player)
	blockSessions[player] = (blockSessions[player] or 0) + 1
	return blockSessions[player]
end

local function stopBlocking(player, character)
	invalidateBlockSession(player)

	if character then
		character:SetAttribute("IsBlocking", false)
		character:SetAttribute("IsParrying", false)
		character:SetAttribute("ParryExpiresAt", 0)

		removeShield(character)
	end

	lastBlockEnded[player] = os.clock()
	setDamageHandlerBlocking(player, false)
end

local function startBlocking(player, character)
	if not character then
		return
	end

	if character:GetAttribute("Stunned") then
		return
	end

	-- Holding block should not repeatedly restart the parry.
	if character:GetAttribute("IsBlocking") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local previousBlockEnd = lastBlockEnded[player] or -math.huge

	local canParry =
		now - previousBlockEnd >= PARRY_REARM_TIME

	local session = invalidateBlockSession(player)

	character:SetAttribute("IsBlocking", true)
	character:SetAttribute("IsParrying", canParry)
	character:SetAttribute("BlockStartedAt", now)
	character:SetAttribute("ShieldStartTime", now)

	if canParry then
		character:SetAttribute(
			"ParryExpiresAt",
			now + PARRY_WINDOW
		)
	else
		character:SetAttribute("ParryExpiresAt", 0)
	end

	setDamageHandlerBlocking(player, true)
	createShield(character, canParry)

	if not canParry then
		return
	end

	task.delay(PARRY_WINDOW, function()
		if not player.Parent then
			return
		end

		if player.Character ~= character then
			return
		end

		-- Prevent an old delayed task from changing a new block.
		if blockSessions[player] ~= session then
			return
		end

		if not character:GetAttribute("IsBlocking") then
			return
		end

		character:SetAttribute("IsParrying", false)
		character:SetAttribute("ParryExpiresAt", 0)

		setShieldAppearance(character, false)
	end)
end

--// STUNNING

local function stunPlayer(player)
	if stunning[player] then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	stunning[player] = true
	stunTokens[player] = (stunTokens[player] or 0) + 1

	local stunToken = stunTokens[player]

	local savedMovement = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
	}

	stopBlocking(player, character)

	character:SetAttribute("Stunned", true)

	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	createStunEffect(character)

	task.delay(STUN_TIME, function()
		if stunTokens[player] ~= stunToken then
			return
		end

		stunning[player] = nil

		if not player.Parent then
			return
		end

		if player.Character ~= character then
			return
		end

		if not humanoid.Parent or humanoid.Health <= 0 then
			return
		end

		character:SetAttribute("Stunned", false)

		humanoid.WalkSpeed =
			savedMovement.walkSpeed > 0
			and savedMovement.walkSpeed
			or DEFAULT_WALKSPEED

		humanoid.AutoRotate = savedMovement.autoRotate

		if humanoid.UseJumpPower then
			humanoid.JumpPower =
				savedMovement.jumpPower > 0
				and savedMovement.jumpPower
				or DEFAULT_JUMPPOWER
		else
			humanoid.JumpHeight =
				savedMovement.jumpHeight > 0
				and savedMovement.jumpHeight
				or DEFAULT_JUMPHEIGHT
		end
	end)
end

--// REMOTE

BlockRemote.OnServerEvent:Connect(function(player, status)
	local now = os.clock()
	local previousUse = lastRemoteUse[player] or 0

	if now - previousUse < REMOTE_COOLDOWN then
		return
	end

	lastRemoteUse[player] = now

	local character = player.Character
	if not character then
		return
	end

	if status == "StunRequest" then
		stunPlayer(player)
		return
	end

	if typeof(status) ~= "boolean" then
		return
	end

	if status then
		startBlocking(player, character)
	else
		stopBlocking(player, character)
	end
end)

--// CLEANUP

local function setupCharacter(player, character)
	invalidateBlockSession(player)

	stunning[player] = nil

	removeShield(character)

	character:SetAttribute("Stunned", false)
	character:SetAttribute("IsBlocking", false)
	character:SetAttribute("IsParrying", false)
	character:SetAttribute("BlockStartedAt", 0)
	character:SetAttribute("ParryExpiresAt", 0)

	setDamageHandlerBlocking(player, false)

	local humanoid = character:WaitForChild("Humanoid", 5)

	if humanoid then
		humanoid.Died:Connect(function()
			stunTokens[player] = (stunTokens[player] or 0) + 1
			stunning[player] = nil

			stopBlocking(player, character)
		end)
	end
end

local function setupPlayer(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)

	if player.Character then
		task.spawn(setupCharacter, player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerAdded:Connect(setupPlayer)

Players.PlayerRemoving:Connect(function(player)
	stunning[player] = nil
	stunTokens[player] = nil
	blockSessions[player] = nil
	lastBlockEnded[player] = nil
	lastRemoteUse[player] = nil
end)