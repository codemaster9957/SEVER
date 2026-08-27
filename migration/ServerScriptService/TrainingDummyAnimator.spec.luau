local Animator = require(script.Parent:WaitForChild("TrainingDummyAnimator"))

local candidates = {
	{Name = "WalkAnim", AnimationId = "rbxassetid://11"},
	{Name = "Scythe Slash", AnimationId = "rbxassetid://22"},
	{Name = "Soul Reap Dash", AnimationId = "rbxassetid://33"},
}

assert(Animator.SelectAnimationId(candidates, {"walk"}, nil) == "rbxassetid://11", "walk animation should resolve by name")
assert(Animator.SelectAnimationId(candidates, {"slash", "attack", "swing"}, nil) == "rbxassetid://22", "slash animation should resolve by name")
assert(Animator.SelectAnimationId(candidates, {"soul", "reap"}, nil) == "rbxassetid://33", "Soul Reap should use a real discovered asset when present")
assert(Animator.SelectAnimationId({}, {"dash"}, "rbxassetid://83398771525907") == "rbxassetid://83398771525907", "dash should use the established fallback")
assert(Animator.SelectAnimationId({}, {"soul", "reap"}, nil) == nil, "Soul Reap must not invent a fallback asset")

return true
