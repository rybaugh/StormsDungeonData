# StormsDungeonData — Agent Context

## Overview
**Storm's Dungeon Data** (v1.4) is a World of Warcraft addon for Mythic+ dungeon performance tracking.  
It records damage, healing, interrupts, deaths, and run metadata for every Mythic+ key, stores them
persistently, and provides a history viewer, live DPS/HPS chart, post-run scoreboard, player rating
system, and LFG tooltip integration.

- **Interface**: 120000–120005 (The War Within / Midnight era)
- **Global namespace**: `StormsDungeonData` (aliased as `MPT` in every file)
- **SavedVariables**: `StormsDungeonDataDB`, `StormsDungeonDataLog`
- **Slash commands**: `/sdd` or `/stormsdungeondata`

---

## File Load Order (from .toc)

```
Core.lua            → namespace, MPT:Initialize()
Utils.lua           → helpers
Logger.lua          → MPT.Log (Info/Warn/Error, DumpToChat, WriteToFile, Clear)
Database.lua        → MPT.Database (run records, player ratings, statistics, migrations)
Events.lua          → MPT.Events (WoW event handling, run lifecycle, FinalizeRun)
DamageMeterCompat.lua → MPT.DamageMeterCompat (C_DamageMeter compatibility layer)
CombatLog.lua       → MPT.CombatLog (COMBAT_LOG_EVENT_UNFILTERED parser)
CombatLogFileMonitor.lua → MPT.CombatLogFileMonitor (file-based auto-detection)
ReporterElection.lua → MPT.ReporterElection (addon-message party election, prefix "SDD")
LiveTracker.lua     → MPT.LiveTracker (timeline snapshots: dataPoints, bossKills, combatSessions)
TestMode.lua        → test helpers
UI/MinimapButton.xml / UI/MinimapButton.lua → draggable minimap button
UI/ScoreboardFrame.lua → MPT.Scoreboard (post-run MVP ranking, GetMVPRanking)
UI/LiveTrackerFrame.lua → MPT.LiveTrackerFrame (real-time DPS/HPS chart, Toggle)
UI/UIUtils.lua      → MPT.UIUtils
UI/LFMFrame.lua     → MPT.LFM (Looking for More guild group-finder)
UI/HistoryViewer.lua → MPT.HistoryViewer (history browser, insights page, Show/Hide)
LFGRatingIndicator.lua → MPT.LFGRatingIndicator (good/bad ratings in LFG tooltips)
PlayerTooltip.lua   → MPT.PlayerTooltip (good/bad ratings on unit tooltips)
Main.lua            → slash commands, minimap button wiring, MPT.PerformManualSave()
```

---

## Key State Variables (on the MPT table)

| Variable | Type | Purpose |
|---|---|---|
| `MPT.InMythicPlus` | bool | true while inside an active M+ key |
| `MPT.CurrentRunData` | table | pending run being recorded; nil outside a run |
| `MPT.RunJustSaved` | bool | set after FinalizeRun; prevents double-save within same instance |
| `MPT.RunBootstrapRecovered` | bool | true if run was detected via bootstrap (not CHALLENGE_MODE_START) |
| `MPT.RunCompletionRequirements` | table | `{bossCount, mapID, enemyForcesRequiredPercent}` |
| `MPT.RunCompletionProgress` | table | live boss/forces progress |
| `MPT.SpecCache` | table | `[guid] = specID` — populated by INSPECT_READY events |

---

## Database Schema (`StormsDungeonDataDB`)

```lua
{
  version = 1,
  runs = {},           -- array of run records (see below)
  characters = {},     -- character metadata
  playerRatings = {},  -- [normalizedPlayerKey] = "good"|"bad"  (legacy global rating)
  playerRatingGoodCount = {},  -- unused (counts are aggregated from per-run data)
  playerRatingBadCount  = {},
  settings = {
    autoShowScoreboard = true,
    playerTooltipEnabled = false,   -- show SDD rating on unit tooltips
    autoReportToParty = bool,       -- auto-post run summary to party chat
    minimap = { angle = number },   -- minimap button position
  },
  lfm = {
    posts     = {},   -- [postID] = post table
    points    = {},   -- [playerKey] = total Guild Points
    mySignups = {},   -- [postID] = true
  },
}
```

### Run Record

```lua
{
  id             = "CharName-Realm-timestamp-rand",
  timestamp      = number,   -- Unix time of save
  character      = string,   -- player name
  realm          = string,
  characterClass = string,   -- e.g. "WARRIOR"
  dungeonID      = number,   -- C_ChallengeMode mapID
  dungeonName    = string,
  keystoneLevel  = number,
  completed      = bool,
  duration       = number,   -- seconds
  onTime         = bool,     -- duration <= dungeon time limit
  startTime      = number,
  endTime        = number,
  players        = {},       -- array of player stat records (see below)
  mobsKilled     = number,
  mobsTotal      = number,
  overallMobPercentage = number,
  seasonID       = number,   -- absolute global season ID
  expansionLevel = number,   -- 10=TWW, 11=Midnight, etc.
  expansionAbbrev = string,  -- "TWW", "Midnight", etc.
  playerRatings  = {},       -- [normalizedPlayerKey] = "good"|"bad" (per-run rating)
  deleted        = bool,     -- soft-delete flag
}
```

### Player Stat Record (element of `run.players`)

```lua
{
  unitID   = string,    -- "party1", "player", etc.
  name     = string,
  class    = string,
  role     = string,    -- "DAMAGER", "HEALER", "TANK"
  guid     = string,
  specID   = number,
  damage   = number,
  healing  = number,
  interrupts = number,
  dispels  = number,
  deaths   = number,
  pointsGained = number,
  damagePerSecond  = number,
  healingPerSecond = number,
  interruptsPerMinute = number,
  rating   = string|nil,  -- "good"|"bad" (per-run player rating, stored inline)
}
```

---

## LiveTracker Data (`MPT.LiveTracker`)

Collects cumulative totals at every combat-exit and every 5 seconds (periodic ticker).

```lua
LiveTracker.dataPoints = {
  { elapsed = number, players = { [name] = { damage, healing, interrupts, deaths, avoidableDamageTaken, dps, hps } } },
  ...
}
LiveTracker.bossKills = { elapsed1, elapsed2, ... }  -- M+ elapsed seconds at each boss kill
LiveTracker.combatSessions = {
  { startElapsed = number, endElapsed = number, players = { [name] = { dps, hps } } },
  ...
}
```

- **Primary source**: `C_DamageMeter` (WoW 12.0+), restricted during combat  
- **Fallback**: `MPT.CombatLog.playerStats` (always available)  
- Cumulative-max semantics: values never decrease between snapshots  
- `collectionActive` is true during an active key; data persists after key ends so the frame is viewable outside the dungeon

---

## Run Lifecycle (Events.lua)

```
CHALLENGE_MODE_START
  → LiveTracker:Reset()
  → ReporterElection:BroadcastPresence()
  → MPT.InMythicPlus = true
  → MPT.CurrentRunData created

(during run)
  COMBAT_LOG_EVENT_UNFILTERED → CombatLog parser updates playerStats
  PLAYER_REGEN_DISABLED/ENABLED → LiveTracker:OnEnterCombat / OnExitCombat

CHALLENGE_MODE_COMPLETED
  → OnChallengeModeCompleted()
  → FinalizeRun("auto") → Database:SaveRun()
  → MPT.RunJustSaved = true
  → auto-report to party (if designated reporter)
  → Scoreboard:Show()

PLAYER_ENTERING_WORLD (out of instance)
  → MPT.RunJustSaved = false
  → LiveTracker:StopCollection()
  → Database:RefreshAllRunTimedStatus()
```

**Bootstrap recovery**: If `CHALLENGE_MODE_START` was missed (e.g., reload mid-run), the addon
detects `instanceType == "party" and difficultyID == 8` and calls `TryBootstrapMythicPlusRun()`.

---

## WoW API Compatibility Notes

| API | Version | Notes |
|---|---|---|
| `C_DamageMeter` | WoW 12.0+ (Midnight) | Restricted during combat; use `Enum.AddOnRestrictionType.Combat` to check |
| `C_MythicPlus.GetRunHistory()` | all | Used for manual save reconstruction |
| `C_ChallengeMode.GetActiveChallengeMapID()` | all | Active key map |
| `C_ChallengeMode.GetStartTime()` | all | Returns ms; divide by 1000 for LiveTracker sync |
| `TooltipDataProcessor.AddTooltipPostCall` | WoW 12.0+ | Runs in tainted context; never pass secret strings |
| `C_LFGList` | all | Group finder integration |
| `C_ChatInfo.SendAddonMessage` (prefix `"SDD"`) | all | Reporter election messages |

**Taint rule**: `TooltipDataProcessor` callbacks are tainted in WoW 12.0+.  
Player names are cached from `UPDATE_MOUSEOVER_UNIT` (untainted) and only the pre-computed
`goodCount`/`badCount` integers are passed into the tooltip callback.

**Season ID mapping** (absolute global IDs):
- BFA: 1–4, SL: 5–8, DF: 9–12, TWW: 13–16, Midnight: 17+

---

## Slash Commands (`/sdd`)

| Command | Effect |
|---|---|
| `history` / `h` | Open history viewer |
| `insights` / `i` | Open history viewer on insights page |
| `status` | Print run count, InMythicPlus, CurrentRunData, completion progress |
| `debug` | Print MVP ranking for CurrentRunData |
| `log [n]` | Dump last N log lines (default 100) |
| `log clear` | Clear internal log |
| `log file` | Write log to file |
| `test` | Call OnChallengeModeCompleted manually |
| `events` | Diagnose event registration, active keystone |
| `flow [n]` | Dump last N entries from event flow trace |
| `reset` | Wipe StormsDungeonDataDB |
| `help` | Print command list |

**Manual save**: `MPT.PerformManualSave(source)` — attempts to finalize the current or most-recent run.
Blocked when `MPT.RunJustSaved == true`. Tries keystone API → run history → `OnChallengeModeCompleted` in that order.

---

## Reporter Election (ReporterElection.lua)

When multiple party members have SDD with `autoReportToParty` enabled, a single designated reporter
is elected to post the run summary to party chat.

- Protocol: `HELLO:<GUID>` broadcast on `CHALLENGE_MODE_START`; recipients reply `ACK:<GUID>`
- Designated reporter = party member with lexicographically smallest GUID
- Manual "Report to Party" is never blocked by election result
- Addon message prefix: `"SDD"`, channel: `"PARTY"`

---

## Player Rating System

- Ratings are `"good"` or `"bad"`, stored both globally (`StormsDungeonDataDB.playerRatings`) and
  per-run (`run.playerRatings` and `player.rating` inside `run.players[]`)
- Key format: `lowercasename-lowercaserealm` (normalized, realm-qualified)
- Counts are aggregated by iterating all non-deleted runs (no separate counter fields)
- Displayed in: unit tooltips (`PlayerTooltip`), LFG search results and applicant tooltips (`LFGRatingIndicator`)

---

## UI Components

| Component | File | Open via |
|---|---|---|
| Minimap button | `UI/MinimapButton.xml` | Always visible; draggable |
| History viewer | `UI/HistoryViewer.lua` | Left-click minimap / `/sdd history` |
| Live tracker frame | `UI/LiveTrackerFrame.lua` | Right-click minimap |
| Scoreboard | `UI/ScoreboardFrame.lua` | Auto-shown on run complete |
| LFM frame | `UI/LFMFrame.lua` | Via LFM module |

---

## Data Migrations (Database.lua)

All migrations are one-time, gated by flags in `StormsDungeonDataDB.settings`:

| Migration | Flag | What it does |
|---|---|---|
| `ApplyOneTimeLegacySeasonAssignment` | `legacySeasonAssignedOnce` | Assigns current seasonID to runs with no season metadata |
| `ApplyOneTimeTWWSeasonIDRemigration` | `twwSeasonAbsoluteIDMigrationV1` | Converts relative TWW season IDs (1-4) to absolute (13-16) |
| `ApplyOneTimeLegacyTimedResultBackfillV2` | `legacyTimedResultBackfilledV2` | Re-evaluates `onTime` for all runs using duration vs API time limit (fixes Midnight mis-tags where `keystoneUpgrades` is always 0) |
| `RefreshAllRunTimedStatus` | (runs every login) | Live refresh of `onTime` in case Blizzard changes dungeon timers mid-season |

---

## Duplicate Run Detection

`Database:IsDuplicateRun(runRecord)` returns true when an existing non-deleted run shares:
- Same `dungeonID`, `keystoneLevel`, `character`, `realm`
- AND either `(endTime + duration)` or `(startTime + duration)` match within **±8 seconds**
