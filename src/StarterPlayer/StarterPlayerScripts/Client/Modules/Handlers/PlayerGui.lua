-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- CONSTANTS
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local GameRemotes = Remotes:FindFirstChild("Game")

local Player = Players.LocalPlayer
local PlayerGui = Player.PlayerGui

local Digits = require(ReplicatedStorage.Modules.Utility.Digits)
local TowerData = require(ReplicatedStorage.Modules.StoredData.TowerData)
local EnemyData = require(ReplicatedStorage.Modules.StoredData.EnemyData)
local SkillsData = require(ReplicatedStorage.Modules.StoredData.SkillsData)

local RecieveDialogueData = GameRemotes:FindFirstChild("SendDialogueData")
local RecieveSkipWave = GameRemotes:WaitForChild("SkipWave")

local MainGui = PlayerGui:WaitForChild("InGame_UI")
local TopUi = MainGui:WaitForChild("CenterTop")
local SkipWaveUi = TopUi:FindFirstChild("Skip", true)

-- VARIABLES
local Dialogue = {}
local LocalTowerSlots = {}
local refreshOwnedTowersUI

local selectedTower = nil
local lastHovered, activeCircle = nil, nil
local activeTimerId = 0
local statsShown = false

-- FUNCTIONS
local function sendNotification(text : string, type : string)
	local Notification = MainGui:WaitForChild("Notification")
	if not Notification then return end 

	local Template = Notification:WaitForChild("Template"):Clone()
	if not Template then return end 

	local TargetSize = UDim2.new(1, 0, 1.165, 0)
	local StartingSize = UDim2.new(0,0,0,0)

	Template.Text = text

	if type == "Error" then
		Template.TextColor3 = Color3.fromRGB(255, 0, 0)
	elseif type == "Normal" then
		Template.TextColor3 = Color3.fromRGB(255, 255, 255)
	elseif type == "Success" then
		Template.TextColor3 = Color3.fromRGB(0, 255, 0)
	end

	Template.Size = StartingSize

	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back)
	local tweenIn = TweenService:Create(Template, tweenInfo, { Size = TargetSize })
	local tweenOut = TweenService:Create(Template, tweenInfo, { Size = StartingSize })

	Template.Parent = Notification
	Template.Visible = true

	tweenIn:Play()

	task.spawn(function()
		task.wait(5)
		tweenOut:Play()
		tweenOut.Completed:Connect(function()
			Template:Destroy()
		end)
	end)
end

local function getUserData()
	local userData
	repeat
		userData = Player:FindFirstChild("UserData")
		if not userData then
			task.wait(0.1)
		end
	until userData
	return userData
end

local UserData = getUserData()
local StartingCash = 0
local StartingEXP = 0

if UserData then
	local moneyVal = UserData:FindFirstChild("Money")
	local expVal = UserData:FindFirstChild("EXP")
	StartingCash = moneyVal and moneyVal.Value or 0
	StartingEXP = expVal and expVal.Value or 0
end

local function setupButtonTween(Button)
	local Icon = Button:FindFirstChild("Icon")

	local rotationOnEnter = 15
	local rotationOnLeave = 0
	local enterScale = 1.05
	local downScale = 0.9
	local duration = 0.5

	local parent = Button
	local uiScale = parent:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = parent
	end

	local function tweenScale(toScale)
		TweenService:Create(uiScale, TweenInfo.new(0.1), { Scale = toScale }):Play()
	end

	Button.MouseEnter:Connect(function() tweenScale(enterScale) end)
	Button.MouseLeave:Connect(function() tweenScale(1) end)
	Button.MouseButton1Down:Connect(function() tweenScale(downScale) end)
	Button.MouseButton1Up:Connect(function() tweenScale(enterScale) end)
end

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function isTextObject(instance)
	return instance
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function findTextObject(root, names)
	if not root then return nil end

	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if isTextObject(found) then
			return found
		end
	end

	return nil
end

local function findGuiButton(root, names)
	if not root then return nil end

	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found then
			if found:IsA("GuiButton") then
				return found
			end

			local nestedButton = found:FindFirstChildWhichIsA("GuiButton", true)
			if nestedButton then
				return nestedButton
			end
		end
	end

	return nil
end

local function findImageObject(root, names)
	if not root then return nil end

	for _, name in ipairs(names) do
		local found = root:FindFirstChild(name, true)
		if found and (found:IsA("ImageLabel") or found:IsA("ImageButton")) then
			return found
		end
	end

	return nil
end

local function getTowerListUi()
	local towersFrame = MainGui:FindFirstChild("Towers")
	if not towersFrame or not towersFrame:IsA("Frame") then
		return nil
	end

	local towersBackground = towersFrame:FindFirstChild("TowersBG") or towersFrame
	local scrollingFrame = towersBackground:FindFirstChild("GridScrollingFrame")
		or towersFrame:FindFirstChild("GridScrollingFrame", true)
	local template = scrollingFrame and scrollingFrame:FindFirstChild("Template")

	return towersFrame, towersBackground, scrollingFrame, template
end

local function getTowersToggleButton()
	local centerLeft = MainGui:FindFirstChild("CenterLeft")
	return centerLeft and centerLeft:FindFirstChild("Towers")
end

local function syncTowersToggleVisibility()
	local towersButton = getTowersToggleButton()
	if not towersButton then return end

	local towersFrame = MainGui:FindFirstChild("Towers")
	local towerInfo = MainGui:FindFirstChild("Tower_Info")

	towersButton.Visible = not (
		(towersFrame and towersFrame.Visible)
			or (towerInfo and towerInfo.Visible)
	)
end

local function getCenterTopText(names)
	return findTextObject(TopUi, names)
end

local function getRoundDisplayText()
	local statsFrame = TopUi:FindFirstChild("Stats")
	local roundFrame = statsFrame and statsFrame:FindFirstChild("RoundBG", true)

	return findTextObject(roundFrame, {"RoundTX", "WaveTX", "Round"})
		or getCenterTopText({"RoundTX", "WaveTX", "Round"})
end

local function getCurrentWaveDisplayText()
	local waveFrame = TopUi:FindFirstChild("Wave")
	if not waveFrame then
		return nil
	end

	local waveText = findTextObject(waveFrame, {"WaveTX", "Text", "RoundTX", "Round"})
	if waveText then
		return waveText
	end

	for _, descendant in ipairs(waveFrame:GetDescendants()) do
		if isTextObject(descendant) then
			return descendant
		end
	end

	return nil
end

local function getGameSpeedButtons()
	local topRight = MainGui:FindFirstChild("TopRight")
	if not topRight then
		return {}
	end

	local container = topRight:FindFirstChild("Holder") or topRight
	local buttons = {}

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiButton") and child.Name:match("^x%d+$") then
			table.insert(buttons, child)
		end
	end

	return buttons
end

local function getTowerBaseAndLevel(towerName)
	local baseName, levelText = string.match(towerName, "^(.-)_(%d+)$")
	if baseName then
		return baseName, tonumber(levelText) or 1
	end

	return towerName, 1
end

local function getTowerUpgradeInfo(tower)
	local baseName, currentLevel = getTowerBaseAndLevel(tower.Name)
	local nextTowerName

	if tower.Name:match("_%d+$") then
		nextTowerName = baseName .. "_" .. (currentLevel + 1)
	else
		nextTowerName = tower.Name .. "_2"
	end

	local towerStorage = ReplicatedStorage:FindFirstChild("Storage")
	local towerFolder = towerStorage and towerStorage:FindFirstChild("Towers")
	local nextTower = towerFolder and towerFolder:FindFirstChild(nextTowerName)
	local nextUpgradeData = TowerData[nextTowerName]

	return baseName, currentLevel, nextTowerName, nextTower, nextUpgradeData
end

local function getPriorityIndex(tower, priorities)
	local attribute = tower and tower:GetAttribute("Priority")

	if typeof(attribute) == "number" then
		return math.clamp(attribute, 1, #priorities)
	end

	if typeof(attribute) == "string" then
		return table.find(priorities, attribute) or 1
	end

	return 1
end

local function updateUpgradeButton(button, nextUpgradeData)
	if not button then return end

	local priceLabel = findTextObject(button, {"Price"})

	if nextUpgradeData then
		if priceLabel then
			priceLabel.Text = "$" .. (nextUpgradeData.Price or 0)
		elseif button:IsA("TextButton") then
			button.Text = "$" .. (nextUpgradeData.Price or 0)
		end

		if button:IsA("GuiButton") then
			button.AutoButtonColor = true
			button.Active = true
		end
	else
		if priceLabel then
			priceLabel.Text = "MAX"
		elseif button:IsA("TextButton") then
			button.Text = "MAX"
		end

		if button:IsA("GuiButton") then
			button.AutoButtonColor = false
			button.Active = false
		end
	end
end

local function updateTowerGameModeText()
	local towersFrame = select(1, getTowerListUi())
	if not towersFrame then return end

	local gameModeText = findTextObject(towersFrame, {"GameModeTX"})
	if not gameModeText then return end

	gameModeText.Text = "Towers"
end

local function updateSpeedButtonState(button, isActive)
	local buttonLabel = findTextObject(button, {"Multiplier"})

	if buttonLabel then
		buttonLabel.TextColor3 = isActive and Color3.new(0, 1, 0) or Color3.new(1, 1, 1)
	elseif isTextObject(button) then
		button.TextColor3 = isActive and Color3.new(0, 1, 0) or Color3.new(1, 1, 1)
	end
end

local function typewriterEffect(label: TextLabel, text: string, delayPerChar: number)
	label.Text = ""
	local fullText = text
	local typing = true
	local skip = false

	local connection
	connection = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 
			or input.UserInputType == Enum.UserInputType.Touch then
			if typing then skip = true end
		end
	end)

	for i = 1, #fullText do
		if skip then
			label.Text = fullText
			break
		end
		label.Text = string.sub(fullText, 1, i)
		task.wait(delayPerChar)
	end

	typing = false
	connection:Disconnect()
end

local function showDialogue()
	local DialogueContainer = MainGui:WaitForChild("Tutorial")
	DialogueContainer.Visible = true

	local DialogueText = DialogueContainer:WaitForChild("DialogueText")
	local SpeakerName = DialogueContainer:WaitForChild("Speaker")
	local ContinueText = DialogueContainer:FindFirstChild("ContinueText")
	if ContinueText then ContinueText.Visible = false end

	for categoryName, dialogueSet in pairs(Dialogue) do
		local keys = {}
		for key in pairs(dialogueSet) do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tonumber(a:match("%d+")) < tonumber(b:match("%d+"))
		end)

		for _, key in ipairs(keys) do
			local dialogueData = dialogueSet[key]
			SpeakerName.Text = dialogueData.Speaker
			typewriterEffect(DialogueText, dialogueData.Text, 0.02)

			if ContinueText then ContinueText.Visible = true end

			local clicked = false
			local connection
			connection = UserInputService.InputBegan:Connect(function(input, gpe)
				if gpe then return end
				if input.UserInputType == Enum.UserInputType.MouseButton1 
					or input.UserInputType == Enum.UserInputType.Touch then
					clicked = true
				end
			end)

			repeat task.wait() until clicked
			connection:Disconnect()
			if ContinueText then ContinueText.Visible = false end
		end
	end

	DialogueContainer.Visible = false
end

local function updateStats()
	local CashText = MainGui:WaitForChild("Bottom"):WaitForChild("CashContainer"):WaitForChild("Frame"):WaitForChild("CashText")
	if not CashText then end

	Player:GetAttributeChangedSignal("TempCash"):Connect(function()
		CashText.Text = "$"..Digits.AddCommas(Player:GetAttribute("TempCash"))
	end)
end

local function hideAllFrames()
	local Frames = MainGui:FindFirstChild("Frames")
	if not Frames then return end

	for _, Frame in ipairs(Frames:GetChildren()) do
		if Frame:IsA("Frame") then
			Frame.Visible = false
		end
	end
end

local function toggleFrame(FrameName : string)
	local Frames = MainGui:FindFirstChild("Frames")
	local TargetFrame = Frames and Frames:FindFirstChild(FrameName)
		or MainGui:FindFirstChild(FrameName)
	if not TargetFrame then return end

	local closeButton = findGuiButton(TargetFrame, {"Close", "CloseBtn"})
	if closeButton then
		closeButton.MouseButton1Click:Connect(function()
			hideAllFrames()
			TargetFrame.Visible = false
		end)
	end

	hideAllFrames()
	TargetFrame.Visible = not TargetFrame.Visible
end

local function setupHotbarKeybinds()
	local UserData = getUserData()
	if not UserData then return end

	local Inventory = UserData:FindFirstChild("Hotbar")
	if not Inventory then return end

	local Hotbar = MainGui:WaitForChild("Bottom"):WaitForChild("Hotbar")
	if not Hotbar then return end

	local keyMap = {
		[Enum.KeyCode.One] = "1",
		[Enum.KeyCode.Two] = "2",
		[Enum.KeyCode.Three] = "3",
		[Enum.KeyCode.Four] = "4",
		[Enum.KeyCode.Five] = "5",
		[Enum.KeyCode.Six] = "6"
	}

	local function tweenButtonScale(button: ImageButton, targetScale: number)
		local uiScale = button:FindFirstChildOfClass("UIScale")
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Scale = 1
			uiScale.Parent = button
		end

		TweenService:Create(uiScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = targetScale
		}):Play()
	end

	local lastPressedSlot = nil

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		local slotName = keyMap[input.KeyCode]
		if not slotName then return end

		if lastPressedSlot == slotName then
			lastPressedSlot = nil
			Remotes.Building.Cancel:Fire()
			return
		end

		lastPressedSlot = slotName

		local Button = Hotbar:FindFirstChild(slotName)
		if Button then
			Remotes.Audio.ClientToClient:Fire("ClickSoundEffect")
			tweenButtonScale(Button, 0.9)
		end
		ReplicatedStorage.Remotes.Building.ClientRequest:Fire(slotName)
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

		local slotName = keyMap[input.KeyCode]
		if not slotName then return end

		local Button = Hotbar:FindFirstChild(slotName)
		if Button then tweenButtonScale(Button, 1) end
	end)

	local hotbarSlots = { "1", "2", "3", "4", "5", "6" }

	local function setSlot(slotName)
		if lastPressedSlot == slotName then
			lastPressedSlot = nil
			Remotes.Building.Cancel:Fire()
			return
		end
		lastPressedSlot = slotName

		local Button = Hotbar:FindFirstChild(slotName)
		if Button then
			Remotes.Audio.ClientToClient:Fire("ClickSoundEffect")
			tweenButtonScale(Button, 0.9)
		end
		ReplicatedStorage.Remotes.Building.ClientRequest:Fire(slotName)
	end

	local function getNextSlot(direction)
		local available = {}
		for _, slot in ipairs(hotbarSlots) do
			local btn = Hotbar:FindFirstChild(slot)
			if btn and btn.Visible then
				table.insert(available, slot)
			end
		end
		if #available == 0 then return end

		local currentIndex = table.find(available, lastPressedSlot)
		if not currentIndex then 
			currentIndex = 1 
		else
			currentIndex += direction
			if currentIndex > #available then currentIndex = 1 end
			if currentIndex < 1 then currentIndex = #available end
		end
		return available[currentIndex]
	end

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.ButtonL1 then
			local nextSlot = getNextSlot(-1)
			if nextSlot then setSlot(nextSlot) end
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode == Enum.KeyCode.ButtonR1 then
			local nextSlot = getNextSlot(1)
			if nextSlot then setSlot(nextSlot) end
		end
	end)
end

local function setupHotbar()
	local TowerDataReq = require(ReplicatedStorage.Modules.StoredData.TowerData)

	local UserData = getUserData()
	if not UserData then return end

	local Level = UserData:FindFirstChild("Level")
	if not Level then return end

	local InventoryFolder = UserData:FindFirstChild("Hotbar")
	if not InventoryFolder then return end

	local HotBar = MainGui:WaitForChild("Bottom"):WaitForChild("Hotbar")
	if not HotBar then return end

	if Level.Value >= 15 then
		local Level15 = HotBar:WaitForChild("Level15")
		if not Level15 then return end 

		local Level9 = HotBar:WaitForChild("Level9")
		if not Level9 then return end 

		local Slot5 = HotBar:WaitForChild("5")
		if not Slot5 then return end 

		local Slot6 = HotBar:WaitForChild("6")
		if not Slot6 then return end

		Level15.Visible = false
		Level9.Visible = false

		Slot5.Visible = true
		Slot6.Visible = true
	elseif Level.Value >= 10 then
		local Level9 = HotBar:WaitForChild("Level9")
		if not Level9 then return end 

		local Slot5 = HotBar:WaitForChild("5")
		if not Slot5 then return end 

		Level9.Visible = false
		Slot5.Visible = true
	end

	for _, Slot in ipairs(InventoryFolder:GetChildren()) do
		local SlotNumber = Slot.Name
		if not SlotNumber then continue end

		local UISlot = HotBar:FindFirstChild(SlotNumber)
		if not UISlot then continue end

		-- Garantimos que se o SkillButton ainda existir fisicamente na UI, ele fique invisível
		local SkillButton = UISlot:FindFirstChild("SkillButton")
		if SkillButton then
			SkillButton.Visible = false
		end

		if Slot.Value == "" then 
			UISlot.Holder.Visible = false
			continue 
		end

		LocalTowerSlots[Slot.Value] = UISlot

		local ImageId = TowerDataReq[Slot.Value].ImageId
		if not ImageId then continue end

		local Price = TowerDataReq[Slot.Value].Price
		if not Price then continue end

		local UnitIcon : ImageLabel = UISlot:FindFirstChild("UnitIcon")
		if not UnitIcon then continue end

		UnitIcon.Image = "rbxassetid://"..ImageId
		UISlot:FindFirstChild("Holder"):FindFirstChild("Price").Text = "$"..Price
		UISlot:FindFirstChild("Holder").Visible = true
	end
end

local function setupButtons()
	for _, Button in ipairs(MainGui:GetDescendants()) do
		if Button:IsA("ImageButton") then
			local frameName = Button:GetAttribute("FrameName")
			local isTowersToggle = frameName == "Towers"
				or Button.Name == "Towers"
				or (Button.Parent and Button.Parent.Name == "Towers")

			setupButtonTween(Button)

			if isTowersToggle then
				continue
			end

			Button.MouseButton1Click:Connect(function()
				Remotes.Audio.ClientToClient:Fire("ClickSoundEffect")
				if Button.Name == "Level9" then
					sendNotification("You must be level 10 to unlock.", "Error")
				elseif Button.Name == "Level15" then
					sendNotification("You must be level 15 to unlock.", "Error")
				end

				if Button.Parent.Name == "Hotbar" then
					ReplicatedStorage.Remotes.Building.ClientRequest:Fire(Button.Name)
				else
					if not frameName then return end
					toggleFrame(frameName)
				end
			end)
		end
	end
end

local function closeTowerInfo()
	local TowerInfo = MainGui:FindFirstChild("Tower_Info")
	if TowerInfo then
		TowerInfo.Visible = false
	end

	selectedTower = nil

	for _, Circle in ipairs(workspace:GetDescendants()) do
		if Circle:IsA("BasePart") and Circle.Name == "BlueCircle" then
			activeCircle = nil
			Circle:Destroy()
		end
	end

	syncTowersToggleVisibility()
end

local function handleClientTowers()
	local mouse = Player:GetMouse()
	local PlacedTowersFolder = workspace:FindFirstChild("Towers")
	if not PlacedTowersFolder then return end

	local BlueCircleTemplate = ReplicatedStorage.Storage.Circles:FindFirstChild("BlueCircle")
	if not BlueCircleTemplate then return end

	local TweenInfoExpand = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local TweenInfoShrink = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local TowerInfo = MainGui:FindFirstChild("Tower_Info")
	local TowerSecondaryInfo = MainGui:FindFirstChild("Tower_Secondary_Info")
	local TowersFrame = select(1, getTowerListUi())

	local SellButtonConn, UpgradeButtonConn, CloseButtonConn
	local PriorityForwardConn, PriorityBackwardConn

	local function updateTowersButtonVisibility()
		syncTowersToggleVisibility()
	end

	local function clearActiveCircle(animated)
		if not activeCircle then return end

		local circle = activeCircle
		activeCircle = nil

		if animated then
			local shrinkTween = TweenService:Create(circle, TweenInfoShrink, {
				Size = Vector3.new(0.01, 0.01, 0.01)
			})
			shrinkTween:Play()

			task.delay(0.15, function()
				if circle and circle.Parent then
					circle:Destroy()
				end
			end)
		else
			circle:Destroy()
		end
	end

	local function refreshTowerPriorityButtons(forwardButton, backwardButton, displayText, tower)
		disconnectConnection(PriorityForwardConn)
		disconnectConnection(PriorityBackwardConn)

		local priorities = {"First", "Last", "Closest"}
		local currentPriorityIndex = getPriorityIndex(tower, priorities)

		if displayText then
			displayText.Text = priorities[currentPriorityIndex]
		end

		local function changePriority(direction)
			if not tower or not tower:IsDescendantOf(workspace) then
				return
			end

			currentPriorityIndex += direction

			if currentPriorityIndex > #priorities then
				currentPriorityIndex = 1
			elseif currentPriorityIndex < 1 then
				currentPriorityIndex = #priorities
			end

			if displayText then
				displayText.Text = priorities[currentPriorityIndex]
			end

			tower:SetAttribute("Priority", currentPriorityIndex)
			Remotes.Building.Target:FireServer(tower, currentPriorityIndex)
		end

		if forwardButton then
			PriorityForwardConn = forwardButton.MouseButton1Click:Connect(function()
				changePriority(1)
			end)
		end

		if backwardButton then
			PriorityBackwardConn = backwardButton.MouseButton1Click:Connect(function()
				changePriority(-1)
			end)
		end
	end

	local function showTowerRangeCircle(tower)
		clearActiveCircle(false)

		if not tower or not tower.PrimaryPart then return end

		local towerRange = tower:GetAttribute("Range") or 0
		activeCircle = BlueCircleTemplate:Clone()
		activeCircle.Anchored = true
		activeCircle.CanCollide = false
		activeCircle.CanQuery = false
		activeCircle.Parent = workspace
		activeCircle.CFrame = tower.PrimaryPart.CFrame
			* CFrame.new(0, -tower.PrimaryPart.Size.Y / 2, 0)
			* CFrame.Angles(0, math.rad(-90), math.rad(90))
		activeCircle.Size = Vector3.new(0.01, 0.01, 0.01)

		local targetSize = Vector3.new(0.375, towerRange * 2, towerRange * 2)
		TweenService:Create(activeCircle, TweenInfoExpand, {Size = targetSize}):Play()
	end

	local function cleanupLegacyInfo()
		clearActiveCircle(true)
		disconnectConnection(SellButtonConn)
		disconnectConnection(UpgradeButtonConn)
		disconnectConnection(CloseButtonConn)
		disconnectConnection(PriorityForwardConn)
		disconnectConnection(PriorityBackwardConn)

		if TowerInfo then
			TowerInfo.Visible = false
		end

		selectedTower = nil
		updateTowersButtonVisibility()
	end

	local function populateLegacyTowerInfo(tower)
		if not TowerInfo then
			return
		end

		local foundData = TowerData[tower.Name]
		if not foundData then return end

		local statsFrame = TowerInfo:FindFirstChild("Stats")
		local damageFrame = statsFrame and statsFrame:FindFirstChild("Damage")
		local rangeFrame = statsFrame and statsFrame:FindFirstChild("Range")
		local rateFrame = statsFrame and statsFrame:FindFirstChild("Rate")
		local upgradeFrame = TowerInfo:FindFirstChild("Upgrade")
		local priorityFrame = TowerInfo:FindFirstChild("Priority")
		local buttonHolder = TowerInfo:FindFirstChild("ButtonHolder")

		local towerIcon = findImageObject(TowerInfo, {"TowerIcon"})
		local towerNameText = findTextObject(TowerInfo, {"TowerName"})
		local damageStat = damageFrame and damageFrame:FindFirstChild("Stat")
		local rangeStat = rangeFrame and rangeFrame:FindFirstChild("Stat")
		local rateStat = rateFrame and rateFrame:FindFirstChild("Stat")
		local nextDamage = damageFrame and damageFrame:FindFirstChild("Stat2")
		local nextRange = rangeFrame and rangeFrame:FindFirstChild("Stat2")
		local nextRate = rateFrame and rateFrame:FindFirstChild("Stat2")
		local currentLevelText = upgradeFrame and findTextObject(upgradeFrame, {"CurrentLevel"})
		local nextLevelText = upgradeFrame and findTextObject(upgradeFrame, {"NextLevel"})
		local upgradeButton = upgradeFrame and findGuiButton(upgradeFrame, {"UpgradeBtn"})
		local sellButton = buttonHolder and findGuiButton(buttonHolder, {"Sell"})
		local closeButton = buttonHolder and findGuiButton(buttonHolder, {"CloseBtn", "Close"})
		local priorityForwardButton = priorityFrame and findGuiButton(priorityFrame, {"Forward", "RightButton"})
		local priorityBackwardButton = priorityFrame and findGuiButton(priorityFrame, {"Backward", "LeftButton"})
		local priorityDisplayText = priorityFrame and findTextObject(priorityFrame, {"Text", "StateName"})

		local baseName, currentLevel, _, nextTower, nextUpgradeData = getTowerUpgradeInfo(tower)

		if towerIcon and foundData.ImageId then
			towerIcon.Image = "rbxassetid://" .. foundData.ImageId
		end

		if towerNameText then
			towerNameText.Text = baseName
		end

		if damageStat then
			damageStat.Text = tostring(tower:GetAttribute("Damage") or 0)
		end

		if rangeStat then
			rangeStat.Text = tostring(tower:GetAttribute("Range") or 0)
		end

		if rateStat then
			rateStat.Text = tostring(tower:GetAttribute("AttackCooldown") or 0)
		end

		if nextTower then
			if nextDamage then
				nextDamage.Text = tostring(nextTower:GetAttribute("Damage") or "Max")
			end

			if nextRange then
				nextRange.Text = tostring(nextTower:GetAttribute("Range") or "Max")
			end

			if nextRate then
				nextRate.Text = tostring(nextTower:GetAttribute("AttackCooldown") or "Max")
			end
		else
			if nextDamage then
				nextDamage.Text = "Max"
			end

			if nextRange then
				nextRange.Text = "Max"
			end

			if nextRate then
				nextRate.Text = "Max"
			end
		end

		updateUpgradeButton(upgradeButton, nextUpgradeData)

		if currentLevelText then
			currentLevelText.Text = "Lvl " .. currentLevel .. " >"
		end

		if nextLevelText then
			nextLevelText.Text = nextTower and ("Lvl " .. (currentLevel + 1)) or "MAX"
		end

		showTowerRangeCircle(tower)

		TowerInfo.Visible = true

		if TowersFrame then
			TowersFrame.Visible = false
		end
		updateTowersButtonVisibility()

		Remotes.Audio.ClientToClient:Fire("ClickSoundEffect")

		disconnectConnection(SellButtonConn)
		disconnectConnection(UpgradeButtonConn)
		disconnectConnection(CloseButtonConn)

		if sellButton then
			SellButtonConn = sellButton.MouseButton1Click:Connect(function()
				Remotes.Game.SellTower:FireServer(selectedTower)
				cleanupLegacyInfo()
			end)
		end

		if upgradeButton then
			UpgradeButtonConn = upgradeButton.MouseButton1Click:Connect(function()
				Remotes.Game.Upgrade:FireServer(selectedTower)
				cleanupLegacyInfo()
			end)
		end

		if closeButton then
			CloseButtonConn = closeButton.MouseButton1Click:Connect(function()
				cleanupLegacyInfo()
			end)
		end

		refreshTowerPriorityButtons(priorityForwardButton, priorityBackwardButton, priorityDisplayText, tower)
	end

	local function openTowerDetails(tower)
		if not tower or not tower:IsDescendantOf(workspace) then return end

		local ownerId = tower:GetAttribute("Owner")
		if ownerId ~= Player.UserId then
			sendNotification("This is not your Tower", "Error")
			return
		end

		selectedTower = tower
		populateLegacyTowerInfo(tower)

		if not TowerInfo then
			showTowerRangeCircle(tower)
		end
	end

	refreshOwnedTowersUI = nil

	mouse.Move:Connect(function()
		local target = mouse.Target
		local hoveredTower = nil

		if target then
			for _, tower in ipairs(PlacedTowersFolder:GetChildren()) do
				if tower:IsA("Model") and tower.PrimaryPart == target then
					hoveredTower = tower
					break
				end
			end
		end

		if hoveredTower ~= lastHovered then
			if lastHovered then
				for _, highlight in ipairs(lastHovered:GetDescendants()) do
					if highlight:IsA("Highlight") then
						highlight:Destroy()
					end
				end
				if TowerSecondaryInfo then
					TowerSecondaryInfo.Visible = false
				end
			end

			if hoveredTower then
				local range = hoveredTower:GetAttribute("Range")
				if range then
					local highlight = Instance.new("Highlight")
					highlight.Name = "temp"
					highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
					highlight.FillColor = Color3.fromRGB(255, 255, 255)
					highlight.FillTransparency = 0.5
					highlight.Parent = hoveredTower

					Remotes.Audio.ClientToClient:Fire("Hover")

					if TowerSecondaryInfo then
						local ownerPlayer = Players:GetPlayerByUserId(hoveredTower:GetAttribute("Owner"))
						local towerNameLabel = TowerSecondaryInfo:FindFirstChild("Tower_Name")
						local towerUserLabel = TowerSecondaryInfo:FindFirstChild("Tower_User")
						TowerSecondaryInfo.Visible = true
						if towerNameLabel then
							towerNameLabel.Text = hoveredTower.Name:gsub("[%d_]", "")
						end
						if towerUserLabel then
							towerUserLabel.Text = ownerPlayer and ("@" .. ownerPlayer.Name) or "@Unknown"
						end
					end
				end
			end

			lastHovered = hoveredTower
		end
	end)

	mouse.Button1Down:Connect(function()
		local target = mouse.Target
		if not target then return end

		for _, tower in ipairs(PlacedTowersFolder:GetChildren()) do
			if tower:IsA("Model") and target:IsDescendantOf(tower) then
				openTowerDetails(tower)
				return
			end
		end

		clearActiveCircle(true)
		selectedTower = nil

		if TowerInfo then
			TowerInfo.Visible = false
		end
		updateTowersButtonVisibility()
	end)

	if TowersFrame then
		TowersFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			updateTowersButtonVisibility()
		end)
	end

	GameRemotes:WaitForChild("ReEnableInfo").OnClientEvent:Connect(function(tower)
		if TowersFrame and TowersFrame.Visible then
			return
		end

		if tower then
			openTowerDetails(tower)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not selectedTower then return end

		if input.KeyCode == Enum.KeyCode.X then
			Remotes.Game.SellTower:FireServer(selectedTower)
			if TowerInfo then
				TowerInfo.Visible = false
			end
			clearActiveCircle(true)
			selectedTower = nil
			updateTowersButtonVisibility()
		elseif input.KeyCode == Enum.KeyCode.E then
			Remotes.Game.Upgrade:FireServer(selectedTower)
			if TowerInfo then
				TowerInfo.Visible = false
			end
			clearActiveCircle(true)
			selectedTower = nil
			updateTowersButtonVisibility()
		end
	end)

	if TowerInfo then
		TowerInfo:GetPropertyChangedSignal("Visible"):Connect(function()
			if TowersFrame and TowersFrame.Visible and TowerInfo.Visible then
				TowersFrame.Visible = false
			end

			updateTowersButtonVisibility()
		end)
	end
end

local function hideAll()
	for _, Frame in ipairs(MainGui:GetChildren()) do
		if Frame:IsA("Frame") then
			Frame.Visible = false
		end
	end
end

-- INIT
local function init()
	updateStats()
	setupButtons()
	setupHotbar()
	handleClientTowers()
	setupHotbarKeybinds()
end

if Player then
	init()
end

RecieveDialogueData.OnClientEvent:Connect(function(Data)
	Dialogue = Data
	task.wait()
	showDialogue()
end)

local lastMaxRound = 0
local INFINITY_SYMBOL = utf8.char(8734)

local function setRoundText(CurrentRound, MaxRound)
	local currentWaveText = getCurrentWaveDisplayText()
	local roundText = getRoundDisplayText()
	if not roundText and not currentWaveText then
		return
	end

	local currentRound = math.max(0, math.floor(tonumber(CurrentRound) or 0))
	local resolvedMaxRound = MaxRound

	if resolvedMaxRound == nil then
		resolvedMaxRound = workspace:GetAttribute("TotalWaves")
	end

	if resolvedMaxRound == nil then
		resolvedMaxRound = lastMaxRound
	end

	if resolvedMaxRound == nil then
		return
	end

	lastMaxRound = resolvedMaxRound

	if currentWaveText then
		local waveFrame = TopUi:FindFirstChild("Wave")
		if waveFrame and waveFrame:IsA("GuiObject") then
			waveFrame.Visible = true
		end
		currentWaveText.Text = string.format("%02d", currentRound)
	end

	if roundText then
		if resolvedMaxRound == "Endless" then
			roundText.Text = string.format("%02d/%s", currentRound, INFINITY_SYMBOL)
			return
		end

		local maxRound = math.floor(tonumber(resolvedMaxRound) or 0)
		if maxRound <= 0 then
			return
		end

		roundText.Text = string.format("%02d/%02d", currentRound, maxRound)
	end
end

Remotes.Game.DisplayRound.OnClientEvent:Connect(function(CurrentRound, MaxRound)
	setRoundText(CurrentRound, MaxRound)
end)

workspace:GetAttributeChangedSignal("CurrentWave"):Connect(function()
	setRoundText(workspace:GetAttribute("CurrentWave") or 0, workspace:GetAttribute("TotalWaves") or lastMaxRound)
end)

workspace:GetAttributeChangedSignal("TotalWaves"):Connect(function()
	setRoundText(workspace:GetAttribute("CurrentWave") or 0, workspace:GetAttribute("TotalWaves") or lastMaxRound)
end)

Remotes.Game.SendNotification.OnClientEvent:Connect(function(Text, Type)
	sendNotification(Text, Type)
end)

setRoundText(workspace:GetAttribute("CurrentWave") or 0, workspace:GetAttribute("TotalWaves") or lastMaxRound)

local function setTimerText(secondsRemaining: number)
	local Timer = getCenterTopText({"TimeTX", "Timer"})
	if not Timer then return end

	local remaining = math.max(0, math.floor(tonumber(secondsRemaining) or 0))
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	Timer.Text = string.format("%02d:%02d", minutes, seconds)
end

Remotes.Game.StartTimer.OnClientEvent:Connect(function(maxTime : number)
	activeTimerId += 1
	local thisTimerId = activeTimerId

	task.spawn(function()
		local remaining = maxTime
		while remaining >= 0 do
			if thisTimerId ~= activeTimerId then return end
			setTimerText(remaining)
			task.wait(1)
			remaining -= 1
		end
	end)
end)

workspace:GetAttributeChangedSignal("Timer"):Connect(function()
	activeTimerId += 1
	setTimerText(workspace:GetAttribute("Timer") or 0)
end)

workspace:WaitForChild("Enemies").ChildAdded:Connect(function(Model)
	if EnemyData[Model.Name] and EnemyData[Model.Name].Boss then
		local NewExample = MainGui.Boss_HP.Example:Clone()
		NewExample.Parent = MainGui.Boss_HP
		NewExample.Visible = true
		NewExample.ImageLabel.Image = EnemyData[Model.Name].ImageId
		NewExample.Tower_Name.Text = Model.Name

		local Humanoid = Model:WaitForChild("Humanoid", 5)
		if not Humanoid then
			NewExample:Destroy()
			return
		end

		local MaxHealth = Humanoid.MaxHealth
		local OriginalBarColor = NewExample.Bar.BackgroundColor3

		NewExample.HP.Text = Humanoid.Health.. "/".. MaxHealth
		NewExample.Bar.Size = UDim2.new(0, 0, 1, 0)

		TweenService:Create(NewExample.Bar, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()

		local function pulseBar()
			local scaleY = NewExample.Bar:FindFirstChildOfClass("UIScale")
			if not scaleY then
				scaleY = Instance.new("UIScale")
				scaleY.Parent = NewExample.Bar
			end

			TweenService:Create(NewExample.Bar, TweenInfo.new(0.05), {
				BackgroundColor3 = Color3.new(1, 1, 1)
			}):Play()

			TweenService:Create(scaleY, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Scale = 1.15
			}):Play()

			task.delay(0.08, function()
				TweenService:Create(scaleY, TweenInfo.new(0.15, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
					Scale = 1
				}):Play()

				TweenService:Create(NewExample.Bar, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					BackgroundColor3 = OriginalBarColor
				}):Play()
			end)
		end

		local previousHealth = Humanoid.Health

		Humanoid:GetPropertyChangedSignal("Health"):Connect(function()
			local currentHealth = Humanoid.Health
			local healthPercent = math.clamp(currentHealth / MaxHealth, 0, 1)

			NewExample.HP.Text = math.floor(currentHealth).. "/".. MaxHealth

			TweenService:Create(NewExample.Bar, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = UDim2.new(healthPercent, 0, 1, 0)
			}):Play()

			if currentHealth < previousHealth then
				pulseBar()
			end
			previousHealth = currentHealth
		end)

		Humanoid.Died:Connect(function()
			NewExample.HP.Text = "0/".. MaxHealth
			TweenService:Create(NewExample.Bar, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = UDim2.new(0, 0, 1, 0)
			}):Play()
			task.wait(0.5)
			TweenService:Create(NewExample, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0)
			}):Play()
			task.wait(0.3)
			NewExample:Destroy()
		end)

		Model.AncestryChanged:Connect(function()
			if not Model:IsDescendantOf(workspace) then
				NewExample.HP.Text = "0/".. MaxHealth
				TweenService:Create(NewExample.Bar, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Size = UDim2.new(0, 0, 1, 0)
				}):Play()
				task.wait(0.5)
				TweenService:Create(NewExample, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Size = UDim2.new(0, 0, 0, 0)
				}):Play()
				task.wait(0.3)
				NewExample:Destroy()
			end
		end)
	end
end)

Remotes.Game.ShowResults.OnClientEvent:Connect(function(roundsPlayed, formattedTime, Type)
	local radius = 35
	local heightoffset = 0
	local speed = .2

	if statsShown == true then return end
	statsShown = true

	local Camera = workspace.Camera
	if not Camera then return end

	local CenterPart = workspace:FindFirstChild("CenterPart")
	if not CenterPart then return end 

	local UserData = getUserData()
	if not UserData then return end

	local CurrentCash = UserData:FindFirstChild("Money")
	if not CurrentCash then return end

	local CurrentXP = UserData:FindFirstChild("EXP")
	if not CurrentXP then return end

	local ResultsFrame = MainGui:WaitForChild("End_Result")
	if not ResultsFrame then return end 

	local Title = ResultsFrame:FindFirstChild("End_Result"):FindFirstChild("Title")
	if not Title then return end

	local TimeText = ResultsFrame:WaitForChild("End_Result"):WaitForChild("ButtonHolder"):WaitForChild("Time"):WaitForChild("Amount")
	if not TimeText then return end

	local Rounds = ResultsFrame:WaitForChild("End_Result"):WaitForChild("ButtonHolder"):WaitForChild("Rounds"):WaitForChild("Amount")
	if not Rounds then return end

	local Rewards = ResultsFrame:WaitForChild("End_Result"):WaitForChild("ButtonHolder"):WaitForChild("Reward")
	if not Rewards then return end

	local ReturnButton = ResultsFrame:WaitForChild("End_Result"):WaitForChild("ButtonHolder2"):WaitForChild("Return")
	if not ReturnButton then return end

	local CashAmount = Rewards:WaitForChild("CashAmount")
	local XPAmount = Rewards:WaitForChild("XPAmount")

	local CashGained = CurrentCash.Value - StartingCash
	local EXPGained = CurrentXP.Value - StartingEXP

	for _, Frame in ipairs(MainGui:GetChildren()) do
		if Frame:IsA("Frame") then
			Frame.Visible = false
		end
	end

	if Type == "Won" then
		Title.Text = "You Won!"
		Remotes.Audio.ClientToClient:Fire("WinRound")
		Title.TextColor3 = Color3.fromRGB(0, 255, 0)
	elseif Type == "Lost" then
		Title.Text = "You Lost!"
		Remotes.Audio.ClientToClient:Fire("EndDefeat")
		Title.TextColor3 = Color3.fromRGB(255, 0, 0)
	end

	TimeText.Text = formattedTime
	Rounds.Text = roundsPlayed
	CashAmount.Text = "+$"..CashGained
	XPAmount.Text = "+"..EXPGained

	ReturnButton.MouseButton1Click:Connect(function()
		ReturnButton.MainText.Text = "Teleporting"
		Remotes.Game.ReturnToLobby:FireServer(Type == "Won")
	end)

	hideAll()
	ResultsFrame.Visible = true

	local originalCameraType = Camera.CameraType
	Camera.CameraType = Enum.CameraType.Scriptable

	local angle = 0
	local isOrbiting = true

	local orbitConnection
	orbitConnection = game:GetService("RunService").RenderStepped:Connect(function(delta)
		if not isOrbiting or not CenterPart then
			orbitConnection:Disconnect()
			Camera.CameraType = originalCameraType
			return
		end
		angle = angle + speed * delta
		local x = CenterPart.Position.X + radius * math.cos(angle)
		local z = CenterPart.Position.Z + radius * math.sin(angle)
		local y = CenterPart.Position.Y + heightoffset
		local newPosition = Vector3.new(x, y, z)
		Camera.CFrame = CFrame.new(newPosition, CenterPart.Position + Vector3.new(0, heightoffset, 0))
	end)
end)

Remotes.Game.UpdateHealthbar.OnClientEvent:Connect(function(currentHealth, maxHealth)
	local HealthBar = MainGui:WaitForChild("CenterTop"):WaitForChild("GameStats")
	if not HealthBar then return end

	local Bar = HealthBar:WaitForChild("Bar")
	if not Bar then return end

	local HPText = HealthBar:WaitForChild("HP")
	if not HPText then return end

	local Percentage = math.clamp(currentHealth / maxHealth, 0, 1)
	local newSize = UDim2.new(Percentage, 0, 1, 0)

	local TweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(Bar, tweenInfo, {Size = newSize}):Play()

	HPText.Text = currentHealth .. "/" .. maxHealth

	local originalSize = HealthBar.Size
	local biggerSize = UDim2.new(originalSize.X.Scale * 1.05, 0, originalSize.Y.Scale * 1.05, 0)

	local popTweenOut = TweenService:Create(HealthBar, TweenInfo.new(0.125, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = biggerSize
	})

	local popTweenIn = TweenService:Create(HealthBar, TweenInfo.new(0.125, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = originalSize
	})

	popTweenOut:Play()
	popTweenOut.Completed:Connect(function()
		popTweenIn:Play()
	end)
end)

Remotes.Building.CloseTowerInfo.Event:Connect(function()
	closeTowerInfo()
end)

local MarketplaceService = game:GetService("MarketplaceService")

local function syncGameSpeedButtons()
	local activeSpeed = tostring(workspace:GetAttribute("GameSpeed") or 1)
	if not activeSpeed:match("^x") then
		activeSpeed = "x" .. activeSpeed
	end

	for _, button in ipairs(getGameSpeedButtons()) do
		updateSpeedButtonState(button, button.Name == activeSpeed)
	end
end

workspace:GetAttributeChangedSignal("GameSpeed"):Connect(syncGameSpeedButtons)
syncGameSpeedButtons()

for _, button in ipairs(getGameSpeedButtons()) do
	button.MouseButton1Click:Connect(function()
		if button.Name == "x3" then
			if not MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 1616584704) then
				MarketplaceService:PromptGamePassPurchase(Player, 1616584704)
				return
			end
		end

		GameRemotes.GameSpeed:FireServer(button.Name)
	end)
end

local Timer = 5

RecieveSkipWave.OnClientEvent:Connect(function()
	if not SkipWaveUi then return end

	local SkipTimerText = findTextObject(SkipWaveUi, {"Timer"})
	SkipWaveUi.Visible = true
	Timer = 5
	while Timer > 0 do
		if SkipTimerText then
			SkipTimerText.Text = Timer .. "s"
		end
		task.wait(1) 
		Timer -= 1
	end
	if Timer <= 0 then
		SkipWaveUi.Visible = false
	end
end)

if SkipWaveUi then
	SkipWaveUi.MouseButton1Click:Connect(function()
		SkipWaveUi.Visible = false
		RecieveSkipWave:FireServer()
	end)
end

return {}
