--!strict
-- Lobby-only Character / weapon loadout UI plus battle slot input routing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local systems = ReplicatedStorage:WaitForChild("ScytheSystems")
local LoadoutPolicy = require(systems:WaitForChild("LoadoutPolicy"))
local remotes = systems:WaitForChild("Remotes"):WaitForChild("Loadout")
local EquipMove = remotes:WaitForChild("EquipMove") :: RemoteEvent
local StateUpdate = remotes:WaitForChild("StateUpdate") :: RemoteEvent
local UseMove = remotes:WaitForChild("UseMove") :: RemoteEvent
local SoulReapRequest = ReplicatedStorage:WaitForChild("GrappleEvents"):WaitForChild("SoulReapRequest") :: RemoteEvent

local ACCENT = Color3.fromRGB(226, 53, 72)
local PANEL = Color3.fromRGB(14, 15, 19)
local CARD = Color3.fromRGB(25, 27, 33)
local CARD_SELECTED = Color3.fromRGB(38, 29, 35)
local BORDER = Color3.fromRGB(70, 73, 84)
local TEXT = Color3.fromRGB(244, 245, 248)
local MUTED = Color3.fromRGB(157, 162, 174)

local activeSlot = 1
local expanded = false
local nextLocalUse: {[string]: number} = {}
local slotButtons: {[number]: TextButton} = {}
local slotNames: {[number]: TextLabel} = {}
local moveButtons: {[string]: TextButton} = {}

local previous = playerGui:FindFirstChild("CharacterLoadoutUI")
if previous then previous:Destroy() end

local function corner(parent: Instance, radius: number)
	local value = Instance.new("UICorner")
	value.CornerRadius = UDim.new(0, radius)
	value.Parent = parent
end

local function stroke(parent: Instance, name: string?): UIStroke
	local value = Instance.new("UIStroke")
	value.Name = name or "UIStroke"
	value.Color = BORDER
	value.Thickness = 1
	value.Transparency = 0.15
	value.Parent = parent
	return value
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, font: Enum.Font, textSize: number, color: Color3): TextLabel
	local value = Instance.new("TextLabel")
	value.BackgroundTransparency = 1
	value.Position = position
	value.Size = size
	value.Font = font
	value.Text = text
	value.TextColor3 = color
	value.TextSize = textSize
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.Parent = parent
	return value
end

local gui = Instance.new("ScreenGui")
gui.Name = "CharacterLoadoutUI"
gui.ResetOnSpawn = false
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

local uiScale = Instance.new("UIScale")
uiScale.Parent = root
local function updateScale()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	uiScale.Scale = math.clamp(math.min(viewport.X / 1100, viewport.Y / 650), 0.76, 1)
end
updateScale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

local weaponCard = Instance.new("TextButton")
weaponCard.Name = "WeaponCard"
weaponCard.AutoButtonColor = false
weaponCard.Text = ""
weaponCard.Size = UDim2.fromScale(1, 1)
weaponCard.BackgroundColor3 = CARD
weaponCard.BorderSizePixel = 0
weaponCard.Parent = root
corner(weaponCard, 10)
local weaponStroke = stroke(weaponCard, "WeaponStroke")

local accent = Instance.new("Frame")
accent.Position = UDim2.fromOffset(9, 9)
accent.Size = UDim2.new(0, 4, 1, -18)
accent.BackgroundColor3 = ACCENT
accent.BorderSizePixel = 0
accent.Parent = weaponCard
corner(accent, 4)

label(weaponCard, "CURRENT WEAPON", UDim2.fromOffset(25, 13), UDim2.new(1, -60, 0, 16), Enum.Font.GothamBold, 10, MUTED)
label(weaponCard, "SCYTHE", UDim2.fromOffset(25, 29), UDim2.new(1, -66, 0, 29), Enum.Font.GothamBlack, 23, TEXT)
local summary = label(weaponCard, "", UDim2.fromOffset(25, 66), UDim2.new(1, -50, 0, 24), Enum.Font.GothamMedium, 10, MUTED)
summary.TextTruncate = Enum.TextTruncate.AtEnd
local expandMark = label(weaponCard, ">", UDim2.new(1, -32, 0.5, -14), UDim2.fromOffset(22, 28), Enum.Font.GothamBold, 18, MUTED)
expandMark.TextXAlignment = Enum.TextXAlignment.Center

local panel = Instance.new("Frame")
panel.Name = "MovePanel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(0, -12, 0.5, 0)
panel.Size = UDim2.fromOffset(376, 326)
panel.BackgroundColor3 = PANEL
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = root
corner(panel, 12)
stroke(panel)
label(panel, "SCYTHE LOADOUT", UDim2.fromOffset(18, 14), UDim2.new(1, -36, 0, 24), Enum.Font.GothamBlack, 18, TEXT)
label(panel, "Select a slot, then choose one of your two battle moves.", UDim2.fromOffset(18, 39), UDim2.new(1, -36, 0, 18), Enum.Font.Gotham, 10, MUTED)

local function makeSlot(index: number, x: number, keyText: string)
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. index
	button.AutoButtonColor = false
	button.Text = ""
	button.Position = UDim2.fromOffset(x, 69)
	button.Size = UDim2.fromOffset(164, 72)
	button.BackgroundColor3 = CARD
	button.BorderSizePixel = 0
	button.Parent = panel
	corner(button, 8)
	stroke(button, "SelectionStroke")
	label(button, "SLOT " .. index, UDim2.fromOffset(12, 8), UDim2.new(1, -58, 0, 16), Enum.Font.GothamBold, 10, MUTED)
	local key = label(button, keyText, UDim2.new(1, -53, 0, 8), UDim2.fromOffset(43, 18), Enum.Font.GothamBold, 9, TEXT)
	key.BackgroundTransparency = 0
	key.BackgroundColor3 = Color3.fromRGB(39, 41, 49)
	key.TextXAlignment = Enum.TextXAlignment.Center
	corner(key, 5)
	local moveName = label(button, "-", UDim2.fromOffset(12, 31), UDim2.new(1, -24, 0, 29), Enum.Font.GothamBold, 13, TEXT)
	moveName.TextWrapped = true
	slotButtons[index] = button
	slotNames[index] = moveName
end
makeSlot(1, 18, "Z / 1")
makeSlot(2, 194, "X / 2")

local chooseLabel = label(panel, "CHOOSE MOVE FOR SLOT 1", UDim2.fromOffset(18, 156), UDim2.new(1, -36, 0, 18), Enum.Font.GothamBold, 10, MUTED)
local moveList = Instance.new("Frame")
moveList.BackgroundTransparency = 1
moveList.Position = UDim2.fromOffset(18, 180)
moveList.Size = UDim2.new(1, -36, 0, 126)
moveList.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = moveList

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
	corner(button, 7)
	stroke(button, "EquippedStroke")
	label(button, data and string.upper(data.Name) or string.upper(moveId), UDim2.fromOffset(12, 0), UDim2.new(1, -92, 1, 0), Enum.Font.GothamBold, 11, TEXT)
	local cd = label(button, data and (tostring(data.Cooldown) .. "s CD") or "", UDim2.new(1, -80, 0, 0), UDim2.fromOffset(70, 38), Enum.Font.GothamMedium, 9, MUTED)
	cd.TextXAlignment = Enum.TextXAlignment.Right
	moveButtons[moveId] = button
end

local function slots(): {string}
	return LoadoutPolicy.Sanitize(player:GetAttribute("EquippedMove1"), player:GetAttribute("EquippedMove2"))
end

local function moveName(moveId: string): string
	local data = LoadoutPolicy.GetMove(moveId)
	return data and data.Name or moveId
end

local function refresh()
	local equipped = slots()
	for i = 1, 2 do
		local selected = i == activeSlot
		local button = slotButtons[i]
		local selectionStroke = button:FindFirstChild("SelectionStroke") :: UIStroke?
		button.BackgroundColor3 = selected and CARD_SELECTED or CARD
		if selectionStroke then
			selectionStroke.Color = selected and ACCENT or BORDER
			selectionStroke.Thickness = selected and 2 or 1
		end
		slotNames[i].Text = string.upper(moveName(equipped[i]))
	end
	chooseLabel.Text = "CHOOSE MOVE FOR SLOT " .. activeSlot
	for moveId, button in pairs(moveButtons) do
		local isEquipped = equipped[1] == moveId or equipped[2] == moveId
		button.BackgroundColor3 = isEquipped and CARD_SELECTED or CARD
		local equippedStroke = button:FindFirstChild("EquippedStroke") :: UIStroke?
		if equippedStroke then
			equippedStroke.Color = isEquipped and ACCENT or BORDER
			equippedStroke.Transparency = isEquipped and 0 or 0.3
		end
	end
	summary.Text = string.format("Z  %s     X  %s", string.upper(moveName(equipped[1])), string.upper(moveName(equipped[2])))
end

local function setExpanded(value: boolean)
	expanded = value
	panel.Visible = value
	expandMark.Text = value and "<" or ">"
	weaponStroke.Color = value and ACCENT or BORDER
end

local function inMatch(): boolean
	local character = player.Character
	return character ~= nil and character:GetAttribute("InMatch") == true
end

local function refreshVisibility()
	gui.Enabled = not inMatch()
	if not gui.Enabled then setExpanded(false) end
end

weaponCard.MouseButton1Click:Connect(function()
	if gui.Enabled then setExpanded(not expanded) end
end)
for index, button in pairs(slotButtons) do
	button.MouseButton1Click:Connect(function()
		activeSlot = index
		refresh()
	end)
end
for moveId, button in pairs(moveButtons) do
	button.MouseButton1Click:Connect(function()
		if gui.Enabled then EquipMove:FireServer(activeSlot, moveId) end
	end)
end

StateUpdate.OnClientEvent:Connect(refresh)
player:GetAttributeChangedSignal("EquippedMove1"):Connect(refresh)
player:GetAttributeChangedSignal("EquippedMove2"):Connect(refresh)

local inMatchConnection: RBXScriptConnection? = nil
local function watchCharacter(character: Model)
	if inMatchConnection then inMatchConnection:Disconnect() end
	inMatchConnection = character:GetAttributeChangedSignal("InMatch"):Connect(refreshVisibility)
	refreshVisibility()
end
player.CharacterAdded:Connect(watchCharacter)
if player.Character then watchCharacter(player.Character) else refreshVisibility() end

-- The scythe Tool is a binary model in this repo. Disable only its legacy Spin/Throw
-- input LocalScripts so they cannot bypass the selected Z/X loadout. Their server-side
-- effects are replaced by EquippedScytheMoves.server.luau.
local LEGACY_TOOL_INPUT = { spinclient = true, throw = true, throwclient = true, throwingclient = true }
local function suppressLegacy(instance: Instance)
	if not instance:IsA("LocalScript") then return end
	local parent = instance.Parent
	local underTool = false
	while parent do
		if parent:IsA("Tool") then underTool = true break end
		parent = parent.Parent
	end
	if not underTool then return end
	local normalized = string.lower(string.gsub(instance.Name, "%s+", ""))
	if LEGACY_TOOL_INPUT[normalized] then instance.Disabled = true end
end
local function scan(container: Instance)
	for _, descendant in ipairs(container:GetDescendants()) do suppressLegacy(descendant) end
	container.DescendantAdded:Connect(suppressLegacy)
end
scan(player:WaitForChild("Backpack"))
player.CharacterAdded:Connect(scan)
if player.Character then scan(player.Character) end

local function playAnimation(moveId: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animationId = if moveId == "spin" then "rbxassetid://89608736085843" elseif moveId == "scythe_throw" then "rbxassetid://95546671624902" else nil
	if not animationId then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
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

	local equipped = slots()
	local moveId = equipped[slotIndex]
	local move = LoadoutPolicy.GetMove(moveId)
	if not move then return end
	local now = os.clock()
	if now < (nextLocalUse[moveId] or 0) then return end
	nextLocalUse[moveId] = now + move.Cooldown

	if moveId == "soul_reap" then
		SoulReapRequest:FireServer(slotIndex)
	else
		playAnimation(moveId)
		UseMove:FireServer(slotIndex)
	end
end

local function slotOne(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then useSlot(1) end
	return inMatch() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end
local function slotTwo(_, state: Enum.UserInputState)
	if state == Enum.UserInputState.Begin then useSlot(2) end
	return inMatch() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
end
ContextActionService:BindActionAtPriority("SEVER_LoadoutSlot1", slotOne, false, 3000, Enum.KeyCode.Z, Enum.KeyCode.One)
ContextActionService:BindActionAtPriority("SEVER_LoadoutSlot2", slotTwo, false, 3000, Enum.KeyCode.X, Enum.KeyCode.Two)

local function spinFX(userId: number, duration: number)
	local target = Players:GetPlayerByUserId(userId)
	local character = target and target.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not rootPart or not rootPart:IsA("BasePart") then return end
	local highlight = Instance.new("Highlight")
	highlight.FillColor = ACCENT
	highlight.FillTransparency = 0.64
	highlight.OutlineColor = Color3.fromRGB(255, 214, 220)
	highlight.OutlineTransparency = 0.12
	highlight.Parent = character
	Debris:AddItem(highlight, duration)
end

local function throwFX(origin: Vector3, direction: Vector3, range: number)
	local blade = Instance.new("Part")
	blade.Name = "LoadoutThrowFX"
	blade.Material = Enum.Material.Neon
	blade.Color = ACCENT
	blade.Anchored = true
	blade.CanCollide = false
	blade.CanTouch = false
	blade.CanQuery = false
	blade.Size = Vector3.new(0.3, 4.5, 1.1)
	blade.CFrame = CFrame.lookAt(origin, origin + direction) * CFrame.Angles(0, math.rad(90), math.rad(32))
	blade.Parent = workspace
	TweenService:Create(blade, TweenInfo.new(0.38, Enum.EasingStyle.Linear), {
		CFrame = blade.CFrame + direction * range,
		Transparency = 0.35,
	}):Play()
	Debris:AddItem(blade, 0.45)
end

UseMove.OnClientEvent:Connect(function(kind, moveId, userId, a, b, c)
	if kind ~= "FX" or type(moveId) ~= "string" or type(userId) ~= "number" then return end
	if moveId == "spin" and type(a) == "number" then
		spinFX(userId, a)
	elseif moveId == "scythe_throw" and typeof(a) == "Vector3" and typeof(b) == "Vector3" and type(c) == "number" then
		throwFX(a, b, c)
	end
end)

refresh()
refreshVisibility()
