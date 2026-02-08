# Storm's Dungeon Data — Patch Notes

**Date:** February 7, 2025  

Summary of updates, features, and fixes from this session.

---

## Run completion & auto-save

- **Run not auto-saving at end of dungeon**  
  Completion and auto-save now use the same moment as RaiderIO: we hook **TopBannerManager_Show** (the “Run Complete” banner) and run completion logic + scheduled end-of-run auto-save there. We also use **CHALLENGE_MODE_COMPLETED** and **C_ChallengeMode.GetChallengeCompletionInfo()** with a next-frame retry so runs are saved reliably when the key is completed.

- **No dependency on Details**  
  Details is no longer required. Run completion and duration come from the WoW completion API and the completion banner hook only.

- **RaiderIO registered run end but we didn’t**  
  Fixed by hooking **TopBannerManager_Show** and triggering **OnChallengeModeCompleted()** and **ScheduleEndOfRunAutoSave("completion_banner")** so our addon registers completion at the same time as RaiderIO.

---

## Keystone level & manual save

- **Wrong key level on manual save (e.g. +12 run saved as +8)**  
  We now store the **keystone level at CHALLENGE_MODE_START** and use it when building run data. Priority: completion API level → stored-at-start level → GetActiveKeystoneInfo. The stored level is cleared when leaving the zone. If no completion/start level is available, we use run history for the same map so manual save after leaving can still get the correct level.

---

## UI: minimap, history, scoreboard

- **Minimap: only one of History or Scoreboard visible**  
  Right-click minimap: hide History then run manual save. Left-click: hide Scoreboard then show History. **ShowScoreboard** hides HistoryViewer and **HistoryViewer:Show** hides the Scoreboard so only one is visible at a time.

- **History: no Result column; show failed runs by red Time**  
  The Result column was removed. Time is shown in **red** when the run was over time (failed). A local **GetDungeonTimeLimitSeconds** is used in HistoryViewer for this display.

- **Scoreboard: total deaths**  
  The scoreboard **Totals** line now includes **Deaths** (from `runRecord.deathCount` or the sum of player deaths). `runRecord.deathCount` and `timeLost` are set in FinalizeRun.

---

## Over-time runs

- **Over-time runs marked as Failed, not Completed**  
  **GetDungeonTimeLimitSeconds(mapID)** uses the third return of **C_ChallengeMode.GetMapUIInfo(mapID)**. In **OnChallengeModeCompleted** and **BuildRunDataFromActiveKeystone**, `completed` is set from `runCompleted`, where `runCompleted` is false when `onTime == false` or when `durationSeconds > timeLimit`.

---

## Players vs pets & filtering

- **Pets saved instead of players**  
  In **CombatLog.lua**, we only add C_DamageMeter entries when **NormalizeUnitName(playerName)** is non-nil (name has a realm). In **Events.lua**, **NameHasRealm(name)** was added and we only add/rebuild players from stats when the name has a realm, so pets and non-player units are excluded.

---

## Role icons on scoreboard

- **Role icons added**  
  Each player row has a **role icon** (Tank / Healer / Damager) to the left of the name. The addon tries **SetAtlas** with several candidate atlas names (e.g. `roleicon-tank`), then falls back to the **UI-LFG-Icon-PortraitRoles** texture with the correct TexCoords. Name and rating buttons are laid out to leave space for the icon.

- **Role icon display fixes**  
  Multiple paths and TexCoord sets were tried (including per-role textures and PORTRAITROLES). The current logic uses atlas when available and the single PORTRAITROLES texture with Details-style coords otherwise. A temporary T/H/D letter fallback was removed so only proper Blizzard role icons (or nothing) are shown.

- **Role assignment: 1 tank, 1 healer, 3 damager**  
  The scoreboard enforces exactly **1 tank, 1 healer, 3 damager**. Roles are determined in this order:
  1. **Saved/selected role** from run data (`player.role` / `stats.role`) when it’s TANK, HEALER, or DAMAGER.
  2. **Spec role for the player** at completion when the group role was NONE: in **Events.lua**, **CollectGroupPlayerStats** now uses **GetSpecializationInfo(GetSpecialization())** for the player when **UnitGroupRolesAssigned("player")** is missing or NONE, so the role reflects the spec they played.
  3. **Fill missing slots only** (no inferring tank from interrupts):  
     - **Healer** (if needed): among players with no role, assign HEALER to the one with **highest healing**.  
     - **Tank** (if needed): assign TANK to the **first** remaining unassigned player (by list order).  
     - Everyone else with no role gets **DAMAGER**.

- **MVP uses same role**  
  MVP scoring uses the same assigned role (saved or filled) so tank/healer/damager weighting is consistent with the icons.

---

## Files touched (reference)

- **Events.lua** — Completion handling, **CollectGroupPlayerStats** (role from UnitGroupRolesAssigned + spec fallback for player), **EnsurePlayersFromStats** (realm filter), **OnChallengeModeCompleted**, **BuildRunDataFromActiveKeystone**, **GetDungeonTimeLimitSeconds**, **NameHasRealm**, FinalizeRun (deathCount/timeLost).
- **CombatLog.lua** — Filter C_DamageMeter merge by realm so only players are added.
- **Database.lua** — **CreatePlayerStats** stores `role`.
- **UI/ScoreboardFrame.lua** — Role icon texture/atlas, role assignment (saved first, then fill 1T/1H/3D), Totals deaths, MVP role.
- **UI/HistoryViewer.lua** — Result column removed, Time in red when over time, local **GetDungeonTimeLimitSeconds**.
- **Main.lua** — Minimap/Scoreboard/History visibility and fallbacks.

---

*Storm's Dungeon Data — Mythic+ run tracking, scoreboard, ratings, and history.*
