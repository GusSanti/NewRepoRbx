local Handler = {}

local Player = game.Players.LocalPlayer
local PlayerGui = Player.PlayerGui
local MainUi = PlayerGui:WaitForChild("InGame_UI")
local TowerSelectuI = MainUi:WaitForChild("Tower_Secondary_Info")
local UIS = game:GetService("UserInputService")

UIS.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		local s = workspace.CurrentCamera.ViewportSize
		local p = input.Position
		TowerSelectuI.Position = UDim2.new(p.X / s.X, 0, p.Y / s.Y, 0) + UDim2.new(0,0,.05,0)
	end
end)

function Handler.Init() end
Handler.Init()

return Handler