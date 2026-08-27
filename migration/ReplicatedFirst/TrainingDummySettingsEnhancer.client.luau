--!strict
-- Adds the training dummy level setting without redesigning the existing UI.
-- It clones a live training settings button so all authored styling is inherited exactly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate") :: RemoteEvent
local TrainingControls = MatchEvents:WaitForChild("TrainingDummyControls")
local SetDummyLevel = TrainingControls:WaitForChild("SetDummyLevel") :: RemoteEvent

local inTraining = false
local currentLevel = 1
local levelButton: GuiButton? = nil
local hiddenTimerState: {[GuiObject]: boolean} = {}

local function lower(value: string): string
	return string.lower(value)
end

local function visibleText(instance: Instance): string
	if instance:IsA("TextButton") or instance:IsA("TextLabel") then
		return instance.Text
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
			if descendant.Text ~= "" then
				return descendant.Text
			end
		end
	end
	return ""
end

local function looksLikeTrainingControl(button: GuiButton): boolean
	local text = lower(visibleText(button))
	local name = lower(button.Name)
	local combined = name .. " " .. text
	return string.find(combined, "respawn", 1, true) ~= nil
		or string.find(combined, "infinite", 1, true) ~= nil
		or string.find(combined, "return", 1, true) ~= nil
		or string.find(combined, "lobby", 1, true) ~= nil
end

local function findTemplateButton(): GuiButton?
	local preferred: GuiButton? = nil
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and descendant.Visible and looksLikeTrainingControl(descendant) then
			local text = lower(visibleText(descendant))
			if string.find(text, "respawn", 1, true) then
				return descendant
			end
			preferred = preferred or descendant
		end
	end
	return preferred
end

local function setButtonLabel(button: GuiButton)
	local labelText = string.format("DUMMY LEVEL: %d", currentLevel)
	if button:IsA("TextButton") and button.Text ~= "" then
		button.Text = labelText
		return
	end

	local bestLabel: TextLabel? = nil
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") and descendant.Text ~= "" then
			local text = lower(descendant.Text)
			if string.find(text, "respawn", 1, true)
				or string.find(text, "infinite", 1, true)
				or string.find(text, "return", 1, true)
				or string.find(text, "lobby", 1, true) then
				bestLabel = descendant
				break
			end
			bestLabel = bestLabel or descendant
		end
	end
	if bestLabel then
		bestLabel.Text = labelText
	end
end

local function placeCloneAfterTemplate(clone: GuiButton, template: GuiButton)
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

local function isBattleTimerObject(gui: GuiObject): boolean
	local name = lower(gui.Name)
	if string.find(name, "timer", 1, true) ~= nil then
		return true
	end

	if gui:IsA("TextLabel") or gui:IsA("TextButton") then
		local text = gui.Text
		if string.match(text, "^%d+:%d%d$") then
			local current: Instance? = gui.Parent
			while current and current ~= playerGui do
				local ancestorName = lower(current.Name)
				if string.find(ancestorName, "battle", 1, true)
					or string.find(ancestorName, "match", 1, true) then
					return true
				end
				current = current.Parent
			end
		end
	end
	return false
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

-- Existing UI scripts may rebuild controls or set timer visibility after state changes.
-- A light watchdog keeps the cloned control and training-only timer state consistent.
task.spawn(function()
	while true do
		task.wait(0.35)
		if inTraining then
			ensureLevelButton()
			hideTrainingTimers()
		end
	end
end)
