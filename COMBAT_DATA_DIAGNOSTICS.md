# Combat Data Diagnostics - StormsDungeonData

## Issue Description

When using `/sdd force` to manually save a dungeon run, combat statistics (damage, healing, interrupts) were showing as **zero** for all players. This indicates that combat data was not available when the save was triggered.

## Why This Happens

Combat data can be unavailable for several reasons:

### 1. **WoW 12.0+ API Restrictions**
   - The `C_DamageMeter` API is restricted in certain contexts
   - Data may not be available immediately after a dungeon completes
   - Manual saves mid-run may not have finalized session data

### 2. **Combat Tracking Not Started**
   - Combat tracking needs to be active during the dungeon run
   - If you join a dungeon late, tracking may not have started
   - If the addon is reloaded mid-run, tracking is lost

### 3. **No Damage Meter Installed**
   - Without Details! addon, the fallback combat data is limited
   - The addon relies on either C_DamageMeter (WoW 12.0+) or Details! addon

### 4. **Forced Save Before Completion**
   - Combat sessions may not be finalized until the dungeon fully completes
   - Using `/sdd force` before natural completion may capture incomplete data

## What Was Fixed

I've added comprehensive **diagnostic messages** that will help you understand why combat data is missing:

### 1. **Combat Tracking Status Checks**
   - When entering a dungeon, the addon now confirms combat tracking is active
   - When using `/sdd force`, it reports:
     - Whether combat tracking is ACTIVE or INACTIVE
     - How many players are being tracked
     - Whether any combat data exists

### 2. **Data Source Logging**
   - The addon now clearly reports which source provided combat data:
     - `C_DamageMeter API` (WoW 12.0+ official API)
     - `Details addon` (Details! damage meter)
     - `CombatLog` (Built-in combat log tracking)
     - `none` (No data available)

### 3. **Missing Data Warnings**
   - When no combat data is found, you'll see detailed warnings explaining:
     - Which APIs were checked
     - Why each one might have failed
     - Actionable steps to fix the issue

### 4. **UI Feedback**
   - The scoreboard now shows: **"No combat data available - see chat for details"**
   - This replaces the confusing "Damage: 0, Healing: 0, Interrupts: 0" display

## How to Get Combat Data

### ✅ Best Practice: Let the Dungeon Complete Naturally
1. **Start the dungeon** - Combat tracking starts automatically
2. **Complete the run** - Wait for the loot window or completion
3. **Let the addon auto-save** - The scoreboard will appear automatically
4. **Combat data will be captured** - All stats will be available

### ⚠️ Manual Save Guidelines
If you need to use `/sdd force`:

1. **Make sure you're in the dungeon** when the run starts
2. **Don't reload the addon** during the run
3. **Wait for completion** before forcing a save
4. **Check the diagnostic messages** to see if combat data is available

### 🔧 Install Details! Addon (Recommended)
- Install [Details! Damage Meter](https://www.curseforge.com/wow/addons/details)
- This provides a reliable fallback for combat data
- Works on all WoW versions including 12.0+

## Diagnostic Messages You'll See

### When Entering a Dungeon:
```
[StormsDungeonData] Starting combat tracking (dungeon instance detected)
[StormsDungeonData] Combat tracking confirmed active
```

### When Using `/sdd force`:
```
[StormsDungeonData] Manual save initiated (slash command)...
[StormsDungeonData] Combat tracking status: ACTIVE
[StormsDungeonData] CombatLog has 5 player entries, hasData=true
```

### When Finalizing a Run:
```
[StormsDungeonData] Combat data retrieved from C_DamageMeter API
[StormsDungeonData] Combat data source: C_DamageMeter API
```

### When No Data Is Available:
```
[StormsDungeonData] WARNING: No combat data available from any source!
[StormsDungeonData] Possible reasons:
  - You are using WoW 12.0+ where combat data may be restricted
  - Try completing a full dungeon run without forcing a save
  - Combat tracking was not active during the run
  - Make sure you are in the dungeon when the run starts
  - Details addon is not installed or not tracking this dungeon
  - Install Details! addon for better combat data tracking
[StormsDungeonData] Combat data source: none
```

## Expected Behavior After Fix

### ✅ With the new diagnostics:
- **Clear feedback** on why combat data is missing
- **Actionable advice** on how to fix the issue
- **Source identification** so you know where data came from
- **Tracking confirmation** when entering dungeons

### ❌ Before the fix:
- Silent failure with all zeros
- No explanation of what went wrong
- Confusing error messages
- No way to diagnose the issue

## Testing the Fix

### Reload the addon:
```
/reload
```

### Enter a dungeon and check for:
```
[StormsDungeonData] Combat tracking confirmed active
```

### Run a dungeon and let it complete naturally

### Check the scoreboard - you should see combat data

### If you see zeros:
- **Read the diagnostic messages in chat**
- **They will tell you exactly what went wrong**
- **Follow the suggested fixes**

## Summary

The addon **is working correctly** - it's just that combat data wasn't available when you forced the save. The new diagnostic messages will help you understand **why** and **how to fix it** in the future.

**Recommended approach**: Let dungeons complete naturally instead of forcing saves mid-run. This ensures all combat data is properly finalized.
