local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataService = require(ServerScriptService:WaitForChild("DataService"))
local WIN_REWARD = 3

local syncing = {}

local function getGoldValue(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Gold")
end

local function setupPlayer(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local gold = leaderstats:FindFirstChild("Gold")
	if not gold then
		gold = Instance.new("IntValue")
		gold.Name = "Gold"
		gold.Parent = leaderstats
	end

	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end

	syncing[player] = true
	gold.Value = DataService.GetGold(player)
	player:SetAttribute("Gold", gold.Value)
	syncing[player] = nil

	gold.Changed:Connect(function(newValue)
		if syncing[player] or player.Parent ~= Players then return end
		-- Legacy scripts that still award through leaderstats are redirected into
		-- the one persisted DataService balance.
		DataService.SetGold(player, newValue)
	end)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(setupPlayer, player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	syncing[player] = nil
end)

function _G.GiveWinReward(player)
	if player and player.Parent == Players then
		DataService.AddGold(player, WIN_REWARD)
	end
end
