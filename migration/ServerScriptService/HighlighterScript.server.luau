local part = workspace:WaitForChild("highlighter")

-- Tracks which parts of each character are currently touching the zone.
-- Key: character, Value: set of touching parts.
local touching = {}

local function getCharacter(otherPart)
	local character = otherPart.Parent
	if character and character:FindFirstChildOfClass("Humanoid") then
		return character
	end
	return nil
end

local function addHighlight(character)
	if character:FindFirstChildOfClass("Highlight") then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "RedlighterEffect"
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.5
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = character
end

local function removeHighlight(character)
	local highlight = character:FindFirstChildOfClass("Highlight")
	if highlight and highlight.Name == "RedlighterEffect" then
		highlight:Destroy()
	end
end

part.Touched:Connect(function(otherPart)
	local character = getCharacter(otherPart)
	if not character then
		return
	end

	local set = touching[character]
	if not set then
		set = {}
		touching[character] = set
	end
	set[otherPart] = true
	addHighlight(character)
end)

part.TouchEnded:Connect(function(otherPart)
	local character = getCharacter(otherPart)
	if not character then
		return
	end

	local set = touching[character]
	if set then
		set[otherPart] = nil
		if next(set) == nil then
			touching[character] = nil
			removeHighlight(character)
		end
	end
end)
