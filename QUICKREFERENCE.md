# Storm's Dungeon Data - Quick Reference

## Commands

```
/sdd              Show help and commands
/sdd history      Open history viewer
/sdd status       Show addon status
/sdd test         Simulate a dungeon run (TESTING ONLY)
/sdd reset        Reset all data (WARNING: Deletes everything)
```

## Features Implemented

✅ **Scoreboard Display**
- Auto-shows when loot chest is opened
- Shows dungeon name, level, duration
- Displays player stats: damage, healing, interrupts, deaths
- Color-coded player names by class

✅ **Run History Tracking**
- Saves all completed runs across characters
- Stores player statistics
- Tracks mob kill percentage
- Persists data across game sessions

✅ **History Viewer**
- Filter by character
- Filter by dungeon
- View summary statistics
- See chronological run history
- Compare runs and performance

✅ **Combat Log Parsing**
- Tracks damage dealt
- Tracks healing done
- Counts interrupts
- Counts mob kills
- Calculates percentages

✅ **Multi-Character Support**
- Track data per character
- View history across all alts
- Filter by specific character

✅ **Database System**
- SavedVariables persistence
- Efficient data storage
- Character metadata tracking
- Run record management

## Main Files

| File | Purpose |
| --- | --- |
| `Core.lua` | Main namespace, initialization |
| `Utils.lua` | Formatting, colors, dungeon info |
| `Database.lua` | Data storage and statistics |
| `Events.lua` | WoW event handlers |
| `CombatLog.lua` | Combat stat tracking |
| `DamageMeterCompat.lua` | WoW 12.0 API compatibility |
| `TestMode.lua` | Test mode and simulation |
| `Main.lua` | Slash commands |
| `UI/ScoreboardFrame.lua` | Scoreboard display |
| `UI/HistoryViewer.lua` | History viewer UI |
| `UI/UIUtils.lua` | Common UI functions |

## Data Stored Per Run

```lua
{
    id = "unique-run-id",
    timestamp = 1234567890,
    character = "CharacterName",
    realm = "RealmName",
    dungeonID = 399,
    dungeonName = "Shadowmoon Burial Grounds",
    keystoneLevel = 15,
    completed = true,
    duration = 1800,  -- seconds
    mobsKilled = 450,
    mobsTotal = 500,
    overallMobPercentage = 90.0,
    players = {
        {
            name = "PlayerName",
            class = "WARRIOR",
            role = "TANK",
            damage = 500000,
            healing = 0,
            interrupts = 5,
            deaths = 0,
            pointsGained = 0,
        },
        -- ... more players
    }
}
```

## Statistics Provided

**Per Run:**
- Dungeon name and difficulty
- Player count
- Duration
- Completion status
- Mob kill percentage

**Per Player Per Run:**
- Total damage dealt
- Total healing done
- Number of interrupts
- Deaths
- Damage per second
- Healing per second
- Interrupts per minute
- Points gained

**Aggregate by Dungeon:**
- Total runs
- Completed vs. failed
- Average keystone level
- Best keystone level
- Average run duration
- Average damage, healing, interrupts
- Average mob kill percentage

## Architecture

```
StormsDungeonData Namespace
├── Database Module
│   ├── Create/Save runs
│   ├── Query history
│   └── Calculate statistics
├── Events Module
│   ├── Listen for dungeon completion
│   ├── Detect loot chest
│   └── Trigger save
├── CombatLog Module
│   ├── Parse combat events
│   ├── Track stats
│   └── Calculate percentages
├── Utils Module
│   ├── Format numbers
│   ├── Get class colors
│   └── Dungeon info
├── UI Module
│   ├── ScoreboardFrame
│   └── HistoryViewer
└── Slash Commands
    ├── /sdd history
    ├── /sdd status
    ├── /sdd test
    └── /sdd reset
```

## Test Mode (NEW - v1.1.0+)

**Perfect for development and demonstration without needing actual M+ keys!**

### Using Test Mode

```
/sdd test
```

This command:
1. Generates a random Mythic+ dungeon (M+2 to M+20)
2. Creates realistic player statistics with:
   - Damage (50k-150k)
   - Healing (for healers)
   - Interrupts (2-8 per player)
   - Random deaths (5% chance)
3. Saves the run to your database
4. Shows the scoreboard immediately
5. Stores in your character history

### What Gets Saved

Each test run includes:
- Dungeon name and difficulty level
- Duration (20-45 minutes)
- All 1-5 party members with stats
- Realistic combat statistics
- Run completion status
- Affixes percentage

### Examples

```
/sdd test              # Generate random test run
/sdd history           # View saved test runs
/sdd test              # Run multiple times for testing
```

**Note**: Test runs are marked internally but appear identical to real runs in the history viewer. This is intentional for testing UI layouts and statistics calculations.

## Common Usage Scenarios

### View Recent Runs
1. Type `/sdd history`
2. Select character from left panel
3. Select dungeon from left panel
4. View stats and run history on right

### Test Without Real Dungeons
1. Type `/sdd test` to generate a test run
2. View scoreboard that appears
3. Type `/sdd history` to see saved data
4. Run `/sdd test` multiple times for different dungeons

### Compare Dungeon Performance
1. Open history with `/sdd history`
2. Click same dungeon multiple times
3. Review statistics (avg level, duration, etc.)
4. Check recent runs list to see trends

### Track Multiple Characters
1. Run dungeon on multiple alts
2. Type `/sdd history`
3. Click different characters in left panel
4. Each character's runs are isolated

### Reset Everything
1. Type `/sdd reset`
2. All data is deleted
3. New runs will be tracked fresh


## UI Overview

### Scoreboard Window
```
┌─────────────────────────────────────┐
│ Mythic+ Run Complete          [X]   │
├─────────────────────────────────────┤
│ Shadowmoon Burial Grounds           │
│ Level: 15    Duration: 45:32        │
│ Mobs: 87.5%                         │
├─────────────────────────────────────┤
│ Player          │Damage   │Healing  │
│ [Class] Name    │  500K   │   0K    │
│ [Class] Name    │  450K   │  100K   │
│ [Class] Name    │  400K   │   50K   │
│ [Class] Name    │   50K   │  500K   │
│ [Class] Name    │   40K   │   60K   │
├─────────────────────────────────────┤
│          [Close]  [History]         │
└─────────────────────────────────────┘
```

### History Viewer Window
```
┌───────────────────────────────────────────┐
│ Mythic+ Run History                  [X]  │
├──────────────┬─────────────────────────────┤
│ Characters   │ Statistics                  │
│ • Alt1       │ Total Runs: 50              │
│ • Alt2       │ Completed: 47               │
│ • Alt3       │ Failed: 3                   │
│              │ Avg Level: 14               │
│ Dungeons     │ Best Level: 19              │
│ • SMBG (12)  │                             │
│ • EB (8)     │ Recent Runs:                │
│ • UBRS (15)  │ 2024-02-01 +15 [Complete]  │
│ • UR (9)     │ 2024-01-31 +14 [Complete]  │
│              │ 2024-01-30 +15 [Failed]    │
├──────────────┴─────────────────────────────┤
│                                            │
└────────────────────────────────────────────┘
```

## Keyboard Shortcuts

Currently, the addon supports only slash commands. Future versions may add keybindings.

## Tips & Tricks

1. **Organize Runs**: All data is stored automatically; just keep running keys
2. **Compare Performance**: Use history viewer to track improvement over time
3. **Track Affixes**: Addon stores affixes with each run (visible in code)
4. **Export Data**: Saved data is plain text in SavedVariables folder
5. **Backup Data**: Copy `StormsDungeonDataDB.lua` from SavedVariables before major updates

## Limitations

- Combat log data is session-only (from dungeon enter to loot)
- Requires looting final chest to trigger save
- Points calculation not yet implemented (shows 0)
- No export/import functionality in v1.0.0
- No guild integration or leaderboards
- UI not yet resizable or customizable

## File Locations

**SavedVariables:**
- Windows: `C:\Users\[User]\Documents\My Games\World of Warcraft\_retail_\WTF\Account\[Account]\SavedVariables\StormsDungeonDataDB.lua`
- Mac: `~/Library/Application Support/World of Warcraft/_retail_/WTF/Account/[Account]/SavedVariables/StormsDungeonDataDB.lua`

**Error Logs:**
- Windows: `World of Warcraft\_retail_\Errors\`

## Support

For issues:
1. Check this quick reference
2. Review README.md for detailed docs
3. Check INSTALLATION.md for setup help
4. Review DEVELOPMENT.md for technical details
5. Type `/sdd status` for diagnostic info
