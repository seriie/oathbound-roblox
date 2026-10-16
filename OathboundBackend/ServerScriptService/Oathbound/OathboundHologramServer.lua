--[[
	OathboundHologramServer (ModuleScript)

	Server authority for the 3D hologram UI. Started once by Main.server.lua.

	Responsibilities
	----------------
	* Track each player's hologram state (visibility mode, open/closed, alive, last position).
	* Accept, validate and rate-limit the owner's reported hologram transform, then relay it to
	  other clients -- but ONLY while the hologram is Public and exposed.
	* Validate visibility changes and open/close requests, then propagate them.
	* Never let a client choose who it is: every event is keyed on `player.UserId`.
	* Never leak a Private hologram's position to anyone but its owner (a Private hologram is in
	  fact driven entirely by the owner's own client, so no position is sent to anyone else at all).
	* Route the hologram's gameplay button actions into the single shared gameplay handler
	  (ActionService) so there is no second roll/economy code path.

	Network contract
	----------------
	UpdatePosition (RemoteEvent, client -> server): FireServer(hologramCFrame)
	SetVisibility  (RemoteFunction, client -> server): InvokeServer("Public"|"Private"|"Hidden")
	                                                      -> true, newMode | false, reason
	RequestAction  (RemoteFunction, client -> server): InvokeServer(action, arg1, arg2, arg3)
	                                                      -> result table
	VisibilityChanged (RemoteEvent, server -> client): FireClient(player, {
	                                                          ownerId = number,
	                                                          visibility = "Public"|"Private"|"Hidden",
	                                                          cframe = CFrame|nil,
	                                                      })
	                                                      Owners never receive events about
	                                                      themselves; an owner's own hologram is
	                                                      rendered and driven entirely locally.

	RequestAction actions
	---------------------
	  "Reroll"      (kind, currency[, confirmed])  currency = "Gold" | "Robux"
	  "GetState"    ()
	  "SetOpen"     (boolean)
	  "BuyStorage"  (kind, "Gold"|"Robux")
	  "StoreActive" (kind)
	  "SwapStored"  (kind, slotIndex)
	  "BuyGold"     (packName)

	Everything gameplay-related is delegated to ActionService, which is Main.server.lua's own
	validated handler. No currency, roll probability or DataStore schema is re-implemented here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local hologramFolder = ReplicatedStorage:WaitForChild("OathboundHologram")
local Config = require(hologramFolder:WaitForChild("HologramConfig"))
local ActionService = require(script.Parent:WaitForChild("ActionService"))

local OathboundHologramServer = {}
local started = false

-- Resolved in Start() so a missing remote cannot silently hang the whole server.
local UpdatePosition, SetVisibility, VisibilityChanged, RequestAction

-- userId -> { visibility: string, open: boolean, alive: boolean, position: CFrame? }
local states = {}
local lastUpdate = {}
local lastAction = {}
local lastVisibility = {}

local allowedVisibility = {
	Public = true,
	Private = true,
	Hidden = true,
}

local allowedActions = {
	Reroll = true,
	GetState = true,
	SetOpen = true,
	BuyStorage = true,
	StoreActive = true,
	SwapStored = true,
	BuyGold = true,
}

local function newState()
	return {
		visibility = Config.Behavior.DefaultVisibility,
		open = Config.Behavior.OpenByDefault,
		alive = false,
		position = nil,
	}
end

-- A hologram is "exposed" (has something to send to other clients) only when it is open, not
-- Hidden, its owner is alive (when configured) and the server holds a recent position.
local function isExposed(state)
	if not state.open then return false end
	if state.visibility == "Hidden" then return false end
	if Config.Behavior.HideWhenDead and not state.alive then return false end
	return state.position ~= nil
end

local function payload(userId, visibility, cframe)
	return {
		ownerId = userId,
		visibility = visibility,
		cframe = cframe,
	}
end

local function fireToOthers(excluded, message)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= excluded then
			VisibilityChanged:FireClient(other, message)
		end
	end
end

-- Push the current exposure state to every OTHER client. Owners never get their own payload;
-- their local client already renders and drives their hologram.
local function syncVisibility(player)
	local state = states[player.UserId]
	if not state then return end
	local userId = player.UserId

	-- A Private hologram is never shared, so make sure nobody else is holding a stale copy.
	if state.visibility == "Private" then
		fireToOthers(player, payload(userId, "Hidden", nil))
		return
	end

	if isExposed(state) and state.visibility == "Public" then
		fireToOthers(player, payload(userId, "Public", state.position))
	else
		fireToOthers(player, payload(userId, "Hidden", nil))
	end
end

-- Cheap per-update relay for a Public hologram that is already exposed.
local function relayPosition(player)
	local state = states[player.UserId]
	if not state then return end
	if state.visibility == "Public" and isExposed(state) then
		fireToOthers(player, payload(player.UserId, "Public", state.position))
	end
end

local function markAlive(player, value)
	local state = states[player.UserId]
	if not state then return end
	state.alive = value
	if not value then
		state.position = nil
	end
	syncVisibility(player)
end

local function bindCharacter(player)
	local function onCharacter(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not states[player.UserId] then return end
		markAlive(player, true)
		if humanoid then
			humanoid.Died:Connect(function()
				markAlive(player, false)
			end)
		end
	end

	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	player.CharacterRemoving:Connect(function()
		markAlive(player, false)
	end)
end

local function onPlayerAdded(player)
	if states[player.UserId] then return end
	states[player.UserId] = newState()
	lastUpdate[player.UserId] = 0
	lastAction[player.UserId] = 0
	lastVisibility[player.UserId] = 0

	-- Bring the newcomer up to date with every existing Public hologram that is currently shown.
	for userId, state in pairs(states) do
		if userId ~= player.UserId and state.visibility == "Public" and isExposed(state) then
			VisibilityChanged:FireClient(player, payload(userId, "Public", state.position))
		end
	end

	bindCharacter(player)
end

local function onPlayerRemoving(player)
	states[player.UserId] = nil
	lastUpdate[player.UserId] = nil
	lastAction[player.UserId] = nil
	lastVisibility[player.UserId] = nil

	-- Tell everyone still connected to drop this player's hologram.
	VisibilityChanged:FireAllClients(payload(player.UserId, "Hidden", nil))
end

local function onPositionUpdate(player, cframe)
	local now = os.clock()
	if now - (lastUpdate[player.UserId] or 0) < Config.Security.ServerMinUpdateInterval then
		return
	end
	lastUpdate[player.UserId] = now

	if typeof(cframe) ~= "CFrame" then return end

	local state = states[player.UserId]
	if not state then return end

	-- No point accepting a transform the hologram will not render from.
	if not state.open or state.visibility == "Hidden" then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end

	local delta = cframe.Position - root.Position
	if delta.Magnitude > Config.Security.MaxDistanceFromCharacter then
		return -- client-reported position is implausibly far from the owner
	end
	if math.abs(delta.Y) > Config.Security.MaxVerticalOffset then
		return -- reject teleport-style vertical jumps
	end

	state.position = cframe
	relayPosition(player)
end

local function onSetVisibility(player, newVisibility)
	if type(newVisibility) ~= "string" or not allowedVisibility[newVisibility] then
		return false, "InvalidVisibility"
	end

	local state = states[player.UserId]
	if not state then
		return false, "NotReady"
	end

	local now = os.clock()
	if now - (lastVisibility[player.UserId] or 0) < Config.Security.ServerMinVisibilityInterval then
		return false, "RateLimited"
	end
	lastVisibility[player.UserId] = now

	state.visibility = newVisibility
	syncVisibility(player)
	return true, newVisibility
end

local function onRequestAction(player, action, arg1, arg2, arg3)
	if type(action) ~= "string" or not allowedActions[action] then
		return { ok = false, error = "UnknownAction" }
	end

	local state = states[player.UserId]
	if not state then
		return { ok = false, error = "NotReady" }
	end

	local now = os.clock()
	if now - (lastAction[player.UserId] or 0) < Config.Security.ServerMinActionInterval then
		return { ok = false, error = "RateLimited" }
	end
	lastAction[player.UserId] = now

	-- Hologram-local presentation state (not gameplay).
	if action == "SetOpen" then
		if type(arg1) ~= "boolean" then
			return { ok = false, error = "InvalidArgument" }
		end
		state.open = arg1
		syncVisibility(player)
		return { ok = true, open = state.open }
	end

	-- Everything below reuses Main.server.lua's validated gameplay handler via ActionService.
	if action == "GetState" then
		return ActionService.Handle(player, "GetState")
	elseif action == "Reroll" then
		local kind, currency, confirmed = arg1, arg2, arg3
		if currency == "Robux" then
			return ActionService.Handle(player, "RerollRobux", kind, confirmed)
		elseif currency == nil or currency == "Gold" then
			return ActionService.Handle(player, "RerollGold", kind, confirmed)
		end
		return { ok = false, error = "InvalidCurrency" }
	elseif action == "BuyStorage" then
		return ActionService.Handle(player, "BuyStorage", arg1, arg2)
	elseif action == "StoreActive" then
		return ActionService.Handle(player, "StoreActive", arg1)
	elseif action == "SwapStored" then
		return ActionService.Handle(player, "SwapStored", arg1, arg2)
	elseif action == "BuyGold" then
		return ActionService.Handle(player, "BuyGold", arg1)
	end

	return { ok = false, error = "UnknownAction" }
end

function OathboundHologramServer.Start()
	if started then return end
	started = true

	UpdatePosition = hologramFolder:FindFirstChild("UpdatePosition")
	SetVisibility = hologramFolder:FindFirstChild("SetVisibility")
	VisibilityChanged = hologramFolder:FindFirstChild("VisibilityChanged")
	RequestAction = hologramFolder:FindFirstChild("RequestAction")

	local ok = UpdatePosition and UpdatePosition:IsA("RemoteEvent")
		and VisibilityChanged and VisibilityChanged:IsA("RemoteEvent")
		and SetVisibility and SetVisibility:IsA("RemoteFunction")
		and RequestAction and RequestAction:IsA("RemoteFunction")

	if not ok then
		warn("[Oathbound] Hologram remotes are missing or the wrong class. Expected " ..
			"ReplicatedStorage.OathboundHologram to contain UpdatePosition (RemoteEvent), " ..
			"VisibilityChanged (RemoteEvent), SetVisibility (RemoteFunction) and " ..
			"RequestAction (RemoteFunction). The hologram UI is disabled until they exist.")
		return
	end

	UpdatePosition.OnServerEvent:Connect(onPositionUpdate)
	SetVisibility.OnServerInvoke = onSetVisibility
	RequestAction.OnServerInvoke = onRequestAction

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
end

return OathboundHologramServer
