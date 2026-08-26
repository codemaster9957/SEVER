-- ReplicatedStorage/MatchStateController
local MatchStateController = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate")

local States = {
	Lobby = "Lobby",
	MatchFound = "MatchFound",
	LoadingArena = "LoadingArena",
	BattleIntro = "BattleIntro",
	Countdown = "Countdown",
	Fighting = "Fighting",
	OvertimeTransition = "OvertimeTransition",
	Overtime = "Overtime",
	FinalHit = "FinalHit",
	VictorySequence = "VictorySequence",
	Rewards = "Rewards",
	ReturningToLobby = "ReturningToLobby"
}

MatchStateController.States = States
MatchStateController.CurrentState = States.Lobby

local signal = Instance.new("BindableEvent")
MatchStateController.StateChanged = signal.Event

function MatchStateController:SetState(newState, data)
	if not States[newState] then
		warn("[MatchStateController] Invalid state: " .. tostring(newState))
		return
	end
	
	if self.CurrentState == newState then return end
	
	print("[MatchStateController] State changed: " .. self.CurrentState .. " -> " .. newState)
	self.CurrentState = newState
	signal:Fire(newState, data)
end

-- Server side listener (if required) would be in a separate script
-- but we expose this to client scripts to sync UI/Audio/Camera

return MatchStateController
