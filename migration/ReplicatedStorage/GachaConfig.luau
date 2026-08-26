local GachaConfig = {}

GachaConfig.PullCost = 10
GachaConfig.CooldownSeconds = 0.75
GachaConfig.RarityWeights = {
	Common = 79,
	Rare = 15,
	Epic = 5,
	Legendary = 1,
}

GachaConfig.Pools = {
	Scythe = {
		{Id = "EmberScythe", Name = "Ember Scythe", Rarity = "Common"},
		{Id = "Frostbite", Name = "Frostbite", Rarity = "Rare"},
		{Id = "Void Reaper", Name = "Void Reaper", Rarity = "Epic"},
		{Id = "Astral Executioner", Name = "Astral Executioner", Rarity = "Legendary"},
	},
	Cosmetic = {
		{Id = "CinderTrail", Name = "Cinder Trail", Rarity = "Common"},
		{Id = "Halo Shards", Name = "Halo Shards", Rarity = "Rare"},
		{Id = "Void Aura", Name = "Void Aura", Rarity = "Epic"},
		{Id = "Celestial Crown", Name = "Celestial Crown", Rarity = "Legendary"},
	},
}

function GachaConfig.GetPool(poolName)
	return GachaConfig.Pools[poolName]
end

function GachaConfig.GetRarityColor(rarity)
	local colors = {
		Common = Color3.fromRGB(190, 200, 214),
		Rare = Color3.fromRGB(75, 165, 255),
		Epic = Color3.fromRGB(190, 90, 255),
		Legendary = Color3.fromRGB(255, 174, 55),
	}
	return colors[rarity] or colors.Common
end

return GachaConfig
