-- Shared configuration. Server code imports this too; never trust client-supplied prices/chances.
local Config = {}

Config.DataStoreName = "Oathbound_PlayerData_v1"
Config.DataVersion = 1
Config.StartingGoldVeyra = 0

-- Studio-only testing aid: the amount granted by the DevGrantGold request.
-- That request is rejected outright whenever RunService:IsStudio() is false,
-- so it is unreachable on a live server regardless of what a client sends.
Config.DevGoldAmount = 1000

-- Gold Veyra purchase packs. Replace DeveloperProductId = 0 with the matching IDs from the
-- Creator Dashboard, and create each product at the intended Robux price there.
Config.GoldPacks = {
    Pouch = { DeveloperProductId = 0, Amount = 100 }, -- TODO: Gold pouch product ID
    Chest = { DeveloperProductId = 0, Amount = 500 }, -- TODO: Gold chest product ID
}

Config.RollTypes = {
    Bloodline = {
        GoldCost = 1,
        DeveloperProductId = 0, -- TODO: replace with your Bloodline reroll Developer Product ID (199 Robux)
        Results = {
            { Name = "No Awakened Royal Bloodline", Weight = 95, Rarity = "Common" },
            { Name = "Eryndor", Weight = 2.5, Rarity = "Legendary" },
            { Name = "Vaelthorne", Weight = 1.5, Rarity = "Legendary" },
            { Name = "Astravael", Weight = 1, Rarity = "Legendary" },
        },
        ProtectedRarities = { Legendary = true },
        Storage = { GoldCost = 100, DeveloperProductId = 0 }, -- TODO: Storage product ID (299 Robux)
    },
    Affinity = {
        GoldCost = 1,
        DeveloperProductId = 0, -- TODO: replace with Affinity reroll Developer Product ID (99 Robux)
        Results = {
            { Name = "Earth", Weight = 30, Rarity = "Common" },
            { Name = "Tide", Weight = 27, Rarity = "Common" },
            { Name = "Flame", Weight = 25, Rarity = "Common" },
            { Name = "Gale", Weight = 12, Rarity = "Epic" },
            { Name = "Storm", Weight = 6, Rarity = "Legendary" },
        },
        ProtectedRarities = { Epic = true, Legendary = true },
        Storage = { GoldCost = 100, DeveloperProductId = 0 }, -- TODO: Storage product ID (199 Robux)
    },
    Race = {
        GoldCost = 1,
        DeveloperProductId = 0, -- TODO: replace with Race reroll Developer Product ID (149 Robux)
        Results = {
            { Name = "Human", Weight = 60, Rarity = "Common" },
            { Name = "Wolf Demi-Human", Weight = 15, Rarity = "Uncommon" },
            { Name = "Cat Demi-Human", Weight = 12, Rarity = "Uncommon" },
            { Name = "Fox Demi-Human", Weight = 8, Rarity = "Rare" },
            { Name = "Vampire", Weight = 5, Rarity = "Legendary" },
        },
        ProtectedRarities = { Rare = true, Legendary = true },
        Storage = { GoldCost = 100, DeveloperProductId = 0 }, -- TODO: Storage product ID (249 Robux)
    },
}

-- These are product prices shown in your game design. Roblox Developer Products are configured
-- in Creator Dashboard; their actual Robux prices are set there, not by this table.
Config.DisplayRobuxPrices = {
    Reroll = { Bloodline = 199, Race = 149, Affinity = 99 },
    Storage = { Bloodline = 299, Race = 249, Affinity = 199 },
    Gold = { Pouch = 49, Chest = 199 },
}

return Config
