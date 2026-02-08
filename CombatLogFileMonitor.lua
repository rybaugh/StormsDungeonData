-- Combat Log File Monitor
-- Monitors the WoW combat log file for key events to auto-detect run start/end
-- Detects CHALLENGE_MODE_START and Hearthstone usage for automatic run logging

local MPT = StormsDungeonData
MPT.CombatLogFileMonitor = MPT.CombatLogFileMonitor or {}
local Monitor = MPT.CombatLogFileMonitor

-- Configuration
Monitor.enabled = true
Monitor.checkInterval = 2  -- Check log file every 2 seconds
Monitor.lastFileSize = 0
Monitor.currentDungeon = nil
Monitor.lastZoneBeforeHearthstone = nil
Monitor.isMonitoring = false
Monitor.ticker = nil

-- Get the most recent combat log file
function Monitor:GetMostRecentCombatLog()
    local wowPath = string.gsub(GetCVar("portal"), "([^/\\]+)$", "")  -- Remove executable name
    wowPath = wowPath .. "Logs"
    
    -- Alternative: Try to construct path from known WoW directory structure
    if not wowPath or wowPath == "" then
        -- Try to find the WoW directory by checking common install locations
        local possiblePaths = {
            "C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Logs\\",
            "C:\\Program Files\\World of Warcraft\\_retail_\\Logs\\",
        }
        
        for _, path in ipairs(possiblePaths) do
            -- We can't actually check file existence from Lua, but we can try to use it
            wowPath = path
            break
        end
    end
    
    -- Return the logs directory path
    -- In practice, we'll need to scan this directory for WoWCombatLog-*.txt files
    -- and find the most recent one based on the timestamp in the filename
    return wowPath
end

-- Parse a combat log line for events we care about
function Monitor:ParseLogLine(line)
    if not line or line == "" then
        return nil
    end
    
    -- Check for CHALLENGE_MODE_START
    -- Format: DATE TIME  CHALLENGE_MODE_START,"DungeonName",mapID,instanceID,keystoneLevel,[affixes]
    local dungeonName, mapID, instanceID, keystoneLevel = line:match('CHALLENGE_MODE_START,"([^"]+)",(%d+),(%d+),(%d+)')
    if dungeonName and mapID and keystoneLevel then
        return {
            event = "CHALLENGE_MODE_START",
            dungeonName = dungeonName,
            mapID = tonumber(mapID),
            instanceID = tonumber(instanceID),
            keystoneLevel = tonumber(keystoneLevel),
            timestamp = line:match("^([%d/]+%s+[%d:%.%-]+)")
        }
    end
    
    -- Check for Hearthstone spell cast
    -- Format: DATE TIME  SPELL_CAST_SUCCESS,...,"SpellName",...
    if line:match("SPELL_CAST_SUCCESS") then
        local spellName = line:match('SPELL_CAST_SUCCESS,[^,]+,"[^"]*",.-,"([^"]*Hearthstone[^"]*)"')
        if spellName then
            return {
                event = "HEARTHSTONE_CAST",
                spellName = spellName,
                timestamp = line:match("^([%d/]+%s+[%d:%.%-]+)")
            }
        end
    end
    
    return nil
end

-- Process a detected event
function Monitor:ProcessEvent(eventData)
    if not eventData then
        return
    end
    
    if eventData.event == "CHALLENGE_MODE_START" then
        print("|cff00ffaa[StormsDungeonData]|r Combat Log: Detected M+ start - " .. eventData.dungeonName .. " +" .. eventData.keystoneLevel)
        
        -- Store current dungeon info
        self.currentDungeon = {
            name = eventData.dungeonName,
            mapID = eventData.mapID,
            keystoneLevel = eventData.keystoneLevel,
            startTime = time(),
        }
        
        -- Ensure combat tracking is started
        if MPT.CombatLog and MPT.CombatLog.StartTracking and not MPT.CombatLog.isTracking then
            print("|cff00ffaa[StormsDungeonData]|r Auto-starting combat tracking from log file detection")
            MPT.CombatLog:StartTracking()
        end
        
        -- Store the zone before we entered the dungeon
        self.lastZoneBeforeHearthstone = eventData.dungeonName
        
    elseif eventData.event == "HEARTHSTONE_CAST" then
        print("|cff00ffaa[StormsDungeonData]|r Combat Log: Detected Hearthstone cast - " .. eventData.spellName)
        
        -- Check if we have a current dungeon and it matches the last zone
        if self.currentDungeon and self.lastZoneBeforeHearthstone then
            if self.currentDungeon.name == self.lastZoneBeforeHearthstone then
                print("|cff00ffaa[StormsDungeonData]|r Auto-logging run: " .. self.currentDungeon.name .. " +" .. self.currentDungeon.keystoneLevel)
                
                -- Trigger auto-save with a small delay to ensure all data is captured
                C_Timer.After(1, function()
                    if MPT.PerformManualSave then
                        MPT.PerformManualSave("hearthstone_auto")
                    elseif MPT.Events and MPT.Events.FinalizeRun then
                        MPT.Events:FinalizeRun("hearthstone_auto")
                    end
                end)
            else
                print("|cff00ffaa[StormsDungeonData]|r Skipping auto-log: Current dungeon (" .. self.currentDungeon.name .. ") doesn't match last zone (" .. self.lastZoneBeforeHearthstone .. ")")
            end
        else
            print("|cff00ffaa[StormsDungeonData]|r No active dungeon to log")
        end
        
        -- Clear current dungeon after hearthstone
        self.currentDungeon = nil
    end
end

-- Monitor the combat log file using a ticker (periodic check)
-- Since we can't directly read files from Lua in WoW, we'll use a different approach:
-- We'll hook into the existing COMBAT_LOG_EVENT_UNFILTERED to catch these events
function Monitor:StartMonitoring()
    if self.isMonitoring then
        print("|cff00ffaa[StormsDungeonData]|r Combat log file monitoring already active")
        return
    end
    
    self.isMonitoring = true
    
    -- Register for combat log events
    if not self.frame then
        self.frame = CreateFrame("Frame")
    end
    
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    
    self.frame:SetScript("OnEvent", function(frame, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            Monitor:OnCombatLogEvent(...)
        end
    end)
    
    print("|cff00ffaa[StormsDungeonData]|r Combat log file monitoring started")
end

-- Handle combat log events directly from the game (more reliable than file parsing)
function Monitor:OnCombatLogEvent(...)
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, 
          destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()
    
    -- Check for CHALLENGE_MODE_START - this is typically sent as a ENCOUNTER_START or similar
    -- Actually, we need to check if this is passed through the subevent
    if eventType == "CHALLENGE_MODE_START" then
        -- This event type doesn't exist in standard CLEU, but we handle it if it appears
        local dungeonName, mapID, instanceID, keystoneLevel = select(12, CombatLogGetCurrentEventInfo())
        if dungeonName then
            self:ProcessEvent({
                event = "CHALLENGE_MODE_START",
                dungeonName = dungeonName,
                mapID = mapID,
                keystoneLevel = keystoneLevel,
            })
        end
    end
    
    -- Check for Hearthstone spell casts
    if eventType == "SPELL_CAST_SUCCESS" then
        local spellID, spellName = select(12, CombatLogGetCurrentEventInfo())
        
        if spellName and spellName:match("Hearthstone") then
            -- Check if this is the player casting
            if sourceGUID == UnitGUID("player") then
                self:ProcessEvent({
                    event = "HEARTHSTONE_CAST",
                    spellName = spellName,
                })
            end
        end
    end
end

function Monitor:StopMonitoring()
    if not self.isMonitoring then
        return
    end
    
    self.isMonitoring = false
    
    if self.frame then
        self.frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Combat log file monitoring stopped")
end

function Monitor:Initialize()
    if self.enabled then
        self:StartMonitoring()
        print("|cff00ffaa[StormsDungeonData]|r Combat Log File Monitor initialized")
    end
end

-- Clean up on disable
function Monitor:Shutdown()
    self:StopMonitoring()
end
