local Lifecycle = require(script.Parent:WaitForChild("TrainingDummyBattleLifecycle"))

local function assertEqual(actual, expected, message)
	assert(actual == expected, string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

local battle = Lifecycle.NewBattleState()
assertEqual(battle.fighting, false, "training battle must begin outside Fighting")
assertEqual(Lifecycle.ShouldRunAI(battle), false, "AI must stay off during intro")

Lifecycle.EnterFighting(battle)
assertEqual(battle.fighting, true, "EnterFighting must mark the battle live")
assertEqual(Lifecycle.ShouldRunAI(battle), true, "AI may run only after Fighting")

battle.finished = true
assertEqual(Lifecycle.ShouldRunAI(battle), false, "finished battles must never keep AI alive")

return true
