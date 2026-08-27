--!strict

local Policy = {}

local PULL_DURATION = 0.72

function Policy.GetPullDuration(_visualReturnDuration: number): number
	-- Hook gameplay must not collapse to the visual return time. A close-range catch can
	-- return visually in ~0.12s, but still needs enough server time to drag the target.
	return PULL_DURATION
end

function Policy.DidHookFromDamageResult(result: any): boolean
	return type(result) == "table"
		and type(result.damage) == "number"
		and result.damage > 0
		and result.blocked ~= true
		and result.parried ~= true
		and result.clashed ~= true
		and result.dodged ~= true
end

return table.freeze(Policy)
