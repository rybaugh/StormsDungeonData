# Installation & Setup Guide

## Prerequisites

- World of Warcraft (Retail/Modern version - 11.0.5+)
- Basic understanding of addon installation

## Step-by-Step Installation

### 1. Locate Your AddOns Folder

The path depends on your operating system:

**Windows:**
```
C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\
   ├── StormsDungeonData/
   │   ├── StormsDungeonData.toc
**Mac:**
```
~/Library/Application Support/World of Warcraft/_retail_/Interface/AddOns/
```

**Linux (with Wine):**
```
~/.wine/drive_c/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/
```
1. Download the `StormsDungeonData` folder
2. Copy it to your `AddOns` folder (from Step 1)
3. The folder structure should be:
   ```
   AddOns/
   ├── StormsDungeonData/
- Ensure folder is named exactly `StormsDungeonData` (case-sensitive)
- Check that `StormsDungeonData.toc` is in the root folder
   │   ├── Utils.lua
   │   ├── Database.lua
   │   ├── Events.lua
   │   ├── CombatLog.lua
   │   │   └── HistoryViewer.lua
   │   └── README.md
   ```

2. Click "AddOns" at the character selection screen
3. Check "Storm's Dungeon Data" to enable it
4. Log into a character

**Option B: Configuration File**
Edit your `WTF\Account\[AccountName]\SavedVariables\AddOns.txt` file and add:
```
STORMSDUNGEONDATA = 1
```

### 4. Verify Installation

1. In-game, type `/sdd` in chat
2. You should see the help message with available commands
2. Optionally, delete saved data:
   - Remove `StormsDungeonData.lua` from `WTF\Account\[AccountName]\SavedVariables\`
## First Time Setup

After installation, the addon will:
- Create a new database automatically
- Initialize saved variables
- Print a welcome message in chat

No additional configuration needed!

## Testing the Addon

### Test Scoreboard Display
1. Queue for a Mythic+ dungeon
2. Complete the dungeon
3. Loot the final chest
4. The scoreboard should automatically appear

### Test History Viewer
1. Run at least one Mythic+ dungeon
2. Type `/sdd history` in chat
3. The history viewer window should open

## Troubleshooting Installation

### Problem: Addon doesn't appear in addon list

**Solution:**
- Ensure folder is named exactly `StormsDungeonData` (case-sensitive)
- Check that `StormsDungeonData.toc` is in the root folder
- Restart WoW completely
- Try `/reload` command in-game

### Problem: "Unknown command" error for /sdd

**Solution:**
- Addon may not have fully loaded; type `/reload`
- Check addon is enabled in AddOns list
- Verify all files are present in the folder

### Problem: Saved data not persisting

**Solution:**
- Make sure `WTF` folder exists in your WoW directory
- Check disk space is available
- Try `/sdd reset` to reinitialize database
- Verify SavedVariables are being created in `WTF\Account\[AccountName]\SavedVariables\`

### Problem: Scoreboard doesn't appear after dungeon completion

**Solution:**
- Make sure you looted the final chest (required for trigger)
- Check UI scaling isn't hiding the window off-screen
- Verify addon loaded correctly with `/sdd status`
- Try `/sdd history` to ensure UI system is working

## Updating the Addon

When updating to a new version:
1. Back up your `SavedVariables` folder (optional but recommended)
2. Delete the old `StormsDungeonData` folder
3. Extract the new version
4. Restart WoW

Your saved data will be preserved as long as you keep the SavedVariables files.

## Uninstalling the Addon

1. Delete the `StormsDungeonData` folder from `Interface\AddOns\`
2. Optionally, delete saved data:
   - Remove `StormsDungeonData.lua` from `WTF\Account\[AccountName]\SavedVariables\`

Your saved data will be removed if you delete the SavedVariables file.

## Performance Considerations

- **Storage**: Each run record takes ~500 bytes; 1000 runs ≈ 500KB
- **Memory**: Addon uses minimal memory (~2-5MB) in non-combat situations
- **CPU**: Combat log parsing only active during Mythic+ runs
- **Disk**: SavedVariables written only when you complete a run

For users with very large histories (10,000+ runs), you may want to use `/sdd reset` to clear old data periodically.

## System Requirements

- **Minimum**: Same as World of Warcraft client
- **Recommended**: Modern system for smooth UI rendering
- **Disk Space**: 1MB for addon + variable size for SavedVariables

## Getting Help

If you encounter issues:
1. Check this guide and the main README.md
2. Type `/sdd status` for diagnostic information
3. Review any error messages in the chat
4. Check WoW Error Logs in `\Errors\` folder
