-- // services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- // modules

local ProfileService = require(ReplicatedStorage.Modules.Packages.ProfileService)
local DataTemplate = require(ServerStorage.Modules.Storage.DataTemplate)

-- // variables

local DataManager = {
	["Stored"] = {}
}

local Key = "GameData_0.03" --(RunService:IsStudio() and "StudioData_0.01") or "GameData_0.03"
local ProfileStore = ProfileService.GetProfileStore(Key, DataTemplate)

local TypeConversions = {
	["string"] = "StringValue",
	["boolean"] = "BoolValue",
	["number"] = "NumberValue"
}

-- // aux

--[[if RunService:IsStudio() then
	ProfileStore = ProfileStore.Mock
	warn("[SERVER] IN STUDIO DATA WILL **NOT SAVE**")
end--]]
-- // functions

local function CompileDataObjects(Player, Data, ParentFolder)
	local Folder = ParentFolder

	if not Folder then
		Folder = Instance.new("Folder")
		Folder.Name = "UserData"
		Folder.Parent = Player
	end

	for Index, Value in pairs(Data) do
		local ValueType = typeof(Value)

		if ValueType == "table" then
			local NewFolder = Instance.new("Folder")
			NewFolder.Name = Index
			NewFolder.Parent = Folder
			CompileDataObjects(Player, Value, NewFolder)
		else
			local ObjectType = TypeConversions[ValueType]
			if ObjectType then
				local Object = Instance.new(ObjectType)
				Object.Name = Index
				Object.Value = Value
				Object.Parent = Folder
			else
				warn("Unsupported value type for:", Index, ValueType)
			end
		end
	end

	if Folder.Name == "UserData" and Folder.Parent == Player then
		Player:SetAttribute("DataLoaded", true)
	end
end

local function SyncValuesToProfile(Player, Folder, Data)
	for _, obj in ipairs(Folder:GetChildren()) do
		if obj:IsA("Folder") then
			if typeof(Data[obj.Name]) ~= "table" then
				Data[obj.Name] = {}
			end
			SyncValuesToProfile(Player, obj, Data[obj.Name])
		elseif obj:IsA("ValueBase") then
			Data[obj.Name] = obj.Value
		end
	end
end

local function PlayerRemoved(Player)
	local Profile = DataManager.Stored[Player.UserId]

	if typeof(Profile) == "table" and Profile:IsActive() then
		local userFolder = Player:FindFirstChild("UserData")
		if userFolder then
			SyncValuesToProfile(Player, userFolder, Profile.Data)
		end

		local success, err = pcall(function()
			print("Saving and releasing profile for", Player.Name)
			Profile:Release()
		end)

		if not success then
			warn("Failed to release profile for", Player.Name, ":", err)
		end
	end

	DataManager.Stored[Player.UserId] = nil
end

local function PlayerAdded(Player)
	if DataManager.Stored[Player.UserId] then return end
	DataManager.Stored[Player.UserId] = true -- temporary lock

	local success, Profile = pcall(function()
		return ProfileStore:LoadProfileAsync("Player_" .. Player.UserId)
	end)

	if success and Profile then
		Profile:AddUserId(Player.UserId)
		Profile:Reconcile()

		Profile:ListenToRelease(function()
			PlayerRemoved(Player)
			if Player:IsDescendantOf(Players) then
				Player:Kick("Your data session was closed.")
			end
		end)

		DataManager.Stored[Player.UserId] = Profile
		CompileDataObjects(Player, Profile.Data)

		print("[DATA] Loaded profile for", Player.Name)
	else
		warn("[DATA] Failed to load profile for", Player.Name, ":", Profile)
		Player:Kick("Failed to load your data. Try again.")
	end
end

-- // connections

for _, Player in ipairs(Players:GetPlayers()) do
	task.spawn(PlayerAdded, Player)
end

Players.PlayerAdded:Connect(PlayerAdded)
Players.PlayerRemoving:Connect(PlayerRemoved)

-- // return

return DataManager
