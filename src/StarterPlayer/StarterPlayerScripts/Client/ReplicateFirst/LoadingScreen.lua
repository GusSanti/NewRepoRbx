-- // services

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

-- // helpers

local function createNoopApi()
	return {
		Show = function() end,
		Hide = function() end,
		SetStatus = function() end,
		SetProgress = function() end,
		PreloadAssets = function()
			return 0, 0
		end,
		Finish = function() end,
	}
end

local function isTextObject(instance: Instance?): boolean
	return instance ~= nil
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function addAssetId(bucket, seen, value)
	if typeof(value) ~= "string" or value == "" or seen[value] then
		return
	end

	seen[value] = true
	table.insert(bucket, value)
end

local function collectAssets(root: Instance): {string}
	local assets = {}
	local seen = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			addAssetId(assets, seen, descendant.Image)
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			addAssetId(assets, seen, descendant.Texture)
		elseif descendant:IsA("Sound") then
			addAssetId(assets, seen, descendant.SoundId)
		elseif descendant:IsA("MeshPart") then
			addAssetId(assets, seen, descendant.TextureID)
		elseif descendant:IsA("SpecialMesh") then
			addAssetId(assets, seen, descendant.TextureId)
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			addAssetId(assets, seen, descendant.Texture)
		elseif descendant:IsA("Animation") then
			addAssetId(assets, seen, descendant.AnimationId)
		end
	end

	return assets
end

local function formatStatusText(baseText: string?, progressValue: number?, showPercent: boolean?): string
	local base = baseText or "LOADING GAME..."

	if showPercent == false or progressValue == nil then
		return base
	end

	local percentage = math.floor(math.clamp(progressValue, 0, 1) * 100 + 0.5)
	return string.format("%s %d%%", base, percentage)
end

-- // variables

local Player = Players.LocalPlayer
local PlayerGui = Player and Player:WaitForChild("PlayerGui", 5)
if not PlayerGui then
	return createNoopApi()
end

local LoadingGui = PlayerGui:WaitForChild("Loading", 5)
if not LoadingGui then
	warn("Loading GUI not found.")
	return createNoopApi()
end

local MainGui = PlayerGui:FindFirstChild("InGame_UI")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")

local public = {}

local DEFAULT_LOADING_TEXT = "LOADING GAME..."
local WORM_BOB_AMOUNT = 6
local WORM_BOB_SPEED = 8
local WORM_ROTATION_AMOUNT = 5
local PROGRESS_LERP_SPEED = 10

local uiCache = nil
local uiReady = false
local progressMode = "indeterminate"
local targetProgress = 0
local displayedProgress = 0
local statusText = DEFAULT_LOADING_TEXT
local animationConnection = nil

local walkingBarFullSize = nil
local wormBasePosition = nil
local wormBaseRotation = 0
local wormBaseCenterOffset = 0
local wormAttachedToWalkingBar = false

local function resolveUi()
	if uiCache then
		return uiCache
	end

	local holder = LoadingGui:FindFirstChild("Holder")
	local newHolder = LoadingGui:FindFirstChild("NewHolder") or holder
	local loadingBarBG = (newHolder and newHolder:FindFirstChild("LoadingBarBG", true))
		or LoadingGui:FindFirstChild("LoadingBarBG", true)
	local walkingBar = loadingBarBG and loadingBarBG:FindFirstChild("WalkingBar", true)
	local worm = (newHolder and newHolder:FindFirstChild("Worm", true))
		or LoadingGui:FindFirstChild("Worm", true)
	local textObjects = {}

	for _, descendant in ipairs(LoadingGui:GetDescendants()) do
		if isTextObject(descendant) and (descendant.Name == "LoadingTX" or descendant.Name == "LoadingLabel") then
			table.insert(textObjects, descendant)
		end
	end

	uiCache = {
		Holder = holder,
		NewHolder = newHolder,
		LoadingBarBG = loadingBarBG,
		WalkingBar = walkingBar,
		Worm = worm,
		Texts = textObjects,
	}

	return uiCache
end

local function setLoadingText(text: string?)
	statusText = text or DEFAULT_LOADING_TEXT

	for _, textObject in ipairs(resolveUi().Texts) do
		textObject.Text = statusText
	end
end

local function captureUiMetrics()
	local ui = resolveUi()
	local walkingBar = ui.WalkingBar
	local worm = ui.Worm
	local loadingBarBG = ui.LoadingBarBG

	if walkingBar then
		walkingBarFullSize = walkingBar.Size
	end

	if worm then
		wormBasePosition = worm.Position
		wormBaseRotation = worm.Rotation
	end

	wormAttachedToWalkingBar = worm ~= nil and worm.Parent == walkingBar

	if loadingBarBG and worm and not wormAttachedToWalkingBar then
		local anchorPoint = worm.AnchorPoint
		local wormCenterX = worm.AbsolutePosition.X + worm.AbsoluteSize.X * anchorPoint.X
		wormBaseCenterOffset = wormCenterX - loadingBarBG.AbsolutePosition.X
	end

	uiReady = true
end

local function applyProgress(progressValue: number, bobOffset: number?, rotationOffset: number?)
	local ui = resolveUi()
	local walkingBar = ui.WalkingBar
	local worm = ui.Worm
	local loadingBarBG = ui.LoadingBarBG

	if walkingBar and walkingBarFullSize then
		walkingBar.Size = UDim2.new(
			walkingBarFullSize.X.Scale * progressValue,
			math.floor(walkingBarFullSize.X.Offset * progressValue + 0.5),
			walkingBarFullSize.Y.Scale,
			walkingBarFullSize.Y.Offset
		)
	end

	if worm and wormBasePosition and wormAttachedToWalkingBar then
		worm.Position = UDim2.new(
			1,
			wormBasePosition.X.Offset,
			wormBasePosition.Y.Scale,
			wormBasePosition.Y.Offset + math.floor((bobOffset or 0) + 0.5)
		)
		worm.Rotation = wormBaseRotation + (rotationOffset or 0)
	elseif worm and wormBasePosition and loadingBarBG then
		local parent = worm.Parent
		if parent then
			local anchorPoint = worm.AnchorPoint
			local targetCenterX = loadingBarBG.AbsolutePosition.X + loadingBarBG.AbsoluteSize.X * progressValue + wormBaseCenterOffset
			local targetLeftX = targetCenterX - worm.AbsoluteSize.X * anchorPoint.X
			local localLeftX = targetLeftX - parent.AbsolutePosition.X

			worm.Position = UDim2.new(
				0,
				math.floor(localLeftX + 0.5),
				wormBasePosition.Y.Scale,
				wormBasePosition.Y.Offset + math.floor((bobOffset or 0) + 0.5)
			)
			worm.Rotation = wormBaseRotation + (rotationOffset or 0)
		end
	end
end

local function stopAnimation()
	if animationConnection then
		animationConnection:Disconnect()
		animationConnection = nil
	end
end

local function startAnimation()
	if animationConnection then
		return
	end

	animationConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if not LoadingGui.Enabled then
			stopAnimation()
			return
		end

		if not uiReady then
			return
		end

		local desiredProgress = targetProgress
		if progressMode == "indeterminate" then
			desiredProgress = 0.08 + (((math.sin(os.clock() * 1.8) + 1) * 0.5) * 0.18)
		end

		displayedProgress += (desiredProgress - displayedProgress) * math.min(deltaTime * PROGRESS_LERP_SPEED, 1)

		local waveTime = os.clock() * WORM_BOB_SPEED
		local bobOffset = math.sin(waveTime + displayedProgress * math.pi * 4) * WORM_BOB_AMOUNT
		local rotationOffset = math.sin(waveTime * 0.75 + displayedProgress * math.pi * 2) * WORM_ROTATION_AMOUNT

		applyProgress(displayedProgress, bobOffset, rotationOffset)
	end)
end

local function preloadLoadingUi()
	local assets = collectAssets(LoadingGui)
	if #assets == 0 then
		return
	end

	local success, err = pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)

	if not success then
		warn("Loading UI preload failed:", err)
	end
end

local function disableLoadingScreen()
	progressMode = "indeterminate"
	targetProgress = 0
	displayedProgress = 0
	uiReady = false

	stopAnimation()

	if MainGui then
		MainGui.Enabled = true
	end
	LoadingGui.Enabled = false
end

local function enableLoadingScreen(initialText: string?)
	uiCache = nil
	local ui = resolveUi()

	if MainGui then
		MainGui.Enabled = false
	end
	LoadingGui.Enabled = true

	if ui.Holder and ui.Holder ~= ui.NewHolder and ui.Holder:IsA("GuiObject") then
		ui.Holder.Visible = false
	end

	if ui.NewHolder and ui.NewHolder:IsA("GuiObject") then
		ui.NewHolder.Visible = true
	end

	progressMode = "indeterminate"
	targetProgress = 0
	displayedProgress = 0
	uiReady = false

	setLoadingText(initialText or DEFAULT_LOADING_TEXT)

	RunService.Heartbeat:Wait()
	captureUiMetrics()
	applyProgress(0, 0, 0)
	startAnimation()
end

local function init()
	preloadLoadingUi()
	enableLoadingScreen(DEFAULT_LOADING_TEXT)
end

-- // public api

function public.Show(initialText: string?)
	enableLoadingScreen(initialText or DEFAULT_LOADING_TEXT)
end

function public.Hide()
	disableLoadingScreen()
end

function public.SetStatus(text: string?)
	setLoadingText(text or DEFAULT_LOADING_TEXT)
end

function public.SetProgress(progressValue: number, text: string?, showPercent: boolean?)
	if not LoadingGui.Enabled then
		enableLoadingScreen(text or DEFAULT_LOADING_TEXT)
	end

	progressMode = "determinate"
	targetProgress = math.clamp(progressValue or 0, 0, 1)
	setLoadingText(formatStatusText(text, targetProgress, showPercent))
end

function public.PreloadAssets(assets: {any}, options)
	options = options or {}

	local total = #assets
	local startProgress = math.clamp(options.startProgress or 0, 0, 1)
	local endProgress = math.clamp(options.endProgress or 1, startProgress, 1)
	local label = options.label or DEFAULT_LOADING_TEXT
	local showPercent = options.showPercent ~= false

	if total == 0 then
		public.SetProgress(endProgress, label, showPercent)
		return 0, 0
	end

	local loaded = 0

	local function updateProgress()
		local alpha = loaded / total
		local mappedProgress = startProgress + ((endProgress - startProgress) * alpha)
		public.SetProgress(mappedProgress, label, showPercent)
	end

	updateProgress()

	local success, err = pcall(function()
		ContentProvider:PreloadAsync(assets, function()
			loaded += 1
			updateProgress()
		end)
	end)

	if not success then
		warn("Asset preload callback failed, falling back to sequential preload:", err)

		for _, asset in ipairs(assets) do
			pcall(function()
				ContentProvider:PreloadAsync({asset})
			end)

			loaded += 1
			updateProgress()
		end
	end

	if loaded < total then
		loaded = total
		updateProgress()
	end

	return loaded, total
end

function public.Finish(text: string?)
	public.SetProgress(1, text or DEFAULT_LOADING_TEXT, false)

	local startedAt = os.clock()
	while LoadingGui.Enabled and os.clock() - startedAt < 0.35 do
		if math.abs(displayedProgress - 1) <= 0.01 then
			break
		end

		RunService.Heartbeat:Wait()
	end
end

-- // code

if Player then
	init()
end

local gameRemotes = Remotes and Remotes:FindFirstChild("Game")
local hideLoadingRemote = gameRemotes and gameRemotes:FindFirstChild("HideLoadingScreen")
local showLoadingRemote = gameRemotes and gameRemotes:FindFirstChild("ShowLoadingScreen")

if hideLoadingRemote and hideLoadingRemote:IsA("RemoteEvent") then
	hideLoadingRemote.OnClientEvent:Connect(disableLoadingScreen)
end

if showLoadingRemote and showLoadingRemote:IsA("RemoteEvent") then
	showLoadingRemote.OnClientEvent:Connect(function()
		public.Show(DEFAULT_LOADING_TEXT)
	end)
end

TeleportService:SetTeleportGui(LoadingGui)

return public
