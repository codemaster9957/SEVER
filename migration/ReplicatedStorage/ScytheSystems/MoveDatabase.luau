local MoveDatabase = {}

MoveDatabase.Moves = {
	soul_reap = {
		MoveId = "soul_reap",
		Name = "Soul Reap",
		Description = "Blink through an enemy, mark their soul, then detonate a devastating delayed slash.",
		Rarity = "Mythic",
		Icon = "",
		Cooldown = 9,
		Tradable = false,
		AnimationId = "",
		ModuleName = "SoulReap",
		Effects = { "Dash", "Stun", "Soul Mark", "Delayed Damage", "Knockback" },
		Tags = { "Assassination", "Gap-closer", "Side-axis", "Signature" },
		Damage = 30,
		Range = 27,
		AllowDuplicate = false,
	},
	quick_reap = {
		MoveId = "quick_reap",
		Name = "Quick Reap",
		Description = "A fast forward lunge that closes distance instantly.",
		Rarity = "Common",
		Icon = "",
		Cooldown = 4,
		Tradable = true,
		AnimationId = "",
		ModuleName = "QuickReap",
		Effects = { "Dash", "Damage" },
		Tags = { "Gap-closer", "Fast" },
		Damage = 10,
		Range = 15,
		AllowDuplicate = false,
	},
	shadow_dash = {
		MoveId = "shadow_dash",
		Name = "Shadow Dash",
		Description = "Dash forward leaving a shadow clone that explodes after a delay.",
		Rarity = "Uncommon",
		Icon = "",
		Cooldown = 8,
		Tradable = true,
		AnimationId = "",
		ModuleName = "ShadowDash",
		Effects = { "Dash", "Clone", "Explosion" },
		Tags = { "Gap-closer", "AOE", "Delayed" },
		Damage = 18,
		Range = 20,
		AllowDuplicate = false,
	},
	phantom_slash = {
		MoveId = "phantom_slash",
		Name = "Phantom Slash",
		Description = "A wide sweeping attack that phases through blocks.",
		Rarity = "Rare",
		Icon = "",
		Cooldown = 10,
		Tradable = true,
		AnimationId = "",
		ModuleName = "PhantomSlash",
		Effects = { "Unblockable", "Sweep" },
		Tags = { "Anti-block", "Wide" },
		Damage = 22,
		Range = 12,
		AllowDuplicate = false,
	},
	soul_harvest = {
		MoveId = "soul_harvest",
		Name = "Soul Harvest",
		Description = "Drain life from nearby enemies, healing yourself.",
		Rarity = "Epic",
		Icon = "",
		Cooldown = 14,
		Tradable = true,
		AnimationId = "",
		ModuleName = "SoulHarvest",
		Effects = { "Lifesteal", "AOE" },
		Tags = { "Sustain", "AOE", "Infernal" },
		Damage = 15,
		Range = 18,
		HealPercent = 0.5,
		AllowDuplicate = false,
	},
	void_rift = {
		MoveId = "void_rift",
		Name = "Void Rift",
		Description = "Tear open a rift that pulls enemies in and deals massive damage.",
		Rarity = "Legendary",
		Icon = "",
		Cooldown = 20,
		Tradable = true,
		AnimationId = "",
		ModuleName = "VoidRift",
		Effects = { "Pull", "AOE", "Damage" },
		Tags = { "Ultimate", "AOE", "Crowd-control", "Void" },
		Damage = 40,
		Range = 25,
		PullStrength = 50,
		AllowDuplicate = false,
	},
	abyssal_judgement = {
		MoveId = "abyssal_judgement",
		Name = "Abyssal Judgement",
		Description = "Summon the Abyss itself. Unavoidable devastation in a massive area.",
		Rarity = "Mythic",
		Icon = "",
		Cooldown = 30,
		Tradable = false,
		AnimationId = "",
		ModuleName = "AbyssalJudgement",
		Effects = { "Unavoidable", "Massive-AOE", "Damage" },
		Tags = { "Ultimate", "Mythic", "Devastation" },
		Damage = 60,
		Range = 35,
		AllowDuplicate = false,
	},
}

function MoveDatabase.GetMove(moveId)
	return MoveDatabase.Moves[moveId]
end

function MoveDatabase.GetMovesByRarity(rarity)
	local result = {}
	for id, move in pairs(MoveDatabase.Moves) do
		if move.Rarity == rarity then
			result[id] = move
		end
	end
	return result
end

return MoveDatabase
