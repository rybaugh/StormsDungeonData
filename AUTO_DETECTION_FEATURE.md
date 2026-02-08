# Storm's Dungeon Data - Auto-Detection Feature

## Summary of Changes

### What Was Fixed
1. **Player Count Validation** - Fixed bug where incorrect players (like "Haadym") were being logged
   - Now validates that only the 5 actual dungeon participants are saved
   - Cross-references with `groupMembers` list captured at dungeon start
   - Implements safety limit to never exceed 5 players
   - Sorts by activity and keeps only top 5 if somehow more are detected

2. **Automatic Run Detection** - New intelligent auto-detection system
   - Detects when Mythic+ runs start via `CHALLENGE_MODE_START` event
   - Automatically saves runs when player uses Hearthstone
   - Validates that the saved run matches the dungeon you just completed
   - Prevents duplicate saves and invalid data

### New File Created
- **`CombatLogFileMonitor.lua`** - Monitors combat log events for:
  - `CHALLENGE_MODE_START` - Tracks when M+ runs begin
  - Hearthstone spell casts - Triggers auto-save when you leave the dungeon
  - Zone validation - Only saves if you were actually in that dungeon

### Modified Files

#### `StormsDungeonData.toc`
- Added `CombatLogFileMonitor.lua` to load order

#### `Core.lua`
- Added `MPT.CombatLogFileMonitor` module declaration
- Initialize combat log file monitor on addon load

#### `Events.lua` (Line ~1430)
- **Enhanced `EnsurePlayersFromStats` function**:
  - Now validates players against `groupMembers` list
  - Filters out players not in the actual dungeon group
  - Implements safety check to limit to maximum 5 players
  - Sorts by combat activity if count exceeds 5
  
- **Added dungeon start notification**:
  - Notifies `CombatLogFileMonitor` when `CHALLENGE_MODE_START` fires
  - Ensures proper tracking of current dungeon

#### `README.md`
- Documented new auto-detection feature
- Added section on auto-save via Hearthstone
- Updated module list to include `CombatLogFileMonitor.lua`

## How It Works

### Run Start Detection
1. Player enters Mythic+ dungeon and activates keystone
2. `CHALLENGE_MODE_START` event fires
3. `CombatLogFileMonitor` captures dungeon info (name, map ID, level)
4. Combat tracking begins automatically

### Run End Detection & Auto-Save
1. Player completes dungeon
2. Player uses any Hearthstone spell to leave
3. `CombatLogFileMonitor` detects the Hearthstone cast
4. Validates current dungeon matches the zone before hearthing
5. Triggers auto-save with 1-second delay to ensure all data is captured
6. Run is logged with correct 5 players

### Player Validation
When merging stats from Details/C_DamageMeter:
1. Check if player is in `groupMembers` list (captured at start)
2. If no `groupMembers` data, only add players with combat activity (damage/healing/interrupts > 0)
3. Final safety: if more than 5 players detected, sort by activity and keep top 5

## Benefits

1. **Hands-Free Operation** - No manual commands needed (`/sdd force` still available as backup)
2. **Accurate Data** - Only actual participants are logged
3. **Prevents Errors** - Won't log phantom players or incorrect runs
4. **User-Friendly** - Natural workflow: do dungeon → hearth → run saved automatically
5. **Safe Validation** - Multiple checks ensure data integrity

## Testing Recommendations

1. Start a Mythic+ key
2. Complete the dungeon normally
3. Use Hearthstone to leave
4. Check saved data - should have exactly 5 players who were in your group
5. Verify no phantom players like "Haadym" appear

## Backward Compatibility

- All existing features still work
- Manual save via `/sdd force` or minimap button still available
- Existing saved data is not affected
- No breaking changes to UI or database structure
