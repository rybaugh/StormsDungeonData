# Storm's Dungeon Data - Documentation Index

Welcome to the **Storm's Dungeon Data** addon! This document guides you to the right documentation for your needs.

## 🚀 Getting Started

**New to the addon? Start here:**

1. **[HOWTO.md](HOWTO.md)** - *5-minute quick start guide*
   - Installation in 2 minutes
   - Your first Mythic+ run walkthrough
   - Basic usage examples
   - Common tasks explained
   - **Start here if you just want to use the addon!**

2. **[INSTALLATION.md](INSTALLATION.md)** - *Detailed installation instructions*
   - Step-by-step setup for all platforms (Windows, Mac, Linux)
   - Verification procedures
   - Troubleshooting installation issues
   - Uninstall/update instructions
   - **Use this if installation is confusing**

## 📖 Learning the Addon

**Want to learn all features?**

1. **[README.md](README.md)** - *Complete user documentation*
   - Feature overview
   - Detailed usage instructions
   - Data storage explanation
   - Troubleshooting common issues
   - Architecture overview
   - **Use this for comprehensive understanding**

2. **[QUICKREFERENCE.md](QUICKREFERENCE.md)** - *Quick lookup guide*
   - Command reference
   - Feature checklist
   - Data structure overview
   - Common usage scenarios
   - Tips and tricks
   - File locations
   - **Use this as a quick reference bookmark**

## 🎯 Understanding the Project

**Want to understand what was built?**

1. **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** - *Complete project overview*
   - What's been implemented
   - Feature list with ✅ checks
   - Technical architecture
   - File structure
   - Performance characteristics
   - Future enhancement ideas
   - **Use this to understand the entire project**

## 🛠️ Developer Documentation

**Want to customize or extend the addon?**

1. **[DEVELOPMENT.md](DEVELOPMENT.md)** - *Developer guide*
   - Code structure and modules
   - API reference for WoW functions
   - How to add new features
   - Code style guidelines
   - Testing procedures
   - Debugging tips
   - **Use this to modify or extend the addon**

## 📂 File Structure

```
StormsDungeonData/
├── 📄 Documentation (read first)
│   ├── HOWTO.md                    ← Start here!
│   ├── README.md
│   ├── INSTALLATION.md
│   ├── QUICKREFERENCE.md
│   ├── PROJECT_SUMMARY.md
│   ├── DEVELOPMENT.md
│   └── INDEX.md                    ← You are here
│
├── 📦 Core Addon Files
│   ├── StormsDungeonData.toc       Addon manifest
│   ├── Core.lua                    Main namespace
│   ├── Utils.lua                   Helper functions
│   ├── Database.lua                Data storage
│   ├── Events.lua                  Event handlers
│   ├── CombatLog.lua               Combat parsing
│   └── Main.lua                    Slash commands
│
└── 🖼️ User Interface
    └── UI/
        ├── UIUtils.lua             Common UI functions
        ├── ScoreboardFrame.lua      Scoreboard window
        └── HistoryViewer.lua        History viewer window
```

## 🎮 Quick Command Reference

```
/sdd              Show help
/sdd history      Open history viewer
/sdd status       Show addon status
/sdd reset        Reset all data
```

## 📋 Documentation Purpose Guide

| Document | Purpose | Audience | Read Time |
|----------|---------|----------|-----------|
| **HOWTO.md** | Get started using the addon | All users | 5 min |
| **README.md** | Learn all features | All users | 15 min |
| **INSTALLATION.md** | Install and troubleshoot | New users | 10 min |
| **QUICKREFERENCE.md** | Quick lookups | Returning users | 2 min |
| **PROJECT_SUMMARY.md** | Understand what was built | Project owners | 10 min |
| **DEVELOPMENT.md** | Customize and extend | Developers | 30 min |

## 🔍 Finding Answers to Common Questions

### "How do I install this?"
→ Go to **INSTALLATION.md**

### "How do I use the addon?"
→ Go to **HOWTO.md** (quick) or **README.md** (detailed)

### "What does this addon do?"
→ Go to **PROJECT_SUMMARY.md** or **README.md**

### "How do I fix [problem]?"
→ See Troubleshooting section in **README.md** or **INSTALLATION.md**

### "What command does [action]?"
→ See **QUICKREFERENCE.md**

### "I want to modify the code"
→ Go to **DEVELOPMENT.md**

### "What are the keyboard shortcuts?"
→ Currently only slash commands; see **QUICKREFERENCE.md**

### "Can I export my data?"
→ See FAQ in **HOWTO.md** or **README.md**

## 📊 What the Addon Tracks

The addon automatically records for each Mythic+ run:

**Run Information:**
- Dungeon name and difficulty level
- Start time and duration
- Completion status (success/failure)
- Mob kill percentage
- Character information

**Player Statistics:**
- Damage dealt
- Healing done
- Interrupts cast
- Deaths
- Damage per second
- Healing per second
- Interrupts per minute

**Historical Data:**
- Run history per character
- Run history per dungeon
- Summary statistics
- Aggregate performance metrics

## 🎯 Typical User Workflows

### Workflow 1: Track Your Performance
1. Run Mythic+ dungeons normally
2. Addon automatically tracks each run
3. Weekly: Open `/sdd history` to check progress
4. Compare statistics to previous weeks

### Workflow 2: Compare Characters
1. Run keys on multiple alts
2. Open `/sdd history`
3. Filter by character to see each alt's performance
4. Identify which character is strongest

### Workflow 3: Analyze Dungeon Difficulty
1. Open `/sdd history`
2. Select a specific dungeon
3. Review "Recent Runs" section
4. See if difficulty is increasing
5. Check if completion times are improving

### Workflow 4: Learn from Mistakes
1. View failed runs in history
2. Compare stats to successful runs on same dungeon
3. Identify where the group struggled
4. Adjust strategy for next attempt

## 🔗 Relationship Between Documents

```
You want to USE the addon?
    ↓
Start with HOWTO.md
    ↓
Learn more in README.md
    ↓
Quick lookups in QUICKREFERENCE.md

You want to UNDERSTAND the addon?
    ↓
Read PROJECT_SUMMARY.md
    ↓
For technical details, see DEVELOPMENT.md

You want to INSTALL the addon?
    ↓
Follow INSTALLATION.md
    ↓
Troubleshoot with README.md if needed

You want to CUSTOMIZE the addon?
    ↓
Read DEVELOPMENT.md
    ↓
Reference code in the .lua files
```

## 📞 Support Resources

**Documentation provided:**
- 6 comprehensive markdown guides
- 10 Lua source files with comments
- Inline code documentation
- Architecture diagrams (in DEVELOPMENT.md)
- Troubleshooting sections
- FAQ sections

**If you need help:**
1. Check the relevant document above
2. Search for keywords in README.md
3. Look at examples in QUICKREFERENCE.md
4. Check code comments in .lua files
5. Review troubleshooting sections

## ✨ Next Steps

**For Users:**
1. Read [HOWTO.md](HOWTO.md)
2. Install following [INSTALLATION.md](INSTALLATION.md)
3. Run your first Mythic+ key
4. Open `/sdd history` to see your stats
5. Bookmark [QUICKREFERENCE.md](QUICKREFERENCE.md)

**For Developers:**
1. Read [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)
2. Review code structure in [DEVELOPMENT.md](DEVELOPMENT.md)
3. Examine the Lua files
4. Plan your modifications
5. Test thoroughly

## 📝 Document Versions

- **Addon Version:** 1.0.0
- **Documentation Last Updated:** February 1, 2026
- **WoW Interface Version:** 110005 (11.0.5+)

---

**Welcome to Storm's Dungeon Data!** Choose your path above and get started.
