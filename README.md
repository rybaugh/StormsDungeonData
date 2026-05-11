# Storm's Dungeon Data Addon

A World of Warcraft addon that tracks and displays detailed statistics for Mythic+ dungeon runs, rates party members, and surfaces those ratings in the Group Finder.

---

## Features

### Real-Time Scoreboard

When you complete a Mythic+ key, a scoreboard displays (automatically when you loot the final chest, or via the minimap button):

- **Dungeon info**: Name, keystone level, duration, mob kill percentage
- **Player statistics**: Damage, healing, interrupts, deaths (per player)
- **MVP highlight**: Top contributor based on role-weighted damage/healing/interrupt share
- **Personal bests**: Your own stats are highlighted in orange when you beat your previous best for that dungeon

**Per-player actions (non–you only):**

- **Rate good / Rate bad**: Thumbs-up (+) and thumbs-down (-) buttons to mark players as good or bad. Counts are stored (e.g. “rated good 5 times”) and used in the Group Finder.
- **Add Friend**: Button to add the player to your friend list. If you add them, a **friend note** is set automatically with your rating summary (e.g. `SDD: Good +5, Bad +2`). If they’re already a friend and you change their rating, the note is updated automatically.

### Run Detection & Auto-Save

The addon detects run start and completion so runs are saved without manual steps.

**Run start**

- Listens for `CHALLENGE_MODE_START` and starts combat tracking.
- Combat log monitor (event-driven, not file scanning) can detect dungeon start and Hearthstone usage for fallback.

**Run completion & auto-save**

- **Multiple triggers**: Completion is detected via:
  - `CHALLENGE_MODE_COMPLETED_REWARDS` (primary)
  - `CHALLENGE_MODE_COMPLETED` (backup)
  - `ENCOUNTER_END` (combat log: last boss kill in M+)
  - `SCENARIO_COMPLETED` / `SCENARIO_UPDATE` when the scenario is complete
  - Loot opened (final chest)
  - Hearthstone used after completing the dungeon (with zone check)
  - Leaving the instance (`PLAYER_ENTERING_WORLD`) with a pending completed run
- **Delayed auto-save**: Several delayed checks (2s, 5s, 10s) run after completion so the run is saved even if the completion API is slow or retries. Fallback timers (8s and 45s) also ensure the run is finalized.
- **Manual save**: Right-click the minimap icon and choose to save the current run if auto-save didn’t trigger.

### Player Ratings (Good / Bad)

- **Scoreboard**: For each non-you player, you can rate them **good** (+) or **bad** (-). Each click increments a **good count** or **bad count** for that player (by name–realm).
- **Storage**: Counts and last rating are stored in saved variables (`playerRatings`, `playerRatingGoodCount`, `playerRatingBadCount`) and persist across sessions.
- **Friend notes**: When you add someone as a friend from the scoreboard, their friend note is set to something like `SDD: Good +5, Bad +2`. If they’re already a friend and you rate them again, the note is updated automatically.

### Group Finder (Premade Groups) Integration

**LFG Rating Indicator** shows your ratings while you browse or manage groups:

- **Browse groups (search results)**  
  - **In-list**: Each group row can show a short label for the **leader** on the right: e.g. `Good +5`, `Bad +3`, or `Good +5  Bad +2` (green/red).  
  - **Tooltip**: Hovering a group adds lines such as “Storm's Dungeon Data: Good player +5” and/or “Storm's Dungeon Data: Bad player +3”.

- **Applicants (when you’re the leader)**  
  - **Tooltip**: Hovering an applicant shows the same Good/Bad player +N lines for that player.

So when forming or joining M+ groups, you can see at a glance whether you’ve previously rated the leader or applicants good or bad and how many times.

### History Viewer

- **Filter by character** and/or **dungeon**.
- **Summary stats**: Total runs, completed/failed, average key level, average duration, best key, average damage/healing/interrupts, mob %.
- **Run list**: Chronological history with key details; open from the scoreboard “History” button or `/sdd history`.

### Combat & Data Sources

- **Combat log**: The addon uses **live combat log events** (`COMBAT_LOG_EVENT_UNFILTERED` and related). It does **not** scan the combat log file on disk.
- **WoW 12+**: When available, uses `C_DamageMeter` (and related) for session data; combat log is still used for deaths, mob kills, and player validation.
- **Player validation**: Only players who actually participated in the run (and match group members) are saved; maximum 5 per run.

---

## Installation

1. Place the `StormsDungeonData` folder in your WoW addons directory:
   - **Windows**: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **Mac**: `~/Library/Application Support/World of Warcraft/_retail_/Interface/AddOns/`
   - **Linux**: `~/.wine/drive_c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/`

2. Restart World of Warcraft or run `/reload` in-game.

3. Enable the addon in the AddOns list.

---

## Usage

### Slash Commands

| Command | Description |
|--------|-------------|
| `/sdd` | Show help |
| `/sdd history` | Open the history viewer |
| `/sdd status` | Show addon status and current run info |
| `/sdd reset` | Reset the database (deletes all runs and ratings) |

### Minimap Button

- **Left-click**: Open the scoreboard for the current/last run (or manual save flow if no run data).
- **Right-click**: Manually save the current run and/or open options (e.g. History).

### Typical Flow

1. Start your Mythic+ key (tracking starts automatically).
2. Complete the dungeon (completion is detected via multiple events and delayed checks).
3. Loot the chest and/or use Hearthstone — the run is saved and the scoreboard can show.
4. On the scoreboard, rate other players (+ / -) and add them as friends if you want (notes are set automatically).
5. When browsing Group Finder, look for “Good +N” / “Bad +M” on leaders and in tooltips for applicants.

---

## Data Storage

All data is stored in **Saved Variables** (`StormsDungeonDataDB`) and persists across sessions:

| Data | Description |
|------|-------------|
| `runs` | Run history (dungeon, level, duration, players, stats) |
| `characters` | Character metadata |
| `playerRatings` | Last rating per player: `"good"` or `"bad"` |
| `playerRatingGoodCount` | Number of times each player was rated good |
| `playerRatingBadCount` | Number of times each player was rated bad |
| `settings` | e.g. `autoShowScoreboard` |

---

## Configuration

- **Auto-show scoreboard**: By default the scoreboard appears when you loot the final chest. This is controlled by `StormsDungeonDataDB.settings.autoShowScoreboard` (can be exposed in a future options UI).

---

## Technical Details

### Modules

| File | Purpose |
|------|--------|
| **Core.lua** | Namespace, initialization, module wiring |
| **Utils.lua** | Formatting, class colors, dungeon info |
| **Database.lua** | Saved variables, runs, ratings, good/bad counts |
| **Events.lua** | WoW events, completion logic, auto-save scheduling |
| **CombatLog.lua** | Combat log parsing, per-player stats, mob counts |
| **CombatLogFileMonitor.lua** | Live combat log events for M+ start and Hearthstone |
| **DamageMeterCompat.lua** | WoW 12+ C_DamageMeter vs legacy combat log |
| **LFGRatingIndicator.lua** | Group Finder: in-list labels and tooltips for ratings |
| **Main.lua** | Slash commands, manual save, status |
| **TestMode.lua** | Test/demo support |
| **UI/ScoreboardFrame.lua** | Scoreboard UI, rating buttons, Add Friend, notes |
| **UI/HistoryViewer.lua** | History viewer UI |
| **UI/UIUtils.lua** | Shared UI helpers |
| **UI/MinimapButton.xml** | Minimap button |

### Events Used

- `ADDON_LOADED`, `PLAYER_ENTERING_WORLD` — Init and zone/instance changes.
- `CHALLENGE_MODE_START` — Start M+ tracking.
- `CHALLENGE_MODE_COMPLETED`, `CHALLENGE_MODE_COMPLETED_REWARDS` — Completion and auto-save.
- `ENCOUNTER_END` — Combat log boss kill (backup completion).
- `SCENARIO_COMPLETED`, `SCENARIO_UPDATE` — Scenario completion.
- `LOOT_OPENED` — Final chest and save.
- `COMBAT_LOG_EVENT_UNFILTERED` — Combat stats and ENCOUNTER_END.
- Optional (WoW 12+): `COMBAT_METRICS_SESSION_*`, `DAMAGE_METER_COMBAT_SESSION_UPDATED`.

LFG Rating Indicator hooks into the Group Finder UI (search panel and applicant viewer) and uses `LFG_LIST_SEARCH_RESULTS_RECEIVED` when the frame is not yet available at load.

---

## Troubleshooting

| Issue | What to try |
|-------|--------------|
| Scoreboard doesn’t appear | Loot the end chest; use right-click minimap to manually save; run `/sdd status` to see if a run is pending. |
| Run not auto-saved | Use right-click minimap to save. Ensure addon is enabled; try `/reload` after a run. |
| No ratings in Group Finder | Open Group Finder at least once so the LFG UI loads; search for a group to refresh. |
| Friend note not set | Adding uses `C_FriendList.AddFriend(name, note)`. Updating uses `C_FriendList.SetFriendNotes(name, note)`. Both require the standard WoW friend list. |

---

## Version History

### v1.1.8+
- **End-of-run auto-save**: Multiple delayed checks (2s, 5s, 10s) and backup from `CHALLENGE_MODE_COMPLETED` and `ENCOUNTER_END` so runs save even when one event doesn’t fire.
- **Player ratings**: Rate party members good (+) or bad (-) on the scoreboard; good and bad counts stored.
- **Group Finder**: In-list “Good +N” / “Bad +M” and tooltips for leaders and applicants.
- **Add Friend + notes**: Add non-you players as friends from the scoreboard; friend note set/updated automatically with “SDD: Good +N, Bad +M”.

### v1.0.0 – Initial
- Scoreboard, run history, character/dungeon filtering, combat log parsing, saved variables.

---

## License

This addon is provided as-is for personal use.
