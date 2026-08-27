--!strict
-- DamageHandler still contains a legacy global matchOver latch. A KO in one arena
-- can therefore briefly stop ApplyDamage in unrelated arenas. Keep the combat
-- implementation untouched, but clear that legacy latch as soon as the finished
-- duel has been announced by MatchManager.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageHandler = require(ReplicatedStorage:WaitForChild("DamageHandler"))
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))

local function clearLatchWithSurvivor(player)
	if not player or not player.Parent then return false end
	local health = DamageHandler.GetPlayerHealth(player)
	if type(health) ~= "number" or health <= 0 then return false end

	-- SetPlayerHealth with a positive value clears DamageHandler's legacy
	-- matchOver flag without changing the survivor's actual match health.
	DamageHandler.SetPlayerHealth(player, health)
	return true
end

MatchManager.GetMatchEndedSignal():Connect(function(p1, p2, winner)
	if not DamageHandler.IsMatchOver() then return end

	if clearLatchWithSurvivor(winner) then return end
	if clearLatchWithSurvivor(p1) then return end
	clearLatchWithSurvivor(p2)
end)
