--!strict
-- Regression contract for low-latency scythe hook path following.

local PullPolicy = require(script.Parent:WaitForChild("ScytheThrowPullPolicy"))

local tether = PullPolicy.GetTetherConfig()
assert(tether.RigidityEnabled == true, "hook tether must be rigid enough to stay glued to the scythe path")
assert(tether.MaxVelocity >= 220, "hook tether must catch up fast enough to avoid visible lag")
assert(tether.Responsiveness >= 120, "hook tether must react nearly instantly")
assert(PullPolicy.GetPathUpdateInterval() <= (1 / 60), "hook target should update every physics frame, not every throw step")
