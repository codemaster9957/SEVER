local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local AirJumpRequest = ReplicatedStorage:WaitForChild("AirJumpRequest")
local PlayPrivateSound = ReplicatedStorage:WaitForChild("PlayPrivateSound")
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))

AirJumpRequest.OnServerEvent:Connect(function(player)
	local opponent = MatchManager.GetOpponent(player)
	if opponent then
		PlayPrivateSound:FireClient(opponent, "AirJump")
	end
end)
