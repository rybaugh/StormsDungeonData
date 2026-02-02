# Storm's Dungeon Data Addon

A World of Warcraft addon that tracks and displays detailed statistics for Mythic+ dungeon runs.

## Features

### Real-Time Scoreboard
- **Automatic Scoreboard Display**: When you complete a Mythic+ key and loot the final chest, a scoreboard automatically displays showing:
  - Dungeon name and keystone level
  - Duration of the run
  - Overall mob kill percentage
  - Player statistics:
    - Total damage dealt
    - Total healing done
    - Number of interrupts
    - Deaths

### Comprehensive Statistics Tracking
The addon tracks and stores:
- **Per-Player Stats**: Damage, healing, interrupts, deaths
- **Per-Run Stats**: Dungeon difficulty, completion status, duration, mob percentage
- **Cross-Character Storage**: All data is saved globally and can be filtered by character

### History Viewer
A detailed UI for viewing historical data:
- **Filter by Character**: View runs specific to each of your characters
- **Filter by Dungeon**: See statistics for individual dungeons
- **Summary Statistics**:
  - Total runs completed and failed
  - Average keystone level
  - Average run duration
  - Best keystone level achieved
  - Average damage, healing, and interrupts
  - Average mob kill percentage
- **Run History**: Chronological list of recent runs with key details

## Installation

1. Extract the `StormsDungeonData` folder to your WoW addons directory:
   - Windows: `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - Mac: `~/Library/Application Support/World of Warcraft/_retail_/Interface/AddOns/`
   - Linux: `~/.wine/drive_c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/`

2. Restart World of Warcraft or type `/reload` in-game

3. The addon will appear in your addons list

## Usage

### Slash Commands

```
/sdd              - Show help
/sdd history      - Open the history viewer
/sdd status       - Show addon status
/sdd reset        - Reset the database (warning: deletes all data)
```

### How It Works

1. **Automatic Tracking**: When you enter a Mythic+ dungeon, the addon automatically begins tracking:
   - Combat log events (damage, healing, interrupts)
   - Mob kills and total mobs
   - Player information and roles

2. **Run Completion**: When you complete the dungeon and loot the final chest, the scoreboard will automatically appear with all the statistics

3. **View History**: Use `/sdd history` to open the history viewer and:
   - Filter by character and dungeon
   - Compare statistics across multiple runs
   - Track your performance over time

## Data Storage

All data is stored in **Saved Variables** and persists across game sessions. The addon stores:
- Run history with complete statistics
- Character metadata (name, realm, class)
- User settings

## Configuration

### Auto-Show Scoreboard
By default, the scoreboard automatically appears when you loot the final chest. To disable this in the future code versions, modify the `StormsDungeonDataDB.settings.autoShowScoreboard` variable.

## Technical Details

### Modules

- **Core.lua** - Main addon namespace and initialization
- **Utils.lua** - Utility functions (formatting, class colors, dungeon info)
- **Database.lua** - Saved variables management and statistics calculation
- **Events.lua** - WoW event handlers
- **CombatLog.lua** - Combat log parsing and stat collection
- **Main.lua** - Slash commands and setup
- **UI/UIUtils.lua** - Common UI functions and styling
- **UI/ScoreboardFrame.lua** - Scoreboard display
- **UI/HistoryViewer.lua** - History viewer interface

### Event Tracking

The addon listens for:
- `ADDON_LOADED` - Initialize addon
- `PLAYER_ENTERING_WORLD` - Start/stop combat tracking
- `CHALLENGE_MODE_COMPLETED` - Cache run completion
- `LOOT_OPENED` - Detect final chest and save run
- `COMBAT_LOG_EVENT_UNFILTERED` - Track all combat statistics

## Future Enhancements

Potential features for future versions:
- Individual player stat breakdown
- Keystroke efficiency metrics
- Performance ranking compared to other players
- Group composition tracking
- Affixes performance analysis
- Weekly/monthly statistics
- Export functionality
- Dungeon route optimization suggestions
- Integration with third-party ranking sites
- Custom alerts for milestones

## Troubleshooting

### Scoreboard Not Appearing
- Make sure you're looting the chest at the end of the dungeon
- Verify addon is enabled in addons list
- Type `/sdd status` to confirm addon is loaded

### Data Not Saving
- Check that `StormsDungeonDataDB` is in your SavedVariables list in the .toc file
- Try `/sdd reset` to reinitialize the database

### Performance Issues
- Combat log tracking is optimized to only run in dungeons
- Uncheck the addon if playing on very low-end systems

## Support

For issues or suggestions, check the addon's source code or contact the author.

## License

This addon is provided as-is for personal use.

## Version History

### v1.0.0 - Initial Release
- Basic scoreboard functionality
- Run history tracking
- Character and dungeon filtering
- Combat log parsing
- Saved variables persistence
