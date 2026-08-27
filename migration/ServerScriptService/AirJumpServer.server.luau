local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AirJumpRequest = ReplicatedStorage:WaitForChild("AirJumpRequest")
local PlayPrivateSound = ReplicatedStorage:WaitForChild("PlayPrivateSound")
local MatchManager = require(ServerScriptService:WaitForChild("MatchManager"))

local MIN_REQUEST_INTERVAL = 0.2
local lastRequestAt = {}

AirJumpRequest.OnServerEvent:Connect(function(player)
	if player.Parent ~= Players then return end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then return end
	if character:GetAttribute("InMatch") ~= true then return end
	if character:GetAttribute("Stunned") == true then return end

	local now = os.clock()
	if now - (lastRequestAt[player] or -math.huge) < MIN_REQUEST_INTERVAL then return end
	lastRequestAt[player] = now

	local opponent = MatchManager.GetOpponent(player)
	if opponent and opponent.Parent == Players then
		PlayPrivateSound:FireClient(opponent, "AirJump")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
end)
