--!strict
-- Cohesive SEVER presentation layer.
-- Keeps existing matchmaking/battle logic intact while replacing the battle intro visual
-- and copying the authored training-dummy settings style onto the relevant live UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MatchEvents = ReplicatedStorage:WaitForChild("MatchEvents")
local GameStateUpdate = MatchEvents:WaitForChild("GameStateUpdate")
local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

local battleActive = false
local introActive = false
local currentIntroGui: ScreenGui? = nil
local introToken = 0
local matchmakingVisibleSnapshot: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})
local legacyVisibleSnapshot: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})
local legacyEnabledSnapshot: {[ScreenGui]: boolean} = setmetatable({}, {__mode = "k"})

local function lower(value: any): string
	return string.lower(tostring(value or ""))
end

local function visibleText(instance: Instance): string
	if instance:IsA("TextButton") or instance:IsA("TextLabel") then
		if instance.Text ~= "" then return instance.Text end
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if (descendant:IsA("TextButton") or descendant:IsA("TextLabel")) and descendant.Text ~= "" then
			return descendant.Text
		end
	end
	return ""
end

local function ancestorNames(instance: Instance, depth: number): string
	local parts = {instance.Name, visibleText(instance)}
	local current = instance.Parent
	local count = 0
	while current and current ~= playerGui and count < depth do
		table.insert(parts, current.Name)
		if current:IsA("GuiObject") then
			table.insert(parts, visibleText(current))
		end
		current = current.Parent
		count += 1
	end
	return table.concat(parts, " ")
end

local function isTrainingButton(button: GuiButton): boolean
	local combined = lower(button.Name .. " " .. visibleText(button) .. " " .. ancestorNames(button, 3))
	return string.find(combined, "respawn dummy", 1, true) ~= nil
		or string.find(combined, "infinite health", 1, true) ~= nil
		or string.find(combined, "return to lobby", 1, true) ~= nil
		or string.find(combined, "dummy level", 1, true) ~= nil
		or button:GetAttribute("SEVERTrainingLevelControl") == true
end

local function findThemeButton(): GuiButton?
	local best: GuiButton? = nil
	local bestScore = -math.huge
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and isTrainingButton(descendant) then
			local text = lower(visibleText(descendant))
			local score = 10
			if string.find(text, "respawn", 1, true) then score += 20 end
			if descendant:FindFirstChildOfClass("UIGradient") then score += 4 end
			if descendant:FindFirstChildOfClass("UIStroke") then score += 4 end
			if descendant:FindFirstChildOfClass("UICorner") then score += 4 end
			if score > bestScore then
				bestScore = score
				best = descendant
			end
		end
	end
	return best
end

local function firstText(root: Instance): TextLabel | TextButton?
	if root:IsA("TextLabel") or root:IsA("TextButton") then return root end
	for _, descendant in ipairs(root:GetDescendants()) do
		if (descendant:IsA("TextLabel") or descendant:IsA("TextButton")) and descendant.Text ~= "" then
			return descendant
		end
	end
	return nil
end

local function directChildOfClass(root: Instance, className: string): Instance?
	for _, child in ipairs(root:GetChildren()) do
		if child.ClassName == className then return child end
	end
	return nil
end

local function replaceModifier(target: Instance, template: Instance?, className: string)
	local old = directChildOfClass(target, className)
	if old then old:Destroy() end
	if template then
		local source = directChildOfClass(template, className)
		if source then source:Clone().Parent = target end
	end
end

local function ensureFallbackSurface(target: GuiObject)
	if not target:FindFirstChildOfClass("UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = target
	end
	if not target:FindFirstChildOfClass("UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1.4
		stroke.Transparency = 0.34
		stroke.Color = Color3.fromRGB(225, 225, 235)
		stroke.Parent = target
	end
end

local function applyTextTheme(target: Instance, template: GuiButton?)
	local sourceText = template and firstText(template) or nil
	local function style(textObject: TextLabel | TextButton)
		if sourceText then
			textObject.FontFace = sourceText.FontFace
			textObject.TextColor3 = sourceText.TextColor3
			textObject.TextStrokeColor3 = sourceText.TextStrokeColor3
			textObject.TextStrokeTransparency = sourceText.TextStrokeTransparency
		else
			textObject.TextColor3 = Color3.fromRGB(247, 247, 250)
			textObject.TextStrokeTransparency = 1
		end
	end

	if target:IsA("TextLabel") or target:IsA("TextButton") then style(target) end
	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then style(descendant) end
	end
end

local function applySurface(target: GuiObject, template: GuiButton?, strong: boolean?)
	if template then
		target.BackgroundColor3 = template.BackgroundColor3
		target.BackgroundTransparency = math.clamp(template.BackgroundTransparency + (strong and -0.04 or 0.02), 0, 0.8)
		replaceModifier(target, template, "UICorner")
		replaceModifier(target, template, "UIStroke")
		replaceModifier(target, template, "UIGradient")
	else
		target.BackgroundColor3 = Color3.fromRGB(20, 21, 28)
		target.BackgroundTransparency = strong and 0.06 or 0.14
		ensureFallbackSurface(target)
	end
	target.BorderSizePixel = 0
	applyTextTheme(target, template)
end

local function isMatchmakingButton(button: GuiButton): boolean
	if isTrainingButton(button) then return false end
	local context = ancestorNames(button, 3)
	return Policy.IsMatchmakingControl(button.Name, context)
end

local function styleMatchmaking(template: GuiButton?)
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and isMatchmakingButton(descendant) then
			applySurface(descendant, template, true)
			if template then descendant.AutoButtonColor = template.AutoButtonColor end
			if battleActive then
				if matchmakingVisibleSnapshot[descendant] == nil then
					matchmakingVisibleSnapshot[descendant] = descendant.Visible
				end
				descendant.Visible = false
			elseif matchmakingVisibleSnapshot[descendant] ~= nil then
				descendant.Visible = matchmakingVisibleSnapshot[descendant]
				matchmakingVisibleSnapshot[descendant] = nil
			end
		end
	end
end

local function healthRole(gui: GuiObject): string?
	return Policy.ClassifyHealthPanel(gui.Name, ancestorNames(gui, 2))
end

local function scoreHealth(gui: GuiObject, role: string): number
	local name = lower(gui.Name)
	local score = gui:IsA("Frame") and 10 or 0
	if role == "player" and string.find(name, "playerdisplay", 1, true) then score += 100 end
	if role == "opponent" and string.find(name, "opponentdisplay", 1, true) then score += 100 end
	if string.find(name, "display", 1, true) then score += 20 end
	if gui.AbsoluteSize.X > 120 then score += 5 end
	return score
end

local function styleHealth(template: GuiButton?)
	if not battleActive then return end
	local bestPlayer: GuiObject? = nil
	local bestOpponent: GuiObject? = nil
	local playerScore = -math.huge
	local opponentScore = -math.huge

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible then
			local role = healthRole(descendant)
			if role then
				local score = scoreHealth(descendant, role)
				if role == "player" and score > playerScore then bestPlayer, playerScore = descendant, score end
				if role == "opponent" and score > opponentScore then bestOpponent, opponentScore = descendant, score end
			end
		end
	end

	for _, panel in ipairs({bestPlayer, bestOpponent}) do
		if panel then applySurface(panel, template, false) end
	end
end

local function themeStrokeColor(template: GuiButton?): Color3
	if template then
		local stroke = template:FindFirstChildOfClass("UIStroke")
		if stroke then return stroke.Color end
	end
	return Color3.fromRGB(232, 232, 240)
end

local function makeText(parent: Instance, text: string, size: UDim2, position: UDim2, fontSize: number, template: GuiButton?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextSize = fontSize
	label.TextScaled = false
	label.TextWrapped = true
	label.Size = size
	label.Position = position
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	applyTextTheme(label, template)
	return label
end

local function loadThumbnail(image: ImageLabel, userId: number)
	if userId <= 0 then
		image.Visible = false
		return
	end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and image.Parent then image.Image = content end
	end)
end

local function makeCard(parent: Instance, name: string, userId: number, side: string, template: GuiButton?): Frame
	local card = Instance.new("Frame")
	card.Name = side .. "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromScale(0.31, 0.32)
	card.Position = side == "Left" and UDim2.fromScale(-0.18, 0.52) or UDim2.fromScale(1.18, 0.52)
	card.Parent = parent
	applySurface(card, template, true)

	local portraitShell = Instance.new("Frame")
	portraitShell.Name = "PortraitShell"
	portraitShell.AnchorPoint = Vector2.new(0.5, 0)
	portraitShell.Position = UDim2.fromScale(0.5, 0.08)
	portraitShell.Size = UDim2.fromScale(0.34, 0.48)
	portraitShell.Parent = card
	applySurface(portraitShell, template, false)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = portraitShell

	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = ""
	image.Parent = portraitShell
	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(1, 0)
	imageCorner.Parent = image
	loadThumbnail(image, userId)

	if userId <= 0 then
		local dummyMark = makeText(portraitShell, "AI", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 30, template)
		dummyMark.TextScaled = true
	end

	local tag = makeText(card, userId <= 0 and "TRAINING DUMMY" or (side == "Left" and "CHALLENGER" or "OPPONENT"), UDim2.fromScale(0.9, 0.12), UDim2.fromScale(0.05, 0.59), 12, template)
	tag.TextTransparency = 0.22
	local nameLabel = makeText(card, string.upper(name), UDim2.fromScale(0.92, 0.2), UDim2.fromScale(0.04, 0.69), 24, template)
	nameLabel.TextScaled = true
	local nameLimit = Instance.new("UITextSizeConstraint")
	nameLimit.MinTextSize = 13
	nameLimit.MaxTextSize = 28
	nameLimit.Parent = nameLabel

	return card
end

local function isOurIntro(instance: Instance): boolean
	return currentIntroGui ~= nil and instance:IsDescendantOf(currentIntroGui)
end

local function strongLegacyIntroMatch(instance: Instance, leftName: string, rightName: string): boolean
	if isOurIntro(instance) then return false end
	local name = lower(instance.Name)
	local text = instance:IsA("TextLabel") or instance:IsA("TextButton") and instance.Text or ""
	local combined = lower(name .. " " .. text .. " " .. ancestorNames(instance, 2))
	if string.find(name, "battleintro", 1, true)
		or string.find(name, "battle intro", 1, true)
		or string.find(name, "versus", 1, true) then return true end
	if lower(text) == "vs" and (string.find(combined, "battle", 1, true) or string.find(combined, "intro", 1, true)) then return true end
	if (text == leftName or text == rightName) and (string.find(combined, "intro", 1, true) or string.find(combined, "versus", 1, true)) then return true end
	return false
end

local function suppressLegacyIntro(leftName: string, rightName: string)
	if not introActive then return end
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child ~= currentIntroGui then
			local n = lower(child.Name)
			if string.find(n, "battleintro", 1, true) or string.find(n, "versus", 1, true) then
				if legacyEnabledSnapshot[child] == nil then legacyEnabledSnapshot[child] = child.Enabled end
				child.Enabled = false
			end
		end
	end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible and strongLegacyIntroMatch(descendant, leftName, rightName) then
			if legacyVisibleSnapshot[descendant] == nil then legacyVisibleSnapshot[descendant] = descendant.Visible end
			descendant.Visible = false
		end
	end
end

local function restoreLegacyIntro()
	for gui, visible in pairs(legacyVisibleSnapshot) do
		if gui.Parent then gui.Visible = visible end
		legacyVisibleSnapshot[gui] = nil
	end
	for gui, enabled in pairs(legacyEnabledSnapshot) do
		if gui.Parent then gui.Enabled = enabled end
		legacyEnabledSnapshot[gui] = nil
	end
end

local function destroyCurrentIntro(animated: boolean)
	introActive = false
	introToken += 1
	local gui = currentIntroGui
	currentIntroGui = nil
	if not gui or not gui.Parent then
		restoreLegacyIntro()
		return
	end

	local root = gui:FindFirstChild("Root")
	if animated and root and root:IsA("Frame") then
		TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("GuiObject") then
				if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
					TweenService:Create(descendant, TweenInfo.new(0.16), {TextTransparency = 1, BackgroundTransparency = 1}):Play()
				elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
					TweenService:Create(descendant, TweenInfo.new(0.16), {ImageTransparency = 1, BackgroundTransparency = 1}):Play()
				else
					TweenService:Create(descendant, TweenInfo.new(0.16), {BackgroundTransparency = 1}):Play()
				end
			end
		end
		task.delay(0.2, function()
			if gui.Parent then gui:Destroy() end
			restoreLegacyIntro()
		end)
	else
		gui:Destroy()
		restoreLegacyIntro()
	end
end

local function startIntro(data: any)
	destroyCurrentIntro(false)
	introToken += 1
	local token = introToken
	introActive = true

	local p1 = type(data) == "table" and data.p1 or nil
	local p2 = type(data) == "table" and data.p2 or nil
	if type(p1) ~= "table" then p1 = {Name = player.Name, UserId = player.UserId} end
	if type(p2) ~= "table" then p2 = {Name = "Opponent", UserId = 0} end

	local left = p1
	local right = p2
	if tonumber(p2.UserId) == player.UserId then left, right = p2, p1 end
	local leftName = tostring(left.Name or "PLAYER")
	local rightName = tostring(right.Name or "OPPONENT")
	local leftUserId = tonumber(left.UserId) or 0
	local rightUserId = tonumber(right.UserId) or 0

	local template = findThemeButton()
	local accent = themeStrokeColor(template)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SEVER_BattleIntro"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 500
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	currentIntroGui = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	root.BackgroundTransparency = 0.08
	root.BorderSizePixel = 0
	root.Parent = gui

	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 8, 12)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 18, 24)), ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 7, 10))})
	shade.Parent = root

	local title = makeText(root, "SEVER  //  DUEL", UDim2.fromScale(0.38, 0.06), UDim2.fromScale(0.31, 0.08), 16, template)
	title.TextTransparency = 0.15
	title.TextScaled = true
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MinTextSize = 11
	titleLimit.MaxTextSize = 18
	titleLimit.Parent = title

	local leftCard = makeCard(root, leftName, leftUserId, "Left", template)
	local rightCard = makeCard(root, rightName, rightUserId, "Right", template)

	local slash = Instance.new("Frame")
	slash.Name = "ScytheSlice"
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromScale(0.5, 0.52)
	slash.Size = UDim2.fromScale(0.006, 0.62)
	slash.Rotation = 14
	slash.BackgroundColor3 = accent
	slash.BackgroundTransparency = 0.15
	slash.BorderSizePixel = 0
	slash.Parent = root
	local slashCorner = Instance.new("UICorner")
	slashCorner.CornerRadius = UDim.new(1, 0)
	slashCorner.Parent = slash

	local vsShell = Instance.new("Frame")
	vsShell.Name = "VSShell"
	vsShell.AnchorPoint = Vector2.new(0.5, 0.5)
	vsShell.Position = UDim2.fromScale(0.5, 0.52)
	vsShell.Size = UDim2.fromOffset(88, 88)
	vsShell.Parent = root
	applySurface(vsShell, template, true)
	local vsAspect = Instance.new("UIAspectRatioConstraint")
	vsAspect.AspectRatio = 1
	vsAspect.Parent = vsShell
	local vsCorner = vsShell:FindFirstChildOfClass("UICorner")
	if vsCorner then vsCorner.CornerRadius = UDim.new(1, 0) end
	local vs = makeText(vsShell, "VS", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 32, template)
	vs.TextScaled = true
	vs.TextStrokeTransparency = 0.55

	local footer = makeText(root, "THE ARENA IS LOCKED", UDim2.fromScale(0.34, 0.04), UDim2.fromScale(0.33, 0.89), 12, template)
	footer.TextTransparency = 0.28
	footer.TextScaled = true
	local footerLimit = Instance.new("UITextSizeConstraint")
	footerLimit.MinTextSize = 9
	footerLimit.MaxTextSize = 13
	footerLimit.Parent = footer

	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	if viewport.X < 700 then
		leftCard.Size = UDim2.fromScale(0.4, 0.3)
		rightCard.Size = UDim2.fromScale(0.4, 0.3)
		vsShell.Size = UDim2.fromOffset(58, 58)
		title.Size = UDim2.fromScale(0.62, 0.055)
		title.Position = UDim2.fromScale(0.19, 0.1)
	end

	root.BackgroundTransparency = 1
	TweenService:Create(root, TweenInfo.new(0.18), {BackgroundTransparency = 0.08}):Play()
	TweenService:Create(leftCard, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.27, 0.52)}):Play()
	TweenService:Create(rightCard, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.73, 0.52)}):Play()
	vsShell.Size = UDim2.fromOffset(18, 18)
	TweenService:Create(vsShell, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = viewport.X < 700 and UDim2.fromOffset(58, 58) or UDim2.fromOffset(88, 88)}):Play()
	slash.BackgroundTransparency = 1
	TweenService:Create(slash, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.15}):Play()

	suppressLegacyIntro(leftName, rightName)
	task.spawn(function()
		while introActive and token == introToken do
			suppressLegacyIntro(leftName, rightName)
			task.wait(0.08)
		end
	end)
end

local function refreshPresentation()
	local template = findThemeButton()
	styleMatchmaking(template)
	styleHealth(template)
end

GameStateUpdate.OnClientEvent:Connect(function(state, data)
	if state == "BattleIntro" then
		battleActive = true
		startIntro(data)
	elseif Policy.IsBattleState(state) then
		battleActive = true
		if state == "Countdown" or state == "Fighting" or state == "MatchEnded" or state == "ReturningToLobby" then
			destroyCurrentIntro(true)
		end
	elseif state == "Lobby" then
		battleActive = false
		destroyCurrentIntro(false)
	end
	task.defer(refreshPresentation)
end)

playerGui.DescendantAdded:Connect(function(descendant)
	if introActive and descendant:IsA("GuiObject") then
		task.defer(function()
			if introActive then refreshPresentation() end
		end)
	else
		task.defer(refreshPresentation)
	end
end)

local accumulated = 0
game:GetService("RunService").Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < 0.4 then return end
	accumulated = 0
	refreshPresentation()
end)

task.delay(1, refreshPresentation)
