-- Mythic Plus Tracker - Event Module
-- Registers and handles WoW events
-- WoW 12.0+: Uses C_CombatLog namespace for event data access
-- Pre-12.0: Uses legacy COMBAT_LOG_EVENT_UNFILTERED (with deprecation fallbacks)

local MPT = StormsDungeonData
local Events = MPT.Events

local function GetDungeonNameFromMapID(mapID)
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local name = C_ChallengeMode.GetMapUIInfo(mapID)
        if type(name) == "string" and name ~= "" then
            return name
        end
        if type(name) == "table" and name.name and name.name ~= "" then
            return name.name
        end
    end
end

local function NormalizeDurationSeconds(duration)
    if not duration then
        return nil
    end
    duration = tonumber(duration)
    if not duration then
        return nil
    end
    -- Some APIs return milliseconds.
    if duration > 100000 then
        return math.floor(duration / 1000)
    end
    return math.floor(duration)
end

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

    -- Always listen to CLEU for deaths/mob kills; WoW 12+ uses C_DamageMeter for damage/healing/interrupt totals.
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    
    -- Register for appropriate combat events based on WoW version
    if MPT.DamageMeterCompat.IsWoW12Plus then
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
        -- Use CombatLogGetCurrentEventInfo inside handler
        MPT.CombatLog:OnCombatLogEvent()
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

    local completionMapID, completionLevel, completionTime
    if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
        completionMapID, completionLevel, completionTime = C_ChallengeMode.GetCompletionInfo()
    end

    -- Fallback: active keystone info (signature varies by version)
    local level, affixes, _, keystoneUpgrades, mapID, name = nil, nil, nil, nil, nil, nil
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        level, affixes, _, keystoneUpgrades, mapID, name = C_ChallengeMode.GetActiveKeystoneInfo()
    end

    mapID = completionMapID or mapID
    level = completionLevel or level
    local durationSeconds = NormalizeDurationSeconds(completionTime)

    if mapID and level then
        name = name or GetDungeonNameFromMapID(mapID) or select(1, GetInstanceInfo())

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

        local startTime = (MPT.CurrentRunData and MPT.CurrentRunData.startTime) or time()
        if durationSeconds and durationSeconds > 0 then
            startTime = time() - durationSeconds
        end

        -- Store run info for later
        MPT.CurrentRunData = {
            dungeonID = mapID,
            dungeonName = name,
            keystoneLevel = level,
            affixes = affixes,
            keystoneUpgrades = keystoneUpgrades,
            completed = true,
            players = playerStats,
            startTime = startTime,
            completionTime = time(),
            completionDuration = durationSeconds,
            saved = false,
        }
        
        print("|cff00ffaa[StormsDungeonData]|r Run data cached, waiting for loot chest...")

        -- Fallback: if LOOT_OPENED doesn't fire or chest validation fails, save after a short delay.
        if C_Timer and C_Timer.After then
            C_Timer.After(45, function()
                if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                    Events:FinalizeRun("timeout")
                end
            end)
        end
    end
end

function Events:FinalizeRun(reason)
    if not MPT.CurrentRunData or MPT.CurrentRunData.saved then
        return
    end

    -- Finalize combat totals before saving/showing (matches how Details reads overall data)
    if MPT.CombatLog and MPT.CombatLog.useNewAPI then
        MPT.CombatLog:FinalizeNewAPIData()
    end

    local duration = MPT.CurrentRunData.completionDuration
    if not duration or duration <= 0 then
        duration = time() - (MPT.CurrentRunData.startTime or time())
    end
    MPT.CurrentRunData.duration = duration

    -- Get mob percentage from combat log
    if MPT.CombatLog.mobsKilled and MPT.CombatLog.mobsTotal > 0 then
        MPT.CurrentRunData.mobsKilled = MPT.CombatLog.mobsKilled
        MPT.CurrentRunData.mobsTotal = MPT.CombatLog.mobsTotal
        MPT.CurrentRunData.overallMobPercentage = (MPT.CombatLog.mobsKilled / MPT.CombatLog.mobsTotal) * 100
    end

    -- Copy tracked stats into player records (so UI and saved history match Details totals)
    local sumBase = 0
    if MPT.CurrentRunData.players then
        for _, p in ipairs(MPT.CurrentRunData.players) do
            local stats = (MPT.CombatLog and MPT.CombatLog:GetPlayerStats(p.name)) or {}
            p.damage = stats.damage or 0
            p.healing = stats.healing or 0
            p.interrupts = stats.interrupts or 0
            p.deaths = stats.deaths or 0

            if duration and duration > 0 then
                p.damagePerSecond = math.floor((p.damage or 0) / duration)
                p.healingPerSecond = math.floor((p.healing or 0) / duration)
                p.interruptsPerMinute = math.floor(((p.interrupts or 0) / duration) * 60)
            end

            -- Base contribution used for points (our calculation)
            local base = (p.damage or 0) + (p.healing or 0) + ((p.interrupts or 0) * 25000)
            p._pointsBase = base
            sumBase = sumBase + base
        end

        -- Points: 0-100 share of contribution, minus death penalty
        for _, p in ipairs(MPT.CurrentRunData.players) do
            local base = p._pointsBase or 0
            local points = 0
            if sumBase > 0 and base > 0 then
                points = math.floor(((base / sumBase) * 100) + 0.5)
            end
            points = math.max(0, points - ((p.deaths or 0) * 5))
            p.pointsGained = points
            p._pointsBase = nil
        end
    end

    local runRecord = MPT.Database:CreateRunRecord(
        MPT.CurrentRunData.dungeonID,
        MPT.CurrentRunData.dungeonName,
        MPT.CurrentRunData.keystoneLevel,
        MPT.CurrentRunData.completed,
        duration,
        MPT.CurrentRunData.players
    )

    runRecord.mobsKilled = MPT.CurrentRunData.mobsKilled or 0
    runRecord.mobsTotal = MPT.CurrentRunData.mobsTotal or 0
    runRecord.overallMobPercentage = MPT.CurrentRunData.overallMobPercentage or 0
    runRecord.finalizeReason = reason

    MPT.Database:SaveRun(runRecord)

    local autoShow = false
    if StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.autoShowScoreboard ~= nil then
        autoShow = StormsDungeonDataDB.settings.autoShowScoreboard
    else
        autoShow = true
    end

    if autoShow then
        MPT.UI:ShowScoreboard(runRecord)
    end

    MPT.CurrentRunData.saved = true
    print("|cff00ffaa[StormsDungeonData]|r Run saved!" .. (reason and (" (" .. reason .. ")") or ""))
    MPT.CurrentRunData = nil
end

function Events:OnLootOpened()
    -- Check if this is the mythic+ chest
    local numLootItems = GetNumLootItems()
    
    if numLootItems > 0 and MPT.CurrentRunData then
        -- Accept loot within a short window after completion; item quality checks are unreliable across seasons/rewards.
        local withinWindow = false
        if MPT.CurrentRunData.completionTime then
            withinWindow = (time() - MPT.CurrentRunData.completionTime) <= 600
        end

        local hasAnyItem = numLootItems and numLootItems > 0
        local looksLikeReward = false
        for i = 1, numLootItems do
            local _, _, quality = GetLootSlotInfo(i)
            if quality ~= nil then
                looksLikeReward = true
                break
            end
        end

        if withinWindow and hasAnyItem and (looksLikeReward or true) then
            self:FinalizeRun("loot")
        end
    end
end

print("|cff00ffaa[StormsDungeonData]|r Events module loaded")
