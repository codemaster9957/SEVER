local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

assert(Policy.IsBattleState("BattleIntro") == true, "BattleIntro must be treated as a battle state")
assert(Policy.IsBattleState("Fighting") == true, "Fighting must be treated as a battle state")
assert(Policy.IsBattleState("Lobby") == false, "Lobby must not be treated as battle")
assert(Policy.IsMatchmakingControl("RankedButton", "RANKED") == true, "ranked button should be themed/hidden during battle")
assert(Policy.IsMatchmakingControl("LeaderboardButton", "Ranked Leaderboard") == false, "leaderboards must not be hidden as matchmaking")
assert(Policy.LooksLikeBattleIntro("BattleIntroFrame", "") == true, "legacy battle intro frame should be detectable")
assert(Policy.LooksLikeBattleIntro("AbilityCooldown", "0:05") == false, "ability UI must not be mistaken for intro")

return true
