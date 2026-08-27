local part = workspace:WaitForChild("highlighter")

local HIGHLIGHT_NAME = "RedlighterEffect"

-- [character] = {[touchingPart] = true}
local touching = {}
-- TouchEnded can fire after a part has moved/reparented, so remember ownership.
local touchOwners = {}

local function getCharacter(otherPart)
	if not otherPart then return nil end
	local character = otherPart:FindFirstAncestorOfClass("Model")
	if character and character:FindFirstChildOfClass("Humanoid") then
		return character
	end
	return nil
end

local function addHighlight(character)
	local existing = character:FindFirstChild(HIGHLIGHT_NAME)
	if existing and existing:IsA("Highlight") then return end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
end

local function removeHighlight(character)
	if not character then return end
	local highlight = character:FindFirstChild(HIGHLIGHT_NAME)
	if highlight and highlight:IsA("Highlight") then
		highlight:Destroy()
	end
end

local function clearCharacter(character)
	local set = touching[character]
	if set then
		for touchingPart in pairs(set) do
			touchOwners[touchingPart] = nil
		end
	end
	touching[character] = nil
	removeHighlight(character)
end

part.Touched:Connect(function(otherPart)
	local character = getCharacter(otherPart)
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local set = touching[character]
	if not set then
		set = {}
		touching[character] = set
	end

	set[otherPart] = true
	touchOwners[otherPart] = character
	addHighlight(character)
end)

part.TouchEnded:Connect(function(otherPart)
	local character = touchOwners[otherPart] or getCharacter(otherPart)
	touchOwners[otherPart] = nil
	if not character then return end

	local set = touching[character]
	if not set then return end

	set[otherPart] = nil
	if next(set) == nil then
		touching[character] = nil
		removeHighlight(character)
	end
end)

-- Characters can die, reset, or be teleported before TouchEnded is delivered.
-- Clean those stale entries so highlights never stick around indefinitely.
task.spawn(function()
	while part.Parent do
		task.wait(1)
		for character in pairs(touching) do
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not character.Parent or not humanoid or humanoid.Health <= 0 then
				clearCharacter(character)
			end
		end
	end
end)
