-- // services

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // variables

local Camera = workspace.CurrentCamera
local CinematicFolder = workspace:FindFirstChild("Cinematic")


local Cinematic = {}

-- // function

local function PlayCinematic()
	
	local StartCamera = CinematicFolder:FindFirstChild("Start")
	local EndCamera = CinematicFolder:FindFirstChild("End")
	
	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CFrame = StartCamera.CFrame

	local tweenInfo = TweenInfo.new(5, Enum.EasingStyle.Sine)
	local goal = {CFrame = EndCamera.CFrame}
	local tween = TweenService:Create(Camera, tweenInfo, goal)
	tween:Play()

	tween.Completed:Connect(function()
		Camera.CameraType = Enum.CameraType.Custom
	end)
	
end

ReplicatedStorage.Remotes.Game.StartCinematic.OnClientEvent:Connect(PlayCinematic)

return {}