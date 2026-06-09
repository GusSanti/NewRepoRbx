-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- CONSTANTS
local VfxFolder = ReplicatedStorage.Storage:FindFirstChild("VfxSkills")
local Enemies = workspace:FindFirstChild("Enemies")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local AudioRemote = Remotes and Remotes:FindFirstChild("Audio") and Remotes.Audio:FindFirstChild("ServerToClient")

-- VARIABLES
local SkillsManager = {}

-- FUNCTIONS
local function findPartInModel(model, name)
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == name then
			return desc
		end
	end
	
	return model.PrimaryPart
end

local function applyDamageAoE(position, range, damage)
	for _, enemy in pairs(Enemies:GetChildren()) do
		if enemy:IsA("Model") and enemy.PrimaryPart then
			local dist = (enemy.PrimaryPart.Position - position).Magnitude
			if dist <= range then
				local humanoid = enemy:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:TakeDamage(damage)
				end
			end
		end
	end
end

local function PlayVFX(vfxPrefab, target, duration, cframeOffset)
	if not vfxPrefab then return nil end
	local vfx = vfxPrefab:Clone()
	local hostPart = vfx

	if typeof(target) == "Vector3" then
		if not vfx:IsA("BasePart") then
			hostPart = Instance.new("Part")
			hostPart.Anchored = true
			hostPart.CanCollide = false
			hostPart.Transparency = 1
			hostPart.Size = Vector3.new(1,1,1)
			hostPart.CFrame = CFrame.new(target) * (cframeOffset or CFrame.identity)
			hostPart.Parent = workspace
			vfx.Parent = hostPart
		else
			vfx.Anchored = true
			vfx.CanCollide = false
			vfx.CFrame = CFrame.new(target) * (cframeOffset or CFrame.identity)
			vfx.Parent = workspace
		end
	else
		if not vfx:IsA("BasePart") then
			vfx.Parent = target
		else
			vfx.Parent = target
			vfx.Anchored = false
			vfx.CanCollide = false
			vfx.Massless = true

			vfx.CFrame = target.CFrame * (cframeOffset or CFrame.identity)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = target
			weld.Part1 = vfx
			weld.Parent = vfx
		end
	end

	for _, p in ipairs(hostPart:GetDescendants()) do
		if p:IsA("ParticleEmitter") then
			p.Enabled = true
			p:Emit(20)
		end
	end

	if hostPart:IsA("ParticleEmitter") then 
		hostPart.Enabled = true 
		hostPart:Emit(20)
	end

	if duration then
		task.delay(duration, function()
			if typeof(target) == "Vector3" and not vfx:IsA("BasePart") then
				hostPart:Destroy()
			else
				if vfx then vfx:Destroy() end
			end
		end)
	end

	return vfx
end

function SkillsManager.Execute(Player, Tower, SkillData, TargetPosition)
	local skillName = SkillData.Name
	local towerPos = Tower.PrimaryPart.Position

	if skillName == "Bunker Buster Air Raid" and not TargetPosition then
		return false
	end

	if AudioRemote then
		local baseName = Tower.Name:gsub("_%d+$", "")
		local cleanName = baseName:gsub("_", "")
		local soundName = cleanName .. "Skill"

		AudioRemote:FireAllClients(soundName)
	end

	if skillName == "Trigger Happy Barrage" then
		local originalCooldown = Tower:GetAttribute("AttackCooldown")
		Tower:SetAttribute("AttackCooldown", originalCooldown * 0.5)

		local weaponPart = findPartInModel(Tower, "Pistol") or Tower.PrimaryPart
		if weaponPart and VfxFolder:FindFirstChild(SkillData.VFX) then
			PlayVFX(VfxFolder[SkillData.VFX], weaponPart, SkillData.Duration, CFrame.new(0, 0, -2))
		end

		task.delay(SkillData.Duration, function()
			if Tower and Tower.Parent then
				Tower:SetAttribute("AttackCooldown", originalCooldown)
			end
		end)

	elseif skillName == "Surprise TNT Delivery" then
		for _, enemy in pairs(Enemies:GetChildren()) do
			if enemy:IsA("Model") and enemy.PrimaryPart then
				local dist = (enemy.PrimaryPart.Position - towerPos).Magnitude
				if dist <= SkillData.Range then
					if VfxFolder:FindFirstChild(SkillData.VFX) then
						PlayVFX(VfxFolder[SkillData.VFX], enemy.PrimaryPart.Position, 0.5, CFrame.new(0, 2, 0))
					end

					local humanoid = enemy:FindFirstChildOfClass("Humanoid")
					if humanoid then
						humanoid:TakeDamage(SkillData.Damage)
					end
				end
			end
		end

	elseif skillName == "Mad Lab Rage Serum" then
		if VfxFolder:FindFirstChild(SkillData.VFX) then
			local vfx = PlayVFX(VfxFolder[SkillData.VFX], towerPos, SkillData.Duration)
			if vfx then
				for _, particle in ipairs(vfx:GetDescendants()) do
					if particle:IsA("ParticleEmitter") then
						particle.Size = NumberSequence.new(SkillData.Range)
						particle.Color = ColorSequence.new(Color3.fromRGB(255, 0, 0))
					end
				end
			end
		end

		local TowersFolder = workspace:FindFirstChild("Towers")
		for _, ally in ipairs(TowersFolder:GetChildren()) do
			if ally.PrimaryPart and ally ~= Tower and (ally.PrimaryPart.Position - towerPos).Magnitude <= SkillData.Range then
				local origDmg = ally:GetAttribute("Damage")
				if origDmg then
					ally:SetAttribute("Damage", origDmg * SkillData.BuffMultiplier)

					task.delay(SkillData.Duration, function()
						if ally and ally.Parent then
							ally:SetAttribute("Damage", origDmg)
						end
					end)
				end
			end
		end

	elseif skillName == "One-Worm Showdown" then
		local oDmg = Tower:GetAttribute("Damage")
		local oRng = Tower:GetAttribute("Range")
		local oCd = Tower:GetAttribute("AttackCooldown")

		Tower:SetAttribute("Damage", oDmg * SkillData.BuffDamage)
		Tower:SetAttribute("Range", oRng * SkillData.BuffRange)
		Tower:SetAttribute("AttackCooldown", oCd * 0.25)

		local weaponPart = findPartInModel(Tower, "Weapon") or Tower.PrimaryPart
		if weaponPart and VfxFolder:FindFirstChild(SkillData.VFX) then
			PlayVFX(VfxFolder[SkillData.VFX], weaponPart, SkillData.Duration, CFrame.new(0, 0, -2))
		end

		task.delay(SkillData.Duration, function()
			if Tower and Tower.Parent then
				Tower:SetAttribute("Damage", oDmg)
				Tower:SetAttribute("Range", oRng)
				Tower:SetAttribute("AttackCooldown", oCd)
			end
		end)

	elseif skillName == "Storm of Wiggly Doom" then
		for _, enemy in pairs(Enemies:GetChildren()) do
			if enemy:IsA("Model") and enemy.PrimaryPart and (enemy.PrimaryPart.Position - towerPos).Magnitude <= SkillData.Range then
				if VfxFolder:FindFirstChild(SkillData.VFX) then
					PlayVFX(VfxFolder[SkillData.VFX], enemy.PrimaryPart.Position, 1, CFrame.new(0, 4, 0))
				end

				local humanoid = enemy:FindFirstChildOfClass("Humanoid")
				if humanoid then
					humanoid:TakeDamage(SkillData.Damage)
				end
			end
		end

	elseif skillName == "Holy Boom Barrage" then
		local expPos = TargetPosition or towerPos

		if VfxFolder:FindFirstChild(SkillData.VFX) then
			PlayVFX(VfxFolder[SkillData.VFX], expPos, 3, CFrame.identity)
		end

		applyDamageAoE(expPos, SkillData.Range, SkillData.Damage)

	elseif skillName == "Scorched Trench Order" then
		local zonePos = TargetPosition or towerPos

		local zone = Instance.new("Part")
		zone.Size = Vector3.new(SkillData.Range, 1, SkillData.Range)
		zone.Position = zonePos - Vector3.new(0, 2, 0)
		zone.Anchored = true
		zone.CanCollide = false
		zone.Transparency = 1
		zone.Parent = workspace

		if VfxFolder:FindFirstChild(SkillData.VFX) then
			PlayVFX(VfxFolder[SkillData.VFX], zone, SkillData.Duration)
		end

		task.spawn(function()
			local endTime = os.clock() + SkillData.Duration

			while os.clock() < endTime do
				applyDamageAoE(zone.Position, SkillData.Range, SkillData.Damage)
				task.wait(1)
			end

			zone:Destroy()
		end)

	elseif skillName == "Toxic Sludge Bubble" or skillName == "Shockworm Field" then
		local spawnedVFX = nil

		if VfxFolder:FindFirstChild(SkillData.VFX) then
			local cframeOffset = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(90), 0, 0)
			spawnedVFX = PlayVFX(VfxFolder[SkillData.VFX], Tower.PrimaryPart.Position, SkillData.Duration, cframeOffset)
		end

		task.spawn(function()
			local endTime = os.clock() + SkillData.Duration

			while os.clock() < endTime do
				if not Tower or not Tower.Parent then 
					if spawnedVFX then
						local hostPart = spawnedVFX.Parent
						spawnedVFX:Destroy()

						if hostPart and hostPart:IsA("BasePart") and hostPart.Name == "Part" and hostPart.Parent == workspace then
							hostPart:Destroy()
						end
					end
					break 
				end

				applyDamageAoE(Tower.PrimaryPart.Position, SkillData.Range, SkillData.Damage)
				task.wait(1)
			end
		end)

	elseif skillName == "Bunker Buster Air Raid" then
		if VfxFolder:FindFirstChild(SkillData.VFX) then
			PlayVFX(VfxFolder[SkillData.VFX], TargetPosition, 3, CFrame.new(0, 4, 0))
		end

		applyDamageAoE(TargetPosition, SkillData.Range, SkillData.Damage)

	elseif skillName == "Frozen Mud Salvo" then
		if VfxFolder:FindFirstChild(SkillData.VFX) then
			PlayVFX(VfxFolder[SkillData.VFX], Tower.PrimaryPart, 2)
		end

		for _, enemy in pairs(Enemies:GetChildren()) do
			if enemy:IsA("Model") and enemy.PrimaryPart then
				if (enemy.PrimaryPart.Position - towerPos).Magnitude <= (SkillData.Range or 25) then
					local humanoid = enemy:FindFirstChildOfClass("Humanoid")

					if humanoid and humanoid.Health > 0 and not humanoid:GetAttribute("Frozen") then
						humanoid:SetAttribute("Frozen", true)

						local origSpeed = humanoid.WalkSpeed
						humanoid.WalkSpeed = 0

						if VfxFolder:FindFirstChild(SkillData.VFX) then
							PlayVFX(VfxFolder[SkillData.VFX], enemy.PrimaryPart, SkillData.Duration)
						end

						task.delay(SkillData.Duration, function()
							if humanoid and humanoid.Parent then
								humanoid.WalkSpeed = origSpeed
								humanoid:SetAttribute("Frozen", nil)
							end
						end)
					end
				end
			end
		end

	elseif skillName == "Grandma's Battle Blessing" then
		local cloneRef = Tower:FindFirstChild("ActiveClone")
		local clone = cloneRef and cloneRef.Value

		if clone and clone:IsDescendantOf(workspace) then
			local humanoid = clone:FindFirstChildOfClass("Humanoid")
			local hrp = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart

			if humanoid and hrp then
				if VfxFolder:FindFirstChild(SkillData.VFX) then
					PlayVFX(VfxFolder[SkillData.VFX], hrp, SkillData.Duration, CFrame.new(0,0,0))
				end

				local origSpeed = humanoid.WalkSpeed
				local origDamage = clone:GetAttribute("Damage") or Tower:GetAttribute("Damage") or 100

				humanoid.WalkSpeed = origSpeed * 2
				clone:SetAttribute("Damage", origDamage * 2)

				task.delay(SkillData.Duration, function()
					if clone and clone:IsDescendantOf(workspace) and humanoid then
						humanoid.WalkSpeed = origSpeed
						clone:SetAttribute("Damage", origDamage)
					end
				end)
			end
		end
	end

	return true
end

-- INIT
return SkillsManager

