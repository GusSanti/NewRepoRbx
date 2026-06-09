-- SERVICES
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

-- CONSTANTS
local MAX_TOWERS_PER_PLAYER = 10
local collision_Group = "Worms"

local Storage = ReplicatedStorage:FindFirstChild("Storage")
local TowerModels = Storage:FindFirstChild("Towers")
local Towers = workspace:FindFirstChild("Towers")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local Enemies = workspace.Enemies
local ExplosionTemplate = Storage:FindFirstChild("Particles"):FindFirstChild("ExplosionTemplate")

local Path = workspace.Path
local Waypoints = Path.Waypoints

local Managers = ServerStorage:WaitForChild("Modules"):WaitForChild("Managers")
local DataManager = require(Managers:WaitForChild("DataManager"))
local DestructionManager = require(script.Parent:WaitForChild("DestructionManager"))
local SkillsManager = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Modules"):WaitForChild("Managers"):WaitForChild("SkillsManager"))

local EnemyData = require(ReplicatedStorage.Modules.StoredData.EnemyData)
local QuestData = require(ReplicatedStorage.Modules.StoredData.QuestsData)
local TowerData = require(ReplicatedStorage.Modules.StoredData.TowerData)
local TowerLevelData = require(ReplicatedStorage.Modules.StoredData.TowerLevelData)
local SkillsData = require(ReplicatedStorage.Modules.StoredData.SkillsData)

-- VARIABLES
local playerTowers = {}
local playerSkillCooldowns = {}

-- FUNCTIONS
local function getGameSpeed()
	return workspace:GetAttribute("GameSpeed") or 1
end

local function increaseStat(Player: Player, StatName: string, increment: number)
	for _, Value in ipairs(Player:GetDescendants()) do
		if Value.Name == StatName then
			Value.Value = Value.Value + increment
		end
	end
end

local function updateQuestProgress(player: Player, keyword: string, amount: number)
	if not player or not keyword then return end
	keyword = keyword:lower()
	for attributeName, value in pairs(player:GetAttributes()) do
		if attributeName:lower():find("quest_") and attributeName:lower():find(keyword) then
			local current = player:GetAttribute(attributeName)
			local newValue = current + amount
			player:SetAttribute(attributeName, newValue)
		end
	end
end

local function processSkillKill(Player, enemy, deathPos)
	local enemyName = enemy.Name
	local BaseCash = EnemyData[enemyName] and EnemyData[enemyName].Money or 0
	local EXPperKill = math.random(10, 20)
	local Multi = 1

	pcall(function()
		if MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 1529352425) then Multi *= 2 end
		if MarketplaceService:UserOwnsGamePassAsync(Player.UserId, 1529258503) then Multi *= 1.5 end
	end)

	local UserData = Player:FindFirstChild("UserData")
	if UserData then
		local EXP = UserData:FindFirstChild("EXP")
		if EXP then EXP.Value += EXPperKill * Multi end
	end

	local reward = math.round(BaseCash / #Players:GetPlayers())
	for _, Plr in ipairs(Players:GetPlayers()) do
		local currentCash = Plr:GetAttribute("TempCash") or 0
		Plr:SetAttribute("TempCash", currentCash + reward)
	end

	Remotes.Audio.ServerToClient:FireClient(Player, "EnemyDying")
	increaseStat(Player, "WormsKilled", 1)
	updateQuestProgress(Player, enemyName, 1)

	local currentKills = Player:GetAttribute("WormsKilled") or 0
	Player:SetAttribute("WormsKilled", currentKills + 1)

	local MoneyTemplate = ReplicatedStorage.Storage.Billboards.Money:Clone()
	if MoneyTemplate then
		MoneyTemplate.Worm_Money.Worm_income.Text = "+$" .. tostring(reward)
		MoneyTemplate.Parent = workspace

		local adorneePart
		if MoneyTemplate:IsA("BillboardGui") then
			MoneyTemplate.StudsOffset = Vector3.new(0, 3, 0)
			adorneePart = Instance.new("Part")
			adorneePart.Anchored = true
			adorneePart.CanCollide = false
			adorneePart.Transparency = 1
			adorneePart.Size = Vector3.new(1, 1, 1)
			adorneePart.Position = deathPos + Vector3.new(0, .25, 0)
			adorneePart.Parent = workspace
			MoneyTemplate.Adornee = adorneePart
		else
			MoneyTemplate:SetPrimaryPartCFrame(CFrame.new(deathPos + Vector3.new(0, 3, 0)))
		end

		task.spawn(function()
			task.wait(1 / getGameSpeed())
			if MoneyTemplate then MoneyTemplate:Destroy() end
			if adorneePart then adorneePart:Destroy() end
		end)
	end
end

local function findPartInModel(model, names)
	if type(names) == "string" then
		names = {names}
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			for _, name in ipairs(names) do
				if descendant.Name == name then
					return descendant
				end
			end
		end
	end
end

local function getTowerLevel(Tower)
	if not Tower or not Tower.Name then return 1 end
	local levelStr = Tower.Name:match("_(%d+)$")
	if levelStr then
		return tonumber(levelStr) or 1
	end
	return 1
end

local function getGameTier(towerName: string): number
	local tierStr = towerName:match("_(%d+)$")
	return tonumber(tierStr) or 1
end

local function getBaseTowerName(towerName: string): string
	return towerName:gsub("_%d+$", "")
end

local function getInventoryEntry(player: Player, baseName: string)
	local profile = DataManager.Stored[player.UserId]
	if not profile or not profile.Data then return nil end

	local inventory = profile.Data.Inventory
	if not inventory then return nil end

	for _, entry in pairs(inventory) do
		if entry.Name == baseName then
			return entry
		end
	end
	return nil
end

local function computeTowerStats(baseName: string, gameTier: number, inventoryEntry)
	local tierName = gameTier > 1 and (baseName .. "_" .. gameTier) or baseName
	local towerDataEntry = TowerData[tierName] or TowerData[baseName]
	if not towerDataEntry then return nil end

	local baseStats = towerDataEntry.BaseStats
	if not baseStats then return nil end

	local invLevel = inventoryEntry and inventoryEntry.Level or 1
	local invDamageBonus = inventoryEntry and inventoryEntry.Damage or 0
	local invRangeBonus = inventoryEntry and inventoryEntry.Range or 0
	local invCooldownBonus = inventoryEntry and inventoryEntry.AttackCooldown or 0

	return TowerLevelData.computeStats(
		baseStats.Damage,
		baseStats.Range,
		baseStats.AttackCooldown,
		invLevel,
		invDamageBonus,
		invRangeBonus,
		invCooldownBonus
	)
end

local function applyStatsToTower(tower: Model, stats)
	if not stats then return end
	tower:SetAttribute("Damage", stats.Damage)
	tower:SetAttribute("Range", stats.Range)
	tower:SetAttribute("AttackCooldown", stats.AttackCooldown)
end

local function getClosestEnemy(Tower: Model, Range: number)
	if not Tower.PrimaryPart then return nil end

	local closestEnemy = nil
	local shortestDistance = math.huge
	local maxRange = Range
	local towerLevel = getTowerLevel(Tower)
	local TargettingMode = Tower:GetAttribute("Priority") or 1
	local highestProgress = -math.huge
	local lowestProgress = math.huge

	for _, enemy in pairs(Enemies:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local distance = (enemy.PrimaryPart.Position - Tower.PrimaryPart.Position).Magnitude
			if distance <= maxRange then
				if TargettingMode == 3 then
					if distance < shortestDistance then
						shortestDistance = distance
						closestEnemy = enemy
					end
				elseif TargettingMode == 1 then
					local currentWaypoint = enemy:GetAttribute("Current") or 0
					local distanceToNext = enemy:GetAttribute("Distance") or math.huge
					local progress = currentWaypoint * 10000 - distanceToNext
					if progress > highestProgress then
						highestProgress = progress
						closestEnemy = enemy
						shortestDistance = distance
					end
				elseif TargettingMode == 2 then
					local currentWaypoint = enemy:GetAttribute("Current") or 0
					local distanceToNext = enemy:GetAttribute("Distance") or 0
					local progress = currentWaypoint * 10000 - distanceToNext
					if progress < lowestProgress then
						lowestProgress = progress
						closestEnemy = enemy
						shortestDistance = distance
					end
				end
			end
		end
	end
	return closestEnemy, shortestDistance
end

local function getClosestEnemyForAutoSkill(Tower, maxRange)
	local closestEnemy = nil
	local shortestDistance = maxRange or math.huge
	for _, enemy in pairs(Enemies:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local distance = (enemy.PrimaryPart.Position - Tower.PrimaryPart.Position).Magnitude
			if distance <= shortestDistance then
				shortestDistance = distance
				closestEnemy = enemy
			end
		end
	end
	return closestEnemy
end

local function processAutoSkills()
	local CurrentTime = os.clock()
	for Player, towers in pairs(playerTowers) do
		local checkedSkills = {}

		for _, Tower in ipairs(towers) do
			if not Tower.PrimaryPart then continue end

			local baseName = getBaseTowerName(Tower.Name)
			local TData = TowerData[baseName] or TowerData[Tower.Name]
			if not TData or not TData.SkillID then continue end

			local SkillData = SkillsData[TData.SkillID]
			if not SkillData then continue end

			if not playerSkillCooldowns[Player] then
				playerSkillCooldowns[Player] = {}
			end

			local LastUsed = playerSkillCooldowns[Player][baseName] or 0

			if CurrentTime - LastUsed >= SkillData.Cooldown then
				if not checkedSkills[baseName] then
					checkedSkills[baseName] = true

					local canActivate = false
					for _, matchingTower in ipairs(towers) do
						if getBaseTowerName(matchingTower.Name) == baseName and matchingTower.PrimaryPart then
							if SkillData.Name == "Grandma Aura" then 
								local cloneRef = matchingTower:FindFirstChild("ActiveClone")
								if cloneRef and cloneRef.Value and cloneRef.Value:IsDescendantOf(workspace) then
									canActivate = true
									break
								end
							else
								local range = matchingTower:GetAttribute("Range") or 0
								local enemy = getClosestEnemyForAutoSkill(matchingTower, range)
								if enemy then
									canActivate = true
									break
								end
							end
						end
					end

					if canActivate then
						playerSkillCooldowns[Player][baseName] = CurrentTime

						for _, matchingTower in ipairs(towers) do
							if getBaseTowerName(matchingTower.Name) == baseName and matchingTower.PrimaryPart then
								local targetPos = nil

								if SkillData.RequiresTarget then
									local range = matchingTower:GetAttribute("Range") or 0
									local enemy = getClosestEnemyForAutoSkill(matchingTower, range)
									if enemy and enemy.PrimaryPart then
										targetPos = enemy.PrimaryPart.Position
									else
										targetPos = matchingTower.PrimaryPart.Position
									end
								end

								SkillsManager.Execute(Player, matchingTower, SkillData, targetPos)
							end
						end
					end
				end
			end
		end
	end
end

local function playTowerLossVFX(position: CFrame)
	local particleTemplate = Storage.Particles:FindFirstChild("PlaceTemplate")
	if not particleTemplate then return end

	local particle = particleTemplate:Clone()
	particle.Parent = workspace
	particle.CFrame = position

	task.delay(0.35 / getGameSpeed(), function()
		for _, descendant in ipairs(particle:GetDescendants()) do
			if descendant:IsA("ParticleEmitter") then
				descendant.Enabled = false
			end
		end

		task.wait(1 / getGameSpeed())
		if particle and particle.Parent then
			particle:Destroy()
		end
	end)
end

local function removeUnsupportedTowers()
	for Player, towers in pairs(playerTowers) do
		for index = #towers, 1, -1 do
			local Tower = towers[index]
			if Tower and Tower.Parent and not DestructionManager.IsTowerSupported(Tower) then
				local towerCFrame = Tower.PrimaryPart and Tower.PrimaryPart.CFrame or CFrame.new()
				local baseName = getBaseTowerName(Tower.Name)
				local towerInfo = TowerData[Tower.Name] or TowerData[baseName]
				local refund = towerInfo and towerInfo.Price and math.floor(towerInfo.Price * 0.5) or 0

				if refund > 0 then
					Player:SetAttribute("TempCash", (Player:GetAttribute("TempCash") or 0) + refund)
				end

				table.remove(towers, index)
				playTowerLossVFX(towerCFrame)
				Tower:Destroy()
				Remotes.Game.SendNotification:FireClient(Player, "Tower lost: unstable ground. +$"..refund.." refunded.", "Error")
			end
		end
	end
end

local function createCrater(Position: Vector3, Radius: number, PartCount: number)
	local craterFolder = workspace:FindFirstChild("CraterParts")
	if not craterFolder then return end

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

		task.delay(3 / getGameSpeed(), function()
			local tweenInfo = TweenInfo.new(0.25 / getGameSpeed(), Enum.EasingStyle.Linear)
			local tween = TweenService:Create(craterPart, tweenInfo, {Transparency = 1})
			tween:Play()
			tween.Completed:Connect(function()
				craterPart:Destroy()
			end)
		end)
	end

	task.delay(0.1 / getGameSpeed(), function()
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

			local debrisForce = Instance.new("BodyVelocity")
			debrisForce.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			debrisForce.Velocity = Vector3.new(
				math.random(-25, 25),
				math.random(25, 55),
				math.random(-25, 25)
			) * getGameSpeed()
			debrisForce.P = 1000
			debrisForce.Parent = part

			game:GetService("Debris"):AddItem(debrisForce, 0.25 / getGameSpeed())

			task.delay(math.random(2, 3) / getGameSpeed(), function()
				local tweenInfo = TweenInfo.new(0.5 / getGameSpeed(), Enum.EasingStyle.Linear)
				local tween = TweenService:Create(part, tweenInfo, {Transparency = 1})
				tween:Play()
				tween.Completed:Connect(function()
					part:Destroy()
				end)
			end)
		end
	end)
end

local function enableTower(Player: Player, Tower: Model)
	local AnimationId = Tower:GetAttribute("AnimationId")
	if not AnimationId then return end

	local AttackAnim = "rbxassetid://" .. Tower:GetAttribute("AnimationId")
	local Damage = Tower:GetAttribute("Damage")
	if not Damage then return end

	local Range = Tower:GetAttribute("Range")
	if not Range then return end

	local TowerDataEntry = TowerData[Tower.Name]
	if not TowerDataEntry then return end

	local CustomAbility = TowerDataEntry.Ability
	if not CustomAbility then return end

	local AttackCooldown = Tower:GetAttribute("AttackCooldown")
	if not AttackCooldown then return end

	local PrimaryPart = Tower.PrimaryPart
	if not PrimaryPart then return end

	local Model = PrimaryPart:FindFirstChild(Tower.Name)
	if not Model then return end

	local Torso = Model:FindFirstChild("Torso")
	if not Torso then return end

	local Humanoid = Model:FindFirstChildOfClass("Humanoid")
	if not Humanoid then return end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		Animator = Instance.new("Animator")
		Animator.Parent = Humanoid
	end

	local PrimaryPartAgain = Tower.PrimaryPart
	if not PrimaryPartAgain then return end

	local FixedYAxis = PrimaryPartAgain.Position.Y

	local Animation = Instance.new("Animation")
	Animation.AnimationId = AttackAnim
	local AnimationTrack = Animator:LoadAnimation(Animation)

	local lastAbilitySoundTime = 0
	local lastGrenadeSoundTime = 0
	local magicianActive = false

	local function updateAnimationSpeed()
		AnimationTrack:AdjustSpeed(getGameSpeed())
	end
	workspace:GetAttributeChangedSignal("GameSpeed"):Connect(updateAnimationSpeed)

	if Tower.Name == "Airport" then
		AnimationTrack:AdjustSpeed(getGameSpeed())
		AnimationTrack.Looped = true
		AnimationTrack:Play()
	end

	task.spawn(function()
		task.wait(1 / getGameSpeed())
		while Tower.Parent == workspace:FindFirstChild("Towers") do
			Damage = Tower:GetAttribute("Damage")
			Range = Tower:GetAttribute("Range")
			AttackCooldown = Tower:GetAttribute("AttackCooldown")

			Torso.CanCollide = false
			local closestEnemy, distance = getClosestEnemy(Tower, Range)

			if closestEnemy and closestEnemy.PrimaryPart then
				local enemyHumanoid = closestEnemy:FindFirstChildOfClass("Humanoid")
				if not enemyHumanoid then
					task.wait(0.1 / getGameSpeed())
					continue
				end

				local towerPos = PrimaryPart.Position
				local enemyPos = closestEnemy.PrimaryPart.Position
				local flatTowerPos = Vector3.new(towerPos.X, FixedYAxis, towerPos.Z)
				local flatEnemyPos = Vector3.new(enemyPos.X, FixedYAxis, enemyPos.Z)
				local lookCFrame = CFrame.lookAt(flatTowerPos, flatEnemyPos)
				local pos = PrimaryPart.Position

				if not Tower.Name:find("Airport") then
					PrimaryPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, select(2, lookCFrame:ToEulerAnglesYXZ()), 0)
				end

				if AnimationTrack.IsPlaying then
					if Tower.Name ~= "Airport" then AnimationTrack:Stop() end
				end

				if Tower.Name ~= "Airport" then
					AnimationTrack:AdjustSpeed(getGameSpeed())
					AnimationTrack:Play()
				end

				if CustomAbility == "Deformation" then
					local names = {"Dynamite", "Grenade"}
					local partToHide = findPartInModel(Tower, names)

					if partToHide then
						task.spawn(function()
							partToHide.Transparency = 1
							task.wait((AttackCooldown - .5) / getGameSpeed())
							local tweenInfo = TweenInfo.new(0.25 / getGameSpeed(), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
							local tween = TweenService:Create(partToHide, tweenInfo, {Transparency = 0})
							tween:Play()
							tween.Completed:Wait()
						end)
					end

					local ExplosionPart = ExplosionTemplate:Clone()
					ExplosionPart.Position = enemyPos - Vector3.new(0, 2.5, 0)
					ExplosionPart.Parent = workspace

					if os.clock() - lastGrenadeSoundTime > 0.1 then
						Remotes.Audio.ServerToClient:FireAllClients("Grenader")
						lastGrenadeSoundTime = os.clock()
					end

					task.spawn(function()
						task.wait(0.05 / getGameSpeed())
						for _, Particle in ipairs(ExplosionPart:GetDescendants()) do
							if Particle:IsA("ParticleEmitter") then
								Particle:Emit(4)
							end
						end
					end)

					task.spawn(function()
						task.wait(3 / getGameSpeed())
						if ExplosionPart and ExplosionPart.Parent then ExplosionPart:Destroy() end
					end)
					createCrater(enemyPos - Vector3.new(0, 2.5, 0), 2, 12)
					DestructionManager.ApplyExplosion(enemyPos - Vector3.new(0, 2.5, 0), 5, 70, "Tower")

				elseif CustomAbility == "Slowness" then
					if os.clock() - lastAbilitySoundTime > 0.1 then
						Remotes.Audio.ServerToClient:FireClient(Player, Tower.Name)
						lastAbilitySoundTime = os.clock()
					end

					local ApplySlowness = Remotes.Game:FindFirstChild("ApplySlowness")
					if ApplySlowness then ApplySlowness:Fire(enemyHumanoid, .5, 3) end

				elseif CustomAbility == "Magician" then
					local Scepter = Model:FindFirstChild("Scepter")
					if Scepter then
						local Beam1Attachment = Scepter:FindFirstChild("Beam1")
						local BeamTargetAttachment = Scepter:FindFirstChild("BeamTarget")
						if Beam1Attachment and BeamTargetAttachment then
							if not magicianActive then
								magicianActive = true

								for _, Beam in ipairs(Beam1Attachment:GetChildren()) do
									if Beam:IsA("Beam") then Beam.Enabled = true end
								end

								task.spawn(function()
									while Tower.Parent == Towers do
										local newTarget, dist = getClosestEnemy(Tower, Range)
										if newTarget and newTarget.PrimaryPart and dist <= Range then
											BeamTargetAttachment.WorldPosition = newTarget.PrimaryPart.Position + Vector3.new(0, -0.5, 0)
										else
											for _, Beam in ipairs(Beam1Attachment:GetChildren()) do
												if Beam:IsA("Beam") then Beam.Enabled = false end
											end 
											break
										end
										task.wait(0.03 / getGameSpeed())
									end
									for _, Beam in ipairs(Beam1Attachment:GetChildren()) do
										if Beam:IsA("Beam") then Beam.Enabled = false end
									end
								end)

								task.wait(.03 / getGameSpeed())
								magicianActive = false
							end
						end
					end

				elseif CustomAbility == "Wizard" then
					if os.clock() - lastAbilitySoundTime > 0.1 then
						Remotes.Audio.ServerToClient:FireClient(Player, Tower.Name)
						lastAbilitySoundTime = os.clock()
					end

					local names = {"Dynamite", "Grenade"}
					local partToHide = findPartInModel(Tower, names)

					if partToHide then
						task.spawn(function()
							partToHide.Transparency = 1
							task.wait((AttackCooldown - .5) / getGameSpeed())
							local tweenInfo = TweenInfo.new(0.25 / getGameSpeed(), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
							local tween = TweenService:Create(partToHide, tweenInfo, {Transparency = 0})
							tween:Play()
							tween.Completed:Wait()
						end)
					end

				elseif CustomAbility == "None" then
					local baseName = Tower.Name:gsub("_%d+$", "")
					if os.clock() - lastAbilitySoundTime > 0.1 then
						Remotes.Audio.ServerToClient:FireClient(Player, baseName)
						lastAbilitySoundTime = os.clock()
					end
				end

				local FistR = Model:FindFirstChild("FistR")
				if FistR then
					for _, Child in ipairs(FistR:GetDescendants()) do
						if Child:IsA("ParticleEmitter") then Child:Emit(2) end
					end
				end

				local success, response = pcall(function()
					local oldHealth = enemyHumanoid.Health

					if Tower:GetAttribute("IceShotsActive") then
						if not enemyHumanoid:GetAttribute("Frozen") then
							enemyHumanoid:SetAttribute("Frozen", true)
							local origSpeed = enemyHumanoid.WalkSpeed
							enemyHumanoid.WalkSpeed = 0

							local vfxFolder = ReplicatedStorage.Storage:FindFirstChild("VfxSkills")
							if vfxFolder and vfxFolder:FindFirstChild("IceShot") then
								local vfx = vfxFolder.IceShot:Clone()
								vfx.Parent = closestEnemy.PrimaryPart
								vfx.Position = closestEnemy.PrimaryPart.Position
								task.delay(10, function() if vfx then vfx:Destroy() end end)
							end

							task.delay(10, function()
								if enemyHumanoid and enemyHumanoid.Parent then
									enemyHumanoid.WalkSpeed = origSpeed
									enemyHumanoid:SetAttribute("Frozen", nil)
								end
							end)
						end
					end

					local damageMultiplier = workspace:GetAttribute("CrateDamageMultiplier") or 1
					local finalDamage = math.max(0, math.floor(Damage * damageMultiplier))
					enemyHumanoid:TakeDamage(finalDamage)

					if enemyHumanoid.Health > 0 then
						Remotes.Game.VisualDamage:FireAllClients(enemyHumanoid.Parent, finalDamage)
					end

					if oldHealth > 0 and enemyHumanoid.Health <= 0 then
						processSkillKill(Player, enemyHumanoid.Parent, closestEnemy.PrimaryPart and closestEnemy.PrimaryPart.Position or Tower.PrimaryPart.Position)
					elseif enemyHumanoid.Health > 0 and CustomAbility == "Thrower" then
						local names = {"Dynamite", "Grenade", "Sheep"}
						local partToHide = findPartInModel(Tower, names)

						if partToHide then
							task.spawn(function()
								partToHide.Transparency = 1
								task.wait((AttackCooldown - .5) / getGameSpeed())
								local tweenInfo = TweenInfo.new(0.25 / getGameSpeed(), Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
								local tween = TweenService:Create(partToHide, tweenInfo, {Transparency = 0})
								tween:Play()
								tween.Completed:Wait()
							end)
						end
					end
				end)

				task.wait(AttackCooldown / getGameSpeed())
			else
				task.wait(0.1 / getGameSpeed())
			end
		end
	end)
end

local function dropAnimation(Tower: Model, TargetCFrame: CFrame)
	if not Tower.PrimaryPart then return end
	local startCFrame = TargetCFrame + Vector3.new(0, 3, 0)
	Tower:SetPrimaryPartCFrame(startCFrame)

	local tweenInfo = TweenInfo.new(0.25 / getGameSpeed(), Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local tween = TweenService:Create(Tower.PrimaryPart, tweenInfo, {CFrame = TargetCFrame})
	tween:Play()
end

local function moveGrandmaBackwards(unit: Model, TOwer)
	if not unit then return end

	local Health = ReplicatedStorage.Storage.Billboards.Health:Clone()
	if not Health then return end

	local hrp = unit:FindFirstChild("HumanoidRootPart")
	local humanoid = unit:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid then return end

	local animator = unit:FindFirstChild(unit.Name):FindFirstChild("Humanoid"):FindFirstChildOfClass("Animator")
	if animator then
		local walkAnim = Instance.new("Animation")
		walkAnim.AnimationId = "rbxassetid://75891183321464"
		local walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Looped = true
		walkTrack:Play()
	end

	local Bar = Health.Worm_Health.Bar
	local HPText = Health.Worm_Health.HP

	task.spawn(function()
		if TOwer.Name:find("_2") then
			humanoid.MaxHealth = 250
			humanoid.Health = 250
		elseif TOwer.Name:find("_3") then
			humanoid.MaxHealth = 500
			humanoid.Health = 500
		end

		Health.Worm_Health.Tower_Name.Text = "Grandma"
		Health.Worm_Health.HP.Text = humanoid.Health.."/"..humanoid.MaxHealth
		Health.Parent = hrp

		local function updateHealth()
			local ratio = humanoid.Health / humanoid.MaxHealth
			Bar.Size = UDim2.new(math.clamp(ratio, 0, 1), 0, 1, 0)
			HPText.Text = string.format("%d / %d", humanoid.Health, humanoid.MaxHealth)
		end

		updateHealth()
		humanoid:GetPropertyChangedSignal("Health"):Connect(updateHealth)
		humanoid.Died:Connect(function()
			unit:Destroy()
		end)
	end)

	local waypoints = {}
	for _, wp in ipairs(Waypoints:GetChildren()) do
		local n = tonumber(wp.Name)
		if n then table.insert(waypoints, {index = n, part = wp}) end
	end

	table.sort(waypoints, function(a, b) return a.index > b.index end)

	local function tweenToPosition(targetPos)
		if not unit or not hrp or not hrp.Parent then return false end
		local startPos = hrp.Position
		local distance = (targetPos - startPos).Magnitude
		local duration = distance / humanoid.WalkSpeed
		local direction = (targetPos - startPos).Unit
		local targetCFrame = CFrame.new(targetPos, targetPos + direction)
		local info = TweenInfo.new(duration, Enum.EasingStyle.Linear)
		local tween = TweenService:Create(hrp, info, {CFrame = targetCFrame})
		tween:Play()
		tween.Completed:Wait()
		return unit and unit.Parent ~= nil
	end

	task.spawn(function()
		for _, w in ipairs(waypoints) do
			if not tweenToPosition(w.part.Position) then return end
		end
		local target = Path:FindFirstChild("Enemy_Spawn")
		if target and unit and unit.Parent then
			tweenToPosition(target.Position)
			if unit and unit.Parent then unit:Destroy() end
		end
	end)
end

function createGrandma(ParentModel: Model)
	local GrandmaModel = ServerStorage.Units.Grandma:Clone()
	if not GrandmaModel then return end

	local Path = workspace.Path
	for _, descendant in ipairs(GrandmaModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CollisionGroup = collision_Group
		end
	end

	local targetCFrame = Path.Enemy_Target.CFrame
	local flippedCFrame = targetCFrame * CFrame.Angles(0, math.rad(180), 0)
	local spawnPosition = flippedCFrame.Position + Vector3.new(0, GrandmaModel.PrimaryPart.Size.Y / 2, 0)
	GrandmaModel.Parent = workspace

	GrandmaModel:SetAttribute("Damage", ParentModel:GetAttribute("Damage") or 100)

	local cloneRef = ParentModel:FindFirstChild("ActiveClone")
	if not cloneRef then
		cloneRef = Instance.new("ObjectValue")
		cloneRef.Name = "ActiveClone"
		cloneRef.Parent = ParentModel
	end
	cloneRef.Value = GrandmaModel

	task.spawn(function()
		ParentModel.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				if GrandmaModel and GrandmaModel.Parent then GrandmaModel:Destroy() end
			end
		end)
		GrandmaModel.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				if not ParentModel or ParentModel.Parent == nil then return end
				task.wait(0.1)
				createGrandma(ParentModel)
			end
		end)
	end)

	GrandmaModel:MoveTo(spawnPosition)
	task.wait(0.1)
	moveGrandmaBackwards(GrandmaModel, ParentModel)
end

local function spawnUnit(Player: Player, TowerName: string, CFrame, isUpgrade)
	if not playerTowers[Player] then
		playerTowers[Player] = {}
	end

	if not isUpgrade and #playerTowers[Player] >= MAX_TOWERS_PER_PLAYER then
		Remotes.Game.SendNotification:FireClient(Player, "Max tower limit ("..MAX_TOWERS_PER_PLAYER..") reached!", "Error")
		return
	end

	local TowerInfo = TowerModels:FindFirstChild(TowerName)
	if not TowerInfo then return end

	local Data = TowerData[TowerName]
	if not Data then return end

	local TowerPrice = Data.Price
	if not TowerPrice then return end

	local PlayerCash = Player:GetAttribute("TempCash")
	if not PlayerCash then return end

	local PlayerTagTemplate = ReplicatedStorage.Storage.Billboards.Player
	if not PlayerTagTemplate then return end

	if not isUpgrade then
		if typeof(CFrame) ~= "CFrame" or not DestructionManager.CanPlaceTower(CFrame, TowerInfo, Player.Character) then
			Remotes.Game.SendNotification:FireClient(Player, "You cannot place a tower on unstable ground.", "Error")
			return
		end
	end

	if not isUpgrade then
		if PlayerCash < TowerPrice then
			local NeededCash = TowerPrice - PlayerCash
			Remotes.Game.SendNotification:FireClient(Player, "You need $"..NeededCash, "Error")
			return
		end
		Player:SetAttribute("TempCash", PlayerCash - TowerPrice)
	end

	local Tower = TowerInfo:Clone()
	Tower:SetAttribute("Owner", Player.UserId)

	for _, BasePart in ipairs(Tower:GetDescendants()) do
		if BasePart:IsA("BasePart") then BasePart.CanCollide = false end
	end

	local baseName = getBaseTowerName(TowerName)
	local gameTier = getGameTier(TowerName)
	local inventoryEntry = getInventoryEntry(Player, baseName)
	local computedStats = computeTowerStats(baseName, gameTier, inventoryEntry)
	applyStatsToTower(Tower, computedStats)

	local PlayerTag = PlayerTagTemplate:Clone()
	local towerBaseName = Tower.Name:gsub("_%d+$", "")
	PlayerTag.Tower_Level.Player.Text = "@"..Player.Name.."'s "..towerBaseName
	PlayerTag.Parent = Tower
	Tower.Parent = Towers

	Remotes.Audio.ServerToClient:FireClient(Player, Tower.Name.."_Voice")

	dropAnimation(Tower, CFrame)
	enableTower(Player, Tower)

	if Tower.Name:match("Grandma") then
		local InnerModel = Tower.Tower:FindFirstChildOfClass("Model")
		InnerModel.Torso.Transparency = .5
		for _, BasePart in ipairs(InnerModel.Torso:GetChildren()) do
			if BasePart:IsA("BasePart") then BasePart.Transparency = .5 end
		end
		task.spawn(createGrandma, Tower)
	end

	if not isUpgrade then
		table.insert(playerTowers[Player], Tower)

		local new_particle = Storage.Particles.PlaceTemplate:Clone()
		new_particle.Parent = workspace
		new_particle.CFrame = Tower.PrimaryPart.CFrame
		task.delay(.5 / getGameSpeed(), function()
			for _, particle in ipairs(new_particle:GetDescendants()) do
				if particle:IsA("ParticleEmitter") then particle.Enabled = false end
			end
			task.wait(1 / getGameSpeed())
			new_particle:Destroy()
		end)
	end
	return Tower
end

-- INIT
task.defer(DestructionManager.PrepareMap)

local supportCheckQueued = false
DestructionManager.Changed:Connect(function()
	if supportCheckQueued then return end
	supportCheckQueued = true

	task.delay(0.25, function()
		supportCheckQueued = false
		removeUnsupportedTowers()
	end)
end)

Remotes:FindFirstChild("Building"):FindFirstChild("PlaceTower").OnServerEvent:Connect(function(Player: Player, TowerName: string, CFrame: CFrame)
	local createdTower = spawnUnit(Player, TowerName, CFrame)
	if not createdTower then return end

	local data = DataManager.Stored[Player.UserId]
	data.Data.Statistics.TowersPlaced += 1

	if not(Player:GetAttribute("TowersPlaced")) then
		Player:SetAttribute("TowersPlaced", 1)
	else
		Player:SetAttribute("TowersPlaced", Player:GetAttribute("TowersPlaced") + 1)
	end
end)

Remotes:FindFirstChild("Game"):FindFirstChild("SellTower").OnServerEvent:Connect(function(Player: Player, Tower: Model)
	if not Tower then return end

	local ownerId = Tower:GetAttribute("Owner")
	if ownerId ~= Player.UserId then
		Remotes.Game.SendNotification:FireClient(Player, "You do not own this tower!", "Error")
		return
	end

	local Cash = Player:GetAttribute("TempCash")
	if not Cash then return end

	local TowerName = Tower.Name
	if not TowerName then return end

	local TowerInfo = TowerData[TowerName]
	if not TowerInfo or not TowerInfo.Price then return end

	local SellValue = math.floor(TowerInfo.Price * 0.75)
	Player:SetAttribute("TempCash", Cash + SellValue)

	if playerTowers[Player] then
		for i, t in ipairs(playerTowers[Player]) do
			if t == Tower then
				table.remove(playerTowers[Player], i)
				break
			end
		end
	end
	Tower:Destroy()
end)

Remotes.Game.Upgrade.OnServerEvent:Connect(function(Player: Player, Tower: Model)
	if not Tower then return end

	local ownerId = Tower:GetAttribute("Owner")
	if ownerId ~= Player.UserId then
		Remotes.Game.ReEnableInfo:FireClient(Player, Tower)
		Remotes.Game.SendNotification:FireClient(Player, "You do not own this tower!", "Error")
		return
	end

	local PrimaryPart = Tower.PrimaryPart
	if not PrimaryPart then return end

	local PreUpgradePos = PrimaryPart.Position
	if not PreUpgradePos then return end

	local PreUpgradeName = Tower.Name
	if not PreUpgradeName then return end

	local CurrentUpgrade = 1
	if not Tower.Name:match("_") then
		CurrentUpgrade = 2
	elseif Tower.Name:match("1") then
		CurrentUpgrade = 2
	elseif Tower.Name:match("2") then
		CurrentUpgrade = 3
	elseif Tower.Name:match("3") then
		CurrentUpgrade = 4
	end

	local TargetName
	if not Tower.Name:match("_") then
		TargetName = PreUpgradeName.."_"..CurrentUpgrade
	else
		TargetName = PreUpgradeName:gsub("%d+$", "") .. CurrentUpgrade
	end

	if not TowerData then return end

	local PriceData = TowerData[TargetName].Price
	if not PriceData then return end

	local PlayerCash = Player:GetAttribute("TempCash")
	if not PlayerCash then return end

	if PlayerCash < PriceData then
		local NeededCash = PriceData - PlayerCash
		Remotes.Game.SendNotification:FireClient(Player, "You need $"..NeededCash, "Error")
		return
	end

	Player:SetAttribute("TempCash", PlayerCash - PriceData)
	increaseStat(Player, "TowersPlaced", 1)

	if playerTowers[Player] then
		for i, oldTower in ipairs(playerTowers[Player]) do
			if oldTower == Tower then
				local new_particle = Storage.Particles.UpgradeTemplate:Clone()
				new_particle.Parent = workspace
				new_particle.CFrame = Tower.PrimaryPart.CFrame
				local SaveCFrame = Tower.PrimaryPart.CFrame

				task.delay(.5 / getGameSpeed(), function()
					for _, particle in ipairs(new_particle:GetDescendants()) do
						if particle:IsA("ParticleEmitter") then particle.Enabled = false end
					end
					task.wait(1 / getGameSpeed())
					new_particle:Destroy()
				end)

				Tower:Destroy()
				Remotes.Audio.ServerToClient:FireClient(Player, "TowerUpgrade")
				task.wait(0.1 / getGameSpeed())

				local newTower = spawnUnit(Player, TargetName, SaveCFrame, true)
				if newTower then playerTowers[Player][i] = newTower end

				Remotes.Game.ReEnableInfo:FireClient(Player, newTower)
				updateQuestProgress(Player, "TowerUpgrades", 1)
				break
			end
		end
	end
end)

Remotes.Building.Target.OnServerEvent:Connect(function(Plr, Model, Target)
	if not(Model) then return end
	Model:SetAttribute("Priority", Target)
end)

Players.PlayerRemoving:Connect(function(player)
	playerTowers[player] = nil
	playerSkillCooldowns[player] = nil
end)

task.spawn(function()
	while task.wait(0.5) do
		processAutoSkills()
	end
end)

return {}
