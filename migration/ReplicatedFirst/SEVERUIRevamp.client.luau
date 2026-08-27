--!strict
-- Lightweight SEVER presentation layer.
-- Event-driven only: no heartbeat polling, no avatar thumbnail requests, no heavy intro tree.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GameStateUpdate = ReplicatedStorage:WaitForChild("MatchEvents"):WaitForChild("GameStateUpdate")
local Policy = require(script.Parent:WaitForChild("UIUnifierPolicy"))

local battleActive = false
local introGui: ScreenGui? = nil
local introToken = 0
local cachedThemeButton: GuiButton? = nil
local matchmakingSnapshots: {[GuiObject]: boolean} = setmetatable({}, {__mode = "k"})

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
	local object = firstText(root)
	return object and object.Text or ""
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

local function isTrainingButton(button: GuiButton): boolean
	local combined = lower(button.Name .. " " .. visibleText(button) .. " " .. contextText(button, 3))
	return button:GetAttribute("SEVERTrainingLevelControl") == true
		or string.find(combined, "respawn dummy", 1, true) ~= nil
		or string.find(combined, "infinite health", 1, true) ~= nil
		or string.find(combined, "return to lobby", 1, true) ~= nil
		or string.find(combined, "dummy level", 1, true) ~= nil
end

local function findThemeButton(): GuiButton?
	if cachedThemeButton and cachedThemeButton.Parent then
		return cachedThemeButton
	end

	local best: GuiButton? = nil
	local bestScore = -math.huge
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") and isTrainingButton(descendant) then
			local score = 10
			if string.find(lower(visibleText(descendant)), "respawn", 1, true) then score += 20 end
			if directModifier(descendant, "UICorner") then score += 3 end
			if directModifier(descendant, "UIStroke") then score += 3 end
			if directModifier(descendant, "UIGradient") then score += 2 end
			if score > bestScore then
				best = descendant
				bestScore = score
			end
		end
	end

	cachedThemeButton = best
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
			textObject.TextColor3 = Color3.fromRGB(245, 245, 248)
			textObject.TextStrokeTransparency = 1
		end
	end

	if root:IsA("TextLabel") or root:IsA("TextButton") then style(root) end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			style(descendant)
		end
	end
end

local function ensureFallbackSurface(target: GuiObject)
	if not directModifier(target, "UICorner") then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = target
	end
	if not directModifier(target, "UIStroke") then
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(225, 225, 232)
		stroke.Thickness = 1.25
		stroke.Transparency = 0.38
		stroke.Parent = target
	end
end

local function applySurface(target: GuiObject, template: GuiButton?, strong: boolean?)
	if template then
		target.BackgroundColor3 = template.BackgroundColor3
		target.BackgroundTransparency = math.clamp(template.BackgroundTransparency + (strong and -0.03 or 0.02), 0, 0.8)
		cloneModifier(template, target, "UICorner")
		cloneModifier(template, target, "UIStroke")
		cloneModifier(template, target, "UIGradient")
	else
		target.BackgroundColor3 = Color3.fromRGB(18, 19, 24)
		target.BackgroundTransparency = strong and 0.07 or 0.14
		ensureFallbackSurface(target)
	end
	target.BorderSizePixel = 0
	applyTextTheme(target, template)
end

local function isMatchmakingButton(button: GuiButton): boolean
	return not isTrainingButton(button)
		and Policy.IsMatchmakingControl(button.Name, contextText(button, 3))
end

local function styleMatchmakingButton(button: GuiButton)
	if not isMatchmakingButton(button) then return end
	local template = findThemeButton()
	applySurface(button, template, true)
	if template then button.AutoButtonColor = template.AutoButtonColor end

	if battleActive then
		if matchmakingSnapshots[button] == nil then
			matchmakingSnapshots[button] = button.Visible
		end
		button.Visible = false
	elseif matchmakingSnapshots[button] ~= nil then
		button.Visible = matchmakingSnapshots[button]
		matchmakingSnapshots[button] = nil
	end
end

local function refreshMatchmaking()
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			styleMatchmakingButton(descendant)
		end
	end
end

local function styleHealthContainer(gui: GuiObject)
	local name = lower(gui.Name)
	local isPlayer = string.find(name, "playerdisplay", 1, true) ~= nil
	local isOpponent = string.find(name, "opponentdisplay", 1, true) ~= nil
	if not isPlayer and not isOpponent then return end

	applySurface(gui, findThemeButton(), false)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local mobile = viewport.X < 700
	local inset = GuiService:GetGuiInset()
	local width = math.floor(math.clamp(viewport.X * (mobile and 0.39 or 0.26), mobile and 145 or 220, mobile and 185 or 330))
	local height = mobile and 52 or 64
	local edge = mobile and 10 or 18
	local top = inset.Y + (mobile and 8 or 12)

	gui.AutomaticSize = Enum.AutomaticSize.None
	gui.Size = UDim2.fromOffset(width, height)
	gui.AnchorPoint = isPlayer and Vector2.new(0, 0) or Vector2.new(1, 0)
	gui.Position = isPlayer and UDim2.fromOffset(edge, top) or UDim2.new(1, -edge, 0, top)
end

local function refreshHealth()
	if not battleActive then return end
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			styleHealthContainer(descendant)
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

local function makeIntroText(parent: Instance, text: string, position: UDim2, size: UDim2, alignment: Enum.TextXAlignment, template: GuiButton?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = false
	label.TextXAlignment = alignment
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTransparency = 1
	label.Parent = parent
	applyTextTheme(label, template)

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 14
	constraint.MaxTextSize = 38
	constraint.Parent = label
	return label
end

local function closeIntro(animated: boolean)
	introToken += 1
	local gui = introGui
	introGui = nil
	if not gui or not gui.Parent then return end

	if not animated then
		gui:Destroy()
		return
	end

	local root = gui:FindFirstChild("Root")
	if root and root:IsA("Frame") then
		TweenService:Create(root, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 1,
		}):Play()
	end
	for _, child in ipairs(gui:GetDescendants()) do
		if child:IsA("TextLabel") then
			TweenService:Create(child, TweenInfo.new(0.12), {TextTransparency = 1}):Play()
		elseif child:IsA("Frame") and child.Name == "Cut" then
			TweenService:Create(child, TweenInfo.new(0.12), {BackgroundTransparency = 1}):Play()
		end
	end
	task.delay(0.16, function()
		if gui.Parent then gui:Destroy() end
	end)
end

local function startIntro(data: any)
	closeIntro(false)
	introToken += 1
	local token = introToken

	local p1 = type(data) == "table" and data.p1 or nil
	local p2 = type(data) == "table" and data.p2 or nil
	if type(p1) ~= "table" then p1 = {Name = player.Name, UserId = player.UserId} end
	if type(p2) ~= "table" then p2 = {Name = "Opponent", UserId = 0} end

	local left, right = p1, p2
	if tonumber(p2.UserId) == player.UserId then
		left, right = p2, p1
	end

	local template = findThemeButton()
	local accent = accentColor(template)

	local gui = Instance.new("ScreenGui")
	gui.Name = "SEVER_LightBattleIntro"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 2000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	introGui = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = gui

	local header = makeIntroText(root, "SEVER  //  DUEL", UDim2.fromScale(0.35, 0.14), UDim2.fromScale(0.3, 0.06), Enum.TextXAlignment.Center, template)
	local leftName = makeIntroText(root, string.upper(tostring(left.Name or "PLAYER")), UDim2.fromScale(-0.03, 0.42), UDim2.fromScale(0.43, 0.13), Enum.TextXAlignment.Right, template)
	local rightName = makeIntroText(root, string.upper(tostring(right.Name or "OPPONENT")), UDim2.fromScale(0.60, 0.42), UDim2.fromScale(0.43, 0.13), Enum.TextXAlignment.Left, template)
	local vs = makeIntroText(root, "VS", UDim2.fromScale(0.455, 0.445), UDim2.fromScale(0.09, 0.08), Enum.TextXAlignment.Center, template)

	local cut = Instance.new("Frame")
	cut.Name = "Cut"
	cut.AnchorPoint = Vector2.new(0.5, 0.5)
	cut.Position = UDim2.fromScale(0.5, 0.5)
	cut.Size = UDim2.fromScale(0.0035, 0.48)
	cut.Rotation = 17
	cut.BackgroundColor3 = accent
	cut.BackgroundTransparency = 1
	cut.BorderSizePixel = 0
	cut.Parent = root

	TweenService:Create(root, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.04,
	}):Play()
	TweenService:Create(header, TweenInfo.new(0.16), {TextTransparency = 0.28}):Play()
	TweenService:Create(vs, TweenInfo.new(0.16), {TextTransparency = 0}):Play()
	TweenService:Create(cut, TweenInfo.new(0.18), {BackgroundTransparency = 0.08}):Play()
	TweenService:Create(leftName, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.04, 0.42),
		TextTransparency = 0,
	}):Play()
	TweenService:Create(rightName, TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0.53, 0.42),
		TextTransparency = 0,
	}):Play()

	-- Safety fallback only. Normally Countdown/Fighting closes the intro first.
	task.delay(4.25, function()
		if token == introToken and introGui == gui then
			closeIntro(true)
		end
	end)
end

local function handleState(state: string, data: any)
	if Policy.IsBattleState(state) then
		battleActive = true
	elseif state == "Lobby" then
		battleActive = false
	end

	if state == "BattleIntro" then
		startIntro(data)
	elseif state == "Countdown" or state == "Fighting" or state == "Lobby" or state == "ReturningToLobby" then
		closeIntro(true)
	end

	refreshMatchmaking()
	if battleActive then refreshHealth() end
end

GameStateUpdate.OnClientEvent:Connect(handleState)

playerGui.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("GuiButton") then
		if isTrainingButton(descendant) then
			cachedThemeButton = nil
			task.defer(refreshMatchmaking)
		else
			task.defer(styleMatchmakingButton, descendant)
		end
	elseif descendant:IsA("GuiObject") and battleActive then
		task.defer(styleHealthContainer, descendant)
	end
end)

local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if battleActive then task.defer(refreshHealth) end
	end)
end

-- One mount-time pass only. No recurring scans.
task.delay(0.8, function()
	cachedThemeButton = nil
	refreshMatchmaking()
	if battleActive then refreshHealth() end
end)
