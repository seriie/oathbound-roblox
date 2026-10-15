local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Oathbound"):WaitForChild("Config"))

local Store = DataStoreService:GetDataStore(Config.DataStoreName)
local DataService = {}
local sessions = {}
local saving = {}
local loading = {}

local function newDefaultData()
    return {
        Version = Config.DataVersion,
        GoldVeyra = Config.StartingGoldVeyra,
        Active = { Bloodline = nil, Race = nil, Affinity = nil },
        Storage = { Bloodline = {}, Race = {}, Affinity = {} },
        Receipts = {},
    }
end

local function normalize(data)
    if type(data) ~= "table" then data = newDefaultData() end
    data.Version = Config.DataVersion
    if type(data.GoldVeyra) ~= "number" or data.GoldVeyra < 0 then data.GoldVeyra = Config.StartingGoldVeyra end
    data.Active = type(data.Active) == "table" and data.Active or {}
    data.Storage = type(data.Storage) == "table" and data.Storage or {}
    data.Receipts = type(data.Receipts) == "table" and data.Receipts or {}
    for _, kind in ipairs({ "Bloodline", "Race", "Affinity" }) do
        data.Storage[kind] = type(data.Storage[kind]) == "table" and data.Storage[kind] or {}
        -- Slot entries store a full result object; don't accept malformed records.
        for i = #data.Storage[kind], 1, -1 do
            local entry = data.Storage[kind][i]
            if type(entry) ~= "table" or type(entry.Name) ~= "string" or type(entry.Rarity) ~= "string" then
                table.remove(data.Storage[kind], i)
            end
        end
    end
    return data
end

function DataService.Get(player)
    return sessions[player.UserId]
end

local LOAD_ATTEMPTS = 3
local LOAD_RETRY_DELAY = 2

function DataService.Load(player)
    local userId = player.UserId
    if sessions[userId] then return sessions[userId] end
    -- PlayerAdded and the Start() catch-up loop can both fire for the same user;
    -- only one load may be in flight or we burn DataStore request budget.
    if loading[userId] then return nil end
    loading[userId] = true

    local key = "player_" .. userId
    local lastError
    for attempt = 1, LOAD_ATTEMPTS do
        local ok, result = pcall(function()
            return Store:UpdateAsync(key, function(old)
                return normalize(old)
            end)
        end)
        if ok then
            sessions[userId] = normalize(result)
            break
        end

        lastError = result
        if player.Parent ~= Players then break end

        -- This one never succeeds on retry; fail fast with an actionable message.
        if tostring(result):find("Studio access to APIs", 1, true) then
            warn("[Oathbound] DataStores are blocked in Studio. Publish the place, then enable " ..
                "Game Settings > Security > Enable Studio Access to API Services.")
            break
        end

        if attempt < LOAD_ATTEMPTS then task.wait(LOAD_RETRY_DELAY) end
    end

    loading[userId] = nil

    if sessions[userId] then return sessions[userId] end
    if player.Parent ~= Players then return nil end

    warn(("[Oathbound] Data load failed for %s (%d) after retries: %s")
        :format(player.Name, userId, tostring(lastError)))
    player:Kick("Your data could not be loaded safely. Please rejoin in a moment.")
    return nil
end

function DataService.Save(player)
    local userId = player.UserId
    local data = sessions[userId]
    if not data or saving[userId] then return false end
    saving[userId] = true
    local snapshot = table.clone(data)
    snapshot.Active = table.clone(data.Active)
    snapshot.Storage = table.clone(data.Storage)
    snapshot.Receipts = table.clone(data.Receipts)
    local ok, err = pcall(function()
        Store:UpdateAsync("player_" .. userId, function(_old)
            -- Server session owns this user's record while they're in this server.
            return snapshot
        end)
    end)
    saving[userId] = nil
    if not ok then
        warn(("[Oathbound] Data save failed for %s: %s"):format(player.Name, tostring(err)))
        return false
    end
    return true
end

function DataService.Remove(player)
    DataService.Save(player)
    sessions[player.UserId] = nil
    saving[player.UserId] = nil
    loading[player.UserId] = nil
end

function DataService.Start()
    Players.PlayerAdded:Connect(DataService.Load)
    Players.PlayerRemoving:Connect(DataService.Remove)
    for _, player in ipairs(Players:GetPlayers()) do task.spawn(DataService.Load, player) end
    game:BindToClose(function()
        for _, player in ipairs(Players:GetPlayers()) do
            task.spawn(DataService.Save, player)
        end
        local deadline = os.clock() + 8
        while next(saving) and os.clock() < deadline do task.wait(0.1) end
    end)
end

return DataService
