# OathboundHologram

This folder holds the hologram UI's shared config plus **instances that cannot be stored as
Lua source** — the four remotes. The `.lua` files here (`RequestAction`, `SetVisibility`,
`UpdatePosition`, `VisibilityChanged`) are empty reminders of the exact instance **names**; they
are **not** ModuleScripts.

Create these in Roblox Studio under `ReplicatedStorage.OathboundHologram`:

| Name | Class |
|---|---|
| `RequestAction` | `RemoteFunction` |
| `SetVisibility` | `RemoteFunction` |
| `UpdatePosition` | `RemoteEvent` |
| `VisibilityChanged` | `RemoteEvent` |

…and this one as a normal script:

| Name | Class | Paste from |
|---|---|---|
| `HologramConfig` | `ModuleScript` | `HologramConfig.lua` |

Names must match exactly. In particular it is `VisibilityChanged` (with a **d**), not
`VisibilityChange`. If a remote is missing or the wrong class, the server logs a warning and the
hologram UI disables itself rather than hanging or crashing the rest of the backend.
