
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local oathbound = ReplicatedStorage:WaitForChild("Oathbound")
local request = oathbound:WaitForChild("Request")

local function test(action, ...)
	local success, result = pcall(function(...)
		return request:InvokeServer(action, ...)
	end, ...)

	print("\n=== TEST:", action, "===")

	if not success then
		warn("Request failed:", result)
	else
		print(result)

		if result.state then
			print("Gold Veyra:", result.state.GoldVeyra)
			print("Active:", result.state.Active)
			print("Storage:", result.state.Storage)
		end

		if result.error then
			warn("Backend response:", result.error)
		end
	end

	-- The server rate-limits requests to one per 0.5s, so pace the calls.
	task.wait(0.6)
end

task.wait(3)

test("GetState")
test("DevGrantGold")                -- Studio-only testing aid; no-op on a live server
test("RerollGold", "Bloodline")     -- costs 1 Gold Veyra
test("BuyStorage", "Race", "Gold")  -- costs 100 Gold Veyra
test("StoreActive", "Race")
test("GetState")
