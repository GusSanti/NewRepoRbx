-- // services

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- // runtime

task.spawn(function()
	local customLoadingScreen = TeleportService:GetArrivingTeleportGui()
	if customLoadingScreen then
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end
end)

return {}