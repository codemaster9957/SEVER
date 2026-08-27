--!strict
-- SEVER UI presentation bridge.
-- The live Training Dummy settings UI is the ONLY visual source of truth.
-- This script never creates a replacement battle intro and never changes HUD geometry.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameStateUpdate = ReplicatedStorage:WaitForChild("MatchEvents"):WaitForChild("GameStateUpdate")
local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

local battleActive = false
local introActive = false
local introGeneration = 0
local introData: any = nil
local cachedThemeButton: GuiButton? = nil
local matchmakingVisibility: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})

local function lower(value: any): string
	return string.lower(tostring(value or ""))
end

local function firstText(root: Instance): TextLabel | TextButton?
	if root:IsA("TextLabel") or root:IsA("TextButton") then
		return root
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Text ~= "" then
			return descendant
		end
	end
	return nil
end

local function visibleText(root: Instance): string
	local textObject = firstText(root)
	return textObject and textObject.Text or ""
end

local function contextText(instance: Instance, depth: number): string
	local pieces = {instance.Name, visibleText(instance)}
	local current = instance.Parent
	local count = 0
	while current and current ~= playerGui and count < depth do
		table.insert(pieces, current.Name)
		if current:IsA("GuiObject") then
			table.insert(pieces, visibleText(current))
		end
		current = current.Parent
		count += 1
	end
	return table.concat(pieces, " ")
end

local function directModifier(root: Instance, className: string): Instance?
	for _, child in ipairs(root:GetChildren()) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

local function hasTrainingAncestor(instance: Instance): boolean
	local current = instance.Parent
	while current and current ~= playerGui do
		local name = lower(current.Name)
		if string.find(name, "training", 1, true) or string.find(name, "dummy", 1, true) then
			return true
		end
		current = current.Parent
	end
	return false
end

local function isTrainingButton(button: GuiButton): boolean
	if button:GetAttribute("SEVERTrainingLevelControl") == true then
		return true
	end

	local combined = lower(button.Name .. " " .. visibleText(button) .. " " .. contextText(button, 3))
	return string.find(combined, "respawn dummy", 1, true) ~= nil
		or string.find(combined, "infinite health", 1, true) ~= nil
		or string.find(combined, "return to lobby", 1, true) ~= nil
		or string.find(combined, "dummy level", 1, true) ~= nil
		or (hasTrainingAncestor(button)
			and (string.find(combined, "respawn", 1, true)
				or string.find(combined, "infinite", 1, true)
				or string.find(combined, "return", 1, true)
				or string.find(combined, "level", 1, true)))
end

-- Hidden buttons count too. The dummy settings UI can be hidden while the player is in Lobby/PvP.
local function findThemeButton(): GuiButton?
	if cachedThemeButton and cachedThemeButton.Parent then
		return cachedThemeButton
	end

	local best: GuiButton? = nil
	local bestScore = -math.huge
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and isTrainingButton(descendant) then
			local combined = lower(descendant.Name .. " " .. visibleText(descendant))
			local score = 10
			if string.find(combined, "respawn", 1, true) then score += 100 end
			if descendant:GetAttribute("SEVERTrainingLevelControl") == true then score += 30 end
			if directModifier(descendant, "UICorner") then score += 5 end
			if directModifier(descendant, "UIStroke") then score += 5 end
			if directModifier(descendant, "UIGradient") then score += 5 end
			if score > bestScore then
				best = descendant
				bestScore = score
			end
		end
	end

	cachedThemeButton = best
	return best
end

local function replaceDirectModifier(template: Instance, target: Instance, className: string)
	local existing = directModifier(target, className)
	if existing then
		existing:Destroy()
	end
	local source = directModifier(template, className)
	if source then
		source:Clone().Parent = target
	end
end

local function applyExactText(textObject: TextLabel | TextButton, template: GuiButton)
	local source = firstText(template)
	if not source then return end

	-- Style only. Layout, size, alignment and animation properties stay authored by the original UI.
	textObject.FontFace = source.FontFace
	textObject.TextColor3 = source.TextColor3
	textObject.TextStrokeColor3 = source.TextStrokeColor3
	textObject.TextStrokeTransparency = source.TextStrokeTransparency
end

local function applyExactTextTree(root: Instance, template: GuiButton)
	if root:IsA("TextLabel") or root:IsA("TextButton") then
		applyExactText(root, template)
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			applyExactText(descendant, template)
		end
	end
end

local function applyExactDummySurface(target: GuiObject, template: GuiButton): boolean
	-- These are copied literally from the authored dummy settings control.
	-- Geometry is intentionally NOT copied.
	target.BackgroundColor3 = template.BackgroundColor3
	target.BackgroundTransparency = template.BackgroundTransparency
	target.BorderColor3 = template.BorderColor3
	target.BorderSizePixel = template.BorderSizePixel
	target.BorderMode = template.BorderMode

	replaceDirectModifier(template, target, "UICorner")
	replaceDirectModifier(template, target, "UIStroke")
	replaceDirectModifier(template, target, "UIGradient")
	applyExactTextTree(target, template)

	if target:IsA("GuiButton") then
		target.AutoButtonColor = template.AutoButtonColor
	end
	return true
end

local function isMatchmakingButton(button: GuiButton): boolean
	return not isTrainingButton(button)
		and Policy.IsMatchmakingControl(button.Name, contextText(button, 3))
end

local function styleMatchmakingButton(button: GuiButton)
	if not isMatchmakingButton(button) then return end

	local template = findThemeButton()
	if template then
		applyExactDummySurface(button, template)
	end

	if battleActive then
		if matchmakingVisibility[button] == nil then
			matchmakingVisibility[button] = button.Visible
		end
		button.Visible = false
	elseif matchmakingVisibility[button] ~= nil then
		button.Visible = matchmakingVisibility[button]
		matchmakingVisibility[button] = nil
	end
end

local function refreshMatchmaking()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			styleMatchmakingButton(descendant)
		end
	end
end

local function isHealthContainer(gui: GuiObject): boolean
	local name = lower(gui.Name)
	return string.find(name, "playerdisplay", 1, true) ~= nil
		or string.find(name, "opponentdisplay", 1, true) ~= nil
end

local function styleHealthContainer(gui: GuiObject)
	if not isHealthContainer(gui) then return end
	local template = findThemeButton()
	if not template then return end

	-- CRITICAL: never touch Size, Position, AnchorPoint, AutomaticSize,
	-- ClipsDescendants or any child health-fill geometry.
	applyExactDummySurface(gui, template)
end

local function refreshHealth()
	if not battleActive then return end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and isHealthContainer(descendant) then
			styleHealthContainer(descendant)
		end
	end
end

local function cleanupGeneratedIntros()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui")
			and (child.Name == "SEVER_LightBattleIntro" or child.Name == "SEVER_BattleIntro") then
			child:Destroy()
		end
	end
end

local function introNames(data: any): (string, string)
	local p1 = type(data) == "table" and data.p1 or nil
	local p2 = type(data) == "table" and data.p2 or nil
	local p1Name = type(p1) == "table" and tostring(p1.Name or "") or ""
	local p2Name = type(p2) == "table" and tostring(p2.Name or "") or ""
	return lower(p1Name), lower(p2Name)
end

local function screenLooksLikeBattleIntro(gui: ScreenGui, data: any): boolean
	local guiName = lower(gui.Name)
	if string.find(guiName, "battleintro", 1, true)
		or string.find(guiName, "battle intro", 1, true)
		or string.find(guiName, "versus", 1, true) then
		return true
	end

	local p1Name, p2Name = introNames(data)
	local hasVs = false
	local fighterHits = 0
	for _, descendant in ipairs(gui:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			local text = lower(descendant.Text)
			if text == "vs" or text == "versus" then
				hasVs = true
			end
			if p1Name ~= "" and text == p1Name then fighterHits += 1 end
			if p2Name ~= "" and text == p2Name then fighterHits += 1 end
		end
	end
	return hasVs and fighterHits >= 1
end

local function isFullscreenLike(gui: GuiObject): boolean
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize
	if not viewport or viewport.X <= 0 or viewport.Y <= 0 then
		return false
	end
	return gui.AbsoluteSize.X >= viewport.X * 0.84
		and gui.AbsoluteSize.Y >= viewport.Y * 0.84
end

local INTRO_SURFACE_WORDS = {
	"card", "panel", "player", "opponent", "challenger", "enemy",
	"versus", "fighter", "left", "right", "profile",
}

local function shouldThemeIntroSurface(gui: GuiObject): boolean
	local name = lower(gui.Name)
	for _, word in ipairs(INTRO_SURFACE_WORDS) do
		if string.find(name, word, 1, true) then
			return true
		end
	end

	-- Preserve the full-screen background/composition. Theme only smaller visible panels.
	return gui:IsA("Frame")
		and gui.BackgroundTransparency < 0.95
		and not isFullscreenLike(gui)
end

local function styleExistingBattleIntro(data: any)
	if not introActive then return end
	local template = findThemeButton()
	if not template then return end

	cleanupGeneratedIntros()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and screenLooksLikeBattleIntro(child, data) then
			for _, descendant in ipairs(child:GetDescendants()) do
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
					applyExactText(descendant, template)
				elseif descendant:IsA("GuiButton") then
					applyExactDummySurface(descendant, template)
				elseif descendant:IsA("GuiObject") and shouldThemeIntroSurface(descendant) then
					applyExactDummySurface(descendant, template)
				end
			end
		end
	end
end

local function scheduleIntroSkin(data: any)
	introGeneration += 1
	local generation = introGeneration
	introData = data
	introActive = true
	cleanupGeneratedIntros()

	-- Existing binary intro can mount after this listener. Finite retries catch it
	-- without bringing back the old heartbeat/full-PlayerGui scanner.
	for _, delaySeconds in ipairs({0, 0.04, 0.10, 0.20, 0.38, 0.70}) do
		task.delay(delaySeconds, function()
			if introActive and generation == introGeneration then
				styleExistingBattleIntro(data)
			end
		end)
	end
end

local function handleState(state: string, data: any)
	if Policy.IsBattleState(state) then
		battleActive = true
	elseif state == "Lobby" then
		battleActive = false
	end

	if state == "BattleIntro" then
		scheduleIntroSkin(data)
	elseif state == "Countdown" or state == "Fighting" or state == "Lobby" or state == "ReturningToLobby" then
		introActive = false
		introGeneration += 1
		introData = nil
		cleanupGeneratedIntros()
	end

	refreshMatchmaking()
	if battleActive then
		refreshHealth()
	end
end

GameStateUpdate.OnClientEvent:Connect(handleState)

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("GuiButton") then
		if isTrainingButton(descendant) then
			cachedThemeButton = nil
			task.defer(function()
				refreshMatchmaking()
				if battleActive then refreshHealth() end
				if introActive then styleExistingBattleIntro(introData) end
			end)
		else
			task.defer(styleMatchmakingButton, descendant)
		end
	elseif descendant:IsA("GuiObject") and battleActive and isHealthContainer(descendant) then
		task.defer(styleHealthContainer, descendant)
	end
end)

-- Clean up any generated intro left behind by an older hot-reloaded version.
cleanupGeneratedIntros()

task.delay(0.8, function()
	cachedThemeButton = nil
	refreshMatchmaking()
	if battleActive then refreshHealth() end
end)
