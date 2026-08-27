local TrainingDummyAI = {}

local CAPABILITIES = {
	[0] = {},
	[1] = {Slash = true},
	[2] = {Slash = true, Move = true, Dash = true},
	[3] = {Slash = true, Move = true, Dash = true, Grapple = true},
	[4] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true},
	[5] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true, Advanced = true},
	[6] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true, Advanced = true, Throw = true},
	[7] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true, Advanced = true, Throw = true, Spin = true},
	[8] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true, Advanced = true, Throw = true, Spin = true, SoulReap = true},
	[9] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true, Advanced = true, Throw = true, Spin = true, SoulReap = true},
	[10] = {Slash = true, Move = true, Dash = true, Grapple = true, Block = true, Advanced = true, Throw = true, Spin = true, SoulReap = true, Adaptive = true},
}

local DEFAULT_MEMORY = {
	Version = 1,
	Samples = 0,
	DummyAttackAttempts = 0,
	BlockedDummyAttacks = 0,
	DodgedDummyAttacks = 0,
	CloseHits = 0,
	RangedHits = 0,
	DistanceSamples = 0,
	DistanceTotal = 0,
	AggressiveSamples = 0,
	DashBursts = 0,
	PlayerWins = 0,
	DummyWins = 0,
}

local function copyTable(source)
	local result = {}
	for key, value in pairs(source) do
		result[key] = value
	end
	return result
end

local function finiteNumber(value, fallback)
	value = tonumber(value)
	if value == nil or value ~= value or value == math.huge or value == -math.huge then
		return fallback or 0
	end
	return value
end

function TrainingDummyAI.ClampLevel(level)
	level = math.floor(finiteNumber(level, 1))
	return math.clamp(level, 0, 10)
end

function TrainingDummyAI.GetCapabilities(level)
	level = TrainingDummyAI.ClampLevel(level)
	local result = {
		Slash = false,
		Move = false,
		Dash = false,
		Grapple = false,
		Block = false,
		Advanced = false,
		Throw = false,
		Spin = false,
		SoulReap = false,
		Adaptive = false,
	}

	for key, value in pairs(CAPABILITIES[level]) do
		result[key] = value
	end

	return result
end

function TrainingDummyAI.ReconcileMemory(memory)
	local result = copyTable(DEFAULT_MEMORY)
	if type(memory) == "table" then
		for key, defaultValue in pairs(DEFAULT_MEMORY) do
			local existing = memory[key]
			if type(defaultValue) == "number" then
				result[key] = math.max(0, finiteNumber(existing, defaultValue))
			end
		end
	end
	result.Version = 1
	return result
end

function TrainingDummyAI.RecordObservation(memory, eventName, value)
	if type(memory) ~= "table" then
		return
	end

	if eventName == "DummyAttackAttempt" then
		memory.DummyAttackAttempts = (memory.DummyAttackAttempts or 0) + 1
	elseif eventName == "BlockedDummyAttack" then
		memory.BlockedDummyAttacks = (memory.BlockedDummyAttacks or 0) + 1
	elseif eventName == "DodgedDummyAttack" then
		memory.DodgedDummyAttacks = (memory.DodgedDummyAttacks or 0) + 1
	elseif eventName == "CloseHit" then
		memory.CloseHits = (memory.CloseHits or 0) + 1
	elseif eventName == "RangedHit" then
		memory.RangedHits = (memory.RangedHits or 0) + 1
	elseif eventName == "DistanceSample" then
		memory.DistanceSamples = (memory.DistanceSamples or 0) + 1
		memory.DistanceTotal = (memory.DistanceTotal or 0) + math.max(0, finiteNumber(value, 0))
	elseif eventName == "AggressiveSample" then
		memory.AggressiveSamples = (memory.AggressiveSamples or 0) + 1
	elseif eventName == "DashBurst" then
		memory.DashBursts = (memory.DashBursts or 0) + 1
	end

	memory.Samples = (memory.Samples or 0) + 1
end

function TrainingDummyAI.RecordRoundResult(memory, playerWon)
	if type(memory) ~= "table" then
		return
	end

	if playerWon == true then
		memory.PlayerWins = (memory.PlayerWins or 0) + 1
	elseif playerWon == false then
		memory.DummyWins = (memory.DummyWins or 0) + 1
	end
end

function TrainingDummyAI.GetAdaptiveProfile(memory)
	memory = TrainingDummyAI.ReconcileMemory(memory)

	local attempts = math.max(1, memory.DummyAttackAttempts)
	local distanceSamples = math.max(1, memory.DistanceSamples)
	local samples = math.max(0, memory.Samples)
	local totalHits = math.max(1, memory.CloseHits + memory.RangedHits)

	local blockRate = math.clamp(memory.BlockedDummyAttacks / attempts, 0, 1)
	local dodgeRate = math.clamp(memory.DodgedDummyAttacks / attempts, 0, 1)
	local closeHitRate = math.clamp(memory.CloseHits / totalHits, 0, 1)
	local averageDistance = math.clamp(memory.DistanceTotal / distanceSamples, 0, 100)
	local aggressionRate = math.clamp(memory.AggressiveSamples / distanceSamples, 0, 1)

	-- Level 10 starts extremely strong. Repeated player wins and accumulated
	-- observations sharpen its counter-selection without ever changing the UI.
	local adaptationStrength = math.clamp(
		0.62 + memory.PlayerWins * 0.045 + math.min(samples, 500) * 0.00035,
		0.62,
		0.96
	)

	return {
		BlockRate = blockRate,
		DodgeRate = dodgeRate,
		CloseHitRate = closeHitRate,
		AverageDistance = averageDistance,
		AggressionRate = aggressionRate,
		DashBursts = memory.DashBursts,
		PlayerWins = memory.PlayerWins,
		DummyWins = memory.DummyWins,
		AdaptationStrength = adaptationStrength,
	}
end

return TrainingDummyAI
