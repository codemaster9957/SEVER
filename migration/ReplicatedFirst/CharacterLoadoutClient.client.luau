--!strict
-- Lobby-only Character / weapon loadout UI + battle slot input routing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local ScytheSystems = ReplicatedStorage:WaitForChild("ScytheSystems")
local LoadoutPolicy = require(ScytheSystems:WaitForChild("LoadoutPolicy"))
local loadoutRemotes = ScytheSystems:WaitForChild("Remotes"):WaitForChild("Loadout")
local EquipMove = loadoutRemotes:WaitForChild("EquipMove") :: RemoteEvent
local StateUpdate = loadoutRemotes:WaitForChild("StateUpdate") :: RemoteEvent
local UseMove = loadoutRemotes:WaitForChild("UseMove") :: RemoteEvent
local SoulReapRequest = ReplicatedStorage:WaitForChild("GrappleEvents"):WaitForChild("SoulReapRequest") :: RemoteEvent
local GameStateUpdate = ReplicatedStorage:WaitForChild("MatchEvents"):WaitForChild("GameStateUpdate") :: RemoteEvent

local ACCENT = Color3.fromRGB(226, 53, 72)
local ACCENT_DARK = Color3.fromRGB(126, 28, 42)
local PANEL = Color3.fromRGB(14, 15, 19)
local CARD = Color3.fromRGB(25, 27, 33)
local CARD_HOVER = Color3.fromRGB(34, 36, 43)
local BORDER = Color3.fromRGB(70, 73, 84)
local TEXT = Color3.fromRGB(244, 245, 248)
local MUTED = Color3.fromRGB(157, 162, 174)

local activeSlot = 1
local expanded = false
local serverCombatPhase = false
local nextLocalUse: {[string]: number} = {}
local slotButtons: {[number]: TextButton} = {}
local slotNameLabels: {[number]: TextLabel} = {}
local moveButtons: {[string]: TextButton} = {}

local oldGui = playerGui:FindFirstChild("CharacterLoadoutUI")
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "CharacterLoadoutUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 24
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "Root"
root.AnchorPoint = Vector2.new(1, 0.5)
root.Position = UDim2.new(1, -24, 0.5, 36)
root.Size = UDim2.fromOffset(286, 106)
root.BackgroundTransparency = 1
root.Parent = gui

local scale = Instance.new("UIScale")
scale.Parent = root

local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	scale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 650), 0.76, 1)
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(updateScale)

local weaponCard = Instance.new("TextButton")
weaponCard.Name = "WeaponCard"
weaponCard.AutoButtonColor = false
weaponCard.Text = ""
weaponCard.Size = UDim2.fromScale(1, 1)
weaponCard.BackgroundColor3 = CARD
weaponCard.BorderSizePixel = 0
weaponCard.Parent = root

local weaponCorner = Instance.new("UICorner")
weaponCorner.CornerRadius = UDim.new(0, 10)
weaponCorner.Parent = weaponCard
local weaponStroke = Instance.new("UIStroke")
weaponStroke.Color = BORDER
weaponStroke.Thickness = 1
weaponStroke.Transparency = 0.15
weaponStroke.Parent = weaponCard

local accentBar = Instance.new("Frame")
accentBar.Size = UDim2.new(0, 4, 1, -18)
accentBar.Position = UDim2.fromOffset(9, 9)
accentBar.BackgroundColor3 = ACCENT
accentBar.BorderSizePixel = 0
accentBar.Parent = weaponCard
local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(1, 0)
accentCorner.Parent = accentBar

local eyebrow = Instance.new("TextLabel")
eyebrow.BackgroundTransparency = 1
eyebrow.Position = UDim2.fromOffset(25, 13)
eyebrow.Size = UDim2.new(1, -58, 0, 16)
eyebrow.Font = Enum.Font.GothamBold
eyebrow.Text = "CURRENT WEAPON"
eyebrow.TextColor3 = MUTED
eyebrow.TextSize = 10
eyebrow.TextXAlignment = Enum.TextXAlignment.Left
eyebrow.Parent = weaponCard

local weaponName = Instance.new("TextLabel")
weaponName.BackgroundTransparency = 1
weaponName.Position = UDim2.fromOffset(25, 29)
weaponName.Size = UDim2.new(1, -66, 0, 29)
weaponName.Font = Enum.Font.GothamBlack
weaponName.Text = "SCYTHE"
weaponName.TextColor3 = TEXT
weaponName.TextSize = 23
weaponName.TextXAlignment = Enum.TextXAlignment.Left
weaponName.Parent = weaponCard

local summary = Instance.new("TextLabel")
summary.BackgroundTransparency = 1
summary.Position = UDim2.fromOffset(25, 66)
summary.Size = UDim2.new(1, -50, 0, 24)
summary.Font = Enum.Font.GothamMedium
summary.TextColor3 = MUTED
summary.TextSize = 11
summary.TextXAlignment = Enum.TextXAlignment.Left
summary.TextTruncate = Enum.TextTruncate.AtEnd
summary.Parent = weaponCard

local expandMark = Instance.new("TextLabel")
expandMark.BackgroundTransparency = 1
expandMark.AnchorPoint = Vector2.new(1, 0.5)
expandMark.Position = UDim2.new(1, -17, 0.5, 0)
expandMark.Size = UDim2.fromOffset(22, 28)
expandMark.Font = Enum.Font.GothamBold
expandMark.Text = ">"
expandMark.TextColor3 = MUTED
expandMark.TextSize = 18
expandMark.Parent = weaponCard

local panel = Instance.new("Frame")
panel.Name = "MovePanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(0, -12, 0.5, 0)
panel.Size = UDim2.fromOffset(376, 326)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = root
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = BORDER
panelStroke.Thickness = 1
panelStroke.Transparency = 0.12
panelStroke.Parent = panel

local panelTitle = Instance.new("TextLabel")
panelTitle.BackgroundTransparency = 1
panelTitle.Position = UDim2.fromOffset(18, 14)
panelTitle.Size = UDim2.new(1, -36, 0, 24)
panelTitle.Font = Enum.Font.GothamBlack
panelTitle.Text = "SCYTHE LOADOUT"
panelTitle.TextColor3 = TEXT
panelTitle.TextSize = 18
panelTitle.TextXAlignment = Enum.TextXAlignment.Left
panelTitle.Parent = panel

local panelHint = Instance.new("TextLabel")
panelHint.BackgroundTransparency = 1
panelHint.Position = UDim2.fromOffset(18, 39)
panelHint.Size = UDim2.new(1, -36, 0, 18)
panelHint.Font = Enum.Font.Gotham
panelHint.Text = "Select a slot, then choose the move you want equipped."
panelHint.TextColor3 = MUTED
panelHint.TextSize = 10
panelHint.TextXAlignment = Enum.TextXAlignment.Left
panelHint.Parent = panel

local function makeSlot(index: number, x: number, keyLabel: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.AutoButtonColor = false
	button.Text = ""
	button.Position = UDim2.fromOffset(x, 69)
	button.Size = UDim2.fromOffset(164, 72)
	button.BackgroundColor3 = CARD
	button.BorderSizePixel = 0
	button.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Name = "SelectionStroke"
	stroke.Color = BORDER
	stroke.Thickness = 1
	stroke.Parent = button

	local slotLabel = Instance.new("TextLabel")
	slotLabel.BackgroundTransparency = 1
	slotLabel.Position = UDim2.fromOffset(12, 8)
	slotLabel.Size = UDim2.new(1, -55, 0, 16)
	slotLabel.Font = Enum.Font.GothamBold
	slotLabel.Text = "SLOT " .. index
	slotLabel.TextColor3 = MUTED
	slotLabel.TextSize = 10
	slotLabel.TextXAlignment = Enum.TextXAlignment.Left
	slotLabel.Parent = button

	local key = Instance.new("TextLabel")
	key.AnchorPoint = Vector2.new(1, 0)
	key.Position = UDim2.new(1, -9, 0, 8)
	key.Size = UDim2.fromOffset(43, 18)
	key.BackgroundColor3 = Color3.fromRGB(39, 41, 49)
	key.BorderSizePixel = 0
	key.Font = Enum.Font.GothamBold
	key.Text = keyLabel
	key.TextColor3 = TEXT
	key.TextSize = 9
	key.Parent = button
	local keyCorner = Instance.new("UICorner")
	keyCorner.CornerRadius = UDim.new(0, 5)
	keyCorner.Parent = key

	local moveName = Instance.new("TextLabel")
	moveName.Name = "MoveName"
	moveName.BackgroundTransparency = 1
	moveName.Position = UDim2.fromOffset(12, 31)
	moveName.Size = UDim2.new(1, -24, 0, 29)
	moveName.Font = Enum.Font.GothamBold
	moveName.Text = "-"
	moveName.TextColor3 = TEXT
	moveName.TextSize = 13
	moveName.TextWrapped = true
	moveName.TextXAlignment = Enum.TextXAlignment.Left
	moveName.Parent = button

	slotButtons[index] = button
	slotNameLabels[index] = moveName
	return button
end

makeSlot(1, 18, "Z / 1")
makeSlot(2, 194, "X / 2")

local chooseLabel = Instance.new("TextLabel")
chooseLabel.BackgroundTransparency = 1
chooseLabel.Position = UDim2.fromOffset(18, 156)
chooseLabel.Size = UDim2.new(1, -36, 0, 18)
chooseLabel.Font = Enum.Font.GothamBold
chooseLabel.Text = "CHOOSE MOVE FOR SLOT 1"
chooseLabel.TextColor3 = MUTED
chooseLabel.TextSize = 10
chooseLabel.TextXAlignment = Enum.TextXAlignment.Left
chooseLabel.Parent = panel

local moveList = Instance.new("Frame")
moveList.BackgroundTransparency = 1
moveList.Position = UDim2.fromOffset(18, 180)
moveList.Size = UDim2.new(1, -36, 0, 126)
moveList.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = moveList

for order, moveId in ipairs(LoadoutPolicy.MoveOrder) do
	local data = LoadoutPolicy.GetMove(moveId)
	local button = Instance.new("TextButton")
	button.Name = moveId
	button.AutoButtonColor = false
	button.Text = ""
	button.Size = UDim2.new(1, 0, 0, 38)
	button.BackgroundColor3 = CARD
	button.BorderSizePixel = 0
	button.LayoutOrder = order
	button.Parent = moveList
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Name = "EquippedStroke"
	stroke.Color = BORDER
	stroke.Thickness = 1
	stroke.Transparency = 0.3
	stroke.Parent = button

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(12, 0)
	title.Size = UDim2.new(1, -92, 1, 0)
	title.Font = Enum.Font.GothamBold
	title.Text = data and string.upper(data.Name) or string.upper(moveId)
	title.TextColor3 = TEXT
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = button

	local cooldown = Instance.new("TextLabel")
	cooldown.AnchorPoint = Vector2.new(1, 0.5)
	cooldown.Position = UDim2.new(1, -10, 0.5, 0)
	cooldown.Size = UDim2.fromOffset(70, 20)
	cooldown.BackgroundTransparency = 1
	cooldown.Font = Enum.Font.GothamMedium
	cooldown.Text = data and (tostring(data.Cooldown) .. "s CD") or ""
	cooldown.TextColor3 = MUTED
	cooldown.TextSize = 9
	cooldown.TextXAlignment = Enum.TextXAlignment.Right
	cooldown.Parent = button

	moveButtons[moveId] = button
end

local function getSlots(): {string}
	return LoadoutPolicy.Sanitize(player:GetAttribute("EquippedMove1"), player:GetAttribute("EquippedMove2"))
end

local function moveDisplay(moveId: string): string
	local data = LoadoutPolicy.GetMove(moveId)
	return data and data.Name or moveId
end

local function refreshSelection()
	local slots = getSlots()
	for index = 1, 2 do
		local selected = index == activeSlot
		local button = slotButtons[index]
		local stroke = button:FindFirstChild("SelectionStroke") :: UIStroke?
		button.BackgroundColor3 = selected and Color3.fromRGB(35, 29, 34) or CARD
		if stroke then
			stroke.Color = selected and ACCENT or BORDER
			stroke.Thickness = selected and 2 or 1
		end
		slotNameLabels[index].Text = string.upper(moveDisplay(slots[index]))
	end
	chooseLabel.Text = "CHOOSE MOVE FOR SLOT " .. activeSlot
	for moveId, button in pairs(moveButtons) do
		local stroke = button:FindFirstChild("EquippedStroke") :: UIStroke?
		local equippedSlot = if slots[1] == moveId then 1 elseif slots[2] == moveId then 2 else nil
		button.BackgroundColor3 = equippedSlot and Color3.fromRGB(34, 29, 34) or CARD
		if stroke then
			stroke.Color = equippedSlot and ACCENT or BORDER
			stroke.Transparency = equippedSlot and 0 or 0.3
		end
	end
	summary.Text = string.format("Z  %s     X  %s", string.upper(moveDisplay(slots[1])), string.upper(moveDisplay(slots[2])))
end

local function setExpanded(value: boolean)
	expanded = value
	panel.Visible = expanded
	expandMark.Text = expanded and "<" or ">"
	weaponStroke.Color = expanded and ACCENT or BORDER
end

local function characterInMatch(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("InMatch") == true
end

local function refreshVisibility()
	local inLobby = not characterInMatch() and not serverCombatPhase
	gui.Enabled = inLobby
	if not inLobby then
		setExpanded(false)
	end
end

weaponCard.MouseButton1Click:Connect(function()
	if gui.Enabled then setExpanded(not expanded) end
end)
weaponCard.MouseEnter:Connect(function()
	if not expanded then weaponCard.BackgroundColor3 = CARD_HOVER end
end)
weaponCard.MouseLeave:Connect(function()
	weaponCard.BackgroundColor3 = CARD
end)

for index, button in pairs(slotButtons) do
	button.MouseButton1Click:Connect(function()
		activeSlot = index
		refreshSelection()
	end)
end

for moveId, button in pairs(moveButtons) do
	button.MouseButton1Click:Connect(function()
		if not gui.Enabled then return end
		EquipMove:FireServer(activeSlot, moveId)
	end)
	button.MouseEnter:Connect(function()
		if not LoadoutPolicy.IsEquipped(getSlots(), moveId) then
			button.BackgroundColor3 = CARD_HOVER
		end
	end)
	button.MouseLeave:Connect(refreshSelection)
end

StateUpdate.OnClientEvent:Connect(function(state)
	if type(state) == "table" and type(state.Slots) == "table" then
		if type(state.Slots[1]) == "string" then player:SetAttribute("EquippedMove1", state.Slots[1]) end
		if type(state.Slots[2]) == "string" then player:SetAttribute("EquippedMove2", state.Slots[2]) end
	end
	refreshSelection()
end)

player:GetAttributeChangedSignal("EquippedMove1"):Connect(refreshSelection)
player:GetAttributeChangedSignal("EquippedMove2"):Connect(refreshSelection)

local NON_COMBAT_STATES = {
	Lobby = true,
	UpdateHealth = false,
	UpdateTimer = false,
	UpdateWinstreak = false,
}
GameStateUpdate.OnClientEvent:Connect(function(stateName)
	if type(stateName) ~= "string" then return end
	if stateName == "Lobby" then
		serverCombatPhase = false
	elseif NON_COMBAT_STATES[stateName] == nil then
		-- LoadingArena / BattleIntro / Countdown / Fighting / overtime/result phases
		-- all keep the character editor hidden until the explicit Lobby state returns.
		serverCombatPhase = true
	end
	refreshVisibility()
end)

local characterAttributeConnection: RBXScriptConnection? = nil
local function watchCharacter(character: Model)
	if characterAttributeConnection then characterAttributeConnection:Disconnect() end
	characterAttributeConnection = character:GetAttributeChangedSignal("InMatch"):Connect(refreshVisibility)
	refreshVisibility()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) else refreshVisibility() end

local LEGACY_LOCAL_MOVE_SCRIPTS = {
	spinclient = true,
	throw = true,
	throwclient = true,
	throwingclient = true,
}
local function suppressLegacyToolInput(instance: Instance)
	if not instance:IsA("LocalScript") then return end
	local ancestor = instance.Parent
	local underTool = false
	while ancestor do
		if ancestor:IsA("Tool") then underTool = true break end
		ancestor = ancestor.Parent
	end
	if not underTool then return end
	local normalized = string.lower(string.gsub(instance.Name, "%s+", ""))
	if LEGACY_LOCAL_MOVE_SCRIPTS[normalized] then
		instance.Disabled = true
	end
end
local function scanLegacy(container: Instance)
	for _, descendant in ipairs(container:GetDescendants()) do suppressLegacyToolInput(descendant) end
	container.DescendantAdded:Connect(suppressLegacyToolInput)
end
scanLegacy(player:WaitForChild("Backpack"))
player.CharacterAdded:Connect(scanLegacy)
if player.Character then scanLegacy(player.Character) end

local function playMoveAnimation(moveId: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animationId = if moveId == "spin" then "rbxassetid://89608736085843" elseif moveId == "scythe_throw" then "rbxassetid://95546671624902" else nil
	if not animationId then return end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	animation:Destroy()
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(0.08)
	end
end

local function useSlot(slotIndex: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or character:GetAttribute("InMatch") ~= true or character:GetAttribute("CanAttack") == false then return end
	if not humanoid or humanoid.Health <= 0 then return end
	local slots = getSlots()
	local moveId = slots[slotIndex]
	local move = LoadoutPolicy.GetMove(moveId)
	if not move then return end
	local now = os.clock()
	if now < (nextLocalUse[moveId] or 0) then return end
	nextLocalUse[moveId] = now + move.Cooldown
	if moveId == "soul_reap" then
		SoulReapRequest:FireServer(slotIndex)
	else
		playMoveAnimation(moveId)
		UseMove:FireServer(slotIndex)
	end
end

local function slotAction1(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then useSlot(1) end
	return characterInMatch() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end
local function slotAction2(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then useSlot(2) end
	return characterInMatch() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end
ContextActionService:BindActionAtPriority("SEVER_LoadoutSlot1", slotAction1, false, 3000, Enum.KeyCode.Z, Enum.KeyCode.One)
ContextActionService:BindActionAtPriority("SEVER_LoadoutSlot2", slotAction2, false, 3000, Enum.KeyCode.X, Enum.KeyCode.Two)

local function makeSpinFX(userId: number, duration: number)
	local target = Players:GetPlayerByUserId(userId)
	local character = target and target.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then return end
	local highlight = Instance.new("Highlight")
	highlight.Name = "LoadoutSpinFX"
	highlight.FillColor = ACCENT
	highlight.FillTransparency = 0.62
	highlight.OutlineColor = Color3.fromRGB(255, 214, 220)
	highlight.OutlineTransparency = 0.12
	highlight.Parent = character
	Debris:AddItem(highlight, duration)
	for i = 1, 3 do
		local ring = Instance.new("Part")
		ring.Name = "LoadoutSpinRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = ACCENT
		ring.Transparency = 0.25 + i * 0.12
		ring.Anchored = false
		ring.CanCollide = false
		ring.CanTouch = false
		ring.CanQuery = false
		ring.Size = Vector3.new(0.06, 7 + i * 1.5, 7 + i * 1.5)
		ring.CFrame = rootPart.CFrame * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = ring
		weld.Part1 = rootPart
		weld.Parent = ring
		Debris:AddItem(ring, math.min(duration, 0.7 + i * 0.12))
	end
end

local function makeThrowFX(origin: Vector3, direction: Vector3, range: number)
	local blade = Instance.new("Part")
	blade.Name = "LoadoutThrowFX"
	blade.Material = Enum.Material.Neon
	blade.Color = ACCENT
	blade.Anchored = true
	blade.CanCollide = false
	blade.CanTouch = false
	blade.CanQuery = false
	blade.Size = Vector3.new(0.28, 4.5, 1.1)
	blade.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.Angles(0, math.rad(90), math.rad(32))
	blade.Parent = workspace
	local tween = TweenService:Create(blade, TweenInfo.new(0.38, Enum.EasingStyle.Linear), {
		CFrame = blade.CFrame + direction * range,
		Transparency = 0.3,
	})
	tween:Play()
	Debris:AddItem(blade, 0.45)
end

UseMove.OnClientEvent:Connect(function(kind, moveId, userId, a, b, c)
	if kind ~= "FX" or type(moveId) ~= "string" or type(userId) ~= "number" then return end
	if moveId == "spin" and type(a) == "number" then
		makeSpinFX(userId, a)
	elseif moveId == "scythe_throw" and typeof(a) == "Vector3" and typeof(b) == "Vector3" and type(c) == "number" then
		makeThrowFX(a, b, c)
	end
end)

refreshSelection()
refreshVisibility()
