local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local ItemDatabase = require(ScytheSystems:WaitForChild("ItemDatabase"))
local ItemUtility = require(ScytheSystems:WaitForChild("ItemUtility"))
local DataService = require(ServerScriptService:WaitForChild("DataService"))

local remotes = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Collection")
local getProgressRemote = remotes:WaitForChild("GetProgress")

local REQUEST_COOLDOWN = 1
local lastProgressRequest = {}

local inventoryService = ServerScriptService:FindFirstChild("InventoryService")
if not inventoryService then
	inventoryService = ServerScriptService:WaitForChild("InventoryService", 5)
end
if not inventoryService then
	warn("[CollectionTracker] InventoryService is missing; using persisted OwnedItems fallback for collection rewards")
end

local function getCollectionProgress(player)
	local profile = DataService.GetProfile(player)
	if not profile then return {} end
	profile.CollectionProgress = profile.CollectionProgress or {}
	return profile.CollectionProgress
end

local function giveCollectionReward(player, rewardId)
	if not ItemUtility.ItemExists(rewardId) then return false end

	if _G.InventoryService and type(_G.InventoryService.GiveItem) == "function" then
		local ok, result = pcall(_G.InventoryService.GiveItem, player, rewardId, 1)
		if ok and result ~= false then return true end
		warn("[CollectionTracker] InventoryService.GiveItem failed for reward " .. tostring(rewardId))
	end

	-- Fallback keeps the reward persistent even if the legacy inventory service is
	-- absent or initializes after this script.
	local profile = DataService.GetProfile(player)
	if not profile then return false end
	profile.OwnedItems = profile.OwnedItems or {}
	profile.OwnedItems[rewardId] = math.max(0, tonumber(profile.OwnedItems[rewardId]) or 0) + 1
	return true
end

local checkCollectionCompletion

local function markDiscovered(player, itemId)
	if not ItemUtility.ItemExists(itemId) then return end
	local progress = getCollectionProgress(player)
	if progress[itemId] then return end

	progress[itemId] = true
	print("[CollectionTracker] " .. player.Name .. " discovered: " .. ItemUtility.FormatItemName(itemId))
	checkCollectionCompletion(player, itemId)
end

checkCollectionCompletion = function(player, newItemId)
	local item = ItemUtility.GetItemById(newItemId)
	if not item or not item.Collection then return end

	local collection = ItemDatabase.Collections[item.Collection]
	if not collection then return end

	local profile = DataService.GetProfile(player)
	if not profile then return end
	profile.CollectionProgress = profile.CollectionProgress or {}

	for _, requiredId in ipairs(collection.Items) do
		if not profile.CollectionProgress[requiredId] then return end
	end

	local rewardId = collection.Reward
	if rewardId and not profile.CollectionProgress[rewardId] then
		print("[CollectionTracker] " .. player.Name .. " completed collection: " .. item.Collection)
		if giveCollectionReward(player, rewardId) then
			-- Mark the reward itself so completing the same collection cannot grant it
			-- repeatedly if another discovery event is received later.
			profile.CollectionProgress[rewardId] = true
		end
	end
end

local function buildProgressData(player)
	local profile = DataService.GetProfile(player)
	if not profile then return {} end

	local discovered = profile.CollectionProgress or {}
	local totalItems = 0
	local totalDiscovered = 0
	local categoryProgress = {}

	for _, category in ipairs(ItemDatabase.Categories) do
		categoryProgress[category] = {Total = 0, Discovered = 0}
	end

	for itemId in pairs(ItemDatabase.Items) do
		totalItems += 1
		local item = ItemUtility.GetItemById(itemId)
		if item then
			local category = categoryProgress[item.Category]
			if category then category.Total += 1 end
			if discovered[itemId] then
				totalDiscovered += 1
				if category then category.Discovered += 1 end
			end
		end
	end

	local collectionStatus = {}
	for name, collection in pairs(ItemDatabase.Collections) do
		local completed = 0
		local total = #collection.Items
		for _, itemId in ipairs(collection.Items) do
			if discovered[itemId] then completed += 1 end
		end
		collectionStatus[name] = {
			Completed = completed,
			Total = total,
			IsComplete = completed >= total,
			Reward = collection.Reward,
			Description = collection.Description,
		}
	end

	return {
		Discovered = discovered,
		TotalItems = totalItems,
		TotalDiscovered = totalDiscovered,
		CategoryProgress = categoryProgress,
		Collections = collectionStatus,
	}
end

local function sendProgress(player)
	if player and player.Parent == Players then
		getProgressRemote:FireClient(player, buildProgressData(player))
	end
end

local function onItemGranted(player, itemId)
	if not player or player.Parent ~= Players then return end
	markDiscovered(player, itemId)
	sendProgress(player)
end

if inventoryService then
	task.defer(function()
		local itemGranted = inventoryService:FindFirstChild("ItemGranted") or inventoryService:WaitForChild("ItemGranted", 10)
		if itemGranted and itemGranted:IsA("BindableEvent") then
			itemGranted.Event:Connect(onItemGranted)
			print("[CollectionTracker] Connected to InventoryService.ItemGranted")
		else
			warn("[CollectionTracker] Could not find InventoryService.ItemGranted BindableEvent")
		end
	end)
end

getProgressRemote.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastProgressRequest[player] or -math.huge) < REQUEST_COOLDOWN then return end
	lastProgressRequest[player] = now
	sendProgress(player)
end)

Players.PlayerAdded:Connect(function(player)
	task.delay(2, function()
		if player.Parent == Players then sendProgress(player) end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastProgressRequest[player] = nil
end)

print("[CollectionTracker] Initialized")
