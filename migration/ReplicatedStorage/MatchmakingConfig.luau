--!strict
-- Shared matchmaking configuration used by both server and client
local MatchmakingConfig = {}

MatchmakingConfig.BASE_MMR = 1000
MatchmakingConfig.MMR_K_FACTOR = 32

-- Initial MMR search range (±)
MatchmakingConfig.INITIAL_MMR_RANGE = 100

-- How much the range expands per second of waiting
MatchmakingConfig.MMR_EXPANSION_RATE = 15

-- Maximum MMR range after expansion
MatchmakingConfig.MAX_MMR_RANGE = 800

-- Time before a queued player gets a bot fallback (seconds)
MatchmakingConfig.BOT_FALLBACK_TIME = 30

-- Time players have to accept a found match (seconds)
MatchmakingConfig.MATCH_ACCEPT_TIMEOUT = 15

-- Queue tick interval (seconds)
MatchmakingConfig.QUEUE_TICK_INTERVAL = 0.5

-- MMR gain/loss on ranked match result
MatchmakingConfig.RankedWinMMR = 25
MatchmakingConfig.RankedLossMMR = 20

-- Casual MMR adjustment (smaller)
MatchmakingConfig.CasualWinMMR = 10
MatchmakingConfig.CasualLossMMR = 8

-- Party size limits
MatchmakingConfig.MAX_PARTY_SIZE = 4

-- Spectating
MatchmakingConfig.MAX_SPECTATORS = 10

-- Bot difficulty levels
MatchmakingConfig.BotDifficulties = {
	Easy = { WalkSpeed = 12, ParryChance = 0.15, BlockChance = 0.10, DamageMult = 0.7 },
	Medium = { WalkSpeed = 16, ParryChance = 0.30, BlockChance = 0.20, DamageMult = 0.85 },
	Hard = { WalkSpeed = 18, ParryChance = 0.48, BlockChance = 0.34, DamageMult = 1.0 },
}

return MatchmakingConfig