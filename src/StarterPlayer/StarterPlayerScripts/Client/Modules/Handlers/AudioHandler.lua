-- // services

local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- // functions

local LastSoundTimes = {}

local function PlaySound(SoundName : string)
	for _, AudioFile in ipairs(SoundService:GetDescendants()) do
		if AudioFile:IsA("Sound") and AudioFile.Name == SoundName then

			if LastSoundTimes[SoundName] and os.clock() - LastSoundTimes[SoundName] < 0.08 then
				return
			end

			LastSoundTimes[SoundName] = os.clock()

			local Existing = SoundService:FindFirstChild("Playing_" .. SoundName)
			if Existing and Existing.IsPlaying then
				Existing:Stop()
				Existing:Destroy()
			end

			local ClonedSound = AudioFile:Clone()
			ClonedSound.Name = "Playing_" .. SoundName
			ClonedSound.Parent = SoundService

			ClonedSound:Play()
			ClonedSound.Ended:Connect(function()
				ClonedSound:Destroy()
			end)
		end
	end
end

-- // conn

ReplicatedStorage.Remotes.Audio.ServerToClient.OnClientEvent:Connect(PlaySound)
ReplicatedStorage.Remotes.Audio.ClientToClient.Event:Connect(PlaySound)

return {}