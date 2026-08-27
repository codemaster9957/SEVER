local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

assert(Policy.IsBattleState("LoadingArena") == true)
assert(Policy.IsBattleState("BattleIntro") == true)
assert(Policy.IsBattleState("Countdown") == true)
assert(Policy.IsBattleState("Fighting") == true)
assert(Policy.IsBattleState("InMatch") == true)
assert(Policy.IsBattleState("MatchEnded") == true)
assert(Policy.IsBattleState("ReturningToLobby") == true)
assert(Policy.IsBattleState("Lobby") == false)

assert(Policy.IsMatchmakingControl("RankedButton", "RANKED") == true)
assert(Policy.IsMatchmakingControl("CasualQueue", "CASUAL") == true)
assert(Policy.IsMatchmakingControl("FindMatch", "FIND MATCH") == true)
assert(Policy.IsMatchmakingControl("RankedLeaderboard", "GLOBAL RANKED LEADERBOARD") == false)
assert(Policy.IsMatchmakingControl("TrainingDummyLevelButton", "DUMMY LEVEL: 5") == false)
assert(Policy.IsMatchmakingControl("RespawnDummy", "RESPAWN DUMMY") == false)

assert(Policy.ClassifyHealthPanel("PlayerDisplay", "YOU") == "player")
assert(Policy.ClassifyHealthPanel("OpponentDisplay", "OPPONENT") == "opponent")
assert(Policy.ClassifyHealthPanel("EnemyHealthFrame", "ENEMY") == "opponent")
assert(Policy.ClassifyHealthPanel("HealthFrame", "") == nil)

print("UIUnifierPolicy.spec passed")
