# YAHOO — Anime Tower Defense (Roblox)

A pixel-art tower defense game for Roblox. Players place **units** beside a path. Waves of **wisps** walk toward the castle, and the stage ends with a boss, the **Wisp King**. Between stages, players spend **Gems** to summon units and collect **materials** for future upgrade systems.

The whole world is drawn as 2D pixel art on a GUI layer, built from plain colored `Frame`s with no uploaded images. The server simulates everything with invisible parts and attributes, and each client draws what it sees.

> The roadmap and the full feature specification live in **[SPECIFICATION.md](SPECIFICATION.md)**.

---

## Getting started

Tooling is managed by [Rokit](https://github.com/rojo-rbx/rokit) (see [rokit.toml](rokit.toml)), and the project uses Rojo 7.7.1.

```sh
rokit install      # installs rojo
rojo serve         # serves default.project.json
```

Then open the place in Roblox Studio and click **Connect** in the Rojo plugin.

- **API access:** To test saving in Studio, turn on *Game Settings → Security → Enable Studio Access to API Services*. If it's off, the DataStore calls fail and the game runs on default data without saving. This is intended behaviour.
- **Syncback:** The repo was imported from the live place with `rojo syncback`, so `.rbxm` files (waypoints, terrain, baseplate, tower models) are binary. Edit them in Studio and sync back.

---

## Current features

| Area | What exists today |
|---|---|
| **Match flow** | Menu → **Prep** phase (60 s, or press START MATCH) → **15 rounds** → Victory / Game Over. Retry, Main Menu and Surrender (with confirmation). |
| **Waves** | Enemy count = `6 + 3.2 × round` (54 in round 15). Each enemy spawns as tier 1–5, which fixes its speed and base HP; health grows 9 % per round. Its color steps down through the tiers as it loses health. Enemies walk the path center in single file, keeping `EnemySpacing` studs apart: a faster enemy queues behind a slower one instead of overlapping it. The boss closes round 15 with 200 HP. |
| **Auto Skip** | **ON**: the next round starts once 60–70 % of the current wave has spawned. **OFF**: no timer while the wave spawns (the HUD shows `WAVE r  x/y`); after the last enemy appears, a 20 s timer starts and the next round begins when it runs out or every enemy is gone. The match follows the host's setting. |
| **Game speed** | x1 / x2 / x3 for everyone. The stage timer runs in real time. |
| **Units** | **Herobrine** (Rare) and **Voidseer** (Legendary, max 2 on the map). Each has 5 **Refine** levels (in-match upgrades; REFINE buys one, MAX buys as many as you can afford). The last levels add an ability: Burn (damage over time) or Slow. 6 targeting modes (First / Last / Strongest / Weakest / Closest / None), selling at a 50 % refund. Up to 8 units per player on the map. |
| **Money** | Per player, earned per whole HP removed (`RewardPerPop` 2, burn damage included) plus a round bonus for everyone (160, +30 per round). A solo full clear earns about 13,200. Turn on `Config.DebugEconomy` to print income by source at stage end. |
| **Saved profile** | Gems, owned units (one record per unit: id, level, XP, trait, lock), items, settings and lifetime stats. Kept in a DataStore with a session lock, autosave, retries and versioned migrations. |
| **Rewards** | Gems, Wisp Essence and Void Crystal at stage end, based on result, round reached, kills and whether the boss died. |
| **Summon** | 100 Gems per roll from a weighted pool. The pool currently holds only Herobrine. |
| **Inventory UI** | Two tabs: Units (owned / locked) and Materials. |
| **Settings** | Auto Skip, health bars (hover / always), resume, surrender. |
| **Host** | The player who has been in the server longest is the host. Only the host can start, retry, return to menu, surrender, or change speed and Auto Skip. |
| **Rendering** | Pixel map with path, cave and castle. Sprites with idle and recoil animations, health bars, shot bolts and particles, a placement ghost with a range ring, and mouse-wheel zoom. |

---

## Project layout

```
default.project.json          Rojo tree (maps src/* to Roblox services)
src/
  ReplicatedStorage/
    Config.luau               ALL tunable numbers: economy, waves, units, tiers, boss, rewards, summon
                              + path helpers (GetPath, DistanceToPath, CanPlace)
    PixelArt.luau             Sprite definitions (Herobrine, Wisp, Arrow) + Frame-based renderer
    WorldView.luau            Client-side 2D world renderer (map, enemies, units, shots, ghost, zoom)
  ServerScriptService/
    GameServer.server.luau    Authoritative game loop: rounds, spawning, movement, targeting, damage,
                              money, lives, place/upgrade/sell, remotes
    PlayerData.luau           DataStore profiles (v2 + migrations, session lock), rewards, summon, settings
    RateLimit.luau            Per-player, per-remote request limits
  StarterPlayer/StarterPlayerScripts/
    ClientMain.client.luau    All UI: menu, HUD, shop, upgrade panel, settings, inventory, result screen, input
  ServerStorage/
    Eclipse Animator Saves/   Plugin data (not game code)
  Workspace/
    Waypoints/1..10           The enemy path. Move these parts in Studio to reshape it
    Towers/, Enemies/         Runtime folders filled by the server
```

---

## How it works

### Server authority
`GameServer` owns all game state. Clients only send requests through remotes and read state from attributes.

**Match state** is stored as attributes on `workspace`:

| Attribute | Meaning |
|---|---|
| `State` | `Menu` · `Playing` · `GameOver` · `Victory` |
| `Phase` | `Menu` · `Prep` · `Match` |
| `Round`, `Lives`, `Countdown`, `PrepLeft` | Round and HUD values |
| `GameSpeed`, `AutoSkip` | Match settings |
| `StageTime`, `StageSync` | Stage clock. The client extrapolates between syncs |
| `EndReason` | `Clear` · `Defeat` · `Surrender` |
| `HostId` | UserId of the host (the player who controls the match flow) |
| `WaveState`, `WaveSpawned`, `WaveCount` | `Spawning` · `Clearing` (Auto Skip OFF timer) · `""`, plus spawn progress of the current wave |

Other state lives on other objects:

- **Per-player money:** the `Money` attribute on each `Player`.
- **Enemies:** invisible ball parts in `workspace.Enemies` with the attributes `Tier`, `Health`, `MaxHealth`, `Boss`, `Born` and `Status` (`Burn` · `Slow` · `BurnSlow` · empty).
- **Units:** invisible models in `workspace.Towers` with the attributes `UnitName`, `UnitId`, `Level`, `OwnerId`, `Targeting` and `Spent`.

### Remotes (`ReplicatedStorage.Remotes`, created at runtime)
| Remote | Kind | Purpose |
|---|---|---|
| `StartGame`, `BeginMatch`, `Retry`, `ReturnToMenu`, `Surrender` | Event | Match flow (host only) |
| `SetSpeed`, `SetAutoSkip`, `SetTargeting` | Event | Match and unit settings (speed / Auto Skip: host only) |
| `PlaceTower(unitId, pos)`, `UpgradeTower(model, all)`, `SellTower` | Function | Unit actions (validated on the server). `unitId` is a key of `profile.Units`; `all = true` refines as many levels as affordable |
| `Shot` | UnreliableEvent | Tells clients to draw a shot |
| `GetProfile`, `Summon` | Function | Profile data |
| `ProfileUpdated`, `StageRewards`, `SetSetting` | Event | Profile data |

### Timing
- **Game time:** `gameTime` speeds up with x2 / x3. Spawning, cooldowns and round countdowns all use game time.
- **Real time:** the prep countdown, the stage timer and shot travel (`ShotTravel`) use real time.
- **Hit timing:** damage lands when the shot arrives. Enemies track `Pending` damage so units don't overkill.

### Saving
`PlayerData` stores one table under `Player_<UserId>` in the DataStore `PlayerData_v1`. The layout is described at the top of [PlayerData.luau](src/ServerScriptService/PlayerData.luau).

- **Versions:** the profile has a `Version`. Old saves are upgraded on load by `MIGRATIONS[oldVersion]` (v1 copy counts → v2 unit records). To change the layout, bump `PROFILE_VERSION` and add a migration.
- **Session lock:** the saved copy holds `Lock = { JobId, Time }`. A server only loads a profile when no other live server holds it, and it waits up to 30 s for the other server to let go. Locks older than 180 s are treated as stale. In Studio, locks from earlier Studio play-tests are ignored.
- **Saving:** at most once every 7 s, and every 60 s for every loaded profile (which also refreshes the lock). The lock is released when the player leaves and on `BindToClose`.
- **Failures:** if loading fails or the profile stays locked, the player plays on default data and their real save is never overwritten.

---

## Tweaking the game

Nearly everything is in [Config.luau](src/ReplicatedStorage/Config.luau):

- **New unit:** add a sprite to `PixelArt` (`defs.<Name>`) and an entry to `Config.Units`. Then add it to `Config.UnitOrder` to show it in the shop, and to `Config.Summon.Pool` to make it summonable.
- **New material:** add it to `Config.Materials` and `Config.MaterialOrder`. Grant it with `PlayerData.AddMaterial(player, key, n)`.
- **Waves and economy:** `EnemiesBase`, `EnemiesPerRound`, `HpPerRound`, `WaveClearTime`, `EnemySpacing`, `RewardPerPop`, `RoundBonus`, `StartMoney`, `MaxPlacedPerPlayer`, and `Tiers[*].Speed` / `HP`.
- **Refine abilities:** add `Ability = { Kind = "Burn", Dps, Duration }` or `{ Kind = "Slow", Pct, Duration }` to a `Levels[i]` entry.
- **Path:** move or add the `Workspace.Waypoints` parts, which are numbered in order.

---

## Known limitations

These are all covered in the spec:

- **One match per server.** Everyone in the server shares one match, and the host controls it. There's no party, lobby or voting yet.
- **The shop picks the unit copy.** Until the loadout exists, placing a unit uses your highest-level copy of it.
- **Little content.** There is one unit, one enemy type plus the boss, and one map.
- **x3 speed is free.** It is planned as a gamepass perk.
