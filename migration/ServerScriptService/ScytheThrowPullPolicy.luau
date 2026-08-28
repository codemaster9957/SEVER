--!strict

local Policy = {}

local PULL_DURATION = 0.72
local PATH_UPDATE_INTERVAL = 1 / 120
local TETHER_CONFIG = table.freeze({
	RigidityEnabled = true,
	MaxForce = 4_000_000,
	MaxVelocity = 320,
	Responsiveness = 200,
	StopDistance = 5,
})

function Policy.GetPullDuration(_visualReturnDuration: number): number
	return PULL_DURATION
end

function Policy.GetTetherConfig()
	return TETHER_CONFIG
end

function Policy.GetPathUpdateInterval(): number
	return PATH_UPDATE_INTERVAL
end

function Policy.IsHookActive(hookedUntil: any, now: number?): boolean
	local current = now or os.clock()
	return type(hookedUntil) == "number" and hookedUntil > current
end

function Policy.ShouldContinueOutboundAfterContact(didHook: boolean): boolean
	-- A real damaging catch rides the remaining outbound path before the boomerang reverses.
	-- Defended/non-hook contact reverses immediately and never attaches the target.
	return didHook == true
end

function Policy.GetPathGoal(projectilePosition: Vector3, targetRootY: number): Vector3
	-- Follow the scythe horizontally through the side-on lane without lifting/dropping the victim.
	return Vector3.new(projectilePosition.X, targetRootY, projectilePosition.Z)
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
