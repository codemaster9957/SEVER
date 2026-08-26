local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local ItemDatabase = require(ScytheSystems:WaitForChild("ItemDatabase"))
local RarityConfig = require(ScytheSystems:WaitForChild("RarityConfig"))
local MoveDatabase = require(ScytheSystems:WaitForChild("MoveDatabase"))

local ItemUtility = {}

function ItemUtility.GetItemById(itemId)
	return ItemDatabase.Items[itemId]
end

function ItemUtility.GetItemsByCategory(category)
	local result = {}
	for id, item in pairs(ItemDatabase.Items) do
		if item.Category == category then
			result[id] = item
		end
	end
	return result
end

function ItemUtility.GetItemsByRarity(rarity)
	local result = {}
	for id, item in pairs(ItemDatabase.Items) do
		if item.Rarity == rarity then
			result[id] = item
		end
	end
	return result
end

function ItemUtility.GetItemsByCategoryAndRarity(category, rarity)
	local result = {}
	for id, item in pairs(ItemDatabase.Items) do
		if item.Category == category and item.Rarity == rarity then
			result[id] = item
		end
	end
	return result
end

function ItemUtility.GetRarityColor(rarity)
	return RarityConfig.GetColor(rarity)
end

function ItemUtility.FormatItemName(itemId)
	local item = ItemDatabase.Items[itemId]
	return item and item.Name or "Unknown"
end

function ItemUtility.IsItemTradable(itemId)
	local item = ItemDatabase.Items[itemId]
	return item and item.Tradable or false
end

function ItemUtility.IsItemLimited(itemId)
	local item = ItemDatabase.Items[itemId]
	return item and item.Limited or false
end

function ItemUtility.IsItemStackable(itemId)
	local item = ItemDatabase.Items[itemId]
	return item and item.Stackable or false
end

function ItemUtility.GetMaxStack(itemId)
	local item = ItemDatabase.Items[itemId]
	if item and item.Stackable then
		return item.MaxStack or 99
	end
	return 1
end

function ItemUtility.GetMoveData(itemId)
	return MoveDatabase.GetMove(itemId)
end

function ItemUtility.GetCollection(collectionName)
	return ItemDatabase.Collections[collectionName]
end

function ItemUtility.GetItemCollection(itemId)
	local item = ItemDatabase.Items[itemId]
	if item and item.Collection then
		return ItemDatabase.Collections[item.Collection]
	end
	return nil
end

function ItemUtility.GetAllItemIds()
	local ids = {}
	for id in pairs(ItemDatabase.Items) do
		table.insert(ids, id)
	end
	return ids
end

function ItemUtility.GetAllItemIdsInCategory(category)
	local ids = {}
	for id, item in pairs(ItemDatabase.Items) do
		if item.Category == category then
			table.insert(ids, id)
		end
	end
	return ids
end

function ItemUtility.GetCategoryLabel(category)
	return ItemDatabase.CategoryLabels[category] or category
end

function ItemUtility.GetTokenValue(itemId)
	local item = ItemDatabase.Items[itemId]
	if not item then return 0 end
	return RarityConfig.GetTokenValue(item.Rarity)
end

function ItemUtility.ItemExists(itemId)
	return ItemDatabase.Items[itemId] ~= nil
end

return ItemUtility
