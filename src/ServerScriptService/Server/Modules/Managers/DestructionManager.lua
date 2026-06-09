-- SERVICES
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local GeometryService = game:GetService("GeometryService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

-- CONSTANTS
local TAG_DESTRUCTIBLE = "Destructible"
local TAG_DESTRUCTIBLE_ROUTE = "DestructibleRoute"
local TAG_DESTRUCTIBLE_TOWER_SPOT = "DestructibleTowerSpot"
local TAG_HIGH_FIDELITY_CSG = "HighFidelityCSG"
local TAG_INDESTRUCTIBLE = "Indestructible"
local TAG_DEBRIS = "DestructionDebris"
local TAG_HOLE_BLOCKER = "DestructionHole"

local DEBRIS_COLLISION_GROUP = "DestructionDebris"
local TERRAIN_RESOLUTION = 4
local DEFAULT_EXPLOSION_RADIUS = 7
local DEFAULT_EXPLOSION_DAMAGE = 100
local MAX_CSG_PER_EXPLOSION = 1
local LARGE_SURFACE_MIN_AXIS = 80
local PATH_MODEL_BREAK_RADIUS_SCALE = 0.7
local PATH_MODEL_BREAK_MIN_RADIUS = 5
local PATH_HOLE_PADDING = 1.5
local PATH_HOLE_HEIGHT_PADDING = 8
local DESTRUCTION_DEBUG = false

local CRITICAL_ROOT_NAMES = {
	Base = true,
}

local IGNORE_ROOT_NAMES = {
	Towers = true,
	Enemies = true,
	CraterParts = true,
	CrateDrops = true,
	Path = true,
}

local CRITICAL_NAMES = {
	Enemy_Spawn = true,
	Enemy_Target = true,
	SpawnPos = true,
	CenterPart = true,
	Waypoints = true,
}

local PATH_COSTS = {
	DestructibleRoute = 2,
	DestructibleTowerSpot = 5,
	DestructionDebris = 100000,
}

-- VARIABLES
local DestructionManager = {}
local changedEvent = Instance.new("BindableEvent")
local prepared = false
local revision = 0
local initialRoutePartCount = 0

DestructionManager.Changed = changedEvent.Event

-- SETUP
pcall(function()
	if not PhysicsService:IsCollisionGroupRegistered(DEBRIS_COLLISION_GROUP) then
		PhysicsService:RegisterCollisionGroup(DEBRIS_COLLISION_GROUP)
	end

	PhysicsService:CollisionGroupSetCollidable(DEBRIS_COLLISION_GROUP, "Worms", false)
	PhysicsService:CollisionGroupSetCollidable(DEBRIS_COLLISION_GROUP, "Players", false)
	PhysicsService:CollisionGroupSetCollidable(DEBRIS_COLLISION_GROUP, DEBRIS_COLLISION_GROUP, false)
end)

-- FUNCTIONS
local function getDebrisFolder()
	local folder = workspace:FindFirstChild("DestructionDebris")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DestructionDebris"
		folder.Parent = workspace
	end

	return folder
end

local function destructionDebug(...)
	if DESTRUCTION_DEBUG then
		warn("[DestructionDebug]", ...)
	end
end

local function getHoleFolder()
	local folder = workspace:FindFirstChild("DestructionHoles")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DestructionHoles"
		folder.Parent = workspace
	end

	return folder
end

local function buildGroundIgnoreList(extraIgnore)
	local ignoreList = {
		workspace:FindFirstChild("Enemies"),
		workspace:FindFirstChild("Path"),
		workspace:FindFirstChild("CraterParts"),
		workspace:FindFirstChild("CrateDrops"),
		workspace:FindFirstChild("DestructionDebris"),
	}

	if extraIgnore then
		for _, instance in ipairs(extraIgnore) do
			table.insert(ignoreList, instance)
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignoreList, player.Character)
		end
	end

	for index = #ignoreList, 1, -1 do
		if not ignoreList[index] then
			table.remove(ignoreList, index)
		end
	end

	return ignoreList
end

local function getLiveRoutePartCount()
	local count = 0
	for _, part in ipairs(CollectionService:GetTagged(TAG_DESTRUCTIBLE_ROUTE)) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and not part:GetAttribute("Destroyed") then
			count += 1
		end
	end

	return count
end

local function getPartVolume(part)
	return math.max(part.Size.X * part.Size.Y * part.Size.Z, 1)
end

local function hasHumanoidAncestor(instance)
	local ancestor = instance.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
			return true
		end
		ancestor = ancestor.Parent
	end

	return false
end

local function isInNamedRoot(instance, roots)
	for rootName in pairs(roots) do
		local root = workspace:FindFirstChild(rootName)
		if root and instance:IsDescendantOf(root) then
			return true
		end
	end

	return false
end

local function isCritical(instance)
	if not instance then return false end
	if CRITICAL_NAMES[instance.Name] then return true end
	if CollectionService:HasTag(instance, TAG_INDESTRUCTIBLE) then return true end
	return isInNamedRoot(instance, CRITICAL_ROOT_NAMES)
end

local function isProtected(instance)
	if not instance then return true end
	if isCritical(instance) then return true end
	if isInNamedRoot(instance, IGNORE_ROOT_NAMES) then return true end
	if hasHumanoidAncestor(instance) then return true end
	return false
end

local function isLargeSurface(part)
	return part.Size.X >= LARGE_SURFACE_MIN_AXIS or part.Size.Z >= LARGE_SURFACE_MIN_AXIS
end

local function addPathfindingModifier(part, label)
	if part:FindFirstChild("DestructionPathfindingModifier") then
		return
	end

	local modifier = Instance.new("PathfindingModifier")
	modifier.Name = "DestructionPathfindingModifier"
	modifier.Label = label
	modifier.PassThrough = false
	modifier.Parent = part
end

local function tagDestructible(part, routeLike)
	if isProtected(part) or not part:IsA("BasePart") then
		return
	end

	CollectionService:AddTag(part, TAG_DESTRUCTIBLE)

	if routeLike then
		CollectionService:AddTag(part, TAG_DESTRUCTIBLE_ROUTE)
		addPathfindingModifier(part, TAG_DESTRUCTIBLE_ROUTE)
	end

	if isLargeSurface(part) and (part:IsA("Part") or part:IsA("UnionOperation")) then
		CollectionService:AddTag(part, TAG_HIGH_FIDELITY_CSG)
		part:SetAttribute("DestructionLargeSurface", true)
	end

	if not part:GetAttribute("DestructionMaxHealth") then
		part:SetAttribute("DestructionMaxHealth", math.clamp(math.floor(getPartVolume(part) * 0.8), 80, 900))
	end
end

local function notifyChanged(position)
	revision += 1
	changedEvent:Fire(revision, position)
end

local function getExplosionOverlap(position, radius)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = {
		workspace:FindFirstChild("Path"),
		workspace:FindFirstChild("Enemies"),
		workspace:FindFirstChild("Towers"),
		workspace:FindFirstChild("CraterParts"),
		workspace:FindFirstChild("CrateDrops"),
		workspace:FindFirstChild("DestructionDebris"),
	}

	local filtered = {}
	for _, instance in ipairs(overlapParams.FilterDescendantsInstances) do
		if instance then
			table.insert(filtered, instance)
		end
	end
	overlapParams.FilterDescendantsInstances = filtered

	return workspace:GetPartBoundsInRadius(position, radius, overlapParams)
end

local function isNearCritical(position, radius)
	local path = workspace:FindFirstChild("Path")
	local parts = workspace:GetPartBoundsInRadius(position, radius)
	for _, part in ipairs(parts) do
		if path and part:IsDescendantOf(path) then
			continue
		end
		if isCritical(part) then
			return true
		end
	end

	return false
end

local function createDebris(position, sourcePart, radius)
	local debrisFolder = getDebrisFolder()
	local count = math.clamp(math.floor(radius * 1.4), 4, 12)
	local color = sourcePart and sourcePart.Color or Color3.fromRGB(86, 66, 54)
	local material = sourcePart and sourcePart.Material or Enum.Material.Slate

	for _ = 1, count do
		local size = math.random(35, 90) / 100
		local debrisPart = Instance.new("Part")
		debrisPart.Name = "DestructionDebris"
		debrisPart.Size = Vector3.new(size, size, size)
		debrisPart.Material = material
		debrisPart.Color = color
		debrisPart.Anchored = false
		debrisPart.CanCollide = false
		debrisPart.CanTouch = false
		debrisPart.CanQuery = false
		debrisPart.CFrame = CFrame.new(position + Vector3.new(
			math.random(-radius, radius),
			math.random(1, 5),
			math.random(-radius, radius)
		))
		debrisPart.Parent = debrisFolder
		CollectionService:AddTag(debrisPart, TAG_DEBRIS)

		pcall(function()
			debrisPart.CollisionGroup = DEBRIS_COLLISION_GROUP
		end)

		local direction = (debrisPart.Position - position)
		if direction.Magnitude < 0.1 then
			direction = Vector3.new(math.random() - 0.5, 1, math.random() - 0.5)
		end
		direction = direction.Unit

		pcall(function()
			debrisPart:ApplyImpulse((direction * math.random(50, 110) + Vector3.new(0, math.random(45, 85), 0)) * debrisPart.AssemblyMass)
		end)

		Debris:AddItem(debrisPart, math.random(3, 6))
	end
end

local function describePart(part)
	if not part then
		return "nil"
	end

	local tags = CollectionService:GetTags(part)
	table.sort(tags)

	return string.format(
		"%s (%s) size=(%.1f, %.1f, %.1f) pos=(%.1f, %.1f, %.1f) tags=%s destroyed=%s collide=%s query=%s transparency=%.2f",
		part:GetFullName(),
		part.ClassName,
		part.Size.X,
		part.Size.Y,
		part.Size.Z,
		part.Position.X,
		part.Position.Y,
		part.Position.Z,
		#tags > 0 and table.concat(tags, ",") or "none",
		tostring(part:GetAttribute("Destroyed") == true),
		tostring(part.CanCollide),
		tostring(part.CanQuery),
		part.Transparency
	)
end

local function createPathHoleBlocker(part)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	local blocker = Instance.new("Part")
	blocker.Name = "PathHoleBlocker"
	blocker.Size = Vector3.new(
		math.max(part.Size.X + PATH_HOLE_PADDING, 4),
		math.max(part.Size.Y + PATH_HOLE_HEIGHT_PADDING, 10),
		math.max(part.Size.Z + PATH_HOLE_PADDING, 4)
	)
	blocker.CFrame = part.CFrame
	blocker.Anchored = true
	blocker.Transparency = 1
	blocker.CanCollide = false
	blocker.CanTouch = false
	blocker.CanQuery = true
	blocker:SetAttribute("SourcePartName", part.Name)
	blocker:SetAttribute("SourcePartClass", part.ClassName)
	blocker.Parent = getHoleFolder()
	CollectionService:AddTag(blocker, TAG_HOLE_BLOCKER)

	local modifier = Instance.new("PathfindingModifier")
	modifier.Name = "HolePathfindingModifier"
	modifier.PassThrough = false
	modifier.Parent = blocker

	destructionDebug("hole blocker created", describePart(part), "blockerSize", blocker.Size)

	return blocker
end

local function carvePartWithCSG(part, position, radius)
	local cutter = Instance.new("Part")
	cutter.Name = "DestructionCutter"
	cutter.Shape = Enum.PartType.Ball
	cutter.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	cutter.CFrame = CFrame.new(position)
	cutter.Anchored = true
	cutter.CanCollide = false
	cutter.CanQuery = false
	cutter.Transparency = 1
	cutter.Parent = workspace

	local success, result = pcall(function()
		return GeometryService:SubtractAsync(part, { cutter }, {
			CollisionFidelity = Enum.CollisionFidelity.Default,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)

	cutter:Destroy()

	if not success or not result then
		return false
	end

	local resultParts = typeof(result) == "table" and result or { result }
	if #resultParts == 0 then
		return false
	end

	local parent = part.Parent
	local name = part.Name
	local anchored = part.Anchored
	local canCollide = part.CanCollide
	local tags = CollectionService:GetTags(part)
	local attributes = part:GetAttributes()

	for _, newPart in ipairs(resultParts) do
		if newPart:IsA("BasePart") then
			newPart.Name = name
			newPart.Anchored = anchored
			newPart.CanCollide = canCollide
			newPart.Parent = parent

			for attributeName, value in pairs(attributes) do
				newPart:SetAttribute(attributeName, value)
			end

			for _, tag in ipairs(tags) do
				CollectionService:AddTag(newPart, tag)
			end

			if CollectionService:HasTag(newPart, TAG_DESTRUCTIBLE_ROUTE) then
				addPathfindingModifier(newPart, TAG_DESTRUCTIBLE_ROUTE)
			elseif CollectionService:HasTag(newPart, TAG_DESTRUCTIBLE_TOWER_SPOT) then
				addPathfindingModifier(newPart, TAG_DESTRUCTIBLE_TOWER_SPOT)
			end
		end
	end

	part:Destroy()
	return true
end

local function breakPart(part, position, radius, csgBudget)
	if part:GetAttribute("Destroyed") then
		return false, csgBudget
	end

	if CollectionService:HasTag(part, TAG_HIGH_FIDELITY_CSG) and csgBudget > 0 then
		local csgRadius = math.clamp(radius, 3, 18)
		if carvePartWithCSG(part, position, csgRadius) then
			createDebris(position, part, math.min(radius, 8))
			return true, csgBudget - 1
		end
	end

	if part:GetAttribute("DestructionLargeSurface") then
		createDebris(position, part, math.min(radius, 8))
		return false, csgBudget
	end

	part:SetAttribute("Destroyed", true)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	createDebris(position, part, math.min(radius, 8))

	return true, csgBudget
end

local function removeRoutePart(part, position, radius)
	if not part or not part:IsA("BasePart") or part:GetAttribute("Destroyed") then
		return false
	end

	local summary = describePart(part)
	part:SetAttribute("Destroyed", true)
	part:SetAttribute("DestructionHealth", 0)
	createDebris(position, part, math.min(radius, 8))
	createPathHoleBlocker(part)
	destructionDebug("route part removed", summary, "explosionPos", position, "radius", radius)
	part:Destroy()

	return true
end

local function damageDestructiblePart(part, position, radius, damage, csgBudget)
	if not part:IsA("BasePart") then
		return false, csgBudget
	end

	if isProtected(part) then
		return false, csgBudget
	end

	if not CollectionService:HasTag(part, TAG_DESTRUCTIBLE)
		and not CollectionService:HasTag(part, TAG_DESTRUCTIBLE_ROUTE)
		and not CollectionService:HasTag(part, TAG_DESTRUCTIBLE_TOWER_SPOT)
		and not CollectionService:HasTag(part, TAG_HIGH_FIDELITY_CSG) then
		return false, csgBudget
	end

	local distance = (part.Position - position).Magnitude
	local falloff = math.clamp(1 - (distance / math.max(radius, 1)) * 0.45, 0.3, 1)
	local maxHealth = part:GetAttribute("DestructionMaxHealth") or math.clamp(math.floor(getPartVolume(part) * 0.8), 80, 900)
	local currentHealth = part:GetAttribute("DestructionHealth") or maxHealth
	currentHealth -= damage * falloff
	part:SetAttribute("DestructionHealth", currentHealth)

	if currentHealth <= 0 or CollectionService:HasTag(part, TAG_HIGH_FIDELITY_CSG) then
		return breakPart(part, position, radius, csgBudget)
	end

	return false, csgBudget
end

local function isPathModelRoutePart(part)
	local pathModel = workspace:FindFirstChild("Path_Model")
	if not pathModel or not part or not part:IsA("BasePart") then
		return false
	end

	return part:IsDescendantOf(pathModel) and CollectionService:HasTag(part, TAG_DESTRUCTIBLE_ROUTE)
end

local function getPathModelBreakRadius(radius)
	return math.max(radius * PATH_MODEL_BREAK_RADIUS_SCALE, PATH_MODEL_BREAK_MIN_RADIUS)
end

local function collectPathModelRouteParts(parts)
	local routeParts = {}

	for _, part in ipairs(parts) do
		if isPathModelRoutePart(part) and not isProtected(part) and not part:GetAttribute("Destroyed") then
			table.insert(routeParts, part)
		end
	end

	return routeParts
end

local function terrainHasSolidAt(position)
	local region = Region3.new(
		position - Vector3.new(4, 6, 4),
		position + Vector3.new(4, 2, 4)
	):ExpandToGrid(TERRAIN_RESOLUTION)

	local success, materials, occupancies = pcall(function()
		return workspace.Terrain:ReadVoxels(region, TERRAIN_RESOLUTION)
	end)

	if not success or not materials or not occupancies then
		return true
	end

	for x = 1, #materials do
		for y = 1, #materials[x] do
			for z = 1, #materials[x][y] do
				if materials[x][y][z] ~= Enum.Material.Air and occupancies[x][y][z] > 0.35 then
					return true
				end
			end
		end
	end

	return false
end

local function isValidSupportPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if CollectionService:HasTag(part, TAG_HOLE_BLOCKER) then
		return false
	end

	if part:GetAttribute("Destroyed") then
		return false
	end

	if CollectionService:HasTag(part, TAG_DEBRIS) then
		return false
	end

	if part.Transparency >= 1 and not part.CanCollide then
		return false
	end

	return part.CanCollide or part.Name == "Baseplate"
end

local function isValidMovementSupportPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if CollectionService:HasTag(part, TAG_HOLE_BLOCKER) then
		return false
	end

	if part:GetAttribute("Destroyed") then
		return false
	end

	if CollectionService:HasTag(part, TAG_DEBRIS) then
		return false
	end

	if isPathModelRoutePart(part) then
		return true
	end

	return part.CanCollide or part.Name == "Baseplate"
end

local function isGroundCloseToFootprint(targetCFrame, towerModel, groundPosition)
	local halfHeight = 3
	if towerModel and towerModel.PrimaryPart then
		halfHeight = towerModel.PrimaryPart.Size.Y / 2
	end

	local bottomY = targetCFrame.Position.Y - halfHeight
	return math.abs(bottomY - groundPosition.Y) <= 3
end

local function isNearHoleBlocker(position, maxRange)
	local holeFolder = workspace:FindFirstChild("DestructionHoles")
	if not holeFolder then
		return false
	end

	for _, blocker in ipairs(holeFolder:GetChildren()) do
		if blocker:IsA("BasePart") and (blocker.Position - position).Magnitude <= maxRange then
			return true
		end
	end

	return false
end

local function raycastGround(position, extraIgnore, options)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = buildGroundIgnoreList(extraIgnore)
	local origin = position + Vector3.new(0, 18, 0)
	local direction = Vector3.new(0, -90, 0)
	local stopOnHoleBlocker = not (options and options.IgnoreHoleBlockers)
	local ignoreRoutePartsNearHoles = options and options.IgnoreRoutePartsNearHoles

	for _ = 1, 12 do
		raycastParams.FilterDescendantsInstances = ignoreList
		local result = workspace:Raycast(origin, direction, raycastParams)
		if not result then
			return nil
		end

		if result.Instance == workspace.Terrain then
			return result
		end

		if result.Instance.Name == "BuildBlock2" then
			table.insert(ignoreList, result.Instance)
			continue
		end

		if CollectionService:HasTag(result.Instance, TAG_HOLE_BLOCKER) then
			if stopOnHoleBlocker then
				return result
			end

			table.insert(ignoreList, result.Instance)
			continue
		end

		if ignoreRoutePartsNearHoles and isPathModelRoutePart(result.Instance) and isNearHoleBlocker(result.Position, 18) then
			table.insert(ignoreList, result.Instance)
			continue
		end

		if isValidMovementSupportPart(result.Instance) or isValidSupportPart(result.Instance) then
			return result
		end

		table.insert(ignoreList, result.Instance)
	end

	return nil
end

function DestructionManager.PrepareMap()
	if prepared then
		return
	end
	prepared = true

	local base = workspace:FindFirstChild("Base")
	if base then
		CollectionService:AddTag(base, TAG_INDESTRUCTIBLE)
	end

	local path = workspace:FindFirstChild("Path")
	if path then
		CollectionService:AddTag(path, TAG_INDESTRUCTIBLE)
	end

	local pathModel = workspace:FindFirstChild("Path_Model")
	if pathModel then
		for _, descendant in ipairs(pathModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				tagDestructible(descendant, true)
			end
		end
	end

	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") and not isProtected(baseplate) then
		tagDestructible(baseplate, true)
		if baseplate:IsA("Part") or baseplate:IsA("UnionOperation") then
			CollectionService:AddTag(baseplate, TAG_HIGH_FIDELITY_CSG)
			baseplate:SetAttribute("DestructionLargeSurface", true)
		end
	end

	for _, part in ipairs(CollectionService:GetTagged(TAG_DESTRUCTIBLE_ROUTE)) do
		if part:IsA("BasePart") then
			addPathfindingModifier(part, TAG_DESTRUCTIBLE_ROUTE)
		end
	end

	for _, part in ipairs(CollectionService:GetTagged(TAG_DESTRUCTIBLE_TOWER_SPOT)) do
		if part:IsA("BasePart") then
			addPathfindingModifier(part, TAG_DESTRUCTIBLE_TOWER_SPOT)
		end
	end

	initialRoutePartCount = getLiveRoutePartCount()
end

function DestructionManager.GetRevision()
	return revision
end

function DestructionManager.GetPathCosts()
	return PATH_COSTS
end

function DestructionManager.IsHoleBlocker(instance)
	return instance and instance:IsA("BasePart") and CollectionService:HasTag(instance, TAG_HOLE_BLOCKER) or false
end

function DestructionManager.GetNearestHoleBlocker(position, maxRange)
	local holeFolder = workspace:FindFirstChild("DestructionHoles")
	if not holeFolder then
		return nil
	end

	local bestBlocker = nil
	local bestDistance = maxRange or math.huge

	for _, blocker in ipairs(holeFolder:GetChildren()) do
		if blocker:IsA("BasePart") then
			local distance = (blocker.Position - position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				bestBlocker = blocker
			end
		end
	end

	return bestBlocker
end

function DestructionManager.HasTopologyChanges()
	if revision > 0 then
		return true
	end

	local holeFolder = workspace:FindFirstChild("DestructionHoles")
	if holeFolder and #holeFolder:GetChildren() > 0 then
		return true
	end

	if initialRoutePartCount > 0 and getLiveRoutePartCount() < initialRoutePartCount then
		return true
	end

	return false
end

function DestructionManager.GetGroundPosition(position, extraIgnore, heightOffset, options)
	DestructionManager.PrepareMap()

	local ground = raycastGround(position, extraIgnore, {
		IgnoreHoleBlockers = true,
		IgnoreRoutePartsNearHoles = options and options.IgnoreRoutePartsNearHoles,
	})
	if not ground then
		return nil, {
			Reason = "NoRayHit",
			ProbePosition = position,
		}
	end

	if ground.Instance == workspace.Terrain then
		if not terrainHasSolidAt(ground.Position) then
			return nil, {
				Reason = "TerrainAir",
				ProbePosition = position,
				HitPosition = ground.Position,
			}
		end
	else
		if not isValidMovementSupportPart(ground.Instance) then
			return nil, {
				Reason = "InvalidSupport",
				ProbePosition = position,
				HitPosition = ground.Position,
				HitInstance = ground.Instance,
				HitSummary = describePart(ground.Instance),
				IsPathModelRoute = isPathModelRoutePart(ground.Instance),
			}
		end
	end

	return Vector3.new(position.X, ground.Position.Y + (heightOffset or 0), position.Z), {
		Reason = "OK",
		ProbePosition = position,
		HitPosition = ground.Position,
		HitInstance = ground.Instance,
		HitSummary = ground.Instance == workspace.Terrain and "Terrain" or describePart(ground.Instance),
	}
end

function DestructionManager.ApplyExplosion(position, radius, damage, source)
	DestructionManager.PrepareMap()

	radius = radius or DEFAULT_EXPLOSION_RADIUS
	damage = damage or DEFAULT_EXPLOSION_DAMAGE
	destructionDebug("apply explosion", "source", source or "Unknown", "position", position, "radius", radius, "damage", damage)

	local changed = false
	local csgBudget = MAX_CSG_PER_EXPLOSION

	if not isNearCritical(position, radius + 3) then
		local success = pcall(function()
			workspace.Terrain:FillBall(position, radius, Enum.Material.Air)
		end)
		changed = changed or success
		destructionDebug("terrain carve", "success", success)
	end

	local overlappedParts = getExplosionOverlap(position, radius)
	local routeOverlapParts = getExplosionOverlap(position, getPathModelBreakRadius(radius))
	local routeParts = collectPathModelRouteParts(routeOverlapParts)
	local routePartSet = {}
	destructionDebug("overlap counts", "all", #overlappedParts, "routeArea", #routeOverlapParts, "routeParts", #routeParts)

	for _, routePart in ipairs(routeParts) do
		routePartSet[routePart] = true
		changed = removeRoutePart(routePart, position, radius) or changed
	end

	for _, part in ipairs(overlappedParts) do
		if not routePartSet[part] and not isPathModelRoutePart(part) then
			local partChanged
			partChanged, csgBudget = damageDestructiblePart(part, position, radius, damage, csgBudget)
			changed = changed or partChanged
		end
	end

	createDebris(position, nil, math.min(radius, 8))

	if changed then
		destructionDebug("explosion changed map", "newRevision", revision + 1)
		notifyChanged(position)
	else
		destructionDebug("explosion caused no structural change")
	end

	return changed
end

function DestructionManager.FindDestroyerTarget(origin, goal, maxRange)
	DestructionManager.PrepareMap()

	maxRange = maxRange or 90
	local bestTarget = nil
	local bestScore = math.huge
	local candidates = {}
	local routeVector = goal - origin
	local routeLengthSquared = math.max(routeVector:Dot(routeVector), 1)

	local function getDistanceFromRoute(position)
		local t = math.clamp((position - origin):Dot(routeVector) / routeLengthSquared, 0, 1)
		local closestPoint = origin + (routeVector * t)
		return (position - closestPoint).Magnitude
	end

	for _, part in ipairs(CollectionService:GetTagged(TAG_DESTRUCTIBLE_ROUTE)) do
		table.insert(candidates, part)
	end

	for _, part in ipairs(CollectionService:GetTagged(TAG_DESTRUCTIBLE_TOWER_SPOT)) do
		table.insert(candidates, part)
	end

	for _, part in ipairs(candidates) do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) and not part:GetAttribute("Destroyed") and not isProtected(part) then
			local distanceFromOrigin = (part.Position - origin).Magnitude
			if distanceFromOrigin <= maxRange then
				local largeSurfacePenalty = part:GetAttribute("DestructionLargeSurface") and 35 or 0
				local towerSpotBonus = CollectionService:HasTag(part, TAG_DESTRUCTIBLE_TOWER_SPOT) and -15 or 0
				local score = distanceFromOrigin
					+ (getDistanceFromRoute(part.Position) * 2)
					+ ((part.Position - goal).Magnitude * 0.08)
					+ largeSurfacePenalty
					+ towerSpotBonus
				if score < bestScore then
					bestScore = score
					bestTarget = part
				end
			end
		end
	end

	return bestTarget
end

function DestructionManager.CanPlaceTower(targetCFrame, towerModel, character)
	DestructionManager.PrepareMap()

	local ignoreList = {}
	if towerModel then
		table.insert(ignoreList, towerModel)
	end
	if character then
		table.insert(ignoreList, character)
	end
	if workspace:FindFirstChild("Towers") then
		table.insert(ignoreList, workspace.Towers)
	end

	local ground = raycastGround(targetCFrame.Position, ignoreList)
	if not ground then
		return false
	end

	if not isGroundCloseToFootprint(targetCFrame, towerModel, ground.Position) then
		return false
	end

	if ground.Instance == workspace.Terrain then
		return terrainHasSolidAt(ground.Position)
	end

	if ground.Instance ~= workspace:FindFirstChild("Baseplate")
		and CollectionService:HasTag(ground.Instance, TAG_DESTRUCTIBLE_ROUTE)
		and not CollectionService:HasTag(ground.Instance, TAG_DESTRUCTIBLE_TOWER_SPOT) then
		return false
	end

	return isValidSupportPart(ground.Instance)
end

function DestructionManager.IsTowerSupported(tower)
	if not tower or not tower.PrimaryPart or not tower:IsDescendantOf(workspace) then
		return false
	end

	local ground = raycastGround(tower.PrimaryPart.Position, { tower })
	if not ground then
		return false
	end

	if not isGroundCloseToFootprint(tower.PrimaryPart.CFrame, tower, ground.Position) then
		return false
	end

	if ground.Instance == workspace.Terrain then
		return terrainHasSolidAt(ground.Position)
	end

	return isValidSupportPart(ground.Instance)
end

return DestructionManager
