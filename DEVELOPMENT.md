-- Storm's Dungeon Data - Configuration & Development Guide

## User Configuration

### In-Game Settings

Currently, the addon has minimal configuration. Future versions will include an in-game settings panel.

**Manual Configuration via Saved Variables:**

Edit the console or access the SavedVariables directly to modify:

```lua
-- Auto-show scoreboard (default: true)
StormsDungeonDataDB.settings.autoShowScoreboard = false

-- Maximum runs to keep per dungeon (default: 50)
StormsDungeonDataDB.settings.maxHistoryPerDungeon = 100

-- Enable debug logging (for developers)
StormsDungeonDataDB.settings.debugMode = false
```

## Developer Guide

### Project Structure

```
StormsDungeonData/
├── StormsDungeonData.toc          # Addon manifest
├── Core.lua                       # Main namespace
├── Utils.lua                      # Utility functions
├── Database.lua                   # Data storage
├── Events.lua                     # Event handlers
├── CombatLog.lua                  # Combat parsing
├── Main.lua                       # Slash commands
├── UI/
│   ├── UIUtils.lua               # UI helpers
│   ├── ScoreboardFrame.lua        # Scoreboard UI
│   └── HistoryViewer.lua          # History UI
└── README.md / INSTALLATION.md
```

### Namespace Structure

All code is contained within the `StormsDungeonData` (or `MPT`) namespace:

```lua
local MPT = StormsDungeonData

-- Access modules
MPT.Database:SaveRun(runRecord)
MPT.Utils:FormatNumber(12345)
MPT.CombatLog:OnCombatLogEvent(...)
MPT.UI:ShowScoreboard(runRecord)
```

### Adding New Features

#### 1. Add a New Tracker

Create a new file in the root directory (e.g., `NewTracker.lua`):

```lua
local MPT = StormsDungeonData
local NewTracker = {}
MPT.NewTracker = NewTracker

function NewTracker:Initialize()
    print("|cff00ffaa[StormsDungeonData]|r NewTracker initialized")
end

function NewTracker:OnEvent(eventType, data)
    -- Handle your event here
end
```

Then reference it in `StormsDungeonData.toc`:

```
NewTracker.lua
```

#### 2. Add to Database Schema

Modify `Database.lua` to include new fields:

```lua
function Database:CreateRunRecord(...)
    return {
        -- existing fields...
        newField = {},  -- Your new field
    }
end
```

#### 3. Extend Combat Log Tracking

Add new event handlers in `CombatLog.lua`:

```lua
function CombatLog:OnNewEvent(data)
    -- Parse and store data
    self.playerStats[sourceName].newStat = value
end

-- Add to OnCombatLogEvent:
elseif eventType == "YOUR_EVENT" then
    self:OnNewEvent(...)
```

#### 4. Add UI Components

Create a new file in `UI/` directory and reference in `.toc`:

```lua
-- UI/NewUI.lua
local MPT = StormsDungeonData
local NewUI = {}
MPT.NewUI = NewUI

function NewUI:Create()
    local frame = CreateFrame("Frame", "StormsDungeonDataNewUI", UIParent)
    -- Create your UI here
    return frame
end
```

### Key APIs Used

#### WoW API Functions

**Unit Information:**
- `UnitName(unitID)` - Get unit name
- `UnitClass(unitID)` - Get class (returns name, class)
- `UnitLevel(unitID)` - Get unit level
- `GetRealmName()` - Get current realm
- `UnitGUID(unitID)` - Get unique identifier
- `UnitGroupRolesAssigned(unitID)` - Get role (TANK, DAMAGER, HEALER)

**Dungeon Information:**
- `GetInstanceInfo()` - Returns name, instanceType, difficultyID, etc.
- `C_ChallengeMode.GetActiveKeystoneInfo()` - Get keystone details
- `C_ChallengeMode.GetMapStatsForRun(mapID)` - Get map stats

**Loot:**
- `GetNumLootItems()` - Get number of loot items
- `GetLootSlotInfo(slot)` - Get item info from loot

**Combat Log:**
- `COMBAT_LOG_EVENT_UNFILTERED` event returns 25+ parameters
- Use bit.band() to check flags like `COMBATLOG_OBJECT_TYPE_PLAYER`

**UI:**
- `CreateFrame(frameType, name, parent, inherits)` - Create UI elements
- `SetScript(scriptType, function)` - Set event handlers
- `CreateFontString(layer, sublayer, fontName)` - Create text

#### Custom Functions

**Utils Module:**
```lua
MPT.Utils:FormatNumber(num)              -- 1234567 → "1.23M"
MPT.Utils:FormatPercentage(curr, total)  -- 50, 100 → "50.0%"
MPT.Utils:FormatDuration(seconds)        -- 3661 → "01:01:01"
MPT.Utils:GetClassColor(class)           -- "WARRIOR" → "C79C6E"
MPT.Utils:GetDungeonName(dungeonID)      -- 399 → "Shadowmoon Burial Grounds"
MPT.Utils:GetDungeonAcronym(name)        -- "Shadowmoon..." → "SMBG"
```

**Database Module:**
```lua
MPT.Database:SaveRun(runRecord)
MPT.Database:GetRunsByCharacter(name, realm)
MPT.Database:GetRunsByDungeon(dungeonID, charName, realm)
MPT.Database:GetAllCharacters()
MPT.Database:GetAllDungeons()
MPT.Database:GetDungeonStatistics(dungeonID, charName, realm)
```

### Code Style Guidelines

1. **Comments**: Use clear, concise comments
   ```lua
   -- Bad: set x
   -- Good: Cache the current player's damage output
   ```

2. **Variable Naming**: Use camelCase for variables
   ```lua
   local playerStats = {}  -- Good
   local player_stats = {} -- Bad
   ```

3. **Function Naming**: Use descriptive names
   ```lua
   function Database:GetRunsByDungeon(dungeonID, charName, realm) -- Good
   function Database:GetRuns(id) -- Bad
   ```

4. **Formatting**: 
   - Use 4 spaces for indentation
   - One blank line between functions
   - Two blank lines between sections

5. **Error Handling**:
   ```lua
   if not runRecord or not runRecord.dungeonID then
    print("|cff00ffaa[StormsDungeonData]|r Error: Invalid run record")
       return false
   end
   ```

### Testing

#### Manual Testing

1. **Load Test**:
   - Type `/reload` to reload addon
    - Type `/sdd status` to verify loading

2. **Feature Test**:
   - Queue Mythic+ dungeon
   - Complete and loot
   - Verify scoreboard appears
    - Check `/sdd history` shows the run

3. **Data Test**:
   - Multiple runs on same dungeon
   - Multiple characters
   - Verify statistics calculation
   - Check historical data persistence

#### Debug Mode

Enable debug logging:
```lua
StormsDungeonDataDB.settings.debugMode = true
```

Then add debug prints:
```lua
if StormsDungeonDataDB.settings.debugMode then
    print("|cffff00ff[DEBUG]|r" .. message)
end
```

### Common Issues & Solutions

**Issue: Saved variables not loading**
```lua
-- Solution: Ensure .toc file includes:
## SavedVariables: StormsDungeonDataDB
```

**Issue: Frame not visible**
```lua
-- Solution: Check frame level and positioning
frame:SetFrameLevel(100)  -- Set above other frames
frame:SetPoint("CENTER", UIParent, "CENTER")
```

**Issue: Combat log data not tracking**
```lua
-- Solution: Check event is registered
self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- Verify event is firing
CombatLog:OnCombatLogEvent(...)
```

**Issue: Database getting too large**
```lua
-- Solution: Implement run limit
function Database:SaveRun(runRecord)
    local runs = StormsDungeonDataDB.runs
    if #runs > 10000 then
        table.remove(runs, 1)  -- Remove oldest
    end
    table.insert(runs, runRecord)
end
```

### Version Compatibility

Currently targets:
- **Interface**: 110005 (WoW 11.0.5+)
- **Client**: World of Warcraft Retail/Modern

To update version:
1. Edit `StormsDungeonData.toc`: Change Interface version
2. Test all features
3. Update version in `Core.lua`

### Performance Optimization

**Current Optimizations:**
- Combat log tracking only active in dungeons
- Efficient table storage with indexed lookups
- Minimal frame updates

**Future Improvements:**
- Implement run limit to cap database size
- Use more efficient data compression
- Lazy-load UI elements
- Cache frequently accessed data

### Debugging Tips

1. **Check Chat for Errors**:
    - All error messages start with `|cff00ffaa[StormsDungeonData]|r`

2. **Use Print Statements**:
   ```lua
    print("Current runs: " .. #StormsDungeonDataDB.runs)
   ```

3. **Inspect Saved Variables**:
    - File location: `WTF/Account/[Account]/SavedVariables/StormsDungeonDataDB.lua`
   - Can be opened in any text editor

4. **Monitor Events**:
   ```lua
   -- Add temporary event logging
   function Events:OnEvent(event, ...)
       if event == "CHALLENGE_MODE_COMPLETED" then
           print("|cffff00ff[DEBUG]|r CM Completed!")
       end
   end
   ```

## Version History

### v1.0.0 - Initial Release
- Core scoreboard functionality
- Run history tracking
- Character/dungeon filtering
- Combat log parsing
- Saved variables system

### Future Versions (Planned)

**v1.1.0 - Enhanced Tracking**
- Player death tracking
- Crowd control tracking
- Boss encounter-specific stats

**v1.2.0 - Advanced UI**
- In-game settings panel
- Customizable stat columns
- Sorting options for history

**v2.0.0 - Social Features**
- Export run data
- Compare with guild members
- Leaderboard integration
