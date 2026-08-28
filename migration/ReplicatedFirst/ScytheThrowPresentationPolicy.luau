--!strict

local Policy = {}

local HELD_EFFECT_CLASSES = table.freeze({
	Trail = true,
	ParticleEmitter = true,
	Beam = true,
})

function Policy.IsHeldEffectClass(className: string): boolean
	return HELD_EFFECT_CLASSES[className] == true
end

return table.freeze(Policy)
