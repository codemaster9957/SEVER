--!strict
-- Contract tests for the scythe throw hook/pull timing and tether strength.
-- This repo does not currently provide a Luau test runner, but keeping this as a pure
-- spec makes the intended behavior explicit and runnable once a harness is added.

local Policy = require(script.Parent:WaitForChild("ScytheThrowPullPolicy"))

assert(Policy.GetPullDuration(0.12) >= 0.65, "close catches must still get a visible pull window")
assert(Policy.GetPullDuration(0.42) >= 0.65, "pull duration must be independent of visual return duration")
assert(Policy.GetPullDuration(1.2) <= 0.85, "hook pull must remain bounded")

local tether = Policy.GetTetherConfig()
assert(tether.MaxForce >= 1_000_000, "hook tether needs enough force to beat humanoid movement")
assert(tether.MaxVelocity >= 100, "hook tether must visibly drag targets")
assert(tether.Responsiveness >= 40, "hook tether must react immediately")
assert(tether.StopDistance >= 4 and tether.StopDistance <= 6, "hook must stop near, not inside, the thrower")

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
