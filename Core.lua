-- Mythic Plus Tracker - Core Module
-- Main namespace and initialization

StormsDungeonData = StormsDungeonData or {}
local MPT = StormsDungeonData

-- Version info
MPT.VERSION = "1.1.8"
MPT.NAME = "Storm's Dungeon Data"

-- Core modules
MPT.Database = MPT.Database or {}
MPT.Utils = MPT.Utils or {}
MPT.Events = MPT.Events or {}
MPT.DamageMeterCompat = MPT.DamageMeterCompat or {}
MPT.CombatLog = MPT.CombatLog or {}
MPT.UI = MPT.UI or {}

-- Settings
MPT.Settings = {
    autoShowScoreboard = true,
    trackAllStats = true,
}

-- Initialize addon
function MPT:Initialize()
    print("|cff00ffaaStorm's Dungeon Data|r v" .. self.VERSION .. " loaded!")
    print("|cff00ffaa[StormsDungeonData]|r WoW Version: " .. select(4, GetBuildInfo()))
    
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
    
    print("|cff00ffaaType /sdd for options|r")
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

print("|cff00ffaa[StormsDungeonData]|r Core module loaded")
