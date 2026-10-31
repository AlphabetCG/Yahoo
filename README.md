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
| **Play flow** | **PLAY** → Select **Mode** (Story / Infinite / Challenge / Raid) → **Map** → **Stage** → **Create Lobby** (Public / Friends / Invite only) or **Matchmaking** → lobby room: the host invites players and presses **START**. Invites pop up for the invited player. Story stages unlock in order (clear Stage 1 to open Stage 2). |
| **Match flow** | **Prep** phase (60 s, or the host presses START MATCH) → the stage's rounds (or endless in Infinite) → Victory / Game Over → Retry (same stage, same players) or Main Menu. |
| **Stages** | `Config.Stages`: mode, map, difficulty (Normal / Hard / Nightmare: enemy health, speed and reward multipliers), rounds (0 = endless) and rules (faster / tougher enemies, start money, allowed rarities, a boss every N rounds, Raid escorts). 1 map for now (`Config.Maps`). |
| **Waves** | Enemy count = `6 + 3.2 × round` (54 in round 15). Each enemy spawns as tier 1–5, which fixes its speed and base HP; health grows 9 % per round. Its color steps down through the tiers as it loses health. Enemies walk the path center in single file, keeping `EnemySpacing` studs apart: a faster enemy queues behind a slower one instead of overlapping it. Bosses (200 HP × the stage's boss multiplier) close the last round, or every N rounds in Infinite / Raid; each later boss is 40 % tougher. |
| **Auto Skip** | **ON**: the next round starts once 60–70 % of the current wave has spawned. **OFF**: no timer while the wave spawns (the HUD shows `WAVE r  x/y`); after the last enemy appears, a 20 s timer starts and the next round begins when it runs out or every enemy is gone. The match follows the host's setting. |
| **Game speed** | x1 / x2 / x3 for everyone. The stage timer runs in real time. |
| **Units** | **Herobrine** (Rare), **Zaruto**, **Fluffy**, **Ichitoe** (Epic) and **Voidseer** (Legendary). Each has 5 in-match **Upgrade** levels (UPGRADE buys one, MAX buys as many as you can afford; units show `UP1`–`UP5`). The last levels add an ability: Burn (damage over time) or Slow. 6 targeting modes (First / Last / Strongest / Weakest / Closest / None), selling at a 50 % refund. Each player can have up to 3 copies of each unit on the map (`DefaultPlaceLimit`; a unit can set its own `PlaceLimit`). |
| **Money** | Per player, but **shared income**: every whole HP removed (`RewardPerPop` 2, burn included) and every round bonus (160, +30 per round) pays **every** player in the match the same amount, scaled by party size (`Config.TeamIncome`: 1.0 / 0.65 / 0.5 / 0.42). A solo full clear earns about 13,200. `Config.DebugEconomy` prints income by source at stage end. |
| **Saved profile** | Gems, Gold, owned units (one record per unit: id, level, XP, trait, lock), items, settings and lifetime stats. Kept in a DataStore with a session lock, autosave, retries and versioned migrations. |
| **Rewards** | Gems, Wisp Essence and Void Crystal at stage end, based on result, round reached, kills and whether the boss died. Every equipped unit also gets XP (`20 + 4 × round`, doubled on a clear). |
| **Summon** | 100 Gems per roll from a weighted pool (Rare 71 % / Epic 24 % / Legendary 5 %). The first copy of a new unit is equipped automatically if a loadout slot is free. |
| **Inventory & loadout** | **Loadout** of 6 slots: only equipped units appear in the in-match shop (keys 1–6). **Units** tab: one card per copy, sortable (rarity / level / newest) and filterable by rarity; a detail panel to equip / unequip, feed Wisp Essence, lock, and sell for **Gold** (Rare 5 · Epic 15 · Legendary 40; locked and equipped units can't be sold). Gold is a separate currency with no use yet (#50). **Materials** tab. |
| **Unit leveling** | Each copy has a saved level (cap by rarity: Rare 30, Epic 40, Legendary 50, Mythic 60). +3 % damage and +0.1 range per level. XP from stages and from feeding Wisp Essence (10 XP each). Separate from in-match upgrades. |
| **Settings** | Auto Skip, health bars (hover / always), resume, surrender. |
| **Party, host & votes** | One server = one match for up to 4 players (`Config.MaxPartySize`); the main menu shows the party. The player in the server longest is the **host**: only the host starts the stage, starts the match early, sets the **speed**, retries and returns to the menu. **Votes**: Auto Skip (each player sets their own in Settings, ON by default; the match uses the majority, ties → host), Skip Wave and Surrender (everyone; solo = instant). Every player has a **colour** (`Config.PlayerColors`): their units are outlined in it and it shows in the party panel. Players who join mid-stage spectate and join at the next round with the team's money. Enemy HP +35 % per extra player. A player who leaves takes their units with them. |
| **Rendering** | Pixel map with path, cave and castle. Sprites with idle and recoil animations, health bars, shot bolts and particles, a placement ghost with a range ring, mouse-wheel zoom, and panning (right/middle-drag, WASD or arrow keys, one-finger drag on touch; `C` re-centers). |

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
    Lobby.luau                Lobby rooms: privacy, invites, matchmaking, start
  StarterPlayer/StarterPlayerScripts/
    ClientMain.client.luau    All UI: menu, HUD, shop, upgrade panel, settings, inventory, result screen, input
    PlayMenu.luau             PLAY flow UI: mode > map > stage > lobby room, invite popups
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
| `Voters`, `AutoSkipVotes`, `SkipVotes`, `SurrenderVotes` | Vote totals for the HUD. Each player's own vote is a player attribute (`VoteAutoSkip`, `VoteSkip`, `VoteSurrender`); `InMatch` marks the players in the stage; `PlayerColor` is their colour index |
| `WaveState`, `WaveSpawned`, `WaveCount` | `Spawning` · `Clearing` (Auto Skip OFF timer) · `""`, plus spawn progress of the current wave |

Other state lives on other objects:

- **Per-player money:** the `Money` attribute on each `Player`.
- **Enemies:** invisible ball parts in `workspace.Enemies` with the attributes `Tier`, `Health`, `MaxHealth`, `Boss`, `Born` and `Status` (`Burn` · `Slow` · `BurnSlow` · empty).
- **Units:** invisible models in `workspace.Towers` with the attributes `UnitName`, `UnitId`, `Level`, `OwnerId`, `Targeting` and `Spent`.

### Remotes (`ReplicatedStorage.Remotes`, created at runtime)
| Remote | Kind | Purpose |
|---|---|---|
| `BeginMatch`, `Retry`, `ReturnToMenu` | Event | Match flow (host only) |
| `LobbyCreate`, `LobbyJoin`, `LobbyMatchmake`, `LobbyInvite`, `LobbyStart` | Function | Lobby rooms (server module `Lobby`) |
| `LobbyLeave`, `LobbySetPrivacy`, `LobbyRefresh` / `LobbyState`, `LobbyInvited` | Event | Lobby rooms: requests / what each client sees |
| `Surrender`, `SkipWave` | Event | Votes (toggle); pass when every player in the match agrees |
| `SetSpeed`, `SetAutoSkip`, `SetTargeting` | Event | Speed: host only. Auto Skip: the player's own choice (majority decides). Targeting: per unit |
| `PlaceTower(unitId, pos)`, `UpgradeTower(model, all)`, `SellTower` | Function | Unit actions (validated on the server). `unitId` is a key of `profile.Units`; `all = true` buys as many upgrade levels as affordable |
| `Shot` | UnreliableEvent | Tells clients to draw a shot |
| `GetProfile`, `Summon` | Function | Profile data |
| `EquipUnit(uid, slot)`, `LockUnit(uid, locked)`, `SellUnits({uid})`, `FeedUnit(uid, amount)` | Function | Inventory actions (refused during a stage) |
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

## Two places: Lobby and Match

The experience has two places, and **both run the same project** (`default.project.json`); the scripts check `game.PlaceId` to know where they are.

| Place | PlaceId | What runs there |
|---|---|---|
| **Lobby** (start place) | the start place | Main menu, inventory, summon, PLAY flow and lobby rooms. START teleports the room to its own reserved Match server |
| **Match** ("2nd place") | `Config.Places.Match` = 138398273175866 | No menu: waits for the room's players (max 20 s), plays the stage from the TeleportData, then **BACK TO LOBBY** sends each player back |

**Publishing a change:**
1. Open the **Lobby** place in Studio, connect Rojo, then **File → Publish to Roblox**.
2. Open the **Match** place (Asset Manager → Places → 2nd place), connect Rojo to the same project, then **Publish** again.
3. Test teleports in the live game (or a private server): Studio can't teleport.

**In Studio:**
- **Lobby place:** a lobby room's START plays the stage in the same server, so the whole flow can be tested.
- **Match place opened directly:** it starts Story Stage 1 with everyone who joined within 3 s.
- **No teleports at all:** set `Config.Places.Match = 0` to play every stage inside the lobby server.

## Tweaking the game

Nearly everything is in [Config.luau](src/ReplicatedStorage/Config.luau):

- **New unit:** add a sprite to `PixelArt` (`defs.<Name>`) and an entry to `Config.Units`. Then add it to `Config.UnitOrder` to show it in the shop, and to `Config.Summon.Pool` to make it summonable.
- **Unit image instead of pixel grid:** add `Image = { Id, Size, FrameSize, Frames }` to the unit in `Config.Units` (format described above `Config.UnitOrder`). As soon as `Id` is set, the map, shop, inventory and placement preview use the image. Leave `Id = ""` to keep the pixel grid. A unit with neither an image nor a grid shows a grey "?" placeholder.
  1. Draw the character facing **right** on a transparent PNG. For a sprite sheet, put the frames side by side, all the same size (e.g. idle, then attack).
  2. Upload it in Studio: **View → Asset Manager → Bulk Import** (or the Creator Dashboard → Development Items → Images).
  3. Right-click the image → **Copy Asset ID** and paste it as `Id = "rbxassetid://<number>"`. Use the *image* id, not a decal id.
  4. Set `Size` (on-screen size in art pixels, around 14–20 × 18–24 to match the other units) and `FrameSize` (the size of one frame in the file, ideally an exact multiple of `Size`).
- **New material:** add it to `Config.Materials` and `Config.MaterialOrder`. Grant it with `PlayerData.AddMaterial(player, key, n)`.
- **Waves and economy:** `EnemiesBase`, `EnemiesPerRound`, `HpPerRound`, `WaveClearTime`, `EnemySpacing`, `RewardPerPop`, `RoundBonus`, `StartMoney`, `DefaultPlaceLimit`, and `Tiers[*].Speed` / `HP`.
- **Upgrade abilities:** add `Ability = { Kind = "Burn", Dps, Duration }` or `{ Kind = "Slow", Pct, Duration }` to a `Levels[i]` entry.
- **Unit leveling:** `Config.Leveling` (XP per stage, XP per Essence, damage / range per level), `Config.XpToNext(level)`, level caps in `Config.Rarities[*].MaxLevel`.
- **Path:** move or add the `Workspace.Waypoints` parts, which are numbered in order.

---

## Known limitations

These are all covered in the spec:

- **Teleports only work in the published game.** In Studio a lobby room plays its stage inside the same server.
- **Little content.** There are five units, one enemy type plus the boss, and one map.
- **x3 speed is free.** It is planned as a gamepass perk.
