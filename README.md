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
│   └── Oathbound/
│       └── Config.lua                              # shared config (roll tables, costs, store name)
├── ServerScriptService/
│   └── Oathbound/
│       ├── Main.server.lua                         # server entry point (bootstrap + remotes)
│       ├── DataService.lua                         # DataStore load/save/kick-on-failure
│       └── RollService.lua                         # weighted rolls + protected-rarity checks
└── StarterPlayer/
    └── StarterCharacterScripts/
        └── OathboundTest.client.lua                # throwaway test harness (delete before release)
```

### Filename convention

The suffix tells you **which class to create in Studio**. This is not enforced by any tool — it is
just a reminder, and picking the wrong class is the most common way this backend breaks:

| Suffix | Studio class |
|---|---|
| `.lua` | **ModuleScript** |
| `.server.lua` | **Script** |
| `.client.lua` | **LocalScript** |

## Install in Roblox Studio

Create each folder/script below, then paste the matching file's contents into it.

| Parent | Create | Class | Name | Paste from |
|---|---|---|---|---|
| `ReplicatedStorage` | Folder | `Folder` | `Oathbound` | — |
| `ReplicatedStorage.Oathbound` | Script | **`ModuleScript`** | `Config` | `OathboundBackend/ReplicatedStorage/Oathbound/Config.lua` |
| `ServerScriptService` | Folder | `Folder` | `Oathbound` | — |
| `ServerScriptService.Oathbound` | Script | **`Script`** | `Main` | `OathboundBackend/ServerScriptService/Oathbound/Main.server.lua` |
| `ServerScriptService.Oathbound` | Script | **`ModuleScript`** | `DataService` | `OathboundBackend/ServerScriptService/Oathbound/DataService.lua` |
| `ServerScriptService.Oathbound` | Script | **`ModuleScript`** | `RollService` | `OathboundBackend/ServerScriptService/Oathbound/RollService.lua` |
| `StarterPlayer.StarterCharacterScripts` | Script | **`LocalScript`** | `OathboundTest` | `OathboundBackend/StarterPlayer/StarterCharacterScripts/OathboundTest.client.lua` |

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
