local Players = game:GetService("Players")

local WIN_REWARD = 3
local STARTING_GOLD = 50

local function getGold(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	return leaderstats and leaderstats:FindFirstChild("Gold")
end

local function updateCurrency(player)
	local gold = getGold(player)
	if gold then
		player:SetAttribute("Gold", gold.Value)
	end
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
		gold.Value = STARTING_GOLD
		gold.Parent = leaderstats
	end
	gold.Changed:Connect(function()
		updateCurrency(player)
	end)
	updateCurrency(player)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.defer(setupPlayer, player)
end

function _G.GiveWinReward(player)
	local gold = getGold(player)
	if gold then
		gold.Value += WIN_REWARD
	end
end
