-- ArmourDataService
-- Provides armour loadout data used by DamageHandler.
-- Returns an empty loadout by default so combat systems (including the
-- training dummy prompt) can load without a full armour system present.

local ArmourDataService = {}

local function getDefaultData()
	return {
		Equipped = {
			Torso = "",
			Head = "",
			Legs = "",
		},
	}
end

function ArmourDataService.GetPlayerData(player)
	if not player then
		return getDefaultData()
	end

	local data = player:FindFirstChild("ArmourData")
	if data and typeof(data.Value) == "table" then
		return data.Value
	end

	return getDefaultData()
end

function ArmourDataService.UpdateMastery(player, armourName, amount)
	-- Mastery tracking is not implemented yet; this is a safe no-op.
	return true
end

return ArmourDataService