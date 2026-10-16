--[[
	ActionService (ModuleScript)

	A single, shared entry point for Oathbound *gameplay* requests so the hologram UI can reuse
	the exact validation, rate limiting, economy and roll logic that Main.server.lua already
	owns. It deliberately contains NO roll/DataStore logic of its own.

	Why this exists
	---------------
	Both the original `ReplicatedStorage.Oathbound.Request` RemoteFunction and the hologram's
	`ReplicatedStorage.OathboundHologram.RequestAction` RemoteFunction must resolve to the SAME
	server handler. Main.server.lua defines that handler and registers it here at startup, so:

		Request.OnServerInvoke          -> handler
		RequestAction.OnServerInvoke    -> ActionService.Handle -> handler

	There is exactly one roll system, one currency check and one set of rules. If the hologram
	server is ever started without Main (it is not), Handle() returns a clean error instead of
	silently doing something different.
]]

local ActionService = {}

local handler = nil

-- Called once by Main.server.lua with its request handler.
function ActionService.Bind(fn)
	assert(typeof(fn) == "function", "ActionService.Bind expects a function")
	handler = fn
end

-- Reuses the registered gameplay handler. Signature matches Request.OnServerInvoke.
function ActionService.Handle(player, action, kind, arg1, arg2)
	if not handler then
		warn("[Oathbound] ActionService.Handle called before Bind(); request ignored")
		return { ok = false, error = "ServiceNotReady" }
	end
	return handler(player, action, kind, arg1, arg2)
end

return ActionService
