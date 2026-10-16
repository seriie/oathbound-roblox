--[[
	HologramConfig (ModuleScript)

	Central configuration for the Oathbound 3D hologram UI.

	ARTWORK-FIRST
	-------------
	Every visible element of the hologram is an ImageLabel or ImageButton whose `Image`
	is an asset ID YOU upload. This module never draws a panel, button, border, decoration
	or label in code -- it only places your artwork on a 3D SurfaceGui and wires the
	ImageButtons to server-validated actions.

	HOW TO FILL IN THE ASSET IDS
	----------------------------
	1. Upload each PNG to Roblox (Creator Dashboard -> Development Items -> Decals/Images,
	   or Studio Asset Manager). Let the image upload fully.
	2. Right-click the uploaded image -> "Copy Asset ID". It looks like 1234567890.
	3. Replace the matching "rbxassetid://0" below with "rbxassetid://1234567890".
	   A value of "rbxassetid://0" means "not configured yet" and is treated as missing.

	Nothing here invents an asset ID. Unassigned artwork is reported clearly at runtime
	(see the warnings in OathboundHologram.client.lua) instead of silently drawing a
	placeholder.

	This module is required by BOTH the server (for security/defaults) and the client
	(for layout/artwork), so keep it free of client-only APIs.
]]

local HologramConfig = {}

-- Sentinel for "this artwork has not been assigned yet".
HologramConfig.UnsetAsset = "rbxassetid://0"

local function isAssigned(asset)
	return type(asset) == "string" and asset ~= "" and asset ~= HologramConfig.UnsetAsset
end

HologramConfig.IsAssetAssigned = isAssigned

--------------------------------------------------------------------------------------------------
-- 1. MAIN PANEL ARTWORK
--------------------------------------------------------------------------------------------------
-- The big hologram background/frame image. THIS IS REQUIRED for the hologram to look right.
HologramConfig.Panel = {
	Image = "rbxassetid://132652503921071", -- TODO: paste your main hologram panel asset ID here

	-- Pixel resolution of the artwork above. It is used ONLY to keep the 3D panel's aspect
	-- ratio identical to the artwork so nothing is stretched. Set this to your image's real
	-- pixel size (Studio Asset Manager shows it, or check the file's properties).
	DesignSize = Vector2.new(1920, 1080),

	-- Optional 9-slice so the panel scales without distorting its borders.
	-- Rect(left, top, right, bottom) in DesignSize pixels. nil = plain stretch.
	SliceCenter = nil,

	-- Tint / transparency of the artwork only (1 = invisible artwork). Leave defaults unless
	-- you want to drive a fade in code.
	ImageColor3 = Color3.fromRGB(255, 255, 255),
	ImageTransparency = 0,
}

--------------------------------------------------------------------------------------------------
-- 2. DECORATIVE OVERLAYS (optional)
--------------------------------------------------------------------------------------------------
-- Non-interactive ImageLabels drawn on top of the panel (glows, corner flourishes, a logo...).
-- They are pure artwork; add as many as you like. ZIndex controls stacking (panel = 0).
HologramConfig.Decorations = {
	-- {
	--     Name = "TopGlow",
	--     Image = "rbxassetid://0", -- TODO
	--     Position = UDim2.fromScale(0, 0),
	--     Size = UDim2.fromScale(1, 0.25),
	--     AnchorPoint = Vector2.new(0, 0),
	--     ImageColor3 = Color3.fromRGB(255, 255, 255),
	--     ImageTransparency = 0,
	--     ZIndex = 1,
	-- },
}

--------------------------------------------------------------------------------------------------
-- 3. CLICKABLE BUTTONS
--------------------------------------------------------------------------------------------------
-- Each entry becomes one ImageButton layered over the panel. Position/Size are NORMALIZED
-- (0..1) relative to the panel, so the hitboxes track the artwork when the panel size changes.
--
-- IMPORTANT: make Position/Size rectangles match the artwork boxes and do not let them
-- overlap, otherwise clicks on one button could land on a neighbour. Where `SliceCenter` is
-- set the image is 9-sliced instead of stretched (use it for framed button art).
--
-- Action types understood by the client:
--   { Type = "SelectKind", Kind = "Race" }       -- pick the reroll target + open its interface
--   { Type = "Reroll", Currency = "Gold" }         -- reroll the currently selected kind
--   { Type = "Reroll", Currency = "Robux" }        -- same but via a Robux Developer Product
--   { Type = "CycleVisibility" }                   -- Public -> Private -> Hidden -> Public
--   { Type = "Close" }                             -- close the hologram (hides for everyone)
--   { Type = "Open" }                              -- open the hologram
--   { Type = "None" }                              -- decorative / no-op
HologramConfig.Buttons = {
	{
		Name = "RaceButton",
		Image = "rbxassetid://123717188701310", -- TODO: Race button artwork
		Position = UDim2.fromScale(0.055, 0.280),
		Size = UDim2.fromScale(0.270, 0.130),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		-- Optional artwork for the currently-selected target:
		NormalImage = nil,
		SelectedImage = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "SelectKind", Kind = "Race" },
	},
	{
		Name = "AffinityButton",
		Image = "rbxassetid://134699181906765", -- TODO: Affinity button artwork
		Position = UDim2.fromScale(0.365, 0.280),
		Size = UDim2.fromScale(0.270, 0.130),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		NormalImage = nil,
		SelectedImage = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "SelectKind", Kind = "Affinity" },
	},
	{
		Name = "BloodlineButton",
		Image = "rbxassetid://127770356002880", -- TODO: Bloodline button artwork
		Position = UDim2.fromScale(0.675, 0.280),
		Size = UDim2.fromScale(0.270, 0.130),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		NormalImage = nil,
		SelectedImage = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "SelectKind", Kind = "Bloodline" },
	},
	{
		Name = "RerollButton",
		Image = "rbxassetid://129315433378639", -- RR1GoldVeyraButton artwork
		Position = UDim2.fromScale(0.365, 0.465),
		Size = UDim2.fromScale(0.270, 0.150),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "Reroll", Currency = "Gold" },
	},
	{
		Name = "RaceRerollRobuxButton",
		Image = "rbxassetid://82301895782570", -- RR149RobuxButton artwork (Race = 149 Robux)
		Position = UDim2.fromScale(0.055, 0.635),
		Size = UDim2.fromScale(0.270, 0.130),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "Reroll", Currency = "Robux", Kind = "Race" },
	},
	{
		Name = "AffinityRerollRobuxButton",
		Image = "rbxassetid://75044325885805", -- RR99RobuxButton artwork (Affinity = 99 Robux)
		Position = UDim2.fromScale(0.365, 0.635),
		Size = UDim2.fromScale(0.270, 0.130),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "Reroll", Currency = "Robux", Kind = "Affinity" },
	},
	{
		Name = "BloodlineRerollRobuxButton",
		Image = "rbxassetid://129153207108430", -- RR199RobuxButton artwork (Bloodline = 199 Robux)
		Position = UDim2.fromScale(0.675, 0.635),
		Size = UDim2.fromScale(0.270, 0.130),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "Reroll", Currency = "Robux", Kind = "Bloodline" },
	},
	{
		Name = "VisibilityButton",
		Image = "rbxassetid://0", -- TODO: Visibility toggle artwork (shown for Public by default)
		Position = UDim2.fromScale(0.055, 0.800),
		Size = UDim2.fromScale(0.270, 0.110),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		-- Optional per-mode artwork. When supplied, the button swaps image to match the
		-- current mode so the owner gets visual feedback without any drawn text.
		-- StateImages = {
		--     Public = "rbxassetid://0",
		--     Private = "rbxassetid://0",
		--     Hidden = "rbxassetid://0",
		-- },
		StateImages = nil,
		ZIndex = 2,
		Action = { Type = "CycleVisibility" },
	},
	{
		Name = "CloseButton",
		Image = "rbxassetid://0", -- TODO: Close button artwork
		Position = UDim2.fromScale(0.675, 0.800),
		Size = UDim2.fromScale(0.270, 0.110),
		AnchorPoint = Vector2.new(0, 0),
		SliceCenter = nil,
		HoverImage = nil,
		PressedImage = nil,
		ZIndex = 2,
		Action = { Type = "Close" },
	},
}

--------------------------------------------------------------------------------------------------
-- 4. OPTIONAL SUB-PANELS
--------------------------------------------------------------------------------------------------
-- When a Race/Affinity/Bloodline button is pressed the client looks for a matching panel here.
-- If the artwork is unassigned the action is reported as "not implemented yet" instead of
-- pretending it works (see client warning). Leave as-is until you have those images.
HologramConfig.Panels = {
	Race = {
		Image = "rbxassetid://0", -- TODO: Race interface artwork (optional)
		Position = UDim2.fromScale(0.250, 0.230),
		Size = UDim2.fromScale(0.500, 0.540),
		SliceCenter = nil,
		ZIndex = 5,
	},
	Affinity = {
		Image = "rbxassetid://0", -- TODO: Affinity interface artwork (optional)
		Position = UDim2.fromScale(0.250, 0.230),
		Size = UDim2.fromScale(0.500, 0.540),
		SliceCenter = nil,
		ZIndex = 5,
	},
	Bloodline = {
		Image = "rbxassetid://0", -- TODO: Bloodline interface artwork (optional)
		Position = UDim2.fromScale(0.250, 0.230),
		Size = UDim2.fromScale(0.500, 0.540),
		SliceCenter = nil,
		ZIndex = 5,
	},
	-- Confirmation prompt shown when a reroll would destroy a protected (rare) result.
	-- Without this artwork the client refuses to auto-confirm and cancels the reroll.
	Confirm = {
		Image = "rbxassetid://0", -- TODO: Confirmation dialog artwork (optional)
		Position = UDim2.fromScale(0.250, 0.300),
		Size = UDim2.fromScale(0.500, 0.400),
		SliceCenter = nil,
		ZIndex = 8,
		ConfirmButton = {
			Image = "rbxassetid://0", -- TODO: "Confirm" button artwork
			Position = UDim2.fromScale(0.080, 0.700),
			Size = UDim2.fromScale(0.380, 0.200),
		},
		CancelButton = {
			Image = "rbxassetid://0", -- TODO: "Cancel" button artwork
			Position = UDim2.fromScale(0.540, 0.700),
			Size = UDim2.fromScale(0.380, 0.200),
		},
	},
}

--------------------------------------------------------------------------------------------------
-- 5. OPTIONAL DYNAMIC TEXT OVERLAYS
--------------------------------------------------------------------------------------------------
-- Your artwork already contains the static labels, so this list is EMPTY by default and the
-- hologram is 100% image based. Add entries only for values that genuinely change at runtime
-- (Gold Veyra balance, the current result, ...). `Text` receives the state table pushed by the
-- server through StateChanged: { GoldVeyra, Active, Storage }.
HologramConfig.TextOverlays = {
	-- {
	--     Name = "GoldLabel",
	--     Text = function(state) return tostring(state.GoldVeyra or 0) end,
	--     Position = UDim2.fromScale(0.70, 0.05),
	--     Size = UDim2.fromScale(0.25, 0.08),
	--     Font = Enum.Font.GothamBold,
	--     TextScaled = true,
	--     TextColor3 = Color3.fromRGB(120, 220, 255),
	--     TextStrokeTransparency = 0.5,
	--     ZIndex = 3,
	-- },
}

--------------------------------------------------------------------------------------------------
-- 6. BEHAVIOR (client rendering + shared defaults)
--------------------------------------------------------------------------------------------------
HologramConfig.Behavior = {
	-- Distance in studs from the camera to the hologram plane, along the camera's look vector.
	Distance = 8,

	-- Extra offset in camera space (applied before the Distance step). X = right, Y = up.
	Offset = Vector3.new(0, 0, 0),

	-- 3D size of the panel. Width is in studs; height is derived from Panel.DesignSize so the
	-- artwork keeps its aspect ratio. Thickness is the invisible backing slab.
	PanelWidthStuds = 10,
	PanelThicknessStuds = 0.12,

	-- SurfaceGui resolution. Higher = crisper artwork, slightly more texture memory.
	-- PixelsPerStud is derived from the artwork's DesignSize so the 3D panel renders at
	-- full artwork resolution. For a 1024px-wide panel at 6 studs, this is ~170.
	PixelsPerStud = 170,

	-- How many position updates per second the owner sends to the server.
	UpdateRate = 12,

	-- Camera follow smoothing. 0 = snap to the camera every frame. > 0 eases (larger = tighter).
	FollowSmoothing = 0,

	-- Initial visibility mode when a player joins. One of "Public" / "Private" / "Hidden".
	DefaultVisibility = "Public",

	-- Whether the hologram starts open (rendered). Closing hides it for everyone until reopened.
	OpenByDefault = false,

	-- Hide the hologram while the owner's character is dead / respawning.
	HideWhenDead = true,

	-- SurfaceGui rendering options for the holographic look.
	AlwaysOnTop = false,
	LightInfluence = 0,
	ZOffset = 0,
	SurfaceMaxDistance = 0, -- 0 = no render-distance limit (studs)

	-- The SurfaceGui's adornee part must have CanQuery = true for its buttons to receive input.
	-- This does not make the panel solid; it only allows the GUI to be clicked. See the README
	-- for the raycast implication.
	CanQuery = true,
}

--------------------------------------------------------------------------------------------------
-- 7. SECURITY / SERVER-SIDE VALIDATION
--------------------------------------------------------------------------------------------------
HologramConfig.Security = {
	-- Minimum seconds between accepted position updates, action requests and visibility changes.
	ServerMinUpdateInterval = 0.05,
	ServerMinActionInterval = 0.40,
	ServerMinVisibilityInterval = 0.40,

	-- Reject a reported position further than this from the owner's HumanoidRootPart.
	MaxDistanceFromCharacter = 35,

	-- Reject reported positions whose Y is absurd relative to the character (anti-teleport).
	MaxVerticalOffset = 20,
}

--------------------------------------------------------------------------------------------------
-- 8. OPEN / CLOSE ANIMATION (optional)
--------------------------------------------------------------------------------------------------
HologramConfig.Animation = {
	Enabled = true,
	OpenDuration = 0.25,
	CloseDuration = 0.15,
	OpenEasingStyle = Enum.EasingStyle.Back,
	OpenEasingDirection = Enum.EasingDirection.Out,
	CloseEasingStyle = Enum.EasingStyle.Quad,
	CloseEasingDirection = Enum.EasingDirection.In,
	StartScale = 0.80, -- UIScale the panel pops in from
}

--------------------------------------------------------------------------------------------------
-- 9. KEYBINDS (desktop)
--------------------------------------------------------------------------------------------------
-- The hologram is fully usable with mouse/touch on the panel itself. These keys exist so the
-- owner can still reach the controls while the hologram is Hidden or closed (when the panel
-- itself is not rendered / not clickable). Touch users cannot un-hide without an on-screen
-- control; see the README limitations section.
HologramConfig.Keys = {
	ToggleHologram = Enum.KeyCode.E,
	CycleVisibility = Enum.KeyCode.V,
}

--------------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------------

-- 3D size of the panel part, derived from the artwork aspect ratio so nothing is stretched.
function HologramConfig.GetPanelStudSize()
	local design = HologramConfig.Panel.DesignSize
	local width = HologramConfig.Behavior.PanelWidthStuds
	local thickness = HologramConfig.Behavior.PanelThicknessStuds
	local aspect = 1
	if typeof(design) == "Vector2" and design.X > 0 and design.Y > 0 then
		aspect = design.Y / design.X
	end
	return Vector3.new(width, width * aspect, thickness)
end

return HologramConfig
