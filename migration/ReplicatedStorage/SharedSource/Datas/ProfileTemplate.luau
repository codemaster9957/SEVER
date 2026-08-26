local ProfileTemplate = {
	Gold = 500,
	ClawTokens = 0,
	OwnedItems = {},
	EquippedSkin = nil,
	EquippedMove1 = nil,
	EquippedMove2 = nil,
	EquippedCosmetics = {},
	EquippedTrails = {},
	CollectionProgress = {},
	TotalClawPlays = 0,

	-- Tutorial / Onboarding
	TutorialCompleted = false,
	TutorialSkipped = false,
	TutorialStep = 0,

	-- Matchmaking / MMR
	MMR = 1000,
	Wins = 0,
	Losses = 0,
	CasualWins = 0,
	CasualLosses = 0,
	RankedWins = 0,
	RankedLosses = 0,
	BestWinStreak = 0,

	-- Social
	ClanId = nil,
	ClanRole = nil,
	FriendsList = {},
	PostMatchReactions = {},
}

return ProfileTemplate
