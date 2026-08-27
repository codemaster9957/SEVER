local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DATA_STORE_NAME = "ScythePlayerData_v1"
local AUTO_SAVE_INTERVAL = 120
local MAX_RETRIES = 3

local dataStore = DataStoreService:GetDataStore(DATA_STORE_NAME)

local DataService = {}

local profiles = {}
local profileLoaded = {}
local profileLoadFailed = {}
local profileSaveBlocked = {}
local saving = {}

local DEFAULT_PROFILE = {
	OwnedItems = {},
	OwnedEmotes = {},
	Gold = 500,
	ClawTokens = 0,
	EquippedSkin = nil,
	EquippedMove1 = nil,
	EquippedMove2 = nil,
	EquippedCosmetics = {},
	EquippedTrails = {},
	CollectionProgress = {},
	RankedTrophies = 0,
	RankedWins = 0,
	RankedLosses = 0,
	TotalClawPlays = 0,
}

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, child in pairs(value) do
		copy[key] = deepCopy(child)
	end
	return copy
end

local function reconcile(data, template)
	local result = deepCopy(data)
	for key, default in pairs(template) do
		if result[key] == nil then
			result[key] = deepCopy(default)
		elseif type(default) == "table" and type(result[key]) == "table" then
			for subKey, subDefault in pairs(default) do
				if result[key][subKey] == nil then
					result[key][subKey] = deepCopy(subDefault)
				end
			end
		end
	end
	return result
end

local function getKey(player)
	return "Player_" .. player.UserId
end

local function normalizeGold(amount)
	amount = tonumber(amount) or 0
	if amount ~= amount or amount == math.huge or amount == -math.huge then
		amount = 0
	end
	return math.max(0, math.floor(amount))
end

local function syncGoldDisplay(player, profile)
	if not player or player.Parent ~= Players or not profile then return end

	local goldAmount = normalizeGold(profile.Gold)
	profile.Gold = goldAmount
	player:SetAttribute("Gold", goldAmount)

	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	if gold and gold:IsA("IntValue") and gold.Value ~= goldAmount then
		gold.Value = goldAmount
	end
end

local function installTemporaryStudioProfile(player)
	local profile = deepCopy(DEFAULT_PROFILE)
	profile.Gold = normalizeGold(profile.Gold)
	profiles[player] = profile
	profileLoaded[player] = true
	profileLoadFailed[player] = nil
	profileSaveBlocked[player] = true
	syncGoldDisplay(player, profile)
	warn("[DataService] Using temporary NON-SAVING Studio data for " .. player.Name .. ". Enable Studio API Services to test persistence.")
	return profile
end

function DataService.LoadProfile(player)
	if profiles[player] then
		return profiles[player]
	end
	if profileLoadFailed[player] then
		return nil
	end

	local key = getKey(player)
	local data = nil
	local success = false

	for attempt = 1, MAX_RETRIES do
		if player.Parent ~= Players then return nil end

		local ok, result = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if ok then
			data = result
			success = true
			break
		end

		warn("[DataService] Load attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(result))
		if attempt < MAX_RETRIES then
			task.wait(2 ^ attempt)
		end
	end

	-- Never manufacture SAVEABLE default data after a failed read. In live servers
	-- this fails closed. In Studio we may still need to test gameplay with API
	-- access disabled, so use an explicitly non-saving temporary profile instead.
	if not success then
		if RunService:IsStudio() and player.Parent == Players then
			return installTemporaryStudioProfile(player)
		end

		profileLoadFailed[player] = true
		warn("[DataService] Refusing to create/save fallback data for " .. player.Name .. " because loading failed")
		if player.Parent == Players then
			player:Kick("Your data could not be loaded safely. Please rejoin in a moment.")
		end
		return nil
	end

	local profile
	if data ~= nil then
		profile = reconcile(data, DEFAULT_PROFILE)
		print("[DataService] Loaded profile for " .. player.Name)
	else
		profile = deepCopy(DEFAULT_PROFILE)
		print("[DataService] Created new profile for " .. player.Name)
	end

	profile.Gold = normalizeGold(profile.Gold)
	profiles[player] = profile
	profileLoaded[player] = true
	profileLoadFailed[player] = nil
	profileSaveBlocked[player] = nil
	syncGoldDisplay(player, profile)
	return profile
end

function DataService.SaveProfile(player)
	local profile = profiles[player]
	if not profile
		or profileLoaded[player] ~= true
		or profileLoadFailed[player]
		or profileSaveBlocked[player] then
		return false
	end
	if saving[player] then
		return false
	end

	saving[player] = true
	local key = getKey(player)
	local snapshot = deepCopy(profile)
	local saved = false

	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			dataStore:SetAsync(key, snapshot)
		end)
		if ok then
			saved = true
			break
		end

		warn("[DataService] Save attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(err))
		if attempt < MAX_RETRIES then
			task.wait(2 ^ attempt)
		end
	end

	saving[player] = nil
	if saved then
		print("[DataService] Saved profile for " .. player.Name)
		return true
	end

	warn("[DataService] All save attempts failed for " .. player.Name)
	return false
end

function DataService.GetProfile(player)
	if profileLoadFailed[player] then return nil end
	if not profiles[player] then
		return DataService.LoadProfile(player)
	end
	return profiles[player]
end

function DataService.UpdateProfile(player, callback)
	local profile = DataService.GetProfile(player)
	if not profile then return nil end
	callback(profile)
	syncGoldDisplay(player, profile)
	return profile
end

function DataService.IsLoaded(player)
	return profileLoaded[player] == true and profileLoadFailed[player] ~= true
end

function DataService.IsPersistent(player)
	return DataService.IsLoaded(player) and profileSaveBlocked[player] ~= true
end

function DataService.GetGold(player)
	local profile = DataService.GetProfile(player)
	return profile and normalizeGold(profile.Gold) or 0
end

function DataService.SetGold(player, amount)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.Gold = normalizeGold(amount)
		syncGoldDisplay(player, profile)
	end
end

function DataService.AddGold(player, amount)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.Gold = normalizeGold((profile.Gold or 0) + (tonumber(amount) or 0))
		syncGoldDisplay(player, profile)
	end
end

function DataService.GetClawTokens(player)
	local profile = DataService.GetProfile(player)
	return profile and profile.ClawTokens or 0
end

function DataService.AddClawTokens(player, amount)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.ClawTokens = math.max(0, (tonumber(profile.ClawTokens) or 0) + (tonumber(amount) or 0))
	end
end

function DataService.UnloadProfile(player)
	if profiles[player]
		and profileLoaded[player]
		and not profileLoadFailed[player]
		and not profileSaveBlocked[player] then
		DataService.SaveProfile(player)
	end
	profiles[player] = nil
	profileLoaded[player] = nil
	profileLoadFailed[player] = nil
	profileSaveBlocked[player] = nil
	saving[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(DataService.LoadProfile, player)
end)

Players.PlayerRemoving:Connect(function(player)
	DataService.UnloadProfile(player)
end)

task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if profiles[player]
				and profileLoaded[player]
				and not profileLoadFailed[player]
				and not profileSaveBlocked[player] then
				task.spawn(DataService.SaveProfile, player)
			end
		end
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if profiles[player]
			and profileLoaded[player]
			and not profileLoadFailed[player]
			and not profileSaveBlocked[player] then
			DataService.SaveProfile(player)
		end
	end
end)

return DataService
