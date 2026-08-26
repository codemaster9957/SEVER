-- Walking Trails Data
-- 10 trails from basic to godly rarity
-- Each trail has: id, name, rarity, color, description, effectConfig

local WalkingTrailsData = {
	[1] = {
		id = "basic_dust",
		name = "Dust Steps",
		rarity = "Common",
		rarityIndex = 1,
		description = "Small puffs of dust follow your steps.",
		color = Color3.fromRGB(180, 170, 155),
		effectConfig = {
			particleSize = 0.3,
			particleLifetime = 0.6,
			particleSpeed = 2,
			transparency = 0.4,
			emitCount = 3,
			fadeSpeed = 0.6,
		},
	},
	[2] = {
		id = "muddy_steps",
		name = "Muddy Steps",
		rarity = "Common",
		rarityIndex = 1,
		description = "Heavy muddy footprints that slowly fade.",
		color = Color3.fromRGB(110, 75, 45),
		effectConfig = {
			particleSize = 0.5,
			particleLifetime = 1.2,
			particleSpeed = 0.5,
			transparency = 0.3,
			emitCount = 2,
			fadeSpeed = 0.3,
		},
	},
	[3] = {
		id = "ice_path",
		name = "Frost Trail",
		rarity = "Uncommon",
		rarityIndex = 2,
		description = "Crystalline frost lingers where you walk.",
		color = Color3.fromRGB(200, 230, 255),
		effectConfig = {
			particleSize = 0.4,
			particleLifetime = 1.0,
			particleSpeed = 1,
			transparency = 0.25,
			emitCount = 4,
			fadeSpeed = 0.4,
			sparkle = true,
			sparkleColor = Color3.fromRGB(255, 255, 255),
		},
	},
	[4] = {
		id = "ember_walk",
		name = "Ember Stride",
		rarity = "Uncommon",
		rarityIndex = 2,
		description = "Smoldering embers glow beneath your feet.",
		color = Color3.fromRGB(255, 140, 30),
		effectConfig = {
			particleSize = 0.35,
			particleLifetime = 0.8,
			particleSpeed = 3,
			transparency = 0.2,
			emitCount = 5,
			fadeSpeed = 0.5,
			glow = true,
			glowColor = Color3.fromRGB(255, 100, 0),
		},
	},
	[5] = {
		id = "shadow_steps",
		name = "Shadow Steps",
		rarity = "Rare",
		rarityIndex = 3,
		description = "Dark wisps trail behind each step, fading into nothing.",
		color = Color3.fromRGB(60, 20, 80),
		effectConfig = {
			particleSize = 0.45,
			particleLifetime = 1.2,
			particleSpeed = 1.5,
			transparency = 0.15,
			emitCount = 6,
			fadeSpeed = 0.35,
			darkGlow = true,
			glowColor = Color3.fromRGB(80, 0, 120),
		},
	},
	[6] = {
		id = "star_glide",
		name = "Star Glide",
		rarity = "Rare",
		rarityIndex = 3,
		description = "Tiny stars twinkle and fade as you move.",
		color = Color3.fromRGB(255, 230, 150),
		effectConfig = {
			particleSize = 0.3,
			particleLifetime = 1.0,
			particleSpeed = 2,
			transparency = 0.1,
			emitCount = 7,
			fadeSpeed = 0.4,
			sparkle = true,
			sparkleColor = Color3.fromRGB(255, 250, 200),
			glow = true,
			glowColor = Color3.fromRGB(255, 220, 100),
		},
	},
	[7] = {
		id = "crystal_walk",
		name = "Crystal Walk",
		rarity = "Epic",
		rarityIndex = 4,
		description = "Shattered crystal shards form and dissolve beneath you.",
		color = Color3.fromRGB(180, 100, 255),
		effectConfig = {
			particleSize = 0.5,
			particleLifetime = 1.4,
			particleSpeed = 1,
			transparency = 0.08,
			emitCount = 8,
			fadeSpeed = 0.3,
			sparkle = true,
			sparkleColor = Color3.fromRGB(220, 180, 255),
			glow = true,
			glowColor = Color3.fromRGB(150, 70, 255),
			shards = true,
		},
	},
	[8] = {
		id = "void_trail",
		name = "Void Trail",
		rarity = "Epic",
		rarityIndex = 4,
		description = "A rift in reality opens with every step, pulling in light.",
		color = Color3.fromRGB(40, 0, 60),
		effectConfig = {
			particleSize = 0.6,
			particleLifetime = 1.6,
			particleSpeed = 0.8,
			transparency = 0.05,
			emitCount = 10,
			fadeSpeed = 0.25,
			darkGlow = true,
			glowColor = Color3.fromRGB(60, 0, 100),
			vortex = true,
			vortexStrength = 0.3,
		},
	},
	[9] = {
		id = "soul_reaper",
		name = "Soul Reaper",
		rarity = "Legendary",
		rarityIndex = 5,
		description = "Spectral green flames mark the reaper's path.",
		color = Color3.fromRGB(50, 255, 80),
		effectConfig = {
			particleSize = 0.55,
			particleLifetime = 1.8,
			particleSpeed = 1.2,
			transparency = 0.02,
			emitCount = 12,
			fadeSpeed = 0.2,
			sparkle = true,
			sparkleColor = Color3.fromRGB(100, 255, 120),
			glow = true,
			glowColor = Color3.fromRGB(30, 200, 60),
			flame = true,
			trailLifetime = 0.3,
		},
	},
	[10] = {
		id = "godly_celestial",
		name = "Celestial Ascension",
		rarity = "Godly",
		rarityIndex = 6,
		description = "Divine light erupts with each step — reserved for legends.",
		color = Color3.fromRGB(255, 215, 0),
		effectConfig = {
			particleSize = 0.7,
			particleLifetime = 2.0,
			particleSpeed = 2.5,
			transparency = 0,
			emitCount = 16,
			fadeSpeed = 0.15,
			sparkle = true,
			sparkleColor = Color3.fromRGB(255, 255, 200),
			glow = true,
			glowColor = Color3.fromRGB(255, 200, 50),
			rainbow = true,
			trailLifetime = 0.4,
			beamCount = 3,
		},
	},
}

-- Rarity weights for claw machine pulls
local RARITY_WEIGHTS = {
	["Common"] = 50,
	["Uncommon"] = 25,
	["Rare"] = 15,
	["Epic"] = 7,
	["Legendary"] = 2.5,
	["Godly"] = 0.5,
}

local RARITY_DISPLAY_COLORS = {
	["Common"] = Color3.fromRGB(180, 180, 180),
	["Uncommon"] = Color3.fromRGB(40, 200, 80),
	["Rare"] = Color3.fromRGB(50, 130, 255),
	["Epic"] = Color3.fromRGB(170, 70, 255),
	["Legendary"] = Color3.fromRGB(255, 180, 20),
	["Godly"] = Color3.fromRGB(255, 50, 50),
}

function WalkingTrailsData.GetTrailById(id)
	for _, trail in ipairs(WalkingTrailsData) do
		if trail.id == id then
			return trail
		end
	end
	return nil
end

function WalkingTrailsData.GetTrailsByRarity(rarity)
	local results = {}
	for _, trail in ipairs(WalkingTrailsData) do
		if trail.rarity == rarity then
			table.insert(results, trail)
		end
	end
	return results
end

function WalkingTrailsData.RollRandomTrail()
	local totalWeight = 0
	for _, trail in ipairs(WalkingTrailsData) do
		local weight = RARITY_WEIGHTS[trail.rarity] or 1
		totalWeight += weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0

	for _, trail in ipairs(WalkingTrailsData) do
		local weight = RARITY_WEIGHTS[trail.rarity] or 1
		cumulative += weight
		if roll <= cumulative then
			return trail
		end
	end

	return WalkingTrailsData[1] -- fallback to common
end

function WalkingTrailsData.GetRarityColor(rarity)
	return RARITY_DISPLAY_COLORS[rarity] or Color3.fromRGB(255, 255, 255)
end

function WalkingTrailsData.GetRarityWeight(rarity)
	return RARITY_WEIGHTS[rarity] or 0
end

return WalkingTrailsData
