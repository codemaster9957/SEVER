-- ArmourDataService
-- Persisted armour loadout/mastery adapter used by DamageHandler.

local ServerScriptService = game:GetService("ServerScriptService")
local DataService = require(ServerScriptService:WaitForChild("DataService"))

local ArmourDataService = {}

local VALID_SLOTS = {
	Torso = true,
	Head = true,
	Legs = true,
}

local function getDefaultData()
	return {
		Equipped = {
			Torso = "",
			Head = "",
			Legs = "",
		},
		Mastery = {},
	}
end

local function ensureProfileData(player)
	local profile = DataService.GetProfile(player)
	if not profile then return nil end

	profile.EquippedArmour = type(profile.EquippedArmour) == "table" and profile.EquippedArmour or {}
	profile.ArmourMastery = type(profile.ArmourMastery) == "table" and profile.ArmourMastery or {}

	for slot in pairs(VALID_SLOTS) do
		if type(profile.EquippedArmour[slot]) ~= "string" then
			-- Accept older flat profile keys if they exist, then migrate them into the
			-- canonical armour table.
			local legacy = profile["Equipped" .. slot]
			profile.EquippedArmour[slot] = type(legacy) == "string" and legacy or ""
		end
	end

	return profile
end

function ArmourDataService.GetPlayerData(player)
	if not player then return getDefaultData() end
	local profile = ensureProfileData(player)
	if not profile then return getDefaultData() end

	return {
		Equipped = profile.EquippedArmour,
		Mastery = profile.ArmourMastery,
	}
end

function ArmourDataService.SetEquipped(player, slot, armourName)
	if not player or not VALID_SLOTS[slot] or type(armourName) ~= "string" then
		return false
	end
	local profile = ensureProfileData(player)
	if not profile then return false end
	profile.EquippedArmour[slot] = armourName
	return true
end

function ArmourDataService.UpdateMastery(player, armourName, amount)
	if not player or type(armourName) ~= "string" or armourName == "" then return false end
	amount = tonumber(amount)
	if not amount or amount ~= amount or amount == math.huge or amount == -math.huge then return false end

	local profile = ensureProfileData(player)
	if not profile then return false end
	profile.ArmourMastery[armourName] = math.max(
		0,
		(tonumber(profile.ArmourMastery[armourName]) or 0) + amount
	)
	return true
end

function ArmourDataService.GetMastery(player, armourName)
	local profile = player and ensureProfileData(player) or nil
	if not profile then return 0 end
	return math.max(0, tonumber(profile.ArmourMastery[armourName]) or 0)
end

return ArmourDataService
