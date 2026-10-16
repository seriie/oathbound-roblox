# Oathbound (Roblox)

Server-authoritative reroll/economy backend for the Oathbound experience: first-join rolls,
weighted result tables, Gold Veyra rerolls, rare-result confirmation, storage unlock/store/swap,
DataStore persistence, and a Developer Product receipt handler.

There is **no build tooling**. These files are the source of truth; you copy them into Roblox
Studio by hand. See [Install in Roblox Studio](#install-in-roblox-studio).

## Contents

```
OathboundBackend/
├── ReplicatedStorage/
│   ├── Oathbound/
│   │   └── Config.lua                              # shared config (roll tables, costs, store name)
│   └── OathboundHologram/
│       ├── HologramConfig.lua                      # hologram artwork IDs, layout, behavior, security
│       ├── RequestAction                           # RemoteFunction  (Studio instance -- see Install)
│       ├── SetVisibility                           # RemoteFunction  (Studio instance -- see Install)
│       ├── UpdatePosition                          # RemoteEvent     (Studio instance -- see Install)
│       └── VisibilityChanged                       # RemoteEvent     (Studio instance -- see Install)
├── ServerScriptService/
│   └── Oathbound/
│       ├── Main.server.lua                         # server entry point (bootstrap + remotes)
│       ├── ActionService.lua                       # shared gameplay handler reused by both remotes
│       ├── DataService.lua                         # DataStore load/save/kick-on-failure
│       ├── RollService.lua                         # weighted rolls + protected-rarity checks
│       └── OathboundHologramServer.lua             # hologram visibility/position authority
└── StarterPlayer/
    ├── StarterCharacterScripts/
    │   └── OathboundTest.client.lua                # throwaway test harness (delete before release)
    └── StarterPlayerScripts/
        └── OathboundHologram.client.lua            # 3D hologram renderer + ImageButton input
```

### Filename convention

The suffix tells you **which class to create in Studio**. This is not enforced by any tool — it is
just a reminder, and picking the wrong class is the most common way this backend breaks:

| Suffix | Studio class |
|---|---|
| `.lua` | **ModuleScript** |
| `.server.lua` | **Script** |
| `.client.lua` | **LocalScript** |

The suffix is only a hint. Every Lua file also starts with an authoritative marker line:

```lua
-- Roblox class: ModuleScript | name: HologramConfig | parent: ReplicatedStorage.OathboundHologram
```

Use that line to decide what to create in Studio. It is the source of truth — for example,
`RequestAction.lua` uses the `.lua` suffix but its marker says `RemoteFunction`, because it is a
placeholder for an **Instance**, not a ModuleScript.

## Install in Roblox Studio

Create each folder/script below, then paste the matching file's contents into it.

| Parent | Create | Class | Name | Paste from |
|---|---|---|---|---|
| `ReplicatedStorage` | Folder | `Folder` | `Oathbound` | — |
| `ReplicatedStorage.Oathbound` | Script | **`ModuleScript`** | `Config` | `OathboundBackend/ReplicatedStorage/Oathbound/Config.lua` |
| `ReplicatedStorage` | Folder | `Folder` | `OathboundHologram` | — |
| `ReplicatedStorage.OathboundHologram` | Script | **`ModuleScript`** | `HologramConfig` | `OathboundBackend/ReplicatedStorage/OathboundHologram/HologramConfig.lua` |
| `ReplicatedStorage.OathboundHologram` | Object | **`RemoteFunction`** | `RequestAction` | — (Studio instance) |
| `ReplicatedStorage.OathboundHologram` | Object | **`RemoteFunction`** | `SetVisibility` | — (Studio instance) |
| `ReplicatedStorage.OathboundHologram` | Object | **`RemoteEvent`** | `UpdatePosition` | — (Studio instance) |
| `ReplicatedStorage.OathboundHologram` | Object | **`RemoteEvent`** | `VisibilityChanged` | — (Studio instance) |
| `ServerScriptService` | Folder | `Folder` | `Oathbound` | — |
| `ServerScriptService.Oathbound` | Script | **`Script`** | `Main` | `OathboundBackend/ServerScriptService/Oathbound/Main.server.lua` |
| `ServerScriptService.Oathbound` | Script | **`ModuleScript`** | `DataService` | `OathboundBackend/ServerScriptService/Oathbound/DataService.lua` |
| `ServerScriptService.Oathbound` | Script | **`ModuleScript`** | `RollService` | `OathboundBackend/ServerScriptService/Oathbound/RollService.lua` |
| `ServerScriptService.Oathbound` | Script | **`ModuleScript`** | `ActionService` | `OathboundBackend/ServerScriptService/Oathbound/ActionService.lua` |
| `ServerScriptService.Oathbound` | Script | **`ModuleScript`** | `OathboundHologramServer` | `OathboundBackend/ServerScriptService/Oathbound/OathboundHologramServer.lua` |
| `StarterPlayer.StarterCharacterScripts` | Script | **`LocalScript`** | `OathboundTest` | `OathboundBackend/StarterPlayer/StarterCharacterScripts/OathboundTest.client.lua` |
| `StarterPlayer.StarterPlayerScripts` | Script | **`LocalScript`** | `OathboundHologram` | `OathboundBackend/StarterPlayer/StarterPlayerScripts/OathboundHologram.client.lua` |

The four `OathboundHologram` remotes are **instances, not scripts** — create them with
right-click → Insert Object. Their names must match exactly (`VisibilityChanged`, not
`VisibilityChange`) or the hologram will disable itself with a warning.

Tip: use **right-click → Insert from File…** and pick the class in the dialog, rather than
Insert Object, which defaults to `Script`.

### Why the class matters

`require()` only accepts a **ModuleScript**. If `Config`, `DataService` or `RollService` is created
as a plain `Script`, you get:

```
... module is not a module script
```

and nothing loads. `Main` is the opposite: it must be a **Script**, because it is the entry point
that Studio runs automatically. A ModuleScript there would never execute.

Everything is wired by fixed paths, so the **names and hierarchy above are not optional**:

- `DataService.lua` and `RollService.lua` require `ReplicatedStorage.Oathbound.Config`
- `Main.server.lua` requires `script.Parent.DataService` and `script.Parent.RollService`

## Configure

Edit `Config`:

1. `Config.DataStoreName` — defaults to `Oathbound_PlayerData_v1`. Use a different name for a test
   experience so dev data never touches production.
2. `Config.StartingGoldVeyra` — currently `0`.
3. `Config.RollTypes[*].DeveloperProductId` and `.Storage.DeveloperProductId` — all `0` placeholders.
   Create the Developer Products in the Creator Dashboard and paste the real IDs here. While an ID
   is `0`, the server returns `DeveloperProductNotConfigured` instead of prompting a purchase.
4. `Config.GoldPacks` — the only way players earn Gold Veyra. Each pack has a
   `DeveloperProductId = 0` placeholder and an `Amount`. Until these are configured, gold is
   unobtainable in a live game and every `RerollGold`/`BuyStorage("Gold")` call fails.
5. `Config.DevGoldAmount` — amount granted by the Studio-only `DevGrantGold` request.
6. Result weights and `ProtectedRarities` — rare results require an explicit client confirmation
   before they can be rerolled.

Robux prices are set in the Creator Dashboard, not in code. `Config.DisplayRobuxPrices` is display
metadata only.

### Gold Veyra

Gold only ever enters the economy server-side, from two places: a `GoldPacks` Developer Product
receipt, or the Studio-only `DevGrantGold` request. Nothing accepts a gold amount from a client.

`DevGrantGold` is gated on `RunService:IsStudio()`, which is `false` on every published server, so
the branch is unreachable in production regardless of what a client sends. Do not replace that check
with a client-supplied flag.

## Client contract

At startup the server creates, under `ReplicatedStorage.Oathbound`:

- `Request` — `RemoteFunction`
- `StateChanged` — `RemoteEvent`

Client calls (all invoked on `Request`):

```lua
Request:InvokeServer("GetState")
Request:InvokeServer("RerollGold", "Bloodline")                 -- returns confirmRequired when protected
Request:InvokeServer("RerollGold", "Bloodline", true)           -- confirmed reroll
Request:InvokeServer("RerollRobux", "Race", true)               -- returns promptProductId
Request:InvokeServer("BuyStorage", "Bloodline", "Gold")
Request:InvokeServer("BuyStorage", "Bloodline", "Robux")        -- returns promptProductId
Request:InvokeServer("StoreActive", "Bloodline")
Request:InvokeServer("SwapStored", "Bloodline", 1)
Request:InvokeServer("BuyGold", "Pouch")                        -- returns promptProductId
Request:InvokeServer("DevGrantGold")                            -- Studio only; grants Config.DevGoldAmount
```

`kind` is one of `Bloodline`, `Race`, `Affinity`.

If a response contains `confirmRequired = true`, show a dialog using `current`, then re-invoke with
`true` as the last argument. If it contains `promptProductId`, call
`MarketplaceService:PromptProductPurchase(player, productId)`.

Server pushes state changes on `StateChanged:FireClient(player, state)` with
`{ GoldVeyra, Active, Storage }`.

**Never accept a result, price, rarity, Gold balance or purchase-success flag from the client.**
The server chooses every result and cost.

## Hologram UI

An image-driven 3D hologram that floats in front of the owning player's camera, in the style of
a "System" interface. **Your artwork is the UI**: the panel is one `ImageLabel` and every button
is a separate `ImageButton`, all driven by `HologramConfig`. No frame/button/border/label artwork
is drawn in code.

### Architecture

- The hologram is a client-local (non-replicated) `Part` in `workspace` with a `SurfaceGui`.
- The owner's `SurfaceGui` is parented to `PlayerGui` with `Adornee` = the part and the part's
  `CanQuery = true`. Roblox only delivers input to a `SurfaceGui` that is in `PlayerGui` and whose
  adornee has `CanQuery = true` — that is why the part is not `CanQuery = false` like a purely
  decorative part would be.
- Other players' holograms are built locally by each viewer, view-only (`Active = false`,
  `CanQuery = false`), so a viewer can never click someone else's interface.
- The owner moves its own part every frame from its camera and reports the transform on
  `UpdatePosition`. The server validates it and relays it to everyone else on `VisibilityChanged`.
- Owners never receive position events about themselves; their hologram is driven locally.

### Assigning your artwork (required)

Open `ReplicatedStorage.OathboundHologram.HologramConfig` and replace each `"rbxassetid://0"`:

1. `Panel.Image` — your main hologram panel. **Required.**
2. `Panel.DesignSize` — the panel PNG's real pixel size (e.g. `Vector2.new(2048, 1152)`). This
   sets the 3D part's aspect ratio, so nothing is stretched.
3. `Buttons[*].Image` — one entry per button. `Buttons[*].Position` / `.Size` are normalized
   (`UDim2.fromScale`) so hitboxes track the artwork. **Match each rectangle to the button art and
   do not overlap neighbours.**
4. `Buttons[*].HoverImage` / `.PressedImage` / `SelectedImage` and the visibility button's
   `StateImages` — optional, for hover/press/selection/mode feedback. Leave `nil` to skip.
5. `Decorations` — optional extra `ImageLabel`s (glows, flourishes).
6. `Panels.Race` / `.Affinity` / `.Bloodline` / `.Confirm` — optional interface art. Until
   assigned, the matching button reports **"not implemented yet"** in the output instead of faking
   it.

The client warns clearly for each unassigned asset. Nothing is auto-generated as a stand-in.

### Visibility & controls

| Mode | Effect |
|---|---|
| `Public` | Everyone sees it, at the owner's reported transform. |
| `Private` | Only the owner sees it. The position is **never** sent to anyone else. |
| `Hidden` | Not rendered, for anyone. |

- The Visibility `ImageButton` cycles `Public -> Private -> Hidden -> Public`.
- Keybinds (desktop): `V` cycles visibility, `H` toggles open/close. These work even while the
  hologram is Hidden or closed, when the panel itself is not clickable.
- Defaults live in `HologramConfig.Behavior.DefaultVisibility` / `.OpenByDefault`.

### Multiplayer testing (Studio)

1. **Test → Clients and Servers → 2 Players** (or more).
2. Player 1 keeps visibility `Public` and moves/turns; the hologram should follow P1's camera and
   P2 should see it in the same place, following P1's view — not attached to P2's camera.
3. On P2, try clicking P1's hologram: nothing happens (their buttons are non-interactive).
4. On P1, press `V` to switch to `Private`: P2's copy disappears; P1 still sees and can click its
   own.
5. Press `V` again (`Hidden`): nobody sees it.
6. Press `V` to return to `Public`, move P1, and confirm P2 sees it again.
7. Kill P1 (with `HideWhenDead = true`): the hologram should disappear for P2 until P1 respawns.

### Server authority

`OathboundHologramServer` only tracks who-may-see-what and validates the reported transform
(type, rate, distance from the owner's `HumanoidRootPart`). Every gameplay button routes through
`RequestAction` → `ActionService` → `Main.server.lua`'s existing handler, so there is exactly one
roll system, one currency check and one set of rules. The server never trusts a client-supplied
owner id, result, price or balance.

### Known limitations

- A `SurfaceGui` only accepts input while its adornee has `CanQuery = true`. While the hologram is
  open, the panel is therefore hit by mouse raycasts along with the world. It stays non-solid
  (no collision) and camera look/drag still works; this is a Roblox input requirement, not a bug.
- Un-hiding a Hidden hologram is keyboard-only (`V`) because "Hidden" means *not rendered*, so
  there is no on-screen control to click. Touch users need an external settings control (e.g. a
  `ScreenGui` button that calls the same `SetVisibility` remote).
- Position is relayed at `Behavior.UpdateRate` (default 12/s) with server-side smoothing off by
  default; raise it if you want tighter remote tracking at some network cost.

## Testing checklist

1. Publish the place — an unpublished local place has no DataStore backing at all.
2. **Home → Game Settings → Security → Enable Studio Access to API Services → ON.**
3. Start a fresh play session (the toggle does not apply to an already-running session).
4. Test in a **separate test experience** and use a distinct `DataStoreName`.

If enabling API access is missed, `DataService` logs
`[Oathbound] Data load failed for <name> (<id>) after retries: ...` and kicks the player with
`Your data could not be loaded safely. Please rejoin in a moment.` The log line names the real cause.

`DataStore request was added to queue` is a benign throttle notice, not a failure.

## Implementation notes

- This is a **starter**, not production economy code. Before launch, harden `DataService` with
  session locking/reconciliation — the current save has no cross-server protection.
- First-join rolls are assigned server-side only when the saved `Active` value is `nil`, then persisted.
- Gold Veyra is only ever added by `grantGold`, which is called from the `GoldPacks` receipt path and
  the Studio-only `DevGrantGold` request. `Config.StartingGoldVeyra` is `0`, so a fresh player cannot
  reroll or buy storage until a gold product is configured or the dev grant is used.
- Storage is a single slot per kind after unlock. `StoreActive` copies the active result into storage;
  `SwapStored` exchanges the stored result with the active one.
- Developer Product receipts rely on in-memory pending intent, which is lost if the server shuts down
  between the prompt and the receipt. `ProcessReceipt` refuses unmatched receipts rather than granting
  blind. Implement persistent intent/receipt reconciliation before launch.
- `OathboundTest.client.lua` is a debug harness: it runs on **every character respawn**. Delete the
  `OathboundTest` LocalScript before publishing.
- The hologram's gameplay buttons route through `RequestAction` → `ActionService` → `Main`'s own
  handler. `ActionService` is a thin seam that `Main.server.lua` binds at startup; it holds no
  economy logic of its own, so there is still a single roll/currency/DataStore path.
