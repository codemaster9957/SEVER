--!strict
-- Mobile-only visual budget. Desktop visuals are unchanged.
-- This does not replace authored slash/throw assets; it only trims legacy generated clash spam.

local UserInputService = game:GetService("UserInputService")

if not UserInputService.TouchEnabled then
	return
end

local CLASH_WINDOW = 0.12
local MAX_SPARKS_PER_BURST = 14
local MAX_RINGS_PER_BURST = 2

local windowStartedAt = 0
local sparkCount = 0
local ringCount = 0

local function resetBurstWindowIfNeeded()
	local now = os.clock()
	if now - windowStartedAt > CLASH_WINDOW then
		windowStartedAt = now
		sparkCount = 0
		ringCount = 0
	end
end

local function hasAncestorNamed(instance: Instance, targetName: string): boolean
	local current = instance.Parent
	while current and current ~= workspace do
		if current.Name == targetName then return true end
		current = current.Parent
	end
	return false
end

local function tune(instance: Instance)
	resetBurstWindowIfNeeded()

	if instance:IsA("BasePart") then
		if instance.Name == "ClashSpark" then
			sparkCount += 1
			if sparkCount > MAX_SPARKS_PER_BURST then
				instance:Destroy()
			end
			return
		end

		if instance.Name == "ClashRing" then
			ringCount += 1
			if ringCount > MAX_RINGS_PER_BURST then
				instance:Destroy()
			end
			return
		end
	end

	if instance:IsA("PointLight") and hasAncestorNamed(instance, "ClashFlash") then
		instance.Shadows = false
		instance.Brightness = math.min(instance.Brightness, 4)
		instance.Range = math.min(instance.Range, 22)
		return
	end

	-- DashServer reuses this emitter now; phones use a slightly smaller continuous budget.
	if instance:IsA("ParticleEmitter") and instance.Name == "DashParticles" then
		instance.Rate = math.min(instance.Rate, 60)
		instance.LightEmission = math.min(instance.LightEmission, 0.5)
	end
end

workspace.DescendantAdded:Connect(function(instance)
	task.defer(tune, instance)
end)

for _, instance in ipairs(workspace:GetDescendants()) do
	tune(instance)
end

print("[MobilePerformanceController] Touch combat VFX budget enabled")
