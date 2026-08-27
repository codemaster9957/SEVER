-- Adds the training dummy level setting without redesigning the existing UI.
-- It clones a live training settings button so all authored styling is inherited exactly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate")
local TrainingControls = MatchEvents:WaitForChild("TrainingDummyControls")
local SetDummyLevel = TrainingControls:WaitForChild("SetDummyLevel")

local inTraining = false
local currentLevel = 1
local levelButton = nil
local hiddenTimerState = {}

local function lower(value)
	return string.lower(tostring(value or ""))
end

local function visibleText(instance)
	if instance:IsA("TextButton") or instance:IsA("TextLabel") then
		return instance.Text
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if (descendant:IsA("TextButton") or descendant:IsA("TextLabel")) and descendant.Text ~= "" then
			return descendant.Text
		end
	end
	return ""
end

local function hasNamedAncestor(instance, keywords)
	local current = instance.Parent
	while current and current ~= playerGui do
		local name = lower(current.Name)
		for _, keyword in ipairs(keywords) do
			if string.find(name, keyword, 1, true) then
				return true
			end
		end
		current = current.Parent
	end
	return false
end

local function looksLikeTrainingControl(button)
	if button:GetAttribute("SEVERTrainingLevelControl") == true then
		return false
	end
	local combined = lower(button.Name .. " " .. visibleText(button))
	return string.find(combined, "respawn", 1, true) ~= nil
		or string.find(combined, "infinite", 1, true) ~= nil
		or string.find(combined, "return", 1, true) ~= nil
		or string.find(combined, "lobby", 1, true) ~= nil
end

local function findTemplateButton()
	local preferred = nil
	local fallback = nil
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and descendant.Visible then
			if looksLikeTrainingControl(descendant) then
				local text = lower(visibleText(descendant))
				if string.find(text, "respawn", 1, true) then
					return descendant
				end
				preferred = preferred or descendant
			elseif hasNamedAncestor(descendant, {"training", "dummy"}) then
				fallback = fallback or descendant
			end
		end
	end
	return preferred or fallback
end

local function setButtonLabel(button)
	local labelText = string.format("DUMMY LEVEL: %d", currentLevel)
	if button:IsA("TextButton") and button.Text ~= "" then
		button.Text = labelText
		return
	end

	local firstTextLabel = nil
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") and descendant.Text ~= "" then
			firstTextLabel = firstTextLabel or descendant
			local text = lower(descendant.Text)
			if string.find(text, "respawn", 1, true)
				or string.find(text, "infinite", 1, true)
				or string.find(text, "return", 1, true)
				or string.find(text, "lobby", 1, true) then
				descendant.Text = labelText
				return
			end
		end
	end
	if firstTextLabel then
		firstTextLabel.Text = labelText
	end
end

local function placeCloneAfterTemplate(clone, template)
	clone.LayoutOrder = template.LayoutOrder + 1
	local parent = template.Parent
	if not parent then return end
	local usesLayout = parent:FindFirstChildOfClass("UIListLayout") ~= nil
		or parent:FindFirstChildOfClass("UIGridLayout") ~= nil
		or parent:FindFirstChildOfClass("UITableLayout") ~= nil
	if not usesLayout then
		clone.Position = template.Position + UDim2.fromOffset(0, template.AbsoluteSize.Y + 8)
	end
end

local function ensureLevelButton()
	if not inTraining then return end
	if levelButton and levelButton.Parent then
		setButtonLabel(levelButton)
		return
	end

	local template = findTemplateButton()
	if not template or not template.Parent then return end

	local clone = template:Clone()
	clone.Name = "TrainingDummyLevelButton"
	clone:SetAttribute("SEVERTrainingLevelControl", true)

	-- Never inherit button-specific LocalScripts from Respawn/Return controls.
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("LocalScript") or descendant:IsA("Script") then
			descendant:Destroy()
		end
	end

	placeCloneAfterTemplate(clone, template)
	clone.Parent = template.Parent
	levelButton = clone
	setButtonLabel(clone)

	clone.Activated:Connect(function()
		if not inTraining then return end
		currentLevel = (currentLevel + 1) % 11
		setButtonLabel(clone)
		SetDummyLevel:FireServer(currentLevel)
	end)
end

local function isBattleTimerObject(gui)
	local isNamedTimer = string.find(lower(gui.Name), "timer", 1, true) ~= nil
	local isClockText = false
	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		isClockText = string.match(gui.Text, "^%d+:%d%d$") ~= nil
	end

	if not isNamedTimer and not isClockText then
		return false
	end

	-- Do not hide ability cooldown timers. Only touch timer elements that live under
	-- the actual battle/match HUD hierarchy.
	return hasNamedAncestor(gui, {"battle", "match"})
end

local function hideTrainingTimers()
	if not inTraining then return end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and isBattleTimerObject(descendant) then
			if hiddenTimerState[descendant] == nil then
				hiddenTimerState[descendant] = descendant.Visible
			end
			descendant.Visible = false
		end
	end
end

local function restoreTimers()
	for gui, wasVisible in pairs(hiddenTimerState) do
		if gui.Parent then
			gui.Visible = wasVisible
		end
		hiddenTimerState[gui] = nil
	end
end

local function leaveTrainingUI()
	inTraining = false
	if levelButton and levelButton.Parent then
		levelButton:Destroy()
	end
	levelButton = nil
	restoreTimers()
end

GameStateUpdate.OnClientEvent:Connect(function(state, data)
	if state == "InMatch" or state == "Fighting" then
		if type(data) == "table"
			and (data.TrainingNoTimer == true or data.OpponentUserId == 0 or data.OpponentName == "Training Dummy") then
			inTraining = true
			if typeof(data.DummyLevel) == "number" then
				currentLevel = math.clamp(math.floor(data.DummyLevel), 0, 10)
			end
			task.defer(ensureLevelButton)
			task.defer(hideTrainingTimers)
		end
	elseif state == "TrainingControlsSync" and inTraining then
		if type(data) == "table" and typeof(data.DummyLevel) == "number" then
			currentLevel = math.clamp(math.floor(data.DummyLevel), 0, 10)
			if levelButton then setButtonLabel(levelButton) end
		end
	elseif state == "Lobby" or state == "ReturningToLobby" then
		leaveTrainingUI()
	end
end)

playerGui.DescendantAdded:Connect(function(descendant)
	if not inTraining then return end
	task.defer(function()
		if not inTraining then return end
		if descendant:IsA("GuiObject") and isBattleTimerObject(descendant) then
			if hiddenTimerState[descendant] == nil then
				hiddenTimerState[descendant] = descendant.Visible
			end
			descendant.Visible = false
		end
		ensureLevelButton()
	end)
end)

task.spawn(function()
	while true do
		task.wait(0.35)
		if inTraining then
			ensureLevelButton()
			hideTrainingTimers()
		end
	end
end)
