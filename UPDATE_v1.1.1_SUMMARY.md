# StormsDungeonData v1.1.1 - WoW 12.0 Compliance + Test Mode

## 🎯 What's New

This update brings **full WoW 12.0 compatibility** and adds **test mode for offline testing**.

### ✨ Key Features

| Feature | Status | Details |
| --- | --- | --- |
| WoW 12.0 API Support | ✅ | Full C_CombatLog and C_DamageMeter support |
| Test Mode | ✅ | `/sdd test` simulates dungeons without keys |
| Restriction Handling | ✅ | Respects WoW 12.0 addon security restrictions |
| Backward Compatibility | ✅ | Works with WoW 11.x AND 12.0+ |
| Database Compatibility | ✅ | Old data preserved, no migration needed |
| Documentation | ✅ | 5 new guides covering WoW 12.0 changes |

---

## 🚀 Quick Start

### Install/Update
1. Extract addon to `World of Warcraft\_retail_\Interface\AddOns\StormsDungeonData\`
2. Restart WoW
3. Type `/sdd help` to see commands

### Test Without Real Dungeons
```
/sdd test
```

This creates a realistic test run with:
- Random M+2 to M+20 dungeon
- 1-5 realistic party members
- Authentic damage/healing/interrupt stats
- Immediate scoreboard display
- Automatic history saving

### View Your Runs
```
/sdd history    # Open history viewer
/sdd status     # Check addon status
```

---

## 📋 Files Changed

### Core Changes (5 files)

**CombatLog.lua**
- Updated headers to reference `C_CombatLog` namespace
- Clarified WoW 12.0+ data flow using C_DamageMeter
- Comments about `C_CombatLog.GetCurrentEventInfo()` usage

**Events.lua**
- Conditional event registration based on WoW version
- Pre-12.0: COMBAT_LOG_EVENT_UNFILTERED
- 12.0+: COMBAT_METRICS_SESSION_NEW/UPDATED/END

**DamageMeterCompat.lua**
- Enhanced documentation about C_CombatLog compatibility
- Already had full C_DamageMeter API support
- Already had restriction state checking

**Main.lua**
- Added `/sdd test` command
- Updated help text
- Routes to new TestMode module

**StormsDungeonData.toc**
- Version: 1.1.0 → 1.1.1
- Added TestMode.lua to load order
- Interface: 120005 (WoW 12.0+)

### New Files (2)

**TestMode.lua** (250+ lines)
- `GenerateDungeonData()` - Random M+2-20 dungeons
- `GeneratePlayerStats()` - Realistic party member stats
- `SimulateDungeonRun()` - Full simulation with saving

**WOW12_API_MIGRATION.md** (500+ lines)
- Complete guide to WoW 12.0 API changes
- How addon implements each change
- Migration guide for other addon developers
- Secret values and restriction system explanation
- Troubleshooting FAQ

### Documentation Updates (3 files)

**QUICKREFERENCE.md**
- Added `/sdd test` command
- New "Test Mode" section with examples
- New "Test Without Real Dungeons" scenario
- Updated file list with new modules

**WOW12_UPDATE_SUMMARY_v1.1.1.md** (NEW - 600+ lines)
- Detailed file-by-file changes
- Before/after code comparisons
- Installation and upgrade instructions
- Testing procedures
- API compatibility matrix

**WOW12_COMPATIBILITY.md**
- Referenced from new documentation

---

## 🧪 Test Mode Usage

### Basic Usage
```
/sdd test              # Generate random test run
/sdd test              # Run again for different dungeon
/sdd test              # And again, etc.
/sdd history           # View all generated runs
```

### What Gets Generated
Each test run includes:
- **Dungeon**: Random M+2 to M+20 difficulty
- **Duration**: 20-45 minutes (realistic timing)
- **Party**: 1-5 members with roles
- **Damage**: 50,000-150,000 per DPS
- **Healing**: 30,000-100,000 per healer
- **Interrupts**: 2-8 per player
- **Deaths**: ~5% chance per player

### Perfect For
✅ Testing without M+ keys  
✅ UI development and testing  
✅ Database verification  
✅ Performance testing  
✅ Screenshots and demos  

---

## 🔧 Technical Details

### WoW 12.0 Compatibility

**Version Detection**
```lua
local IsWoW12Plus = C_DamageMeter ~= nil
```

**Event Handling**
- Pre-12.0: Registers `COMBAT_LOG_EVENT_UNFILTERED`
- 12.0+: Registers `COMBAT_METRICS_SESSION_NEW/UPDATED/END`

**Data Collection**
- Pre-12.0: Real-time event parsing
- 12.0+: Session-based data via `C_DamageMeter` API

**Restrictions**
- Checks `C_RestrictedActions` for:
  - Combat restrictions
  - Encounter restrictions
  - Challenge mode restrictions
  - PvP restrictions
  - Map restrictions

### Database Format
- ✅ Unchanged from v1.0.0
- ✅ No migration needed
- ✅ Old runs preserved
- ✅ Works across versions

---

## 📚 Documentation Guide

### For Users
Start with: **QUICKREFERENCE.md**
- Commands and usage
- Feature overview
- Common scenarios

Then read: **WOW12_UPDATE_GUIDE.md**
- What changed in WoW 12.0
- How addon handles it
- Architecture overview

### For Developers
Start with: **WOW12_API_MIGRATION.md**
- Complete API change reference
- Implementation patterns
- Migration guide for other addons

Then read: **DEVELOPMENT.md**
- Code architecture
- How to extend addon
- Best practices

### For Troubleshooting
Check: **WOW12_COMPATIBILITY.md**
- Technical deep dive
- Known issues (none currently)
- FAQ

---

## ✅ Verification Checklist

After installation, verify:

```
/sdd help           # Shows all commands including /sdd test
/sdd status         # Confirms version detection
/sdd test           # Creates test run successfully
/sdd history        # Shows saved runs
/sdd help           # Tests all command functionality
```

Expected output:
- Help text includes `/sdd test`
- Status shows WoW version (11.x or 12.0+)
- Test creates realistic run data
- History viewer loads saved runs
- All commands work without errors

---

## 🔄 Update Path

### From v1.1.0 → v1.1.1
1. Download new addon files
2. Backup `StormsDungeonDataDB.lua` (optional, for safety)
3. Replace addon folder
4. Restart WoW
5. Old database automatically loads
6. Test with `/sdd test`

**No database reset needed!**

### From v1.0.0 → v1.1.1
1. All old runs preserved
2. New features (test mode) available immediately
3. Existing commands work as before
4. DamageMeterCompat auto-detects WoW version

---

## 📊 Compatibility Matrix

| Feature | WoW 11.x | WoW 12.0+ |
| --- | --- | --- |
| Combat Log | ✅ COMBAT_LOG_EVENT_UNFILTERED | ✅ C_DamageMeter API |
| Stat Collection | ✅ Real-time parsing | ✅ Session-based |
| Restriction Check | ❌ N/A | ✅ Implemented |
| Test Mode | ✅ `/sdd test` works | ✅ `/sdd test` works |
| Database | ✅ Compatible | ✅ Compatible |
| Scoreboard | ✅ Works | ✅ Works |
| History Viewer | ✅ Works | ✅ Works |

---

## 🐛 Troubleshooting

### "Nothing showing in history"
→ Run actual dungeon or use `/sdd test` to generate data

### "Test runs showing zero stats"
→ Re-run `/sdd test` - stats are randomized per run

### "Different WoW version than expected"
→ Check WoW installation version
→ Verify game is fully updated
→ Type `/sdd status` to confirm

### "Database missing after update"
→ Check SavedVariables location:
  - Windows: `World of Warcraft\_retail_\WTF\Account\[Account]\SavedVariables\StormsDungeonDataDB.lua`
→ Should exist automatically

### "Errors when running dungeon"
→ Check `/sdd status` output
→ Verify WoW client is updated to 12.0+
→ Check error log in WoW Errors folder

---

## 📝 What's Inside

### Total Files
- **11 Lua modules** (core + UI + test)
- **12 Documentation files** (guides + references)

### Code Quality
- ✅ Fully commented
- ✅ Error handling included
- ✅ No external dependencies
- ✅ Backward compatible
- ✅ Performance optimized

### Size
- **Total addon**: ~100 KB
- **Documentation**: ~50 KB
- **Test data**: Generated on demand

---

## 🎓 Learning Resources

### Understand WoW 12.0 Changes
1. Read: **WOW12_API_MIGRATION.md** (technical)
2. Review: **WOW12_COMPATIBILITY.md** (implementation)
3. Explore: **DamageMeterCompat.lua** (reference code)

### Learn Addon Development
1. Read: **DEVELOPMENT.md** (architecture)
2. Study: **Core.lua** (initialization)
3. Examine: **CombatLog.lua** (event handling)
4. Review: **UI/ScoreboardFrame.lua** (UI code)

### Contribute / Extend
1. Check: **CODE_OF_CONDUCT.md**
2. Follow: **Contributing guidelines**
3. Test: Use `/sdd test` for validation
4. Document: Update relevant .md files

---

## 📊 Statistics

### Code Metrics
- CombatLog.lua: ~260 lines (WoW 12.0 compatible)
- TestMode.lua: ~250 lines (NEW)
- DamageMeterCompat.lua: ~260 lines (existing)
- Total Lua code: ~2,500 lines

### Documentation
- WOW12_API_MIGRATION.md: ~500 lines
- WOW12_UPDATE_SUMMARY_v1.1.1.md: ~600 lines
- QUICKREFERENCE.md: ~280 lines (updated)
- Total documentation: ~2,000 lines

---

## 🚀 Next Steps

### For Users
1. ✅ Update addon
2. ✅ Type `/sdd test` to verify installation
3. ✅ Run actual dungeons when ready
4. ✅ Check `/sdd history` for saved runs

### For Developers
1. ✅ Review **WOW12_API_MIGRATION.md**
2. ✅ Study **TestMode.lua** implementation
3. ✅ Check **DamageMeterCompat.lua** for API patterns
4. ✅ Extend with your own features

### For Contributors
1. ✅ Report bugs via issue tracker
2. ✅ Suggest features for future versions
3. ✅ Help improve documentation
4. ✅ Submit pull requests

---

## ❓ FAQ

**Q: Will this break my existing data?**
A: No! Database format is unchanged. All old runs preserved.

**Q: Can I use this on WoW 11.x?**
A: Yes! Addon auto-detects version and uses appropriate APIs.

**Q: How realistic is test mode?**
A: Very! Damage ranges from 50k-150k, healing 30k-100k, interrupts 2-8, deaths ~5%.

**Q: Can I use test mode with real dungeons?**
A: Yes! Both work together. Test mode is just easier for offline testing.

**Q: Where's my database?**
A: Automatic SavedVariables. Check WTF folder or use `/sdd history`.

**Q: How do I report bugs?**
A: Check GitHub issues or contact maintainers.

**Q: Can I contribute?**
A: Yes! See CODE_OF_CONDUCT.md and DEVELOPMENT.md.

---

## 🎉 Summary

**StormsDungeonData v1.1.1** provides:
- ✅ Full WoW 12.0 API compliance
- ✅ Test mode for offline testing
- ✅ Backward compatibility with WoW 11.x
- ✅ Comprehensive documentation
- ✅ Zero breaking changes
- ✅ All existing features preserved

**Status**: Production Ready ✅

---

**Version**: 1.1.1  
**Released**: February 1, 2026  
**Compatibility**: WoW 11.x and 12.0+  
**License**: MIT

**Need Help?** Check QUICKREFERENCE.md or WOW12_API_MIGRATION.md
