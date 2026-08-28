-- Pure arena eligibility/random-choice policy used by MatchManager.
-- Keeping this module free of Roblox services makes the selection rules easy to regression-test.

local ArenaSelectionPolicy = {}

function ArenaSelectionPolicy.FilterAvailable(arenas, isLocked, isUsable)
	local available = {}

	for _, arena in ipairs(arenas) do
		if not isLocked(arena) and isUsable(arena) then
			table.insert(available, arena)
		end
	end

	return available
end

function ArenaSelectionPolicy.ChooseRandom(available, nextInteger)
	if #available == 0 then
		return nil
	end

	return available[nextInteger(1, #available)]
end

return ArenaSelectionPolicy
