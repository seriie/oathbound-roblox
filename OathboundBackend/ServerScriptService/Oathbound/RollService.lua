local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Oathbound"):WaitForChild("Config"))
local RollService = {}

local function weightedPick(entries)
	local total = 0
	for _, entry in ipairs(entries) do total += entry.Weight end
	local roll = Random.new():NextNumber(0, total)
	local cursor = 0
	for _, entry in ipairs(entries) do
		cursor += entry.Weight
		if roll <= cursor then
			return { Name = entry.Name, Rarity = entry.Rarity }
		end
	end
	local last = entries[#entries]
	return { Name = last.Name, Rarity = last.Rarity }
end

function RollService.Roll(kind)
	local config = Config.RollTypes[kind]
	assert(config, "Invalid roll type")
	return weightedPick(config.Results)
end

function RollService.IsProtected(kind, result)
	local config = Config.RollTypes[kind]
	return result ~= nil and config.ProtectedRarities[result.Rarity] == true
end

function RollService.IsValidKind(kind)
	return Config.RollTypes[kind] ~= nil
end

return RollService
