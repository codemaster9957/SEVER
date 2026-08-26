--// SYNTHWAVE ENERGY GRID
--// Place this in ServerScriptService or inside Arena2 as a normal Script.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

---------------------------------------------------------------------
-- CONFIGURATION
---------------------------------------------------------------------

local CONFIG = {
	ArenaName = "Arena2",
	GridFolderName = "grid lines",

	-- Performance
	UpdateRate = 1 / 30, -- 30 updates per second

	-- Main colour movement
	ColorCycleSpeed = 0.075,
	GradientRepeats = 1.65,

	-- Travelling energy pulse
	ScanSpeed = 0.28,
	ScanWidth = 0.075,
	ScanStrength = 0.58,

	-- Secondary crossing pulse
	CrossWaveSpeed = 0.17,
	CrossWaveStrength = 0.24,

	-- General glow
	BaseBrightness = 0.42,
	WaveBrightness = 0.22,
	FlickerStrength = 0.035,

	-- Transparency also pulses with the grid
	MinimumTransparency = 0.02,
	MaximumTransparency = 0.26,

	-- Automatically apply Neon material
	ForceNeonMaterial = true,

	-- Removes unnecessary shadows from the thin grid pieces
	DisableGridShadows = true,

	-- Creates a subtle global bloom effect
	EnableBloom = true,
}

---------------------------------------------------------------------
-- SYNTHWAVE PALETTE
---------------------------------------------------------------------

local PALETTE = {
	Color3.fromRGB(255, 20, 147),  -- Hot pink
	Color3.fromRGB(255, 0, 255),   -- Magenta
	Color3.fromRGB(166, 38, 255),  -- Electric violet
	Color3.fromRGB(72, 35, 255),   -- Deep blue-violet
	Color3.fromRGB(0, 122, 255),   -- Electric blue
	Color3.fromRGB(0, 245, 255),   -- Cyan
	Color3.fromRGB(90, 80, 255),   -- Indigo
	Color3.fromRGB(255, 30, 210),  -- Pink return
}

local BLACK = Color3.new(0, 0, 0)
local WHITE_HOT = Color3.fromRGB(255, 225, 255)
local TAU = math.pi * 2

---------------------------------------------------------------------
-- FIND GRID FOLDER
---------------------------------------------------------------------

local arenasFolder = Workspace:WaitForChild("Arenas", 10)

if not arenasFolder then
	warn("[SynthGrid] Workspace.Arenas could not be found.")
	return
end

local arena = arenasFolder:WaitForChild(CONFIG.ArenaName, 10)

if not arena then
	warn(string.format(
		"[SynthGrid] Could not find arena named %q.",
		CONFIG.ArenaName
		))
	return
end

local gridFolder = arena:WaitForChild(CONFIG.GridFolderName, 10)

if not gridFolder then
	warn(string.format(
		"[SynthGrid] Could not find folder %q inside %s.",
		CONFIG.GridFolderName,
		arena:GetFullName()
		))
	return
end

---------------------------------------------------------------------
-- OPTIONAL BLOOM
---------------------------------------------------------------------

if CONFIG.EnableBloom then
	local bloom = Lighting:FindFirstChild("SynthGridBloom")

	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "SynthGridBloom"
		bloom.Parent = Lighting
	end

	bloom.Intensity = 0.85
	bloom.Size = 32
	bloom.Threshold = 0.82
end

---------------------------------------------------------------------
-- HELPER FUNCTIONS
---------------------------------------------------------------------

local function clamp01(value)
	return math.clamp(value, 0, 1)
end

local function smoothStep(value)
	value = clamp01(value)
	return value * value * (3 - 2 * value)
end

local function fractional(value)
	return value - math.floor(value)
end

local function getPaletteColor(value)
	value = value % 1

	local scaled = value * #PALETTE
	local paletteIndex = math.floor(scaled)
	local blend = smoothStep(scaled - paletteIndex)

	local firstIndex = (paletteIndex % #PALETTE) + 1
	local secondIndex = (firstIndex % #PALETTE) + 1

	return PALETTE[firstIndex]:Lerp(PALETTE[secondIndex], blend)
end

local function circularDistance(value)
	value = value % 1
	return math.min(value, 1 - value)
end

local function pulseFromDistance(distance, width)
	local safeWidth = math.max(width, 0.001)
	local exponent = -(distance * distance) / (2 * safeWidth * safeWidth)

	return math.exp(exponent)
end

local function createSeed(part)
	local position = part.Position

	return fractional(
		math.sin(
			position.X * 12.9898
				+ position.Y * 37.719
				+ position.Z * 78.233
		) * 43758.5453
	)
end

---------------------------------------------------------------------
-- GRID PART STORAGE
---------------------------------------------------------------------

local gridParts = {}

local bounds = {
	minX = math.huge,
	maxX = -math.huge,
	minZ = math.huge,
	maxZ = -math.huge,
}

local function preparePart(part)
	if gridParts[part] then
		return
	end

	if CONFIG.ForceNeonMaterial then
		part.Material = Enum.Material.Neon
	end

	if CONFIG.DisableGridShadows then
		part.CastShadow = false
	end

	gridParts[part] = {
		seed = createSeed(part),
		u = 0,
		v = 0,
		diagonal = 0,
		cross = 0,
	}
end

local function removePart(part)
	gridParts[part] = nil
end

local function recalculateGridData()
	bounds.minX = math.huge
	bounds.maxX = -math.huge
	bounds.minZ = math.huge
	bounds.maxZ = -math.huge

	local validPartCount = 0

	for part in pairs(gridParts) do
		if part.Parent and part:IsDescendantOf(gridFolder) then
			validPartCount += 1

			local position = part.Position

			bounds.minX = math.min(bounds.minX, position.X)
			bounds.maxX = math.max(bounds.maxX, position.X)
			bounds.minZ = math.min(bounds.minZ, position.Z)
			bounds.maxZ = math.max(bounds.maxZ, position.Z)
		else
			gridParts[part] = nil
		end
	end

	if validPartCount == 0 then
		return
	end

	local rangeX = math.max(bounds.maxX - bounds.minX, 0.001)
	local rangeZ = math.max(bounds.maxZ - bounds.minZ, 0.001)

	for part, data in pairs(gridParts) do
		local position = part.Position

		data.u = (position.X - bounds.minX) / rangeX
		data.v = (position.Z - bounds.minZ) / rangeZ

		-- Diagonal wave moving across the entire grid.
		data.diagonal = data.u * 0.46 + data.v * 0.54

		-- Opposing coordinate for the secondary crossing wave.
		data.cross = data.u * 0.55 - data.v * 0.45

		-- Slightly stagger lines depending on their direction.
		if part.Size.X > part.Size.Z then
			data.orientationOffset = 0
		else
			data.orientationOffset = 0.08
		end
	end
end

---------------------------------------------------------------------
-- COLLECT CURRENT PARTS
---------------------------------------------------------------------

for _, descendant in ipairs(gridFolder:GetDescendants()) do
	if descendant:IsA("BasePart") then
		preparePart(descendant)
	end
end

recalculateGridData()

local function countGridParts()
	local count = 0

	for _ in pairs(gridParts) do
		count += 1
	end

	return count
end

local initialPartCount = countGridParts()

if initialPartCount == 0 then
	warn("[SynthGrid] No BaseParts were found inside the grid folder.")
	return
end

print(string.format(
	"[SynthGrid] Started enhanced grid animation with %d parts.",
	initialPartCount
	))

---------------------------------------------------------------------
-- DYNAMIC GRID SUPPORT
---------------------------------------------------------------------

local boundsDirty = false

gridFolder.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("BasePart") then
		preparePart(descendant)
		boundsDirty = true
	end
end)

gridFolder.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("BasePart") then
		removePart(descendant)
		boundsDirty = true
	end
end)

---------------------------------------------------------------------
-- ANIMATION
---------------------------------------------------------------------

local accumulator = 0
local elapsed = 0
local animationConnection

animationConnection = RunService.Heartbeat:Connect(function(deltaTime)
	if not gridFolder:IsDescendantOf(Workspace) then
		animationConnection:Disconnect()
		return
	end

	accumulator += deltaTime
	elapsed += deltaTime

	if accumulator < CONFIG.UpdateRate then
		return
	end

	accumulator %= CONFIG.UpdateRate

	if boundsDirty then
		boundsDirty = false
		recalculateGridData()
	end

	local globalBreathing =
		0.5
		+ 0.5 * math.sin(elapsed * 0.9)

	for part, data in pairs(gridParts) do
		if not part.Parent then
			gridParts[part] = nil
			continue
		end

		-------------------------------------------------------------
		-- MAIN COLOUR GRADIENT
		-------------------------------------------------------------

		local colourDistortion =
			math.sin(
				(data.u - data.v) * TAU
				+ elapsed * 0.38
				+ data.seed * TAU
			) * 0.035

		local colourPosition =
			elapsed * CONFIG.ColorCycleSpeed
			+ data.diagonal * CONFIG.GradientRepeats
			+ data.orientationOffset
			+ colourDistortion

		local baseColor = getPaletteColor(colourPosition)

		-------------------------------------------------------------
		-- MAIN TRAVELLING SCAN
		-------------------------------------------------------------

		local scanPosition =
			data.diagonal * 1.55
		- elapsed * CONFIG.ScanSpeed
			+ data.seed * 0.025

		local scanDistance = circularDistance(scanPosition)

		local mainScan = pulseFromDistance(
			scanDistance,
			CONFIG.ScanWidth
		)

		-------------------------------------------------------------
		-- CROSSING ENERGY WAVE
		-------------------------------------------------------------

		local crossPosition =
			data.cross * 1.3
			+ elapsed * CONFIG.CrossWaveSpeed
			+ 0.5

		local crossDistance = circularDistance(crossPosition)

		local crossScan = pulseFromDistance(
			crossDistance,
			CONFIG.ScanWidth * 1.35
		)

		-------------------------------------------------------------
		-- SOFT AMBIENT WAVE
		-------------------------------------------------------------

		local ambientWave =
			0.5
			+ 0.5 * math.sin(
				(data.u * 1.15 + data.v * 1.7) * TAU
				- elapsed * 1.25
				+ data.seed * 2
			)

		-------------------------------------------------------------
		-- SUBTLE ELECTRICAL FLICKER
		-------------------------------------------------------------

		local flicker =
			0.5
			+ 0.5 * math.sin(
				elapsed * (5.5 + data.seed * 2.5)
				+ data.seed * 80
			)

		flicker = flicker * flicker

		-------------------------------------------------------------
		-- FINAL BRIGHTNESS
		-------------------------------------------------------------

		local brightness =
			CONFIG.BaseBrightness
			+ ambientWave * CONFIG.WaveBrightness
			+ mainScan * CONFIG.ScanStrength
			+ crossScan * CONFIG.CrossWaveStrength
			+ flicker * CONFIG.FlickerStrength
			+ globalBreathing * 0.045

		brightness = clamp01(brightness)

		local finalColor = BLACK:Lerp(baseColor, brightness)

		-- Makes the centre of travelling pulses appear white-hot.
		local whiteHotAmount =
			mainScan * 0.34
			+ crossScan * 0.12

		finalColor = finalColor:Lerp(
			WHITE_HOT,
			clamp01(whiteHotAmount)
		)

		-------------------------------------------------------------
		-- TRANSPARENCY PULSE
		-------------------------------------------------------------

		local totalPulse = clamp01(
			mainScan
				+ crossScan * 0.45
				+ ambientWave * 0.08
		)

		local transparency =
			CONFIG.MaximumTransparency
			+ (
				CONFIG.MinimumTransparency
				- CONFIG.MaximumTransparency
			) * totalPulse

		part.Color = finalColor
		part.Transparency = math.clamp(transparency, 0, 1)
	end
end)