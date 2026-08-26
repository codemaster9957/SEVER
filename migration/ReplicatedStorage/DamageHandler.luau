local DamageHandler = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatEvents = ReplicatedStorage:WaitForChild("CombatEvents")
local BlockRemote = CombatEvents:WaitForChild("BlockRemote")

local CombatJuice = require(script.Parent:WaitForChild("CombatJuice"))

local MAX_HEALTH = 100

local CLASH_HITSTOP = 0.18
local CLASH_KNOCKBACK = 90
local CLASH_UP_FORCE = 15
local CLASH_SIDE_FORCE = 24

local CLASH_SOUND_ID = "rbxassetid://107477539382034"

local matchPlayerHealth = {}
local matchOver = false
local overtimeActive = false
local isBlocking = {}

--------------------------------------------------
-- HELPERS
--------------------------------------------------

local function getHealthValue(player, humanoid)
	if player and matchPlayerHealth[player] ~= nil then
		return matchPlayerHealth[player]
	end

	return humanoid and humanoid.Health or MAX_HEALTH
end

local function safeUnit(vector, fallback)
	if vector.Magnitude <= 0.001 then
		return fallback or Vector3.new(0, 0, -1)
	end

	return vector.Unit
end

local function getRoot(character)
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid(character)
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function isAttacking(character)
	if not character then
		return false
	end

	if overtimeActive then
		return false
	end

	local attackUntil = character:GetAttribute("AttackActiveUntil")

	return typeof(attackUntil) == "number"
		and os.clock() < attackUntil
end

local function isDodging(character)
	if not character then
		return false, false
	end

	if overtimeActive then
		return true, true
	end

	local perfectDodgeUntil =
		character:GetAttribute("PerfectDodgeUntil")

	local perfectDodgeActive =
		typeof(perfectDodgeUntil) == "number"
		and os.clock() <= perfectDodgeUntil

	local dashInvulnerable =
		character:GetAttribute("IsDashInvulnerable") == true

	return perfectDodgeActive or dashInvulnerable,
		dashInvulnerable
end

--------------------------------------------------
-- CLASH VFX
--------------------------------------------------

local function flashCharacter(character)
	if not character then
		return
	end

	local highlight = Instance.new("Highlight")

	highlight.Name = "ClashHighlight"
	highlight.FillColor = Color3.fromRGB(255, 245, 180)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 0.2
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character

	local tween = TweenService:Create(
		highlight,
		TweenInfo.new(
			0.25,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			FillTransparency = 1,
			OutlineTransparency = 1,
		}
	)

	tween:Play()

	Debris:AddItem(highlight, 0.3)
end

local function makeSlashBeam(
	position,
	direction,
	length,
	thickness,
	color
)
	local beam = Instance.new("Part")

	beam.Name = "ClashSlashBeam"
	beam.Material = Enum.Material.Neon
	beam.Color = color

	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false

	beam.Size =
		Vector3.new(thickness, thickness, length)

	beam.CFrame =
		CFrame.lookAt(position, position + direction)

	beam.Parent = workspace

	local tween = TweenService:Create(
		beam,
		TweenInfo.new(
			0.16,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		),
		{
			Size = Vector3.new(
				0.05,
				0.05,
				length * 1.45
			),

			Transparency = 1,
		}
	)

	tween:Play()

	Debris:AddItem(beam, 0.2)
end

local function makeClashShockwave(position, direction)
	local flash = Instance.new("Part")

	flash.Name = "ClashFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon

	flash.Color = Color3.fromRGB(
		255,
		255,
		230
	)

	flash.Transparency = 0

	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false

	flash.Size = Vector3.new(6, 6, 6)
	flash.CFrame = CFrame.new(position)

	flash.Parent = workspace

	local light = Instance.new("PointLight")

	light.Brightness = 10
	light.Range = 35

	light.Color = Color3.fromRGB(
		255,
		240,
		190
	)

	light.Parent = flash

	if CLASH_SOUND_ID ~= "" then
		local sound = Instance.new("Sound")

		sound.SoundId = CLASH_SOUND_ID
		sound.Volume = 2

		sound.PlaybackSpeed =
			math.random(92, 108) / 100

		sound.RollOffMinDistance = 10
		sound.RollOffMaxDistance = 90

		sound.Parent = flash

		sound:Play()
	end

	local flashTween = TweenService:Create(
		flash,
		TweenInfo.new(
			0.16,
			Enum.EasingStyle.Exponential,
			Enum.EasingDirection.Out
		),
		{
			Size = Vector3.new(
				38,
				38,
				38
			),

			Transparency = 1,
		}
	)

	flashTween:Play()

	Debris:AddItem(flash, 0.3)

	--------------------------------------------------
	-- RINGS
	--------------------------------------------------

	for i = 1, 3 do
		local ring = Instance.new("Part")

		ring.Name = "ClashRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon

		ring.Color =
			Color3.fromRGB(
				255,
				255,
				255
			)

		ring.Transparency = 0

		ring.Anchored = true
		ring.CanCollide = false
		ring.CanTouch = false
		ring.CanQuery = false

		ring.Size =
			Vector3.new(
				0.16,
				2,
				2
			)

		local angle =
			math.rad((i - 1) * 60)

		ring.CFrame =
			CFrame.new(position)
			* CFrame.Angles(
				math.rad(90),
				angle,
				0
			)

		ring.Parent = workspace

		local ringTween =
			TweenService:Create(
				ring,

				TweenInfo.new(
					0.22 + i * 0.035,

					Enum.EasingStyle.Exponential,

					Enum.EasingDirection.Out
				),

				{
					Size =
					Vector3.new(
						0.16,

						38 + i * 7,

						38 + i * 7
					),

					Transparency = 1,
				}
			)

		ringTween:Play()

		Debris:AddItem(
			ring,
			0.36
		)
	end

	--------------------------------------------------
	-- SLASHES
	--------------------------------------------------

	local flatDir =
		safeUnit(
			Vector3.new(
				direction.X,
				0,
				direction.Z
			),

			Vector3.new(
				0,
				0,
				-1
			)
		)

	local sideDir =
		safeUnit(
			flatDir:Cross(
				Vector3.new(
					0,
					1,
					0
				)
			),

			Vector3.new(
				1,
				0,
				0
			)
		)

	makeSlashBeam(
		position,
		flatDir,
		36,
		0.6,
		Color3.fromRGB(255, 255, 255)
	)

	makeSlashBeam(
		position,
		-flatDir,
		36,
		0.6,
		Color3.fromRGB(255, 230, 120)
	)

	makeSlashBeam(
		position,
		sideDir,
		26,
		0.4,
		Color3.fromRGB(255, 245, 190)
	)

	makeSlashBeam(
		position,
		-sideDir,
		26,
		0.4,
		Color3.fromRGB(255, 245, 190)
	)

	--------------------------------------------------
	-- SPARKS
	--------------------------------------------------

	for i = 1, 50 do
		local spark = Instance.new("Part")

		spark.Name = "ClashSpark"
		spark.Material = Enum.Material.Neon

		if i % 3 == 0 then
			spark.Color =
				Color3.fromRGB(
					255,
					170,
					60
				)
		else
			spark.Color =
				Color3.fromRGB(
					255,
					255,
					210
				)
		end

		spark.Anchored = false

		spark.CanCollide = false
		spark.CanTouch = false
		spark.CanQuery = false

		spark.Size =
			Vector3.new(
				0.12,
				0.12,
				math.random(10, 24) / 10
			)

		local randomDir =
			safeUnit(
				Vector3.new(
					math.random(-100, 100) / 100,

					math.random(5, 95) / 100,

					math.random(-100, 100) / 100
				),

				direction
			)

		spark.CFrame =
			CFrame.lookAt(
				position,
				position + randomDir
			)

		spark.AssemblyLinearVelocity =
			randomDir
			* math.random(
				70,
				135
			)

		spark.Parent = workspace

		local sparkTween =
			TweenService:Create(
				spark,

				TweenInfo.new(
					0.22,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				),

				{
					Transparency = 1,
				}
			)

		sparkTween:Play()

		Debris:AddItem(
			spark,
			0.3
		)
	end
end

--------------------------------------------------
-- CLASH HITSTOP
--------------------------------------------------

local function applyClashHitstop(characterA, characterB)
	local token = os.clock()

	local function freezeCharacter(character)
		local humanoid = getHumanoid(character)
		local root = getRoot(character)

		if not humanoid or not root then
			return nil
		end

		local data = {
			humanoid = humanoid,

			root = root,

			walkSpeed =
				humanoid.WalkSpeed,

			jumpPower =
				humanoid.JumpPower,

			autoRotate =
				humanoid.AutoRotate,

			anchored =
				root.Anchored,
		}

		character:SetAttribute(
			"ClashFreezeToken",
			token
		)

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0

		humanoid.AutoRotate = false

		root.AssemblyLinearVelocity =
			Vector3.zero

		root.AssemblyAngularVelocity =
			Vector3.zero

		root.Anchored = true

		return data
	end

	local dataA =
		freezeCharacter(characterA)

	local dataB =
		freezeCharacter(characterB)

	task.delay(
		CLASH_HITSTOP,

		function()
			local function restoreCharacter(
				character,
				data
			)
				if not character or not data then
					return
				end

				if character:GetAttribute(
					"ClashFreezeToken"
					) ~= token then
					return
				end

				if not data.humanoid
					or not data.humanoid.Parent then
					return
				end

				if not data.root
					or not data.root.Parent then
					return
				end

				data.root.Anchored =
					data.anchored

				data.humanoid.WalkSpeed =
					data.walkSpeed

				data.humanoid.JumpPower =
					data.jumpPower

				data.humanoid.AutoRotate =
					data.autoRotate

				character:SetAttribute(
					"ClashFreezeToken",
					nil
				)
			end

			restoreCharacter(
				characterA,
				dataA
			)

			restoreCharacter(
				characterB,
				dataB
			)
		end
	)
end

--------------------------------------------------
-- CLASH
--------------------------------------------------

local function doClash(
	character,
	attackerCharacter,
	player,
	attackerPlayer,
	targetRoot,
	attackerRoot
)
	local midpoint =
		(targetRoot.Position
			+ attackerRoot.Position)
		/ 2

	local dir =
		safeUnit(
			targetRoot.Position
			- attackerRoot.Position,

			targetRoot.CFrame.LookVector
		)

	local sideDir =
		safeUnit(
			dir:Cross(
				Vector3.new(
					0,
					1,
					0
				)
			),

			Vector3.new(
				1,
				0,
				0
			)
		)

	character:SetAttribute(
		"AttackActiveUntil",
		0
	)

	attackerCharacter:SetAttribute(
		"AttackActiveUntil",
		0
	)

	character:SetAttribute(
		"Clashed",
		os.clock() + 0.45
	)

	attackerCharacter:SetAttribute(
		"Clashed",
		os.clock() + 0.45
	)

	flashCharacter(character)
	flashCharacter(attackerCharacter)

	CombatJuice.Emit(
		"Clash",
		{
			position = midpoint,

			playerA =
				player
				and player.UserId
				or 0,

			playerB =
				attackerPlayer
				and attackerPlayer.UserId
				or 0,
		}
	)

	CombatJuice.Emit(
		"HitImpact",
		{
			position = midpoint,

			power = 120,

			heavy = true,

			combo = 1,

			ko = false,

			attackerUserId =
				attackerPlayer
				and attackerPlayer.UserId
				or 0,

			targetUserId =
				player
				and player.UserId
				or 0,
		}
	)

	makeClashShockwave(
		midpoint,
		dir
	)

	applyClashHitstop(
		character,
		attackerCharacter
	)

	task.delay(
		CLASH_HITSTOP,

		function()
			if not targetRoot.Parent
				or not attackerRoot.Parent then
				return
			end

			targetRoot.AssemblyLinearVelocity =
				(dir
					* CLASH_KNOCKBACK
					* 1.5)

				+ (sideDir
					* CLASH_SIDE_FORCE)

				+ Vector3.new(
					0,
					CLASH_UP_FORCE,
					0
				)

			attackerRoot.AssemblyLinearVelocity =
				(-dir
					* CLASH_KNOCKBACK
					* 1.5)

				+ (-sideDir
					* CLASH_SIDE_FORCE)

				+ Vector3.new(
					0,
					CLASH_UP_FORCE,
					0
				)

			targetRoot.AssemblyAngularVelocity =
				Vector3.new(
					math.random(-15, 15),
					math.random(-25, 25),
					math.random(-15, 15)
				)

			attackerRoot.AssemblyAngularVelocity =
				Vector3.new(
					math.random(-15, 15),
					math.random(-25, 25),
					math.random(-15, 15)
				)
		end
	)
end

--------------------------------------------------
-- PLAYER HEALTH
--------------------------------------------------

function DamageHandler.InitializePlayerHealth(player)
	if not player then
		return
	end

	matchPlayerHealth[player] =
		MAX_HEALTH

	matchOver = false
	overtimeActive = false
end

function DamageHandler.ResetMatch()
	table.clear(matchPlayerHealth)
	table.clear(isBlocking)

	matchOver = false
	overtimeActive = false
end

function DamageHandler.RemovePlayer(player)
	if not player then
		return
	end

	matchPlayerHealth[player] = nil
	isBlocking[player] = nil
end

function DamageHandler.GetPlayerHealth(player)
	return matchPlayerHealth[player]
		or MAX_HEALTH
end

function DamageHandler.SetPlayerHealth(
	player,
	amount
)
	if not player then
		return
	end

	local health =
		math.clamp(
			tonumber(amount)
			or MAX_HEALTH,

			0,
			MAX_HEALTH
		)

	matchPlayerHealth[player] =
		health

	local character =
		player.Character

	local humanoid =
		character
		and character:FindFirstChildOfClass(
			"Humanoid"
		)

	if humanoid then
		humanoid.Health = health
	end

	if health > 0 then
		matchOver = false
	end
end

function DamageHandler.IsMatchOver()
	return matchOver
end

function DamageHandler.SetMatchOver()
	matchOver = true
end

function DamageHandler.SetOvertimeActive(status)
	overtimeActive = status
end

--------------------------------------------------
-- ARMOUR
--------------------------------------------------

local ArmourDataService =
	require(
		game:GetService(
			"ServerScriptService"
		):WaitForChild(
			"ArmourDataService"
		)
	)

--------------------------------------------------
-- APPLY DAMAGE
--------------------------------------------------

function DamageHandler.ApplyDamage(
	humanoid,
	damage,
	attackerPlayer
)
	damage =
		tonumber(damage)
		or 0

	damage =
		math.max(
			0,
			damage
		)

	if not humanoid
		or humanoid.Health <= 0 then
		return nil
	end

	if matchOver
		or overtimeActive then
		return nil
	end

	local character =
		humanoid.Parent

	if not character then
		return nil
	end

	local player =
		Players:GetPlayerFromCharacter(
			character
		)

	local targetRoot =
		getRoot(character)

	local blocked = false
	local parried = false
	local clashed = false
	local dodged = false

	--------------------------------------------------
	-- LASTLIGHT MAIL
	--------------------------------------------------

	if player
		and matchPlayerHealth[player] ~= nil
		and matchPlayerHealth[player] <= 25
		and matchPlayerHealth[player] > 0 then

		local armourData =
			ArmourDataService.GetPlayerData(
				player
			)

		if armourData.Equipped.Torso
			== "LastlightMail"

			and not character:GetAttribute(
				"LastlightUsed"
			) then

			character:SetAttribute(
				"LastlightUsed",
				true
			)

			if targetRoot then
				CombatJuice.Emit(
					"HitImpact",
					{
						position =
							targetRoot.Position,

						power = 80,

						heavy = true,

						ko = false,

						targetUserId =
							player.UserId,
					}
				)
			end

			return {
				damage = 0,

				blocked = false,

				parried = false,

				clashed = false,

				dodged = true,

				targetPlayer =
					player,

				remainingHealth =
					matchPlayerHealth[
				player
				],

				attackerPlayer =
					attackerPlayer,
			}
		end
	end

	--------------------------------------------------
	-- DODGE
	--------------------------------------------------

	local dodgeActive,
		isDashDodge =
		isDodging(character)

	if dodgeActive then
		dodged = true

		if not isDashDodge then
			CombatJuice.Emit(
				"PerfectDodge",
				{
					targetUserId =
						player
						and player.UserId
						or 0,

					attackerUserId =
						attackerPlayer
						and attackerPlayer.UserId
						or 0,
				}
			)

			character:SetAttribute(
				"CounterBoostUntil",
				os.clock() + 1.2
			)
		end

		return {
			damage = 0,

			blocked = false,

			parried = false,

			clashed = false,

			dodged = true,

			targetPlayer =
				player,

			remainingHealth =
				getHealthValue(
					player,
					humanoid
				),

			attackerPlayer =
				attackerPlayer,
		}
	end

	--------------------------------------------------
	-- CLASH
	--------------------------------------------------

	if attackerPlayer
		and attackerPlayer.Character

		and isAttacking(character)

		and isAttacking(
			attackerPlayer.Character
		) then

		local attackerCharacter =
			attackerPlayer.Character

		local attackerRoot =
			getRoot(
				attackerCharacter
			)

		if targetRoot
			and attackerRoot then

			clashed = true
			damage = 0

			doClash(
				character,
				attackerCharacter,
				player,
				attackerPlayer,
				targetRoot,
				attackerRoot
			)

			return {
				damage = 0,

				blocked = false,

				parried = false,

				clashed = true,

				dodged = false,

				targetPlayer =
					player,

				remainingHealth =
					getHealthValue(
						player,
						humanoid
					),

				attackerPlayer =
					attackerPlayer,
			}
		end
	end

	--------------------------------------------------
	-- PARRY
	--------------------------------------------------

	if character:GetAttribute(
		"IsParrying"
		) == true then

		parried = true
		damage = 0

		if targetRoot then
			CombatJuice.Emit(
				"Parry",
				{
					position =
						targetRoot.Position,

					targetUserId =
						player
						and player.UserId
						or 0,

					attackerUserId =
						attackerPlayer
						and attackerPlayer.UserId
						or 0,
				}
			)

			--------------------------------------------------
			-- DUELIST MASK MASTERY
			--------------------------------------------------

			if player then
				local armourData =
					ArmourDataService.GetPlayerData(
						player
					)

				if armourData.Equipped.Head
					== "DuelistMask" then

					ArmourDataService.UpdateMastery(
						player,
						"DuelistMask",
						1
					)
				end
			end
		end

		--------------------------------------------------
		-- ONE-HIT BLOCK
		--------------------------------------------------

	elseif character:GetAttribute(
		"IsBlocking"
		) == true

			or (
				player
				and isBlocking[player]
			) then

		blocked = true

		--------------------------------------------------
		-- CONSUME BLOCK IMMEDIATELY
		--------------------------------------------------

		if player then
			-- Remove the block on the server immediately.
			-- This makes it genuinely one-hit only.

			isBlocking[player] = nil

			character:SetAttribute(
				"IsBlocking",
				false
			)

			-- Tell the player's LocalScript that
			-- the block SUCCESSFULLY caught an attack.
			--
			-- The LocalScript should end the block
			-- with NO cooldown.

			BlockRemote:FireClient(
				player,
				"BlockSuccess"
			)
		end

		--------------------------------------------------
		-- IRONROOT PLATE
		--------------------------------------------------

		local ironrootBonus = false

		if player then
			local armourData =
				ArmourDataService.GetPlayerData(
					player
				)

			if armourData.Equipped.Torso
				== "IronrootPlate" then

				local lastUse =
					character:GetAttribute(
						"IronrootLastUse"
					)
					or 0

				if os.clock() - lastUse
					>= 12 then

					character:SetAttribute(
						"IronrootLastUse",
						os.clock()
					)

					ironrootBonus =
						true
				end
			end
		end

		--------------------------------------------------
		-- BLOCK NEGATES THE HIT
		--------------------------------------------------

		damage = 0

		--------------------------------------------------
		-- BLOCK VFX
		--------------------------------------------------

		if targetRoot then
			CombatJuice.Emit(
				"Block",
				{
					position =
						targetRoot.Position,

					attackerUserId =
						attackerPlayer
						and attackerPlayer.UserId
						or 0,

					targetUserId =
						player
						and player.UserId
						or 0,
				}
			)
		end

		--------------------------------------------------
		-- RETURN BLOCK RESULT
		--------------------------------------------------

		return {
			damage = 0,

			blocked = true,

			parried = false,

			clashed = false,

			dodged = false,

			targetPlayer =
				player,

			remainingHealth =
				getHealthValue(
					player,
					humanoid
				),

			attackerPlayer =
				attackerPlayer,

			ironrootBonus =
				ironrootBonus,
		}
	end

	--------------------------------------------------
	-- KNOCKBACK
	--------------------------------------------------

	if damage > 0
		and attackerPlayer
		and attackerPlayer.Character then

		local attackerRoot =
			getRoot(
				attackerPlayer.Character
			)

		if attackerRoot
			and targetRoot then

			local knockbackDir =
				safeUnit(
					targetRoot.Position
					- attackerRoot.Position,

					targetRoot.CFrame.LookVector
				)

			--------------------------------------------------
			-- ANCHOR BOOTS
			--------------------------------------------------

			local kbReduc = 1

			if player then
				local armourData =
					ArmourDataService.GetPlayerData(
						player
					)

				if armourData.Equipped.Legs
					== "AnchorBoots" then

					kbReduc = 0.5
				end
			end

			local upForce =
				damage > 12
				and 35
				or 5

			targetRoot.AssemblyLinearVelocity =
				knockbackDir
				* 65
				* kbReduc

				+ Vector3.new(
					0,

					upForce
					* kbReduc,

					0
				)

			attackerRoot.AssemblyLinearVelocity =
				-knockbackDir
				* 45

				+ Vector3.new(
					0,
					5,
					0
				)

			if upForce > 20
				and player then

				CombatJuice.EmitTo(
					player,
					"LaunchWindow",
					{
						targetUserId =
							player.UserId,
					}
				)
			end
		end
	end

	--------------------------------------------------
	-- DAMAGE
	--------------------------------------------------

	if damage > 0 then
		if player
			and matchPlayerHealth[player]
			~= nil then

			matchPlayerHealth[player] =
				math.max(
					0,

					matchPlayerHealth[player]
					- damage
				)

			if matchPlayerHealth[player]
				<= 0 then

				matchOver = true
			end
		end

		humanoid:TakeDamage(
			damage
		)
	end

	local remainingHealth =
		getHealthValue(
			player,
			humanoid
		)

	local ko =
		remainingHealth <= 0
		or humanoid.Health <= 0

	--------------------------------------------------
	-- HIT IMPACT
	--------------------------------------------------

	if damage > 0
		and targetRoot then

		CombatJuice.Emit(
			"HitImpact",
			{
				position =
					targetRoot.Position,

				power = 50,

				heavy =
					damage > 20,

				combo = 1,

				ko = ko,

				attackerUserId =
					attackerPlayer
					and attackerPlayer.UserId
					or 0,

				targetUserId =
					player
					and player.UserId
					or 0,
			}
		)
	end

	return {
		damage = damage,

		blocked = blocked,

		parried = parried,

		clashed = clashed,

		dodged = dodged,

		targetPlayer =
			player,

		remainingHealth =
			remainingHealth,

		attackerPlayer =
			attackerPlayer,
	}
end

--------------------------------------------------
-- BLOCK STATE
--------------------------------------------------

function DamageHandler.SetBlocking(
	player,
	status
)
	if not player then
		return
	end

	local blocking =
		status == true

	isBlocking[player] =
		blocking or nil

	if player.Character then
		player.Character:SetAttribute(
			"IsBlocking",
			blocking
		)
	end
end

return DamageHandler