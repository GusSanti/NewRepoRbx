-- SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- CONSTANTS
local DROP_HEIGHT = 45
local FIRST_DROP_MIN_DELAY = 5
local FIRST_DROP_MAX_DELAY = 9
local DROP_MIN_INTERVAL = 18
local DROP_MAX_INTERVAL = 28
local DAMAGE_MULTIPLIER = 1.5
local COIN_BASE_AMOUNT = 100
local COIN_AMOUNT_PER_WAVE = 25
local AIR_STRIKE_BASE_DAMAGE = 120
local AIR_STRIKE_DAMAGE_PER_WAVE = 20

local CRATE_CONFIGS = {
	{
		Type = "Damage",
		DisplayName = "Damage Crate",
		TemplateName = "Explosive Crate",
		Weight = 35,
		Color = Color3.fromRGB(255, 96, 58),
		Lifetime = 14,
	},
	{
		Type = "AirStrike",
		DisplayName = "Air Strike Crate",
		TemplateName = "Basic Weapon Crate",
		Weight = 25,
		Color = Color3.fromRGB(92, 174, 255),
		Lifetime = 14,
	},
	{
		Type = "Coin",
		DisplayName = "Coin Crate",
		TemplateName = "Golden",
		Weight = 40,
		Color = Color3.fromRGB(255, 205, 74),
		Lifetime = 8,
	},
}

-- VARIABLES
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GameRemotes = Remotes:WaitForChild("Game")
local Storage = ReplicatedStorage:FindFirstChild("Storage")
local Particles = Storage and Storage:FindFirstChild("Particles")
local Billboards = Storage and Storage:FindFirstChild("Billboards")
local ExplosionTemplate = Particles and Particles:FindFirstChild("ExplosionTemplate")
local MoneyBillboardTemplate = Billboards and Billboards:FindFirstChild("Money")
local EnemyStats = require(ReplicatedStorage.Modules.StoredData.EnemyData)

local CrateDropManager = {}
local activeWaveToken = 0
local activeWaveNumber = 0
local activeCrates = {}

-- FUNCTIONS
local function getGameSpeed()
	return math.max(workspace:GetAttribute("GameSpeed") or 1, 0.1)
end

local function scaledDelay(seconds)
	return seconds / getGameSpeed()
end

local function getCrateFolder()
	local folder = workspace:FindFirstChild("CrateDrops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "CrateDrops"
		folder.Parent = workspace
	end
	return folder
end

local function getCrateTemplateFolder()
	return workspace:FindFirstChild("Crates")
end

local function sendNotification(targetPlayer, text, notificationType)
	local remote = GameRemotes:FindFirstChild("SendNotification")
	if not remote then return end

	if targetPlayer then
		remote:FireClient(targetPlayer, text, notificationType)
	else
		remote:FireAllClients(text, notificationType)
	end
end

local function playSound(soundName)
	local audioFolder = Remotes:FindFirstChild("Audio")
	local remote = audioFolder and audioFolder:FindFirstChild("ServerToClient")
	if remote then
		remote:FireAllClients(soundName)
	end
end

local function clearCrates()
	for crate in pairs(activeCrates) do
		if crate and crate.Parent then
			crate:Destroy()
		end
		activeCrates[crate] = nil
	end
end

local function getSortedWaypoints()
	local path = workspace:FindFirstChild("Path")
	local waypointsFolder = path and path:FindFirstChild("Waypoints")
	if not waypointsFolder then
		return {}
	end

	local waypoints = {}
	for _, waypoint in ipairs(waypointsFolder:GetChildren()) do
		if waypoint:IsA("BasePart") then
			table.insert(waypoints, waypoint)
		end
	end

	table.sort(waypoints, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)

	return waypoints
end

local function getDropPosition()
	local waypoints = getSortedWaypoints()
	if #waypoints == 0 then
		local spawnPart = workspace:FindFirstChild("SpawnPos")
		return spawnPart and spawnPart.Position or Vector3.new(0, 5, 0)
	end

	local waypoint = waypoints[math.random(1, #waypoints)]
	local angle = math.random() * math.pi * 2
	local radius = math.random(5, 11)
	local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
	local rayOrigin = waypoint.Position + offset + Vector3.new(0, 120, 0)
	local rayDirection = Vector3.new(0, -260, 0)
	local raycastParams = RaycastParams.new()
	local filterInstances = {
		workspace:FindFirstChild("Enemies"),
		workspace:FindFirstChild("Towers"),
		workspace:FindFirstChild("CrateDrops"),
	}

	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	for index = #filterInstances, 1, -1 do
		if not filterInstances[index] then
			table.remove(filterInstances, index)
		end
	end
	raycastParams.FilterDescendantsInstances = filterInstances

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	if result then
		return result.Position + Vector3.new(0, 1.75, 0)
	end

	return waypoint.Position + offset + Vector3.new(0, 2, 0)
end

local function chooseCrateConfig()
	local totalWeight = 0
	for _, config in ipairs(CRATE_CONFIGS) do
		totalWeight += config.Weight
	end

	local roll = math.random() * totalWeight
	local current = 0

	for _, config in ipairs(CRATE_CONFIGS) do
		current += config.Weight
		if roll <= current then
			return config
		end
	end

	return CRATE_CONFIGS[#CRATE_CONFIGS]
end

local function getCratePrimaryPart(crate)
	if crate:IsA("BasePart") then
		return crate
	end

	if crate:IsA("Model") then
		if not crate.PrimaryPart then
			local primaryPart = crate:FindFirstChildWhichIsA("BasePart", true)
			if primaryPart then
				crate.PrimaryPart = primaryPart
			end
		end
		return crate.PrimaryPart
	end

	return nil
end

local function setCrateCFrame(crate, targetCFrame)
	if crate:IsA("Model") then
		crate:PivotTo(targetCFrame)
	else
		crate.CFrame = targetCFrame
	end
end

local function prepareCrateInstance(crate)
	for _, descendant in ipairs(crate:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
		elseif descendant:IsA("Highlight") or descendant:IsA("ClickDetector") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end

	local primaryPart = getCratePrimaryPart(crate)
	if not primaryPart then
		return nil
	end

	return primaryPart
end

local function createCrateBillboard(crate, config)
	local primaryPart = getCratePrimaryPart(crate)
	if not primaryPart then return end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CrateBillboard"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(220, 72)
	billboard.StudsOffset = Vector3.new(0, 3.8, 0)
	billboard.Adornee = primaryPart
	billboard.Parent = crate

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = config.DisplayName .. "\nClick to claim"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.35
	label.Parent = billboard
end

local function createFallbackCratePart(config)
	local crate = Instance.new("Part")
	crate.Name = config.Type .. "Crate"
	crate.Size = Vector3.new(4, 3.25, 4)
	crate.Material = Enum.Material.WoodPlanks
	crate.Color = config.Color
	crate.Anchored = true
	crate.CanCollide = false
	crate:SetAttribute("CrateType", config.Type)
	crate:SetAttribute("DisplayName", config.DisplayName)

	return crate
end

local function createCratePart(config, targetPosition)
	local crateTemplateFolder = getCrateTemplateFolder()
	local crate = nil

	if crateTemplateFolder and config.TemplateName then
		local template = crateTemplateFolder:FindFirstChild(config.TemplateName)
		if template then
			crate = template:Clone()
		end
	end

	if not crate then
		crate = createFallbackCratePart(config)
	end

	crate.Name = config.Type .. "Crate"
	crate:SetAttribute("CrateType", config.Type)
	crate:SetAttribute("DisplayName", config.DisplayName)

	local primaryPart = prepareCrateInstance(crate)
	if not primaryPart then
		return nil
	end

	local startCFrame = CFrame.new(targetPosition + Vector3.new(0, DROP_HEIGHT, 0))
	setCrateCFrame(crate, startCFrame)

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 60
	clickDetector.Parent = primaryPart

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Claim"
	prompt.ObjectText = config.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = primaryPart

	local highlight = Instance.new("Highlight")
	highlight.Adornee = crate
	highlight.FillTransparency = 1
	highlight.OutlineColor = config.Color
	highlight.OutlineTransparency = 0
	highlight.Parent = crate

	createCrateBillboard(crate, config)

	return crate, clickDetector, prompt
end

local function animateCrateIn(crate, targetPosition)
	local spin = CFrame.Angles(0, math.rad(math.random(0, 359)), 0)
	local targetCFrame = CFrame.new(targetPosition) * spin

	if crate:IsA("Model") then
		local startCFrame = getCratePrimaryPart(crate).CFrame
		local tweenValue = Instance.new("CFrameValue")
		tweenValue.Value = startCFrame
		tweenValue:GetPropertyChangedSignal("Value"):Connect(function()
			if crate and crate.Parent then
				setCrateCFrame(crate, tweenValue.Value)
			end
		end)

		local tween = TweenService:Create(
			tweenValue,
			TweenInfo.new(scaledDelay(0.65), Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ Value = targetCFrame }
		)
		tween:Play()
		tween.Completed:Connect(function()
			tweenValue:Destroy()
		end)
		return
	end

	local tween = TweenService:Create(
		crate,
		TweenInfo.new(scaledDelay(0.65), Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	tween:Play()
end

local function destroyCrate(crate)
	if not crate or not crate.Parent then return end
	activeCrates[crate] = nil

	local tweenInfo = TweenInfo.new(scaledDelay(0.18), Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local parts = {}

	if crate:IsA("BasePart") then
		table.insert(parts, crate)
	else
		for _, descendant in ipairs(crate:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	for _, part in ipairs(parts) do
		TweenService:Create(part, tweenInfo, { Transparency = 1 }):Play()
	end

	task.delay(scaledDelay(0.2), function()
		if crate and crate.Parent then
			crate:Destroy()
		end
	end)
end

local function showMoneyPopup(amount, position)
	if not MoneyBillboardTemplate then return end

	local moneyTemplate = MoneyBillboardTemplate:Clone()
	local wormMoney = moneyTemplate:FindFirstChild("Worm_Money")
	local incomeText = wormMoney and wormMoney:FindFirstChild("Worm_income")
	if incomeText and incomeText:IsA("TextLabel") then
		incomeText.Text = "+$" .. tostring(amount)
	end

	local adorneePart = Instance.new("Part")
	adorneePart.Anchored = true
	adorneePart.CanCollide = false
	adorneePart.Transparency = 1
	adorneePart.Size = Vector3.new(1, 1, 1)
	adorneePart.Position = position + Vector3.new(0, 0.25, 0)
	adorneePart.Parent = workspace

	moneyTemplate.Parent = workspace
	if moneyTemplate:IsA("BillboardGui") then
		moneyTemplate.StudsOffset = Vector3.new(0, 3, 0)
		moneyTemplate.Adornee = adorneePart
	elseif moneyTemplate:IsA("Model") and moneyTemplate.PrimaryPart then
		moneyTemplate:SetPrimaryPartCFrame(CFrame.new(position + Vector3.new(0, 3, 0)))
	end

	task.delay(scaledDelay(1), function()
		if moneyTemplate then moneyTemplate:Destroy() end
		if adorneePart then adorneePart:Destroy() end
	end)
end

local function emitExplosion(position)
	if not ExplosionTemplate then return end

	local explosionPart = ExplosionTemplate:Clone()
	explosionPart.Position = position - Vector3.new(0, 2.5, 0)
	explosionPart.Parent = workspace

	task.delay(scaledDelay(0.05), function()
		if not explosionPart or not explosionPart.Parent then return end
		for _, particle in ipairs(explosionPart:GetDescendants()) do
			if particle:IsA("ParticleEmitter") then
				particle:Emit(8)
			end
		end
	end)

	task.delay(scaledDelay(2.5), function()
		if explosionPart then
			explosionPart:Destroy()
		end
	end)
end

local function increaseStat(player, statName, increment)
	for _, value in ipairs(player:GetDescendants()) do
		if value.Name == statName and (value:IsA("IntValue") or value:IsA("NumberValue")) then
			value.Value += increment
		end
	end
end

local function updateQuestProgress(player, keyword, amount)
	if not player or not keyword then return end
	keyword = keyword:lower()

	for attributeName in pairs(player:GetAttributes()) do
		if attributeName:lower():find("quest_") and attributeName:lower():find(keyword) then
			local current = player:GetAttribute(attributeName)
			if typeof(current) == "number" then
				player:SetAttribute(attributeName, current + amount)
			end
		end
	end
end

local function awardEnemyKill(player, enemy, deathPosition)
	local enemyName = enemy.Name
	local baseCash = EnemyStats[enemyName] and EnemyStats[enemyName].Money or 0
	local playerCount = math.max(#Players:GetPlayers(), 1)
	local reward = math.round(baseCash / playerCount)

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local currentCash = otherPlayer:GetAttribute("TempCash") or 0
		otherPlayer:SetAttribute("TempCash", currentCash + reward)
	end

	if player then
		increaseStat(player, "WormsKilled", 1)
		updateQuestProgress(player, enemyName, 1)
		player:SetAttribute("WormsKilled", (player:GetAttribute("WormsKilled") or 0) + 1)
	end

	showMoneyPopup(reward, deathPosition)
end

local function applyDamageCrate(player)
	local currentMultiplier = workspace:GetAttribute("CrateDamageMultiplier") or 1
	workspace:SetAttribute("CrateDamageMultiplier", math.max(currentMultiplier, DAMAGE_MULTIPLIER))
	workspace:SetAttribute("CrateDamageWave", activeWaveNumber)

	sendNotification(nil, player.Name .. " claimed a Damage Crate! Towers hit harder this wave.", "Success")
	playSound("TowerUpgrade")
end

local function applyCoinCrate(player, position)
	local amount = math.clamp(COIN_BASE_AMOUNT + (activeWaveNumber * COIN_AMOUNT_PER_WAVE), 125, 600)
	local currentCash = player:GetAttribute("TempCash") or 0

	player:SetAttribute("TempCash", currentCash + amount)
	sendNotification(player, "Coin Crate claimed! +$" .. amount, "Success")
	showMoneyPopup(amount, position)
	playSound("ClickSoundEffect")
end

local function applyAirStrikeCrate(player)
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if not enemiesFolder then return end

	local damage = AIR_STRIKE_BASE_DAMAGE + (activeWaveNumber * AIR_STRIKE_DAMAGE_PER_WAVE)
	local hitCount = 0

	for _, enemy in ipairs(enemiesFolder:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local oldHealth = humanoid.Health
				local deathPosition = enemy.PrimaryPart.Position

				humanoid:TakeDamage(damage)
				emitExplosion(deathPosition)
				hitCount += 1

				if humanoid.Health > 0 then
					local visualDamage = GameRemotes:FindFirstChild("VisualDamage")
					if visualDamage then
						visualDamage:FireAllClients(enemy, damage)
					end
				elseif oldHealth > 0 then
					awardEnemyKill(player, enemy, deathPosition)
				end
			end
		end
	end

	sendNotification(nil, player.Name .. " called an Air Strike! " .. hitCount .. " worms hit.", "Success")
	playSound("Grenader")
end

local function claimCrate(player, crate, config, waveToken, position)
	if waveToken ~= activeWaveToken then
		destroyCrate(crate)
		return
	end

	if crate:GetAttribute("Claimed") then
		return
	end

	crate:SetAttribute("Claimed", true)

	if config.Type == "Damage" then
		applyDamageCrate(player)
	elseif config.Type == "AirStrike" then
		applyAirStrikeCrate(player)
	elseif config.Type == "Coin" then
		applyCoinCrate(player, position)
	end

	destroyCrate(crate)
end

local function spawnCrate(waveToken)
	if waveToken ~= activeWaveToken then return end

	local config = chooseCrateConfig()
	local position = getDropPosition()
	local crate, clickDetector, prompt = createCratePart(config, position)
	if not crate or not clickDetector or not prompt then
		return
	end

	crate.Parent = getCrateFolder()
	activeCrates[crate] = true
	animateCrateIn(crate, position)

	clickDetector.MouseClick:Connect(function(player)
		claimCrate(player, crate, config, waveToken, position)
	end)

	prompt.Triggered:Connect(function(player)
		claimCrate(player, crate, config, waveToken, position)
	end)

	task.delay(scaledDelay(config.Lifetime), function()
		if waveToken == activeWaveToken and crate and crate.Parent and not crate:GetAttribute("Claimed") then
			destroyCrate(crate)
		end
	end)
end

function CrateDropManager.StartWave(waveNumber)
	activeWaveToken += 1
	activeWaveNumber = waveNumber or 1

	workspace:SetAttribute("CrateDamageMultiplier", 1)
	workspace:SetAttribute("CrateDamageWave", nil)
	clearCrates()

	local waveToken = activeWaveToken

	task.spawn(function()
		task.wait(scaledDelay(math.random(FIRST_DROP_MIN_DELAY, FIRST_DROP_MAX_DELAY)))

		while waveToken == activeWaveToken do
			spawnCrate(waveToken)
			task.wait(scaledDelay(math.random(DROP_MIN_INTERVAL, DROP_MAX_INTERVAL)))
		end
	end)
end

function CrateDropManager.StopWave()
	activeWaveToken += 1
	activeWaveNumber = 0

	workspace:SetAttribute("CrateDamageMultiplier", 1)
	workspace:SetAttribute("CrateDamageWave", nil)
	clearCrates()
end

return CrateDropManager
