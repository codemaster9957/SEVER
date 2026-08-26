local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local ItemDatabase = require(ScytheSystems:WaitForChild("ItemDatabase"))
local ItemUtility = require(ScytheSystems:WaitForChild("ItemUtility"))
local DataService = require(ServerScriptService:WaitForChild("DataService"))

local remotes = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Collection")
local getProgressRemote = remotes:WaitForChild("GetProgress")

local inventoryService = ServerScriptService:WaitForChild("InventoryService")

local function getCollectionProgress(player)
	local profile = DataService.GetProfile(player)
	if not profile then return {} end
	return profile.CollectionProgress or {}
end

local function markDiscovered(player, itemId)
	local profile = DataService.GetProfile(player)
	if not profile then return end

	if not profile.CollectionProgress then
		profile.CollectionProgress = {}
	end

	if profile.CollectionProgress[itemId] then return end
	profile.CollectionProgress[itemId] = true
	print("[CollectionTracker] " .. player.Name .. " discovered: " .. ItemUtility.FormatItemName(itemId))

	checkCollectionCompletion(player, itemId)
end

function checkCollectionCompletion(player, newItemId)
	local item = ItemUtility.GetItemById(newItemId)
	if not item or not item.Collection then return end

	local collection = ItemDatabase.Collections[item.Collection]
	if not collection then return end

	local profile = DataService.GetProfile(player)
	if not profile then return end

	for _, requiredId in ipairs(collection.Items) do
		if not profile.CollectionProgress[requiredId] then
			return
		end
	end

	if collection.Reward then
		if not profile.CollectionProgress[collection.Reward] then
			print("[CollectionTracker] " .. player.Name .. " completed collection: " .. item.Collection)
			if _G.InventoryService and ItemUtility.ItemExists(collection.Reward) then
				_G.InventoryService.GiveItem(player, collection.Reward, 1)
			end
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
		categoryProgress[category] = { Total = 0, Discovered = 0 }
	end

	for itemId, _ in pairs(ItemDatabase.Items) do
		totalItems += 1
		local item = ItemUtility.GetItemById(itemId)
		if item then
			local cat = categoryProgress[item.Category]
			if cat then
				cat.Total += 1
			end
			if discovered[itemId] then
				totalDiscovered += 1
				if cat then
					cat.Discovered += 1
				end
			end
		end
	end

	local collectionStatus = {}
	for name, collection in pairs(ItemDatabase.Collections) do
		local completed = 0
		local total = #collection.Items
		for _, itemId in ipairs(collection.Items) do
			if discovered[itemId] then
				completed += 1
			end
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
	local data = buildProgressData(player)
	getProgressRemote:FireClient(player, data)
end

local function onItemGranted(player, itemId, qty)
	markDiscovered(player, itemId)
	sendProgress(player)
end

task.defer(function()
	local itemGranted = inventoryService:WaitForChild("ItemGranted", 10)
	if itemGranted then
		itemGranted.Event:Connect(onItemGranted)
		print("[CollectionTracker] Connected to InventoryService.ItemGranted")
	else
		warn("[CollectionTracker] Could not find ItemGranted BindableEvent")
	end
end)

getProgressRemote.OnServerEvent:Connect(function(player)
	sendProgress(player)
end)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		task.wait(2)
		sendProgress(player)
	end)
end)

print("[CollectionTracker] Initialized")
