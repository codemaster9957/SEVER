--!strict
-- Presentation-only UI unifier for SEVER.
-- It never replaces matchmaking/battle scripts or remotes; it only styles, positions,
-- and temporarily hides the live UI objects those existing systems create.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate")
local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

local battleActive = false
local currentState = "Lobby"
local introData = nil

local matchmakingVisibility: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})
local battleLayoutSnapshots: {[GuiObject]: any} = setmetatable({}, {__mode = "k"})
local styledMatchmaking: {[GuiButton]: boolean} = setmetatable({}, {__mode = "k"})
local styledIntro: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})
local styledHealth: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})

local function lower(value: any): string
	return string.lower(tostring(value or ""))
end

local function visibleText(instance: Instance): string
	if instance:IsA("TextButton") or instance:IsA("TextLabel") then
		if instance.Text ~= "" then
			return instance.Text
		end
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if (descendant:IsA("TextButton") or descendant:IsA("TextLabel")) and descendant.Text ~= "" then
			return descendant.Text
		end
	end
	return ""
end

local function ancestorText(instance: Instance, depth: number): string
	local parts = {instance.Name, visibleText(instance)}
	local current = instance.Parent
	local steps = 0
	while current and current ~= playerGui and steps < depth do
		table.insert(parts, current.Name)
		if current:IsA("GuiObject") then
			table.insert(parts, visibleText(current))
		end
		current = current.Parent
		steps += 1
	end
	return table.concat(parts, " ")
end

local function hasNamedAncestor(instance: Instance, keywords: {string}): boolean
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

local function looksLikeTrainingControl(button: GuiButton): boolean
	if button:GetAttribute("SEVERTrainingLevelControl") == true then
		return true
	end
	local combined = lower(button.Name .. " " .. visibleText(button))
	return string.find(combined, "respawn", 1, true) ~= nil
		or string.find(combined, "infinite", 1, true) ~= nil
		or string.find(combined, "return", 1, true) ~= nil
		or string.find(combined, "lobby", 1, true) ~= nil
		or string.find(combined, "dummy level", 1, true) ~= nil
end

local function findTrainingTemplateButton(): GuiButton?
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

local function findFirstText(root: Instance): TextLabel | TextButton?
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

local function directModifier(root: Instance, className: string): Instance?
	for _, child in ipairs(root:GetChildren()) do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

local function copyModifier(template: Instance, target: Instance, className: string)
	local old = directModifier(target, className)
	if old then
		old:Destroy()
	end
	local source = directModifier(template, className)
	if source then
		source:Clone().Parent = target
	end
end

local function applyFallbackCornerStroke(target: GuiObject)
	local corner = directModifier(target, "UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		(corner :: UICorner).CornerRadius = UDim.new(0, 12)
		corner.Parent = target
	end

	local stroke = directModifier(target, "UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		(stroke :: UIStroke).Thickness = 1.5
		(stroke :: UIStroke).Transparency = 0.3
		(stroke :: UIStroke).Color = Color3.fromRGB(210, 210, 220)
		stroke.Parent = target
	end
end

local function applyTextStyle(sourceText: TextLabel | TextButton?, target: Instance)
	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			if sourceText then
				descendant.FontFace = sourceText.FontFace
				descendant.TextColor3 = sourceText.TextColor3
				descendant.TextStrokeColor3 = sourceText.TextStrokeColor3
				descendant.TextStrokeTransparency = sourceText.TextStrokeTransparency
			else
				descendant.TextColor3 = Color3.fromRGB(245, 245, 250)
				descendant.TextStrokeTransparency = 1
			end
		end
	end
	if target:IsA("TextButton") or target:IsA("TextLabel") then
		if sourceText then
			target.FontFace = sourceText.FontFace
			target.TextColor3 = sourceText.TextColor3
			target.TextStrokeColor3 = sourceText.TextStrokeColor3
			target.TextStrokeTransparency = sourceText.TextStrokeTransparency
		else
			target.TextColor3 = Color3.fromRGB(245, 245, 250)
			target.TextStrokeTransparency = 1
		end
	end
end

local function applyThemeSurface(target: GuiObject, template: GuiButton?, stronger: boolean?)
	if template then
		target.BackgroundColor3 = template.BackgroundColor3
		target.BackgroundTransparency = math.clamp(template.BackgroundTransparency + (stronger and -0.05 or 0.04), 0, 0.75)
		target.BorderSizePixel = 0
		copyModifier(template, target, "UICorner")
		copyModifier(template, target, "UIStroke")
		copyModifier(template, target, "UIGradient")
		applyTextStyle(findFirstText(template), target)
	else
		target.BackgroundColor3 = Color3.fromRGB(20, 21, 28)
		target.BackgroundTransparency = stronger and 0.08 or 0.16
		target.BorderSizePixel = 0
		applyFallbackCornerStroke(target)
		applyTextStyle(nil, target)
	end
end

local function styleMatchmakingButton(button: GuiButton, template: GuiButton?)
	if looksLikeTrainingControl(button) then return end
	local context = ancestorText(button, 3)
	if not Policy.IsMatchmakingControl(button.Name, context) then return end
	if string.find(lower(context), "leaderboard", 1, true) then return end

	applyThemeSurface(button, template, true)
	button.AutoButtonColor = template and template.AutoButtonColor or true
	button.BorderSizePixel = 0
	styledMatchmaking[button] = true
end

local function updateMatchmakingVisibility(template: GuiButton?)
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			local context = ancestorText(descendant, 3)
			if Policy.IsMatchmakingControl(descendant.Name, context)
				and not looksLikeTrainingControl(descendant)
				and not string.find(lower(context), "leaderboard", 1, true) then
				styleMatchmakingButton(descendant, template)
				if battleActive then
					if matchmakingVisibility[descendant] == nil then
						matchmakingVisibility[descendant] = descendant.Visible
					end
					descendant.Visible = false
				elseif matchmakingVisibility[descendant] ~= nil then
					descendant.Visible = matchmakingVisibility[descendant]
					matchmakingVisibility[descendant] = nil
				end
			end
		end
	end
end

local function snapshotLayout(gui: GuiObject)
	if battleLayoutSnapshots[gui] then return end
	battleLayoutSnapshots[gui] = {
		AnchorPoint = gui.AnchorPoint,
		Position = gui.Position,
		Size = gui.Size,
		AutomaticSize = gui.AutomaticSize,
	}
end

local function restoreBattleLayouts()
	for gui, snapshot in pairs(battleLayoutSnapshots) do
		if gui.Parent then
			gui.AnchorPoint = snapshot.AnchorPoint
			gui.Position = snapshot.Position
			gui.Size = snapshot.Size
			gui.AutomaticSize = snapshot.AutomaticSize
		end
		battleLayoutSnapshots[gui] = nil
	end
end

local function classifyHealthCandidate(gui: GuiObject): string?
	local context = ancestorText(gui, 2)
	return Policy.ClassifyHealthPanel(gui.Name, context)
end

local function scoreHealthRoot(gui: GuiObject, role: string): number
	local name = lower(gui.Name)
	local score = 0
	if role == "player" and string.find(name, "playerdisplay", 1, true) then score += 100 end
	if role == "opponent" and string.find(name, "opponentdisplay", 1, true) then score += 100 end
	if string.find(name, "display", 1, true) then score += 30 end
	if string.find(name, "health", 1, true) then score += 15 end
	if gui:IsA("Frame") then score += 8 end
	if gui.AbsoluteSize.X >= 120 then score += 5 end
	return score
end

local function findHealthPanels(): (GuiObject?, GuiObject?)
	local bestPlayer, bestOpponent = nil, nil
	local playerScore, opponentScore = -math.huge, -math.huge
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible then
			local role = classifyHealthCandidate(descendant)
			if role then
				local score = scoreHealthRoot(descendant, role)
				if role == "player" and score > playerScore then
					bestPlayer, playerScore = descendant, score
				elseif role == "opponent" and score > opponentScore then
					bestOpponent, opponentScore = descendant, score
				end
			end
		end
	end
	return bestPlayer, bestOpponent
end

local function viewportSize(): Vector2
	local current = workspace.CurrentCamera or camera
	return current and current.ViewportSize or Vector2.new(1280, 720)
end

local function layoutHealthPanel(panel: GuiObject, role: string, template: GuiButton?)
	snapshotLayout(panel)
	local viewport = viewportSize()
	local mobile = viewport.X < 700
	local width = math.floor(math.clamp(viewport.X * (mobile and 0.42 or 0.28), mobile and 145 or 230, mobile and 190 or 340))
	local height = mobile and 56 or 68
	local edge = mobile and 10 or 18
	local insetTopLeft = GuiService:GetGuiInset()
	local top = math.max(edge, insetTopLeft.Y + (mobile and 6 or 10))

	panel.AutomaticSize = Enum.AutomaticSize.None
	panel.Size = UDim2.fromOffset(width, height)
	panel.AnchorPoint = role == "player" and Vector2.new(0, 0) or Vector2.new(1, 0)
	panel.Position = role == "player"
		and UDim2.new(0, edge, 0, top)
		or UDim2.new(1, -edge, 0, top)
	panel.ZIndex = math.max(panel.ZIndex, 20)

	applyThemeSurface(panel, template, false)
	styledHealth[panel] = true
end

local function styleHealthHUD(template: GuiButton?)
	if not battleActive then return end
	local playerPanel, opponentPanel = findHealthPanels()
	if playerPanel then layoutHealthPanel(playerPanel, "player", template) end
	if opponentPanel and opponentPanel ~= playerPanel then
		layoutHealthPanel(opponentPanel, "opponent", template)
	end
end

local function isIntroText(descendant: Instance): boolean
	if not (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) then return false end
	local text = descendant.Text
	if text == "" then return false end
	local lowerText = lower(text)
	if lowerText == "vs" or string.find(lowerText, "versus", 1, true) then return true end
	if type(introData) == "table" then
		local p1 = introData.p1
		local p2 = introData.p2
		if type(p1) == "table" and text == p1.Name then return true end
		if type(p2) == "table" and text == p2.Name then return true end
	end
	return false
end

local function nearestIntroCard(instance: Instance): GuiObject?
	local current = instance.Parent
	local fallback = nil
	for _ = 1, 5 do
		if not current or current == playerGui then break end
		if current:IsA("GuiObject") then
			fallback = current
			local name = lower(current.Name)
			if string.find(name, "intro", 1, true)
				or string.find(name, "card", 1, true)
				or string.find(name, "player", 1, true)
				or string.find(name, "versus", 1, true) then
				return current
			end
		end
		current = current.Parent
	end
	return fallback
end

local function styleBattleIntro(template: GuiButton?)
	if currentState ~= "BattleIntro" then return end

	local candidates: {[GuiObject]: boolean} = {}
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible then
			local context = ancestorText(descendant, 2)
			if Policy.LooksLikeBattleIntro(descendant.Name, context) or isIntroText(descendant) then
				local card = nearestIntroCard(descendant)
				if card then candidates[card] = true end
			end
		end
	end

	for card in pairs(candidates) do
		applyThemeSurface(card, template, true)
		card.BorderSizePixel = 0
		card.ZIndex = math.max(card.ZIndex, 30)
		styledIntro[card] = true
		for _, descendant in ipairs(card:GetDescendants()) do
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				descendant.TextColor3 = Color3.fromRGB(248, 248, 252)
				if lower(descendant.Text) == "vs" then
					descendant.TextScaled = true
					descendant.TextStrokeTransparency = 0.6
				end
			end
		end
	end
end

local function applyUnifiedUI()
	local template = findTrainingTemplateButton()
	updateMatchmakingVisibility(template)
	if battleActive then
		styleHealthHUD(template)
		styleBattleIntro(template)
	end
end

local function setState(state: string, data: any)
	currentState = state
	if state == "BattleIntro" then
		introData = data
	end

	if Policy.IsBattleState(state) then
		battleActive = true
	elseif state == "Lobby" then
		battleActive = false
		introData = nil
		restoreBattleLayouts()
	end

	task.defer(applyUnifiedUI)
end

GameStateUpdate.OnClientEvent:Connect(setState)

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("GuiObject") then
		task.defer(applyUnifiedUI)
	end
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if battleActive then
			task.defer(styleHealthHUD, findTrainingTemplateButton())
		end
	end)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.35 then return end
	accumulator = 0
	applyUnifiedUI()
end)

-- Initial lobby style pass once existing UI has had a chance to mount.
task.delay(1, applyUnifiedUI)
