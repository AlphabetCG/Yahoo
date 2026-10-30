# YAHOO — Feature Specification & Roadmap

This document lists what to build next. Each feature is mapped to the current code. Each entry gives:
- **Now:** what the code does today.
- **Goal:** what we want.
- **Spec:** how to build it.
- **Done when:** the acceptance check.
- **Open questions:** decisions still needed from the team.

The numbers below are starting values. All of them belong in `Config` so we can tune them without code changes.

> **Source list:** Core Gameplay (Units Leveling, Units Upgrade In Match (Refine), Reforging Units + maybe Equipment/Artifacts, Inventory System, Stage Economy Nerf, Multiplayer, Auto Skip Off rework, enemy overlap), Money (Banner, Guaranteed Reforge, Limited Units, Gamepasses, Starter Pack), Additional (Codes, Daily Rewards).

---

## 0. Roadmap at a glance

Several requested features depend on foundations that don't exist yet. The order below avoids building things twice.

| Phase | Contents | Why this order |
|---|---|---|
| **P0 — Foundations** | Profile v2 + migration, session locking, unit *instances*, rarity, remote authority, cleanup | Leveling, reforging, inventory, banners and purchases all need per-unit data and safe saving |
| **P1 — Core gameplay** | Auto Skip OFF rework, enemy overlap fix, stage economy nerf, Refine (in-match upgrades) | Cheap fixes that make the current loop feel right; the economy has to be settled before monetization |
| **P2 — Progression** | Inventory & loadout, unit leveling | The first use for Wisp Essence and duplicate units |
| **P3 — Multiplayer** | Party/lobby, host and votes, shared lives, team economy, (later) lobby/match place split | Touches flow, economy and Auto Skip, which P1 has already settled |
| **P4 — Reforge** | Traits + reforging; equipment/artifacts as an optional follow-up | Needs unit instances (P0) and the inventory (P2) |
| **P5 — Monetization** | Receipt handling, gamepasses, starter pack, banners + limited units, guaranteed reforge | Needs session locking, rarity, more units and reforge |
| **P6 — Retention** | Codes, daily rewards | Small. Can go in any time after P0 |
| **Ongoing — Content** | More units, enemy types, stages | Banners and leveling are pointless with one unit (see §7) |

---

## 1. P0 — Foundations

### 1.1 Profile v2 + migration
**Now:** `PlayerData` has a fixed layout with `Version = 1`. `Units = { [name] = copies }`. `reconcile` fills in missing keys but there is no migration step.

**Spec:**
- Add a `MIGRATIONS[fromVersion] = function(data)` table and run migrations in order after `GetAsync`, before `reconcile`.
- **v1 → v2:** turn each `{ Herobrine = n }` into `n` unit instances.
- New v2 layout:

```lua
{
  Version = 2,
  Settings  = { AlwaysHealthBars, AutoSkip },
  Gems      = number,
  Units     = { [uid] = UnitInstance },          -- see 1.3
  Loadout   = { uid?, uid?, uid?, uid?, uid?, uid? }, -- 6 slots (Config.LoadoutSlots)
  Items     = { [itemKey] = amount },            -- replaces Materials (WispEssence, VoidCrystal, ReforgeStone, ...)
  Summon    = { Total = 0, Pity = { [bannerId] = { Epic = 0, Legendary = 0 } } },
  Daily     = { Streak = 0, LastClaimDay = -1 },
  Codes     = { [CODE] = true },
  Purchases = { [purchaseId] = os.time() },      -- receipt idempotency (keep the last ~100)
  Flags     = { StarterPack = false },
  Stats     = { StagesCleared, BossesKilled, Kills, Summons, RobuxSpent },
}
```

- `Items` merges with `Materials`. Keep `Config.Materials` as the item registry and add a `Kind` field (`Material` | `Consumable`).
- **Done when:** a v1 save with `{ Herobrine = 2 }` loads as 2 instances, saves as v2, and loads again unchanged.

### 1.2 Session locking (required before teleports or purchases)
**Now:** `UpdateAsync` overwrites with the server's in-memory copy. If a player hops servers before their last save lands, the old server can overwrite newer data. In the worst case that duplicates or loses purchased items.

**Spec:**
- Either adopt **ProfileStore** (the successor to ProfileService) or add a lock field `{ JobId, Time }` written via `UpdateAsync`.
- With a hand-rolled lock:
  - Refuse to load while another live server holds the lock (older than 5 min = stale, take it over).
  - Release the lock on leave.
- **Done when:** joining a second server while the first still holds the profile waits or retries, and never loads stale data.

### 1.3 Unit instances
A unit you own becomes a record instead of a counter:

```lua
UnitInstance = {
  Id       = "u_<base36>",  -- HttpService:GenerateGUID(false) shortened
  Name     = "Herobrine",   -- key into Config.Units
  Level    = 1,             -- account level (§3.2), NOT the in-match upgrade level
  XP       = 0,
  Trait    = nil,           -- reforge trait key (§5)
  Locked   = false,         -- protect from feeding/selling
  Obtained = os.time(),
}
```

- Replace `PlayerData.Owns(player, name)` with `PlayerData.GetUnit(player, uid)`.
- `PlaceTower` takes a **uid** instead of a name:
  - The server reads Name, Level and Trait from the instance and computes the final stats.
  - The tower model gets a `UnitId` attribute.
- Add `Config.MaxUnitsOwned` (e.g. 150) so profiles stay well under the DataStore size limit.

### 1.4 Rarity
- Add `Rarity` to every `Config.Units` entry: `Rare` · `Epic` · `Legendary` · `Mythic` (plus `Secret` later).
- Add `Config.Rarities = { [name] = { Color, Order, MaxLevel, SellValue } }`.
- Rarity drives the banner rates (§6.2), the level cap (§3.2), the card frame color and the summon reveal.

### 1.5 Remote authority & hardening
**Now:** any player can fire `StartGame`, `Surrender`, `Retry`, `ReturnToMenu`, `SetSpeed` and `SetAutoSkip`. `SetAutoSkip` and profile load (`applySettings`) both write the global `workspace.AutoSkip`, so the last player to load decides it for everyone.

**Spec:**
- Introduce a **host**, the party leader or first player in the match. Match-flow remotes from anyone else become votes (§4.3).
- Add simple per-player rate limits to every remote (e.g. 10 calls/s for place/upgrade, 2/s for flow remotes).
- **Done when:** a non-host firing `Surrender` alone does not end a multiplayer match.

### 1.6 Cleanup
- `GameServer`: remove the dead `LevelLabel` branch in `UpgradeTower`.
- Decide whether `ServerStorage/ClientMain_3D_backup` and `TowerModels/*` stay. If they do, document them as archived; otherwise delete them.
- `Config.TowerScale` is used only by the 3D backup.
- `.gitignore` the `Eclipse Animator Saves` plugin folder, or leave it alone. It isn't game code.
- **Fresh clone:** the empty Rojo paths (`src/StarterGui`, `src/StarterPack`, `src/StarterPlayer/StarterCharacterScripts`) aren't in git because empty folders aren't tracked. Add a `.gitkeep` to each so `$path` resolves on a fresh clone.

---

## 2. P1 — Core gameplay fixes

### 2.1 Auto Skip OFF rework
**Now (OFF):** a "NEXT ROUND IN n" countdown runs during the whole spawn. The next round starts the moment the last enemy of the wave has spawned. The countdown counts down the remaining spawn time.

**Goal:** the timer only appears when the last enemy of the wave has spawned. The wave ends when **the timer runs out** or **the enemies are wiped out**, whichever comes first.

**Spec:**

1. **While the wave spawns:** no countdown. The HUD shows `WAVE r — x/y SPAWNED` (or nothing).
2. **When the last enemy spawns:** start `Config.WaveClearTime` (start at **20 s** game time, possibly scaled by round) and publish it as `workspace.Countdown`.
3. **Next round** starts when `Countdown` hits 0 **or** `#enemies == 0`. Count every enemy alive, including leftovers from earlier waves.
4. **Optional:** a **SKIP** button / vote (§4.3) ends the timer early.
5. **Final round:** no timer. Victory once everything is dead, as now.
6. **Auto Skip ON:** unchanged (60–70 % spawn threshold).

**Implementation:**

- In `startGame`'s round loop, replace the `target()` loop for the OFF branch with:
  1. Wait for `thisWave.Done`.
  2. Run the clear timer: loop with `gameWait(0.25)`, update `Countdown`, and break on `#enemies == 0`.
- Read `AutoSkip` once at the *start* of each round so toggling mid-wave can't produce a half-state.
- Give the client a phase attribute (`WaveState = "Spawning" | "Clearing"`) so the HUD can show the right text.

**Done when:** with OFF, no timer is visible while enemies spawn. A 20 s timer appears after the last spawn. Wiping the wave early starts the next round immediately.

### 2.2 Enemy overlap
**Now:** every enemy spawns at exactly `path[1]` and walks the exact center line. Faster tiers (5.5 → 11 studs/s) run into slower ones, and a hit changes an enemy's tier and so its speed. Round 15 spawns **104 enemies in 36 s** (one every 0.35 s), so sprites stack into a blob.

**Spec:** do both of the following.

1. **Fewer, tougher enemies.** Separate **Tier** (looks / type) from **Health** (a number):
   - Change the count to `EnemiesBase 6 + 3.2 × round`, so 54 at round 15.
   - Keep total wave HP about the same through a per-round HP multiplier: `Health = tierHP × (1 + HpPerRound × (round-1))`.
   - **Why this is needed anyway:** unit leveling (§3.2) and traits will push damage past the 1–5 HP range, so "tier = HP" can't last.
   - **Visuals:** the tier color changes at HP thresholds (`ceil(hp / maxHp × tierCount)`) instead of on every hit.
   - **Speed:** use a fixed speed per enemy type, not per remaining HP, so hits don't make enemies speed up.
2. **Lanes / spread:**
   - Give each enemy a random **lateral offset** of ±`(PathWidth/2 − 1.5)` studs from the center line. Store it on the server entry and apply it perpendicular to the current segment. Distance-along-path (`Dist`) stays exact, so targeting is unaffected.
   - Add a **minimum spawn gap**: delay a spawn if the previous enemy is within 2 studs of the start.
   - On the client, nudge the sprite's Z-sort by the offset so overlapping sprites layer cleanly.

**Done when:** at x3 on round 15, individual enemies stay readable and their health bars don't stack on top of each other.

**Open question:** do we want enemy *types* (fast / tank / flying / shielded) as well as tiers? This is recommended (§7.2), and the HP/type split above makes it easy.

### 2.3 Stage economy nerf
**Now (solo, full clear, current Config):**

| Source | Amount |
|---|---|
| Start money | 650 |
| Pops: ~3,650 enemy HP + 200 boss HP × `RewardPerPop 5` | ≈ 19,250 |
| Round bonuses: 200 + 40 × (r−2), rounds 2–15 | 6,440 |
| **Total per player** | **≈ 26,300** |

A fully upgraded Herobrine costs 5,000, so one player can afford about **5 maxed units**. There is also **no placement limit**, and every player in a server gets the full round bonus.

**Spec:**

1. **Lower and flatten income.** Starting targets:
   - `RewardPerPop` 5 → **2**
   - `RoundBonus` 200 → **120**
   - `RoundBonusStep` 40 → **20**
   - `StartMoney` stays at **650**, enough for one unit plus one upgrade.
   - Retune after §2.2 changes the HP totals. Aim for **≈ 2.5–3 maxed units by the boss** with good play.
2. **Placement cap:** `Config.MaxPlacedPerPlayer` (e.g. **8**), plus an optional per-unit `PlaceLimit` (e.g. a Legendary limited to 2). Show it as `3/8` in the shop.
3. **Upgrade costs:** let them scale with the unit's rarity. Rarer units cost more and are worth more.
4. **Multiplayer scaling** is in §4.4.
5. **Tooling:** add a `Config.DebugEconomy` flag. At stage end it prints income by source (pops / bonus / refunds) so balance can be checked from the numbers instead of guessed.

**Done when:** a solo full clear ends with total money earned within ±10 % of the target, and the end-of-stage print confirms it.

### 2.4 Refine (in-match upgrades)
**Now:** each unit has a linear `Levels` list (5 for Herobrine). The UPGRADE button / `U` key buys the next level. Selling refunds 50 % of `Spent`.

**Goal:** make in-match upgrading a deliberate choice that fits the new economy. Shown in the UI as **REFINE**.

**Spec:**
- **Every unit gets 4–6 refine levels.** The last one or two unlock something beyond stats, e.g. an ability: Herobrine's "Burning Gaze" deals burn damage over time.
- **Refine level cap** = `Levels` length. Optionally, account level gates the last refine (e.g. Refine 5 needs unit Lv 20). This links §3.2 to the match.
- **UI:**
  - The panel shows the next refine's name, a stat diff, and an ability description if there is one.
  - Add a **"Refine MAX"** shortcut that buys as many levels as you can afford, one after another.
- **Data:** add optional `Ability = { Kind = "Burn", Dps = 1, Duration = 2 }` to a `Levels[i]` entry. `GameServer.updateHits` applies status effects.

**Open question:** is "Refine" just the new name for the existing upgrade button, or a separate second mechanic (e.g. a one-time in-match boost paid with a material)? This spec assumes the first. Please confirm.

---

## 3. P2 — Progression

### 3.1 Inventory system & loadout
**Now:** the inventory shows Units and Materials tabs (counts only) and a Summon button. The in-match shop shows every owned unit type.

**Spec:**
- **Units tab:**
  - One card per instance: sprite, rarity frame, Lv, trait badge, lock icon.
  - Sort by rarity, level or newest. Filter by rarity.
  - Show the capacity (`42 / 150`).
- **Unit detail panel:**
  - Shows stats at the current level, the trait and XP.
  - Actions: **Equip**, **Level Up** (§3.2), **Reforge** (§5), **Lock**, **Sell** (for Gems or Essence; locked units and units in the loadout can't be sold).
- **Loadout:** `Config.LoadoutSlots = 6` (more with VIP, §6.3).
  - The in-match shop shows **only** loadout units, in slot order. Keys `1`–`6` select a slot. Today only `1` is bound.
- **Items tab:** the current Materials tab, plus consumables (Reforge Stone, Guaranteed Reforge, ...).
- **Remotes:** `EquipUnit(uid, slot)`, `LockUnit(uid, bool)`, `SellUnits({uid})` (bulk). All are server-validated, and none may run while the player is in a match.
- **Done when:** with 2 Herobrines at different levels, you can choose which one goes into the loadout, and the one you place in a match uses that instance's stats.

### 3.2 Unit leveling (account level)
Each instance levels up permanently. This is separate from in-match Refine.

- **XP sources:**
  - Units in the loadout earn XP at stage end: `XpBase + XpPerRound × round`, doubled on victory.
  - **Feed Wisp Essence**: 1 Essence = N XP. This gives Essence its first use.
  - Optional later: feed duplicate units.
- **Curve:** `XpToNext(level) = floor(20 × level^1.5)`. The level cap depends on rarity (Rare 30 · Epic 40 · Legendary 50 · Mythic 60).
- **Stat scaling:**
  - Damage: `× (1 + 0.03 × (Level−1))`.
  - Range: `+0.1 × (Level−1)`, capped.
  - SPA: unchanged, to avoid fast-firing outliers.
  - All of these live in `Config.LevelScaling`.
- **Damage numbers:**
  - Damage may become fractional. Once Health is a number (§2.2), keep fractional HP on the server and round it for display.
  - `RewardPerPop` then pays per **whole HP removed**, so carry the fraction per enemy.
- **Done when:** a Lv 10 Herobrine deals the configured extra damage in a match. Feeding Essence levels the unit up and the change is saved.

---

## 4. P3 — Multiplayer

### 4.1 Architecture
**Now:** the server runs one shared match, and `State`, lives, round and speed are global. There is no host or party, and everyone in the server sees the same menu.

**Plan:**
- **Step A, inside the current place: one server = one match.**
  - The main menu becomes a **lobby screen** with party slots (max `Config.MaxPartySize = 4`).
  - The host presses PLAY. Players who join mid-match spectate and can place units from the next round.
  - This makes the match logic multiplayer-correct before any teleport work.
- **Step B, after session locking (§1.2): split into a Lobby place and a Match place in the same universe.**
  - Lobby: party pads or queues → `TeleportService:ReserveServer` → teleport the party with `TeleportData { StageId, Difficulty, HostId }`.
  - Match place: loads profiles, runs one stage, then teleports everyone back.
  - Rojo needs a second project file (`match.project.json`) sharing `ReplicatedStorage`.

### 4.2 Shared vs per-player state
| Thing | Rule |
|---|---|
| Lives | Shared |
| Round, timer, boss | Shared |
| Money | Per player (see §4.4) |
| Units | Per player. Only the owner can refine, sell or retarget (already enforced) |
| Placement cap | Per player |
| Rewards | Per player, from their own profile. Same stage result for everyone |
| Settings (health bars) | Per player, client side |
| Auto Skip, Speed | Match-wide (see §4.3) |

### 4.3 Host & votes
- **Host-only:** START MATCH, Retry and Return to Lobby. If the host leaves, the oldest remaining player becomes host.
- **Votes:**
  - **Speed:** a majority picks the speed, and x3 needs the gamepass (§6.3).
  - **Auto Skip:** majority.
  - **Skip Wave:** all players.
  - **Surrender:** all players. Solo surrender needs no vote.
- Show the vote count on each button (e.g. `SKIP 2/3`).
- Remove the global `workspace.AutoSkip` write from `PlayerData.applySettings`. A player's saved setting now only sets their *vote*.

### 4.4 Team economy
**Now:** pop money goes to the shooter's owner, so in multiplayer players compete for kills. The round bonus goes to everyone in full.

**Spec:**
- **Shared pop income:** each pop pays **every** player `RewardPerPop × TeamIncome[n]` (e.g. n=1: 1.0, n=2: 0.65, n=3: 0.5, n=4: 0.42). This removes kill-stealing and keeps total team income at about 1.0–1.7× solo.
- The round bonus scales by the same factor.
- **Enemy HP scaling:** `× (1 + 0.35 × (n−1))`, so a full party still finds the stage hard.
- **Done when:** in a 2-player test both wallets stay equal, whoever's units do the killing.

---

## 5. P4 — Reforge (and maybe Equipment/Artifacts)

### 5.1 Traits
- Each unit instance has **one trait slot**. A second slot is an option for Mythic units later.
- Traits are a weighted table in `Config.Traits`:

| Trait | Effect | Weight |
|---|---|---|
| Sharp I / II / III | +5 / +10 / +15 % damage | 30 / 15 / 6 |
| Swift I / II / III | −4 / −8 / −12 % SPA | 30 / 15 / 6 |
| Eagle I / II / III | +6 / +12 / +18 % range | 30 / 15 / 6 |
| Greedy | +15 % money from this unit's pops (team share) | 4 |
| Overlord *(top)* | +25 % damage, +10 % range | 1 |

### 5.2 Reforging
- **Cost:** `1 ReforgeStone` (new item), or `ReforgeGemCost` Gems, plus Void Crystal for higher rarities. Reforge Stones drop from boss kills and daily rewards, and are sold in packs (§6).
- **Roll:**
  - Rolled on the server; the new trait replaces the old one.
  - Show the result with a short reveal. Optionally "keep old / take new" for a premium version.
- **Locking:** reforging is blocked while the unit is in an active match, and locked units can't be reforged by accident unless the player confirms.
- **Pity (optional):** after `Config.ReforgePity` (e.g. 80) rolls without a top-tier trait, the next roll is guaranteed one.
- **Remote:** `ReforgeUnit(uid, useItem)` → `{ ok, oldTrait, newTrait }`.

### 5.3 Equipment / Artifacts (maybe, after traits ship)
- **Artifacts:** an item you equip in a unit's artifact slot, with its own rarity and a rolled main stat (+% dmg, +range, −SPA, +money). Dropped by bosses or crafted from Essence + Crystal.
- This adds a second gear system and a lot of UI. Only start it if traits prove popular. The data shape leaves room for it: `UnitInstance.Artifact = artifactId`, stored in `Profile.Artifacts = { [id] = {...} }`.

---

## 6. P5 — Monetization

### 6.0 Shared infrastructure (must exist first)
- **Product IDs:** a `Config.Monetization` table with gamepass and dev product IDs. Placeholder IDs are fine in Studio.
- **Receipts:** one `MarketplaceService.ProcessReceipt` handler on the server.
  - It is **idempotent**: if `Profile.Purchases[PurchaseId]` already exists, return `PurchaseGranted` without granting again.
  - Otherwise grant the items, write `PurchaseId`, **save successfully**, then return `PurchaseGranted`. If the profile isn't loaded or the save fails, return `NotProcessedYet`.
- **Gamepasses:**
  - Cache ownership on join with `UserOwnsGamePassAsync` (with a pcall and a retry).
  - Update the cache on `PromptGamePassPurchaseFinished`.
  - Expose it as player attributes (`Pass_VIP = true`) so UI and rules can read it.
- **Shop UI:** a menu tab with Passes / Gems / Packs / Banner.
- **Compliance:**
  - If Gems can be bought with Robux, summons are *paid random items*. Show **drop rates** on the banner.
  - Check `PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted` and hide the Robux path for those players.

### 6.1 Gamepasses
| Pass | Perk | Notes |
|---|---|---|
| **VIP** | +1 loadout slot, +10 % Gems from stages, daily reward ×1.5, chat/name tag, VIP-only cosmetic frame | |
| **x3 Speed** | Unlocks the x3 option | Today x3 is free. Change `SpeedOptions` for non-owners to `{1, 2}`. In multiplayer, x3 is available if *any* party member owns the pass, which also encourages buying it |
| **2× Gems** | Doubles stage Gem rewards | |
| **+Unit Storage** | `MaxUnitsOwned` +100 | |
| *(later)* **Auto Summon / Skip Animations** | Quality of life | |

### 6.2 Banner & limited units
**Now:** a single summon at a fixed 100 Gems from one weighted pool, with no rarity, pity or rates.

**Spec:**
- **Banner definition** (`Config.Banners`, server-validated):

```lua
{ Id = "launch_01", Name = "Herobrine Rising",
  StartsAt = <unix>, EndsAt = <unix>,          -- Limited window (UTC)
  Cost = 50, Cost10 = 450,                      -- x1 and x10 (x10 discounted)
  Rates = { Rare = 70, Epic = 24, Legendary = 5.5, Mythic = 0.5 },  -- %
  Featured = { Mythic = "UnitX", Legendary = "UnitY" },  -- rate-up: 50% of that rarity
  Pity = { Legendary = 50, Mythic = 300 },       -- guaranteed by N pulls (per banner)
}
```

- There is always one **Standard banner** (no end date, no featured unit).
- **Limited units:** a unit with `Limited = true` can only drop from a banner whose time window includes `os.time()`. After the banner ends it never drops again. Possibly a re-run later, to keep its value.
- **Pity:** the counters live in `Profile.Summon.Pity[bannerId]`. A counter resets when that rarity (or higher) drops.
- **UI:**
  - Banner art from the pixel sprites, the time remaining, a rates popup, pity progress ("Mythic guaranteed in 212"), and x1 / x10 buttons.
  - The reveal animation is colored by rarity.
- **Done when:** a simulated 10,000-pull script on the server matches the configured rates within 1 %, and pity always triggers at N.

### 6.3 Guaranteed Reforge (dev product)
- A consumable **Guaranteed Reforge**:
  - **Option A (recommended):** the next reforge rolls only from the top tier (III or Overlord).
  - **Option B:** the player picks the trait they want.
- It is sold as a dev product (single and 5-pack) and can also be a rare daily-reward drop. It's stored in `Items` and used through `ReforgeUnit(uid, "Guaranteed")`.
- **Open question:** Option A or Option B? B is stronger and should be priced higher.

### 6.4 Starter Pack
- A **one-time dev product**, tracked with `Profile.Flags.StarterPack`.
- **Contents:** e.g. 1,000 Gems, 1 guaranteed Epic+ unit, 5 Reforge Stones, 1 Guaranteed Reforge, and 3 days of 2× Gems. It should be clearly better value than the normal Gem packs.
- **Shown:** a popup after the first stage clear, and in the shop for the player's first 7 days (from `Profile.Stats.FirstJoin`). It is hidden once bought.
- **Gem packs:** a normal dev product ladder (e.g. 100 / 550 / 1,200 / 2,600 / 7,000 Gems, with growing bonus %).

---

## 7. Content (needed for the features above to matter)

### 7.1 Units
Leveling, reforge and banners need several units across all rarities.
- **Minimum target:** **8–10 units**: about 3 Rare, 3 Epic, 2 Legendary and 1 Mythic, plus 1 Limited for the first banner.
- **Reuse:** `Rookie.rbxm` is a ready-made concept (a Rare starter unit). Give it a pixel sprite in `PixelArt`.
- **Archetypes:** single-target (Herobrine), splash, slow/support, money farm, long-range sniper, close-range rapid. Each needs a sprite, `Levels` (refine path) and a `BeamColor`. Splash, slow and money-farm units need small additions to `updateTowers` / `updateHits`.

### 7.2 Enemies & stages
- **Enemy types** (made possible by §2.2): Runner (fast, low HP), Tank (slow, high HP), Shielded (ignores the first N damage), Flying (only some units can hit it).
- **Stages:**
  - **Now:** one map, from `Workspace.Waypoints`.
  - Support several path folders (`Waypoints_Forest`, ...) and a **stage select** (with difficulty: Normal / Hard) on the lobby screen. Rewards scale by stage.
  - `Config.GetPath()` currently caches a single path, so it needs to take a stage ID.

---

## 8. P6 — Retention

### 8.1 Codes
- **Storage:** codes live **server-side only**, in `ServerStorage` or `ServerScriptService`. They must not go in `ReplicatedStorage/Config`, or clients can read every code.

```lua
Codes = { RELEASE = { Rewards = { Gems = 300, Items = { ReforgeStone = 2 } }, Expires = <unix|nil>, MinLevel = nil } }
```

- **Redeeming:**
  - Codes are case-insensitive and whitespace is trimmed.
  - Each code can be redeemed once per account, tracked in `Profile.Codes`.
  - The server checks the expiry date and rate-limits attempts (e.g. 5 per minute).
- **UI:** a text box plus a REDEEM button in the menu. The result message is one of: invalid · expired · already used · rewards list.
- **Optional:** live codes without republishing, by reading the list from a DataStore or `MemoryStoreService` that an admin command edits.

### 8.2 Daily Rewards
- **Cycle:** a 7-day loop, e.g.:

| Day | Reward |
|---|---|
| 1 | 100 Gems |
| 2 | 20 Essence |
| 3 | 150 Gems |
| 4 | 1 Reforge Stone |
| 5 | 200 Gems |
| 6 | 2 Void Crystals |
| 7 | 1 Guaranteed Reforge or a 1× Epic summon ticket |

- **Logic:**
  - `today = os.time() // 86400` (UTC day). The player can claim if `LastClaimDay < today`.
  - The streak goes up by 1 if `LastClaimDay == today − 1`. Otherwise it resets to day 1 (team decision: reset or keep).
- **UI:** a popup on join when a reward can be claimed, a calendar with past, today and future days, and a countdown to the next reset. VIP gets ×1.5 (§6.1).
- **Remote:** `ClaimDaily()` → `{ ok, day, rewards }`. The server is the only authority on time; never trust the client clock.

---

## 9. Cross-cutting requirements

- **Config-driven:** every new number and table goes in `Config`. The only exception is codes (§8.1) and anything else that must stay secret. Keep the "add one entry to add a unit" workflow.
- **Server authority:**
  - Every grant, roll and purchase happens on the server.
  - Remotes check types, ownership and match state, as `PlaceTower` already does.
- **Saving rules:**
  - Call `saveSoon` after anything valuable (summon, reforge, purchase, claim).
  - Purchases must save *before* acknowledging the receipt.
- **Profile size:** keep it under about 100 KB. Unit instances with short keys stay small; enforce `MaxUnitsOwned`.
- **Mobile:** the UI is mouse/keyboard-only today (hover health bars, right-click cancel, mouse-wheel zoom). Every new screen needs touch-friendly buttons, and the HUD needs a cancel button and a zoom control for touch.
- **Testing:** add server-side debug commands for Studio only, behind `RunService:IsStudio()`: give Gems, give unit, set round, simulate pulls, dump the economy.

---

## 10. Open questions for the team

1. **Refine:** is it the existing upgrade button renamed and expanded (this spec's assumption) or a separate mechanic? (§2.4)
2. **Guaranteed Reforge:** top-tier roll, or the player picks the trait? (§6.3)
3. **Daily streak:** if a player misses a day, reset to day 1 or pause? (§8.2)
4. **Multiplayer:** go straight to Lobby/Match places, or ship Step A (one server = one match) first? This spec recommends A first. (§4.1)
5. **Party size:** 4? (§4.1)
6. **x3 speed:** gate it behind a gamepass (it's free today)? (§6.1)
7. **Equipment/Artifacts:** in scope for the first release, or after traits? (§5.3)
8. **Enemy count:** halve it and add HP (recommended), or keep the count and fix only the overlap? (§2.2)
