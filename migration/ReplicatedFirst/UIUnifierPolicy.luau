local Policy = {}

local BATTLE_STATES = {
	LoadingArena = true,
	BattleIntro = true,
	Countdown = true,
	Fighting = true,
	InMatch = true,
	MatchEnded = true,
	ReturningToLobby = true,
}

local function lower(value)
	return string.lower(tostring(value or ""))
end

function Policy.IsBattleState(state)
	return BATTLE_STATES[state] == true
end

function Policy.IsMatchmakingControl(name, text)
	local combined = lower(name .. " " .. text)

	if string.find(combined, "training", 1, true)
		or string.find(combined, "dummy", 1, true)
		or string.find(combined, "leaderboard", 1, true)
		or string.find(combined, "spectat", 1, true) then
		return false
	end

	if string.find(combined, "matchmaking", 1, true)
		or string.find(combined, "find match", 1, true)
		or string.find(combined, "findmatch", 1, true)
		or string.find(combined, "casual", 1, true)
		or string.find(combined, "ranked", 1, true)
		or string.find(combined, "queue", 1, true) then
		return true
	end

	return false
end

function Policy.ClassifyHealthPanel(name, text)
	local combined = lower(name .. " " .. text)

	if string.find(combined, "opponentdisplay", 1, true)
		or string.find(combined, "opponent display", 1, true)
		or string.find(combined, "enemyhealth", 1, true)
		or string.find(combined, "enemy health", 1, true)
		or string.find(combined, "opponenthealth", 1, true)
		or string.find(combined, "opponent health", 1, true)
		or string.find(combined, "opponent", 1, true)
		or string.find(combined, "enemy", 1, true) then
		return "opponent"
	end

	if string.find(combined, "playerdisplay", 1, true)
		or string.find(combined, "player display", 1, true)
		or string.find(combined, "playerhealth", 1, true)
		or string.find(combined, "player health", 1, true)
		or string.find(combined, "yourhealth", 1, true)
		or string.find(combined, "your health", 1, true)
		or combined == "you" then
		return "player"
	end

	return nil
end

function Policy.LooksLikeBattleIntro(name, text)
	local combined = lower(name .. " " .. text)
	return string.find(combined, "battleintro", 1, true) ~= nil
		or string.find(combined, "battle intro", 1, true) ~= nil
		or string.find(combined, "versus", 1, true) ~= nil
		or combined == "vs"
		or string.find(combined, " vs ", 1, true) ~= nil
end

return Policy
