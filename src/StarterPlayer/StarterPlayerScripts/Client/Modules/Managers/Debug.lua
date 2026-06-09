-- // services

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

-- // variables

local LocalPlayer = Players.LocalPlayer
local debugGuiTemp = script.UI:WaitForChild("debug_Gui")

local pathFolder = workspace:FindFirstChild("Path")
local waypointsFolder = pathFolder:FindFirstChild("Waypoints")

-- // functions

local function getRamUsage()
	return math.floor(Stats:GetTotalMemoryUsageMb())
end

local function getFPS()
	return math.floor(1 / RunService.RenderStepped:Wait())
end

local function getPing()
	return LocalPlayer:GetNetworkPing() * 1000
end

local function setupDebugGui()
	
	local DebugGui = debugGuiTemp:Clone()
	if not DebugGui then return end
	
	local DebugContainer = DebugGui:WaitForChild("debug_Container")
	if not DebugContainer then return end
	
	local Fps = DebugContainer:WaitForChild("Fps")
	local Ping = DebugContainer:WaitForChild("Ping")
	local Ram = DebugContainer:WaitForChild("Ram")
	
	DebugGui.Parent = LocalPlayer.PlayerGui
	
	local function getColor(value, thresholds)
		if value <= thresholds.green then
			return Color3.fromRGB(0, 255, 0)
		elseif value <= thresholds.yellow then
			return Color3.fromRGB(255, 255, 0)
		else
			return Color3.fromRGB(255, 0, 0)
		end
	end

	task.spawn(function()
		while true do
			task.wait(0.1)

			local fps = getFPS()
			local ping = getPing()
			local ram = getRamUsage()

			Fps.Text = fps .. " fps"
			Ping.Text = math.floor(ping) .. " ms"
			Ram.Text = ram .. " MB"

			Fps.TextColor3 = getColor(fps * -1, {green = -60, yellow = -30}) -- inverted for >= check
			Ping.TextColor3 = getColor(ping, {green = 80, yellow = 120})
			Ram.TextColor3 = getColor(ram, {green = 2000, yellow = 4000})
		end
	end)
	
end

local function revealWaypoints()
	if not pathFolder then return end
	for _, descendant in ipairs(pathFolder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = Color3.fromRGB(255, 0, 0)
			descendant.Transparency = 0.25
		end
	end
end

-- // initialize

LocalPlayer.Chatted:Connect(function(msg)
	
	if msg:lower() == "!debug" then
		setupDebugGui()
		revealWaypoints()
	end

end)

return {}