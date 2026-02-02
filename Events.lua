-- Mythic Plus Tracker - Event Module
-- Registers and handles WoW events
-- WoW 12.0+: Uses C_CombatLog namespace for event data access
-- Pre-12.0: Uses legacy COMBAT_LOG_EVENT_UNFILTERED (with deprecation fallbacks)

local MPT = StormsDungeonData
local Events = MPT.Events

-- Create event frame
local eventFrame = CreateFrame("Frame")
Events.frame = eventFrame

function Events:Initialize()
    -- Register for key events
    self.frame:RegisterEvent("ADDON_LOADED")
    self.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    self.frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    self.frame:RegisterEvent("LOOT_OPENED")
    
    -- Register for appropriate combat events based on WoW version
    if not MPT.DamageMeterCompat.IsWoW12Plus then
        -- Legacy API (pre-12.0)
        self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    else
        -- WoW 12.0+ uses damage meter events
        self.frame:RegisterEvent("COMBAT_METRICS_SESSION_NEW")
        self.frame:RegisterEvent("COMBAT_METRICS_SESSION_UPDATED")
        self.frame:RegisterEvent("COMBAT_METRICS_SESSION_END")
    end
    
    self.frame:SetScript("OnEvent", function(self, event, ...)
        Events:OnEvent(event, ...)
    end)
    
    print("|cff00ffaa[StormsDungeonData]|r Events module initialized")
end

function Events:OnEvent(event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
            if addonName == "StormsDungeonData" then
            MPT:Initialize()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:OnPlayerEnteringWorld()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        self:OnChallengeModeCompleted()
    elseif event == "LOOT_OPENED" then
        self:OnLootOpened()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Legacy API (pre-12.0)
        MPT.CombatLog:OnCombatLogEvent(...)
    elseif event == "COMBAT_METRICS_SESSION_NEW" then
        -- WoW 12.0+ event
        MPT.DamageMeterCompat:OnDamageMeterEvent(event, ...)
    elseif event == "COMBAT_METRICS_SESSION_UPDATED" then
        -- WoW 12.0+ event
        MPT.DamageMeterCompat:OnDamageMeterEvent(event, ...)
    elseif event == "COMBAT_METRICS_SESSION_END" then
        -- WoW 12.0+ event
        MPT.DamageMeterCompat:OnDamageMeterEvent(event, ...)
    end
end

function Events:OnPlayerEnteringWorld()
    -- Check if in a dungeon
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType == "party" then
        -- We're in a group dungeon
        MPT.CombatLog:StartTracking()
    else
        MPT.CombatLog:StopTracking()
    end
end

function Events:OnChallengeModeCompleted()
    print("|cff00ffaa[StormsDungeonData]|r Challenge mode completed!")
    
    -- Get completion info
    local level, affixes, isChampionChallenge, keystoneUpgrades, mapID, name = C_ChallengeMode.GetActiveKeystoneInfo()
    
    if level and mapID then
        -- Collect player statistics
        local playerStats = {}
        for i = 1, 5 do
            local unitID = "party" .. i
            if UnitExists(unitID) then
                local name = UnitName(unitID)
                local class = select(2, UnitClass(unitID))
                local role = UnitGroupRolesAssigned(unitID)
                
                table.insert(playerStats, MPT.Database:CreatePlayerStats(unitID, name, class, role))
            end
        end
        
        -- Also add player
        local playerName = UnitName("player")
        local playerClass = select(2, UnitClass("player"))
        local playerRole = UnitGroupRolesAssigned("player")
        table.insert(playerStats, MPT.Database:CreatePlayerStats("player", playerName, playerClass, playerRole))
        
        -- Store run info for later
        MPT.CurrentRunData = {
            dungeonID = mapID,
            dungeonName = name,
            keystoneLevel = level,
            affixes = affixes,
            keystoneUpgrades = keystoneUpgrades,
            completed = true,
            players = playerStats,
            startTime = MPT.CurrentRunData and MPT.CurrentRunData.startTime or time(),
        }
        
        print("|cff00ffaa[StormsDungeonData]|r Run data cached, waiting for loot chest...")
    end
end

function Events:OnLootOpened()
    -- Check if this is the mythic+ chest
    local numLootItems = GetNumLootItems()
    
    if numLootItems > 0 and MPT.CurrentRunData then
        -- Get the mythic+ chest (usually the last item)
        local isValidChest = false
        for i = 1, numLootItems do
            local _, _, quality = GetLootSlotInfo(i)
            if quality and quality >= 4 then  -- Epic or higher
                isValidChest = true
                break
            end
        end
        
        if isValidChest then
            -- Finalize run data
            local duration = time() - MPT.CurrentRunData.startTime
            MPT.CurrentRunData.duration = duration
            
            -- Get mob percentage from combat log
            if MPT.CombatLog.mobsKilled and MPT.CombatLog.mobsTotal > 0 then
                MPT.CurrentRunData.mobsKilled = MPT.CombatLog.mobsKilled
                MPT.CurrentRunData.mobsTotal = MPT.CombatLog.mobsTotal
                MPT.CurrentRunData.overallMobPercentage = (MPT.CombatLog.mobsKilled / MPT.CombatLog.mobsTotal) * 100
            end
            
            -- Create run record and save
            local runRecord = MPT.Database:CreateRunRecord(
                MPT.CurrentRunData.dungeonID,
                MPT.CurrentRunData.dungeonName,
                MPT.CurrentRunData.keystoneLevel,
                MPT.CurrentRunData.completed,
                duration,
                MPT.CurrentRunData.players
            )
            
            MPT.Database:SaveRun(runRecord)
            
            -- Show scoreboard
                if StormsDungeonDataDB.settings.autoShowScoreboard then
                MPT.UI:ShowScoreboard(runRecord)
            end
            
            print("|cff00ffaa[StormsDungeonData]|r Run saved!")
            
            -- Clean up
            MPT.CurrentRunData = nil
        end
    end
end

print("|cff00ffaa[StormsDungeonData]|r Events module loaded")
