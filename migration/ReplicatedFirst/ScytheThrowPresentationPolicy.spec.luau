--!strict
-- Contract for which held-sc ythe effects must be suspended while the real weapon is thrown.

local Policy = require(script.Parent:WaitForChild("ScytheThrowPresentationPolicy"))

assert(Policy.IsHeldEffectClass("Trail") == true, "held Trail must be disabled during throw")
assert(Policy.IsHeldEffectClass("ParticleEmitter") == true, "held particle emitters must be disabled during throw")
assert(Policy.IsHeldEffectClass("Beam") == true, "held beams must be disabled during throw")
assert(Policy.IsHeldEffectClass("Highlight") == false, "unrelated visual instances must not be toggled")
assert(Policy.IsHeldEffectClass("Attachment") == false, "attachments must remain intact")
