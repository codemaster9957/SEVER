--!strict
-- Cohesive SEVER presentation layer. Existing gameplay/remotes stay untouched.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameStateUpdate = ReplicatedStorage:WaitForChild("MatchEvents"):WaitForChild("GameStateUpdate")
local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

local battleActive = false
local introActive = false
local introGui: ScreenGui? = nil
local introToken = 0
local matchmakingSnapshots: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})
local legacyGuiSnapshots: {[ScreenGui]: boolean} = setmetatable({}, {__mode = "k"})
local legacyObjectSnapshots: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})

local function lower(value: any): string
	return string.lower(tostring(value or ""))
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

local function visibleText(root: Instance): string
	local object = firstText(root)
	return object and object.Text or ""
end

local function contextText(instance: Instance, depth: number): string
	local pieces = {instance.Name, visibleText(instance)}
	local current = instance.Parent
	local count = 0
	while current and current ~= playerGui and count < depth do
		table.insert(pieces, current.Name)
		if current:IsA("GuiObject") then table.insert(pieces, visibleText(current)) end
		current = current.Parent
		count += 1
	end
	return table.concat(pieces, " ")
end

local function directModifier(root: Instance, className: string): Instance?
	for _, child in ipairs(root:GetChildren()) do
		if child.ClassName == className then return child end
	end
	return nil
end

local function isTrainingButton(button: GuiButton): boolean
	local combined = lower(button.Name .. " " .. visibleText(button) .. " " .. contextText(button, 3))
	return button:GetAttribute("SEVERTrainingLevelControl") == true
		or string.find(combined, "respawn dummy", 1, true) ~= nil
		or string.find(combined, "infinite health", 1, true) ~= nil
		or string.find(combined, "return to lobby", 1, true) ~= nil
		or string.find(combined, "dummy level", 1, true) ~= nil
end

local function findThemeButton(): GuiButton?
	local best: GuiButton? = nil
	local scoreBest = -math.huge
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and isTrainingButton(descendant) then
			local score = 10
			if string.find(lower(visibleText(descendant)), "respawn", 1, true) then score += 20 end
			if directModifier(descendant, "UICorner") then score += 4 end
			if directModifier(descendant, "UIStroke") then score += 4 end
			if directModifier(descendant, "UIGradient") then score += 4 end
			if score > scoreBest then best, scoreBest = descendant, score end
		end
	end
	return best
end

local function cloneModifier(template: Instance?, target: Instance, className: string)
	local old = directModifier(target, className)
	if old then old:Destroy() end
	if template then
		local source = directModifier(template, className)
		if source then source:Clone().Parent = target end
	end
end

local function applyTextTheme(root: Instance, template: GuiButton?)
	local source = template and firstText(template) or nil
	local function style(textObject: TextLabel | TextButton)
		if source then
			textObject.FontFace = source.FontFace
			textObject.TextColor3 = source.TextColor3
			textObject.TextStrokeColor3 = source.TextStrokeColor3
			textObject.TextStrokeTransparency = source.TextStrokeTransparency
		else
			textObject.TextColor3 = Color3.fromRGB(247, 247, 250)
			textObject.TextStrokeTransparency = 1
		end
	end
	if root:IsA("TextLabel") or root:IsA("TextButton") then style(root) end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then style(descendant) end
	end
end

local function ensureFallbackSurface(target: GuiObject)
	if not directModifier(target, "UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = target
	end
	if not directModifier(target, "UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(225, 225, 235)
		stroke.Thickness = 1.4
		stroke.Transparency = 0.34
		stroke.Parent = target
	end
end

local function applySurface(target: GuiObject, template: GuiButton?, strong: boolean?)
	if template then
		target.BackgroundColor3 = template.BackgroundColor3
		target.BackgroundTransparency = math.clamp(template.BackgroundTransparency + (strong and -0.04 or 0.02), 0, 0.8)
		cloneModifier(template, target, "UICorner")
		cloneModifier(template, target, "UIStroke")
		cloneModifier(template, target, "UIGradient")
	else
		target.BackgroundColor3 = Color3.fromRGB(20, 21, 28)
		target.BackgroundTransparency = strong and 0.06 or 0.14
		ensureFallbackSurface(target)
	end
	target.BorderSizePixel = 0
	applyTextTheme(target, template)
end

local function refreshMatchmaking(template: GuiButton?)
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton")
			and not isTrainingButton(descendant)
			and Policy.IsMatchmakingControl(descendant.Name, contextText(descendant, 3)) then
			applySurface(descendant, template, true)
			if template then descendant.AutoButtonColor = template.AutoButtonColor end
			if battleActive then
				if matchmakingSnapshots[descendant] == nil then matchmakingSnapshots[descendant] = descendant.Visible end
				descendant.Visible = false
			elseif matchmakingSnapshots[descendant] ~= nil then
				descendant.Visible = matchmakingSnapshots[descendant]
				matchmakingSnapshots[descendant] = nil
			end
		end
	end
end

local function refreshHealthContainers(template: GuiButton?)
	if not battleActive then return end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible then
			local name = lower(descendant.Name)
			if string.find(name, "playerdisplay", 1, true) or string.find(name, "opponentdisplay", 1, true) then
				applySurface(descendant, template, false)
			end
		end
	end
end

local function accentColor(template: GuiButton?): Color3
	if template then
		local stroke = template:FindFirstChildOfClass("UIStroke")
		if stroke then return stroke.Color end
	end
	return Color3.fromRGB(232, 232, 240)
end

local function makeText(parent: Instance, text: string, size: UDim2, position: UDim2, textSize: number, template: GuiButton?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Text = text
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	applyTextTheme(label, template)
	return label
end

local function loadHeadshot(image: ImageLabel, userId: number)
	if userId <= 0 then image.Visible = false return end
	task.spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
		end)
		if ok and image.Parent then image.Image = content end
	end)
end

local function makeCard(parent: Instance, fighterName: string, userId: number, leftSide: boolean, template: GuiButton?): Frame
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Size = UDim2.fromScale(0.31, 0.32)
	card.Position = leftSide and UDim2.fromScale(-0.18, 0.52) or UDim2.fromScale(1.18, 0.52)
	card.Parent = parent
	applySurface(card, template, true)

	local portrait = Instance.new("Frame")
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.fromScale(0.5, 0.07)
	portrait.Size = UDim2.fromScale(0.34, 0.48)
	portrait.Parent = card
	applySurface(portrait, template, false)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = portrait
	local portraitCorner = portrait:FindFirstChildOfClass("UICorner")
	if portraitCorner then portraitCorner.CornerRadius = UDim.new(1, 0) end

	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Parent = portrait
	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(1, 0)
	imageCorner.Parent = image
	loadHeadshot(image, userId)
	if userId <= 0 then
		local ai = makeText(portrait, "AI", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 34, template)
		ai.TextScaled = true
	end

	local tag = makeText(card, userId <= 0 and "TRAINING DUMMY" or (leftSide and "CHALLENGER" or "OPPONENT"), UDim2.fromScale(0.9, 0.11), UDim2.fromScale(0.05, 0.59), 12, template)
	tag.TextTransparency = 0.24
	local nameLabel = makeText(card, string.upper(fighterName), UDim2.fromScale(0.9, 0.19), UDim2.fromScale(0.05, 0.7), 24, template)
	nameLabel.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 13
	limit.MaxTextSize = 28
	limit.Parent = nameLabel
	return card
end

local function legacyName(name: string): boolean
	local n = lower(name)
	return string.find(n, "battleintro", 1, true) ~= nil
		or string.find(n, "battle intro", 1, true) ~= nil
		or string.find(n, "versus", 1, true) ~= nil
		or n == "vs"
end

local function suppressLegacyIntro()
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and child ~= introGui and legacyName(child.Name) then
			if legacyGuiSnapshots[child] == nil then legacyGuiSnapshots[child] = child.Enabled end
			child.Enabled = false
		end
	end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Visible and legacyName(descendant.Name) then
			if not introGui or not descendant:IsDescendantOf(introGui) then
				if legacyObjectSnapshots[descendant] == nil then legacyObjectSnapshots[descendant] = descendant.Visible end
				descendant.Visible = false
			end
		end
	end
end

local function restoreLegacyIntro()
	for gui, enabled in pairs(legacyGuiSnapshots) do
		if gui.Parent then gui.Enabled = enabled end
		legacyGuiSnapshots[gui] = nil
	end
	for gui, visible in pairs(legacyObjectSnapshots) do
		if gui.Parent then gui.Visible = visible end
		legacyObjectSnapshots[gui] = nil
	end
end

local function closeIntro(animated: boolean)
	introActive = false
	introToken += 1
	local gui = introGui
	introGui = nil
	if not gui then return end
	local root = gui:FindFirstChild("Root")
	if animated and root and root:IsA("Frame") then
		TweenService:Create(root, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
		task.delay(0.2, function() if gui.Parent then gui:Destroy() end end)
	else
		gui:Destroy()
	end
end

local function startIntro(data: any)
	closeIntro(false)
	introToken += 1
	local token = introToken
	introActive = true

	local p1 = type(data) == "table" and data.p1 or nil
	local p2 = type(data) == "table" and data.p2 or nil
	if type(p1) ~= "table" then p1 = {Name = player.Name, UserId = player.UserId} end
	if type(p2) ~= "table" then p2 = {Name = "Opponent", UserId = 0} end
	local left, right = p1, p2
	if tonumber(p2.UserId) == player.UserId then left, right = p2, p1 end

	local template = findThemeButton()
	local accent = accentColor(template)
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 700

	local gui = Instance.new("ScreenGui")
	gui.Name = "SEVER_BattleIntro"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	introGui = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(6, 6, 9)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(7, 7, 11)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 18, 24)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 8)),
	})
	gradient.Parent = root

	local title = makeText(root, "SEVER  //  DUEL", mobile and UDim2.fromScale(0.62, 0.055) or UDim2.fromScale(0.38, 0.055), mobile and UDim2.fromScale(0.19, 0.09) or UDim2.fromScale(0.31, 0.08), 16, template)
	title.TextScaled = true
	local titleLimit = Instance.new("UITextSizeConstraint")
	titleLimit.MinTextSize = 11
	titleLimit.MaxTextSize = 18
	titleLimit.Parent = title

	local leftCard = makeCard(root, tostring(left.Name or "PLAYER"), tonumber(left.UserId) or 0, true, template)
	local rightCard = makeCard(root, tostring(right.Name or "OPPONENT"), tonumber(right.UserId) or 0, false, template)
	if mobile then
		leftCard.Size = UDim2.fromScale(0.4, 0.3)
		rightCard.Size = UDim2.fromScale(0.4, 0.3)
	end

	local slash = Instance.new("Frame")
	slash.AnchorPoint = Vector2.new(0.5, 0.5)
	slash.Position = UDim2.fromScale(0.5, 0.52)
	slash.Size = UDim2.fromScale(0.006, 0.62)
	slash.Rotation = 14
	slash.BackgroundColor3 = accent
	slash.BackgroundTransparency = 1
	slash.BorderSizePixel = 0
	slash.Parent = root
	local slashCorner = Instance.new("UICorner")
	slashCorner.CornerRadius = UDim.new(1, 0)
	slashCorner.Parent = slash

	local vsShell = Instance.new("Frame")
	vsShell.AnchorPoint = Vector2.new(0.5, 0.5)
	vsShell.Position = UDim2.fromScale(0.5, 0.52)
	vsShell.Size = UDim2.fromOffset(18, 18)
	vsShell.Parent = root
	applySurface(vsShell, template, true)
	local vsAspect = Instance.new("UIAspectRatioConstraint")
	vsAspect.AspectRatio = 1
	vsAspect.Parent = vsShell
	local circle = vsShell:FindFirstChildOfClass("UICorner")
	if circle then circle.CornerRadius = UDim.new(1, 0) end
	local vs = makeText(vsShell, "VS", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 32, template)
	vs.TextScaled = true
	vs.TextStrokeTransparency = 0.55

	local footer = makeText(root, "ARENA LINK ESTABLISHED", UDim2.fromScale(0.38, 0.04), UDim2.fromScale(0.31, 0.89), 12, template)
	footer.TextTransparency = 0.3
	footer.TextScaled = true

	suppressLegacyIntro()
	TweenService:Create(root, TweenInfo.new(0.18), {BackgroundTransparency = 0.02}):Play()
	TweenService:Create(leftCard, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.27, 0.52)}):Play()
	TweenService:Create(rightCard, TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Position = UDim2.fromScale(0.73, 0.52)}):Play()
	TweenService:Create(vsShell, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = mobile and UDim2.fromOffset(58, 58) or UDim2.fromOffset(88, 88)}):Play()
	TweenService:Create(slash, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.14}):Play()

	task.spawn(function()
		while token == introToken and battleActive do
			suppressLegacyIntro()
			task.wait(0.08)
		end
	end)
end

local function refreshPresentation()
	local template = findThemeButton()
	refreshMatchmaking(template)
	refreshHealthContainers(template)
end

GameStateUpdate.OnClientEvent:Connect(function(state, data)
	if state == "BattleIntro" then
		battleActive = true
		startIntro(data)
	elseif Policy.IsBattleState(state) then
		battleActive = true
		if state == "Countdown" or state == "Fighting" or state == "MatchEnded" or state == "ReturningToLobby" then closeIntro(true) end
	elseif state == "Lobby" then
		battleActive = false
		closeIntro(false)
		restoreLegacyIntro()
	end
	task.defer(refreshPresentation)
end)

playerGui.DescendantAdded:Connect(function() task.defer(refreshPresentation) end)

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < 0.4 then return end
	accumulator = 0
	refreshPresentation()
end)

task.delay(1, refreshPresentation)
