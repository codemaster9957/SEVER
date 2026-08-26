local OvertimeManager = {}

local ServerScriptService = game:GetService("ServerScriptService")

-- Called by MatchManager when a timed match ends in a draw.
-- Restarts the match in overtime (timer already at 0).
function OvertimeManager.StartOvertime(p1, p2, arena)
	if not p1 or not p2 or not arena then
		return
	end

	local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))
	MatchManager.StartMatch(p1, p2, arena.Name, true)
end

return OvertimeManager
