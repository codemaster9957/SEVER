--!strict
-- Contract tests for scythe throw hook timing, tether strength, and continuous path following.
-- This repo does not currently provide a Luau test runner, but these pure contracts
-- keep the intended behavior explicit and runnable once a harness is added.

local Policy = require(script.Parent:WaitForChild("ScytheThrowPullPolicy"))

assert(Policy.GetPullDuration(0.12) >= 0.65, "close catches must still get a visible pull window")
assert(Policy.GetPullDuration(0.42) >= 0.65, "pull duration must be independent of visual return duration")
assert(Policy.GetPullDuration(1.2) <= 0.85, "hook pull must remain bounded")

local tether = Policy.GetTetherConfig()
assert(tether.MaxForce >= 1_000_000, "hook tether needs enough force to beat humanoid movement")
assert(tether.MaxVelocity >= 100, "hook tether must visibly drag targets")
assert(tether.Responsiveness >= 40, "hook tether must react immediately")
assert(tether.StopDistance >= 4 and tether.StopDistance <= 6, "hook must stop near, not inside, the thrower")

assert(Policy.IsHookActive(101.0, 100.0) == true, "active hook must suppress competing movement")
assert(Policy.IsHookActive(100.0, 100.0) == false, "expired hook must release movement")
assert(Policy.IsHookActive(nil, 100.0) == false, "missing hook timestamp is inactive")

-- A successful catch must stay attached while the projectile finishes travelling outward.
assert(Policy.ShouldContinueOutboundAfterContact(true) == true, "hooked targets must continue outbound with the scythe")
assert(Policy.ShouldContinueOutboundAfterContact(false) == false, "defended/non-hook contact should reverse immediately")

local outboundGoal = Policy.GetPathGoal(Vector3.new(24, 8, -3), 4)
assert(outboundGoal == Vector3.new(24, 4, -3), "hook path should follow projectile X/Z without lifting target root")

assert(Policy.DidHookFromDamageResult({
	damage = 18,
	blocked = false,
	parried = false,
	clashed = false,
	dodged = false,
}) == true, "real damaging hits hook")

assert(Policy.DidHookFromDamageResult({damage = 0, blocked = true}) == false, "blocked throws never hook")
assert(Policy.DidHookFromDamageResult({damage = 0, parried = true}) == false, "parried throws never hook")
assert(Policy.DidHookFromDamageResult({damage = 0, dodged = true}) == false, "dodged throws never hook")
