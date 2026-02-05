# Implementation Notes: Details & RaiderIO Integration

## Overview
This document describes the implementation of mythic plus completion detection and enemy forces calculation based on how Details! and RaiderIO handle these features.

## 1. Enemy Forces (Mob %) Calculation - Based on RaiderIO

### RaiderIO's Approach
RaiderIO uses a robust method to calculate enemy forces percentage that handles multiple API formats:

```lua
-- From RaiderIO core.lua (lines 9266-9287)
1. Gets C_Scenario.GetStepInfo() to find number of criteria
2. Iterates criteria, last one is always trash/enemy forces
3. Tries multiple methods to extract data:
   - Method 1: Parse quantityString (e.g., "95%")
   - Method 2: Calculate from quantity * totalQuantity / 100
   - Method 3: Fall back to quantity/totalQuantity ratio
```

### Our Implementation
```lua
-- Events.lua: GetEnemyForcesProgress()
- Uses C_Scenario.GetStepInfo() and C_ScenarioInfo.GetCriteriaInfo()
- Gets the LAST criteria (numCriteria) which is always enemy forces
- Tries quantityString parsing first (handles "95%" and "530/600" formats)
- Falls back to RaiderIO formula: current = (quantity * totalQuantity) / 100
- Ensures percent is clamped to 0-100 range
- Returns {current, total, percent} for maximum flexibility
```

**Key Insight**: RaiderIO's formula `quantity*totalQuantity/100` suggests that `quantity` is already a percentage (0-100) and `totalQuantity` is the actual enemy count. This handles cases where the API doesn't provide `quantityString`.

## 2. Mythic Plus Completion Detection - Based on Details!

### Details! Approach
Details! uses a comprehensive method to capture all completion data:

```lua
-- From Details parser.lua (lines 6254-6330)
function Details.parser_functions:CHALLENGE_MODE_COMPLETED(...)
    1. Calls C_ChallengeMode.GetChallengeCompletionInfo()
    2. Extracts ALL available fields:
       - mapChallengeModeID, level, time (completion time)
       - keystoneUpgradeLevels, onTime, practiceRun
       - isAffixRecord, isMapRecord, isEligibleForScore
       - oldOverallDungeonScore, newOverallDungeonScore
       - members (upgrade info for each player)
    3. Gets additional dungeon info from C_ChallengeMode.GetMapUIInfo()
    4. Stores comprehensive LastMythicPlusData table
    5. Uses timers to delay showing UI (1-2 seconds)
```

### Our Implementation
```lua
-- Events.lua: GetCompletionInfoCompat()
- Enhanced to capture all fields from GetChallengeCompletionInfo()
- Added: onTime, practiceRun, isAffixRecord, isMapRecord, etc.
- Stores in MPT.CurrentRunData for later use
- Maintains backward compatibility with legacy APIs

-- Events.lua: OnChallengeModeCompleted()
- Captures comprehensive completion data
- Stores additional metadata: onTime, keystoneUpgrades, scores
- Uses 8-second and 45-second fallback timers
- Logs key information for debugging
```

## 3. Key Improvements Made

### Enemy Forces Calculation
1. **More accurate parsing**: Handles both percentage strings and numeric values
2. **RaiderIO formula**: Uses proven `quantity*totalQuantity/100` calculation
3. **Better fallback logic**: Multiple methods to extract data
4. **Comprehensive logging**: Easier to debug issues

### Completion Detection
1. **Comprehensive data capture**: All fields from GetChallengeCompletionInfo()
2. **Better timing**: Fallback timers (8s, 45s) like Details!
3. **Improved logging**: Shows completion status, timing, upgrades
4. **Additional metadata**: onTime, scores, records for future features

## 4. Why These Changes Fix the Issues

### Auto-Save Not Triggering
**Root Cause**: The LOOT_OPENED event may not always fire reliably, and fallback timers weren't being set correctly.

**Solution**: 
- Ensured fallback timers are ALWAYS set when CHALLENGE_MODE_COMPLETED fires
- Added `fallbackTimersSet` flag to prevent duplicate timers
- Reset flag in FinalizeRun() for next run
- Added comprehensive logging to diagnose issues

### Timing Inaccuracy
**Root Cause**: Duration calculation could be inaccurate if API data wasn't properly preserved or if CombatLog timestamps were used incorrectly.

**Solution**:
- Prioritize `completionDuration` from API (most accurate)
- Use Details! method: `startTime = time() - durationSeconds` when API duration available
- Only fall back to timestamp calculation if API duration is missing
- Added logging to show which timing source is used

### Mob Percentage Accuracy
**Root Cause**: Original implementation didn't handle all API response formats correctly.

**Solution**:
- Implemented RaiderIO's proven parsing methods
- Handle multiple formats: "95%", "530/600", or quantity/totalQuantity
- Use RaiderIO's formula for numeric calculation
- Get LAST criteria (always enemy forces) instead of assuming numSteps

## 5. Testing Recommendations

After these changes, look for these log messages:

```
[StormsDungeonData] CHALLENGE_MODE_COMPLETED event fired
[StormsDungeonData] Completion info: mapID=..., level=..., time=...s, onTime=...
[StormsDungeonData] Challenge mode completed!
[StormsDungeonData] Key upgraded: X levels, onTime: true/false
[StormsDungeonData] Fallback timers set (8s and 45s)
[StormsDungeonData] GetEnemyForcesProgress: Returning current=X, total=Y, percent=Z
[StormsDungeonData] Mob % from CombatLog: X% (Y/Z)
[StormsDungeonData] 8-second fallback timer triggered, auto-saving run (completed)
[StormsDungeonData] Run saved! (completed)
```

## 6. Future Enhancements

Based on Details! and RaiderIO implementations, potential future features:

1. **Death penalty calculation**: Details! subtracts 5 seconds per death from completion time
2. **Affix tracking**: Store and display active affixes for the run
3. **Record detection**: Show when a run is a new record (time, affix, or map record)
4. **Score changes**: Display old vs new Mythic+ score
5. **Member upgrades**: Track which players got vault upgrades
6. **Run comparison**: Compare current run to previous best (RaiderIO style overlay)

## References

- Details! mythic dungeon handling: `Details/functions/mythicdungeon/mythicdungeon.lua`
- Details! completion parsing: `Details/core/parser.lua` (CHALLENGE_MODE_COMPLETED)
- RaiderIO enemy forces: `RaiderIO/core.lua` (lines 9260-9287)
- RaiderIO replay system: `RaiderIO/core.lua` (ReplayBoss, ReplaySummary classes)
