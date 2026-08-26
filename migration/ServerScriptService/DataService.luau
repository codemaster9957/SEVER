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

local DEFAULT_PROFILE = {
	OwnedItems = {},
	OwnedEmotes = {},
	Gold = 500,
	ClawTokens = 0,
	OwnedItems = {},
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

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deepCopy(v)
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

function DataService.LoadProfile(player)
	if profiles[player] then
		return profiles[player]
	end

	local key = getKey(player)
	local data = nil
	local success = false

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return dataStore:GetAsync(key)
		end)
		if ok then
			data = result
			success = true
			break
		else
			warn("[DataService] Load attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(result))
			if attempt < MAX_RETRIES then
				task.wait(2 ^ attempt)
			end
		end
	end

	if not success then
		warn("[DataService] All load attempts failed for " .. player.Name .. ", using defaults")
	end

	local profile
	if data then
		profile = reconcile(data, DEFAULT_PROFILE)
		print("[DataService] Loaded profile for " .. player.Name)
	else
		profile = deepCopy(DEFAULT_PROFILE)
		print("[DataService] Created new profile for " .. player.Name)
	end

	profiles[player] = profile
	profileLoaded[player] = true
	return profile
end

function DataService.SaveProfile(player)
	local profile = profiles[player]
	if not profile then
		return false
	end

	local key = getKey(player)
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			dataStore:SetAsync(key, profile)
		end)
		if ok then
			print("[DataService] Saved profile for " .. player.Name)
			return true
		else
			warn("[DataService] Save attempt " .. attempt .. " failed for " .. player.Name .. ": " .. tostring(err))
			if attempt < MAX_RETRIES then
				task.wait(2 ^ attempt)
			end
		end
	end

	warn("[DataService] All save attempts failed for " .. player.Name)
	return false
end

function DataService.GetProfile(player)
	if not profiles[player] then
		return DataService.LoadProfile(player)
	end
	return profiles[player]
end

function DataService.UpdateProfile(player, callback)
	local profile = DataService.GetProfile(player)
	if not profile then return nil end
	callback(profile)
	return profile
end

function DataService.IsLoaded(player)
	return profileLoaded[player] == true
end

function DataService.GetGold(player)
	local profile = DataService.GetProfile(player)
	return profile and profile.Gold or 0
end

function DataService.SetGold(player, amount)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.Gold = math.max(0, amount)
	end
end

function DataService.AddGold(player, amount)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.Gold = math.max(0, profile.Gold + amount)
	end
end

function DataService.GetClawTokens(player)
	local profile = DataService.GetProfile(player)
	return profile and profile.ClawTokens or 0
end

function DataService.AddClawTokens(player, amount)
	local profile = DataService.GetProfile(player)
	if profile then
		profile.ClawTokens = math.max(0, profile.ClawTokens + amount)
	end
end

function DataService.UnloadProfile(player)
	if profiles[player] then
		DataService.SaveProfile(player)
		profiles[player] = nil
		profileLoaded[player] = nil
	end
end

Players.PlayerAdded:Connect(function(player)
	DataService.LoadProfile(player)
end)

Players.PlayerRemoving:Connect(function(player)
	DataService.UnloadProfile(player)
end)

task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			if profiles[player] then
				task.spawn(DataService.SaveProfile, player)
			end
		end
		print("[DataService] Auto-save complete")
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		if profiles[player] then
			DataService.SaveProfile(player)
		end
	end
end)

return DataService
