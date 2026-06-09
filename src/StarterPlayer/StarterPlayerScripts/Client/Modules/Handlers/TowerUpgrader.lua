local Handler = {}

local UnitsAssigned = {}
local CardConnections = {}

local Priorities = {
	"First",
	"Last",
	"Closest"
}

local RunService = game:GetService("RunService")
local Towers = workspace:WaitForChild("Towers")

local ReplicatedStorage = game.ReplicatedStorage
local Modules = ReplicatedStorage:WaitForChild("Modules")
local StoredData = Modules:WaitForChild("StoredData")
local TowerData = require(StoredData:WaitForChild("TowerData"))

local Players = game.Players
local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local MainUi = PlayerGui:WaitForChild("InGame_UI")
local ButtonFrame = MainUi:WaitForChild("CenterLeft")
local TowersButton = ButtonFrame:WaitForChild("Towers")
local TowersFrame = MainUi:WaitForChild("Towers")
local ExitButton = TowersFrame:FindFirstChild("Close") or TowersFrame:FindFirstChild("Close", true)

local TowersBackground = TowersFrame:FindFirstChild("TowersBG") or TowersFrame
local TowersHolder = TowersBackground:FindFirstChild("GridScrollingFrame")
	or TowersFrame:FindFirstChild("GridScrollingFrame", true)
	or TowersFrame:FindFirstChild("Holder")
local ExampleTower = TowersHolder and (TowersHolder:FindFirstChild("Template") or TowersHolder:FindFirstChild("Example"))

local TowersEnabled = false
local Debounce = false
local SyncQueued = false
local SyncExistingTowers
local RequestSync

local function DisconnectCardConnections(card)
	local connections = CardConnections[card]
	if not connections then return end

	for _, connection in ipairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end

	CardConnections[card] = nil
end

local function TrackConnection(card, connection)
	if not connection then return end

	CardConnections[card] = CardConnections[card] or {}
	table.insert(CardConnections[card], connection)
end

local function FindGuiButton(root, names)
	if not root then return nil end

	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found and found:IsA("GuiButton") then
			return found
		end
	end

	return nil
end

local function FindTextObject(root, names)
	if not root then return nil end

	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found and (found:IsA("TextLabel") or found:IsA("TextButton") or found:IsA("TextBox")) then
			return found
		end
	end

	return nil
end

local function FindImageObject(root, names)
	if not root then return nil end

	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found and (found:IsA("ImageLabel") or found:IsA("ImageButton")) then
			return found
		end
	end

	return nil
end

local function ConnectGuiButton(button, callback)
	if not button then return nil end
	return button.Activated:Connect(callback)
end

local function GetLevel(tower)
	local level = tower.Name:match("_(%d+)$")
	return level and tonumber(level) or 1
end

local function GetBaseTowerName(tower)
	local baseName = tower.Name:match("^(.-)_%d+$")
	return baseName or tower.Name
end

local function GetPriorityIndex(tower)
	local attribute = tower:GetAttribute("Priority")

	if typeof(attribute) == "number" then
		return math.clamp(attribute, 1, #Priorities)
	end

	if typeof(attribute) == "string" then
		return table.find(Priorities, attribute) or 1
	end

	return 1
end

local function GetNextTowerName(tower)
	local baseName = GetBaseTowerName(tower)
	local currentLevel = GetLevel(tower)

	if tower.Name:match("_%d+$") then
		return baseName .. "_" .. (currentLevel + 1)
	end

	return tower.Name .. "_2"
end

local function GetNextTowerData(tower)
	local nextTowerName = GetNextTowerName(tower)
	local towerFolder = ReplicatedStorage:FindFirstChild("Storage")
		and ReplicatedStorage.Storage:FindFirstChild("Towers")
	local nextTowerModel = towerFolder and towerFolder:FindFirstChild(nextTowerName)
	local nextTowerInfo = TowerData[nextTowerName]

	return nextTowerName, nextTowerModel, nextTowerInfo
end

local function UpdateUpgradeDisplay(card, tower)
	local currentLevelLabel = FindTextObject(card, {"CurrentLevel", "TowerLevel"})
	local nextLevelLabel = FindTextObject(card, {"NextLevel"})
	local upgradeButton = FindGuiButton(card, {"UpgradeBtn"})
	local priceLabel = upgradeButton and FindTextObject(upgradeButton, {"Price"})
	local towerLevel = GetLevel(tower)
	local _, nextTowerModel, nextTowerInfo = GetNextTowerData(tower)

	if currentLevelLabel and currentLevelLabel.Name == "TowerLevel" then
		currentLevelLabel.Text = nextTowerModel
			and string.format("Lvl %d > Lvl %d", towerLevel, towerLevel + 1)
			or string.format("Lvl %d > MAX", towerLevel)
	elseif currentLevelLabel then
		currentLevelLabel.Text = "Lvl " .. towerLevel .. " >"
	end

	if nextLevelLabel then
		nextLevelLabel.Text = nextTowerModel and ("Lvl " .. (towerLevel + 1)) or "MAX"
	end

	if not upgradeButton then return end

	if nextTowerInfo then
		if priceLabel then
			priceLabel.Text = "$" .. (nextTowerInfo.Price or 0)
		elseif upgradeButton:IsA("TextButton") then
			upgradeButton.Text = "$" .. (nextTowerInfo.Price or 0)
		end

		upgradeButton.AutoButtonColor = true
		upgradeButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	else
		if priceLabel then
			priceLabel.Text = "MAX"
		elseif upgradeButton:IsA("TextButton") then
			upgradeButton.Text = "MAX"
		end

		upgradeButton.AutoButtonColor = false
		upgradeButton.BackgroundColor3 = Color3.fromRGB(90, 90, 90)
	end
end

local function UpdatePriorityDisplay(card, tower)
	local priorityLabel = FindTextObject(card, {"StateName", "Text"})
	if not priorityLabel then return end

	priorityLabel.Text = Priorities[GetPriorityIndex(tower)]
end

local function UpdateTowerCard(card, tower)
	if not card or not tower then return end

	card.Name = tower.Name

	local towerNameLabel = FindTextObject(card, {"TowerName"})
	local towerIcon = FindImageObject(card, {"TowerIcon"})

	if towerNameLabel then
		towerNameLabel.Text = GetBaseTowerName(tower)
	end

	if towerIcon and TowerData[tower.Name] then
		towerIcon.Image = "rbxassetid://" .. TowerData[tower.Name].ImageId
	end

	UpdateUpgradeDisplay(card, tower)
	UpdatePriorityDisplay(card, tower)
end

local function UpdateGameModeText()
	local gameModeText = FindTextObject(TowersFrame, {"GameModeTX"})
	if not gameModeText then return end

	local modeValue = workspace:GetAttribute("GameMode")
		or workspace:GetAttribute("Gamemode")
		or workspace:GetAttribute("Mode")
		or workspace:GetAttribute("Difficulty")

	if modeValue then
		gameModeText.Text = tostring(modeValue)
	end
end

local function ApplyTowersButtonVisibility()
	local towerInfo = MainUi:FindFirstChild("Tower_Info")
	TowersButton.Visible = not (TowersFrame.Visible or (towerInfo and towerInfo.Visible))
end

local function ClearTowerCards()
	for card in pairs(UnitsAssigned) do
		DisconnectCardConnections(card)
		UnitsAssigned[card] = nil

		if card and card.Parent then
			card:Destroy()
		end
	end
end

local function CreateTowerCard(model)
	if not TowersHolder or not ExampleTower then return end

	local newFrame = ExampleTower:Clone()
	newFrame.Parent = TowersHolder
	newFrame.Visible = true

	UpdateTowerCard(newFrame, model)
	UnitsAssigned[newFrame] = model

	local priorityLeftButton = FindGuiButton(newFrame, {"LeftButton", "Backward"})
	local priorityRightButton = FindGuiButton(newFrame, {"RightButton", "Forward"})
	local upgradeButton = FindGuiButton(newFrame, {"UpgradeBtn"})
	local sellButton = FindGuiButton(newFrame, {"Sell"})

	if upgradeButton then
		TrackConnection(newFrame, ConnectGuiButton(upgradeButton, function()
			if not model:IsDescendantOf(workspace) then return end

			local _, _, nextTowerInfo = GetNextTowerData(model)
			if not nextTowerInfo then return end

			ReplicatedStorage.Remotes.Game.Upgrade:FireServer(model)
			task.delay(.2, RequestSync)
		end))
	end

	if sellButton then
		TrackConnection(newFrame, ConnectGuiButton(sellButton, function()
			if not model:IsDescendantOf(workspace) then return end
			ReplicatedStorage.Remotes.Game.SellTower:FireServer(model)
			task.delay(.2, RequestSync)
		end))
	end

	local function ChangePriority(direction)
		if not model:IsDescendantOf(workspace) then return end

		local currentPriorityIndex = GetPriorityIndex(model)
		currentPriorityIndex += direction

		if currentPriorityIndex > #Priorities then
			currentPriorityIndex = 1
		elseif currentPriorityIndex < 1 then
			currentPriorityIndex = #Priorities
		end

		if typeof(model:GetAttribute("Priority")) == "string" then
			model:SetAttribute("Priority", Priorities[currentPriorityIndex])
		else
			model:SetAttribute("Priority", currentPriorityIndex)
		end

		UpdatePriorityDisplay(newFrame, model)
		ReplicatedStorage.Remotes.Building.Target:FireServer(model, currentPriorityIndex)
		task.delay(.1, RequestSync)
	end

	if priorityRightButton then
		TrackConnection(newFrame, ConnectGuiButton(priorityRightButton, function()
			ChangePriority(1)
		end))
	end

	if priorityLeftButton then
		TrackConnection(newFrame, ConnectGuiButton(priorityLeftButton, function()
			ChangePriority(-1)
		end))
	end

	TrackConnection(newFrame, model:GetAttributeChangedSignal("Priority"):Connect(function()
		if newFrame.Parent then
			UpdatePriorityDisplay(newFrame, model)
		end
	end))

	TrackConnection(newFrame, model:GetPropertyChangedSignal("Name"):Connect(function()
		if newFrame.Parent then
			UpdateTowerCard(newFrame, model)
		end
	end))
end

local function RemoveTowerCard(model)
	for card, assignedModel in pairs(UnitsAssigned) do
		if assignedModel == model then
			DisconnectCardConnections(card)
			UnitsAssigned[card] = nil

			if card and card.Parent then
				card:Destroy()
			end
		end
	end
end

SyncExistingTowers = function()
	if not TowersHolder or not ExampleTower then return end
	ClearTowerCards()

	for _, model in ipairs(Towers:GetChildren()) do
		if model:IsA("Model") and model:GetAttribute("Owner") == Player.UserId then
			CreateTowerCard(model)
		end
	end

	UpdateGameModeText()
end

RequestSync = function()
	if SyncQueued then return end

	SyncQueued = true

	task.defer(function()
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		SyncQueued = false

		TowersEnabled = TowersFrame.Visible
		ApplyTowersButtonVisibility()

		if TowersEnabled then
			SyncExistingTowers()
		end
	end)
end

local function ActionMenu()
	if Debounce then return end

	Debounce = true
	task.delay(.5, function()
		Debounce = false
	end)

	TowersFrame.Visible = not TowersFrame.Visible
end

function Handler.Init()
	if ExampleTower then
		ExampleTower.Visible = false
	end

	TowersEnabled = TowersFrame.Visible
	ApplyTowersButtonVisibility()

	TowersButton.MouseButton1Click:Connect(ActionMenu)

	if ExitButton then
		ExitButton.MouseButton1Click:Connect(ActionMenu)
	end

	Towers.ChildAdded:Connect(function(model)
		if not model:IsA("Model") then return end

		repeat task.wait() until model:GetAttribute("Owner") ~= nil or not model:IsDescendantOf(Towers)
		if not model:IsDescendantOf(Towers) then return end

		RequestSync()
	end)

	Towers.ChildRemoved:Connect(function(model)
		if not model:IsA("Model") then return end
		RequestSync()
	end)

	for _, attributeName in ipairs({"GameMode", "Gamemode", "Mode", "Difficulty"}) do
		workspace:GetAttributeChangedSignal(attributeName):Connect(function()
			UpdateGameModeText()
		end)
	end

	TowersFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		TowersEnabled = TowersFrame.Visible
		ApplyTowersButtonVisibility()

		if TowersEnabled then
			RequestSync()
		end
	end)

	if TowersEnabled then
		RequestSync()
	end
end

Handler.Init()

return Handler
