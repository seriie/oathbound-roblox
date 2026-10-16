-- Roblox class: Script | name: Main | parent: ServerScriptService.Oathbound
-- Backend bootstrap. No UI is created here; client UI can be added later.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local root = ReplicatedStorage:FindFirstChild("Oathbound")
if not root then
	root = Instance.new("Folder")
	root.Name = "Oathbound"
	root.Parent = ReplicatedStorage
end

local function getRemote(name, className)
	local remote = root:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = root
	end
	return remote
end

local Request = getRemote("Request", "RemoteFunction")
local StateChanged = getRemote("StateChanged", "RemoteEvent")
local Config = require(root:WaitForChild("Config"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local RollService = require(script.Parent:WaitForChild("RollService"))
local ActionService = require(script.Parent:WaitForChild("ActionService"))
local HologramServer = require(script.Parent:WaitForChild("OathboundHologramServer"))

DataService.Start()

local rateLimits = {}
local pendingPurchases = {} -- userId -> productId -> {Kind, Action, Token}; token is server-created
local function rateLimited(player)
	local now = os.clock()
	local last = rateLimits[player.UserId] or 0
	if now - last < 0.5 then return true end
	rateLimits[player.UserId] = now
	return false
end

local function publicState(data)
	return {
		GoldVeyra = data.GoldVeyra,
		Active = data.Active,
		Storage = data.Storage,
	}
end

local function pushState(player, data)
	StateChanged:FireClient(player, publicState(data))
end

-- First-join initialization: assign each category exactly once, then persist.
local function initializeFirstJoin(player)
	local deadline = os.clock() + 25
	local data = DataService.Get(player)
	while not data and player.Parent == Players and os.clock() < deadline do
		task.wait(0.1)
		data = DataService.Get(player)
	end
	if not data or player.Parent ~= Players then return end
	local changed = false
	for _, kind in ipairs({ "Bloodline", "Race", "Affinity" }) do
		if data.Active[kind] == nil then
			data.Active[kind] = RollService.Roll(kind)
			changed = true
		end
	end
	if changed and not DataService.Save(player) then
		warn("[Oathbound] Initial rolls could not be saved for", player.UserId)
	end
	pushState(player, data)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(initializeFirstJoin, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initializeFirstJoin, player)
end

local function rollNeedsConfirmation(kind, data)
	return RollService.IsProtected(kind, data.Active[kind])
end

local function doGoldReroll(player, kind, confirmed)
	local data = DataService.Get(player)
	local config = Config.RollTypes[kind]
	if not data or not config then return { ok = false, error = "NotReadyOrInvalidType" } end
	if rollNeedsConfirmation(kind, data) and confirmed ~= true then
		return { ok = false, confirmRequired = true, current = data.Active[kind] }
	end
	if data.GoldVeyra < config.GoldCost then return { ok = false, error = "NotEnoughGoldVeyra" } end
	data.GoldVeyra -= config.GoldCost
	data.Active[kind] = RollService.Roll(kind)
	DataService.Save(player)
	pushState(player, data)
	return { ok = true, result = data.Active[kind], state = publicState(data) }
end

local function requestRobuxReroll(player, kind, confirmed)
	local data = DataService.Get(player)
	local config = Config.RollTypes[kind]
	if not data or not config then return { ok = false, error = "NotReadyOrInvalidType" } end
	if rollNeedsConfirmation(kind, data) and confirmed ~= true then
		return { ok = false, confirmRequired = true, current = data.Active[kind] }
	end
	if config.DeveloperProductId <= 0 then
		return { ok = false, error = "DeveloperProductNotConfigured" }
	end
	local token = HttpService:GenerateGUID(false)
	pendingPurchases[player.UserId] = pendingPurchases[player.UserId] or {}
	pendingPurchases[player.UserId][config.DeveloperProductId] = { Action = "Reroll", Kind = kind, Token = token }
	return { ok = true, promptProductId = config.DeveloperProductId, token = token }
end

local function buyStorage(player, kind, payment, confirmed)
	local data = DataService.Get(player)
	local config = Config.RollTypes[kind]
	if not data or not config then return { ok = false, error = "NotReadyOrInvalidType" } end
	if data.Storage[kind .. "Unlocked"] == true then return { ok = false, error = "AlreadyUnlocked" } end
	if payment == "Gold" then
		if data.GoldVeyra < config.Storage.GoldCost then return { ok = false, error = "NotEnoughGoldVeyra" } end
		data.GoldVeyra -= config.Storage.GoldCost
		data.Storage[kind .. "Unlocked"] = true
		DataService.Save(player)
		pushState(player, data)
		return { ok = true, state = publicState(data) }
	elseif payment == "Robux" then
		if config.Storage.DeveloperProductId <= 0 then return { ok = false, error = "DeveloperProductNotConfigured" } end
		pendingPurchases[player.UserId] = pendingPurchases[player.UserId] or {}
		pendingPurchases[player.UserId][config.Storage.DeveloperProductId] = { Action = "Storage", Kind = kind, Token = HttpService:GenerateGUID(false) }
		return { ok = true, promptProductId = config.Storage.DeveloperProductId }
	end
	return { ok = false, error = "InvalidPaymentMethod" }
end

-- The only way Gold Veyra enters the economy. Always server-side: amounts come from
-- Config or from a Developer Product intent the server itself created.
local function grantGold(player, amount)
	local data = DataService.Get(player)
	if not data or type(amount) ~= "number" or amount <= 0 then return nil end
	data.GoldVeyra += amount
	if not DataService.Save(player) then
		warn("[Oathbound] Gold grant could not be saved for", player.UserId)
	end
	pushState(player, data)
	return data
end

local function requestGoldPurchase(player, packName)
	local data = DataService.Get(player)
	if not data then return { ok = false, error = "DataNotReady" } end
	local pack = type(packName) == "string" and Config.GoldPacks[packName] or nil
	if not pack then return { ok = false, error = "InvalidPack" } end
	if pack.DeveloperProductId <= 0 then
		return { ok = false, error = "DeveloperProductNotConfigured" }
	end
	pendingPurchases[player.UserId] = pendingPurchases[player.UserId] or {}
	pendingPurchases[player.UserId][pack.DeveloperProductId] = {
		Action = "Gold",
		Amount = pack.Amount,
		Token = HttpService:GenerateGUID(false),
	}
	return { ok = true, promptProductId = pack.DeveloperProductId, amount = pack.Amount }
end

local function devGrantGold(player)
	-- Studio-only testing aid. IsStudio() is false on every live server, so this
	-- branch is unreachable in production no matter what a client sends.
	if not RunService:IsStudio() then return { ok = false, error = "NotAvailable" } end
	local data = grantGold(player, Config.DevGoldAmount)
	if not data then return { ok = false, error = "DataNotReady" } end
	return { ok = true, granted = Config.DevGoldAmount, state = publicState(data) }
end

local function handleRequest(player, action, kind, arg1, arg2)
	if rateLimited(player) then return { ok = false, error = "RateLimited" } end
	if type(action) ~= "string" then return { ok = false, error = "InvalidRequest" } end
	local data = DataService.Get(player)
	if not data then return { ok = false, error = "DataNotReady" } end

	if action == "GetState" then
		return { ok = true, state = publicState(data) }
	elseif action == "RerollGold" then
		if not RollService.IsValidKind(kind) then return { ok = false, error = "InvalidType" } end
		return doGoldReroll(player, kind, arg1)
	elseif action == "RerollRobux" then
		if not RollService.IsValidKind(kind) then return { ok = false, error = "InvalidType" } end
		return requestRobuxReroll(player, kind, arg1)
	elseif action == "BuyStorage" then
		if not RollService.IsValidKind(kind) then return { ok = false, error = "InvalidType" } end
		return buyStorage(player, kind, arg1, arg2)
	elseif action == "BuyGold" then
		return requestGoldPurchase(player, kind)
	elseif action == "DevGrantGold" then
		return devGrantGold(player)
	elseif action == "StoreActive" or action == "SwapStored" then
		if not RollService.IsValidKind(kind) then return { ok = false, error = "InvalidType" } end
		if data.Storage[kind .. "Unlocked"] ~= true then return { ok = false, error = "StorageLocked" } end
		local slots = data.Storage[kind]
		if action == "StoreActive" then
			local active = data.Active[kind]
			if not active then return { ok = false, error = "NoActiveResult" } end
			if #slots >= 1 then return { ok = false, error = "StorageFull" } end
			-- Store a copy; the active result remains equipped and can be rerolled later.
			slots[1] = { Name = active.Name, Rarity = active.Rarity }
		else
			local index = tonumber(arg1)
			if not index or index % 1 ~= 0 or index < 1 or index > #slots then return { ok = false, error = "InvalidSlot" } end
			local old = data.Active[kind]
			data.Active[kind] = slots[index]
			if old then slots[index] = old else table.remove(slots, index) end
		end
		DataService.Save(player)
		pushState(player, data)
		return { ok = true, state = publicState(data) }
	end
	return { ok = false, error = "UnknownAction" }
end

Request.OnServerInvoke = handleRequest
-- Expose the same validated handler to the hologram server so RequestAction can reuse it
-- rather than duplicating any roll, currency or receipt logic.
ActionService.Bind(handleRequest)

HologramServer.Start()

-- NOTE: Marketplace receipts must only be granted from ProcessReceipt, never from a client event.
-- This starter intentionally refuses unconfigured/unmatched receipts. Configure product IDs first.
MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local data = DataService.Get(player)
	if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local purchaseId = tostring(receiptInfo.PurchaseId)
	if data.Receipts[purchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end

	local pending = pendingPurchases[player.UserId]
	local intent = pending and pending[receiptInfo.ProductId]
	if not intent then
		warn("[Oathbound] Receipt has no matching pending purchase intent; not granting", purchaseId, receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local kind = intent.Kind
	if intent.Action == "Reroll" then
		data.Active[kind] = RollService.Roll(kind)
	elseif intent.Action == "Storage" then
		if data.Storage[kind .. "Unlocked"] ~= true then
			data.Storage[kind .. "Unlocked"] = true
		end
	elseif intent.Action == "Gold" then
		data.GoldVeyra += intent.Amount
	else
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	data.Receipts[purchaseId] = true
	pending[receiptInfo.ProductId] = nil
	if not DataService.Save(player) then
		-- Return NotProcessedYet so Roblox retries receipt processing.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	pushState(player, data)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

Players.PlayerRemoving:Connect(function(player)
	rateLimits[player.UserId] = nil
	pendingPurchases[player.UserId] = nil
end)
