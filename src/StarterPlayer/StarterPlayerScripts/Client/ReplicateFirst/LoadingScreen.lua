-- // services

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

-- // variables

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local LoadingScreen = PlayerGui:WaitForChild("Loading")
local MainGui = PlayerGui:WaitForChild("InGame_UI")

local Remotes = ReplicatedStorage.Remotes

local public = {}
local activeCoroutine
local activeTweens = {}

-- // functions

local function disableLoadingScreen()
	MainGui.Enabled = true
	LoadingScreen.Enabled = false
end

local function enableLoadingScreen()
	local Holder = LoadingScreen:WaitForChild("Holder")
	if not Holder then return end

	MainGui.Enabled = false
	LoadingScreen.Enabled = true

	if activeCoroutine then
		activeCoroutine:Cancel()
		activeCoroutine = nil
	end
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	activeTweens = {}

	local jumpScale = 1.5
	local duration = 0.2
	local delayBetween = 0.05

	local images = {}
	for _, image in ipairs(Holder:GetChildren()) do
		if image:IsA("ImageLabel") then
			local uiScale = image:FindFirstChildOfClass("UIScale")
			if not uiScale then
				uiScale = Instance.new("UIScale")
				uiScale.Scale = 1
				uiScale.Parent = image
			end
			table.insert(images, uiScale)
		end
	end

	activeCoroutine = coroutine.create(function()
		while LoadingScreen.Enabled do
			for _, uiScale in ipairs(images) do
				local tweenUp = TweenService:Create(uiScale, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Scale = jumpScale
				})
				local tweenDown = TweenService:Create(uiScale, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					Scale = 1
				})

				table.insert(activeTweens, tweenUp)
				table.insert(activeTweens, tweenDown)

				tweenUp:Play()
				tweenUp.Completed:Wait()
				tweenDown:Play()
				tweenDown.Completed:Wait()

				table.remove(activeTweens, 1)
				table.remove(activeTweens, 1)

				task.wait(delayBetween)
			end
		end
	end)
	coroutine.resume(activeCoroutine)
end

local function init()
	enableLoadingScreen()
end

function public.Hide()
	disableLoadingScreen()
end

-- // code

if game.Players.LocalPlayer then
	init()
end

TeleportService:SetTeleportGui(LoadingScreen)

return public