-- // services

local SoundService = game:GetService("SoundService")

-- // settings

local MapMusic = "Toy"

-- // function

local function findAndPlay()
	
	local UserData = game.Players.LocalPlayer:WaitForChild("UserData")
	local Settings = UserData:WaitForChild("Settings", 60)
	local MusicEnabled = Settings:WaitForChild("MusicEnabled")

	task.wait(.5)

	if MusicEnabled.Value then
		
		local TargetSound = MapMusic
	
		for _, Sound in ipairs(SoundService:GetDescendants()) do
			if Sound:IsA("Sound") and Sound.Name == TargetSound then
				Sound:Play()
				Sound.Looped = true
				Sound.Volume = .5
			end
		end
	else
		print("nah")
	end
	
end

-- // conn

if game.Players.LocalPlayer then
	findAndPlay()
end

return {}