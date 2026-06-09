-- // services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

-- // variables
local LocalPlayer = Players.LocalPlayer
local TowerStorage = ReplicatedStorage:FindFirstChild("Storage"):FindFirstChild("Towers")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local PlayerGui = LocalPlayer.PlayerGui
local MainGui = PlayerGui:WaitForChild("InGame_UI")
local MobileButtons = MainGui:WaitForChild("MobileButtons")
local MobilePlace = MobileButtons:WaitForChild("Place")
local MobileRotate = MobileButtons:WaitForChild("Rotate")
local MobileCancel = MobileButtons:WaitForChild("Cancel")

-- // states
local ROTATE_COOLDOWN = false
local IS_BUILDING = false
local BUILD_CONNECTION
local SELECTED_TOWER
local IS_MOBILE = UserInputService.TouchEnabled
local InputConn
local ClickConn
local LAST_VALID_PLACEMENT = false

local TAG_DESTRUCTIBLE_ROUTE = "DestructibleRoute"
local TAG_DESTRUCTIBLE_TOWER_SPOT = "DestructibleTowerSpot"
local TAG_DEBRIS = "DestructionDebris"

-- // console-specific state
local USING_GAMEPAD = false
local CONSOLE_PLACE_DISTANCE = 15
local CONSOLE_MOVE_SPEED = 20
local consoleMoveOffset = Vector3.new(0, 0, 0)

-- // helper to check if a surface is valid for placement
local function isValidPlacementSurface(instance)
	if not instance then
		return false
	end

	if instance:IsA("Terrain") then
		return true
	end

	if not instance:IsA("BasePart") then
		return false
	end

	if instance:GetAttribute("Destroyed") or CollectionService:HasTag(instance, TAG_DEBRIS) then
		return false
	end

	if instance == workspace.Baseplate then
		return true
	end

	return CollectionService:HasTag(instance, TAG_DESTRUCTIBLE_TOWER_SPOT)
end

-- // functions
local function canPlace(position: Vector3, rotation: number, size: Vector3): boolean
	-- checks if anything is overlapping htat position
	local cf = CFrame.new(position) * CFrame.Angles(0, math.rad(rotation), 0)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Blacklist
	overlapParams.FilterDescendantsInstances = {SELECTED_TOWER, LocalPlayer.Character}

	local partsInRegion = workspace:GetPartBoundsInBox(cf, size, overlapParams)

	for _, part in pairs(partsInRegion) do
		if not isValidPlacementSurface(part) and part.CanCollide and part.Transparency < 1 then
			return false
		end
	end

	return true
end

local function setPlacementIndicator(circle, isValid)
	LAST_VALID_PLACEMENT = isValid
	if not circle or not circle:FindFirstChild("SurfaceGui") then return end

	local color = isValid and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 0, 0)
	circle.SurfaceGui.Frame.BackgroundColor3 = color
	circle.SurfaceGui.Frame.UIStroke.Color = color
end

local function getCurrentPlacementValidity(rotation: number): boolean
	if not SELECTED_TOWER or not SELECTED_TOWER.PrimaryPart then
		return false
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { SELECTED_TOWER, LocalPlayer.Character }

	local origin = SELECTED_TOWER.PrimaryPart.Position + Vector3.new(0, 10, 0)
	local result = workspace:Raycast(origin, Vector3.new(0, -35, 0), raycastParams)
	if not result or not isValidPlacementSurface(result.Instance) then
		return false
	end

	local towerBottomY = SELECTED_TOWER.PrimaryPart.Position.Y - (SELECTED_TOWER.PrimaryPart.Size.Y / 2)
	if math.abs(towerBottomY - result.Position.Y) > 3 then
		return false
	end

	return canPlace(SELECTED_TOWER.PrimaryPart.Position, rotation, SELECTED_TOWER.PrimaryPart.Size)
end

local function exitBuildMode()
	-- claers all connections required for build mode
	IS_BUILDING = false

	if BUILD_CONNECTION then
		BUILD_CONNECTION:Disconnect()
		BUILD_CONNECTION = nil
	end

	if InputConn then
		InputConn:Disconnect()
		InputConn = nil
	end

	if ClickConn then
		ClickConn:Disconnect()
		ClickConn = nil
	end

	if SELECTED_TOWER then
		SELECTED_TOWER:Destroy()
		SELECTED_TOWER = nil
	end

	MainGui:WaitForChild("BuildControls").Visible = false
	MobileButtons.Visible = false

	consoleMoveOffset = Vector3.new(0, 0, 0)
	USING_GAMEPAD = false
	LAST_VALID_PLACEMENT = false
end

local function setModelCollision(model: Model, state: boolean)
	-- makes the model uncollidable
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = state
		end
	end

	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CanCollide = state
		end
	end)
end

local function getCharacterPosition(): Vector3?
	local character = LocalPlayer.Character
	if character then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			return rootPart.Position
		end
	end
	return nil
end

local function getConsolePlacementPosition(yOffset: number): Vector3?
	local charPos = getCharacterPosition()
	if not charPos then return nil end

	local camera = workspace.CurrentCamera
	local lookVector = camera.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z).Unit

	local basePosition = charPos + flatLook * CONSOLE_PLACE_DISTANCE + consoleMoveOffset

	local rayOrigin = basePosition + Vector3.new(0, 50, 0)
	local rayDirection = Vector3.new(0, -100, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { SELECTED_TOWER, LocalPlayer.Character }

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if result and isValidPlacementSurface(result.Instance) then
		return result.Position + Vector3.new(0, yOffset, 0)
	end

	return basePosition + Vector3.new(0, yOffset - charPos.Y, 0)
end

local function enterBuildMode(towerName : string)
	--warn("BUILD MODE")

	if IS_BUILDING then
		exitBuildMode()
	end

	IS_BUILDING = true
	consoleMoveOffset = Vector3.new(0, 0, 0)
	USING_GAMEPAD = false

	if IS_MOBILE then
		MobileButtons.Visible = true
	else
		MainGui:WaitForChild("BuildControls").Visible = true
		MobileButtons.Visible = false
	end

	print(towerName)

	SELECTED_TOWER = TowerStorage:FindFirstChild(towerName):Clone()

	if not SELECTED_TOWER then
		warn("Target tower doesn't exist")
		exitBuildMode()
		return
	end

	SELECTED_TOWER.Parent = workspace
	Remotes.Building.CloseTowerInfo:Fire()

	local WhiteCircle = ReplicatedStorage.Storage.Circles.WhiteCircle:Clone()
	if not WhiteCircle then return end

	local Range = SELECTED_TOWER:GetAttribute("Range")
	local TargetSize = Vector3.new(0.375, Range * 2, Range * 2)
	local StartingSize = Vector3.new(0.01, 0.01, 0.01)

	WhiteCircle.Size = StartingSize
	WhiteCircle.Parent = SELECTED_TOWER
	WhiteCircle.Anchored = true
	WhiteCircle.CanCollide = false

	setModelCollision(SELECTED_TOWER, false)

	local tween = TweenService:Create(
		WhiteCircle,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = TargetSize }
	)
	tween:Play()

	local Mouse = LocalPlayer:GetMouse()

	if not Mouse then return end

	if not SELECTED_TOWER.PrimaryPart then
		warn("Tower has no PrimaryPart: " .. towerName)
		return
	end

	Mouse.TargetFilter = SELECTED_TOWER

	setModelCollision(SELECTED_TOWER, false)

	local yOffset = SELECTED_TOWER.PrimaryPart.Size.Y / 2
	local currentRotation = 90
	local targetRotation = currentRotation

	local rotationTween
	local rotationValue = Instance.new("NumberValue")
	rotationValue.Value = currentRotation

	local function tweenRotation(newRotation)
		if rotationTween then
			rotationTween:Cancel()
		end

		local current = rotationValue.Value
		local delta = (newRotation - current) % 360
		if delta > 180 then delta = delta - 360 end
		local adjustedTarget = current + delta

		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		rotationTween = TweenService:Create(rotationValue, tweenInfo, { Value = adjustedTarget })

		rotationTween.Completed:Connect(function()
			currentRotation = newRotation % 360
			rotationValue.Value = currentRotation
		end)

		rotationTween:Play()
	end

	rotationValue:GetPropertyChangedSignal("Value"):Connect(function()
		currentRotation = rotationValue.Value
	end)

	if not IS_MOBILE then
		InputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or not IS_BUILDING then return end

			-- Keyboard controls
			if input.KeyCode == Enum.KeyCode.R and not(ROTATE_COOLDOWN) then
				ROTATE_COOLDOWN = true
				targetRotation = (targetRotation + 90) % 360
				tweenRotation(targetRotation)
				task.wait(.2)
				ROTATE_COOLDOWN = false
			elseif input.KeyCode == Enum.KeyCode.Q then
				exitBuildMode()
			end

			-- Gamepad controls
			if input.KeyCode == Enum.KeyCode.ButtonX and not(ROTATE_COOLDOWN) then
				USING_GAMEPAD = true
				ROTATE_COOLDOWN = true
				targetRotation = (targetRotation + 90) % 360
				tweenRotation(targetRotation)
				task.wait(.2)
				ROTATE_COOLDOWN = false
			elseif input.KeyCode == Enum.KeyCode.ButtonB then
				exitBuildMode()
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				if USING_GAMEPAD and LAST_VALID_PLACEMENT then
					Remotes.Building.PlaceTower:FireServer(towerName, SELECTED_TOWER.PrimaryPart.CFrame)
					exitBuildMode()
				end
			end

			-- Detect gamepad usage from thumbstick
			if input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2 then
				USING_GAMEPAD = true
			end
		end)

		ClickConn = Mouse.Button1Down:Connect(function()
			if not IS_BUILDING then return end

			if LAST_VALID_PLACEMENT and isValidPlacementSurface(Mouse.Target) then
				Remotes.Building.PlaceTower:FireServer(towerName, SELECTED_TOWER.PrimaryPart.CFrame)
				exitBuildMode()
			end
		end)
	end

	if IS_MOBILE then
		local function getPlacementPositionFromScreen(touchPos)
			local ray = workspace.CurrentCamera:ScreenPointToRay(touchPos.X, touchPos.Y)
			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = { SELECTED_TOWER, LocalPlayer.Character }
			local result = workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)

			if result and isValidPlacementSurface(result.Instance) then
				return result.Position + Vector3.new(0, yOffset, 0)
			end
			return nil
		end

		UserInputService.TouchTap:Connect(function(touchPositions)
			if not IS_BUILDING then return end
			local screenPos = touchPositions[1]
			local newPos = getPlacementPositionFromScreen(screenPos)
			if newPos then
				local newCFrame = CFrame.new(newPos) * CFrame.Angles(0, math.rad(currentRotation), 0)
				SELECTED_TOWER:SetPrimaryPartCFrame(newCFrame)
			end
		end)

		MobileRotate.Activated:Connect(function()
			if not IS_BUILDING then return end
			if not SELECTED_TOWER or not SELECTED_TOWER.PrimaryPart then return end

			targetRotation = (targetRotation + 90) % 360
			tweenRotation(targetRotation)

			local currentPos = SELECTED_TOWER.PrimaryPart.Position
			local newCFrame = CFrame.new(currentPos) * CFrame.Angles(0, math.rad(targetRotation), 0)
			SELECTED_TOWER:SetPrimaryPartCFrame(newCFrame)
		end)

		MobilePlace.Activated:Connect(function()
			if not IS_BUILDING then return end
			if not LAST_VALID_PLACEMENT then return end
			Remotes.Building.PlaceTower:FireServer(towerName, SELECTED_TOWER.PrimaryPart.CFrame)
			exitBuildMode()
		end)

		MobileCancel.Activated:Connect(function()
			exitBuildMode()
		end)
	end

	BUILD_CONNECTION = RunService.RenderStepped:Connect(function(deltaTime)
		if not IS_BUILDING then return end

		setModelCollision(SELECTED_TOWER, false)

		-- Console thumbstick movement (only when actively using gamepad)
		if USING_GAMEPAD and not IS_MOBILE then
			local gamepadState = UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
			for _, input in ipairs(gamepadState) do
				if input.KeyCode == Enum.KeyCode.Thumbstick1 then
					local thumbPos = input.Position
					if thumbPos.Magnitude > 0.2 then
						local camera = workspace.CurrentCamera
						local camCFrame = camera.CFrame
						local forward = Vector3.new(camCFrame.LookVector.X, 0, camCFrame.LookVector.Z).Unit
						local right = Vector3.new(camCFrame.RightVector.X, 0, camCFrame.RightVector.Z).Unit
						local moveDirection = (forward * thumbPos.Y + right * thumbPos.X)
						consoleMoveOffset = consoleMoveOffset + moveDirection * CONSOLE_MOVE_SPEED * deltaTime
					end
				end
			end

			local consolePos = getConsolePlacementPosition(yOffset)
			if consolePos then
				local newCFrame = CFrame.new(consolePos) * CFrame.Angles(0, math.rad(currentRotation), 0)
				SELECTED_TOWER:SetPrimaryPartCFrame(newCFrame)

				local rayOrigin = consolePos + Vector3.new(0, 10, 0)
				local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -20, 0))

				if rayResult and isValidPlacementSurface(rayResult.Instance) then
					WhiteCircle.SurfaceGui.Frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					WhiteCircle.SurfaceGui.Frame.UIStroke.Color = Color3.fromRGB(255, 255, 255)
				else
					WhiteCircle.SurfaceGui.Frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
					WhiteCircle.SurfaceGui.Frame.UIStroke.Color = Color3.fromRGB(255, 0, 0)
				end
			end
		elseif not IS_MOBILE then
			-- Mouse-based placement (PC default)
			if Mouse.Target then
				local targetPosition = Mouse.Hit.Position + Vector3.new(0, yOffset, 0)
				local newCFrame = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(currentRotation), 0)
				SELECTED_TOWER:SetPrimaryPartCFrame(newCFrame)

				if isValidPlacementSurface(Mouse.Target) then
					WhiteCircle.SurfaceGui.Frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
					WhiteCircle.SurfaceGui.Frame.UIStroke.Color = Color3.fromRGB(255, 255, 255)
				else
					--warn(Mouse.Target)
					WhiteCircle.SurfaceGui.Frame.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
					WhiteCircle.SurfaceGui.Frame.UIStroke.Color = Color3.fromRGB(255, 0, 0)
				end
			end
		end

		local targetCFrame = SELECTED_TOWER.PrimaryPart.CFrame
		local towerBottomY = targetCFrame.Position.Y - (SELECTED_TOWER.PrimaryPart.Size.Y / 2)
		WhiteCircle.CFrame = CFrame.new(
			Vector3.new(targetCFrame.Position.X, towerBottomY + 0.05, targetCFrame.Position.Z)
		) * CFrame.Angles(0, 0, math.pi / 2)
		setPlacementIndicator(WhiteCircle, getCurrentPlacementValidity(currentRotation))
	end)
end

ReplicatedStorage.Remotes.Building.ClientRequest.Event:Connect(function(SlotNumber : number)
	local UserData = LocalPlayer:FindFirstChild("UserData")
	if not UserData then return end
	local Inventory = UserData:FindFirstChild("Hotbar")
	if not Inventory then return end
	local SlotData = Inventory:FindFirstChild(SlotNumber)
	if not SlotData then return end
	local TargetUnit = SlotData.Value
	if not TargetUnit then return end
	if SlotData.Value == "" or SlotData.Value == nil then return end

	enterBuildMode(TargetUnit)
end)

Remotes.Building.Cancel.Event:Connect(function()
	exitBuildMode()
end)

return {}
