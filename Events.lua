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

local function NormalizeUnitName(name)
    if type(name) ~= "string" then
        return nil
    end
    local short = name:match("^([^%-]+)%-")
    return short or name
end

local function GetDetailsSegmentCount(details)
    if not details then
        return 0
    end

    local count = nil

    local a = SafeCall(details.GetCombatSegments, details)
    if type(a) == "number" then
        count = a
    elseif type(a) == "table" then
        count = #a
    end

    if not count then
        local b = SafeCall(details.GetNumCombatSegments, details)
        if type(b) == "number" then
            count = b
        end
    end

    if not count then
        local c = SafeCall(details.GetCombatSegmentsAmount, details)
        if type(c) == "number" then
            count = c
        end
    end

    if not count and type(details.segments) == "table" then
        count = #details.segments
    end

    if not count and type(details.combat_id) == "number" then
        count = details.combat_id
    end

    if not count then
        count = 25
    end

    if count < 0 then
        count = 0
    end

    return count
end

local function CombatHasAnyTotals(combat)
    if not combat or type(combat.GetContainer) ~= "function" then
        return false
    end

    local damageContainer = combat:GetContainer(_G.DETAILS_ATTRIBUTE_DAMAGE or 1)
    if damageContainer and type(damageContainer.ListActors) == "function" then
        for _, actor in damageContainer:ListActors() do
            if actor and tonumber(actor.total) and actor.total > 0 then
                return true
            end
        end
    end

    local healContainer = combat:GetContainer(_G.DETAILS_ATTRIBUTE_HEAL or 2)
    if healContainer and type(healContainer.ListActors) == "function" then
        for _, actor in healContainer:ListActors() do
            if actor and tonumber(actor.total) and actor.total > 0 then
                return true
            end
        end
    end

    local miscContainer = combat:GetContainer(_G.DETAILS_ATTRIBUTE_MISC or 4)
    if miscContainer and type(miscContainer.ListActors) == "function" then
        for _, actor in miscContainer:ListActors() do
            local interrupts = actor and (actor.interrupt or actor.interrupts or actor.interrupt_amount or actor.interrupts_amount)
            if interrupts and tonumber(interrupts) and tonumber(interrupts) > 0 then
                return true
            end
        end
    end

    return false
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

    if subTreeID and subTreeID ~= 0 then
        local heroName, heroIcon
        
        -- Try with configID first
        if configID then
            local subTreeInfo = GetSubTreeInfoSafe(configID, subTreeID)
            if type(subTreeInfo) == "table" then
                heroName = subTreeInfo.name
                heroIcon = subTreeInfo.icon or subTreeInfo.iconFileID or subTreeInfo.iconID
            end
            
            if not heroIcon then
                local treeInfo = GetTreeInfoSafe(configID, subTreeID)
                if type(treeInfo) == "table" then
                    heroName = heroName or treeInfo.name
                    heroIcon = treeInfo.icon or treeInfo.iconFileID or treeInfo.iconID
                end
            end
        end
        
        -- Try without configID if we still don't have an icon
        if not heroIcon then
            local subTreeInfo = GetSubTreeInfoSafe(nil, subTreeID)
            if type(subTreeInfo) == "table" then
                heroName = heroName or subTreeInfo.name
                heroIcon = subTreeInfo.icon or subTreeInfo.iconFileID or subTreeInfo.iconID
            end
            
            if not heroIcon then
                local treeInfo = GetTreeInfoSafe(nil, subTreeID)
                if type(treeInfo) == "table" then
                    heroName = heroName or treeInfo.name
                    heroIcon = treeInfo.icon or treeInfo.iconFileID or treeInfo.iconID
                end
            end
        end
        
        -- Try GetHeroTalentSpecInfo as last resort
        if not heroIcon and type(C_ClassTalents.GetHeroTalentSpecInfo) == "function" then
            local heroInfo = SafeCall(C_ClassTalents.GetHeroTalentSpecInfo, subTreeID)
            if type(heroInfo) == "table" then
                heroName = heroName or heroInfo.name or heroInfo.specName
                heroIcon = heroInfo.icon or heroInfo.iconFileID or heroInfo.iconID
            end
        end
        
        return {
            heroTreeID = subTreeID,
            heroName = heroName,
            heroIcon = heroIcon,
        }
    end

    return nil
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

-- Based on RaiderIO's implementation for accurate enemy forces tracking
-- Handles both quantityString and quantity/totalQuantity formats
local function GetEnemyForcesProgress()
    if not C_Scenario or not C_ScenarioInfo then
        print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: C_Scenario or C_ScenarioInfo not available")
        return nil
    end
    if type(C_Scenario.GetStepInfo) ~= "function" or type(C_ScenarioInfo.GetCriteriaInfo) ~= "function" then
        print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: Required API functions not available")
        return nil
    end

    local _, _, numCriteria = C_Scenario.GetStepInfo()
    if not numCriteria or numCriteria <= 1 then
        print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: No scenario criteria found (numCriteria=" .. tostring(numCriteria) .. ")")
        return nil
    end
    
    print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: Found " .. numCriteria .. " scenario criteria")

    -- The last criteria is always the enemy forces (trash)
    local criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(numCriteria)
    if type(criteriaInfo) ~= "table" then
        print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: No criteria info available")
        return nil
    end

    -- RaiderIO method: Try quantityString first (e.g., "95%"), then fall back to quantity*totalQuantity/100
    local quantityString = criteriaInfo.quantityString
    local quantity = criteriaInfo.quantity
    local totalQuantity = criteriaInfo.totalQuantity
    
    local current, total, percent
    
    print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: quantityString='" .. tostring(quantityString) .. "', quantity=" .. tostring(quantity) .. ", totalQuantity=" .. tostring(totalQuantity))

    -- Method 1: Parse quantityString if available (e.g., "95%" -> 95)
    if quantityString and type(quantityString) == "string" then
        -- Try to extract percentage (remove % sign)
        local percentMatch = quantityString:match("([%d%.]+)%%")
        if percentMatch then
            percent = tonumber(percentMatch)
            print("|cff00ffaa[SDD]|r Parsed percent from quantityString: " .. tostring(percent) .. "%")
        else
            -- Try to extract "current/total" format
            local a, b = quantityString:match("([%d%.]+)%s*/%s*([%d%.]+)")
            if a and b then
                current = tonumber(a)
                total = tonumber(b)
                if current and total and total > 0 then
                    percent = (current / total) * 100
                end
                print("|cff00ffaa[SDD]|r Parsed from quantityString: " .. tostring(current) .. "/" .. tostring(total))
            end
        end
    end
    
    -- Method 2: Calculate from quantity and totalQuantity (RaiderIO formula)
    if not percent and quantity and totalQuantity and totalQuantity > 0 then
        -- RaiderIO uses: trash = quantity*totalQuantity/100
        -- This suggests quantity is a percentage (0-100) and totalQuantity is the actual count
        current = (quantity * totalQuantity) / 100
        total = totalQuantity
        percent = quantity -- quantity is already the percentage
        print("|cff00ffaa[SDD]|r Calculated using RaiderIO method: current=" .. tostring(current) .. ", total=" .. tostring(total) .. ", percent=" .. tostring(percent) .. "%")
    end

    -- Ensure percent is within bounds
    if percent then
        if percent > 100 then
            percent = 100
        elseif percent < 0 then
            percent = 0
        end
    end

    if not current and not total and not percent then
        print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: No valid data found")
        return nil
    end

    -- Calculate missing values if we have percent and total
    if percent and total and not current then
        current = (percent * total) / 100
    end
    
    -- Calculate missing values if we have current and total
    if current and total and not percent and total > 0 then
        percent = (current / total) * 100
    end

    print("|cff00ffaa[SDD]|r GetEnemyForcesProgress: Returning current=" .. tostring(current or 0) .. ", total=" .. tostring(total or 0) .. ", percent=" .. tostring(percent))
    return {
        current = current or 0,
        total = total or 0,
        percent = percent,
    }
end

local function GetDetailsMythicDungeonOverallCombat()
    local details = _G.Details
    if not details or type(details.GetCombat) ~= "function" then
        return nil
    end

    if type(details.GetMythicDungeonOverallCombat) == "function" then
        local combat = details:GetMythicDungeonOverallCombat()
        if combat then
            return combat
        end
    end

    local overallId = _G.DETAILS_SEGMENTID_OVERALL or -1
    local overallCombat = details:GetCombat(overallId)
    local overallType = _G.DETAILS_SEGMENTTYPE_MYTHICDUNGEON_OVERALL or 12
    if overallCombat then
        if overallCombat.IsMythicDungeonOverall and overallCombat:IsMythicDungeonOverall() then
            return overallCombat
        end
        if overallCombat.GetCombatType and overallCombat:GetCombatType() == overallType then
            return overallCombat
        end
    end

    local bestCombat
    local bestEndTime
    local segmentCount = GetDetailsSegmentCount(details)
    if segmentCount <= 0 then
        segmentCount = 25
    end
    for i = 1, segmentCount do
        local combat = details:GetCombat(i)
        if combat then
            local isOverall = (combat.IsMythicDungeonOverall and combat:IsMythicDungeonOverall())
                or (combat.GetCombatType and combat:GetCombatType() == overallType)

            if isOverall then
                local endTime
                if combat.GetDate then
                    local _, e = combat:GetDate()
                    endTime = e
                end
                if endTime and (not bestEndTime or endTime > bestEndTime) then
                    bestEndTime = endTime
                    bestCombat = combat
                elseif not bestCombat then
                    bestCombat = combat
                end
            end
        end
    end

    if bestCombat then
        return bestCombat
    end

    if overallCombat and CombatHasAnyTotals(overallCombat) then
        return overallCombat
    end

    if details.tabela_overall and CombatHasAnyTotals(details.tabela_overall) then
        return details.tabela_overall
    end

    return nil
end

local function GetDetailsOverallPlayerStats()
    local combat = GetDetailsMythicDungeonOverallCombat()
    if not combat or type(combat.GetContainer) ~= "function" then
        return nil
    end

    local statsByName = {}

    local function Ensure(name)
        local key = NormalizeUnitName(name) or name
        if not key then
            return nil
        end
        if not statsByName[key] then
            statsByName[key] = { damage = 0, healing = 0, interrupts = 0 }
        end
        return statsByName[key]
    end

    local function ExtractName(actor)
        return actor and (actor.name or actor.nome or actor.Name)
    end

    local damageContainer = combat:GetContainer(_G.DETAILS_ATTRIBUTE_DAMAGE or 1)
    if damageContainer and type(damageContainer.ListActors) == "function" then
        for _, actor in damageContainer:ListActors() do
            local name = ExtractName(actor)
            local entry = Ensure(name)
            if entry then
                entry.damage = tonumber(actor.total) or 0
            end
        end
    end

    local healContainer = combat:GetContainer(_G.DETAILS_ATTRIBUTE_HEAL or 2)
    if healContainer and type(healContainer.ListActors) == "function" then
        for _, actor in healContainer:ListActors() do
            local name = ExtractName(actor)
            local entry = Ensure(name)
            if entry then
                entry.healing = tonumber(actor.total) or 0
            end
        end
    end

    local miscContainer = combat:GetContainer(_G.DETAILS_ATTRIBUTE_MISC or 4)
    if miscContainer and type(miscContainer.ListActors) == "function" then
        for _, actor in miscContainer:ListActors() do
            local name = ExtractName(actor)
            local entry = Ensure(name)
            if entry then
                local interrupts = actor.interrupt or actor.interrupts or actor.interrupt_amount or actor.interrupts_amount
                entry.interrupts = tonumber(interrupts) or entry.interrupts or 0
            end
        end
    end

    return next(statsByName) and statsByName or nil
end

-- Based on Details! implementation - comprehensive completion info extraction
-- Supports both new (GetChallengeCompletionInfo) and legacy APIs
local function GetCompletionInfoCompat()
    -- Try the modern API first (Details! method)
    if C_ChallengeMode and type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
        local info = C_ChallengeMode.GetChallengeCompletionInfo()
        if type(info) == "table" then
            return {
                mapID = info.mapChallengeModeID or info.mapID or info.challengeMapID,
                level = info.level or info.keystoneLevel,
                time = info.time or info.completionTime or info.duration,
                keystoneUpgrades = info.keystoneUpgradeLevels or info.keystoneUpgrades or info.upgrades,
                onTime = info.onTime,
                practiceRun = info.practiceRun,
                isAffixRecord = info.isAffixRecord,
                isMapRecord = info.isMapRecord,
                isEligibleForScore = info.isEligibleForScore,
                oldOverallDungeonScore = info.oldOverallDungeonScore,
                newOverallDungeonScore = info.newOverallDungeonScore,
                members = info.members,
            }
        end
    end

    -- Fallback to legacy API
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

    -- Try to get accurate duration from Details combat tracker first
    local detailsDuration = nil
    local combat = GetDetailsMythicDungeonOverallCombat()
    if combat then
        -- Details tracks combat time in seconds
        if combat.GetCombatTime and type(combat.GetCombatTime) == "function" then
            detailsDuration = combat:GetCombatTime()
            print("|cff00ffaa[StormsDungeonData]|r Details combat time: " .. tostring(detailsDuration))
        elseif combat.combat_time then
            detailsDuration = combat.combat_time
            print("|cff00ffaa[StormsDungeonData]|r Details combat_time: " .. tostring(detailsDuration))
        elseif combat.GetDate and type(combat.GetDate) == "function" then
            local startTime, endTime = combat:GetDate()
            if startTime and endTime then
                detailsDuration = endTime - startTime
                print("|cff00ffaa[StormsDungeonData]|r Details calculated from dates: " .. tostring(detailsDuration) .. " (start: " .. tostring(startTime) .. ", end: " .. tostring(endTime) .. ")")
            end
        end
    end

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
    
    -- Prefer Details duration if available, otherwise use completion time
    local durationSeconds = detailsDuration or NormalizeDurationSeconds(completionTime)
    print("|cff00ffaa[StormsDungeonData]|r Using duration: " .. tostring(durationSeconds) .. " (Details: " .. tostring(detailsDuration) .. ", Completion API: " .. tostring(completionTime) .. ")")

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
    
    -- Additional completion detection events
    self.frame:RegisterEvent("CHALLENGE_MODE_START")
    self.frame:RegisterEvent("SCENARIO_COMPLETED")
    self.frame:RegisterEvent("WORLD_STATE_TIMER_STOP")
    
    -- New: Use official completion rewards event (more reliable)
    self.frame:RegisterEvent("CHALLENGE_MODE_COMPLETED_REWARDS")

    -- Always listen to CLEU for deaths/mob kills; WoW 12+ uses C_DamageMeter for damage/healing/interrupt totals.
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    
    -- Register for appropriate combat events based on WoW version
    if MPT.DamageMeterCompat.IsWoW12Plus then
        -- WoW 12.0+ uses damage meter events
        self.frame:RegisterEvent("COMBAT_METRICS_SESSION_NEW")
        self.frame:RegisterEvent("COMBAT_METRICS_SESSION_UPDATED")
        self.frame:RegisterEvent("COMBAT_METRICS_SESSION_END")
        
        -- WoW 12.0+: Damage meter events can indicate session end
        self.frame:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
    end
    
    self.frame:SetScript("OnEvent", function(self, event, ...)
        Events:OnEvent(event, ...)
    end)
    
    print("|cff00ffaa[StormsDungeonData]|r Events module initialized")
    print("|cff00ffaa[StormsDungeonData]|r Registered for: CHALLENGE_MODE_COMPLETED, CHALLENGE_MODE_COMPLETED_REWARDS, CHALLENGE_MODE_START")
end

function Events:OnEvent(event, ...)
    -- Capture varargs before pcall
    local args = {...}
    
    -- Add error handling wrapper to catch any issues
    local success, err = pcall(function()
        if event == "ADDON_LOADED" then
            local addonName = args[1]
                if addonName == "StormsDungeonData" then
                MPT:Initialize()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:OnPlayerEnteringWorld()
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            print("|cff00ffaa[StormsDungeonData]|r === CHALLENGE_MODE_COMPLETED EVENT RECEIVED ===")
            self:OnChallengeModeCompleted()
        elseif event == "CHALLENGE_MODE_COMPLETED_REWARDS" then
            -- This event fires AFTER completion and includes all completion data as payload
            local mapID, medal, timeMS, money, rewards = args[1], args[2], args[3], args[4], args[5]
            print("|cff00ffaa[StormsDungeonData]|r === CHALLENGE_MODE_COMPLETED_REWARDS EVENT RECEIVED ===")
            print("|cff00ffaa[StormsDungeonData]|r Payload: mapID=" .. tostring(mapID) .. ", timeMS=" .. tostring(timeMS))
            
            -- This is a very reliable event - trigger completion with slight delay for API to update
            C_Timer.After(0.1, function()
                self:OnChallengeModeCompleted()
            end)
        elseif event == "CHALLENGE_MODE_START" then
            local mapID = args[1]
            print("|cff00ffaa[StormsDungeonData]|r CHALLENGE_MODE_START event received (mapID=" .. tostring(mapID) .. ")")
            -- Store that we're in a mythic+ run
            MPT.InMythicPlus = true
            MPT.MythicPlusMapID = mapID
        elseif event == "SCENARIO_COMPLETED" then
            print("|cff00ffaa[StormsDungeonData]|r SCENARIO_COMPLETED event received (potential key completion)")
            if MPT.InMythicPlus then
                -- Give a moment for APIs to update, then trigger completion
                C_Timer.After(0.5, function()
                    self:OnChallengeModeCompleted()
                end)
            end
        elseif event == "WORLD_STATE_TIMER_STOP" then
            print("|cff00ffaa[StormsDungeonData]|r WORLD_STATE_TIMER_STOP event received (potential key completion)")
            if MPT.InMythicPlus then
                -- Give a moment for APIs to update, then trigger completion
                C_Timer.After(0.5, function()
                    self:OnChallengeModeCompleted()
                end)
            end
        elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" then
            -- WoW 12.0+ event that fires when combat session updates
            local dmType, sessionID = args[1], args[2]
            -- Check if this is a mythic+ session ending
            if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
                local sessions = C_DamageMeter.GetAvailableCombatSessions()
                for _, session in ipairs(sessions) do
                    if session.sessionID == sessionID and session.durationSeconds and MPT.InMythicPlus then
                        -- Session has ended (has duration), might be key completion
                        print("|cff00ffaa[StormsDungeonData]|r Damage meter session ended (sessionID=" .. sessionID .. ", duration=" .. session.durationSeconds .. "s)")
                    end
                end
            end
        elseif event == "LOOT_OPENED" then
            self:OnLootOpened()
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- Use CombatLogGetCurrentEventInfo inside handler
            MPT.CombatLog:OnCombatLogEvent()
        elseif event == "COMBAT_METRICS_SESSION_NEW" then
            -- WoW 12.0+ event
            MPT.DamageMeterCompat:OnDamageMeterEvent(event, unpack(args))
        elseif event == "COMBAT_METRICS_SESSION_UPDATED" then
            -- WoW 12.0+ event
            MPT.DamageMeterCompat:OnDamageMeterEvent(event, unpack(args))
        elseif event == "COMBAT_METRICS_SESSION_END" then
            -- WoW 12.0+ event
            MPT.DamageMeterCompat:OnDamageMeterEvent(event, unpack(args))
        end
    end)
    
    if not success then
        print("|cff00ffaa[StormsDungeonData]|r ERROR in OnEvent(" .. tostring(event) .. "): " .. tostring(err))
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
            print("|cff00ffaa[StormsDungeonData]|r Player teleported out of dungeon, auto-saving run (exit)")
            self:FinalizeRun("exit")
        end
        MPT.CombatLog:StopTracking()
    end
end

function Events:OnChallengeModeCompleted()
    print("|cff00ffaa[StormsDungeonData]|r CHALLENGE_MODE_COMPLETED event fired")
    
    -- Wrap in pcall for safety
    local success, err = pcall(function()
        -- Avoid re-creating run data if we already cached it and it isn't saved yet.
        -- BUT: ensure fallback timers are set even if run data exists
        if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
            print("|cff00ffaa[StormsDungeonData]|r Run already cached, ensuring fallback timers are set...")
            
            -- Ensure fallback timers exist even if we return early
            if C_Timer and C_Timer.After and not self.fallbackTimersSet then
                self.fallbackTimersSet = true
                
                local timer1Success = pcall(function()
                    C_Timer.After(8, function()
                        if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                            print("|cff00ffaa[StormsDungeonData]|r 8-second fallback timer triggered, auto-saving run (completed)")
                            Events:FinalizeRun("completed")
                        else
                            print("|cff00ffaa[StormsDungeonData]|r 8-second timer fired but run already saved or missing")
                        end
                    end)
                end)
                
                local timer2Success = pcall(function()
                    C_Timer.After(45, function()
                        if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                            print("|cff00ffaa[StormsDungeonData]|r 45-second fallback timer triggered, auto-saving run (timeout)")
                            Events:FinalizeRun("timeout")
                        else
                            print("|cff00ffaa[StormsDungeonData]|r 45-second timer fired but run already saved or missing")
                        end
                    end)
                end)
                
                if timer1Success and timer2Success then
                    print("|cff00ffaa[StormsDungeonData]|r Fallback timers set successfully (8s and 45s)")
                else
                    print("|cff00ffaa[StormsDungeonData]|r ERROR: Failed to create one or both timers!")
                end
            elseif not C_Timer or not C_Timer.After then
                print("|cff00ffaa[StormsDungeonData]|r ERROR: C_Timer.After not available!")
            end
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
    
    -- Capture additional completion data (Details! style)
    local onTime = completion and completion.onTime
    local practiceRun = completion and completion.practiceRun
    local isAffixRecord = completion and completion.isAffixRecord
    local isMapRecord = completion and completion.isMapRecord
    local isEligibleForScore = completion and completion.isEligibleForScore
    local oldDungeonScore = completion and completion.oldOverallDungeonScore
    local newDungeonScore = completion and completion.newOverallDungeonScore
    
    print("|cff00ffaa[StormsDungeonData]|r Completion info: mapID=" .. tostring(mapID) .. ", level=" .. tostring(level) .. ", time=" .. tostring(durationSeconds) .. "s, onTime=" .. tostring(onTime))

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
        
        -- Capture enemy forces data NOW while we're still in the dungeon
        -- This prevents issues if the player leaves before FinalizeRun is called
        local earlyForces = GetEnemyForcesProgress()
        local capturedMobData = false
        if earlyForces and earlyForces.percent and earlyForces.percent > 0 then
            capturedMobData = true
            print("|cff00ffaa[StormsDungeonData]|r Captured mob data at completion: " .. string.format("%.1f%%", earlyForces.percent) .. " (" .. tostring(earlyForces.current) .. "/" .. tostring(earlyForces.total) .. ")")
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
            
            -- Pre-capture mob data if available (prevents loss if player leaves dungeon)
            mobsKilled = capturedMobData and (earlyForces.current or 0) or nil,
            mobsTotal = capturedMobData and (earlyForces.total or 0) or nil,
            overallMobPercentage = capturedMobData and earlyForces.percent or nil,
            
            -- Additional completion data (Details! style)
            onTime = onTime,
            practiceRun = practiceRun,
            isAffixRecord = isAffixRecord,
            isMapRecord = isMapRecord,
            isEligibleForScore = isEligibleForScore,
            oldDungeonScore = oldDungeonScore,
            newDungeonScore = newDungeonScore,
        }
        
        print("|cff00ffaa[StormsDungeonData]|r Challenge mode completed!")
        print("|cff00ffaa[StormsDungeonData]|r Run data cached, waiting for loot chest...")
        print("|cff00ffaa[StormsDungeonData]|r Duration from API: " .. tostring(durationSeconds) .. " seconds")
        print("|cff00ffaa[StormsDungeonData]|r Calculated startTime: " .. tostring(startTime) .. ", completionTime: " .. tostring(time()))
        print("|cff00ffaa[StormsDungeonData]|r Key upgraded: " .. tostring(keystoneUpgrades) .. " levels, onTime: " .. tostring(onTime))

        -- Save/show shortly after completion even if LOOT_OPENED never fires.
        -- This fixes runs that reward via UI/mail and never open a loot window.
        self.fallbackTimersSet = true
        if C_Timer and C_Timer.After then
            print("|cff00ffaa[StormsDungeonData]|r Creating fallback timers...")
            
            local timer1Success = pcall(function()
                C_Timer.After(8, function()
                    if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                        print("|cff00ffaa[StormsDungeonData]|r 8-second fallback timer triggered, auto-saving run (completed)")
                        Events:FinalizeRun("completed")
                    else
                        print("|cff00ffaa[StormsDungeonData]|r 8-second timer fired but run already saved or missing")
                    end
                end)
            end)
            
            local timer2Success = pcall(function()
                C_Timer.After(45, function()
                    if MPT.CurrentRunData and MPT.CurrentRunData.completed and not MPT.CurrentRunData.saved then
                        print("|cff00ffaa[StormsDungeonData]|r 45-second fallback timer triggered, auto-saving run (timeout)")
                        Events:FinalizeRun("timeout")
                    else
                        print("|cff00ffaa[StormsDungeonData]|r 45-second timer fired but run already saved or missing")
                    end
                end)
            end)
            
            if timer1Success and timer2Success then
                print("|cff00ffaa[StormsDungeonData]|r Fallback timers set successfully (8s and 45s)")
            else
                print("|cff00ffaa[StormsDungeonData]|r ERROR: Failed to create one or both timers (8s=" .. tostring(timer1Success) .. ", 45s=" .. tostring(timer2Success) .. ")")
            end
        else
            print("|cff00ffaa[StormsDungeonData]|r WARNING: C_Timer not available, fallback timers not set!")
        end
    else
        -- Some clients return completion info slightly later. Retry a few times.
        print("|cff00ffaa[StormsDungeonData]|r Warning: could not read completion info (mapID=" .. tostring(mapID) .. ", level=" .. tostring(level) .. ")")
        if C_Timer and C_Timer.After then
            self.challengeRetryCount = (self.challengeRetryCount or 0) + 1
            if self.challengeRetryCount <= 5 then
                local delay = 1.5 * self.challengeRetryCount
                print("|cff00ffaa[StormsDungeonData]|r Retrying in " .. delay .. " seconds (attempt " .. self.challengeRetryCount .. "/5)")
                C_Timer.After(delay, function()
                    Events:OnChallengeModeCompleted()
                end)
                return
            else
                print("|cff00ffaa[StormsDungeonData]|r Failed to get completion info after 5 retries")
            end
        end
    end
    end) -- end of pcall
    
    if not success then
        print("|cff00ffaa[StormsDungeonData]|r ERROR in OnChallengeModeCompleted: " .. tostring(err))
    end
end

function Events:FinalizeRun(reason)
    print("|cff00ffaa[StormsDungeonData]|r FinalizeRun called (reason: " .. tostring(reason) .. ")")
    
    -- Reset fallback timer flag for next run
    self.fallbackTimersSet = false
    
    if not MPT.CurrentRunData then
        print("|cff00ffaa[StormsDungeonData]|r No current run data, attempting to build from keystone")
        if not self:BuildRunDataFromActiveKeystone() then
            print("|cff00ffaa[StormsDungeonData]|r No pending run data to save")
            return false
        end
    end

    if MPT.CurrentRunData.saved then
        print("|cff00ffaa[StormsDungeonData]|r Run already saved, skipping")
        return false
    end

    if not MPT.CurrentRunData.completed then
        MPT.CurrentRunData.completed = true
        MPT.CurrentRunData.completionTime = time()
        if not MPT.CurrentRunData.startTime then
            MPT.CurrentRunData.startTime = (MPT.CombatLog and MPT.CombatLog.startTime) or time()
        end
        -- Use completionDuration if available (from API), otherwise calculate from timestamps
        if not MPT.CurrentRunData.completionDuration or MPT.CurrentRunData.completionDuration <= 0 then
            MPT.CurrentRunData.completionDuration = time() - (MPT.CurrentRunData.startTime or time())
        end
        print("|cff00ffaa[StormsDungeonData]|r Run marked completed, duration: " .. tostring(MPT.CurrentRunData.completionDuration) .. "s")
    end

    -- Finalize combat totals before saving/showing (matches how Details reads overall data)
    if MPT.CombatLog and MPT.CombatLog.useNewAPI then
        MPT.CombatLog:FinalizeNewAPIData()
    end

    -- Prefer the API-provided duration over calculated duration for accuracy
    local duration = MPT.CurrentRunData.completionDuration
    if not duration or duration <= 0 then
        duration = time() - (MPT.CurrentRunData.startTime or time())
        print("|cff00ffaa[StormsDungeonData]|r WARNING: No valid completionDuration, calculated from timestamps: " .. tostring(duration) .. "s")
    else
        print("|cff00ffaa[StormsDungeonData]|r Using duration: " .. tostring(duration) .. "s (from completionDuration)")
    end
    MPT.CurrentRunData.duration = duration

    -- Get mob percentage - try multiple sources in order of reliability
    -- Priority: 1) Pre-captured at completion, 2) CombatLog, 3) Scenario API, 4) Assume 100%
    local mobDataSource = "none"
    
    -- Method 0: Use pre-captured data from OnChallengeModeCompleted if available
    if MPT.CurrentRunData.overallMobPercentage and MPT.CurrentRunData.overallMobPercentage > 0 then
        mobDataSource = "pre-captured at completion"
        print("|cff00ffaa[StormsDungeonData]|r Using pre-captured mob %: " .. string.format("%.1f%%", MPT.CurrentRunData.overallMobPercentage))
    -- Method 1: CombatLog tracking (if we have valid data)
    elseif MPT.CombatLog and MPT.CombatLog.mobsKilled and MPT.CombatLog.mobsTotal and MPT.CombatLog.mobsTotal > 0 then
        MPT.CurrentRunData.mobsKilled = MPT.CombatLog.mobsKilled
        MPT.CurrentRunData.mobsTotal = MPT.CombatLog.mobsTotal
        MPT.CurrentRunData.overallMobPercentage = (MPT.CombatLog.mobsKilled / MPT.CombatLog.mobsTotal) * 100
        mobDataSource = "CombatLog"
        print("|cff00ffaa[StormsDungeonData]|r Mob % from CombatLog: " .. string.format("%.1f%%", MPT.CurrentRunData.overallMobPercentage) .. " (" .. MPT.CombatLog.mobsKilled .. "/" .. MPT.CombatLog.mobsTotal .. ")")
    else
        print("|cff00ffaa[StormsDungeonData]|r CombatLog mob data not available (mobsKilled=" .. tostring(MPT.CombatLog and MPT.CombatLog.mobsKilled) .. ", mobsTotal=" .. tostring(MPT.CombatLog and MPT.CombatLog.mobsTotal) .. ")")
        
        -- Method 2: Scenario API (real-time data from game)
        print("|cff00ffaa[StormsDungeonData]|r Trying Scenario API for mob data...")
        local forces = GetEnemyForcesProgress()
        if forces and forces.percent and forces.percent > 0 then
            MPT.CurrentRunData.mobsKilled = forces.current or 0
            MPT.CurrentRunData.mobsTotal = forces.total or 0
            MPT.CurrentRunData.overallMobPercentage = forces.percent
            mobDataSource = "Scenario API (percent)"
            print("|cff00ffaa[StormsDungeonData]|r Mob % from Scenario API (percent): " .. string.format("%.1f%%", forces.percent))
        elseif forces and forces.current and forces.total and forces.total > 0 then
            MPT.CurrentRunData.mobsKilled = forces.current
            MPT.CurrentRunData.mobsTotal = forces.total
            MPT.CurrentRunData.overallMobPercentage = (forces.current / forces.total) * 100
            mobDataSource = "Scenario API (calculated)"
            print("|cff00ffaa[StormsDungeonData]|r Mob % from Scenario API (calculated): " .. string.format("%.1f%%", MPT.CurrentRunData.overallMobPercentage) .. " (" .. forces.current .. "/" .. forces.total .. ")")
        else
            print("|cff00ffaa[StormsDungeonData]|r Scenario API returned no valid data")
            
            -- Method 3: Assume 100% if run was completed successfully
            if MPT.CurrentRunData.completed and MPT.CurrentRunData.onTime ~= false then
                -- If the run was completed (especially if onTime), assume 100% mob count
                MPT.CurrentRunData.overallMobPercentage = 100
                mobDataSource = "assumed (completed run)"
                print("|cff00ffaa[StormsDungeonData]|r WARNING: No mob data available, assuming 100% for completed run")
            else
                print("|cff00ffaa[StormsDungeonData]|r WARNING: Could not get mob percentage from any source")
                MPT.CurrentRunData.overallMobPercentage = 0
                mobDataSource = "failed"
            end
        end
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Final mob data source: " .. mobDataSource)

    -- Copy tracked stats into player records (so UI and saved history match Details totals)
    local sumBase = 0
    local detailsStats = GetDetailsOverallPlayerStats()
    if MPT.CurrentRunData.players then
        for _, p in ipairs(MPT.CurrentRunData.players) do
            local key = NormalizeUnitName(p.name) or p.name
            local stats = (detailsStats and key and detailsStats[key])
                or (MPT.CombatLog and MPT.CombatLog:GetPlayerStats(p.name))
                or {}
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
    
    print("|cff00ffaa[StormsDungeonData]|r LOOT_OPENED event fired, numLootItems=" .. tostring(numLootItems))
    print("|cff00ffaa[StormsDungeonData]|r MPT.CurrentRunData exists: " .. tostring(MPT.CurrentRunData ~= nil))
    if MPT.CurrentRunData then
        print("|cff00ffaa[StormsDungeonData]|r CurrentRunData.completed=" .. tostring(MPT.CurrentRunData.completed) .. ", saved=" .. tostring(MPT.CurrentRunData.saved) .. ", completionTime=" .. tostring(MPT.CurrentRunData.completionTime))
    end
    
    if numLootItems > 0 and not MPT.CurrentRunData then
        print("|cff00ffaa[StormsDungeonData]|r Loot opened but no current run, attempting to build from keystone")
        self:BuildRunDataFromActiveKeystone()
    end

    if numLootItems > 0 and MPT.CurrentRunData then
        -- Accept loot within a short window after completion; item quality checks are unreliable across seasons/rewards.
        local withinWindow = false
        local timeSinceCompletion = nil
        if MPT.CurrentRunData.completionTime then
            timeSinceCompletion = time() - MPT.CurrentRunData.completionTime
            withinWindow = timeSinceCompletion <= 600
        end

        print("|cff00ffaa[StormsDungeonData]|r Time since completion: " .. tostring(timeSinceCompletion) .. "s, withinWindow=" .. tostring(withinWindow))
        
        local hasAnyItem = numLootItems and numLootItems > 0
        local looksLikeReward = false
        for i = 1, numLootItems do
            local _, _, quality = GetLootSlotInfo(i)
            if quality ~= nil then
                looksLikeReward = true
                break
            end
        end

        print("|cff00ffaa[StormsDungeonData]|r hasAnyItem=" .. tostring(hasAnyItem) .. ", looksLikeReward=" .. tostring(looksLikeReward))
        
        if MPT.CurrentRunData.saved then
            print("|cff00ffaa[StormsDungeonData]|r Run already saved, skipping loot-triggered save")
        elseif withinWindow and hasAnyItem and (looksLikeReward or true) then
            print("|cff00ffaa[StormsDungeonData]|r Loot chest detected, auto-saving run (loot)")
            self:FinalizeRun("loot")
        else
            print("|cff00ffaa[StormsDungeonData]|r Loot NOT triggering save: withinWindow=" .. tostring(withinWindow) .. ", hasAnyItem=" .. tostring(hasAnyItem) .. ", saved=" .. tostring(MPT.CurrentRunData.saved))
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

-- Reconstruct CurrentRunData from C_MythicPlus.GetRunHistory() entry
function Events:ReconstructRunDataFromHistory(runInfo)
    if not runInfo then
        print("|cff00ffaa[StormsDungeonData]|r Cannot reconstruct run: no run info provided")
        return false
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Reconstructing run data from history...")
    
    -- Get dungeon info
    local dungeonName = C_ChallengeMode.GetMapUIInfo(runInfo.mapChallengeModeID)
    if not dungeonName then
        dungeonName = "Unknown Dungeon"
    end
    
    -- Get current affixes
    local affixes = {}
    local affixIDs = C_MythicPlus.GetCurrentAffixes()
    if affixIDs then
        for _, affixInfo in ipairs(affixIDs) do
            table.insert(affixes, affixInfo.id)
        end
    end
    
    -- Initialize CurrentRunData
    MPT.CurrentRunData = {
        dungeonName = dungeonName,
        mapID = runInfo.mapChallengeModeID,
        keystoneLevel = runInfo.level,
        affixes = affixes,
        startTime = time() - runInfo.durationSec, -- Estimate start time
        completionTime = time(),
        completionDuration = runInfo.durationSec,
        completed = runInfo.completed,
        totalEnemyForces = 100.0, -- Assume 100% for completed runs
        enemyForcesCurrent = 100.0,
        groupMembers = {},
        saved = false,
        reconstructed = true -- Flag to indicate this was reconstructed
    }
    
    -- Try to get group member info
    if self.CollectGroupPlayerStats then
        local members = self:CollectGroupPlayerStats()
        if members then
            MPT.CurrentRunData.groupMembers = members
        end
    end
    
    -- Try to get completion info for more details
    if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
        local completionInfo = C_ChallengeMode.GetCompletionInfo()
        if completionInfo then
            MPT.CurrentRunData.onTime = completionInfo.onTime
            MPT.CurrentRunData.keystoneUpgrades = completionInfo.keystoneUpgrades
            if completionInfo.members then
                MPT.CurrentRunData.groupMembers = completionInfo.members
            end
        end
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Reconstructed: " .. dungeonName .. " +" .. runInfo.level .. " (" .. runInfo.durationSec .. "s)")
    return true
end

print("|cff00ffaa[StormsDungeonData]|r Events module loaded")
