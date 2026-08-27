local Lifecycle = {}

function Lifecycle.NewBattleState()
	return {
		fighting = false,
		finished = false,
	}
end

function Lifecycle.EnterFighting(battle)
	if type(battle) ~= "table" or battle.finished then
		return false
	end
	battle.fighting = true
	return true
end

function Lifecycle.ShouldRunAI(battle)
	return type(battle) == "table"
		and battle.fighting == true
		and battle.finished ~= true
end

return Lifecycle
