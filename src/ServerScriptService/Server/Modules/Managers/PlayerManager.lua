------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService: TeleportService = game:GetService("TeleportService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local LOBBY_PLACE_ID = 77035582123606
local STARTING_CASH = 300
local TUTORIAL_STARTING_CASH = 600

local MAP_ORDER = {
	"Frosty Peaks",
	"Jungle",
	"Wild West",
	"Toyland",
}

local DIFFICULTY_ORDER = {
	"Easy",
	"Medium",
	"Hard",
	"Impossible",
}

local DIFFICULTY_ALIASES = {
	Normal = "Easy",
	easy = "Easy",
	medium = "Medium",
	hard = "Hard",
	impossible = "Impossible",
}

local MAX_RETRIES = 5
local RETRY_WAIT = 0.1

------------------//VARIABLES
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local storedData = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StoredData")
local TowerData = require(storedData:WaitForChild("TowerData"))
local BossTowerUnlocks = require(storedData:WaitForChild("BossTowerUnlocks"))
local DataManager = require(ServerStorage.Modules.Managers.DataManager)

local clientLoading = remotes:FindFirstChild("ClientLoading")
local clientLoadedEvent = clientLoading:FindFirstChild("ClientLoaded")

local requestGameStartEvent = remotes:FindFirstChild("Game"):FindFirstChild("RequestGameStart")

local isCinematic = true
local playersLoaded = {}

------------------//FUNCTIONS
local function find_index(list: {string}, value: string): number
	for i = 1, #list do
		if list[i] == value then
			return i
		end
	end
	return 0
end

local function normalizeDifficulty(difficulty: any): string
	if typeof(difficulty) ~= "string" then
		return DIFFICULTY_ORDER[1]
	end

	return DIFFICULTY_ALIASES[difficulty]
		or DIFFICULTY_ALIASES[difficulty:lower()]
		or DIFFICULTY_ORDER[1]
end

local function normalizeMap(mapName: any): string
	if typeof(mapName) ~= "string" then
		return MAP_ORDER[1]
	end

	if find_index(MAP_ORDER, mapName) > 0 then
		return mapName
	end

	return MAP_ORDER[1]
end

local function normalizeRequestedMap(mapName: any): string
	if mapName == "Tutorial" then
		return "Tutorial"
	end

	return normalizeMap(mapName)
end

local function getUserData(player: Player): Folder
	local userData
	repeat
		userData = player:FindFirstChild("UserData")
		if not userData then
			task.wait(0.1)
		end
	until userData

	return userData :: Folder
end

local function ensureFolder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder :: Folder
end

local function ensureMapFolder(userData: Folder): Folder
	return ensureFolder(userData, "Map")
end

local function ensureStringValue(parent: Instance, name: string, defaultValue: string): StringValue
	local v = parent:FindFirstChild(name)
	if v and not v:IsA("StringValue") then
		v:Destroy()
		v = nil
	end

	if not v then
		v = Instance.new("StringValue")
		v.Name = name
		v.Value = defaultValue
		v.Parent = parent
	end
	return v :: StringValue
end

local function ensureBoolValue(parent: Instance, name: string, defaultValue: boolean): BoolValue
	local v = parent:FindFirstChild(name)
	if v and not v:IsA("BoolValue") then
		v:Destroy()
		v = nil
	end

	if not v then
		v = Instance.new("BoolValue")
		v.Name = name
		v.Value = defaultValue
		v.Parent = parent
	end
	return v :: BoolValue
end

local function getCurrentMapData(player: Player, teleportData: any?): (string, string)
	if teleportData then
		local mapName = teleportData.Map
		local difficulty = teleportData.Difficulty

		if mapName or difficulty then
			return normalizeMap(mapName), normalizeDifficulty(difficulty)
		end
	end

	local userData = getUserData(player)
	local mapFolder = userData:FindFirstChild("Map")

	if mapFolder then
		local lvl = mapFolder:FindFirstChild("Level")
		local diff = mapFolder:FindFirstChild("Difficulty")
		if lvl and lvl:IsA("StringValue") and diff and diff:IsA("StringValue") then
			return normalizeMap(lvl.Value), normalizeDifficulty(diff.Value)
		end
	end

	if teleportData and teleportData.UserData and teleportData.UserData.Map then
		return normalizeMap(teleportData.UserData.Map.Level), normalizeDifficulty(teleportData.UserData.Map.Difficulty)
	end

	return MAP_ORDER[1], DIFFICULTY_ORDER[1]
end

local function getStoredMapData(player: Player, teleportData: any?): (string, string)
	local userData = getUserData(player)
	local mapFolder = userData:FindFirstChild("Map")

	if mapFolder then
		local lvl = mapFolder:FindFirstChild("Level")
		local diff = mapFolder:FindFirstChild("Difficulty")
		if lvl and lvl:IsA("StringValue") and diff and diff:IsA("StringValue") then
			return normalizeMap(lvl.Value), normalizeDifficulty(diff.Value)
		end
	end

	if teleportData and teleportData.UserData and teleportData.UserData.Map then
		return normalizeMap(teleportData.UserData.Map.Level), normalizeDifficulty(teleportData.UserData.Map.Difficulty)
	end

	return MAP_ORDER[1], DIFFICULTY_ORDER[1]
end

local function setPlayerMapData(player: Player, mapName: string, difficulty: string): ()
	local userData = getUserData(player)
	local mapFolder = ensureMapFolder(userData)

	local lvl = ensureStringValue(mapFolder, "Level", MAP_ORDER[1])
	local diff = ensureStringValue(mapFolder, "Difficulty", DIFFICULTY_ORDER[1])

	lvl.Value = normalizeMap(mapName)
	diff.Value = normalizeDifficulty(difficulty)
end

local function ensureClearRecordsFolder(userData: Folder): Folder
	local records = ensureFolder(userData, "ClearRecords")

	for _, mapName in ipairs(MAP_ORDER) do
		local mapFolder = ensureFolder(records, mapName)
		for _, difficulty in ipairs(DIFFICULTY_ORDER) do
			ensureBoolValue(mapFolder, difficulty, false)
		end
	end

	return records
end

local function getClearRecordsData(player: Player): {}
	local userData = getUserData(player)
	local records = ensureClearRecordsFolder(userData)
	local output = {}

	for _, mapName in ipairs(MAP_ORDER) do
		output[mapName] = {}
		local mapFolder = records:FindFirstChild(mapName)
		for _, difficulty in ipairs(DIFFICULTY_ORDER) do
			local value = mapFolder and mapFolder:FindFirstChild(difficulty)
			output[mapName][difficulty] = value ~= nil
				and value:IsA("BoolValue")
				and value.Value == true
		end
	end

	return output
end

local function markClearRecord(player: Player, mapName: string, difficulty: string): ()
	mapName = normalizeMap(mapName)
	difficulty = normalizeDifficulty(difficulty)

	local userData = getUserData(player)
	local records = ensureClearRecordsFolder(userData)
	local mapFolder = ensureFolder(records, mapName)
	local clearValue = ensureBoolValue(mapFolder, difficulty, false)
	clearValue.Value = true

	local profile = DataManager.Stored[player.UserId]
	if typeof(profile) == "table" and profile:IsActive() then
		profile.Data.ClearRecords = profile.Data.ClearRecords or {}
		profile.Data.ClearRecords[mapName] = profile.Data.ClearRecords[mapName] or {}
		profile.Data.ClearRecords[mapName][difficulty] = true
	end
end

local function getBossInventoryKey(towerName: string): string
	return "BOSS_" .. towerName:gsub("[^%w_]", "_")
end

local function playerOwnsTower(player: Player, towerName: string): boolean
	local profile = DataManager.Stored[player.UserId]
	if typeof(profile) == "table" and profile:IsActive() and typeof(profile.Data.Inventory) == "table" then
		for _, entry in pairs(profile.Data.Inventory) do
			if typeof(entry) == "table" and entry.Name == towerName then
				return true
			end
		end
	end

	local userData = player:FindFirstChild("UserData")
	local inventory = userData and userData:FindFirstChild("Inventory")
	if inventory then
		for _, slot in ipairs(inventory:GetChildren()) do
			local nameValue = slot:FindFirstChild("Name")
			if nameValue and nameValue:IsA("StringValue") and nameValue.Value == towerName then
				return true
			end
		end
	end

	return false
end

local function syncInventoryEntry(player: Player, slotKey: string, entry: {}): ()
	local userData = getUserData(player)
	local inventory = ensureFolder(userData, "Inventory")
	local slotFolder = ensureFolder(inventory, slotKey)

	local fields = {
		{Name = "Name", Type = "StringValue", Value = entry.Name},
		{Name = "Level", Type = "NumberValue", Value = entry.Level},
		{Name = "EXP", Type = "NumberValue", Value = entry.EXP},
		{Name = "Damage", Type = "NumberValue", Value = entry.Damage},
		{Name = "Range", Type = "NumberValue", Value = entry.Range},
		{Name = "AttackCooldown", Type = "NumberValue", Value = entry.AttackCooldown},
	}

	for _, field in ipairs(fields) do
		local value = slotFolder:FindFirstChild(field.Name)
		if value and not value:IsA(field.Type) then
			value:Destroy()
			value = nil
		end

		if not value then
			value = Instance.new(field.Type)
			value.Name = field.Name
			value.Parent = slotFolder
		end

		value.Value = field.Value
	end
end

local function grantBossTower(player: Player, towerName: string): boolean
	if playerOwnsTower(player, towerName) then
		return false
	end

	local towerInfo = TowerData[towerName]
	if not towerInfo then
		warn("[BossTowerUnlocks] Missing TowerData for", towerName)
		return false
	end

	local entry = {
		Name = towerName,
		Level = 1,
		EXP = 0,
		Damage = 0,
		Range = 0,
		AttackCooldown = 0,
	}
	local slotKey = getBossInventoryKey(towerName)

	local profile = DataManager.Stored[player.UserId]
	if typeof(profile) == "table" and profile:IsActive() then
		profile.Data.Inventory = profile.Data.Inventory or {}
		profile.Data.Inventory[slotKey] = entry
	end

	syncInventoryEntry(player, slotKey, entry)
	return true
end

local function tryUnlockBossTower(player: Player, clearedMap: string, clearedDifficulty: string): {}?
	if normalizeDifficulty(clearedDifficulty) ~= BossTowerUnlocks.MaxDifficulty then
		return nil
	end

	local towerName = BossTowerUnlocks.ByMap[clearedMap]
	if type(towerName) ~= "string" then
		return nil
	end

	local newlyUnlocked = grantBossTower(player, towerName)
	if newlyUnlocked then
		remotes.Notification.SendNotification:FireClient(
			player,
			"Boss Tower unlocked: " .. towerName .. "!",
			"Success"
		)
	end

	return {
		Map = clearedMap,
		Difficulty = clearedDifficulty,
		Tower = towerName,
		NewlyUnlocked = newlyUnlocked,
	}
end

local function computeNextMapDifficulty(currentMap: string, currentDifficulty: string): (string, string, boolean)
	local mapIndex = find_index(MAP_ORDER, currentMap)
	if mapIndex == 0 then
		mapIndex = 1
	end

	local diffIndex = find_index(DIFFICULTY_ORDER, currentDifficulty)
	if diffIndex == 0 then
		diffIndex = 1
	end

	local nextMapIndex = mapIndex
	local nextDiffIndex = diffIndex

	if diffIndex < #DIFFICULTY_ORDER then
		nextDiffIndex += 1
	else
		if mapIndex < #MAP_ORDER then
			nextMapIndex += 1
			nextDiffIndex = 1
		end
	end

	local advanced = nextMapIndex ~= mapIndex or nextDiffIndex ~= diffIndex
	return MAP_ORDER[nextMapIndex], DIFFICULTY_ORDER[nextDiffIndex], advanced
end

local function applyWinProgression(player: Player, teleportData: any?): (string, string, string, string, boolean)
	local currentMap, currentDifficulty = getCurrentMapData(player, teleportData)
	local nextMap, nextDifficulty, advanced = computeNextMapDifficulty(currentMap, currentDifficulty)
	setPlayerMapData(player, nextMap, nextDifficulty)
	return nextMap, nextDifficulty, currentMap, currentDifficulty, advanced
end

local function setupTempCash(player: Player, mapName: string?): ()
	local startingCash = mapName == "Tutorial" and TUTORIAL_STARTING_CASH or STARTING_CASH
	player:SetAttribute("TempCash", startingCash)
end

local function PrintTableRecursive(tbl, indent)
	indent = indent or ""
	for key, value in pairs(tbl) do
		if typeof(value) == "table" then
			print(indent .. tostring(key) .. ": {")
			PrintTableRecursive(value, indent .. "  ")
			print(indent .. "}")
		else
			print(indent .. tostring(key) .. ": " .. tostring(value))
		end
	end
end

local function checkIfAllPlayersLoaded(difficulty, gamemode, mapName)
	local list = Players:GetPlayers()
	for i = 1, #list do
		local plr = list[i]
		if not playersLoaded[plr] then
			return false
		end
	end

	print("[🛡️] All clients loaded, starting game.")
	requestGameStartEvent:Fire(difficulty, gamemode, mapName)

	if isCinematic then
		remotes.Game.StartCinematic:FireAllClients()
	end

	return true
end

local function setupPlayer(player: Player)
	local spawnPosition = workspace:FindFirstChild("SpawnPos")
	if not spawnPosition then return end

	local character = player.Character
	if not character then return end

	local desc = character:GetDescendants()
	for i = 1, #desc do
		local inst = desc[i]
		if inst:IsA("BasePart") then
			inst.CollisionGroup = "Players"
		end
	end

	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	local requestedMap = teleportData and normalizeRequestedMap(teleportData.Map) or MAP_ORDER[1]
	ensureClearRecordsFolder(getUserData(player))

	if teleportData then
		teleportData.Difficulty = normalizeDifficulty(teleportData.Difficulty)

		PrintTableRecursive(teleportData)

		if teleportData.UserData and teleportData.UserData.Quests then
			for category, questData in pairs(teleportData.UserData.Quests) do
				if questData.Active then
					for questName, questInfo in pairs(questData.Active) do
						local progress = questInfo.Progress or 0
						local attributeName = string.format("Quest_%s_%s", category, questName)
						attributeName = attributeName:gsub("%s+", "_"):gsub("[^%w_]", "")
						player:SetAttribute(attributeName, progress)
					end
				end
			end
		end

		if teleportData.Gamemode ~= "PVP" then
			local mapName, mapDiff = getCurrentMapData(player, teleportData)
			setPlayerMapData(player, mapName, mapDiff)
		end
	end

	character:SetPrimaryPartCFrame(spawnPosition.CFrame)
	setupTempCash(player, requestedMap)

	if not teleportData then
		teleportData = {}
		teleportData.Difficulty = "Easy"
		teleportData.Gamemode = "endless"
		requestedMap = MAP_ORDER[1]
	end

	checkIfAllPlayersLoaded(teleportData.Difficulty, teleportData.Gamemode, requestedMap)
end

------------------//MAIN FUNCTIONS
local function gatherQuestAttributes(player: Player): {}
	local attrs = player:GetAttributes()
	if not attrs or next(attrs) == nil then
		return {}
	end

	local out = {}
	for name, value in pairs(attrs) do
		if string.sub(name, 1, 6) == "Quest_" then
			local category, rest = string.match(name, "^Quest_([^_]+)_(.+)$")
			if category and rest then
				category = category:gsub("^%s+", ""):gsub("%s+$", "")
				local questName = rest:gsub("^%s+", ""):gsub("%s+$", "")
				questName = questName:gsub("_", " ")
				out[category] = out[category] or {}
				out[category][questName] = value
			end
		end
	end

	return out
end

local function hasCompletedTutorial(player: Player): boolean
	local userData = player:FindFirstChild("UserData")
	if not userData then
		return false
	end

	local completedTutorial = userData:FindFirstChild("CompletedTutorial")
	return completedTutorial ~= nil
		and completedTutorial:IsA("BoolValue")
		and completedTutorial.Value == true
end

local function markCompletedTutorial(player: Player): ()
	local userData = getUserData(player)
	local completedTutorial = userData:FindFirstChild("CompletedTutorial")

	if completedTutorial and not completedTutorial:IsA("BoolValue") then
		completedTutorial:Destroy()
		completedTutorial = nil
	end

	if not completedTutorial then
		completedTutorial = Instance.new("BoolValue")
		completedTutorial.Name = "CompletedTutorial"
		completedTutorial.Parent = userData
	end

	(completedTutorial :: BoolValue).Value = true

	local onboarding = userData:FindFirstChild("Onboarding")
	if onboarding then
		local onboardingCompleted = onboarding:FindFirstChild("Completed")
		if onboardingCompleted and onboardingCompleted:IsA("BoolValue") then
			onboardingCompleted.Value = true
		end

		local stage = onboarding:FindFirstChild("Stage")
		if stage and stage:IsA("StringValue") then
			stage.Value = "completed"
		end
	end
end

------------------//INIT
remotes.Game.ReturnToLobby.OnServerEvent:Connect(function(player: Player, didWin: boolean?)
	local questData = {}
	for i = 1, MAX_RETRIES do
		questData = gatherQuestAttributes(player)
		if next(questData) ~= nil then
			break
		end
		if i < MAX_RETRIES then
			task.wait(RETRY_WAIT)
		end
	end

	local joinData = player:GetJoinData()
	local teleportDataIn = joinData.TeleportData

	local serverRecordedWin = player:GetAttribute("MatchWon") == true
	local wonMatch = didWin == true and serverRecordedWin
	local isPVP = teleportDataIn and teleportDataIn.Gamemode == "PVP"
	local canAdvanceProgression = wonMatch and not isPVP
	local mapLevel, mapDifficulty

	if isPVP then
		mapLevel, mapDifficulty = getStoredMapData(player, teleportDataIn)
	else
		mapLevel, mapDifficulty = getCurrentMapData(player, teleportDataIn)
	end

	local clearedMap, clearedDifficulty = mapLevel, mapDifficulty
	local advanced = false
	local completedTutorial = hasCompletedTutorial(player)
	local bossTowerUnlock = nil

	if canAdvanceProgression then
		if teleportDataIn and teleportDataIn.Map == "Tutorial" then
			clearedMap = "Tutorial"
			clearedDifficulty = normalizeDifficulty(teleportDataIn.Difficulty)
			mapLevel = MAP_ORDER[1]
			mapDifficulty = DIFFICULTY_ORDER[1]
			advanced = true
			setPlayerMapData(player, mapLevel, mapDifficulty)
			markCompletedTutorial(player)
			completedTutorial = true
		else
			mapLevel, mapDifficulty, clearedMap, clearedDifficulty, advanced = applyWinProgression(player, teleportDataIn)
		end
	else
		if not isPVP then
			setPlayerMapData(player, mapLevel, mapDifficulty)
		end
	end

	if canAdvanceProgression and clearedMap ~= "Tutorial" then
		markClearRecord(player, clearedMap, clearedDifficulty)
		bossTowerUnlock = tryUnlockBossTower(player, clearedMap, clearedDifficulty)
	end

	local clearRecords = getClearRecordsData(player)

	local teleportData = {
		Result = wonMatch and "Won" or "Lost",
		CompletedTutorial = completedTutorial,
		TutorialCompleted = completedTutorial,
		ClearRecords = clearRecords,
		BossTowerUnlock = bossTowerUnlock,
		Onboarding = {
			Completed = completedTutorial,
			Stage = completedTutorial and "completed" or "tutorial",
		},
		Progression = {
			Won = wonMatch,
			CanAdvance = canAdvanceProgression,
			Advanced = advanced,
			ClearedMap = clearedMap,
			ClearedDifficulty = clearedDifficulty,
			NextMap = mapLevel,
			NextDifficulty = mapDifficulty,
			TutorialCompleted = completedTutorial,
			BossTowerUnlock = bossTowerUnlock,
		},
		UserData = {
			CompletedTutorial = completedTutorial,
			TutorialCompleted = completedTutorial,
			ClearRecords = clearRecords,
			BossTowerUnlock = bossTowerUnlock,
			Onboarding = {
				Completed = completedTutorial,
				Stage = completedTutorial and "completed" or "tutorial",
			},
			Quests = questData,
			Map = {
				Level = mapLevel,
				Difficulty = mapDifficulty,
			},
		},
	}

	TeleportService:Teleport(LOBBY_PLACE_ID, player, teleportData)
end)

clientLoadedEvent.OnServerEvent:Connect(function(player: Player)
	playersLoaded[player] = true
	setupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	playersLoaded[player] = nil
end)

return {}
