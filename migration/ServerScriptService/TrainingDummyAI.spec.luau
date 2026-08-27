local TrainingDummyAI = require(script.Parent:WaitForChild("TrainingDummyAI"))

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. string.format(" (expected %s, got %s)", tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value, message)
	if value ~= true then
		error(message or "expected true")
	end
end

return function()
	assertEqual(TrainingDummyAI.ClampLevel(-4), 0, "difficulty clamps low")
	assertEqual(TrainingDummyAI.ClampLevel(99), 10, "difficulty clamps high")
	assertEqual(TrainingDummyAI.ClampLevel(4.8), 4, "difficulty is integral")

	local level0 = TrainingDummyAI.GetCapabilities(0)
	assertEqual(level0.Slash, false, "level 0 is passive")
	assertEqual(level0.Move, false, "level 0 does not move")

	local level1 = TrainingDummyAI.GetCapabilities(1)
	assertTrue(level1.Slash, "level 1 slashes")
	assertEqual(level1.Move, false, "level 1 stays stationary")

	local level2 = TrainingDummyAI.GetCapabilities(2)
	assertTrue(level2.Move, "level 2 moves")
	assertTrue(level2.Dash, "level 2 dashes")

	local level3 = TrainingDummyAI.GetCapabilities(3)
	assertTrue(level3.Grapple, "level 3 grapples")

	local level4 = TrainingDummyAI.GetCapabilities(4)
	assertTrue(level4.Block, "level 4 blocks")

	local level5 = TrainingDummyAI.GetCapabilities(5)
	assertTrue(level5.Advanced, "level 5 uses advanced fundamentals")

	local level6 = TrainingDummyAI.GetCapabilities(6)
	assertTrue(level6.Throw, "level 6 throws")

	local level7 = TrainingDummyAI.GetCapabilities(7)
	assertTrue(level7.Spin, "level 7 spins")

	local level8 = TrainingDummyAI.GetCapabilities(8)
	assertTrue(level8.SoulReap, "level 8 uses Soul Reap")

	local level9 = TrainingDummyAI.GetCapabilities(9)
	assertTrue(level9.Advanced, "level 9 is advanced")
	assertTrue(level9.Throw and level9.Spin and level9.SoulReap, "level 9 has the full kit")

	local level10 = TrainingDummyAI.GetCapabilities(10)
	assertTrue(level10.Adaptive, "level 10 is adaptive")
	assertTrue(level10.Advanced, "level 10 retains advanced full-kit play")

	local memory = TrainingDummyAI.ReconcileMemory(nil)
	assertEqual(memory.Version, 1, "adaptive memory has a version")
	assertEqual(memory.PlayerWins, 0, "new memory starts without player wins")

	TrainingDummyAI.RecordObservation(memory, "BlockedDummyAttack")
	TrainingDummyAI.RecordObservation(memory, "BlockedDummyAttack")
	TrainingDummyAI.RecordObservation(memory, "DummyAttackAttempt")
	TrainingDummyAI.RecordObservation(memory, "DummyAttackAttempt")
	TrainingDummyAI.RecordObservation(memory, "DummyAttackAttempt")
	TrainingDummyAI.RecordObservation(memory, "DummyAttackAttempt")

	local profile = TrainingDummyAI.GetAdaptiveProfile(memory)
	assertEqual(profile.BlockRate, 0.5, "block rate is learned from attempts")

	TrainingDummyAI.RecordRoundResult(memory, true)
	assertEqual(memory.PlayerWins, 1, "beating level 10 is remembered")
	assertTrue(TrainingDummyAI.GetAdaptiveProfile(memory).AdaptationStrength > profile.AdaptationStrength,
		"a player win silently strengthens future adaptation")
end
