local MatchCameraManager = {}

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local States = {
	Lobby = "Lobby",
	Match = "Match",
	Intro = "Intro",
	FinalHit = "FinalHit",
	Victory = "Victory"
}

MatchCameraManager.CurrentState = States.Lobby
local forcedMode = nil -- New field for custom overrides
local targetSubject = nil
local opponentSubject = nil

local shakePower = 0
local shakeUntil = 0
local zoomOffset = 0

local function getRoot(char)
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function updateCamera()
	if forcedMode == "Scriptable" then
		camera.CameraType = Enum.CameraType.Scriptable
		return
	end
	
	if MatchCameraManager.CurrentState == States.Lobby then
		camera.CameraType = Enum.CameraType.Custom
		return
	end
	
	camera.CameraType = Enum.CameraType.Scriptable
	
	local char = player.Character
	local root = getRoot(char)
	
	if MatchCameraManager.CurrentState == States.Match then
		local oppRoot = getRoot(opponentSubject)
		if root and oppRoot then
			local mid = (root.Position + oppRoot.Position) / 2
			local dist = (root.Position - oppRoot.Position).Magnitude
			local zDepth = math.clamp(30 + (dist * 0.5), 25, 60) + zoomOffset

			-- Side-on view: keep the camera at the fighters' height looking horizontally
			local targetPos = mid + Vector3.new(0, 2, zDepth)
			camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(targetPos, mid + Vector3.new(0, 2, 0)), 0.1)
		end
	elseif MatchCameraManager.CurrentState == States.Victory then
		if targetSubject then
			local tRoot = getRoot(targetSubject)
			if tRoot then
				local targetPos = tRoot.Position + tRoot.CFrame.LookVector * 10 + Vector3.new(0, 4, 0)
				camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(targetPos, tRoot.Position + Vector3.new(0, 2, 0)), 0.05)
			end
		end
	elseif MatchCameraManager.CurrentState == States.FinalHit then
		-- Hard freeze or dramatic zoom
	end
	
	-- Apply Shake
	local now = os.clock()
	if shakeUntil > now then
		local factor = (shakeUntil - now) / 0.5
		local offset = Vector3.new((math.random()-0.5)*shakePower*factor, (math.random()-0.5)*shakePower*factor, 0)
		camera.CFrame *= CFrame.new(offset)
	end
end

function MatchCameraManager:SetMode(mode)
	forcedMode = mode
	if mode == "Classic" then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid")
	end
end

function MatchCameraManager:SetState(state, subject, opponent)
	self.CurrentState = state
	targetSubject = subject
	opponentSubject = opponent
	
	if state == States.Lobby then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = player.Character and player.Character:FindFirstChild("Humanoid")
	end
end

function MatchCameraManager:Shake(power, duration)
	shakePower = power
	shakeUntil = os.clock() + duration
end

function MatchCameraManager:Impulse(direction)
	-- Dramatic camera shift
end

RunService:BindToRenderStep("MatchCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)

return MatchCameraManager
