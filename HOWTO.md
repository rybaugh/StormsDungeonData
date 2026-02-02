# How to Use Storm's Dungeon Data - Complete Guide

## Getting Started in 5 Minutes

### Step 1: Install the Addon (2 minutes)
1. Find your WoW AddOns folder (see INSTALLATION.md)
2. Extract `StormsDungeonData` folder there
3. Restart World of Warcraft
4. Check AddOns list to ensure it's enabled

### Step 2: Verify Installation (1 minute)
1. In-game, open chat
2. Type: `/sdd`
3. You should see the help message
4. Type: `/sdd status`
5. You should see "Total runs: 0"

### Step 3: Run Your First Mythic+ (varies)
1. Queue for a Mythic+ dungeon key
2. Enter the dungeon
3. Combat log tracking starts automatically
4. Complete the dungeon
5. Loot the final chest
6. **Scoreboard appears automatically!**

### Step 4: View Your History (1 minute)
1. Type: `/sdd history`
2. History viewer window opens
3. Your first run is in the database
4. Add more runs to build history

**You're all set!** The addon is now tracking your Mythic+ performance.

---

## Detailed Usage

### The Scoreboard Window

After you complete a Mythic+ key and loot the final chest, this window automatically appears:

**What It Shows:**
```
┌──────────────────────────────────────────────────┐
│ Mythic+ Run Complete                       [Close]│
├──────────────────────────────────────────────────┤
│ Shadowmoon Burial Grounds                        │
│ Level: +15        Duration: 35:47                │
│ Mobs: 92.5%                                      │
├──────────────────────────────────────────────────┤
│ Player          │ Damage   │ Healing │Interrupts│
├─────────────────┼──────────┼─────────┼──────────┤
│ [Warrior] Tank  │  550.2K  │    0K   │    8     │
│ [Priest] Healer │   45.3K  │  520K   │    2     │
│ [Rogue] DPS1    │  680.1K  │   10K   │   12     │
│ [Mage] DPS2     │  625.3K  │    5K   │    5     │
│ [Druid] DPS3    │  590.2K  │  100K   │    3     │
├──────────────────────────────────────────────────┤
│                          [Close]   [History]    │
└──────────────────────────────────────────────────┘
```

**Understanding the Stats:**
- **Player**: Character name with class color
- **Damage**: Total damage dealt during the run
- **Healing**: Total healing done during the run
- **Interrupts**: Number of times they interrupted enemies
- **Deaths**: Number of deaths (not shown but tracked)
- **Points**: Seasonal points (shows as 0 in current version)

**Buttons:**
- **Close**: Dismiss the scoreboard
- **History**: Jump directly to history viewer

---

### The History Viewer

Open with: `/sdd history`

**Top Filters:**

**Character Dropdown:**
```
Character:
All Characters
```
- Select a character to filter by that character
- Shows all characters with runs in the database
- Realm name shown for clarity

**Dungeon Dropdown:**
```
Dungeon:
SMBG (12)
```
- Select a dungeon to filter by that dungeon
- Number in parentheses shows total runs on that dungeon
- Dungeons shown across all characters (or just selected one)

**Keystone Dropdown:**
Choose a keystone level to filter by difficulty

**Right Side - Statistics:**

**Summary Section:**
```
Dungeon Statistics

Total Runs: 50
Completed: 48
Failed: 2
Avg Level: 13
Avg Duration: 36:45
Best Level: 18
Avg Damage: 550.2K
Avg Healing: 250.1K
Avg Interrupts: 7
Avg Mob %: 87.3%
```

- **Total Runs**: How many times you've run this dungeon
- **Completed**: Successful completions
- **Failed**: Times you didn't complete (key expired)
- **Avg Level**: Average keystone difficulty
- **Best Level**: Highest level keystone completed
- **Avg Duration**: Average time to complete
- **Damage/Healing/Interrupts**: Per-run averages
- **Mob %**: What percentage of mobs you killed on average

**Recent Runs Section:**
```
Recent Runs:

2024-02-01 16:30  +15  Completed  35:47  92.5%
2024-01-31 14:15  +14  Completed  38:22  88.1%
2024-01-30 19:45  +16  Failed     42:10  75.3%
2024-01-29 13:20  +14  Completed  37:15  91.2%
2024-01-28 20:50  +15  Completed  36:50  89.9%
```

- **Date/Time**: When you ran the dungeon
- **Level**: Keystone difficulty (+15, +16, etc.)
- **Status**: Completed or Failed
- **Duration**: How long the run took
- **Mob %**: Overall mob kill percentage

---

## Common Tasks

### View Stats for Specific Character

**Steps:**
1. Type `/sdd history`
2. In the top bar, choose your character
3. Statistics update to show only that character's data
4. Right panel shows that character's averages

**What Changes:**
- Damage, healing, interrupt numbers are specific to that character
- Run list shows only their runs
- Statistics are per that character

### Compare Dungeon Performance Over Time

**Steps:**
1. Type `/sdd history`
2. Choose a dungeon (e.g., "SMBG")
3. Look at "Recent Runs" section
4. See progression of difficulty and performance

**What to Look For:**
- Are your average keystones going up?
- Are you completing faster?
- Is your mob percentage improving?
- Do you see a difficulty trend?

### See Performance on Specific Dungeon with Specific Character

**Steps:**
1. Type `/sdd history`
2. Choose a character (top bar)
3. Choose a dungeon (top bar)
4. Both filters active - stats show only that combo

**Example:**
- Show only "YourMain" on "SMBG"
- See how many times you've run SMBG on that character
- Compare performance against all your other characters

### Find Your Best Runs

**Steps:**
1. Open `/sdd history`
2. Look at "Best Level" stat - that's highest key you completed
3. Look at "Recent Runs" for that specific level
4. Check if times are improving

**Tips:**
- High "Avg Level" means you consistently do difficult keys
- High "Avg Mob %" means you're efficient
- Lower "Avg Duration" means you're fast

### Track Improvement Over Time

**Weekly Check:**
1. Every week, run `/sdd history`
2. Note your "Avg Level" and "Avg Duration"
3. Note your "Avg Damage" or "Avg Healing"
4. Compare to last week

**What to Track:**
- Average keystone level going up = success!
- Duration going down = getting faster!
- Damage/healing going up = getting better gear!
- Completion rate going up = fewer failures!

---

## Slash Commands Reference

### `/sdd` - Help
Shows all available commands and what they do.

```
/sdd
```

**Output:**
```
[StormsDungeonData] Commands:
/sdd history - Show run history
/sdd status - Show addon status
/sdd reset - Reset database
/sdd help - Show this message
```

### `/sdd history` - Open History Viewer
Opens the main history viewer window where you can filter and analyze runs.

```
/sdd history
```

**Window Opens:** 1000x700 window with character/dungeon filters and statistics

### `/sdd status` - Check Addon Status
Shows current addon status and how many runs are recorded.

```
/sdd status
```

**Output:**
```
[StormsDungeonData] Status:
Total runs: 47
Type /sdd history to view history
```

### `/sdd reset` - Delete All Data
⚠️ **WARNING** - This permanently deletes all recorded runs and data!

```
/sdd reset
```

**Use Only When:**
- You want to start fresh tracking
- Testing the addon
- You're absolutely sure

**CANNOT be undone** - Previous runs are gone forever!

---

## Tips & Tricks

### Maximize Your Data

**Tip 1: Run Varied Keystone Levels**
- Run easy keys to build confidence
- Challenge yourself with harder keys
- History shows your progression

**Tip 2: Check Weekly**
- Set a weekly alarm to review stats
- See if you're improving
- Note which dungeons you excel at

**Tip 3: Compare Characters**
- Which character performs best?
- Which character prefers certain dungeons?
- Use this to optimize alt farming

**Tip 4: Track Affixes**
- Addon stores affixes with each run (not displayed yet)
- Note in external notes which affixes you like/hate
- Plan future runs accordingly

### Organize Your Data

**Keep Good Records:**
- Run multiple times per dungeon
- Mix in harder and easier keys
- Eventually build 50+ runs per dungeon
- Use history viewer for analysis

**Data Limits:**
- Default: Keeps up to 50 runs per dungeon
- Addon won't get too large
- More is better for statistics accuracy
- 1000 total runs = ~500KB disk space

---

## Frequently Asked Questions

### Q: Will the scoreboard appear even if I fail?
**A:** No, addon only saves runs when the key is completed. Failed runs are not tracked (yet).

### Q: What if I close the scoreboard before looking at it?
**A:** The data is still saved! Use `/sdd history` to see it anytime.

### Q: Can I export my data?
**A:** v1.0.0 doesn't have export, but data is stored in plain text SavedVariables file. You can copy it manually.

### Q: Does this addon track my guild members?
**A:** No, it only tracks your own characters. Future versions may add guild integration.

### Q: What happens to data if I delete the addon?
**A:** SavedVariables persist. If you reinstall the addon, your data returns. Only deleted if you manually delete the .lua file.

### Q: How much space does it use?
**A:** ~1KB per run, so 100 runs = 100KB. Not significant even with thousands of runs.

### Q: Can I have different settings for different characters?
**A:** v1.0.0 has global settings only. Per-character settings coming in future version.

### Q: Does this slow down my game?
**A:** No. Combat tracking only active during dungeons, minimal memory usage, no UI lag.

---

## Troubleshooting

### Scoreboard Doesn't Appear After Dungeon

**Solution:**
1. Make sure you looted the final chest (it's required)
2. Verify addon is enabled in AddOns list
3. Type `/sdd status` - addon should show as loaded
4. Try typing `/sdd history` - if that works, addon is loaded

### History Viewer Shows No Data

**Solution:**
1. You need to complete at least one Mythic+ key first
2. After first run, type `/sdd history` again
3. Data takes a few seconds to appear after completion

### Data Not Saving

**Solution:**
1. Close WoW completely (important!)
2. Locate SavedVariables folder (see INSTALLATION.md)
3. Verify `StormsDungeonDataDB.lua` file exists
4. If not, run another dungeon to create it
5. Try `/sdd reset` to reinitialize

### Numbers Look Wrong

**Solution:**
1. Combat log may have missed some events (rare)
2. If damage seems low, it's counting correctly
3. Try comparing against recount/damage meter
4. If still wrong, bug may exist - note details for reporting

### Window Off Screen

**Solution:**
1. Alt+drag any part of window to move
2. Or type `/sdd reset` and reopen `/sdd history`
3. Window should center on screen

---

## Next Steps

### For Casual Players
- Run 1-2 Mythic+ keys per week
- Check history once a week
- Watch your average level improve
- Enjoy the stats tracking!

### For Serious Players
- Run multiple keys daily
- Track specific affixes
- Compare to teammates
- Use data to optimize strategies
- Plan which dungeons to focus on

### For Developers
- Read DEVELOPMENT.md for code structure
- Modify addon for custom statistics
- Add new UI features
- Contribute improvements

---

## Support

**If something isn't working:**
1. Read this guide
2. Check README.md for more info
3. Verify installation steps in INSTALLATION.md
4. Type `/sdd status` for diagnostics
5. Check WoW Error Logs folder

**Data Files:**
- SavedVariables: `WTF\Account\[Account]\SavedVariables\StormsDungeonDataDB.lua`
- Error Logs: `World of Warcraft\_retail_\Errors\`

---

**Enjoy tracking your Mythic+ progress!**

For advanced features and customization, see DEVELOPMENT.md.
