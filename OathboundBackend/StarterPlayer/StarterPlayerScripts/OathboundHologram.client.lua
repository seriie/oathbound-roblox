--[[
	OathboundHologram (LocalScript)  ->  StarterPlayer/StarterPlayerScripts

	Renders the Oathbound hologram in 3D space, in front of the local camera, and wires the
	artwork ImageButtons to server-validated actions.

	Artwork-first: the panel is an ImageLabel, every button is an ImageButton, and all of it
	comes from HologramConfig. Nothing here draws panel/button/border/label artwork in code.

	Input architecture (this is the part that usually breaks):
	  * A SurfaceGui only receives player input when it lives in the player's PlayerGui and its
	    Adornee is set, AND the adornee part has CanQuery = true. So the OWNER's SurfaceGui is
	    parented to PlayerGui with Adornee = the hologram part, and the part has CanQuery = true.
	  * Other players' holograms do not need input, so their SurfaceGui is parented to the part
	    (client-local, view only) and the part has CanQuery = false. Their buttons are made
	    non-interactive so a viewer can never click someone else's interface.

	Multiplayer: each client builds its own local hologram parts -- there is no replicated part.
	The owner moves its own part every frame from its camera and reports the transform to the
	server, which validates and relays it to everyone else. Private holograms are never relayed,
	so a Private hologram's position is never sent to another client at all.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hologramFolder = ReplicatedStorage:WaitForChild("OathboundHologram")
local Config = require(hologramFolder:WaitForChild("HologramConfig"))

-- Resolve the remotes with a timeout so a missing one disables the UI cleanly (with an
-- actionable warning) instead of hanging this script forever.
local function waitForRemote(name)
	local remote = hologramFolder:WaitForChild(name, 15)
	if not remote then
		warn(("[Oathbound] Missing hologram remote '%s'. Expected it under " ..
			"ReplicatedStorage.OathboundHologram. Hologram UI disabled until it exists.")
			:format(name))
	end
	return remote
end

local UpdatePosition = waitForRemote("UpdatePosition")
local SetVisibility = waitForRemote("SetVisibility")
local VisibilityChanged = waitForRemote("VisibilityChanged")
local RequestAction = waitForRemote("RequestAction")

if not (UpdatePosition and SetVisibility and VisibilityChanged and RequestAction) then
	return
end

--------------------------------------------------------------------------------------------------
-- Local action bus: other client scripts can react to hologram navigation without editing this
-- file. Example:
--     local bus = ReplicatedStorage.OathboundHologram:WaitForChild("HologramAction")
--     bus.Event:Connect(function(action)
--         if action.type == "SelectKind" then ... end
--     end)
--------------------------------------------------------------------------------------------------
local actionBus = hologramFolder:FindFirstChild("HologramAction")
if not actionBus then
	actionBus = Instance.new("BindableEvent")
	actionBus.Name = "HologramAction"
	actionBus.Parent = hologramFolder
end

--------------------------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------------------------
local myState = {
	visibility = Config.Behavior.DefaultVisibility,
	open = Config.Behavior.OpenByDefault,
	alive = true,
}

local activeKind = "Race"
local ownerHologram = nil
local remoteHolograms = {} -- userId -> hologram record
local overlayLabels = {}

-- Forward declarations (mutually referenced by the builders/actions below).
local handleAction, selectKind, cycleVisibility, setVisibility, requestOpen, doReroll, showConfirm
local refreshSelection, refreshVisibilityButton, applyOwnerVisible, placeHologramInWorld

local visibilityCycle = { Public = "Private", Private = "Hidden", Hidden = "Public" }

--------------------------------------------------------------------------------------------------
-- Small asset helpers
--------------------------------------------------------------------------------------------------
local warnedAssets = {}

local function requireAsset(asset, label)
	if Config.IsAssetAssigned(asset) then
		return asset
	end
	if not warnedAssets[label] then
		warnedAssets[label] = true
		warn(("[Oathbound] Hologram artwork not assigned: %s. Set its asset ID in " ..
			"ReplicatedStorage.OathboundHologram.HologramConfig."):format(label))
	end
	return asset -- return anyway; an unassigned Image simply renders nothing
end

local function applyScaleType(guiObject, sliceCenter)
	if typeof(sliceCenter) == "Rect" then
		guiObject.ScaleType = Enum.ScaleType.Slice
		guiObject.SliceCenter = sliceCenter
	else
		guiObject.ScaleType = Enum.ScaleType.Stretch
	end
end

--------------------------------------------------------------------------------------------------
-- Building the image-based UI
--------------------------------------------------------------------------------------------------
local function buildHologramUI(surface, interactive, onAction)
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = surface

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local fadeTargets = {}
	local function track(obj, base)
		table.insert(fadeTargets, { obj = obj, base = base or 0 })
		return obj
	end

	-- Main panel artwork.
	local panel = Instance.new("ImageLabel")
	panel.Name = "Panel"
	panel.BackgroundTransparency = 1
	panel.Position = UDim2.fromScale(0, 0)
	panel.Size = UDim2.fromScale(1, 1)
	panel.Image = requireAsset(Config.Panel.Image, "Panel.Image")
	panel.ImageColor3 = Config.Panel.ImageColor3
	panel.ZIndex = 0
	applyScaleType(panel, Config.Panel.SliceCenter)
	panel.Parent = root
	track(panel, Config.Panel.ImageTransparency)

	-- Decorative (non-interactive) artwork.
	for _, cfg in ipairs(Config.Decorations) do
		local deco = Instance.new("ImageLabel")
		deco.Name = cfg.Name or "Decoration"
		deco.BackgroundTransparency = 1
		deco.Position = cfg.Position or UDim2.fromScale(0, 0)
		deco.Size = cfg.Size or UDim2.fromScale(1, 1)
		deco.AnchorPoint = cfg.AnchorPoint or Vector2.new(0, 0)
		deco.Image = requireAsset(cfg.Image, "Decorations." .. (cfg.Name or "?"))
		deco.ImageColor3 = cfg.ImageColor3 or Color3.fromRGB(255, 255, 255)
		deco.ZIndex = cfg.ZIndex or 1
		applyScaleType(deco, cfg.SliceCenter)
		deco.Parent = root
		track(deco, cfg.ImageTransparency or 0)
	end

	-- Clickable button artwork.
	local buttons = {}
	for _, cfg in ipairs(Config.Buttons) do
		local button = Instance.new("ImageButton")
		button.Name = cfg.Name or "Button"
		button.BackgroundTransparency = 1
		button.Position = cfg.Position
		button.Size = cfg.Size
		button.AnchorPoint = cfg.AnchorPoint or Vector2.new(0, 0)
		button.Image = requireAsset(cfg.Image, "Buttons." .. (cfg.Name or "?"))
		button.AutoButtonColor = false
		button.ZIndex = cfg.ZIndex or 2
		if cfg.HoverImage then button.HoverImage = cfg.HoverImage end
		if cfg.PressedImage then button.PressedImage = cfg.PressedImage end
		applyScaleType(button, cfg.SliceCenter)
		button.Active = interactive
		button.Selectable = interactive
		button.Parent = root
		track(button, 0)

		if interactive then
			button.Activated:Connect(function()
				onAction(cfg, button)
			end)
		end
		buttons[cfg.Name] = button
	end

	return {
		surface = surface,
		root = root,
		scale = scale,
		fadeTargets = fadeTargets,
		buttons = buttons,
	}
end

local function newHologramPart(name, canQuery)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = canQuery
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Config.GetPanelStudSize()
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = workspace
	return part
end

local function newHologramSurface(part, interactive)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "HologramSurface"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = Config.Behavior.PixelsPerStud
	surface.AlwaysOnTop = Config.Behavior.AlwaysOnTop
	surface.LightInfluence = Config.Behavior.LightInfluence
	surface.ZOffset = Config.Behavior.ZOffset
	surface.MaxDistance = Config.Behavior.SurfaceMaxDistance
	surface.Active = interactive
	surface.Adornee = part
	-- PlayerGui parenting is required for input; a view-only hologram can live on the part.
	surface.Parent = interactive and playerGui or part
	return surface
end

--------------------------------------------------------------------------------------------------
-- Open / close animation
--------------------------------------------------------------------------------------------------
local function tweenHologram(holo, show)
	local anim = Config.Animation
	if not anim.Enabled then
		holo.scale.Scale = 1
		for _, ft in ipairs(holo.fadeTargets) do
			ft.obj.ImageTransparency = ft.base
		end
		return
	end

	local duration = show and anim.OpenDuration or anim.CloseDuration
	local style = show and anim.OpenEasingStyle or anim.CloseEasingStyle
	local direction = show and anim.OpenEasingDirection or anim.CloseEasingDirection
	local info = TweenInfo.new(duration, style, direction)

	TweenService:Create(holo.scale, info, { Scale = show and 1 or anim.StartScale }):Play()
	for _, ft in ipairs(holo.fadeTargets) do
		TweenService:Create(ft.obj, info, { ImageTransparency = show and ft.base or 1 }):Play()
	end
end

--------------------------------------------------------------------------------------------------
-- Overlays (optional dynamic text)
--------------------------------------------------------------------------------------------------
local function buildOverlays(root)
	overlayLabels = {}
	for index, cfg in ipairs(Config.TextOverlays) do
		local label = Instance.new("TextLabel")
		label.Name = cfg.Name or ("Overlay" .. index)
		label.BackgroundTransparency = 1
		label.Position = cfg.Position or UDim2.fromScale(0, 0)
		label.Size = cfg.Size or UDim2.fromScale(0.2, 0.06)
		label.Font = cfg.Font or Enum.Font.GothamBold
		label.TextScaled = cfg.TextScaled ~= false
		label.TextColor3 = cfg.TextColor3 or Color3.fromRGB(255, 255, 255)
		label.TextStrokeTransparency = cfg.TextStrokeTransparency or 1
		label.Text = ""
		label.ZIndex = cfg.ZIndex or 3
		label.Parent = root
		overlayLabels[label.Name] = { cfg = cfg, label = label }
	end
end

local function refreshOverlays(state)
	if not state then return end
	for _, entry in pairs(overlayLabels) do
		local ok, text = pcall(entry.cfg.Text, state)
		if ok and text ~= nil then
			entry.label.Text = tostring(text)
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Owner hologram
--------------------------------------------------------------------------------------------------
local function createOwnerHologram()
	if ownerHologram then return ownerHologram end

	local part = newHologramPart("OathboundHologram_" .. player.UserId, Config.Behavior.CanQuery)
	local surface = newHologramSurface(part, true)
	local holo = buildHologramUI(surface, true, handleAction)
	holo.part = part
	holo.visible = false
	surface.Enabled = false
	buildOverlays(holo.root)

	ownerHologram = holo
	refreshSelection()
	refreshVisibilityButton()
	return holo
end

-- Rebuilds the owner hologram if its instances ever disappear (e.g. a full PlayerGui reset).
local function ensureOwnerHologram()
	if ownerHologram and ownerHologram.part.Parent and ownerHologram.surface.Parent then
		return ownerHologram
	end
	if ownerHologram then
		if ownerHologram.surface then ownerHologram.surface:Destroy() end
		if ownerHologram.part then ownerHologram.part:Destroy() end
		ownerHologram = nil
	end
	return createOwnerHologram()
end

applyOwnerVisible = function(visible)
	local holo = ownerHologram
	if not holo or holo.visible == visible then return end
	holo.visible = visible

	if visible then
		-- CanQuery must be true for the buttons to receive input while shown.
		holo.part.CanQuery = Config.Behavior.CanQuery
		holo.surface.Enabled = true
		tweenHologram(holo, true)
		-- Place the hologram at a fixed position in the world in front of the player.
		placeHologramInWorld()
	elseif Config.Animation.Enabled then
		-- While hidden the panel is invisible, so stop it from intercepting mouse raycasts.
		holo.part.CanQuery = false
		tweenHologram(holo, false)
		local closing = holo
		task.delay(Config.Animation.CloseDuration, function()
			if ownerHologram == closing and not closing.visible then
				closing.surface.Enabled = false
			end
		end)
	else
		holo.part.CanQuery = false
		holo.surface.Enabled = false
	end
end

local function shouldOwnerRender()
	if not myState.open then return false end
	if myState.visibility == "Hidden" then return false end
	if Config.Behavior.HideWhenDead and not myState.alive then return false end
	return true
end

--------------------------------------------------------------------------------------------------
-- Remote holograms (other players)
--------------------------------------------------------------------------------------------------
local function removeRemoteHologram(userId)
	local holo = remoteHolograms[userId]
	if holo then
		if holo.part then holo.part:Destroy() end
		remoteHolograms[userId] = nil
	end
end

local function createRemoteHologram(userId)
	local part = newHologramPart("OathboundHologram_" .. userId, false)
	local surface = newHologramSurface(part, false)
	local holo = buildHologramUI(surface, false, nil)
	holo.part = part
	surface.Enabled = true
	tweenHologram(holo, true) -- snap to full opacity (no per-viewer open animation)
	remoteHolograms[userId] = holo
	return holo
end

local function applyRemoteUpdate(message)
	if type(message) ~= "table" then return end
	local ownerId = message.ownerId
	if type(ownerId) ~= "number" or ownerId == player.UserId then
		return -- never handle our own hologram from a network message
	end

	local cframe = message.cframe
	if message.visibility ~= "Public" or typeof(cframe) ~= "CFrame" then
		removeRemoteHologram(ownerId)
		return
	end

	local holo = remoteHolograms[ownerId] or createRemoteHologram(ownerId)
	holo.part.CFrame = cframe
end

--------------------------------------------------------------------------------------------------
-- Actions (owner only)
--------------------------------------------------------------------------------------------------
refreshSelection = function()
	local holo = ownerHologram
	if not holo then return end
	for _, cfg in ipairs(Config.Buttons) do
		local button = holo.buttons[cfg.Name]
		local action = cfg.Action
		if button and action and action.Type == "SelectKind" then
			local normal = cfg.NormalImage or cfg.Image
			local selected = cfg.SelectedImage or normal
			button.Image = (action.Kind == activeKind) and selected or normal
		end
	end
end

refreshVisibilityButton = function()
	local holo = ownerHologram
	if not holo then return end
	for _, cfg in ipairs(Config.Buttons) do
		if cfg.Action and cfg.Action.Type == "CycleVisibility" and type(cfg.StateImages) == "table" then
			local image = cfg.StateImages[myState.visibility]
			if Config.IsAssetAssigned(image) then
				local button = holo.buttons[cfg.Name]
				if button then button.Image = image end
			end
		end
	end
end

selectKind = function(kind)
	activeKind = kind
	refreshSelection()

	local panelCfg = Config.Panels[kind]
	if panelCfg and Config.IsAssetAssigned(panelCfg.Image) then
		-- Artwork exists: show it as a display panel layered over the hologram.
		if ownerHologram then
			if ownerHologram.subPanel then
				ownerHologram.subPanel:Destroy()
				ownerHologram.subPanel = nil
			end
			if ownerHologram.subPanelKind ~= kind then
				local sub = Instance.new("ImageLabel")
				sub.Name = kind .. "Panel"
				sub.BackgroundTransparency = 1
				sub.Position = panelCfg.Position
				sub.Size = panelCfg.Size
				sub.Image = panelCfg.Image
				sub.ZIndex = panelCfg.ZIndex or 5
				applyScaleType(sub, panelCfg.SliceCenter)
				sub.Parent = ownerHologram.root
				ownerHologram.subPanel = sub
				ownerHologram.subPanelKind = kind
			else
				ownerHologram.subPanelKind = nil
			end
		end
		actionBus:Fire({ type = "OpenInterface", kind = kind })
	else
		-- No artwork yet: say so plainly instead of pretending the interface exists.
		warn(("[Oathbound] The %s interface is not implemented yet. Assign artwork to " ..
			"HologramConfig.Panels.%s to enable it. Reroll will still target %s.")
			:format(kind, kind, kind))
		actionBus:Fire({ type = "SelectKind", kind = kind })
	end
end

doReroll = function(kind, currency)
	local result = RequestAction:InvokeServer("Reroll", kind, currency)
	if type(result) ~= "table" then
		warn("[Oathbound] Reroll returned an unexpected response:", result)
		return
	end

	if result.ok then
		return -- authoritative state arrives via ReplicatedStorage.Oathbound.StateChanged
	end

	if result.confirmRequired then
		showConfirm(result.current, function()
			local confirmed = RequestAction:InvokeServer("Reroll", kind, currency, true)
			if type(confirmed) == "table" and not confirmed.ok and not confirmed.promptProductId then
				warn("[Oathbound] Confirmed reroll failed:", confirmed.error)
			elseif type(confirmed) == "table" and confirmed.promptProductId then
				MarketplaceService:PromptProductPurchase(player, confirmed.promptProductId)
			end
		end)
	elseif result.promptProductId then
		MarketplaceService:PromptProductPurchase(player, result.promptProductId)
	else
		warn("[Oathbound] Reroll failed:", result.error)
	end
end

setVisibility = function(mode)
	local ok, result = SetVisibility:InvokeServer(mode)
	if ok then
		myState.visibility = result
		refreshVisibilityButton()
		applyOwnerVisible(shouldOwnerRender())
	else
		warn("[Oathbound] Visibility change rejected:", result)
	end
end

cycleVisibility = function()
	setVisibility(visibilityCycle[myState.visibility] or "Public")
end

requestOpen = function(value)
	local result = RequestAction:InvokeServer("SetOpen", value)
	if type(result) == "table" and result.ok then
		myState.open = result.open
	else
		warn("[Oathbound] Open/close request rejected:", result)
	end
	applyOwnerVisible(shouldOwnerRender())
end

showConfirm = function(current, onConfirm)
	local cfg = Config.Panels.Confirm
	local holo = ownerHologram
	if not holo then return end

	local hasArtwork = cfg and Config.IsAssetAssigned(cfg.Image)
		and Config.IsAssetAssigned(cfg.ConfirmButton and cfg.ConfirmButton.Image)
		and Config.IsAssetAssigned(cfg.CancelButton and cfg.CancelButton.Image)

	if not hasArtwork then
		-- Never auto-confirm a protected reroll: without a way to ask, do nothing.
		warn(("[Oathbound] This reroll would destroy a protected result (%s / %s), but no " ..
			"confirmation artwork is assigned (HologramConfig.Panels.Confirm). Reroll cancelled.")
			:format(tostring(current and current.Name), tostring(current and current.Rarity)))
		return
	end

	if holo.confirmDialog then
		holo.confirmDialog:Destroy()
	end

	local dialog = Instance.new("Frame")
	dialog.Name = "ConfirmDialog"
	dialog.BackgroundTransparency = 1
	dialog.Position = cfg.Position
	dialog.Size = cfg.Size
	dialog.ZIndex = cfg.ZIndex or 8
	dialog.Parent = holo.root

	local background = Instance.new("ImageLabel")
	background.Name = "Background"
	background.BackgroundTransparency = 1
	background.Size = UDim2.fromScale(1, 1)
	background.Image = cfg.Image
	background.ZIndex = dialog.ZIndex
	applyScaleType(background, cfg.SliceCenter)
	background.Parent = dialog

	local function makeChoice(buttonCfg, callback)
		local choice = Instance.new("ImageButton")
		choice.Name = "Choice"
		choice.BackgroundTransparency = 1
		choice.Position = buttonCfg.Position
		choice.Size = buttonCfg.Size
		choice.Image = buttonCfg.Image
		choice.AutoButtonColor = false
		choice.ZIndex = dialog.ZIndex + 1
		choice.Parent = dialog
		choice.Activated:Connect(function()
			if holo.confirmDialog then
				holo.confirmDialog:Destroy()
				holo.confirmDialog = nil
			end
			callback()
		end)
	end

	makeChoice(cfg.ConfirmButton, onConfirm)
	makeChoice(cfg.CancelButton, function() end)

	holo.confirmDialog = dialog
end

handleAction = function(cfg)
	local action = cfg.Action
	if type(action) ~= "table" then return end

	local kind = action.Type
	if kind == "SelectKind" then
		selectKind(action.Kind)
	elseif kind == "Reroll" then
		doReroll(action.Kind or activeKind, action.Currency or "Gold")
	elseif kind == "CycleVisibility" then
		cycleVisibility()
	elseif kind == "Close" then
		requestOpen(false)
	elseif kind == "Open" then
		requestOpen(true)
	end
	-- "None" and unknown types are intentional no-ops.
end

--------------------------------------------------------------------------------------------------
-- Local character tracking (hide while dead when configured)
--------------------------------------------------------------------------------------------------
local function onCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	myState.alive = true
	ensureOwnerHologram()
	if humanoid then
		humanoid.Died:Connect(function()
			myState.alive = false
		end)
	end
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

--------------------------------------------------------------------------------------------------
-- Fixed world placement (placed in front of the player on open; stays in place)
--------------------------------------------------------------------------------------------------
placeHologramInWorld = function()
	local holo = ownerHologram
	if not holo then return end
	local character = player.Character
	if not character then return end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local offset = CFrame.new(Config.Behavior.Offset) * CFrame.new(0, 0, -Config.Behavior.Distance)
	-- Face the panel's Front surface back toward the player.
	local target = hrp.CFrame * offset * CFrame.Angles(0, math.pi, 0)
	holo.part.CFrame = target
	-- Send the fixed position to the server so other players can see it.
	if myState.visibility ~= "Hidden" then
		UpdatePosition:FireServer(target)
	end
end
-- Only handle visibility toggling per frame; position is fixed once placed.
RunService.RenderStepped:Connect(function()
	local visible = shouldOwnerRender()
	applyOwnerVisible(visible)
end)

--------------------------------------------------------------------------------------------------
-- Networking
--------------------------------------------------------------------------------------------------
VisibilityChanged.OnClientEvent:Connect(applyRemoteUpdate)

Players.PlayerRemoving:Connect(function(leaving)
	removeRemoteHologram(leaving.UserId)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Config.Keys.CycleVisibility then
		cycleVisibility()
	elseif input.KeyCode == Config.Keys.ToggleHologram then
		requestOpen(not myState.open)
	end
end)

-- Optional: keep dynamic overlays in sync with the authoritative economy state.
task.spawn(function()
	local root = ReplicatedStorage:WaitForChild("Oathbound", 10)
	local stateChanged = root and root:WaitForChild("StateChanged", 10)
	if not stateChanged then return end
	stateChanged.OnClientEvent:Connect(refreshOverlays)

	local initial = RequestAction:InvokeServer("GetState")
	if type(initial) == "table" and initial.ok then
		refreshOverlays(initial.state)
	end
end)

--------------------------------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------------------------------
ensureOwnerHologram()
