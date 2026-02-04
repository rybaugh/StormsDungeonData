-- Mythic Plus Tracker - Event Module
-- Registers and handles WoW events
-- WoW 12.0+: Uses C_CombatLog namespace for event data access
-- Pre-12.0: Uses legacy COMBAT_LOG_EVENT_UNFILTERED (with deprecation fallbacks)

local MPT = StormsDungeonData
local Events = MPT.Events

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(func, ...)
    if not ok then
        return nil
    end
    return a, b, c, d
end

local function GetPlayerSpecInfoSafe()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end

    local specID, specName, _, specIcon, role, classToken = GetSpecializationInfo(specIndex)
    if not specID then
        return nil
    end

    return {
        specID = specID,
        specName = specName,
        specIcon = specIcon,
        specRole = role,
        specClass = classToken,
    }
end

local function GetHeroTalentInfoSafe()
    -- Best-effort: API surface varies by patch; always guard with SafeCall.
    if not C_ClassTalents or not C_Traits then
        return nil
    end

    local function GetSubTreeInfoSafe(configID, subTreeID)
        if type(C_Traits.GetSubTreeInfo) ~= "function" then
            return nil
        end
        local info = SafeCall(C_Traits.GetSubTreeInfo, configID, subTreeID)
        if not info and subTreeID then
            info = SafeCall(C_Traits.GetSubTreeInfo, subTreeID)
        end
        return info
    end

    local function GetTreeInfoSafe(configID, treeID)
        if type(C_Traits.GetTreeInfo) ~= "function" then
            return nil
        end
        local info = SafeCall(C_Traits.GetTreeInfo, configID, treeID)
        if not info and treeID then
            info = SafeCall(C_Traits.GetTreeInfo, treeID)
        end
        return info
    end

    local configID = SafeCall(C_ClassTalents.GetActiveConfigID)
    if not configID and type(C_Traits.GetActiveConfigID) == "function" then
        configID = SafeCall(C_Traits.GetActiveConfigID)
    end

    local heroSpecID = SafeCall(C_ClassTalents.GetActiveHeroTalentSpec)
    if heroSpecID and type(C_ClassTalents.GetHeroTalentSpecInfo) == "function" then
        local heroInfo = SafeCall(C_ClassTalents.GetHeroTalentSpecInfo, heroSpecID)
        if type(heroInfo) == "table" then
            local heroTreeID = heroInfo.subTreeID or heroInfo.heroTreeID or heroSpecID
            local heroName = heroInfo.name or heroInfo.specName
            local heroIcon = heroInfo.icon or heroInfo.iconFileID or heroInfo.iconID
            if heroTreeID or heroName or heroIcon then
                return {
                    heroTreeID = heroTreeID,
                    heroName = heroName,
                    heroIcon = heroIcon,
                }
            end
        end
    end

    local subTreeID = heroSpecID
    if not subTreeID then
        subTreeID = SafeCall(C_ClassTalents.GetActiveHeroTalentTreeID)
    end

    if (not subTreeID or subTreeID == 0) and configID and type(C_ClassTalents.GetHeroTalentSpecsForClassSpec) == "function" then
        local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
        local specID = specIndex and type(GetSpecializationInfo) == "function" and select(1, GetSpecializationInfo(specIndex)) or nil
        if specID then
            local subTreeIDs = SafeCall(C_ClassTalents.GetHeroTalentSpecsForClassSpec, configID, specID)
            if type(subTreeIDs) == "table" then
                for _, id in ipairs(subTreeIDs) do
                    local info = GetSubTreeInfoSafe(configID, id)
                    if info and info.isActive then
                        subTreeID = id
                        break
                    end
                end
            end
        end
    end

    if configID and subTreeID then
        local subTreeInfo = GetSubTreeInfoSafe(configID, subTreeID)
        if type(subTreeInfo) == "table" then
            return {
                heroTreeID = subTreeID,
                heroName = subTreeInfo.name,
                heroIcon = subTreeInfo.icon or subTreeInfo.iconFileID or subTreeInfo.iconID,
            }
        end

        local treeInfo = GetTreeInfoSafe(configID, subTreeID)
        if type(treeInfo) == "table" then
            return {
                heroTreeID = subTreeID,
                heroName = treeInfo.name,
                heroIcon = treeInfo.icon or treeInfo.iconFileID or treeInfo.iconID,
            }
        end
    end

    return subTreeID and { heroTreeID = subTreeID } or nil
end

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

local function GetCompletionInfoCompat()
    if C_ChallengeMode and type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
        local info = C_ChallengeMode.GetChallengeCompletionInfo()
        if type(info) == "table" then
            return {
                mapID = info.mapChallengeModeID or info.mapID or info.challengeMapID,
                level = info.level or info.keystoneLevel,
                time = info.time or info.completionTime or info.duration,
                keystoneUpgrades = info.keystoneUpgradeLevels or info.keystoneUpgrades or info.upgrades,
            }
        end
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetCompletionInfo) == "function" then
        local a, b, c, d = C_ChallengeMode.GetCompletionInfo()
        if type(a) == "table" then
            return {
                mapID = a.mapChallengeModeID or a.mapID or a.challengeMapID or a.completionMapID,
                level = a.level or a.keystoneLevel or a.completionLevel,
                time = a.time or a.completionTime or a.duration,
                keystoneUpgrades = a.keystoneUpgrades or a.upgrades,
            }
        end
        return {
            mapID = a,
            level = b,
            time = c,
            keystoneUpgrades = d,
        }
    end

    return nil
end

local function CollectGroupPlayerStats()
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

    local playerName = UnitName("player")
    local playerClass = select(2, UnitClass("player"))
    local playerRole = UnitGroupRolesAssigned("player")
    table.insert(playerStats, MPT.Database:CreatePlayerStats("player", playerName, playerClass, playerRole))

    return playerStats
end

function Events:BuildRunDataFromActiveKeystone()
    local completion = GetCompletionInfoCompat()
    local completionMapID = completion and completion.mapID or nil
    local completionLevel = completion and completion.level or nil
    local completionTime = completion and completion.time or nil
    local completionKeystoneUpgrades = completion and completion.keystoneUpgrades or nil

    local level, affixes, _, keystoneUpgrades, mapID, name = nil, nil, nil, nil, nil, nil
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
        local a, b, c, d, e, f = C_ChallengeMode.GetActiveKeystoneInfo()
        if type(a) == "table" then
            level = a.level or a.keystoneLevel
            affixes = a.affixes
            keystoneUpgrades = a.keystoneUpgrades or a.upgrades
            mapID = a.mapChallengeModeID or a.mapID or a.challengeMapID
            name = a.name
        else
            level, affixes, _, keystoneUpgrades, mapID, name = a, b, c, d, e, f
        end
    end

    mapID = completionMapID or mapID
    if not mapID and C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        mapID = C_ChallengeMode.GetActiveChallengeMapID()
    end

    level = completionLevel or level
    keystoneUpgrades = completionKeystoneUpgrades or keystoneUpgrades
    local durationSeconds = NormalizeDurationSeconds(completionTime)

    if not mapID or not level then
        return false
    end

    name = name or GetDungeonNameFromMapID(mapID) or select(1, GetInstanceInfo())
    local playerStats = CollectGroupPlayerStats()

    local startTime = (MPT.CurrentRunData and MPT.CurrentRunData.startTime)
        or (MPT.CombatLog and MPT.CombatLog.startTime)
        or time()
    if durationSeconds and durationSeconds > 0 then
        startTime = time() - durationSeconds
    end

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

    return true
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
        -- If we just exited a completed key and it wasn't saved, force-save it.
        if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
            self:FinalizeRun("exit")
        end
        MPT.CombatLog:StopTracking()
    end
end

function Events:OnChallengeModeCompleted()
    -- Avoid re-creating run data if we already cached it and it isn't saved yet.
    if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
        return
    end

    local completion = GetCompletionInfoCompat()
    local completionMapID = completion and completion.mapID or nil
    local completionLevel = completion and completion.level or nil
    local completionTime = completion and completion.time or nil
    local completionKeystoneUpgrades = completion and completion.keystoneUpgrades or nil

    -- Fallback: active keystone info (signature varies by version)
    local level, affixes, _, keystoneUpgrades, mapID, name = nil, nil, nil, nil, nil, nil
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
        local a, b, c, d, e, f = C_ChallengeMode.GetActiveKeystoneInfo()
        if type(a) == "table" then
            level = a.level or a.keystoneLevel
            affixes = a.affixes
            keystoneUpgrades = a.keystoneUpgrades or a.upgrades
            mapID = a.mapChallengeModeID or a.mapID or a.challengeMapID
            name = a.name
        else
            level, affixes, _, keystoneUpgrades, mapID, name = a, b, c, d, e, f
        end
    end

    mapID = completionMapID or mapID
    if not mapID and C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        mapID = C_ChallengeMode.GetActiveChallengeMapID()
    end

    level = completionLevel or level
    keystoneUpgrades = completionKeystoneUpgrades or keystoneUpgrades
    local durationSeconds = NormalizeDurationSeconds(completionTime)

    if mapID and level then
        self.challengeRetryCount = 0
        name = name or GetDungeonNameFromMapID(mapID) or select(1, GetInstanceInfo())

        -- Collect player statistics
        local playerStats = CollectGroupPlayerStats()

        local startTime = (MPT.CurrentRunData and MPT.CurrentRunData.startTime)
            or (MPT.CombatLog and MPT.CombatLog.startTime)
            or time()
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
        
        print("|cff00ffaa[StormsDungeonData]|r Challenge mode completed!")
        print("|cff00ffaa[StormsDungeonData]|r Run data cached, waiting for loot chest...")

        -- Save/show shortly after completion even if LOOT_OPENED never fires.
        -- This fixes runs that reward via UI/mail and never open a loot window.
        if C_Timer and C_Timer.After then
            C_Timer.After(8, function()
                if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                    Events:FinalizeRun("completed")
                end
            end)
            -- Secondary safety net.
            C_Timer.After(45, function()
                if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                    Events:FinalizeRun("timeout")
                end
            end)
        end
    else
        -- Some clients return completion info slightly later. Retry a few times.
        if C_Timer and C_Timer.After then
            self.challengeRetryCount = (self.challengeRetryCount or 0) + 1
            if self.challengeRetryCount <= 5 then
                local delay = 1.5 * self.challengeRetryCount
                C_Timer.After(delay, function()
                    Events:OnChallengeModeCompleted()
                end)
                return
            end
        end
        print("|cff00ffaa[StormsDungeonData]|r Warning: could not read completion info (missing mapID/level)")
    end
end

function Events:FinalizeRun(reason)
    if not MPT.CurrentRunData then
        if not self:BuildRunDataFromActiveKeystone() then
            print("|cff00ffaa[StormsDungeonData]|r No pending run data to save")
            return false
        end
    end

    if MPT.CurrentRunData.saved then
        return false
    end

    if not MPT.CurrentRunData.completed then
        MPT.CurrentRunData.completed = true
        MPT.CurrentRunData.completionTime = time()
        if not MPT.CurrentRunData.startTime then
            MPT.CurrentRunData.startTime = (MPT.CombatLog and MPT.CombatLog.startTime) or time()
        end
        MPT.CurrentRunData.completionDuration = time() - (MPT.CurrentRunData.startTime or time())
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

    -- Persist the spec/hero talent that THIS character completed the run with.
    do
        local spec = GetPlayerSpecInfoSafe()
        if spec then
            runRecord.specID = spec.specID
            runRecord.specName = spec.specName
            runRecord.specIcon = spec.specIcon
            runRecord.specRole = spec.specRole
        end

        local hero = GetHeroTalentInfoSafe()
        if hero then
            runRecord.heroTreeID = hero.heroTreeID
            runRecord.heroName = hero.heroName
            runRecord.heroIcon = hero.heroIcon
        end
    end

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

    MPT.LastSavedRun = runRecord
    MPT.LastSavedRunTime = time()
    MPT.LastSavedRunShown = false
    MPT.LastSavedRunReason = reason

    -- Show scoreboard for loot/manual triggers, plus fallback for completion without loot window.
    if autoShow and (reason == "loot" or reason == "manual-loot" or reason == "manual" or reason == "completed" or reason == "timeout" or reason == "exit") then
        MPT.UI:ShowScoreboard(runRecord)
        MPT.LastSavedRunShown = true
    end

    MPT.CurrentRunData.saved = true
    print("|cff00ffaa[StormsDungeonData]|r Run saved!" .. (reason and (" (" .. reason .. ")") or ""))
    MPT.CurrentRunData = nil
    return true
end

function Events:OnLootOpened()
    -- Check if this is the mythic+ chest
    local numLootItems = GetNumLootItems()
    
    if numLootItems > 0 and not MPT.CurrentRunData then
        self:BuildRunDataFromActiveKeystone()
    end

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
    elseif numLootItems > 0 and MPT.LastSavedRun and not MPT.LastSavedRunShown then
        -- Run was already saved (auto/timeout/exit). If the chest is looted later, show the scoreboard now.
        local withinWindow = false
        if MPT.LastSavedRunTime then
            withinWindow = (time() - MPT.LastSavedRunTime) <= 600
        end
        if withinWindow then
            local autoShow = true
            if StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.autoShowScoreboard ~= nil then
                autoShow = StormsDungeonDataDB.settings.autoShowScoreboard
            end
            if autoShow then
                MPT.UI:ShowScoreboard(MPT.LastSavedRun)
                MPT.LastSavedRunShown = true
            end
        end
    end
end

-- Debug/testing helper: simulate a loot chest opening to finalize a pending run.
function Events:SimulateLootOpened()
    if not MPT.CurrentRunData then
        if MPT.LastSavedRun and not MPT.LastSavedRunShown then
            MPT.UI:ShowScoreboard(MPT.LastSavedRun)
            MPT.LastSavedRunShown = true
        else
            print("|cff00ffaa[StormsDungeonData]|r No pending run to finalize.")
        end
        return
    end
    if not MPT.CurrentRunData.completed then
        -- Treat as a manual chest open: mark completion now.
        MPT.CurrentRunData.completed = true
        MPT.CurrentRunData.completionTime = time()
        if not MPT.CurrentRunData.startTime then
            MPT.CurrentRunData.startTime = time()
        end
        MPT.CurrentRunData.completionDuration = time() - (MPT.CurrentRunData.startTime or time())
    end

    if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus then
        MPT.DamageMeterCompat:EnsureSessionID()
    end

    self:FinalizeRun("manual-loot")
end

print("|cff00ffaa[StormsDungeonData]|r Events module loaded")
