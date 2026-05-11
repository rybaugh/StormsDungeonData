-- Mythic Plus Tracker - Core Module
-- Main namespace and initialization

StormsDungeonData = StormsDungeonData or {}
local MPT = StormsDungeonData

-- Version info
MPT.VERSION = "1.4"
MPT.NAME = "Storm's Dungeon Data"

-- Core modules
MPT.Database = MPT.Database or {}
MPT.Utils = MPT.Utils or {}
MPT.Events = MPT.Events or {}
MPT.DamageMeterCompat = MPT.DamageMeterCompat or {}
MPT.CombatLog = MPT.CombatLog or {}
MPT.CombatLogFileMonitor = MPT.CombatLogFileMonitor or {}
MPT.ReporterElection = MPT.ReporterElection or {}
MPT.PlayerTooltip = MPT.PlayerTooltip or {}
MPT.LFGRatingIndicator = MPT.LFGRatingIndicator or {}
MPT.UI = MPT.UI or {}

-- Settings
MPT.Settings = {
    autoShowScoreboard = true,
    trackAllStats = true,
}

-- Initialize addon
function MPT:Initialize()
    -- Ensure Logger is available (it's loaded from Logger.lua in toc)
    if not self.Log then
        print("|cffff4444[StormsDungeonData]|r ERROR: Logger not loaded!")
        return
    end
    
    self.Log:Info("=== StormsDungeonData Initialize() starting ===")
    
    -- Initialize compatibility layer first
    self.DamageMeterCompat:Initialize()
    
    -- Load database
    if not StormsDungeonDataDB and MythicPlusTrackerDB then
        StormsDungeonDataDB = MythicPlusTrackerDB
    end
    if not StormsDungeonDataDB then
        StormsDungeonDataDB = self.Database:CreateDefaultDB()
    end
    
    -- Initialize modules
    self.Database:Initialize()
    self.Events:Initialize()
    self.CombatLog:Initialize()
    self.UI:Initialize()
    
    -- Initialize combat log file monitor for auto-detection
    if self.CombatLogFileMonitor and self.CombatLogFileMonitor.Initialize then
        self.CombatLogFileMonitor:Initialize()
    end

    -- Initialize reporter election (addon-message based auto-report delegation)
    if self.ReporterElection and self.ReporterElection.Initialize then
        self.ReporterElection:Initialize()
    end

    -- Initialize player tooltip rating display
    if self.PlayerTooltip and self.PlayerTooltip.Initialize then
        self.PlayerTooltip:Initialize()
    end

    -- Initialize LFG rating indicator for Group Finder tooltips
    if self.LFGRatingIndicator and self.LFGRatingIndicator.Initialize then
        self.LFGRatingIndicator:Initialize()
    end

    print("|cff00ffaaStorm's Dungeon Data loaded!|r")
end

-- Get current player info
function MPT:GetPlayerInfo()
    return {
        name = UnitName("player"),
        realm = GetRealmName(),
        class = select(2, UnitClass("player")),
        level = UnitLevel("player"),
    }
end

-- True if we are currently inside a Mythic+ dungeon (party instance, difficulty 8).
-- Use this as well as InMythicPlus so the live tracker works when joining in progress
-- or when CHALLENGE_MODE_START didn't fire for this client.
function MPT:IsInMythicPlusDungeon()
    local _, instanceType, difficultyID = GetInstanceInfo()
    return instanceType == "party" and difficultyID == 8
end

