local RarityConfig = {}

RarityConfig.Tiers = {
	Common = {
		Order = 1,
		Color = Color3.fromRGB(190, 200, 214),
		Weight = 40,
		GlowIntensity = 0,
		ParticleRate = 0,
		ParticleColor = Color3.fromRGB(190, 200, 214),
		SoundId = "",
		CapsuleMaterial = Enum.Material.SmoothPlastic,
		CapsuleColor = Color3.fromRGB(160, 165, 175),
		TokenValue = 1,
	},
	Uncommon = {
		Order = 2,
		Color = Color3.fromRGB(80, 200, 120),
		Weight = 25,
		GlowIntensity = 0.3,
		ParticleRate = 5,
		ParticleColor = Color3.fromRGB(80, 200, 120),
		SoundId = "",
		CapsuleMaterial = Enum.Material.SmoothPlastic,
		CapsuleColor = Color3.fromRGB(80, 200, 120),
		TokenValue = 3,
	},
	Rare = {
		Order = 3,
		Color = Color3.fromRGB(75, 165, 255),
		Weight = 18,
		GlowIntensity = 0.6,
		ParticleRate = 10,
		ParticleColor = Color3.fromRGB(75, 165, 255),
		SoundId = "",
		CapsuleMaterial = Enum.Material.Neon,
		CapsuleColor = Color3.fromRGB(75, 165, 255),
		TokenValue = 10,
	},
	Epic = {
		Order = 4,
		Color = Color3.fromRGB(190, 90, 255),
		Weight = 10,
		GlowIntensity = 1.0,
		ParticleRate = 20,
		ParticleColor = Color3.fromRGB(190, 90, 255),
		SoundId = "",
		CapsuleMaterial = Enum.Material.Neon,
		CapsuleColor = Color3.fromRGB(190, 90, 255),
		TokenValue = 30,
	},
	Legendary = {
		Order = 5,
		Color = Color3.fromRGB(255, 174, 55),
		Weight = 5,
		GlowIntensity = 1.5,
		ParticleRate = 35,
		ParticleColor = Color3.fromRGB(255, 174, 55),
		SoundId = "",
		CapsuleMaterial = Enum.Material.Neon,
		CapsuleColor = Color3.fromRGB(255, 174, 55),
		TokenValue = 100,
	},
	Mythic = {
		Order = 6,
		Color = Color3.fromRGB(255, 55, 90),
		Weight = 2,
		GlowIntensity = 2.0,
		ParticleRate = 50,
		ParticleColor = Color3.fromRGB(255, 55, 90),
		SoundId = "",
		CapsuleMaterial = Enum.Material.ForceField,
		CapsuleColor = Color3.fromRGB(255, 55, 90),
		TokenValue = 500,
	},
}

RarityConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

function RarityConfig.GetTier(rarity)
	return RarityConfig.Tiers[rarity]
end

function RarityConfig.GetColor(rarity)
	local tier = RarityConfig.Tiers[rarity]
	return tier and tier.Color or Color3.fromRGB(190, 200, 214)
end

function RarityConfig.GetTokenValue(rarity)
	local tier = RarityConfig.Tiers[rarity]
	return tier and tier.TokenValue or 1
end

function RarityConfig.Compare(a, b)
	local tierA = RarityConfig.Tiers[a]
	local tierB = RarityConfig.Tiers[b]
	return (tierA and tierA.Order or 0) < (tierB and tierB.Order or 0)
end

return RarityConfig
