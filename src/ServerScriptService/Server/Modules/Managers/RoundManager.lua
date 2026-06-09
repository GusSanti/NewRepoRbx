-- services

local MarketplaceService = game:GetService("MarketplaceService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local ServerStorage = game.ServerStorage
local Modules = ServerStorage:WaitForChild("Modules")
local Manager = Modules:WaitForChild("Managers")
local DataStore = require(Manager:WaitForChild("DataManager"))
local CrateDropManager = require(script.Parent:WaitForChild("CrateDropManager"))
local DestructionManager = require(script.Parent:WaitForChild("DestructionManager"))

local TotalCompleted = 0

-- variables

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local GameRemotes = Remotes:FindFirstChild("Game")

local Path = workspace:FindFirstChild("Path")
local Waypoints = Path and Path:FindFirstChild("Waypoints")

local Units = ServerStorage:FindFirstChild("Units")

local GlobalValues = ReplicatedStorage:FindFirstChild("GlobalValues")

local HealthBillboardTemplate = ReplicatedStorage.Storage.Billboards.Health

-- tables

local EnemyStats = require(ReplicatedStorage.Modules.StoredData.EnemyData)

local TotalWaves = nil

local WaveUnits = nil

local TimeTillNext = nil

-- values

local MaxHealth = GlobalValues:FindFirstChild("Base_Health").Value

-- public

local RoundManager = {}
task.defer(DestructionManager.PrepareMap)

-- determines cash reward per difficulty
local WaveCash = {
	["Easy"] = 50,
	["Medium"] = 100,
	["Hard"] = 150,
	["Impossible"] = 250,
}

-- server config

local collision_Group = "Worms"
local MAX_ROUNDS = 0
local UNITS_PER_WAVE = 5
local WAVE_DELAY = 3
local MaxTime = 60 * 60
local SPAWN_DEBUG = false
local MOVEMENT_DEBUG = false
local ALLOW_GENERATED_ENEMY_FALLBACK = false
local WAYPOINT_REACH_DISTANCE = 3
local STEP_REDUCTION_FACTORS = { 1, 0.5, 0.25 }

local DatastoreService = game:GetService("DataStoreService")
local ClanStore = DatastoreService:GetDataStore("Clans_v2")

-- difficulty scaling

local SPAWN_TIME_STEP = 0.25   -- controls seconds faster each wave
local HEALTH_MULTIPLIER_STEP = 0.25  -- controls 25% health increase per wave
local BASE_SPAWN_DELAY = 4

local Handler = {}
local CachedData = nil
local PlayerCooldowns = {} -- tracks cooldowns per player

-- local functions
local function spawnDebug(...)
	if SPAWN_DEBUG then
		warn("[RoundSpawn]", ...)
	end
end

local function movementDebug(...)
	if MOVEMENT_DEBUG then
		warn("[MovementDebug]", ...)
	end
end

local function formatGroundInfo(info)
	if not info then
		return "no ground info"
	end

	local fragments = {
		"reason=" .. tostring(info.Reason),
	}

	if info.ProbePosition then
		table.insert(fragments, string.format(
			"probe=(%.2f, %.2f, %.2f)",
			info.ProbePosition.X,
			info.ProbePosition.Y,
			info.ProbePosition.Z
		))
	end

	if info.HitPosition then
		table.insert(fragments, string.format(
			"hit=(%.2f, %.2f, %.2f)",
			info.HitPosition.X,
			info.HitPosition.Y,
			info.HitPosition.Z
		))
	end

	if info.HitSummary then
		table.insert(fragments, "hitSummary=" .. info.HitSummary)
	end

	if info.IsPathModelRoute ~= nil then
		table.insert(fragments, "isPathRoute=" .. tostring(info.IsPathModelRoute))
	end

	return table.concat(fragments, " | ")
end

local function getPath()
	Path = workspace:FindFirstChild("Path")
	if not Path then
		spawnDebug("workspace.Path missing")
	end
	return Path
end

local function getWaypoints()
	local path = getPath()
	if not path then
		return nil
	end

	Waypoints = path:FindFirstChild("Waypoints")
	if not Waypoints then
		spawnDebug("workspace.Path.Waypoints missing")
	end
	return Waypoints
end

local function getEnemyFolder()
	local folder = workspace:FindFirstChild("Enemies")
	if not folder then
		spawnDebug("workspace.Enemies missing; creating fallback folder")
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = workspace
	end
	return folder
end

local function getUnitFolder()
	Units = ServerStorage:FindFirstChild("Units")
	if not Units then
		spawnDebug("ServerStorage.Units missing")
	end
	return Units
end

local function findHumanoid(model)
	return model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildWhichIsA("Humanoid", true)
end

local function findRootPart(model)
	local rootPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("HumanoidRootPart", true)
	if not rootPart then
		rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	end
	if rootPart and rootPart:IsA("BasePart") and not model.PrimaryPart then
		model.PrimaryPart = rootPart
	end
	return rootPart
end

local function createFallbackEnemyModel(unitName)
	spawnDebug("creating visible fallback model for", unitName)

	local model = Instance.new("Model")
	model.Name = unitName

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 2)
	rootPart.Color = Color3.fromRGB(110, 190, 95)
	rootPart.Material = Enum.Material.SmoothPlastic
	rootPart.Anchored = false
	rootPart.CanCollide = false
	rootPart.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.7, 1.4, 1.7)
	head.Color = Color3.fromRGB(165, 220, 120)
	head.Material = Enum.Material.SmoothPlastic
	head.Anchored = false
	head.CanCollide = false
	head.CFrame = rootPart.CFrame + Vector3.new(0, 1.8, 0)
	head.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = head
	weld.Parent = rootPart

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model

	model.PrimaryPart = rootPart
	return model
end

-- picks a random unit from the units folder
local function chooseRandomUnit()
	local unitFolder = getUnitFolder()
	if not unitFolder then
		return nil
	end

	local unitList = unitFolder:GetChildren()
	if #unitList <= 0 then
		spawnDebug("ServerStorage.Units is empty")
		return nil
	end

	local randomUnit = unitList[math.random(1, #unitList)]
	return randomUnit
end

local function debugSpawnState()
	local unitFolder = getUnitFolder()
	local path = getPath()
	local waypointsFolder = getWaypoints()
	local enemyFolder = getEnemyFolder()

	local unitNames = {}
	if unitFolder then
		for _, unit in ipairs(unitFolder:GetChildren()) do
			table.insert(unitNames, unit.Name)
		end
	end
	table.sort(unitNames)

	spawnDebug("state",
		"units=", #unitNames > 0 and table.concat(unitNames, ", ") or "none",
		"path=", path ~= nil,
		"spawn=", path and path:FindFirstChild("Enemy_Spawn") ~= nil,
		"target=", path and path:FindFirstChild("Enemy_Target") ~= nil,
		"waypoints=", waypointsFolder and #waypointsFolder:GetChildren() or 0,
		"enemiesFolder=", enemyFolder ~= nil
	)
end

-- fetches clan data from datastore
function GetClanData()
	local success, data = pcall(function()
		return ClanStore:GetAsync("Data")
	end)
	if success then
		if data then
			CachedData = data
		end
		return CachedData
	end
end

-- saves clan data to datastore
function SaveClanData(ClanData)
	local success, err = pcall(function()
		ClanStore:SetAsync("Data", ClanData)

		print("saved!")

		--print(ClanData)
	end)
	if not success then
		warn("Error saving clans:", err)
	end
	return success
end

-- handles when the game ends early (player loses)
local function endGameEarly(currentWave)
	local TimeEnd = tick()
	local TimeTaken = TimeEnd - (workspace:GetAttribute("GameStartTime") or TimeEnd)
	local isTutorial = workspace:GetAttribute("MapName") == "Tutorial"

	print(workspace:GetAttribute("Difficulty"))

	-- gives players cash based on waves completed
	for _, Plr in ipairs(Players:GetPlayers()) do
		Plr:SetAttribute("MatchWon", false)
		local Multi = 1

		-- checks for gamepass multipliers
		pcall(function()
			if MarketplaceService:UserOwnsGamePassAsync(Plr.UserId, 1529106675) then
				Multi *= 2
			end

			if MarketplaceService:UserOwnsGamePassAsync(Plr.UserId, 1529258503) then
				Multi *= 1.5
			end
		end)

		if not isTutorial then
			Plr.UserData.Money.Value += WaveCash[workspace:GetAttribute("Difficulty")] * currentWave
		end
	end

	-- formats the time taken
	local minutes = math.floor(TimeTaken / 60)
	local seconds = math.floor(TimeTaken % 60)
	local formattedTime = string.format("%d:%02d", minutes, seconds)

	-- notifies all clients of the loss
	Remotes.Game.SendNotification:FireAllClients("You lost!", "Error")
	Remotes.Game.ShowResults:FireAllClients(currentWave, formattedTime, "Lost")

	-- updates clan stats after game ends
	local Cache = GetClanData()

	if Cache then
		for _, Player in ipairs(Players:GetPlayers()) do
			local ClanTag = DataStore.Stored[Player.UserId].Data.ClanTag
			if ClanTag then 
				if Cache.Clans[ClanTag] then
					if Player:GetAttribute("WormsKilled") then
						Cache.Clans[ClanTag].Stats.Killed += Player:GetAttribute("WormsKilled")
					end
					if Player:GetAttribute("TowersPlaced") then
						Cache.Clans[ClanTag].Stats.Placed += Player:GetAttribute("TowersPlaced")
					end
				else
					print("no clan")
				end
			else
				print("nope")
			end
		end

		SaveClanData(Cache)
	end
end

-- updates the base health bar ui
local function setBaseHealth()

	local Base = workspace:FindFirstChild("Base")
	if not Base then return end

	local HealthBar = Base:FindFirstChild("UiAttachment"):FindFirstChild("HealthBar")
	if not HealthBar then return end

	local Bar = HealthBar:WaitForChild("GameStats"):WaitForChild("Bar")
	if not Bar then return end

	local HealthText = HealthBar:FindFirstChild("GameStats"):FindFirstChild("HP")
	if not HealthText then return end

	local GlobalHealth = GlobalValues:FindFirstChild("Base_Health")
	if not GlobalHealth then return end

	-- calculates health percentage for the bar
	local Percentage = GlobalHealth.Value / MaxHealth

	Bar.Size = UDim2.new(Percentage, 0, 1, 0)
	HealthText.Text = GlobalHealth.Value.."/"..MaxHealth

end

-- handles damage to the base
local function baseTakeDamage(Damage : number)
	local Base = workspace:FindFirstChild("Base")
	if not Base then return end

	local HealthBar = Base:FindFirstChild("UiAttachment"):FindFirstChild("HealthBar")
	if not HealthBar then return end

	local HealthText = HealthBar:FindFirstChild("GameStats"):FindFirstChild("HP")
	if not HealthText then return end

	local Bar = HealthBar:WaitForChild("GameStats"):WaitForChild("Bar")
	if not Bar then return end

	local GlobalHealth = GlobalValues:FindFirstChild("Base_Health")
	if not GlobalHealth then return end

	local Percentage = GlobalHealth.Value / MaxHealth

	Bar.Size = UDim2.new(Percentage, 0, 1, 0)

	-- subtracts damage and clamps to zero
	GlobalHealth.Value = math.max(GlobalHealth.Value - Damage, 0)
	HealthText.Text = GlobalHealth.Value.."/"..MaxHealth

	-- tells clients to update their health bar display
	Remotes.Game.UpdateHealthbar:FireAllClients(GlobalHealth.Value, MaxHealth)

	-- ends the game if base health hits zero
	if GlobalHealth.Value <= 0 then
		GlobalHealth.Value = 0
		CrateDropManager.StopWave()
		local currentWave = workspace:GetAttribute("CurrentWave") or 1
		endGameEarly(currentWave)
	end
end

-- moves the enemy using server-side dynamic pathfinding
local function moveUnit(unit: Model)
	if not unit then return end
	local humanoidRootPart = findRootPart(unit)
	if not humanoidRootPart then
		spawnDebug("move blocked: missing HumanoidRootPart/BasePart for", unit.Name)
		return
	end
	local humanoid = findHumanoid(unit)
	if not humanoid then
		spawnDebug("move blocked: missing Humanoid for", unit.Name)
		return
	end

	-- plays the walk animation
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = unit:FindFirstChildWhichIsA("Animator", true)
	end
	if animator then
		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = "rbxassetid://128646144753424"
		local walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Looped = true
		walkTrack:Play()
	end

	-- handles collision with grandma towers
	humanoidRootPart.Touched:Connect(function(Hit)
		if Hit.Parent and Hit.Parent.Name:find("Grandma") then
			if Hit.Parent.Parent and Hit.Parent.Parent.Name:find("Grandma") then

				local GrandmaHumanoid = Hit.Parent.Parent:FindFirstChildOfClass("Humanoid")
				if not GrandmaHumanoid then return end

				local EnemyHumanoid = unit:FindFirstChildOfClass("Humanoid")
				if not EnemyHumanoid or EnemyHumanoid.Health <= 0 then return end

				GrandmaHumanoid:TakeDamage(EnemyHumanoid.Health)
				unit:Destroy()

				for _, Plr in ipairs(Players:GetPlayers()) do
					local currentCash = Plr:GetAttribute("TempCash") or 0
					local unitStats = EnemyStats[unit.Name]
					local reward = unitStats and math.round(unitStats.Money / #Players:GetPlayers()) or 0
					Plr:SetAttribute("TempCash", currentCash + reward)
				end
				return
			end
		end
	end)

	local routeProgress = unit:GetAttribute("Current") or 0
	local mapWaypointIndex = 1
	local destroyerStrikeUsed = false
	local path = getPath()
	if not path then return end
	local waypointsFolder = getWaypoints()
	if not waypointsFolder then return end
	local finalTarget = path:FindFirstChild("Enemy_Target")
	if not finalTarget then
		spawnDebug("move blocked: workspace.Path.Enemy_Target missing for", unit.Name)
	end
	local staticWaypoints = {}

	for _, waypoint in ipairs(waypointsFolder:GetChildren()) do
		table.insert(staticWaypoints, waypoint)
	end
	table.sort(staticWaypoints, function(a, b)
		return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
	end)
	local stats = EnemyStats[unit.Name] or {}
	humanoid.AutoRotate = false
	humanoidRootPart.Anchored = true

	local function collectFallbackWaypoints(goalPosition)
		local currentWaypoints = getWaypoints()
		if not currentWaypoints then
			return { { Position = goalPosition, MapIndex = 1 } }
		end

		for _, waypoint in ipairs(currentWaypoints:GetChildren()) do
			if not table.find(staticWaypoints, waypoint) then
				table.insert(staticWaypoints, waypoint)
			end
		end
		table.sort(staticWaypoints, function(a, b)
			return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0)
		end)

		local positions = {}
		for index, waypoint in ipairs(staticWaypoints) do
			if index >= mapWaypointIndex then
				table.insert(positions, {
					Position = waypoint.Position,
					MapIndex = index,
				})
			end
		end
		table.insert(positions, {
			Position = goalPosition,
			MapIndex = #staticWaypoints + 1,
		})

		return positions
	end

	local function collectDestroyerTargetRoute(goalPosition)
		return {
			{
				Position = goalPosition,
				IsDestroyerTarget = true,
			},
		}
	end

	local function getHorizontalVector(fromPosition: Vector3, toPosition: Vector3): Vector3
		return Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
	end

	local function getHorizontalDirection(fromPosition: Vector3, toPosition: Vector3, fallbackDirection: Vector3?): Vector3
		local horizontalVector = getHorizontalVector(fromPosition, toPosition)
		if horizontalVector.Magnitude > 0.001 then
			return horizontalVector.Unit
		end

		if fallbackDirection and fallbackDirection.Magnitude > 0.001 then
			return fallbackDirection.Unit
		end

		return Vector3.new(0, 0, -1)
	end

	local function pivotUnitTo(position: Vector3, flatDirection: Vector3?)
		local lookDirection = flatDirection and Vector3.new(flatDirection.X, 0, flatDirection.Z) or Vector3.zero
		if lookDirection.Magnitude <= 0.001 then
			local currentLook = humanoidRootPart.CFrame.LookVector
			lookDirection = Vector3.new(currentLook.X, 0, currentLook.Z)
			if lookDirection.Magnitude <= 0.001 then
				lookDirection = Vector3.new(0, 0, -1)
			end
		end

		humanoidRootPart.CFrame = CFrame.new(position, position + lookDirection.Unit)
	end

	local function tryGroundStep(currentPosition: Vector3, flatDirection: Vector3, maxStepDistance: number, rootHeightOffset: number)
		local lastGroundInfo = nil

		for _, scale in ipairs(STEP_REDUCTION_FACTORS) do
			local horizontalStep = flatDirection * (maxStepDistance * scale)
			local probePosition = currentPosition + Vector3.new(horizontalStep.X, 0, horizontalStep.Z)
			local groundedPosition, groundInfo = DestructionManager.GetGroundPosition(probePosition, { unit }, rootHeightOffset, {
				IgnoreRoutePartsNearHoles = true,
			})
			if groundedPosition then
				return groundedPosition, scale, groundInfo
			end
			lastGroundInfo = groundInfo
		end

		local groundedCurrentPosition, currentGroundInfo = DestructionManager.GetGroundPosition(currentPosition, { unit }, rootHeightOffset, {
			IgnoreRoutePartsNearHoles = true,
		})
		if groundedCurrentPosition then
			return groundedCurrentPosition, 0, currentGroundInfo
		end

		return nil, nil, currentGroundInfo or lastGroundInfo
	end

	local function getDestroyerStrikePosition(currentPosition: Vector3, goalPosition: Vector3, lockedTarget)
		if not stats.Destroyer or destroyerStrikeUsed then
			return nil
		end

		local destroyTarget = lockedTarget
		if destroyTarget and (not destroyTarget:IsDescendantOf(workspace) or destroyTarget:GetAttribute("Destroyed")) then
			destroyTarget = nil
		end
		if not destroyTarget then
			destroyTarget = DestructionManager.FindDestroyerTarget(currentPosition, goalPosition, 24)
		end
		if not destroyTarget then
			return nil
		end

		local strikeDistance = stats.DestroyerAttackRange or math.max((stats.DestructionRadius or 8) + 2, 8)
		if destroyTarget:IsA("BasePart") then
			strikeDistance += math.max(destroyTarget.Size.X, destroyTarget.Size.Z) * 0.35
		end

		if getHorizontalVector(currentPosition, destroyTarget.Position).Magnitude <= strikeDistance then
			return destroyTarget.Position
		end

		return nil
	end

	local function followRoute(route, destroyerTarget)
		local rootHeightOffset = humanoidRootPart.Size.Y / 2
		local lastFlatDirection = Vector3.new(humanoidRootPart.CFrame.LookVector.X, 0, humanoidRootPart.CFrame.LookVector.Z)
		if lastFlatDirection.Magnitude <= 0.001 then
			lastFlatDirection = Vector3.new(0, 0, -1)
		end

		movementDebug(unit.Name, "followRoute start", "routeCount", #route)

		for index, waypoint in ipairs(route) do
			if not unit or not unit.Parent or humanoid.Health <= 0 then
				movementDebug(unit.Name, "followRoute aborted", "state invalid before waypoint", index)
				return false, "InvalidState"
			end

			local waypointMapIndex = typeof(waypoint) == "table" and waypoint.MapIndex or nil

			if waypointMapIndex then
				routeProgress = waypointMapIndex
				unit:SetAttribute("Current", waypointMapIndex)
			else
				routeProgress += 1
				unit:SetAttribute("Current", routeProgress)
			end

			while unit and unit.Parent and humanoid.Health > 0 do
				local targetPos = waypoint.Position
				local currentPosition = humanoidRootPart.Position
				local groundedCurrentPosition = DestructionManager.GetGroundPosition(currentPosition, { unit }, rootHeightOffset, {
					IgnoreRoutePartsNearHoles = true,
				})
				if groundedCurrentPosition then
					currentPosition = groundedCurrentPosition
					pivotUnitTo(currentPosition, lastFlatDirection)
				end

				local destroyerStrikePosition = getDestroyerStrikePosition(currentPosition, finalTarget.Position, destroyerTarget)
				if destroyerStrikePosition then
					return false, "DestroyerReady", {
						ExplosionPosition = destroyerStrikePosition,
					}
				end

				local horizontalDiff = getHorizontalVector(currentPosition, targetPos)
				local horizontalDistance = horizontalDiff.Magnitude
				unit:SetAttribute("Distance", horizontalDistance)

				if horizontalDistance <= WAYPOINT_REACH_DISTANCE then
					if waypointMapIndex then
						mapWaypointIndex = math.max(mapWaypointIndex, waypointMapIndex + 1)
					end
					break
				end

				local dt = task.wait()
				local flatDirection = getHorizontalDirection(currentPosition, targetPos, lastFlatDirection)
				lastFlatDirection = flatDirection
				local stepDistance = math.min(humanoid.WalkSpeed * dt, horizontalDistance)

				-- probe ahead to detect vertical change (slope/crater); if the next
				-- step goes up or down meaningfully, halve the step for this frame
				local probedPos, _, _ = tryGroundStep(currentPosition, flatDirection, stepDistance, rootHeightOffset)
				if probedPos and math.abs(probedPos.Y - currentPosition.Y) > 0.5 then
					stepDistance = stepDistance * 0.5
				end

				local groundedPos, usedScale, groundInfo = tryGroundStep(currentPosition, flatDirection, stepDistance, rootHeightOffset)
				if groundedPos then
					if usedScale and usedScale < 1 then
						movementDebug(unit.Name, "reduced step", "scale", usedScale, "routeIndex", index)
					end
					pivotUnitTo(groundedPos, flatDirection)
				else
					movementDebug(unit.Name, "frame ground miss", formatGroundInfo(groundInfo), "target", targetPos, "routeIndex", index)
					task.wait(0.03)
				end
			end
		end

		movementDebug(unit.Name, "followRoute complete")
		return unit and unit.Parent and humanoid.Health > 0, "Reached"
	end

	task.spawn(function()
		while unit and unit.Parent and humanoid.Health > 0 do
			if not finalTarget then
				return
			end

			local destroyerTarget = nil
			local goalPosition = finalTarget.Position
			local route

			if stats.Destroyer then
				destroyerTarget = DestructionManager.FindDestroyerTarget(
					humanoidRootPart.Position,
					finalTarget.Position,
					stats.DestroyerTargetRange or 220
				)

				if destroyerTarget then
					goalPosition = destroyerTarget.Position
					route = collectDestroyerTargetRoute(goalPosition)
					unit:SetAttribute("TargetingTerrain", true)
					unit:SetAttribute("DestroyerTarget", destroyerTarget.Name)
				else
					unit:SetAttribute("TargetingTerrain", false)
					unit:SetAttribute("DestroyerTarget", "")
				end
			end

			if not route then
				route = collectFallbackWaypoints(goalPosition)
			end

			if #route <= 0 then
				task.wait(0.05)
				continue
			end

			local reached, failureReason, failureInfo = followRoute(route, destroyerTarget)

			if not reached and failureReason == "DestroyerReady" and failureInfo and failureInfo.ExplosionPosition then
				destroyerStrikeUsed = true
				unit:SetAttribute("DestroyingTerrain", true)
				task.wait(0.45 / (workspace:GetAttribute("GameSpeed") or 1))
				DestructionManager.ApplyExplosion(failureInfo.ExplosionPosition, stats.DestructionRadius or 8, stats.DestructionDamage or 140, "Destroyer")
				unit:SetAttribute("DestroyingTerrain", false)
				if stats.Destroyer and unit and unit.Parent then
					unit:Destroy()
					return
				end
				task.wait(0.2)
				continue
			end

			if reached and unit and unit.Parent then
				if stats.Destroyer and destroyerTarget then
					destroyerStrikeUsed = true
					unit:SetAttribute("DestroyingTerrain", true)
					task.wait(0.2 / (workspace:GetAttribute("GameSpeed") or 1))
					DestructionManager.ApplyExplosion(goalPosition, stats.DestructionRadius or 8, stats.DestructionDamage or 140, "Destroyer")
				else
					baseTakeDamage(humanoid.Health)
				end
				unit:Destroy()
			end

			if not reached then
				task.wait(0.05)
				continue
			end

			return
		end
	end)
end

-- applies stats to enemies based on type and difficulty
local function applyEnemyStats(unit: Model, enemyType: string, Difficulty)
	if not unit or not EnemyStats[enemyType] then return end

	local humanoid = findHumanoid(unit)
	if humanoid then
		local baseStats = EnemyStats[enemyType]
		local baseHealth = baseStats.BaseHealth or baseStats.Health
		baseStats.BaseHealth = baseHealth

		-- sets health multiplier based on difficulty
		if workspace:GetAttribute("Difficulty") == "Easy" then
			HEALTH_MULTIPLIER_STEP = .1
		elseif workspace:GetAttribute("Difficulty") == "Medium" then
			HEALTH_MULTIPLIER_STEP = .25
		elseif workspace:GetAttribute("Difficulty") == "Hard" then
			HEALTH_MULTIPLIER_STEP = .35
		elseif workspace:GetAttribute("Difficulty") == "Impossible" then
			HEALTH_MULTIPLIER_STEP = .5
		end

		-- calculates scaled health based on wave number
		local currentWave = workspace:GetAttribute("CurrentWave") or 1
		local healthMultiplier = math.floor((1 + ((currentWave - 1) * HEALTH_MULTIPLIER_STEP)) * 10) / 10
		humanoid.MaxHealth = math.floor(baseHealth * healthMultiplier)

		-- caps easy mode health at 500
		if workspace:GetAttribute("Difficulty") == "Easy" then
			humanoid.MaxHealth = math.min(humanoid.MaxHealth, 500)
		end
		humanoid.Health = humanoid.MaxHealth
		humanoid.WalkSpeed = baseStats.WalkSpeed and baseStats.WalkSpeed * (workspace:GetAttribute("GameSpeed") or 1) or humanoid.WalkSpeed

		-- updates walk speed when game speed changes
		workspace:GetAttributeChangedSignal("GameSpeed"):Connect(function()
			print("changed")
			humanoid.WalkSpeed = baseStats.WalkSpeed and baseStats.WalkSpeed * (workspace:GetAttribute("GameSpeed") or 1) or humanoid.WalkSpeed
		end)	
	end
end

-- creates a tombstone when enemy dies
local function createTomb(CF: CFrame)
	local Tomb = ReplicatedStorage.Storage.GraveStones:FindFirstChild("Default")
	if not Tomb then return end

	local NewTomb = Tomb:Clone()
	local tombSizeY = NewTomb.Size.Y

	-- raycasts to find ground level
	local rayOrigin = CF.Position
	local rayDirection = Vector3.new(0, -50, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {NewTomb, Path}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	local newPos = CF.Position
	if result then
		newPos = Vector3.new(newPos.X, result.Position.Y + (tombSizeY / 2) - 2, newPos.Z)
	end

	-- drops the tombstone from above
	local startPos = newPos + Vector3.new(0, 15, 0)
	local newCF = CFrame.new(newPos, newPos + CF.LookVector)

	NewTomb.CFrame = CFrame.new(startPos, startPos + CF.LookVector)
	NewTomb.Parent = workspace

	local dropTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Back)
	local dropTween = TweenService:Create(NewTomb, dropTweenInfo, {CFrame = newCF})
	dropTween:Play()

	-- removes the tombstone after a delay
	task.spawn(function()
		dropTween.Completed:Wait()
		task.wait(4.75)

		local shrinkTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local shrinkTween = TweenService:Create(NewTomb, shrinkTweenInfo, {Size = Vector3.new(0.1, 0.1, 0.1), Position = NewTomb.Position - Vector3.new(0,3,0)})
		shrinkTween:Play()
		shrinkTween.Completed:Wait()

		NewTomb:Destroy()
	end)
end

-- creates a crater effect for tnt enemies
local function createCrater(Position: Vector3, Radius: number, PartCount: number)
	local craterFolder = workspace:FindFirstChild("CraterParts")
	if not craterFolder then return end

	-- creates the crater ring
	local angleIncrement = 2 * math.pi / PartCount
	for i = 0, PartCount - 1 do
		local angle = i * angleIncrement
		local x = Position.X + Radius * math.cos(angle)
		local z = Position.Z + Radius * math.sin(angle)
		local partPosition = Vector3.new(x, Position.Y, z)

		local craterPart = Instance.new("Part")
		craterPart.Size = Vector3.new(1.5, 1, 1.5)
		craterPart.Material = Enum.Material.Ground
		craterPart.Color = Color3.fromRGB(86, 66, 54)
		craterPart.Position = partPosition
		craterPart.Anchored = true
		craterPart.CanCollide = false

		local direction = (Position - partPosition).Unit
		local tilt = CFrame.new(partPosition, partPosition + direction) * CFrame.Angles(math.rad(15), 0, 0)
		craterPart.CFrame = tilt

		craterPart.Parent = craterFolder

		-- fades out crater parts
		task.delay(3, function()
			local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Linear)
			local tween = TweenService:Create(craterPart, tweenInfo, {Transparency = 1})
			tween:Play()
			tween.Completed:Connect(function()
				craterPart:Destroy()
			end)
		end)
	end

	-- creates flying debris particles
	task.delay(0.1, function()
		for i = 1, PartCount do
			local randomSize = math.random(25, 60) / 100
			local part = Instance.new("Part")
			part.Size = Vector3.new(randomSize, randomSize, randomSize)
			part.Material = Enum.Material.Slate
			part.Color = Color3.fromRGB(86, 66, 54)
			part.Position = Position + Vector3.new(
				math.random(-Radius, Radius),
				math.random(0, 3),
				math.random(-Radius, Radius)
			)
			part.Anchored = false
			part.CanCollide = false
			part.Parent = craterFolder
			part.Orientation = Vector3.new(math.random(0, 360), math.random(0, 360), math.random(0, 360))

			-- launches debris upward
			local debrisForce = Instance.new("BodyVelocity")
			debrisForce.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			debrisForce.Velocity = Vector3.new(
				math.random(-25, 25),
				math.random(25, 55),
				math.random(-25, 25)
			)
			debrisForce.P = 1000
			debrisForce.Parent = part

			game:GetService("Debris"):AddItem(debrisForce, 0.25)

			-- fades out debris
			task.delay(math.random(2, 3), function()
				local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Linear)
				local tween = TweenService:Create(part, tweenInfo, {Transparency = 1})
				tween:Play()
				tween.Completed:Connect(function()
					part:Destroy()
				end)
			end)
		end
	end)
end

-- spawns an enemy unit
local function spawnUnit(unitName: string)
	spawnDebug("spawn requested", unitName)

	local enemyInfo = EnemyStats[unitName]
	local modelName = enemyInfo and (enemyInfo.Model or enemyInfo.ModelName) or unitName
	local unitFolder = getUnitFolder()
	local selectedUnit = unitFolder and (unitFolder:FindFirstChild(unitName) or unitFolder:FindFirstChild(modelName))

	if not selectedUnit then
		spawnDebug("unit model not found", modelName, "for enemy", unitName, "using random/fallback")
		selectedUnit = chooseRandomUnit()
	end

	local CreatedUnit: Model = selectedUnit and selectedUnit:Clone()
	if not CreatedUnit and ALLOW_GENERATED_ENEMY_FALLBACK then
		CreatedUnit = createFallbackEnemyModel(unitName)
	end
	if not CreatedUnit then
		spawnDebug("spawn failed: clone/fallback missing for", unitName)
		return nil
	end
	CreatedUnit.Name = unitName
	CreatedUnit:SetAttribute("SourceModel", selectedUnit and selectedUnit.Name or modelName)

	local path = getPath()
	if not path then
		spawnDebug("spawn failed: workspace.Path missing for", unitName)
		CreatedUnit:Destroy()
		return nil
	end

	local SpawnPart = path:FindFirstChild("Enemy_Spawn")
	if not SpawnPart then
		spawnDebug("spawn failed: Enemy_Spawn missing for", unitName)
		CreatedUnit:Destroy()
		return nil
	end

	local humanoid = findHumanoid(CreatedUnit)
	local rootPart = findRootPart(CreatedUnit)
	if (not humanoid or not rootPart) and ALLOW_GENERATED_ENEMY_FALLBACK then
		spawnDebug("real/random model invalid; replacing with fallback", unitName, "humanoid", humanoid ~= nil, "root", rootPart ~= nil)
		CreatedUnit:Destroy()
		CreatedUnit = createFallbackEnemyModel(unitName)
		CreatedUnit:SetAttribute("SourceModel", "GeneratedFallback")
		humanoid = findHumanoid(CreatedUnit)
		rootPart = findRootPart(CreatedUnit)
	end

	if not humanoid or not rootPart then
		spawnDebug("spawn failed: invalid enemy model", unitName, "model", modelName, "humanoid", humanoid ~= nil, "root", rootPart ~= nil)
		CreatedUnit:Destroy()
		return nil
	end

	local HealthBar = HealthBillboardTemplate and HealthBillboardTemplate:Clone()
	local Bar = nil
	local TowerName = nil
	local HPText = nil

	if HealthBar then
		local Container = HealthBar:FindFirstChild("Worm_Health")
		if Container then
			Bar = Container:FindFirstChild("Bar")
			TowerName = Container:FindFirstChild("Tower_Name")
			HPText = Container:FindFirstChild("HP")
		else
			spawnDebug("health billboard missing Worm_Health; continuing spawn", unitName)
		end
	else
		spawnDebug("health billboard missing; continuing spawn", unitName)
	end

	-- sets up the unit in workspace
	if HealthBar then
		HealthBar.Parent = rootPart
	end

	for _, descendant in ipairs(CreatedUnit:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CollisionGroup = collision_Group
		end
	end

	CreatedUnit.Parent = getEnemyFolder()
	CreatedUnit:PivotTo(SpawnPart.CFrame)
	CreatedUnit:SetAttribute("Current", 0)

	if TowerName then
		TowerName.Text = CreatedUnit.Name
	end

	-- shows boss health bar for boss enemies
	if enemyInfo and enemyInfo.Boss then
		Remotes:FindFirstChild("Game"):FindFirstChild("ShowBossBar"):FireAllClients(CreatedUnit)
	end

	applyEnemyStats(CreatedUnit, unitName)
	spawnDebug("spawned", unitName, "model", CreatedUnit:GetAttribute("SourceModel"), "at", SpawnPart.Position)

	-- updates the health bar display
	local function updateHealth()
		if not humanoid or not Bar or not HPText then return end
		local ratio = humanoid.Health / humanoid.MaxHealth
		Bar.Size = UDim2.new(ratio, 0, 1, 0)
		HPText.Text = string.format("%d / %d", humanoid.Health, humanoid.MaxHealth)
	end

	local ghostSpawned = false

	-- handles health changes and scientist ghost spawn
	humanoid.HealthChanged:Connect(function(newHealth)
		updateHealth()

		-- spawns a ghost when scientist health is low
		if CreatedUnit.Name == "Mad Worm Scientist" and newHealth <= 20 and not ghostSpawned then
			ghostSpawned = true

			task.delay(0.1, function()
				spawnUnit("Phantom Worm")
			end)
		end
	end)

	updateHealth()

	-- handles enemy death
	if humanoid then
		humanoid.Died:Connect(function()

			local PrimaryPart = CreatedUnit.PrimaryPart
			if not PrimaryPart then return end

			-- creates crater for tnt enemies
			if CreatedUnit.Name == "Walking Dynamite" or CreatedUnit:GetAttribute("SourceModel") == "TNT" then
				createCrater(PrimaryPart.Position - Vector3.new(0, 2.7, 0), 1.5, 8)
				DestructionManager.ApplyExplosion(PrimaryPart.Position - Vector3.new(0, 2.7, 0), 7, 120, "Enemy")
			end

			local unitCF = CreatedUnit:GetPrimaryPartCFrame()
			createTomb(unitCF)
			CreatedUnit:Destroy()
		end)
	end

	moveUnit(CreatedUnit)
	return CreatedUnit
end

-- functions

-- starts a single wave
function RoundManager.StartWave(WaveNumber, visualwave)
	local waveName = tostring(WaveNumber)
	local unitList = WaveUnits[waveName]

	if not unitList then
		spawnDebug("wave missing in WaveUnits", waveName)
		return
	end

	print("Starting", waveName)
	spawnDebug("wave", waveName, "visual", visualwave or WaveNumber, "units", table.concat(unitList, ", "))
	Remotes.Game.SendNotification:FireAllClients("Wave "..tostring(visualwave or WaveNumber), "Normal")
	local unitsAlive = #unitList
	CrateDropManager.StartWave(visualwave or WaveNumber)

	-- spawns each unit in the wave
	for _, unitName in ipairs(unitList) do
		local unit
		local ok, result = pcall(function()
			return spawnUnit(unitName)
		end)

		if ok then
			unit = result
		else
			unitsAlive -= 1
			spawnDebug("spawn error", unitName, "wave", waveName, result, "aliveLeft", unitsAlive)
		end

		if unit then
			-- tracks when units are destroyed
			unit.AncestryChanged:Connect(function(_, parent)
				if not parent then
					unitsAlive -= 1
					spawnDebug("unit removed", unitName, "aliveLeft", unitsAlive)
				end
			end)
			task.delay(1, function()
				if unit and unit.Parent then
					spawnDebug("unit alive check", unitName, "parent", unit.Parent.Name, "position", unit.PrimaryPart and unit.PrimaryPart.Position or "no primary")
				end
			end)
		elseif ok then
			unitsAlive -= 1
			spawnDebug("spawn returned nil", unitName, "aliveLeft", unitsAlive)
		end
		-- calculates spawn delay that decreases each wave
		local spawnDelay = math.max(0.5, BASE_SPAWN_DELAY - ((WaveNumber - 1) * SPAWN_TIME_STEP))

		task.wait(spawnDelay)
	end

	Remotes.Game.SkipWave:FireAllClients()

	-- waits for wave to complete or timer to expire
	while true do
		task.wait(0.1)

		if GlobalValues.Base_Health.Value <= 0 then
			break
		end

		if WaveNumber ~= MAX_ROUNDS then
			if TimeTillNext <= 0 or workspace:GetAttribute("Skip") or unitsAlive <= 0 then
				workspace:SetAttribute("Skip", nil)
				break
			end
		else
			if unitsAlive <= 0 then
				break
			end
		end
	end

	if GlobalValues.Base_Health.Value <= 0 then
		CrateDropManager.StopWave()
		return
	end

	print(waveName, "completed")
	CrateDropManager.StopWave()

	-- gives players cash after wave completion
	for _, Plr in ipairs(Players:GetPlayers()) do
		Plr:SetAttribute("TempCash", Plr:GetAttribute("TempCash") + ((math.clamp(50 * WaveNumber, 0, 250))/#Players:GetPlayers()))
	end
end

-- awards money to all players based on difficulty
local function awardAllMoney(DifficultyName)

	local AmountToGive = 0

	if DifficultyName == "Easy" then
		AmountToGive = 500
	elseif DifficultyName == "Medium" then
		AmountToGive = 1500
	elseif DifficultyName == "Hard" then
		AmountToGive = 4500
	elseif DifficultyName == "Impossible" then
		AmountToGive = 7500
	end

	if AmountToGive > 0 then

		for _, Player in ipairs(Players:GetPlayers()) do

			local UserData = Player:FindFirstChild("UserData")
			if not UserData then return end 

			local Money = UserData:FindFirstChild("Money")
			if not Money then return end 

			Money.Value = Money.Value + AmountToGive
		end

	end

end

-- starts the entire game
function RoundManager.StartGame(TotalWaves, DifficultyPreset, Gamemode, DifficultyName, MapName)
	DestructionManager.PrepareMap()
	local isEndless = tostring(Gamemode):lower() == "endless"
	local isTutorial = MapName == "Tutorial"
	workspace:SetAttribute("GameStartTime", tick())
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("MatchWon", false)
	end

	MAX_ROUNDS = TotalWaves
	WaveUnits = DifficultyPreset
	debugSpawnState()

	workspace:SetAttribute("Difficulty", DifficultyName)
	workspace:SetAttribute("MapName", MapName or "")

	TotalWaves = MAX_ROUNDS

	-- collects and sorts available waves
	local availableWaves = {}
	for waveName, _ in pairs(WaveUnits) do
		table.insert(availableWaves, waveName)
	end
	table.sort(availableWaves, function(a, b)
		return tonumber(a:match("%d+")) < tonumber(b:match("%d+"))
	end)

	local totalDefinedWaves = #availableWaves

	-- displays round counter
	if isEndless then
		Remotes.Game.DisplayRound:FireAllClients(0, "Endless")
	else
		Remotes.Game.DisplayRound:FireAllClients(0, totalDefinedWaves)
	end
	Remotes.Game.StartTimer:FireAllClients(15)
	task.wait(15)

	local waveIndex = 1
	local cycleCount = 0

	-- loops through all waves
	while true do
		-- handles endless mode cycling
		if waveIndex > totalDefinedWaves then
			if isEndless then
				waveIndex = 1
				cycleCount += 1

				-- scales enemy stats for endless mode
				local multiplier = 1 + (cycleCount * 0.1)
				for enemyType, stats in pairs(EnemyStats) do
					stats.Health = math.floor(stats.Health * multiplier)
					stats.WalkSpeed = stats.WalkSpeed * (1 + (cycleCount * 0.02))
				end

				print(string.format("[Endless] Cycle %d: Enemies now x%.1f HP", cycleCount, multiplier))
			else
				break
			end
		end

		local waveName = availableWaves[waveIndex]
		local waveNumber = tonumber(waveName:match("%d+")) or waveIndex

		TimeTillNext = 60

		workspace:SetAttribute("Timer", TimeTillNext)

		workspace:SetAttribute("CurrentWave", waveNumber + (totalDefinedWaves * cycleCount))
		if isEndless then
			Remotes.Game.DisplayRound:FireAllClients(waveNumber + (totalDefinedWaves * cycleCount), "Endless")
		else
			Remotes.Game.DisplayRound:FireAllClients(waveNumber, totalDefinedWaves)
		end

		RoundManager.StartWave(waveNumber, waveNumber + (totalDefinedWaves * cycleCount))

		-- checks if game ended early
		if GlobalValues.Base_Health.Value <= 0 then
			print("Game ended early during wave", waveNumber)
			return
		end

		waveIndex += 1
		task.wait(.25)
	end

	-- calculates final time
	local TimeEnd = tick()
	local TimeTaken = TimeEnd - workspace:GetAttribute("GameStartTime")
	local minutes = math.floor(TimeTaken / 60)
	local seconds = math.floor(TimeTaken % 60)
	local formattedTime = string.format("%d:%02d", minutes, seconds)

	if not isTutorial then
		awardAllMoney(DifficultyName)
	end

	-- updates player stats on win
	for _, player in ipairs(game.Players:GetPlayers()) do
		player:SetAttribute("MatchWon", true)

		local userData = player:FindFirstChild("UserData")
		if userData then
			if isTutorial then
				local tutorialValue = userData:FindFirstChild("CompletedTutorial")
				if tutorialValue and tutorialValue:IsA("BoolValue") then
					tutorialValue.Value = true
				end
			end

			pcall(function()
				userData.Statistics.Wins.Value += 1

				if not(player:GetAttribute("Wins")) then
					player:SetAttribute("Wins", 1)
				else
					player:SetAttribute("Wins", player:GetAttribute("Wins") + 1)
				end
			end)
		end
	end

	-- notifies players of victory
	Remotes.Game.SendNotification:FireAllClients("You won!", "Success")
	Remotes.Game.ShowResults:FireAllClients(MAX_ROUNDS, formattedTime, "Won")

	-- updates clan stats on win
	local Cache = GetClanData()

	if Cache then
		for _, Player in ipairs(Players:GetPlayers()) do
			local ClanTag = DataStore.Stored[Player.UserId].Data.ClanTag
			if ClanTag then 
				if Cache.Clans[ClanTag] then
					if Player:GetAttribute("WormsKilled") then
						Cache.Clans[ClanTag].Stats.Killed += Player:GetAttribute("WormsKilled")
					end
					if Player:GetAttribute("TowersPlaced") then
						Cache.Clans[ClanTag].Stats.Placed += Player:GetAttribute("TowersPlaced")
					end
					Cache.Clans[ClanTag].Stats.Wins += 1	
				else
					print("no clan")
				end
			else
				print("nope")
			end
		end

		SaveClanData(Cache)
	end
end

-- applies slowness effect to enemies
GameRemotes:FindFirstChild("ApplySlowness").Event:Connect(function(humanoid, slowFactor, duration)
	if not humanoid then return end

	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = math.max(1, originalSpeed * slowFactor)

	task.delay(duration, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalSpeed
		end
	end)
end)

-- handles game speed changes from client
GameRemotes:WaitForChild("GameSpeed").OnServerEvent:Connect(function(Plr, Speed)
	local cleanedSpeed = string.gsub(Speed, "x", "")
	local TargetSpeed = tonumber(cleanedSpeed)

	if TargetSpeed then
		workspace:SetAttribute("GameSpeed", TargetSpeed)
	end
end)

-- decreases the wave timer
task.spawn(function()
	while task.wait(.1) do
		if TimeTillNext then
			TimeTillNext -= .1 * (workspace:GetAttribute("GameSpeed") or 1)
			workspace:SetAttribute("Timer", TimeTillNext)
		end
	end
end)

-- handles wave skip requests
Remotes.Game.SkipWave.OnServerEvent:Connect(function()
	workspace:SetAttribute("Skip", true)
end)

return RoundManager
