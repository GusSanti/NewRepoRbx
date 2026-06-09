-- // services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- // variables

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ClientLoading = Remotes:WaitForChild("ClientLoading")

local LoadingScreen = require(script.Parent.ReplicateFirst.LoadingScreen)
local Recieve = require(script.Parent.Replicate.Recieve)
local Audio = require(script.Parent.ReplicateFirst.MapMusic)

-- // pcall

pcall(function()
	StarterGui:SetCore("ResetButtonCallback", false)
end)

-- // setup modules

for _, Module in ipairs(script.Parent.Modules:GetDescendants()) do
	if Module:IsA("ModuleScript") and not Module.Parent:IsA("ModuleScript") then
		local success, err = pcall(function()
			require(Module)
		end)

		if not success then
			warn("⚠️ Failed to load module:", Module.Name, "-", err)
		end
	end
end

print("✅ | Client loaded all modules.")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

LoadingScreen.Hide()
ClientLoading.ClientLoaded:FireServer()

