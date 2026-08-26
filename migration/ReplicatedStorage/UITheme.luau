-- ReplicatedStorage/UITheme
local UITheme = {}

UITheme.Colors = {
	Primary = Color3.fromRGB(255, 255, 255),
	Secondary = Color3.fromRGB(180, 180, 180),
	Accent = Color3.fromRGB(255, 60, 45), -- Red for Scythe
	Success = Color3.fromRGB(0, 255, 120),
	Warning = Color3.fromRGB(255, 200, 50),
	Danger = Color3.fromRGB(255, 50, 50),
	Background = Color3.fromRGB(20, 20, 20),
	Overlay = Color3.fromRGB(0, 0, 0),
	Gold = Color3.fromRGB(255, 215, 0),
	Text = Color3.fromRGB(255, 255, 255),
}

UITheme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Main = Enum.Font.GothamBold,
	Secondary = Enum.Font.Gotham,
}

UITheme.Layout = {
	CornerRadius = UDim.new(0, 8),
	StrokeThickness = 2,
	StrokeTransparency = 0.5,
	DefaultPadding = UDim2.new(0, 10, 0, 10),
}

UITheme.Transitions = {
	Default = TweenInfo.new(0.3, Enum.EasingStyle.Sine),
	Quick = TweenInfo.new(0.15, Enum.EasingStyle.Sine),
	Slow = TweenInfo.new(0.6, Enum.EasingStyle.Sine),
	Bounce = TweenInfo.new(0.4, Enum.EasingStyle.Back),
}

function UITheme.applyStandardStyle(instance)
	if instance:IsA("GuiObject") then
		local corner = instance:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
		corner.CornerRadius = UITheme.Layout.CornerRadius
		corner.Parent = instance
		
		local stroke = instance:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
		stroke.Thickness = UITheme.Layout.StrokeThickness
		stroke.Transparency = UITheme.Layout.StrokeTransparency
		stroke.Color = UITheme.Colors.Primary
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = instance
	end
end

return UITheme
