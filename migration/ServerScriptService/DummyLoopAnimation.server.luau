local dummy = workspace:WaitForChild("training")
local humanoid = dummy:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local ANIMATION_ID = "rbxassetid://123946702942473"

local animation = Instance.new("Animation")
animation.AnimationId = ANIMATION_ID
animation.Name = "LoopAnimation"
animation.Parent = dummy

local track = animator:LoadAnimation(animation)
track.Looped = true
track.Priority = Enum.AnimationPriority.Action
track:Play()

-- Re-play if the track ever stops (e.g. character respawn)
track.Stopped:Connect(function()
	track:Play()
end)