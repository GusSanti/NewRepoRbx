local Handler = {}

local ReplicatedStorage = game.ReplicatedStorage
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameRemotes = Remotes:WaitForChild("Game")
local TakeDamage = GameRemotes:WaitForChild("VisualDamage")
local TweenService = game:GetService("TweenService")

TakeDamage.OnClientEvent:Connect(function(Model, Total)
	local Highlight = Instance.new("Highlight")
	Highlight.FillColor = Color3.fromRGB(255, 0, 0)
	Highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	Highlight.FillTransparency = 0
	Highlight.OutlineTransparency = 0
	Highlight.Parent = Model

	local flashTween = TweenService:Create(Highlight, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {
		FillTransparency = 1,
		OutlineTransparency = 1
	})

	flashTween:Play()
	flashTween.Completed:Connect(function()
		Highlight:Destroy()
	end)

	local HumanoidRootPart = Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChild("Head") or Model.PrimaryPart
	if HumanoidRootPart then
		local Attachment = Instance.new("Attachment")
		Attachment.Position = Vector3.new(0, 3, 0)
		Attachment.Parent = HumanoidRootPart

		local BillboardGui = Instance.new("BillboardGui")
		BillboardGui.Size = UDim2.new(0, 80, 0, 40)
		BillboardGui.AlwaysOnTop = true
		BillboardGui.Adornee = Attachment
		BillboardGui.Parent = Attachment

		local TextLabel = Instance.new("TextLabel")
		TextLabel.Size = UDim2.new(1, 0, 1, 0)
		TextLabel.BackgroundTransparency = 1
		TextLabel.Text = "-"..tostring(Total)
		TextLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
		TextLabel.TextScaled = true
		TextLabel.Font = Enum.Font.FredokaOne
		TextLabel.TextTransparency = 1
		TextLabel.TextStrokeTransparency = 0.5
		TextLabel.Parent = BillboardGui

		local fadeIn = TweenService:Create(TextLabel, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			TextTransparency = 0,
			TextStrokeTransparency = 0.5
		})

		local fadeOut = TweenService:Create(TextLabel, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			TextTransparency = 1,
			TextStrokeTransparency = 1
		})

		local moveUp = TweenService:Create(Attachment, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = Vector3.new(0, 5, 0)
		})

		fadeIn:Play()
		moveUp:Play()

		fadeIn.Completed:Connect(function()
			fadeOut:Play()
		end)

		fadeOut.Completed:Connect(function()
			Attachment:Destroy()
		end)
	end
end)

return Handler