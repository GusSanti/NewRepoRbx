-- // services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

-- // variables

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local GameRemotes = Remotes:FindFirstChild("Game")

local Path = workspace:FindFirstChild("Path")
local Waypoints = Path:FindFirstChild("Waypoints")

local Units = ServerStorage:FindFirstChild("Units")

local GlobalValues = ReplicatedStorage:FindFirstChild("GlobalValues")

-- // remotes

local RequestGameStart_Event = GameRemotes:FindFirstChild("RequestGameStart")

-- // tables

local GameManager = {}
local Dialogue = require(ReplicatedStorage.Modules.StoredData.Dialogue)

-- // values

local MaxHealth = GlobalValues:FindFirstChild("Base_Health").Value

-- // function

local GameManager = {}

-- // settings

local hasDialogue = false
local collision_Group = "Worms"

-- // functions

local function hideArrows()
	task.spawn(function()
		local Path_Model = workspace:FindFirstChild("Path_Model")
		if not Path_Model then return end

		local Arrows = Path_Model:FindFirstChild("Arrows")
		if not Arrows then return end

		task.wait(30)

		for _, Beam in ipairs(Arrows:GetDescendants()) do
			if Beam:IsA("Beam") then
				Beam.Enabled = false
			end
		end
	end)
end

local function sendDialogueData()
	if hasDialogue then
		local DialogueData = Dialogue
		GameRemotes:FindFirstChild("SendDialogueData"):FireAllClients(DialogueData)
	end
end

local Presets = require(ReplicatedStorage.Modules.StoredData.RoundInfo)

function GameManager.Start(Difficulty, Gamemode, MapName)
	
	-- // starting functions
	hideArrows()
	sendDialogueData()
	
	local isTutorial = MapName == "Tutorial"
	local DifficultyPreset = isTutorial and Presets.Tutorial or Presets[Difficulty]
	local WaveCount = 0
	local isEndless = tostring(Gamemode):lower() == "endless"

	if not DifficultyPreset then
		warn("[GameManager] Round preset missing:", Difficulty, MapName)
		return
	end

	if isEndless and not isTutorial then
		WaveCount = math.huge
	else
		for _ in pairs(DifficultyPreset) do
			WaveCount = WaveCount + 1
		end
	end

	local RoundManager = require(script.Parent.Parent.Managers.RoundManager)
	RoundManager.StartGame(WaveCount, DifficultyPreset, isEndless and "Endless" or Gamemode, Difficulty, MapName)

end

RequestGameStart_Event.Event:Connect(function(Difficulty, Gamemode, MapName)
	warn(Difficulty, Gamemode, MapName)
	GameManager.Start(Difficulty, Gamemode, MapName)
end)

return GameManager
