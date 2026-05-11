-- Mythic Plus Tracker - Event Module
-- Registers and handles WoW events
-- WoW 12.0+: Uses C_CombatLog namespace for event data access
-- Pre-12.0: Uses legacy COMBAT_LOG_EVENT_UNFILTERED (with deprecation fallbacks)

local MPT = StormsDungeonData
local Events = MPT.Events

local function L(level, msg)
    if MPT.Log then MPT.Log:Log(level or "INFO", msg) end
end

local function Chat(msg)
    print("|cff00ffaa[StormsDungeonData]|r " .. tostring(msg))
end

local function ResetRunAnnouncements()
    MPT.RunAnnouncements = {
        trackingStarted = false,
        mobMilestones = {},
        bossKills = {},
    }
end

local function EnsureRunAnnouncements()
    if type(MPT.RunAnnouncements) ~= "table" then
        ResetRunAnnouncements()
    end
    if type(MPT.RunAnnouncements.mobMilestones) ~= "table" then
        MPT.RunAnnouncements.mobMilestones = {}
    end
    if type(MPT.RunAnnouncements.bossKills) ~= "table" then
        MPT.RunAnnouncements.bossKills = {}
    end
    return MPT.RunAnnouncements
end

local function AnnounceTrackingStarted(source)
    local announcements = EnsureRunAnnouncements()
    if announcements.trackingStarted then
        return
    end
    announcements.trackingStarted = true
    L("INFO", "Tracking started for this key" .. (source and (" (" .. tostring(source) .. ")") or ""))
end

local function AnnounceMobMilestones(forcesPercent)
    local percent = tonumber(forcesPercent)
    if not percent then
        return
    end

    local announcements = EnsureRunAnnouncements()
    local milestones = { 25, 50, 75, 100 }
    for _, milestone in ipairs(milestones) do
        if percent >= milestone and not announcements.mobMilestones[milestone] then
            announcements.mobMilestones[milestone] = true
            Chat("Enemy forces milestone: " .. tostring(milestone) .. "%")
        end
    end
end

local function AnnounceBossKill(encounterID, encounterName, bossesKilled, bossCount)
    local announcements = EnsureRunAnnouncements()
    local key = encounterID and ("id:" .. tostring(encounterID)) or ("name:" .. tostring(encounterName or "unknown"))
    if announcements.bossKills[key] then
        return
    end
    announcements.bossKills[key] = true

    local bossLabel = (type(encounterName) == "string" and encounterName ~= "") and encounterName or ("Encounter " .. tostring(encounterID or "?"))
    Chat(tostring(bossLabel) .. " Defeated.")
end

local function EnsureFlowTrace()
    if type(MPT.FlowTrace) ~= "table" then
        MPT.FlowTrace = {
            events = {},
            maxEntries = 120,
            runStartedAt = nil,
        }
    elseif type(MPT.FlowTrace.events) ~= "table" then
        MPT.FlowTrace.events = {}
    end
    if type(MPT.FlowTrace.maxEntries) ~= "number" or MPT.FlowTrace.maxEntries < 20 then
        MPT.FlowTrace.maxEntries = 120
    end
    return MPT.FlowTrace
end

local function RecordFlow(tag, detail)
    local trace = EnsureFlowTrace()
    local nowTs = time()
    table.insert(trace.events, {
        ts = nowTs,
        tag = tostring(tag or "event"),
        detail = detail and tostring(detail) or nil,
    })
    while #trace.events > trace.maxEntries do
        table.remove(trace.events, 1)
    end
end

local function MarkCompletionSignal(reason)
    MPT.RunCompletionSignal = {
        reason = tostring(reason or "unknown"),
        at = time(),
    }
    RecordFlow("RUN_COMPLETE_SIGNAL", tostring(reason or "unknown"))
end

local function ClearCompletionSignal()
    MPT.RunCompletionSignal = nil
end

function Events:RecordFlow(tag, detail)
    RecordFlow(tag, detail)
end

function Events:DumpFlowTrace(limit)
    local trace = EnsureFlowTrace()
    local events = trace.events or {}
    local maxLines = tonumber(limit) or 30
    if maxLines < 1 then maxLines = 1 end
    if maxLines > 200 then maxLines = 200 end

    L("INFO","|cff00ffaa[StormsDungeonData]|r Flow trace (most recent " .. tostring(maxLines) .. ")")
    L("INFO","|cff00ffaa[StormsDungeonData]|r   Last save reason: " .. tostring(MPT.LastSavedRunReason or "none") .. ", last save time: " .. tostring(MPT.LastSavedRunTime or "n/a"))

    if #events == 0 then
        L("INFO","|cff00ffaa[StormsDungeonData]|r   (no flow events recorded yet)")
        return
    end

    local startIndex = math.max(1, (#events - maxLines) + 1)
    for i = startIndex, #events do
        local e = events[i]
        local when = (e and e.ts and date and date("%H:%M:%S", e.ts)) or "??:??:??"
        local tag = (e and e.tag) or "event"
        local detail = (e and e.detail) or ""
        if detail ~= "" then
            L("INFO","  [" .. tostring(when) .. "] " .. tostring(tag) .. " - " .. tostring(detail))
        else
            L("INFO","  [" .. tostring(when) .. "] " .. tostring(tag))
        end
    end
end

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

local function GetCurrentRealmToken()
    local realm = nil
    if type(GetNormalizedRealmName) == "function" then
        realm = GetNormalizedRealmName()
    end
    if (not realm or realm == "") and type(GetRealmName) == "function" then
        realm = GetRealmName()
    end
    if type(realm) ~= "string" then
        return nil
    end
    realm = realm:gsub("%s+", "")
    if realm == "" then
        return nil
    end
    return realm
end

local function ResolveFullPlayerName(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    if name:find("%-") then
        return name
    end

    local shortName = NormalizeUnitName(name) or name
    if not shortName or shortName == "" then
        return nil
    end

    if MPT.CombatLog and type(MPT.CombatLog.fullNameByShort) == "table" then
        local mapped = MPT.CombatLog.fullNameByShort[shortName]
        if type(mapped) == "string" and mapped ~= "" then
            return mapped
        end
    end

    local function fullNameForUnit(unitID)
        if not unitID or not UnitExists(unitID) then
            return nil
        end
        local unitName, unitRealm = UnitName(unitID)
        if type(unitName) ~= "string" or unitName == "" then
            return nil
        end
        if unitRealm and unitRealm ~= "" then
            return unitName .. "-" .. unitRealm
        end
        return unitName
    end

    local playerFull = fullNameForUnit("player")
    if playerFull and (NormalizeUnitName(playerFull) or playerFull) == shortName then
        return playerFull
    end

    for i = 1, 5 do
        local partyFull = fullNameForUnit("party" .. i)
        if partyFull and (NormalizeUnitName(partyFull) or partyFull) == shortName then
            return partyFull
        end
    end

    return shortName
end

local function ResolvePetOwnerByCurrentUnits(petDisplayName)
    if type(petDisplayName) ~= "string" then
        return nil
    end

    local okTarget, targetLower = pcall(string.lower, petDisplayName)
    if not okTarget or type(targetLower) ~= "string" then
        return nil
    end

    local function ownerFromUnits(ownerUnitID, petUnitID)
        if not UnitExists(ownerUnitID) or not UnitExists(petUnitID) then
            return nil
        end

        local petName = UnitName(petUnitID)
        if type(petName) ~= "string" then
            return nil
        end

        local okLower, petNameLower = pcall(string.lower, petName)
        if not okLower or type(petNameLower) ~= "string" then
            return nil
        end

        local okMatch, isMatch = pcall(function()
            return petNameLower == targetLower
        end)
        if not okMatch or not isMatch then
            return nil
        end

        local ownerName, ownerRealm = UnitName(ownerUnitID)
        if type(ownerName) ~= "string" or ownerName == "" then
            return nil
        end

        if ownerRealm and ownerRealm ~= "" then
            return ownerName .. "-" .. ownerRealm
        end

        return ResolveFullPlayerName(ownerName) or ownerName
    end

    local owner = ownerFromUnits("player", "pet")
    if owner then
        return owner
    end

    for i = 1, 5 do
        owner = ownerFromUnits("party" .. i, "party" .. i .. "pet")
        if owner then
            return owner
        end
    end

    return nil
end

local DEBUG_PERSONAL_DEATHS = true

local function ResolvePlayerGUID(name, unitID, explicitGUID)
    if type(explicitGUID) == "string" and explicitGUID ~= "" then
        return explicitGUID
    end

    if type(unitID) == "string" and unitID ~= "" and UnitExists(unitID) then
        local directGUID = UnitGUID(unitID)
        if type(directGUID) == "string" and directGUID ~= "" then
            return directGUID
        end
    end

    local resolvedName = ResolveFullPlayerName(name) or name
    local shortName = NormalizeUnitName(resolvedName) or resolvedName
    local shortLower = type(shortName) == "string" and string.lower(shortName) or nil
    local fullLower = type(resolvedName) == "string" and string.lower(resolvedName) or nil

    local function unitMatches(unit)
        if not UnitExists(unit) then
            return false
        end
        local unitName, unitRealm = UnitName(unit)
        if type(unitName) ~= "string" or unitName == "" then
            return false
        end
        local unitFull = unitRealm and unitRealm ~= "" and (unitName .. "-" .. unitRealm) or unitName
        local unitShort = NormalizeUnitName(unitFull) or unitFull
        local unitShortLower = string.lower(unitShort)
        local unitFullLower = string.lower(unitFull)
        return (shortLower and unitShortLower == shortLower) or (fullLower and unitFullLower == fullLower)
    end

    if unitMatches("player") then
        local guid = UnitGUID("player")
        if type(guid) == "string" and guid ~= "" then
            return guid
        end
    end

    for i = 1, 5 do
        local partyUnit = "party" .. i
        if unitMatches(partyUnit) then
            local guid = UnitGUID(partyUnit)
            if type(guid) == "string" and guid ~= "" then
                return guid
            end
        end
    end

    if MPT.CombatLog and type(MPT.CombatLog.playerGUIDToName) == "table" then
        for guid, fullName in pairs(MPT.CombatLog.playerGUIDToName) do
            if type(guid) == "string" and guid ~= "" and type(fullName) == "string" and fullName ~= "" then
                local mappedShort = NormalizeUnitName(fullName) or fullName
                local mappedShortLower = string.lower(mappedShort)
                local mappedFullLower = string.lower(fullName)
                if (shortLower and mappedShortLower == shortLower) or (fullLower and mappedFullLower == fullLower) then
                    return guid
                end
            end
        end
    end

    return nil
end

local function CreatePlayerEntry(unitID, name, class, role, guid)
    if MPT.Database and type(MPT.Database.CreatePlayerStats) == "function" then
        local entry = MPT.Database:CreatePlayerStats(unitID, name, class, role)
        if type(guid) == "string" and guid ~= "" then
            entry.guid = guid
        end
        return entry
    end
    return {
        unitID = unitID,
        name = name,
        class = class,
        role = role,
        guid = guid,
        specID = nil,
        damage = 0,
        healing = 0,
        interrupts = 0,
        deaths = 0,
        pointsGained = 0,
        damagePerSecond = 0,
        healingPerSecond = 0,
        interruptsPerMinute = 0,
    }
end

-- GUID -> specID cache, populated via INSPECT_READY and on CHALLENGE_MODE_START.
-- Persists for the session so even if inspect data arrives late it is available at save time.
MPT.SpecCache = MPT.SpecCache or {}

local function CacheSpecFromUnit(unitID)
    if not unitID or not UnitExists(unitID) then return end
    local guid = UnitGUID(unitID)
    if not guid then return end
    local specID
    if unitID == "player" then
        local specIndex = GetSpecialization and GetSpecialization() or nil
        if specIndex and GetSpecializationInfo then
            specID = select(1, GetSpecializationInfo(specIndex))
        end
    else
        specID = GetInspectSpecialization and GetInspectSpecialization(unitID) or nil
    end
    if specID and specID > 0 then
        MPT.SpecCache[guid] = specID
    end
end

local function RequestGroupInspects()
    -- Cache self immediately (no inspect round-trip needed)
    CacheSpecFromUnit("player")
    if not NotifyInspect then return end
    for i = 1, 4 do
        local uid = "party" .. i
        if UnitExists(uid) then
            SafeCall(NotifyInspect, uid)
        end
    end
end

-- Back-fill specID into the current run's player list for any player whose spec
-- was just resolved.  Safe to call at any point; no-ops if no active run.
local function BackfillCurrentRunSpecIDs()
    local run = MPT.CurrentRunData
    if not run or not run.players then return end
    for _, p in ipairs(run.players) do
        if (not p.specID or p.specID == 0) and p.guid and MPT.SpecCache[p.guid] then
            p.specID = MPT.SpecCache[p.guid]
        end
    end
end

local function ClonePlayerList(players)
    local copy = {}
    if type(players) ~= "table" then
        return copy
    end
    for _, p in ipairs(players) do
        if p and type(p.name) == "string" and p.name ~= "" then
            local entry = CreatePlayerEntry(p.unitID, p.name, p.class, p.role, p.guid)
            -- Preserve spec ID from the source record
            if p.specID and p.specID > 0 then
                entry.specID = p.specID
            elseif p.guid and MPT.SpecCache[p.guid] then
                entry.specID = MPT.SpecCache[p.guid]
            end
            table.insert(copy, entry)
        end
    end
    return copy
end

local function BuildGroupMembersFromCompletionMembers(members)
    local result = {}
    if type(members) ~= "table" then
        return result
    end

    local seen = {}
    for _, member in ipairs(members) do
        if type(member) == "table" then
            local memberName = ResolveFullPlayerName(member.name) or member.name
            local memberGUID = member.memberGUID or member.guid
            local normalized = NormalizeUnitName(memberName) or memberName
            if type(memberName) == "string" and memberName ~= "" and normalized and not seen[normalized] then
                local classToken = nil
                if memberGUID and type(GetPlayerInfoByGUID) == "function" then
                    local _, englishClass = GetPlayerInfoByGUID(memberGUID)
                    classToken = englishClass
                end
                table.insert(result, CreatePlayerEntry(nil, memberName, classToken, nil, memberGUID))
                seen[normalized] = true
            end
        end
    end

    return result
end

local function MergePreferredPlayerList(primaryMembers, fallbackMembers, maxPlayers)
    -- Build a name-keyed lookup from the fallback list so we can enrich primary entries
    -- with specID and role that the fallback collected via live API / inspect.
    local fallbackByName = {}
    if type(fallbackMembers) == "table" then
        for _, m in ipairs(fallbackMembers) do
            if m and type(m.name) == "string" and m.name ~= "" then
                local key = NormalizeUnitName(m.name) or m.name
                if key then fallbackByName[key] = m end
            end
        end
    end

    local merged = {}
    local seen = {}
    local limit = tonumber(maxPlayers) or 5

    local function addMembers(list)
        if type(list) ~= "table" then
            return
        end
        for _, member in ipairs(list) do
            if #merged >= limit then
                break
            end
            if member and type(member.name) == "string" and member.name ~= "" then
                local resolvedName = ResolveFullPlayerName(member.name) or member.name
                local key = NormalizeUnitName(resolvedName) or resolvedName
                if key and not seen[key] then
                    -- Try to enrich with data from the fallback entry (has live specID/role)
                    local fb = fallbackByName[key]

                    -- Prefer the fallback's guid if the primary has none (completion members
                    -- often carry memberGUID while live entries have UnitGUID)
                    local guid = member.guid or (fb and fb.guid) or nil
                    local role = member.role or (fb and fb.role) or nil
                    local class = member.class or (fb and fb.class) or nil

                    local entry = CreatePlayerEntry(member.unitID, resolvedName, class, role, guid)

                    -- Spec ID: prefer source record, then fallback live entry, then cache
                    if member.specID and member.specID > 0 then
                        entry.specID = member.specID
                    elseif fb and fb.specID and fb.specID > 0 then
                        entry.specID = fb.specID
                    elseif guid and MPT.SpecCache[guid] then
                        entry.specID = MPT.SpecCache[guid]
                    end

                    table.insert(merged, entry)
                    seen[key] = true
                end
            end
        end
    end

    addMembers(primaryMembers)
    addMembers(fallbackMembers)

    return merged
end

-- True if name has a realm suffix (Name-Realm or Name-Realm-US); names without realm are assumed pets
local function NameHasRealm(name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    -- Must have at least one hyphen to be a player name (could be Name-Realm or Name-Realm-Region)
    return name:find("%-") ~= nil
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
    -- Fallback: if we are currently inside a M+ instance with this mapID, use the zone text
    if mapID and MPT.MythicPlusMapID and mapID == MPT.MythicPlusMapID then
        local zoneText = GetRealZoneText and GetRealZoneText()
        if zoneText and zoneText ~= "" then
            return zoneText
        end
    end
end

-- Returns time limit in seconds for the dungeon, or nil.
local function GetDungeonTimeLimitSeconds(mapID)
    if not mapID or not C_ChallengeMode or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        return nil
    end
    local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    if timeLimit and timeLimit > 0 and timeLimit < 100000 then
        return timeLimit
    end
    return nil
end

-- Get all boss encounter IDs for a challenge-mode map (for ENCOUNTER_END verification). Uses Encounter Journal.
-- Returns table of encounter IDs, or nil if EJ API unavailable / map has no journal instance.
local function GetEncounterIDsForMap(mapID)
    if not mapID or mapID == 0 then return nil end
    if type(EJ_GetInstanceForMap) ~= "function" or type(EJ_SelectInstance) ~= "function" or type(EJ_GetEncounterInfoByIndex) ~= "function" then
        return nil
    end
    local instanceID = EJ_GetInstanceForMap(mapID)
    if not instanceID or instanceID == 0 then return nil end
    EJ_SelectInstance(instanceID)
    local list = {}
    local j = 1
    while true do
        local name, _, encounterId = EJ_GetEncounterInfoByIndex(j, instanceID)
        if not encounterId or encounterId == 0 then break end
        list[#list + 1] = encounterId
        j = j + 1
        if j > 20 then break end
    end
    if #list == 0 then return nil end
    return list
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

-- MPlusTimer uses GetChallengeCompletionInfo().time / 1000 (time is milliseconds). Use this for run duration.
local function CompletionTimeToSeconds(apiTime)
    if not apiTime or type(apiTime) ~= "number" or apiTime <= 0 then
        return nil
    end
    -- WoW returns completion time in milliseconds (same as MPlusTimer Display.lua: self.timer = time/1000)
    if apiTime >= 1000 then
        return apiTime / 1000
    end
    -- Values under 1000 could be seconds (legacy or different API)
    return apiTime
end

local function NormalizeEnemyForcesPercent(percent)
    percent = tonumber(percent)
    if not percent then
        return nil
    end
    if percent < 0 then
        percent = 0
    end
    if percent > 100 then
        percent = 100
    end
    return percent
end

-- Based on RaiderIO's implementation for accurate enemy forces tracking
-- Uses criteriaInfo.quantity as the forces percent (0-100) directly.
local function GetEnemyForcesProgress()
    if not C_Scenario or not C_ScenarioInfo then
        L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: C_Scenario or C_ScenarioInfo not available")
        return nil
    end
    if type(C_Scenario.GetStepInfo) ~= "function" or type(C_ScenarioInfo.GetCriteriaInfo) ~= "function" then
        L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: Required API functions not available")
        return nil
    end

    local _, _, numCriteria = C_Scenario.GetStepInfo()
    if not numCriteria or numCriteria <= 1 then
        L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: No scenario criteria found (numCriteria=" .. tostring(numCriteria) .. ")")
        return nil
    end
    
    L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: Found " .. numCriteria .. " scenario criteria")

    -- Find the enemy forces criterion by looking for isWeightedProgress = true.
    -- NOTE: enemy forces is NOT always the last criterion. Dawnbreaker and some other dungeons
    -- place it at a different index, so we must scan rather than assume index = numCriteria.
    local criteriaInfo = nil
    local forcesIndex = nil
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if type(info) == "table" and info.isWeightedProgress then
            criteriaInfo = info
            forcesIndex = i
            break
        end
    end
    if not criteriaInfo then
        -- Fallback: assume last criterion is enemy forces (legacy behaviour)
        criteriaInfo = C_ScenarioInfo.GetCriteriaInfo(numCriteria)
        forcesIndex = numCriteria
        L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: No isWeightedProgress criterion found, falling back to last (index=" .. numCriteria .. ")")
    else
        L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: Found forces criterion at index=" .. tostring(forcesIndex))
    end
    if type(criteriaInfo) ~= "table" then
        L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: No criteria info available")
        return nil
    end

    local quantity = criteriaInfo.quantity
    local totalQuantity = criteriaInfo.totalQuantity

    L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: quantity=" .. tostring(quantity) .. ", totalQuantity=" .. tostring(totalQuantity))

    -- quantity is the forces % (0-100) directly.
    if not quantity then
       L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: No valid data found")
        return nil
    end

    local percent = NormalizeEnemyForcesPercent(quantity)
    local current = totalQuantity and totalQuantity > 0 and ((percent / 100) * totalQuantity) or 0
    local total   = totalQuantity or 0

   L("INFO","|cff00ffaa[SDD]|r GetEnemyForcesProgress: Returning current=" .. tostring(current) .. ", total=" .. tostring(total) .. ", percent=" .. tostring(percent))
    return {
        current = current,
        total   = total,
        percent = percent,
    }
end

-- MPlusTimer-style: scenario criteria = boss objectives + one weighted-progress forces criterion.
-- Returns: allBossesKilled, bossesKilled, forcesPercent, forcesAt100, bossCount, bossKillTimes (seconds into run), forcesCurrent, forcesTotal.
local function GetScenarioCompletionState()
    if not C_Scenario or type(C_Scenario.GetStepInfo) ~= "function" or not C_ScenarioInfo or type(C_ScenarioInfo.GetCriteriaInfo) ~= "function" then
        return nil
    end
    local _, _, numCriteria = C_Scenario.GetStepInfo()
    if not numCriteria or numCriteria <= 0 then
        return nil
    end

    -- Find the enemy forces criterion by isWeightedProgress. It is NOT always last;
    -- Dawnbreaker and other dungeons may place it at a different index.
    local forcesCriteria = nil
    local forcesIndex = nil
    for i = 1, numCriteria do
        local info = C_ScenarioInfo.GetCriteriaInfo(i)
        if type(info) == "table" and info.isWeightedProgress then
            forcesCriteria = info
            forcesIndex = i
            break
        end
    end
    if not forcesIndex then
        -- Legacy fallback: assume last criterion is enemy forces
        forcesIndex = numCriteria
        forcesCriteria = C_ScenarioInfo.GetCriteriaInfo(numCriteria)
    end

    -- All criteria except the forces one are boss objectives
    local allBossesKilled = true
    local bossesKilled = 0
    local bossKillTimes = {}
    local bossSlot = 0
    for i = 1, numCriteria do
        if i ~= forcesIndex then
            bossSlot = bossSlot + 1
            local crit = C_ScenarioInfo.GetCriteriaInfo(i)
            if not crit or not crit.completed then
                allBossesKilled = false
            else
                bossesKilled = bossesKilled + 1
                -- criteria.elapsed = seconds into run when objective completed (same as MPlusTimer)
                local killTime = (crit.elapsed and crit.elapsed > 0) and crit.elapsed or (select(2, GetWorldElapsedTime(1)))
                bossKillTimes[bossSlot] = killTime
            end
        end
    end
    local maxBoss = bossSlot  -- total number of boss criteria

    -- quantity is the forces % (0-100) directly.
    local forcesPercent = NormalizeEnemyForcesPercent(forcesCriteria and forcesCriteria.quantity) or 0
    local forcesTotal   = (forcesCriteria and forcesCriteria.totalQuantity) or 0
    local forcesCurrent = forcesTotal > 0 and ((forcesPercent / 100) * forcesTotal) or 0
    local forcesAt100 = (forcesPercent >= 100) or (forcesCriteria and forcesCriteria.completed)
    return {
        allBossesKilled = allBossesKilled,
        bossesKilled = bossesKilled,
        forcesPercent = forcesPercent,
        forcesAt100 = forcesAt100,
        bossCount = maxBoss,
        bossKillTimes = bossKillTimes,
        forcesCurrent = forcesCurrent,
        forcesTotal = forcesTotal,
    }
end

-- Comprehensive completion info extraction
-- Supports both new (GetChallengeCompletionInfo) and legacy APIs
local function GetCompletionInfoCompat()
    -- Try the modern API first.
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

-- Returns true when C_ChallengeMode.GetChallengeCompletionInfo() has run completion data (same signal MPlusTimer uses).
local function HasValidCompletionInfo()
    local info = GetCompletionInfoCompat()
    if not info or not info.mapID or info.mapID == 0 then
        return false
    end
    local t = info.time or info.completionTime or info.duration
    if type(t) == "number" and t > 0 then
        return true
    end
    if info.level and info.level > 0 then
        return true
    end
    return false
end

-- Try to get keystone level for a completed run from run history (same mapID). Returns level or nil.
local function GetLevelFromRunHistoryForMap(mapID)
    if not C_MythicPlus or type(C_MythicPlus.GetRunHistory) ~= "function" or not mapID then
        return nil
    end
    local runHistory = C_MythicPlus.GetRunHistory(false, true)
    if not runHistory or #runHistory == 0 then
        return nil
    end
    for i = #runHistory, 1, -1 do
        local run = runHistory[i]
        if run and run.mapChallengeModeID == mapID and run.level and run.level > 0 then
            return run.level
        end
    end
    return nil
end

-- Build CurrentRunData from CHALLENGE_MODE_COMPLETED_REWARDS payload (mapID, medal, timeMS).
-- Does not call GetChallengeCompletionInfo(), so works when that API is restricted (e.g. WoW 12+).
-- See: https://github.com/tomrus88/BlizzardInterfaceCode/blob/master/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChallengeModeInfoDocumentation.lua
-- Level: prefer CHALLENGE_MODE_START capture; if missing, try C_MythicPlus.GetRunHistory for this map (populated shortly after completion).
-- Returns true if run data was built.
local function BuildRunDataFromRewardsPayload(mapID, medal, timeMS)
    if not mapID or mapID == 0 or not timeMS or timeMS <= 0 then
        return false
    end
    -- Level: from CHALLENGE_MODE_START first; then from run history (API may be populated a few seconds after completion)
    local level = (MPT.MythicPlusKeystoneLevel and MPT.MythicPlusMapID == mapID) and MPT.MythicPlusKeystoneLevel or nil
    if not level or level <= 0 then
        level = GetLevelFromRunHistoryForMap(mapID)
    end
    if not level or level <= 0 then
        return false
    end
    local durationSeconds = timeMS / 1000
    -- medal: 0 = no medal (over time), 1+ = in time (1=no upgrade, 2=1 upgrade, etc.)
    local onTime = (medal ~= 0)

    local name = GetDungeonNameFromMapID(mapID)
    if not name then
        name = "Unknown Dungeon (ID: " .. tostring(mapID) .. ")"
    end

    local completionMembers = BuildGroupMembersFromCompletionMembers((GetCompletionInfoCompat() or {}).members)
    local playerStats = MergePreferredPlayerList(completionMembers, CollectGroupPlayerStats(), 5)
    local startTime = (MPT.CombatLog and MPT.CombatLog.startTime) or time()
    if durationSeconds and durationSeconds > 0 then
        startTime = time() - durationSeconds
    end

    local deathCount, timeLost = 0, 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local deaths, lostTime = C_ChallengeMode.GetDeathCount()
        if deaths then
            deathCount = deaths
            timeLost = lostTime or 0
        end
    end
    if C_ChallengeMode and C_ChallengeMode.GetStartTime then
        local apiStartTime = C_ChallengeMode.GetStartTime()
        if apiStartTime and apiStartTime > 0 then
            startTime = apiStartTime
        end
    end

    local scenarioState = GetScenarioCompletionState()
    local earlyForces = GetEnemyForcesProgress()
    local capturedMobData = false
    if scenarioState and scenarioState.forcesAt100 and scenarioState.forcesTotal and scenarioState.forcesTotal > 0 then
        capturedMobData = true
        earlyForces = earlyForces or {}
        earlyForces.current = scenarioState.forcesCurrent
        earlyForces.total = scenarioState.forcesTotal
        earlyForces.percent = scenarioState.forcesPercent >= 100 and 100 or scenarioState.forcesPercent
    elseif earlyForces and earlyForces.percent and earlyForces.percent > 0 then
        capturedMobData = true
    end
    local bossKillTimes = (scenarioState and scenarioState.bossKillTimes and #scenarioState.bossKillTimes > 0) and scenarioState.bossKillTimes or nil

    MPT.CurrentRunData = {
        dungeonID = mapID,
        dungeonName = name,
        keystoneLevel = level,
        affixes = nil,
        keystoneUpgrades = nil,
        completed = onTime,
        players = playerStats,
        groupMembers = ClonePlayerList(playerStats),
        startTime = startTime,
        completionTime = time(),
        completionDuration = durationSeconds,
        saved = false,
        deathCount = deathCount,
        timeLost = timeLost,
        mobsKilled = capturedMobData and (earlyForces.current or 0) or nil,
        mobsTotal = capturedMobData and (earlyForces.total or 0) or nil,
        overallMobPercentage = capturedMobData and earlyForces.percent or nil,
        bossKillTimes = bossKillTimes,
        onTime = onTime,
    }
    L("INFO", "BuildRunDataFromRewardsPayload: built from event payload (mapID=" .. tostring(mapID) .. " level=" .. tostring(level) .. " timeMS=" .. tostring(timeMS) .. " medal=" .. tostring(medal) .. ")")
    return true
end

-- Try to build CurrentRunData from C_MythicPlus.GetRunHistory (MPlusTimer uses this 5s after completion). Returns true if built.
local function TryBuildFromRunHistory()
    if not C_MythicPlus or not C_MythicPlus.GetRunHistory then
        return false
    end
    local runHistory = C_MythicPlus.GetRunHistory(false, true)
    if not runHistory or #runHistory == 0 then
        return false
    end
    for i = #runHistory, 1, -1 do
        local run = runHistory[i]
        if run and run.completed and run.mapChallengeModeID and run.level and run.level > 0 then
            Events:ReconstructRunDataFromHistory(run)
            if MPT.CurrentRunData then
                return true
            end
        end
    end
    return false
end

local function RunHistoryCompletionDateToTimestamp(run)
    if not run or not run.completionDate then
        return nil
    end
    if type(run.completionDate) == "number" then
        return run.completionDate
    end
    if type(run.completionDate) == "table" then
        local ok, ts = pcall(time, run.completionDate)
        if ok and ts then
            return ts
        end
    end
    return nil
end

local function GetRunHistoryKey(run)
    if not run then
        return nil
    end
    local mapID = tonumber(run.mapChallengeModeID) or 0
    local level = tonumber(run.level) or 0
    local durationSec = tonumber(run.durationSec) or 0
    local completionTs = tonumber(RunHistoryCompletionDateToTimestamp(run)) or 0
    return string.format("%d_%d_%d_%d", mapID, level, durationSec, completionTs)
end

function Events:StopCriteriaCompletionTracker()
    if self.criteriaCompletionTracker then
        self.criteriaCompletionTracker:Cancel()
        self.criteriaCompletionTracker = nil
    end
    self.criteriaCompletionPollInterval = nil
end

function Events:StartCriteriaCompletionTracker(intervalSeconds)
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        L("ERROR", "StartCriteriaCompletionTracker: C_Timer.NewTicker not available!")
        return
    end

    -- Always poll at 1s regardless of the caller-supplied interval.
    local interval = 1

    if self.criteriaCompletionTracker and self.criteriaCompletionPollInterval == interval then
        L("INFO", "StartCriteriaCompletionTracker: poller already running at 1s, skipping restart")
        return
    end

    self:StopCriteriaCompletionTracker()
    self.criteriaCompletionPollInterval = interval
    local tickCount = 0

    self.criteriaCompletionTracker = C_Timer.NewTicker(interval, function()
        tickCount = tickCount + 1

        if MPT.CurrentRunData and MPT.CurrentRunData.saved then
            Events:StopCriteriaCompletionTracker()
            return
        end

        if not C_ChallengeMode or type(C_ChallengeMode.GetChallengeCompletionInfo) ~= "function" then
            return
        end

        local challengeModeActive = C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() or false
        local info = C_ChallengeMode.GetChallengeCompletionInfo()


        -- Require info.time > 0 to distinguish a completed run from stale data retained
        -- from the previous run (GetChallengeCompletionInfo holds the last result until the
        -- next run completes, so mapChallengeModeID alone is not a reliable completion signal).
        if info and info.mapChallengeModeID and info.mapChallengeModeID > 0 and info.time and info.time > 0 then
            L("INFO", "CompletionPoller tick #" .. tickCount .. ": valid completion info (mapID=" .. tostring(info.mapChallengeModeID) .. " level=" .. tostring(info.level) .. " time=" .. tostring(info.time) .. "ms) - saving in 5s")
            Events:StopCriteriaCompletionTracker()
            C_Timer.After(5, function()
                if not MPT.CurrentRunData or not MPT.CurrentRunData.saved then
                    if MPT.Events and MPT.Events.FinalizeRun then
                        MPT.Events:FinalizeRun("completion_info_poll")
                    end
                end
            end)
        else
            L("INFO", "CompletionPoller tick #" .. tickCount .. ": no completion info yet (challengeModeActive=" .. tostring(challengeModeActive) .. " InMythicPlus=" .. tostring(MPT.InMythicPlus) .. ")")
            -- If challenge mode is gone, InMythicPlus is cleared, and there is no unsaved run,
            -- there is nothing left to save — stop the poller.
            local hasUnsavedRun = MPT.CurrentRunData and not MPT.CurrentRunData.saved
            if not challengeModeActive and not MPT.InMythicPlus and not hasUnsavedRun then
                L("INFO", "CompletionPoller: no active run and no unsaved data - stopping poller")
                Events:StopCriteriaCompletionTracker()
            end
        end
    end)
    L("INFO", "Completion poller started (1s interval)")
end

function Events:StopRunStateWatcher()
    if self.runStateWatcherTicker then
        self.runStateWatcherTicker:Cancel()
        self.runStateWatcherTicker = nil
    end
    self.runStateWatcherInterval = nil
end

function Events:StartRunStateWatcher(intervalSeconds)
    if not C_Timer or type(C_Timer.NewTicker) ~= "function" then
        L("ERROR", "StartRunStateWatcher: C_Timer.NewTicker not available!")
        return
    end

    local interval = tonumber(intervalSeconds) or 1
    if interval <= 0 then
        interval = 1
    end

    if self.runStateWatcherTicker and self.runStateWatcherInterval == interval then
        return
    end

    self:StopRunStateWatcher()
    self.runStateWatcherInterval = interval
    local watchTick = 0
    L("INFO", "RunStateWatcher starting (" .. tostring(interval) .. "s interval)")
    self.runStateWatcherTicker = C_Timer.NewTicker(interval, function()
        watchTick = watchTick + 1

        -- Primary detection: IsChallengeModeActive
        local challengeActive = C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function"
            and C_ChallengeMode.IsChallengeModeActive() or false

        -- Secondary detection: GetActiveChallengeMapID returns non-zero when inside an active M+ key
        if not challengeActive and C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
            if activeMapID and activeMapID > 0 then
                L("INFO", "RunStateWatcher tick#" .. watchTick .. ": GetActiveChallengeMapID()=" .. tostring(activeMapID) .. ", treating as challenge active")
                challengeActive = true
            end
        end
        L("INFO", "RunStateWatcher tick#" .. watchTick .. " challengeActive=" .. tostring(challengeActive) .. " InMythicPlus=" .. tostring(MPT.InMythicPlus) .. " criteriaTracker=" .. tostring(Events.criteriaCompletionTracker ~= nil))

        if challengeActive and not MPT.InMythicPlus then
            if MPT.RunJustSaved then
                -- Run already saved for this instance; wait until PLAYER_ENTERING_WORLD to re-arm.
                L("INFO", "RunStateWatcher tick#" .. watchTick .. ": challenge active but RunJustSaved=true - skipping re-bootstrap")
            else
                L("INFO", "RunStateWatcher tick#" .. watchTick .. ": challenge active, setting InMythicPlus=true and starting poller")
                print("|cff00ffaa[StormsDungeonData]|r Challenge mode active - starting run tracking")
                MPT.InMythicPlus = true
                Events:EnsureCriteriaTrackingForActiveRun("state_watcher")
            end
        elseif MPT.InMythicPlus and not Events.criteriaCompletionTracker then
            -- Keep the completion poller alive if it somehow stopped mid-run.
            L("WARN", "RunStateWatcher tick#" .. watchTick .. ": InMythicPlus but poller stopped - restarting")
            Events:StartCriteriaCompletionTracker(1)
        end
    end)
    L("INFO", "Run-state watcher started (" .. tostring(interval) .. "s)")
end

function Events:InitializeRunCompletionRequirements(mapID)
    local targetMapID = tonumber(mapID) or 0
    if targetMapID == 0 and C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        targetMapID = tonumber(C_ChallengeMode.GetActiveChallengeMapID()) or 0
    end

    local encounterIDs = GetEncounterIDsForMap(targetMapID) or {}
    local forces = GetEnemyForcesProgress()
    local scenarioState = GetScenarioCompletionState()
    local scenarioBossCount = (scenarioState and tonumber(scenarioState.bossCount)) or 0
    local forcesTotal = (forces and forces.total) or (scenarioState and scenarioState.forcesTotal) or 0
    local requiredForcesPercent = 100
    local bossCount = #encounterIDs
    if bossCount == 0 and scenarioBossCount and scenarioBossCount > 0 then
        bossCount = scenarioBossCount
    end

    MPT.RunCompletionRequirements = {
        mapID = targetMapID,
        bossEncounterIDs = encounterIDs,
        bossCount = bossCount,
        enemyForcesRequiredPercent = requiredForcesPercent,
        enemyForcesTotal = forcesTotal,
    }
    MPT.RunCompletionProgress = nil
    self.criteriaCompletionSaveTriggered = nil
    self.criteriaCompletionSaveAttemptTimestamp = nil

    L("INFO", "Initialized run completion requirements: mapID=" .. tostring(targetMapID) .. ", bossCount=" .. tostring(bossCount) .. ", requiredEnemyForces=" .. tostring(requiredForcesPercent) .. "%")
end

function Events:TryBootstrapMythicPlusRun(triggerReason, allowDungeonDifficultyFallback)
    local challengeActive = false
    if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" then
        challengeActive = C_ChallengeMode.IsChallengeModeActive() and true or false
    end
    L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] challengeActive=" .. tostring(challengeActive) .. " allowFallback=" .. tostring(allowDungeonDifficultyFallback) .. " InMythicPlus=" .. tostring(MPT.InMythicPlus))

    local hasChallengeStartTime = false
    local challengeStartTimestamp = nil
    if C_ChallengeMode and type(C_ChallengeMode.GetStartTime) == "function" then
        local apiStart = C_ChallengeMode.GetStartTime()
        if apiStart and apiStart > 0 then
            hasChallengeStartTime = true
            challengeStartTimestamp = math.floor(apiStart / 1000)
        end
    end
    L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] hasChallengeStartTime=" .. tostring(hasChallengeStartTime) .. " challengeStartTimestamp=" .. tostring(challengeStartTimestamp))

    local inMythicPartyDungeon = false
    if allowDungeonDifficultyFallback then
        local _, instanceType, difficultyID = GetInstanceInfo()
        inMythicPartyDungeon = (instanceType == "party" and difficultyID == 8)
        L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] instanceType=" .. tostring(instanceType) .. " difficultyID=" .. tostring(difficultyID) .. " inMythicPartyDungeon=" .. tostring(inMythicPartyDungeon))
    end

    if not challengeActive and not hasChallengeStartTime and not inMythicPartyDungeon then
        L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] all checks false - returning false")
        return false
    end

    local previousStart = tonumber(MPT.MythicPlusRunStartTimestamp) or 0
    local candidateStart = challengeStartTimestamp or (previousStart > 0 and previousStart) or time()
    local detectedNewRun = false

    if challengeStartTimestamp and challengeStartTimestamp > 0 then
        if previousStart <= 0 then
            detectedNewRun = true
            L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] detectedNewRun: previousStart <= 0")
        elseif math.abs(challengeStartTimestamp - previousStart) >= 2 then
            detectedNewRun = true
            L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] detectedNewRun: timestamp drift abs(" .. tostring(challengeStartTimestamp) .. " - " .. tostring(previousStart) .. ") >= 2")
        elseif MPT.LastSavedRunTime and challengeStartTimestamp > MPT.LastSavedRunTime then
            detectedNewRun = true
            L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] detectedNewRun: challengeStart > LastSavedRunTime (" .. tostring(MPT.LastSavedRunTime) .. ")")
        end
    elseif previousStart <= 0 then
        detectedNewRun = true
        L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] detectedNewRun: no apiStart and previousStart <= 0")
    end
    L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] previousStart=" .. tostring(previousStart) .. " candidateStart=" .. tostring(candidateStart) .. " detectedNewRun=" .. tostring(detectedNewRun))

    if detectedNewRun then
        MPT.CurrentRunData = nil
        MPT.LastRewardsPayload = nil
        MPT.LastEnemyForces = nil
        MPT.KilledEncounterIDs = {}
        MPT.MythicPlusBossKillCount = 0
        MPT.DungeonEncounterIDs = nil
        MPT.RunCompletionRequirements = nil
        MPT.RunCompletionProgress = nil
        self.criteriaCompletionSaveTriggered = nil
        self.criteriaCompletionSaveAttemptTimestamp = nil
        ResetRunAnnouncements()
        ClearCompletionSignal()
        RecordFlow("RUN_RESET", tostring(triggerReason or "bootstrap"))
    end

    if MPT.InMythicPlus and not detectedNewRun then
        L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] already InMythicPlus, no new run - returning true (no-op)")
        return true
    end

    MPT.InMythicPlus = true
    MPT.MythicPlusRunStartTimestamp = candidateStart
    MPT.RunBootstrapRecovered = true
    MPT.RunBootstrapReason = tostring(triggerReason or "bootstrap")
    MPT.RunBootstrapAt = time()
    MPT.KilledEncounterIDs = MPT.KilledEncounterIDs or {}
    L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] setting InMythicPlus=true, runStart=" .. tostring(candidateStart))

    local activeMapID = nil
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
    end
    if activeMapID and activeMapID > 0 then
        MPT.MythicPlusMapID = activeMapID
        MPT.MythicPlusDungeonName = GetDungeonNameFromMapID(activeMapID)
        MPT.DungeonEncounterIDs = GetEncounterIDsForMap(activeMapID)
    end

    MPT.MythicPlusKeystoneLevel = MPT.MythicPlusKeystoneLevel or nil
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
        local a = C_ChallengeMode.GetActiveKeystoneInfo()
        local level = nil
        if type(a) == "table" then
            level = a.level or a.keystoneLevel
        else
            level = a
        end
        if level and level > 0 then
            MPT.MythicPlusKeystoneLevel = level
        end
    end

    self:StopEndOfDungeonHistoryPoll()
    self:StopCriteriaCompletionTracker()
    self:InitializeRunHistoryTracking()

    if not MPT.RunCompletionRequirements then
        self:InitializeRunCompletionRequirements(MPT.MythicPlusMapID)
    elseif MPT.RunCompletionRequirements and (MPT.RunCompletionRequirements.mapID or 0) == 0 and MPT.MythicPlusMapID and MPT.MythicPlusMapID > 0 then
        self:InitializeRunCompletionRequirements(MPT.MythicPlusMapID)
    end
    self:StartCriteriaCompletionTracker(5)

    if MPT.LiveTracker and MPT.LiveTracker.Reset and (not MPT.LiveTracker.startTime) then
        MPT.LiveTracker:Reset()
    end

    if MPT.CombatLog and MPT.CombatLog.StartTracking then
        if not MPT.CombatLog.isTracking then
            MPT.CombatLog:StartTracking()
        else
            -- Refresh roster if tracking was already running while we were inside the dungeon.
            MPT.CombatLog:StartTracking()
        end
        if MPT.CombatLog.isTracking then
            AnnounceTrackingStarted(triggerReason or "bootstrap")
        end
    end

    -- Reporter election: ensure presence is broadcast on bootstrap recovery
    if MPT.ReporterElection and MPT.ReporterElection.BroadcastPresence then
        MPT.ReporterElection:BroadcastPresence()
    end

    L("INFO", "TryBootstrap[" .. tostring(triggerReason) .. "] complete: InMythicPlus=" .. tostring(MPT.InMythicPlus) .. " mapID=" .. tostring(MPT.MythicPlusMapID) .. " keystoneLevel=" .. tostring(MPT.MythicPlusKeystoneLevel) .. " criteriaTracker=" .. tostring(self.criteriaCompletionTracker ~= nil))
    L("INFO", "Recovered Mythic+ run state via bootstrap (reason=" .. tostring(triggerReason) .. ", mapID=" .. tostring(MPT.MythicPlusMapID) .. ")")
    RecordFlow("RUN_BOOTSTRAP", tostring(triggerReason or "bootstrap"))
    return true
end

function Events:EvaluateRunCompletionCriteria(triggerReason)
    -- No-op: completion is now detected exclusively by the 1s GetChallengeCompletionInfo poller
    -- started in StartCriteriaCompletionTracker. No boss/forces/numCriteria evaluation needed.
end

function Events:_EvaluateRunCompletionCriteria_UNUSED(triggerReason)
    L("INFO", "EvaluateRunCompletionCriteria[" .. tostring(triggerReason) .. "] InMythicPlus=" .. tostring(MPT.InMythicPlus) .. " saved=" .. tostring(MPT.CurrentRunData and MPT.CurrentRunData.saved) .. " criteriaTriggered=" .. tostring(self.criteriaCompletionSaveTriggered))
    if not MPT.InMythicPlus then
        L("WARN", "EvaluateRunCompletionCriteria[" .. tostring(triggerReason) .. "] not InMythicPlus - attempting bootstrap")
        if not self:TryBootstrapMythicPlusRun(triggerReason or "criteria_eval", false) then
            -- Bootstrap failed (challenge mode is no longer active). Before giving up, check
            -- whether the scenario has torn down (numCriteria=0) and prior progress had at least
            -- one completion condition met (all bosses killed OR forces at required %).
            -- Either condition combined with the scenario ending is enough to save the run.
            local prev = MPT.RunCompletionProgress
            if prev and not self.criteriaCompletionSaveTriggered then
                local nc = 0
                if C_Scenario and type(C_Scenario.GetStepInfo) == "function" then
                    local _, _, n = C_Scenario.GetStepInfo()
                    nc = tonumber(n) or 0
                end
                if nc == 0 and (prev.allBossesKilled or prev.forcesAtRequired) then
                    L("INFO", "EvaluateRunCompletionCriteria: bootstrap failed but numCriteria=0 with prior allBossesKilled=" .. tostring(prev.allBossesKilled) .. " forcesAtRequired=" .. tostring(prev.forcesAtRequired) .. " - triggering save")
                    self.criteriaCompletionSaveTriggered = true
                    MarkCompletionSignal("scenario_cleared_on_bootstrap_fail")
                    if C_Timer and C_Timer.After then
                        C_Timer.After(3, function()
                            if not MPT.CurrentRunData or not MPT.CurrentRunData.saved then
                                if MPT.PerformManualSave then
                                    MPT.PerformManualSave("scenario_cleared")
                                end
                            end
                        end)
                    end
                    return
                end
            end
            L("WARN", "EvaluateRunCompletionCriteria[" .. tostring(triggerReason) .. "] bootstrap failed - returning early")
            return
        end
    end
    if MPT.LastSavedRunTime and MPT.MythicPlusRunStartTimestamp and MPT.LastSavedRunTime >= MPT.MythicPlusRunStartTimestamp then
        local challengeActiveNow = false
        if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" then
            challengeActiveNow = C_ChallengeMode.IsChallengeModeActive() and true or false
        end
        -- Ignore stale timestamp overlap while challenge mode is currently active.
        if not challengeActiveNow then
            -- Before stopping, check if the scenario just ended (numCriteria=0) with a
            -- completion condition already met. The timestamp overlap is from the previous run;
            -- the current run still needs saving.
            local prev = MPT.RunCompletionProgress
            if prev and not self.criteriaCompletionSaveTriggered and (prev.allBossesKilled or prev.forcesAtRequired) then
                local nc = 0
                if C_Scenario and type(C_Scenario.GetStepInfo) == "function" then
                    local _, _, n = C_Scenario.GetStepInfo()
                    nc = tonumber(n) or 0
                end
                if nc == 0 then
                    L("INFO", "Run already saved (timestamp check) but numCriteria=0 with allBossesKilled=" .. tostring(prev.allBossesKilled) .. " forcesAtRequired=" .. tostring(prev.forcesAtRequired) .. " - current run needs saving, proceeding")
                    print("|cff00ffaa[StormsDungeonData]|r Scenario ended (numCriteria=0) with " .. (prev.allBossesKilled and "all bosses killed" or "forces met") .. " - overriding stale timestamp check, triggering save")
                    self.criteriaCompletionSaveTriggered = true
                    MarkCompletionSignal("scenario_cleared_timestamp_override")
                    if C_Timer and C_Timer.After then
                        C_Timer.After(3, function()
                            if not MPT.CurrentRunData or not MPT.CurrentRunData.saved then
                                if MPT.PerformManualSave then
                                    MPT.PerformManualSave("scenario_cleared")
                                end
                            end
                        end)
                    end
                    self:StopCriteriaCompletionTracker()
                    return
                end
            end
            L("INFO", "Run already saved (timestamp check) - stopping tracker")
            self:StopCriteriaCompletionTracker()
            return
        end
    end
    if MPT.CurrentRunData and MPT.CurrentRunData.saved then
        L("INFO", "CurrentRunData.saved=true - stopping tracker")
        self:StopCriteriaCompletionTracker()
        return
    end

    local previousProgress = MPT.RunCompletionProgress
    local scenarioState = GetScenarioCompletionState()
    local forces = GetEnemyForcesProgress()
    if forces and forces.percent then
        MPT.LastEnemyForces = forces
    end

    local requirements = MPT.RunCompletionRequirements or {}
    local encounterIDs = requirements.bossEncounterIDs
    local bossCount = (requirements and requirements.bossCount) or 0
    local bossesKilled = 0
    local allBossesKilled = false

    if encounterIDs and #encounterIDs > 0 then
        bossCount = #encounterIDs
        for _, eid in ipairs(encounterIDs) do
            if MPT.KilledEncounterIDs and MPT.KilledEncounterIDs[eid] then
                bossesKilled = bossesKilled + 1
            end
        end
        allBossesKilled = bossesKilled >= bossCount and bossCount > 0

        -- Fallback: the Encounter Journal may list encounter IDs that differ from what
        -- ENCOUNTER_END actually sends (a known issue for some last bosses). If the EJ-based
        -- count falls short, cross-check against: (1) the scenario API's own allBossesKilled flag,
        -- or (2) the raw ENCOUNTER_END kill counter vs the scenario's authoritative boss count.
        if not allBossesKilled then
            if scenarioState and scenarioState.allBossesKilled then
                L("INFO", "EvaluateRunCompletionCriteria: EJ ID mismatch detected - scenario reports allBossesKilled=true, overriding")
                allBossesKilled = true
                bossesKilled = math.max(bossesKilled, scenarioState.bossesKilled or bossCount)
                bossCount = scenarioState.bossCount or bossCount
            elseif (MPT.MythicPlusBossKillCount or 0) > 0 then
                local rawKills = MPT.MythicPlusBossKillCount
                local scenarioBossCount = (scenarioState and scenarioState.bossCount) or 0
                -- Use scenario boss count when available (authoritative); fall back to EJ count.
                local effectiveBossCount = (scenarioBossCount > 0) and scenarioBossCount or bossCount
                if rawKills >= effectiveBossCount and effectiveBossCount > 0 then
                    L("INFO", "EvaluateRunCompletionCriteria: EJ ID mismatch - rawKills(" .. rawKills .. ") >= effectiveBossCount(" .. effectiveBossCount .. "), overriding allBossesKilled")
                    allBossesKilled = true
                    bossesKilled = math.max(bossesKilled, rawKills)
                    bossCount = effectiveBossCount
                end
            end
        end
    else
        bossCount = (scenarioState and scenarioState.bossCount) or bossCount
        bossesKilled = (scenarioState and scenarioState.bossesKilled) or 0
        allBossesKilled = (scenarioState and scenarioState.allBossesKilled) or false

        -- Also check raw kill counter when scenario state is unavailable or stale.
        if not allBossesKilled and (MPT.MythicPlusBossKillCount or 0) > 0 and bossCount > 0 then
            if MPT.MythicPlusBossKillCount >= bossCount then
                L("INFO", "EvaluateRunCompletionCriteria: no EJ IDs, rawKills(" .. tostring(MPT.MythicPlusBossKillCount) .. ") >= bossCount(" .. bossCount .. "), setting allBossesKilled=true")
                allBossesKilled = true
                bossesKilled = math.max(bossesKilled, MPT.MythicPlusBossKillCount)
            end
        end
    end

    if bossCount == 0 and scenarioState and scenarioState.bossCount and scenarioState.bossCount > 0 then
        bossCount = scenarioState.bossCount
        if MPT.RunCompletionRequirements then
            MPT.RunCompletionRequirements.bossCount = bossCount
        end
    end

    -- Keep the best-known boss progress if API data is temporarily unavailable.
    if (not scenarioState or bossCount == 0) and previousProgress then
        bossCount = math.max(tonumber(bossCount) or 0, tonumber(previousProgress.bossCount) or 0)
        bossesKilled = math.max(tonumber(bossesKilled) or 0, tonumber(previousProgress.bossesKilled) or 0)
        if bossCount > 0 then
            allBossesKilled = bossesKilled >= bossCount
        end
    end

    local requiredEnemyForcesPercent = tonumber(requirements.enemyForcesRequiredPercent) or 100
    local forcesPercent = NormalizeEnemyForcesPercent((forces and forces.percent) or (scenarioState and scenarioState.forcesPercent)) or 0
    if (not forces or not forces.percent) and previousProgress and tonumber(previousProgress.forcesPercent or 0) > 0 then
        forcesPercent = math.max(forcesPercent, tonumber(previousProgress.forcesPercent) or 0)
    end
    AnnounceMobMilestones(forcesPercent)
    local forcesAtRequired = forcesPercent >= requiredEnemyForcesPercent or (scenarioState and scenarioState.forcesAt100) or false

    -- Scenario-cleared completion detection.
    -- Trigger when numCriteria drops to 0 (scenario torn down) AND at least one completion
    -- condition was already met: (allBossesKilled AND numCriteria=0) OR (forcesAtRequired AND numCriteria=0).
    if not MPT.RunCompletionSignal then
        local nc = 0
        if C_Scenario and type(C_Scenario.GetStepInfo) == "function" then
            local _, _, n = C_Scenario.GetStepInfo()
            nc = tonumber(n) or 0
        end
        if nc == 0 and (allBossesKilled or forcesAtRequired) then
            L("INFO", "EvaluateRunCompletionCriteria: numCriteria=0 with allBossesKilled=" .. tostring(allBossesKilled) .. " forcesAtRequired=" .. tostring(forcesAtRequired) .. " - dungeon ended, inferring completion")
            L("INFO","|cff00ffaa[StormsDungeonData]|r Scenario ended (numCriteria=0) with " .. (allBossesKilled and "all bosses killed" or "forces met") .. " - inferring dungeon completion")
            local prevBossesKilled = previousProgress and (tonumber(previousProgress.bossesKilled) or 0) or 0
            local prevBossesLeft   = previousProgress and (tonumber(previousProgress.bossesRemaining) or 0) or 0
            allBossesKilled  = true
            bossesKilled     = math.max(bossesKilled, (bossCount > 0) and bossCount or (prevBossesKilled + prevBossesLeft))
            forcesAtRequired = true
            MarkCompletionSignal("scenario_cleared")
        end
    end

    local bossesRemaining = math.max(0, (bossCount or 0) - (bossesKilled or 0))
    local enemyForcesRemainingPercent = math.max(0, requiredEnemyForcesPercent - (forcesPercent or 0))

    L("INFO", "Criteria: bosses=" .. tostring(bossesKilled) .. "/" .. tostring(bossCount) .. " (all=" .. tostring(allBossesKilled) .. "), forces=" .. tostring(forcesPercent) .. "% (req=" .. tostring(requiredEnemyForcesPercent) .. "%, met=" .. tostring(forcesAtRequired) .. ")")

    MPT.RunCompletionProgress = {
        allBossesKilled = allBossesKilled,
        bossesKilled = bossesKilled,
        bossesRemaining = bossesRemaining,
        bossCount = bossCount,
        forcesPercent = forcesPercent,
        enemyForcesRemainingPercent = enemyForcesRemainingPercent,
        forcesAtRequired = forcesAtRequired,
        triggerReason = triggerReason,
        updatedAt = time(),
    }

    local shouldUseFastPoll = (allBossesKilled and not forcesAtRequired) or (forcesAtRequired and bossesRemaining == 1)
    local desiredInterval = shouldUseFastPoll and 0.5 or 5
    if self.criteriaCompletionPollInterval ~= desiredInterval then
        self:StartCriteriaCompletionTracker(desiredInterval)
    end

    if allBossesKilled and forcesAtRequired and not self.criteriaCompletionSaveTriggered then
        self.criteriaCompletionSaveTriggered = true
        self.criteriaCompletionSaveAttemptTimestamp = time()
        L("INFO", "=== RUN COMPLETION CRITERIA MET - TRIGGERING SAVE ===")
        L("INFO", "Run completion criteria met (reason=" .. tostring(triggerReason) .. ") - scheduling save")
        print("|cff00ffaa[StormsDungeonData]|r === RUN COMPLETION CRITERIA MET ===")
        print("|cff00ffaa[StormsDungeonData]|r   Bosses: " .. tostring(bossesKilled) .. "/" .. tostring(bossCount) .. " (all killed: " .. tostring(allBossesKilled) .. ")")
        print("|cff00ffaa[StormsDungeonData]|r   Enemy forces: " .. tostring(forcesPercent) .. "% (required: " .. tostring(requiredEnemyForcesPercent) .. "%)")
        print("|cff00ffaa[StormsDungeonData]|r   Trigger reason: " .. tostring(triggerReason))
        print("|cff00ffaa[StormsDungeonData]|r Scheduling save in 3 seconds...")
        
        -- Request fresh data
        if C_MythicPlus and C_MythicPlus.RequestMapInfo then
            C_MythicPlus.RequestMapInfo()
        end
        
        -- Stop any existing timers
        self:StopEndOfDungeonHistoryPoll()
        
        -- Schedule save 3 seconds later (shorter than CHALLENGE_MODE_COMPLETED since we detect it earlier)
        if C_Timer and C_Timer.After then
            C_Timer.After(3, function()
                if not MPT.CurrentRunData or not MPT.CurrentRunData.saved then
                    L("INFO", "Criteria completion timer: executing save")
                    print("|cff00ffaa[StormsDungeonData]|r Criteria completion 3s save executing...")
                    if MPT.PerformManualSave then
                        MPT.PerformManualSave("criteria_completion")
                    else
                        print("|cffff4444[StormsDungeonData]|r ERROR: MPT.PerformManualSave not available!")
                    end
                else
                    L("INFO", "Criteria completion timer: run already saved, skipping")
                end
            end)
        end
    end
end

function Events:EnsureCriteriaTrackingForActiveRun(triggerReason)
    if not MPT.InMythicPlus then
        if not self:TryBootstrapMythicPlusRun(triggerReason or "ensure_active_run", false) then
            return
        end
    end

    if not MPT.MythicPlusRunStartTimestamp then
        MPT.MythicPlusRunStartTimestamp = time()
    end

    if not MPT.RunCompletionRequirements then
        local mapID = MPT.MythicPlusMapID
        if (not mapID or mapID == 0) and C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            mapID = C_ChallengeMode.GetActiveChallengeMapID()
            if mapID and mapID > 0 then
                MPT.MythicPlusMapID = mapID
            end
        end
        self:InitializeRunCompletionRequirements(mapID)
    end

    if not self.criteriaCompletionTracker then
        self:StartCriteriaCompletionTracker(5)
    end

    self:EvaluateRunCompletionCriteria(triggerReason or "ensure_active_run")
end

local function CollectGroupPlayerStats()
    local playerStats = {}

    -- Collect party members first
    for i = 1, 4 do
        local unitID = "party" .. i
        if UnitExists(unitID) then
            local name, realm = UnitName(unitID)
            if realm and realm ~= "" then name = name .. "-" .. realm end
            local class = select(2, UnitClass(unitID))
            local role = UnitGroupRolesAssigned(unitID)
            local entry = MPT.Database:CreatePlayerStats(unitID, name, class, role)
            -- Eagerly read inspect spec — data is freshest right at completion time
            if GetInspectSpecialization then
                local sid = GetInspectSpecialization(unitID)
                if sid and sid > 0 then
                    entry.specID = sid
                    local guid = UnitGUID(unitID)
                    if guid then MPT.SpecCache[guid] = sid end
                end
            end
            table.insert(playerStats, entry)
        end
    end

    -- Add the local player
    local playerName, playerRealm = UnitName("player")
    if playerRealm and playerRealm ~= "" then
        playerName = playerName .. "-" .. playerRealm
    end
    local playerClass = select(2, UnitClass("player"))
    local playerRole = UnitGroupRolesAssigned("player")
    if not playerRole or playerRole == "" or playerRole == "NONE" then
        local specIndex = GetSpecialization and GetSpecialization() or nil
        if specIndex and GetSpecializationInfo then
            local _, _, _, _, specRole = GetSpecializationInfo(specIndex)
            if specRole == "TANK" or specRole == "HEALER" or specRole == "DAMAGER" then
                playerRole = specRole
            end
        end
    end
    table.insert(playerStats, MPT.Database:CreatePlayerStats("player", playerName, playerClass, playerRole))

    return playerStats
end

-- Build run data for an abandoned key (surrender vote passed / left without completing). Saves progress up to that point as a failed run.
function Events:BuildRunDataForAbandon()
    local mapID = MPT.MythicPlusMapID
    if not mapID or mapID == 0 then
        if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            mapID = C_ChallengeMode.GetActiveChallengeMapID()
        end
    end
    if not mapID or mapID == 0 then
        L("WARN", "BuildRunDataForAbandon: no mapID (MythicPlusMapID=" .. tostring(MPT.MythicPlusMapID) .. ", GetActiveChallengeMapID=" .. tostring(mapID) .. ")")
        print("|cffff4444[StormsDungeonData]|r Cannot save abandoned key: no dungeon map ID")
        return false
    end
    local level = MPT.MythicPlusKeystoneLevel
    if not level or level == 0 then
        if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
            local a = C_ChallengeMode.GetActiveKeystoneInfo()
            if type(a) == "table" then
                level = a.level or a.keystoneLevel
            else
                level = a
            end
        end
    end
    if not level or level == 0 then
        L("WARN", "BuildRunDataForAbandon: no keystone level (MythicPlusKeystoneLevel=" .. tostring(MPT.MythicPlusKeystoneLevel) .. ", GetActiveKeystoneInfo=" .. tostring(level) .. ")")
        print("|cffff4444[StormsDungeonData]|r Cannot save abandoned key: no keystone level")
        return false
    end
    L("INFO", "Building abandoned run: mapID=" .. tostring(mapID) .. " level=" .. tostring(level))
    local name = MPT.MythicPlusDungeonName or GetDungeonNameFromMapID(mapID)
    if not name or name == "" then
        local zoneText = GetRealZoneText and GetRealZoneText()
        if zoneText and zoneText ~= "" then
            name = zoneText
            L("INFO", "BuildRunDataForAbandon: dungeon name from GetRealZoneText: " .. tostring(zoneText))
        end
    end
    name = name or ("Unknown (ID: " .. tostring(mapID) .. ")")
    L("INFO", "BuildRunDataForAbandon: resolved name='" .. tostring(name) .. "' from mapID=" .. tostring(mapID))
    local startTime = time()
    if C_ChallengeMode and C_ChallengeMode.GetStartTime then
        local apiStart = C_ChallengeMode.GetStartTime()
        if apiStart and apiStart > 0 then
            startTime = apiStart
        end
    end
    if MPT.CombatLog and MPT.CombatLog.startTime and MPT.CombatLog.startTime > 0 then
        startTime = MPT.CombatLog.startTime
    end
    local durationSeconds = time() - startTime
    if durationSeconds <= 0 then
        durationSeconds = 1
    end
    -- For abandoned keys the group is often already dismantled/teleported when this runs,
    -- so UnitExists("party1") etc. return false. We seed with an empty list here; FinalizeRun
    -- will repopulate from C_DamageMeter (the authoritative source for the current session).
    local playerStats = {}
    local deathCount, timeLost = 0, 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local d, lt = C_ChallengeMode.GetDeathCount()
        if d then deathCount = d end
        if lt then timeLost = lt end
    end
    -- Fallback: sum deaths from combat log if API returns nil/0 (after leaving dungeon)
    if deathCount == 0 and MPT.CombatLog and MPT.CombatLog.playerStats then
        for _, pstats in pairs(MPT.CombatLog.playerStats) do
            deathCount = deathCount + (pstats.deaths or 0)
        end
        L("INFO", "Using combat log death count: " .. tostring(deathCount))
    end
    local forcesPercent = 0
    local forcesCurrent, forcesTotal = 0, 0
    if MPT.LastEnemyForces and MPT.LastEnemyForces.percent then
        forcesPercent = MPT.LastEnemyForces.percent
        forcesCurrent = MPT.LastEnemyForces.current or 0
        forcesTotal = MPT.LastEnemyForces.total or 0
    end
    MPT.CurrentRunData = {
        dungeonID = mapID,
        dungeonName = name,
        keystoneLevel = level,
        affixes = nil,
        keystoneUpgrades = 0,
        completed = false,
        onTime = false,
        abandonReason = "abandon",
        players = playerStats,
        startTime = startTime,
        completionTime = nil,  -- No completion time for abandoned keys
        completionDuration = nil,  -- No duration for abandoned keys (logged as "abandon" only)
        saved = false,
        deathCount = deathCount,
        timeLost = timeLost,
        mobsKilled = forcesTotal > 0 and forcesCurrent or nil,
        mobsTotal = forcesTotal > 0 and forcesTotal or nil,
        overallMobPercentage = forcesPercent > 0 and forcesPercent or nil,
        bossKillTimes = nil,
    }
    L("INFO", "BuildRunDataForAbandon: built (mapID=" .. tostring(mapID) .. " +" .. tostring(level) .. " status=ABANDON)")
    L("INFO", "Abandoned key logged as FAILED: " .. tostring(name) .. " +" .. tostring(level) .. " (status: ABANDON)")
    return true
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

    -- Prefer completion API level; then level captured at CHALLENGE_MODE_START (avoids using post-run "active" key, e.g. +8 after a +12)
    local startLevel = (MPT.MythicPlusKeystoneLevel and (not mapID or MPT.MythicPlusMapID == mapID)) and MPT.MythicPlusKeystoneLevel or nil
    level = completionLevel or startLevel or level
    -- When we have no completion and no start level, "level" is from GetActiveKeystoneInfo (post-run key, e.g. +8). Prefer run history for this map.
    if mapID and (not completionLevel and not startLevel) and C_MythicPlus and type(C_MythicPlus.GetRunHistory) == "function" then
        local runHistory = C_MythicPlus.GetRunHistory(false, true)
        if runHistory then
            for i = 1, #runHistory do
                local r = runHistory[i]
                if r and r.completed and r.mapChallengeModeID == mapID and r.level and r.level > 0 then
                    level = r.level
                    print("|cff00ffaa[StormsDungeonData]|r Using keystone level from run history: +" .. tostring(level) .. " (avoids post-run active key)")
                    break
                end
            end
        end
    end
    keystoneUpgrades = completionKeystoneUpgrades or keystoneUpgrades
    
    -- Use completion API time first (same as MPlusTimer: GetChallengeCompletionInfo().time in ms -> /1000 for seconds)
    local durationSeconds = CompletionTimeToSeconds(completionTime) or NormalizeDurationSeconds(completionTime)

    -- Validate mapID before proceeding (CRITICAL for save validation)
    if not mapID or mapID == 0 then
        print("|cffff4444[StormsDungeonData]|r ERROR: Cannot build run data - invalid mapID (" .. tostring(mapID) .. ")")
        print("|cffff4444[StormsDungeonData]|r TIP: You must use /sdd force while in the dungeon or immediately after completion")
        return false
    end
    
    if not level or level == 0 then
        print("|cffff4444[StormsDungeonData]|r ERROR: Cannot build run data - invalid keystone level (" .. tostring(level) .. ")")
        return false
    end

    -- Completed = within time limit (same logic as OnChallengeModeCompleted)
    local runCompleted = true
    local completionOnTime = completion and completion.onTime
    if completionOnTime == false then
        runCompleted = false
    elseif completionOnTime ~= true and durationSeconds and durationSeconds > 0 then
        local timeLimit = GetDungeonTimeLimitSeconds(mapID)
        if timeLimit and durationSeconds > timeLimit then
            runCompleted = false
        end
    end

    -- Always use mapID for dungeon name to avoid getting current zone after teleporting out
    name = name or GetDungeonNameFromMapID(mapID)
    if not name then
        print("|cffff4444[StormsDungeonData]|r WARNING: Could not get dungeon name from mapID " .. tostring(mapID))
        name = "Unknown Dungeon (ID: " .. tostring(mapID) .. ")"
    end
    local completionMembers = BuildGroupMembersFromCompletionMembers(completion and completion.members)
    local playerStats = MergePreferredPlayerList(completionMembers, CollectGroupPlayerStats(), 5)

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
        completed = runCompleted,
        players = playerStats,
        groupMembers = ClonePlayerList(playerStats),
        startTime = startTime,
        completionTime = time(),
        completionDuration = durationSeconds,
        saved = false,
        oldDungeonScore = completion and completion.oldOverallDungeonScore,
        newDungeonScore = completion and completion.newOverallDungeonScore,
    }

    local timeStr = MPT.Utils and MPT.Utils.FormatDuration and MPT.Utils:FormatDuration(durationSeconds or 0) or tostring(durationSeconds)
    Chat("Run Complete: " .. tostring(name) .. " +" .. tostring(level) .. " in " .. timeStr)

    return true
end

-- Create event frame and register all events at module load time.
-- This MUST be top-level code: Frame:RegisterEvent() is protected in WoW 12+ and
-- raises ADDON_ACTION_FORBIDDEN when called from any tainted runtime call-chain
-- (e.g. a C_Timer callback scheduled inside a tainted event handler). Top-level
-- addon script execution is always untainted.
local eventFrame = CreateFrame("Frame")
Events.frame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
eventFrame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("SCENARIO_COMPLETED")
eventFrame:RegisterEvent("SCENARIO_UPDATE")
eventFrame:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
eventFrame:RegisterEvent("SCENARIO_POI_UPDATE")
eventFrame:RegisterEvent("WORLD_STATE_TIMER_START")
eventFrame:RegisterEvent("WORLD_STATE_TIMER_STOP")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED_REWARDS")
eventFrame:RegisterEvent("CHALLENGE_MODE_NEW_RECORD")
eventFrame:RegisterEvent("INSTANCE_ABANDON_VOTE_FINISHED")
eventFrame:RegisterEvent("ENCOUNTER_END")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("INSPECT_READY")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    Events:OnEvent(event, ...)
end)

function Events:Initialize()
    -- Guard against double-initialization
    if self._initialized then return end
    self._initialized = true

    -- All RegisterEvent / SetScript calls are done at module load time above.
    -- Just start the run-state watcher here.
    self:StartRunStateWatcher(5)

    L("INFO", "Events initialized; registered CHALLENGE_MODE_COMPLETED, CHALLENGE_MODE_COMPLETED_REWARDS, CHALLENGE_MODE_START, SCENARIO_*, PLAYER_ENTERING_WORLD, etc.")
end

function Events:OnEvent(event, ...)
    local args = {...}
    if event == "CHALLENGE_MODE_START" then
        local trace = EnsureFlowTrace()
        trace.events = {}
        trace.runStartedAt = time()
        RecordFlow("RUN_START", "CHALLENGE_MODE_START")
        -- Cache self immediately, then request party inspects; retry at +5s for late loaders
        CacheSpecFromUnit("player")
        C_Timer.After(2, RequestGroupInspects)
        C_Timer.After(5, function()
            RequestGroupInspects()
            BackfillCurrentRunSpecIDs()
        end)
    elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_COMPLETED_REWARDS" or event == "CHALLENGE_MODE_NEW_RECORD"
        or event == "SCENARIO_COMPLETED" or event == "ENCOUNTER_END" or event == "PLAYER_ENTERING_WORLD" then
        RecordFlow("EVENT", tostring(event) .. " args=" .. tostring(#args))
    end

    if event:match("CHALLENGE") or event:match("SCENARIO") or event == "PLAYER_ENTERING_WORLD" then
        L("INFO", "EVENT " .. tostring(event) .. " (args=" .. #args .. ")")
    end

    local success, err = pcall(function()
        if event == "ADDON_LOADED" then
            local addonName = args[1]
            if addonName == "StormsDungeonData" and not MPT._coreInitialized then
                MPT._coreInitialized = true
                MPT:Initialize()
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            self:OnPlayerEnteringWorld()
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            L("INFO", "CHALLENGE_MODE_COMPLETED received")
        elseif event == "INSTANCE_ABANDON_VOTE_FINISHED" then
            -- Handle abandon vote (same pattern as MPlusTimer)
            if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive() then
                local success = args[1]
                L("INFO", "INSTANCE_ABANDON_VOTE_FINISHED received - success=" .. tostring(success))
                
                if success then
                    -- Vote passed - key is being abandoned, save immediately
                    MPT.KeyWasAbandoned = true
                    
                    -- Build abandon run data if needed
                    if not MPT.CurrentRunData or MPT.CurrentRunData.saved then
                        self:BuildRunDataForAbandon()
                    end
                    
                    -- Mark as abandoned
                    if MPT.CurrentRunData then
                        MPT.CurrentRunData.abandonReason = "abandon"
                        MPT.CurrentRunData.completed = false
                    end
                    
                    -- Save immediately (no delay needed for abandons)
                    if MPT.CurrentRunData and not MPT.CurrentRunData.saved then
                        self:FinalizeRun("abandon")
                    end
                end
            end
        elseif event == "CHALLENGE_MODE_COMPLETED_REWARDS" then
            -- Payload: mapID, medal, timeMS, money, rewards
            local rewardMapID = args[1]
            local medal = args[2]
            local timeMS = args[3]
            L("INFO", "CHALLENGE_MODE_COMPLETED_REWARDS received mapID=" .. tostring(rewardMapID) .. " medal=" .. tostring(medal) .. " timeMS=" .. tostring(timeMS))
            -- Store for run data building (duration/level capture)
            if rewardMapID and timeMS then
                MPT.LastRewardsPayload = { mapID = rewardMapID, medal = medal, timeMS = timeMS }
            end
        elseif event == "CHALLENGE_MODE_NEW_RECORD" then
            -- Payload: mapID, timeMS, medal (Blizzard API).
            local recordMapID = args[1]
            local recordTimeMS = args[2]
            local recordMedal = args[3]
            L("INFO", "CHALLENGE_MODE_NEW_RECORD received mapID=" .. tostring(recordMapID) .. " timeMS=" .. tostring(recordTimeMS) .. " medal=" .. tostring(recordMedal))
            -- Store for run data building (duration/level capture)
            if recordMapID and recordTimeMS then
                MPT.LastRewardsPayload = { mapID = recordMapID, medal = recordMedal or 1, timeMS = recordTimeMS }
            end
        elseif event == "CHALLENGE_MODE_START" then
            local mapID = args[1]
            ClearCompletionSignal()
            ResetRunAnnouncements()
            MPT.RunSavedAt = nil
            MPT.RunJustSaved = nil  -- new key started; cleared here and only here
            MPT._pendingCombatEndSave = nil  -- clear any deferred save from previous run
            MPT.LastSavedRunFingerprint = nil

            -- Reporter election: reset and announce presence for the new key
            if MPT.ReporterElection then
                MPT.ReporterElection:Reset()
                MPT.ReporterElection:BroadcastPresence()
            end

            L("INFO", "=== CHALLENGE_MODE_START EVENT ===")
            L("INFO", "mapID=" .. tostring(mapID))
            L("INFO", "Current time: " .. tostring(time()))
            
            MPT.LastRewardsPayload = nil  -- clear so we don't reuse stale completion data
            MPT.MythicPlusRunStartTimestamp = time()
            MPT.RunBootstrapRecovered = false
            MPT.RunBootstrapReason = nil
            MPT.RunBootstrapAt = nil
            L("INFO", "Run start timestamp: " .. tostring(MPT.MythicPlusRunStartTimestamp))
            
            -- Store that we're in a mythic+ run
            MPT.InMythicPlus = true
            MPT.MythicPlusMapID = mapID
            MPT.MythicPlusDungeonName = GetDungeonNameFromMapID(mapID)
            -- Fallback: capture zone text while inside the dungeon (works even when GetMapUIInfo returns nil)
            if not MPT.MythicPlusDungeonName or MPT.MythicPlusDungeonName == "" then
                local zoneText = GetRealZoneText and GetRealZoneText()
                if zoneText and zoneText ~= "" then
                    MPT.MythicPlusDungeonName = zoneText
                    L("INFO", "Dungeon name from GetRealZoneText: " .. tostring(zoneText))
                end
            end
            L("INFO", "Set InMythicPlus=true, MythicPlusMapID=" .. tostring(mapID) .. " dungeonName=" .. tostring(MPT.MythicPlusDungeonName))
            L("INFO", "Set InMythicPlus=true, runStartTimestamp=" .. tostring(MPT.MythicPlusRunStartTimestamp))
            
            MPT.LastEnemyForces = nil
            -- ENCOUNTER_END tracking: which bosses (by encounter ID) have been killed this run
            MPT.KilledEncounterIDs = {}
            MPT.MythicPlusBossKillCount = 0
            MPT.DungeonEncounterIDs = GetEncounterIDsForMap(mapID)
            L("INFO", "Reset encounter tracking for mapID " .. tostring(mapID))
            
            self:StopEndOfDungeonHistoryPoll()
            self:StopCriteriaCompletionTracker()
            
            -- Initialize run history tracking for auto-completion detection
            L("INFO", "Initializing run history tracking and completion requirements...")
            Events:InitializeRunHistoryTracking()
            Events:InitializeRunCompletionRequirements(mapID)
            Events:StartCriteriaCompletionTracker(5)
            L("INFO", "CompletionTracker started=" .. tostring(Events.criteriaCompletionTracker ~= nil) .. " pollInterval=" .. tostring(Events.criteriaCompletionPollInterval))
            
            -- Capture keystone level at start so we don't use post-completion "active" key (e.g. +8) for a +12 run
            MPT.MythicPlusKeystoneLevel = nil
            if C_ChallengeMode and type(C_ChallengeMode.GetActiveKeystoneInfo) == "function" then
                local a, b, c, d, e, f = C_ChallengeMode.GetActiveKeystoneInfo()
                local startLevel = nil
                if type(a) == "table" then
                    startLevel = a.level or a.keystoneLevel
                else
                    startLevel = a
                end
                if startLevel and startLevel > 0 then
                    MPT.MythicPlusKeystoneLevel = startLevel
                    L("INFO", "Keystone level captured at start: +" .. tostring(MPT.MythicPlusKeystoneLevel))
                else
                    L("WARN", "Failed to get keystone level from GetActiveKeystoneInfo")
                end
            else
                L("WARN", "GetActiveKeystoneInfo not available")
            end

            -- Primary completion is criteria-based (bosses + enemy forces) via periodic tracker.
            -- Reset live dungeon tracker for new run
            if MPT.LiveTracker and MPT.LiveTracker.Reset then
                L("INFO", "Resetting live tracker for new run")
                MPT.LiveTracker:Reset()
            end

            -- Start combat tracking
            L("INFO", "Starting combat tracking...")
            if MPT.CombatLog and MPT.CombatLog.StartTracking then
                MPT.CombatLog:StartTracking()
                if MPT.CombatLog.isTracking then
                    L("INFO", "Combat tracking ACTIVE: isTracking=" .. tostring(MPT.CombatLog.isTracking))
                    AnnounceTrackingStarted("challenge_mode_start")
                else
                    L("ERROR", "Combat tracking failed to start! isTracking=" .. tostring(MPT.CombatLog.isTracking))
                    print("|cffff4444[StormsDungeonData]|r WARNING: Combat tracking failed to start!")
                end
            else
                L("ERROR", "CombatLog.StartTracking not available!")
            end
            
            -- Notify the combat log file monitor about the dungeon start
            if MPT.CombatLogFileMonitor and MPT.CombatLogFileMonitor.ProcessEvent then
                local dungeonName = C_ChallengeMode.GetMapUIInfo(mapID)
                L("INFO", "Notifying combat log file monitor: dungeon=" .. tostring(dungeonName))
                MPT.CombatLogFileMonitor:ProcessEvent({
                    event = "CHALLENGE_MODE_START",
                    dungeonName = dungeonName or "Unknown",
                    mapID = mapID,
                    keystoneLevel = 0,  -- Level not available in this event
                })
            end
            
            L("INFO", "Evaluating run completion criteria for initial state")
            Events:EvaluateRunCompletionCriteria("run_start")
            L("INFO", "=== CHALLENGE_MODE_START processing complete ===")
        elseif event == "CHALLENGE_MODE_END" then
            -- Payload (retail): mapID, completedFlag, level, timeMS, ...
            local endMapID = tonumber(args[1]) or tonumber(MPT.MythicPlusMapID) or 0
            local completedFlag = args[2]
            local endLevel = tonumber(args[3]) or tonumber(MPT.MythicPlusKeystoneLevel) or 0
            local endTimeMS = tonumber(args[4]) or 0
            local completed = (completedFlag == true) or (tonumber(completedFlag) == 1)

            L("INFO", "CHALLENGE_MODE_END mapID=" .. tostring(endMapID) .. " completed=" .. tostring(completed) .. " level=" .. tostring(endLevel) .. " timeMS=" .. tostring(endTimeMS))

            -- Keep combat/file monitor state in sync with this explicit end signal.
            if MPT.CombatLogFileMonitor and MPT.CombatLogFileMonitor.ProcessEvent then
                MPT.CombatLogFileMonitor:ProcessEvent({ event = "CHALLENGE_MODE_END", mapID = endMapID })
            end

            if completed then
                -- Store for run data building (duration/level capture)
                if endMapID > 0 and endTimeMS > 0 then
                    MPT.LastRewardsPayload = { mapID = endMapID, medal = 1, timeMS = endTimeMS }
                end
            else
                -- Failed/abandoned key path.
                if (not MPT.CurrentRunData or MPT.CurrentRunData.saved) and self.BuildRunDataForAbandon then
                    self:BuildRunDataForAbandon()
                end
            end

            -- Run is over either way; stop collecting new live data points.
            if MPT.LiveTracker and MPT.LiveTracker.StopCollection then
                MPT.LiveTracker:StopCollection()
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
        elseif event == "ENCOUNTER_END" then
            -- Payload: encounterID, encounterName, difficultyID, groupSize, success (1=kill, 0=wipe)
            -- difficultyID 8 = Mythic Keystone; groupSize 5 = dungeon. Use with scenario mob % (MPlusTimer-style) to trigger autosave.
            local encounterID, encounterName, difficultyID, groupSize, success = args[1], args[2], args[3], args[4], args[5]
            local successKill = (tonumber(success) == 1)
            local _, instanceType, instanceDifficultyID = GetInstanceInfo()
            local looksLikeMythicKeyContext = (tonumber(difficultyID) == 8) or (instanceType == "party" and tonumber(instanceDifficultyID) == 8)
            local isMythicKeystoneDungeonKill = successKill and (MPT.InMythicPlus or looksLikeMythicKeyContext)
            L("INFO", "ENCOUNTER_END: " .. tostring(encounterName) .. " (ID=" .. tostring(encounterID) .. ") difficultyID=" .. tostring(difficultyID) .. " groupSize=" .. tostring(groupSize) .. " success=" .. tostring(success) .. " isMythicKeystoneDungeonKill=" .. tostring(isMythicKeystoneDungeonKill) .. " InMythicPlus=" .. tostring(MPT.InMythicPlus))

            if isMythicKeystoneDungeonKill and not MPT.InMythicPlus then
                self:TryBootstrapMythicPlusRun("encounter_end", true)
            end
            
            if MPT.InMythicPlus and successKill and MPT.LiveTracker and MPT.LiveTracker.RecordBossKill then
                MPT.LiveTracker:RecordBossKill()
            end
            -- Record this boss kill for ENCOUNTER_END verification
            if isMythicKeystoneDungeonKill and encounterID and encounterID ~= 0 then
                MPT.KilledEncounterIDs = MPT.KilledEncounterIDs or {}
                MPT.KilledEncounterIDs[encounterID] = true
                -- Raw kill counter: counts each successful M+ ENCOUNTER_END boss kill regardless of
                -- whether the encounter ID matches the Encounter Journal list. This is the fallback
                -- used when GetEncounterIDsForMap returns IDs that differ from what ENCOUNTER_END
                -- sends (a known mismatch for some last bosses in certain dungeons).
                MPT.MythicPlusBossKillCount = (MPT.MythicPlusBossKillCount or 0) + 1
                L("INFO", "ENCOUNTER_END: MythicPlusBossKillCount now " .. tostring(MPT.MythicPlusBossKillCount))

                local knownEncounters = MPT.DungeonEncounterIDs
                local bossCount = (type(knownEncounters) == "table" and #knownEncounters) or 0
                local bossesKilled = 0
                if bossCount > 0 then
                    for _, eid in ipairs(knownEncounters) do
                        if MPT.KilledEncounterIDs[eid] then
                            bossesKilled = bossesKilled + 1
                        end
                    end
                end
                AnnounceBossKill(encounterID, encounterName, bossesKilled, bossCount)
                L("INFO", "Recorded boss kill (rawTotal=" .. tostring(MPT.MythicPlusBossKillCount) .. ") EJ match " .. tostring(bossesKilled) .. "/" .. tostring(bossCount))
            end
            -- Primary autosave is criteria-based (bosses + enemy forces) and evaluated continuously.
            if not isMythicKeystoneDungeonKill or MPT.CurrentRunData and MPT.CurrentRunData.saved then
                -- skip
            else
                self:EvaluateRunCompletionCriteria("encounter_end")
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            -- Enter combat: record session start elapsed for DPS/HPS session tracking
            if MPT.LiveTracker and MPT.LiveTracker.OnEnterCombat then
                MPT.LiveTracker:OnEnterCombat()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Exit combat: record point-in-time snapshot for live dungeon tracker
            if MPT.LiveTracker and MPT.LiveTracker.OnExitCombat then
                MPT.LiveTracker:OnExitCombat()
            end

            -- If a run finalization was deferred due to being in combat, execute it now.
            if MPT._pendingCombatEndSave then
                local pendingReason = MPT._pendingCombatEndSave
                MPT._pendingCombatEndSave = nil
                L("INFO", "PLAYER_REGEN_ENABLED: executing deferred FinalizeRun (reason=" .. tostring(pendingReason) .. ")")
                print("|cff00ffaa[StormsDungeonData]|r Combat ended - saving run now...")
                self:FinalizeRun(pendingReason)
            end

        elseif event == "UNIT_PET" then
            -- A party member's (or player's) pet changed. Refresh pet→owner mappings so
            -- interrupts from pets summoned/respawned are attributed correctly.
            -- Track during any active M+ run, not just while isTracking=true, so late
            -- summons (e.g. after the final boss kill) are never missed.
            if MPT.CombatLog and MPT.InMythicPlus then
                MPT.CombatLog:OnUnitPetChanged(args[1])
            end

        elseif event == "INSPECT_READY" then
            -- args[1] is the GUID of the inspected unit. Cache their spec ID.
            local guid = args[1]
            if guid then
                -- Find which unit slot this GUID belongs to and read their spec
                for i = 1, 4 do
                    local uid = "party" .. i
                    if UnitExists(uid) and UnitGUID(uid) == guid then
                        CacheSpecFromUnit(uid)
                        break
                    end
                end
            end
            -- Update any already-captured player records for the active run
            BackfillCurrentRunSpecIDs()

        elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
            -- args[1] is the unit whose spec changed; re-cache immediately
            local uid = args[1]
            if uid then
                CacheSpecFromUnit(uid)
                BackfillCurrentRunSpecIDs()
            end

        elseif event == "WORLD_STATE_TIMER_START" then
            -- WoW 12.0+: reliable signal that a timed objective (including M+ timer) just started.
            -- Use this as a start fallback when CHALLENGE_MODE_START does not arrive.
            self:TryBootstrapMythicPlusRun("world_state_timer_start", true)
            if MPT.InMythicPlus then
                self:EnsureCriteriaTrackingForActiveRun("world_state_timer_start")
            end
        elseif event == "SCENARIO_CRITERIA_UPDATE" or event == "SCENARIO_POI_UPDATE" or event == "SCENARIO_UPDATE" then
            if not MPT.InMythicPlus then
                self:TryBootstrapMythicPlusRun("scenario_progress", true)
            end
            if not MPT.InMythicPlus then return end
            if C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function" and not C_ChallengeMode.IsChallengeModeActive() then
                local apiStart = C_ChallengeMode.GetStartTime and C_ChallengeMode.GetStartTime() or 0
                if not apiStart or apiStart <= 0 then
                    -- Challenge mode is no longer active with no recorded start time.
                    -- Only proceed if numCriteria has dropped to 0 (dungeon scenario torn down).
                    local nc = 0
                    if C_Scenario and type(C_Scenario.GetStepInfo) == "function" then
                        local _, _, n = C_Scenario.GetStepInfo()
                        nc = tonumber(n) or 0
                    end
                    if nc == 0 then
                        L("INFO", "SCENARIO_CRITERIA_UPDATE: numCriteria=0, challenge inactive - dungeon ended, evaluating completion")
                        print("|cff00ffaa[StormsDungeonData]|r Scenario ended (numCriteria=0) - inferring dungeon completion")
                    else
                        return
                    end
                end
            end
            if MPT.CurrentRunData and MPT.CurrentRunData.saved then return end
            self:EvaluateRunCompletionCriteria("scenario_progress")
        elseif event == "SCENARIO_COMPLETED" then
            local _, instanceType, difficultyID = GetInstanceInfo()
            if instanceType ~= "party" or difficultyID ~= 8 then return end
            if not MPT.InMythicPlus then
                self:TryBootstrapMythicPlusRun("scenario_completed", true)
            end
            if not MPT.InMythicPlus then return end
            if MPT.CurrentRunData and MPT.CurrentRunData.saved then return end
            L("INFO", "SCENARIO_COMPLETED received - evaluating criteria")
            self:EvaluateRunCompletionCriteria("scenario_completed")
        elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- Fallback bootstrap: if CHALLENGE_MODE_START was missed but we're in an active key,
            -- start/restore tracking as soon as combat events appear.
            if not MPT.InMythicPlus then
                self:TryBootstrapMythicPlusRun("cleu_bootstrap", false)
                self:EnsureCriteriaTrackingForActiveRun("cleu_bootstrap")
            end

            -- CLEU feeds combat statistics; completion save is criteria-driven and handled separately.
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
        L("ERROR", "OnEvent(" .. tostring(event) .. ") pcall failed: " .. tostring(err))
        print("|cff00ffaa[StormsDungeonData]|r ERROR in OnEvent(" .. tostring(event) .. "): " .. tostring(err))
    end
end

function Events:OnPlayerEnteringWorld()
    local _, instanceType, difficultyID = GetInstanceInfo()
    L("INFO", "PLAYER_ENTERING_WORLD instanceType=" .. tostring(instanceType) .. " InMythicPlus=" .. tostring(MPT.InMythicPlus))

    -- Bootstrap: if we load/reload inside an active M+ key, start live tracking immediately
    -- even when the tracker window has never been opened.
    if difficultyID == 8 and not MPT.InMythicPlus then
        MPT.InMythicPlus = true
        ResetRunAnnouncements()
        if not MPT.MythicPlusRunStartTimestamp then
            MPT.MythicPlusRunStartTimestamp = time()
        end
        if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
            local activeMapID = C_ChallengeMode.GetActiveChallengeMapID()
            if activeMapID and activeMapID > 0 then
                MPT.MythicPlusMapID = activeMapID
            end
        end
        self:InitializeRunHistoryTracking()
        self:EnsureCriteriaTrackingForActiveRun("enter_world_bootstrap")
        if MPT.LiveTracker and MPT.LiveTracker.Reset and (not MPT.LiveTracker.startTime) then
            MPT.LiveTracker:Reset()
        end
    end
    
    if instanceType == "party" then
        -- We're in a group dungeon
        L("INFO", "Starting combat tracking (dungeon instance detected)")
        MPT.CombatLog:StartTracking()
        if difficultyID == 8 then
            MPT.InMythicPlus = true
            self:EnsureCriteriaTrackingForActiveRun("enter_world_party")
            -- Always (re)start the 5s watcher so it's guaranteed running inside the dungeon.
            -- Force-stop first so the startup print always fires even if already running at 5s.
            self:StopRunStateWatcher()
            self:StartRunStateWatcher(5)
        end
        if MPT.CombatLog.isTracking then
            if difficultyID == 8 then
                AnnounceTrackingStarted("enter_world")
            end
        else
            L("ERROR", "Combat tracking failed to start on PLAYER_ENTERING_WORLD! isTracking=" .. tostring(MPT.CombatLog.isTracking))
        end
    else
        L("INFO","|cff00ffaa[StormsDungeonData]|r Not in dungeon instance, checking for pending runs...")
        MPT.SavedRunThisExit = nil
        self:StopCriteriaCompletionTracker()
        self:StopEndOfDungeonHistoryPoll()
        ResetRunAnnouncements()
        MPT.RunCompletionRequirements = nil
        MPT.RunCompletionProgress = nil

        -- Stop Live Dungeon Tracker immediately when we're not in a dungeon (don't rely only on InMythicPlus)
        if MPT.LiveTracker and MPT.LiveTracker.StopCollection then
            MPT.LiveTracker:StopCollection()
        elseif MPT.LiveTracker and MPT.LiveTracker.StopPeriodicSnapshot then
            MPT.LiveTracker:StopPeriodicSnapshot()
        end

        -- Only auto-save on exit if the key was explicitly abandoned via surrender vote.
        -- Completed runs are saved by the boss/forces criteria tracker (EvaluateRunCompletionCriteria).
        if MPT.KeyWasAbandoned and MPT.InMythicPlus and (not MPT.CurrentRunData or not MPT.CurrentRunData.saved) then
            if self:BuildRunDataForAbandon() then
                L("INFO", "Exit: abandoned key - FinalizeRun(abandon)")
                self:FinalizeRun("abandon")
                MPT.SavedRunThisExit = true
            end
        end
        MPT.KeyWasAbandoned = nil
        if MPT.CurrentRunData and not MPT.CurrentRunData.saved then
            L("INFO", "CurrentRunData exists: completed=" .. tostring(MPT.CurrentRunData.completed) .. ", saved=" .. tostring(MPT.CurrentRunData.saved))
        end
        
        if MPT.InMythicPlus then
            MPT.InMythicPlus = false
            MPT.MythicPlusKeystoneLevel = nil
            MPT.MythicPlusRunStartTimestamp = nil
            ClearCompletionSignal()
            MPT.RunBootstrapRecovered = nil
            MPT.RunBootstrapReason = nil
            MPT.RunBootstrapAt = nil
        end
        
        MPT.CombatLog:StopTracking()

        -- Ensure the M+ watcher (CombatLogFileMonitor) is running and has a fresh
        -- state so it reliably detects the next key after an abandon or dungeon exit.
        if MPT.CombatLogFileMonitor then
            MPT.CombatLogFileMonitor:StopMonitoring()
            MPT.CombatLogFileMonitor.lastActiveMapID   = nil
            MPT.CombatLogFileMonitor.currentDungeon    = nil
            MPT.CombatLogFileMonitor.hearthstoneCastID = nil
            MPT.CombatLogFileMonitor:StartMonitoring()
            L("INFO", "CombatLogFileMonitor re-initialized after dungeon exit")
        end
    end
end

-- Schedule several delayed attempts to auto-save the completed run (MPlusTimer syncs history 5s after CHALLENGE_MODE_COMPLETED; we retry earlier and more often).
-- OnChallengeModeCompleted can populate CurrentRunData late (e.g. after API retries), so we retry building and use multiple delays.
-- Last delay triggers manual save (same as /sdd save) so FinalizeRun runs again with whatever data we have.
function Events:ScheduleEndOfRunAutoSave(reason)
    -- No-op: end-of-run save is now triggered exclusively by boss/forces criteria (EvaluateRunCompletionCriteria).
end

function Events:OnChallengeModeCompleted()
    L("INFO", "OnChallengeModeCompleted called")
    L("INFO","|cff00ffaa[StormsDungeonData]|r OnChallengeModeCompleted called")
    
    if C_ChallengeMode and C_ChallengeMode.GetChallengeCompletionInfo then
        local completionInfo = C_ChallengeMode.GetChallengeCompletionInfo()
        if completionInfo and completionInfo.mapChallengeModeID and completionInfo.mapChallengeModeID > 0 then
            L("INFO","|cff00ffaa[StormsDungeonData]|r GetChallengeCompletionInfo returned valid data:")
            print("|cff00ffaa[StormsDungeonData]|r   mapID=" .. tostring(completionInfo.mapChallengeModeID) .. ", level=" .. tostring(completionInfo.level) .. ", time=" .. tostring(completionInfo.time) .. "ms")
            print("|cff00ffaa[StormsDungeonData]|r   onTime=" .. tostring(completionInfo.onTime) .. ", upgrades=" .. tostring(completionInfo.keystoneUpgradeLevels))
        else
            L("INFO","|cffff4444[StormsDungeonData]|r GetChallengeCompletionInfo returned nil or invalid data")
        end
    end
    
    -- Check if challenge mode is active
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local isActive = C_ChallengeMode.IsChallengeModeActive()
        print("|cff00ffaa[StormsDungeonData]|r IsChallengeModeActive: " .. tostring(isActive))
    end
    
    -- Wrap in pcall for safety
    local success, err = pcall(function()
        if MPT.CurrentRunData and not MPT.CurrentRunData.saved then
            L("INFO", "OnChallengeModeCompleted: run already cached, skipping rebuild")
            L("INFO","|cff00ffaa[StormsDungeonData]|r Run already cached, skipping rebuild")
            return
        end

        local completion = GetCompletionInfoCompat()
    if not completion then
        L("WARN", "OnChallengeModeCompleted: GetCompletionInfoCompat returned nil - completion API not populated or restricted")
        L("WARN","|cffff4444[StormsDungeonData]|r GetChallengeCompletionInfo returned nil or empty - completion API not populated or restricted (WoW 12+ ChallengeMode restriction can cause this)")
        if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsRestricted and Enum and Enum.AddOnRestrictionType then
            local restricted = MPT.DamageMeterCompat:IsRestricted(Enum.AddOnRestrictionType.ChallengeMode)
            if restricted then
                L("WARN","|cffff4444[StormsDungeonData]|r ChallengeMode addon restriction is ACTIVE - completion API may be blocked")
            end
        end
    end
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

    -- Prefer completion API level; then level captured at CHALLENGE_MODE_START (avoids using post-run "active" key, e.g. +8 after a +12)
    local startLevel = (MPT.MythicPlusKeystoneLevel and (not mapID or MPT.MythicPlusMapID == mapID)) and MPT.MythicPlusKeystoneLevel or nil
    level = completionLevel or startLevel or level
    keystoneUpgrades = completionKeystoneUpgrades or keystoneUpgrades
    -- MPlusTimer: completion time is in milliseconds -> divide by 1000 for seconds
    local durationSeconds = CompletionTimeToSeconds(completionTime) or NormalizeDurationSeconds(completionTime)
    
    -- Capture additional completion data
    local onTime = completion and completion.onTime
    local practiceRun = completion and completion.practiceRun
    local isAffixRecord = completion and completion.isAffixRecord
    local isMapRecord = completion and completion.isMapRecord
    local isEligibleForScore = completion and completion.isEligibleForScore
    local oldDungeonScore = completion and completion.oldOverallDungeonScore
    local newDungeonScore = completion and completion.newOverallDungeonScore
    
    -- Completed = within time limit. Use API onTime when present; else compare duration to dungeon time limit.
    local runCompleted = true
    if onTime == false then
        runCompleted = false
        L("INFO","|cff00ffaa[StormsDungeonData]|r Run over time limit (onTime=false) - marking as Failed")
    elseif onTime ~= true and durationSeconds and durationSeconds > 0 and mapID then
        local timeLimit = GetDungeonTimeLimitSeconds(mapID)
        if timeLimit and durationSeconds > timeLimit then
            runCompleted = false
            L("INFO","|cff00ffaa[StormsDungeonData]|r Run over time limit (" .. tostring(durationSeconds) .. "s > " .. tostring(timeLimit) .. "s) - marking as Failed")
        end
    end

    print("|cff00ffaa[StormsDungeonData]|r Completion info: mapID=" .. tostring(mapID) .. ", level=" .. tostring(level) .. ", time=" .. tostring(durationSeconds) .. "s, onTime=" .. tostring(onTime) .. ", result=" .. (runCompleted and "Completed" or "Failed"))

    if mapID and level then
        self.challengeRetryCount = 0
        
        -- Always use mapID for dungeon name to avoid getting current zone after teleporting out
        name = name or GetDungeonNameFromMapID(mapID)
        if not name then
            L("INFO","|cffff4444[StormsDungeonData]|r WARNING: Could not get dungeon name from mapID " .. tostring(mapID))
            name = "Unknown Dungeon (ID: " .. tostring(mapID) .. ")"
        end
        L("INFO","|cff00ffaa[StormsDungeonData]|r Dungeon name resolved: " .. tostring(name) .. " (mapID: " .. tostring(mapID) .. ")")

        -- Collect player statistics
        local completionMembers = BuildGroupMembersFromCompletionMembers(completion and completion.members)
        local playerStats = MergePreferredPlayerList(completionMembers, CollectGroupPlayerStats(), 5)

        local startTime = (MPT.CurrentRunData and MPT.CurrentRunData.startTime)
            or (MPT.CombatLog and MPT.CombatLog.startTime)
            or time()
        if durationSeconds and durationSeconds > 0 then
            startTime = time() - durationSeconds
        end
        
        -- Get death count and time lost from API
        local deathCount, timeLost = 0, 0
        if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
            local deaths, lostTime = C_ChallengeMode.GetDeathCount()
            if deaths then
                deathCount = deaths
                timeLost = lostTime or 0
                L("INFO","|cff00ffaa[StormsDungeonData]|r Deaths: " .. deathCount .. ", Time Lost: " .. timeLost .. "s")
            end
        end
        
        -- Get actual start time from API if available
        if C_ChallengeMode and C_ChallengeMode.GetStartTime then
            local apiStartTime = C_ChallengeMode.GetStartTime()
            if apiStartTime and apiStartTime > 0 then
                startTime = apiStartTime
                L("INFO","|cff00ffaa[StormsDungeonData]|r Using API start time: " .. tostring(startTime))
            end
        end
        
        -- Capture enemy forces and boss kill times (MPlusTimer-style from scenario criteria)
        local scenarioState = GetScenarioCompletionState()
        local earlyForces = GetEnemyForcesProgress()
        local capturedMobData = false
        if scenarioState and scenarioState.forcesAt100 and scenarioState.forcesTotal and scenarioState.forcesTotal > 0 then
            capturedMobData = true
            earlyForces = earlyForces or {}
            earlyForces.current = scenarioState.forcesCurrent
            earlyForces.total = scenarioState.forcesTotal
            earlyForces.percent = scenarioState.forcesPercent >= 100 and 100 or scenarioState.forcesPercent
            L("INFO","|cff00ffaa[StormsDungeonData]|r Captured mob data from scenario: " .. string.format("%.1f%%", earlyForces.percent) .. " (" .. tostring(earlyForces.current) .. "/" .. tostring(earlyForces.total) .. ")")
        elseif earlyForces and earlyForces.percent and earlyForces.percent > 0 then
            capturedMobData = true
            L("INFO","|cff00ffaa[StormsDungeonData]|r Captured mob data at completion: " .. string.format("%.1f%%", earlyForces.percent) .. " (" .. tostring(earlyForces.current) .. "/" .. tostring(earlyForces.total) .. ")")
        end
        local bossKillTimes = (scenarioState and scenarioState.bossKillTimes and #scenarioState.bossKillTimes > 0) and scenarioState.bossKillTimes or nil

        -- Store run info for later (completed = within time limit; over time = Failed)
        MPT.CurrentRunData = {
            dungeonID = mapID,
            dungeonName = name,
            keystoneLevel = level,
            affixes = affixes,
            keystoneUpgrades = keystoneUpgrades,
            completed = runCompleted,
            players = playerStats,
            groupMembers = ClonePlayerList(playerStats),
            startTime = startTime,
            completionTime = time(),
            completionDuration = durationSeconds,
            saved = false,
            
            -- Death tracking
            deathCount = deathCount,
            timeLost = timeLost,
            
            -- Pre-capture mob data if available (prevents loss if player leaves dungeon)
            mobsKilled = capturedMobData and (earlyForces.current or 0) or nil,
            mobsTotal = capturedMobData and (earlyForces.total or 0) or nil,
            overallMobPercentage = capturedMobData and earlyForces.percent or nil,
            
            -- Boss kill timings (MPlusTimer-style, seconds into run per objective)
            bossKillTimes = bossKillTimes,
            
            -- Additional completion data
            onTime = onTime,
            practiceRun = practiceRun,
            isAffixRecord = isAffixRecord,
            isMapRecord = isMapRecord,
            isEligibleForScore = isEligibleForScore,
            oldDungeonScore = oldDungeonScore,
            newDungeonScore = newDungeonScore,
        }
        
        L("INFO", "OnChallengeModeCompleted: built CurrentRunData (mapID=" .. tostring(mapID) .. " level=" .. tostring(level) .. " duration=" .. tostring(durationSeconds) .. "s)")
        print("|cff00ffaa[StormsDungeonData]|r Challenge mode completed!")
        print("|cff00ffaa[StormsDungeonData]|r Run data cached. Save is triggered by criteria completion (bosses + enemy forces), with history poll as backup.")
        print("|cff00ffaa[StormsDungeonData]|r Duration: " .. tostring(durationSeconds) .. " seconds")
        print("|cff00ffaa[StormsDungeonData]|r Key upgraded: " .. tostring(keystoneUpgrades) .. " levels, onTime: " .. tostring(onTime))
    else
        -- Some clients return completion info slightly later. Retry a few times.
        L("INFO","|cff00ffaa[StormsDungeonData]|r Warning: could not read completion info (mapID=" .. tostring(mapID) .. ", level=" .. tostring(level) .. ")")
        if C_Timer and C_Timer.After then
            self.challengeRetryCount = (self.challengeRetryCount or 0) + 1
            if self.challengeRetryCount <= 5 then
                local delay = 1.5 * self.challengeRetryCount
                L("INFO","|cff00ffaa[StormsDungeonData]|r Retrying in " .. delay .. " seconds (attempt " .. self.challengeRetryCount .. "/5)")
                C_Timer.After(delay, function()
                    Events:OnChallengeModeCompleted()
                end)
                return
            else
                L("INFO","|cff00ffaa[StormsDungeonData]|r Failed to get completion info after 5 retries")
            end
        end
    end
    end) -- end of pcall
    
    if not success then
        L("INFO","|cff00ffaa[StormsDungeonData]|r ERROR in OnChallengeModeCompleted: " .. tostring(err))
    end
end

function Events:FinalizeRun(reason)
    -- Guard: once a run is saved, block all further calls until CHALLENGE_MODE_START fires.
    if MPT.RunJustSaved then
        L("INFO", "FinalizeRun: RunJustSaved=true, blocking duplicate finalize (reason=" .. tostring(reason) .. ")")
        return false
    end

    -- If the player is still in combat, defer the save until PLAYER_REGEN_ENABLED.
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        L("INFO", "FinalizeRun: player is in combat, deferring save (reason=" .. tostring(reason) .. ")")
        print("|cffffff00[StormsDungeonData]|r Run complete! Waiting for combat to end before saving...")
        MPT._pendingCombatEndSave = reason
        return false
    end

    L("INFO", "FinalizeRun(" .. tostring(reason) .. ")")
    RecordFlow("FINALIZE_START", tostring(reason))
    L("INFO","|cff00ffaa[StormsDungeonData]|r FinalizeRun called (reason: " .. tostring(reason) .. ")")
    
    if not MPT.CurrentRunData then
        L("INFO", "FinalizeRun: no CurrentRunData - calling BuildRunDataFromActiveKeystone")
        L("INFO","|cff00ffaa[StormsDungeonData]|r No current run data, attempting to build from keystone")
        if not self:BuildRunDataFromActiveKeystone() then
            L("WARN", "FinalizeRun: BuildRunDataFromActiveKeystone returned false - no run to save")
            RecordFlow("FINALIZE_ABORT", "no CurrentRunData")
            print("|cff00ffaa[StormsDungeonData]|r No pending run data to save")
            return false
        end
        L("INFO", "FinalizeRun: BuildRunDataFromActiveKeystone succeeded")
    end
    
    if not MPT.CurrentRunData.dungeonID or MPT.CurrentRunData.dungeonID == 0 then
        MPT.CurrentRunData._saveRetryCount = (MPT.CurrentRunData._saveRetryCount or 0) + 1
        L("WARN", "FinalizeRun: invalid dungeonID=" .. tostring(MPT.CurrentRunData.dungeonID) .. " (attempt " .. MPT.CurrentRunData._saveRetryCount .. "/3)")
        if MPT.CurrentRunData._saveRetryCount > 3 then
            L("ERROR", "FinalizeRun: invalid dungeonID after 3 retries - aborting")
            RecordFlow("FINALIZE_ABORT", "invalid dungeonID after 3 retries")
            print("|cffff4444[StormsDungeonData]|r ERROR: Run could not be saved after 3 attempts (invalid dungeon data).")
            print("|cffff4444[StormsDungeonData]|r Please |cffffd700/reload|r your UI to fix this issue.")
            return false
        end
        RecordFlow("FINALIZE_RETRY", "invalid dungeonID attempt " .. MPT.CurrentRunData._saveRetryCount)
        print("|cffffff00[StormsDungeonData]|r Run data not ready, retrying in 2 seconds... (attempt " .. MPT.CurrentRunData._saveRetryCount .. "/3)")
        local retryReason = reason
        C_Timer.After(2, function() Events:FinalizeRun(retryReason) end)
        return false
    end

    if not MPT.CurrentRunData.keystoneLevel or MPT.CurrentRunData.keystoneLevel == 0 then
        MPT.CurrentRunData._saveRetryCount = (MPT.CurrentRunData._saveRetryCount or 0) + 1
        L("WARN", "FinalizeRun: invalid keystoneLevel=" .. tostring(MPT.CurrentRunData.keystoneLevel) .. " (attempt " .. MPT.CurrentRunData._saveRetryCount .. "/3)")
        if MPT.CurrentRunData._saveRetryCount > 3 then
            L("ERROR", "FinalizeRun: invalid keystoneLevel after 3 retries - aborting")
            RecordFlow("FINALIZE_ABORT", "invalid keystoneLevel after 3 retries")
            print("|cffff4444[StormsDungeonData]|r ERROR: Run could not be saved after 3 attempts (invalid keystone data).")
            print("|cffff4444[StormsDungeonData]|r Please |cffffd700/reload|r your UI to fix this issue.")
            return false
        end
        RecordFlow("FINALIZE_RETRY", "invalid keystoneLevel attempt " .. MPT.CurrentRunData._saveRetryCount)
        print("|cffffff00[StormsDungeonData]|r Run data not ready, retrying in 2 seconds... (attempt " .. MPT.CurrentRunData._saveRetryCount .. "/3)")
        local retryReason = reason
        C_Timer.After(2, function() Events:FinalizeRun(retryReason) end)
        return false
    end

    if MPT.CurrentRunData.saved then
        L("INFO", "FinalizeRun: run already saved - skipping")
        RecordFlow("FINALIZE_SKIP", "already saved")
        print("|cff00ffaa[StormsDungeonData]|r Run already saved, skipping")
        return false
    end

    local isAbandon = (reason == "abandon") or (MPT.CurrentRunData.abandonReason == "abandon")
    if isAbandon then
        MPT.CurrentRunData.completed = false
        MPT.CurrentRunData.onTime = false
        MPT.CurrentRunData.abandonReason = "abandon"
        -- No completion time or duration for abandoned keys - logged as "ABANDON" status only
        MPT.CurrentRunData.completionTime = nil
        MPT.CurrentRunData.completionDuration = nil
        L("INFO", "FinalizeRun: Key marked as ABANDONED (no completion time)")
    end

    if not MPT.CurrentRunData.completed and not isAbandon then
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
    elseif not MPT.CurrentRunData.completionTime then
        MPT.CurrentRunData.completionTime = time()
    end
    if not isAbandon and (not MPT.CurrentRunData.completionDuration or MPT.CurrentRunData.completionDuration <= 0) and MPT.CurrentRunData.startTime then
        MPT.CurrentRunData.completionDuration = time() - MPT.CurrentRunData.startTime
    end

    -- Finalize combat totals before saving/showing.
    if MPT.CombatLog and MPT.CombatLog.useNewAPI then
        MPT.CombatLog:FinalizeNewAPIData()
    end

    -- Prefer the API-provided duration over calculated duration for accuracy
    local duration
    if isAbandon then
        duration = nil  -- Abandoned runs store no time
    else
        duration = MPT.CurrentRunData.completionDuration
        if not duration or duration <= 0 then
            duration = time() - (MPT.CurrentRunData.startTime or time())
            L("WARNING","|cff00ffaa[StormsDungeonData]|r No valid completionDuration, calculated from timestamps: " .. tostring(duration) .. "s")
        else
            L("INFO","|cff00ffaa[StormsDungeonData]|r Using duration: " .. tostring(duration) .. "s (from completionDuration)")
        end
    end
    MPT.CurrentRunData.duration = duration

    -- Get mob percentage - try multiple sources in order of reliability
    -- Priority: 1) Pre-captured at completion, 2) CombatLog, 3) Scenario API, 4) Assume 100%
    local mobDataSource = "none"
    
    -- Method 0: Use pre-captured data from OnChallengeModeCompleted if available
    if MPT.CurrentRunData.overallMobPercentage and MPT.CurrentRunData.overallMobPercentage > 0 then
        mobDataSource = "pre-captured at completion"
        L("INFO","|cff00ffaa[StormsDungeonData]|r Using pre-captured mob %: " .. string.format("%.1f%%", MPT.CurrentRunData.overallMobPercentage))
    -- Method 1: CombatLog tracking (if we have valid data)
    elseif MPT.CombatLog and MPT.CombatLog.mobsKilled and MPT.CombatLog.mobsTotal and MPT.CombatLog.mobsTotal > 0 then
        MPT.CurrentRunData.mobsKilled = MPT.CombatLog.mobsKilled
        MPT.CurrentRunData.mobsTotal = MPT.CombatLog.mobsTotal
        MPT.CurrentRunData.overallMobPercentage = (MPT.CombatLog.mobsKilled / MPT.CombatLog.mobsTotal) * 100
        mobDataSource = "CombatLog"
        L("INFO","|cff00ffaa[StormsDungeonData]|r Mob % from CombatLog: " .. string.format("%.1f%%", MPT.CurrentRunData.overallMobPercentage) .. " (" .. MPT.CombatLog.mobsKilled .. "/" .. MPT.CombatLog.mobsTotal .. ")")
    else
        L("INFO","|cff00ffaa[StormsDungeonData]|r CombatLog mob data not available (mobsKilled=" .. tostring(MPT.CombatLog and MPT.CombatLog.mobsKilled) .. ", mobsTotal=" .. tostring(MPT.CombatLog and MPT.CombatLog.mobsTotal) .. ")")
        
        -- Method 2: Scenario API (real-time data from game)
        L("INFO","|cff00ffaa[StormsDungeonData]|r Trying Scenario API for mob data...")
        local forces = GetEnemyForcesProgress()
        if forces and forces.percent and forces.percent > 0 then
            MPT.CurrentRunData.mobsKilled = forces.current or 0
            MPT.CurrentRunData.mobsTotal = forces.total or 0
            MPT.CurrentRunData.overallMobPercentage = forces.percent
            mobDataSource = "Scenario API (percent)"
            L("INFO","|cff00ffaa[StormsDungeonData]|r Mob % from Scenario API (percent): " .. string.format("%.1f%%", forces.percent))
        elseif forces and forces.current and forces.total and forces.total > 0 then
            MPT.CurrentRunData.mobsKilled = forces.current
            MPT.CurrentRunData.mobsTotal = forces.total
            MPT.CurrentRunData.overallMobPercentage = (forces.current / forces.total) * 100
            mobDataSource = "Scenario API (calculated)"
            L("INFO","|cff00ffaa[StormsDungeonData]|r Mob % from Scenario API (calculated): " .. string.format("%.1f%%", MPT.CurrentRunData.overallMobPercentage) .. " (" .. forces.current .. "/" .. forces.total .. ")")
        else
            L("INFO","|cff00ffaa[StormsDungeonData]|r Scenario API returned no valid data")
            
            -- Method 3: Assume 100% if run was completed successfully
            if MPT.CurrentRunData.completed and MPT.CurrentRunData.onTime ~= false then
                -- If the run was completed (especially if onTime), assume 100% mob count
                MPT.CurrentRunData.overallMobPercentage = 100
                mobDataSource = "assumed (completed run)"
                L("INFO","|cff00ffaa[StormsDungeonData]|r WARNING: No mob data available, assuming 100% for completed run")
            else
                L("INFO","|cff00ffaa[StormsDungeonData]|r WARNING: Could not get mob percentage from any source")
                MPT.CurrentRunData.overallMobPercentage = 0
                mobDataSource = "failed"
            end
        end
    end
    
    L("INFO","|cff00ffaa[StormsDungeonData]|r Final mob data source: " .. mobDataSource)

    -- Copy tracked stats into player records (prefer in-game damage meter data on WoW 12.0+)
    local sumBase = 0
    local detailsStats = nil
    local combatDataSource = "none"
    
    if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus then
        local damageData = MPT.DamageMeterCompat:GetDamageData()
        local healingData = MPT.DamageMeterCompat:GetHealingData()
        local interruptData = MPT.DamageMeterCompat:GetInterruptData()
        local dispelData = MPT.DamageMeterCompat.GetDispelData and MPT.DamageMeterCompat:GetDispelData() or nil
        local combined = {}

        local function EnsureEntry(name)
            local key = NormalizeUnitName(name) or name
            if not key then
                return nil, nil
            end
            if not combined[key] then
                combined[key] = { damage = 0, healing = 0, interrupts = 0, dispels = 0, dps = 0, hps = 0, name = name }
            end
            return combined[key], key
        end

        if damageData then
            for name, data in pairs(damageData) do
                local entry = EnsureEntry(name)
                if entry then
                    entry.damage = tonumber(data.damage) or 0
                    entry.dps = tonumber(data.dps) or 0
                    entry.class = data.class or entry.class
                end
            end
        end

        if healingData then
            for name, data in pairs(healingData) do
                local entry = EnsureEntry(name)
                if entry then
                    entry.healing = tonumber(data.healing) or 0
                    entry.hps = tonumber(data.hps) or 0
                    entry.class = data.class or entry.class
                end
            end
        end

        -- Refresh pet→owner mappings immediately before attribution: the run just ended
        -- and party pets are still alive/visible.  This fills gaps left by missed UNIT_PET
        -- events (e.g. pets that existed before CHALLENGE_MODE_START fired) and ensures
        -- that every pet summon session during the run has a resolvable owner.
        if MPT.CombatLog then
            local function refreshPetSlot(ownerUnitID, petUnitID)
                if not UnitExists(ownerUnitID) or not UnitExists(petUnitID) then return end
                -- Pet GUIDs and names may be secret strings for cross-realm players.
                -- Never compare secret strings with == / ~= directly; use pcall everywhere.
                local petGUID = pcall and (function()
                    local ok, v = pcall(UnitGUID, petUnitID)
                    return (ok and v ~= nil) and tostring(v) or nil
                end)() or nil
                local petName = pcall and (function()
                    local ok, v = pcall(UnitName, petUnitID)
                    return (ok and v ~= nil) and tostring(v) or nil
                end)() or nil
                local rawOwnerName, rawOwnerRealm = UnitName(ownerUnitID)
                local ownerN = rawOwnerName and tostring(rawOwnerName) or nil
                local ownerR = rawOwnerRealm and tostring(rawOwnerRealm) or nil
                local ownerRNonEmpty = ownerR and (function()
                    local ok, ne = pcall(function() return ownerR ~= "" end)
                    return ok and ne
                end)()
                if ownerN and ownerRNonEmpty then ownerN = ownerN .. "-" .. ownerR end
                local ownerNNonEmpty = ownerN and (function()
                    local ok, ne = pcall(function() return ownerN ~= "" end)
                    return ok and ne
                end)()
                if not ownerNNonEmpty then return end
                if petGUID and type(MPT.CombatLog.petOwnerNameByGUID) == "table" then
                    pcall(function() MPT.CombatLog.petOwnerNameByGUID[petGUID] = ownerN end)
                end
                if petName and type(MPT.CombatLog.petOwnerByPetName) == "table" then
                    pcall(function() MPT.CombatLog.petOwnerByPetName[petName] = ownerN end)
                end
            end
            refreshPetSlot("player", "pet")
            for i = 1, 5 do refreshPetSlot("party" .. i, "party" .. i .. "pet") end
        end

        if interruptData then
            for name, data in pairs(interruptData) do
                local sourceName = name
                local sourceGUID = type(data) == "table" and (data.sourceGUID or data.guid) or nil
                if sourceGUID ~= nil then
                    sourceGUID = tostring(sourceGUID)
                end
                if MPT.CombatLog then
                    local ownerName = nil
                    local ownerResolution = nil

                    -- Primary: resolve pet source to owner via GUID map.
                    -- Try the primary GUID first, then any additional GUIDs collected
                    -- when the same pet name was resummoned during the run.
                    if MPT.CombatLog.petOwnerNameByGUID then
                        local guidsToTry = {}
                        if sourceGUID then guidsToTry[#guidsToTry + 1] = sourceGUID end
                        if type(data) == "table" and type(data.allGUIDs) == "table" then
                            for g in pairs(data.allGUIDs) do
                                if g ~= sourceGUID then
                                    guidsToTry[#guidsToTry + 1] = g
                                end
                            end
                        end
                        for _, guid in ipairs(guidsToTry) do
                            local ok, resolved = pcall(function()
                                return MPT.CombatLog.petOwnerNameByGUID[guid]
                            end)
                            if ok and resolved and resolved ~= "" then
                                ownerName = resolved
                                ownerResolution = "guid"
                                break
                            end
                        end
                    end

                    -- Fallback: C_DamageMeter can omit sourceGUID for pet interrupt sources.
                    if (not ownerName or ownerName == "") and type(sourceName) == "string" and sourceName ~= "" and MPT.CombatLog.petOwnerByPetName then
                        local ok, resolved = pcall(function()
                            return MPT.CombatLog.petOwnerByPetName[sourceName]
                        end)
                        if ok then
                            ownerName = resolved
                            if ownerName and ownerName ~= "" then
                                ownerResolution = "pet-name-map"
                            end
                        end
                    end

                    -- Last-resort fallback: match the pet display name against current live pet units.
                    if (not ownerName or ownerName == "") and type(sourceName) == "string" and sourceName ~= "" then
                        ownerName = ResolvePetOwnerByCurrentUnits(sourceName)
                        if ownerName and ownerName ~= "" and type(MPT.CombatLog.petOwnerByPetName) == "table" then
                            MPT.CombatLog.petOwnerByPetName[sourceName] = ownerName
                            ownerResolution = "live-unit-scan"
                        end
                    end

                    if ownerName and ownerName ~= "" then
                        if ownerResolution then
                            L("INFO", "Interrupt attribution: source='" .. tostring(name) .. "' guid='" .. tostring(sourceGUID) .. "' -> owner='" .. tostring(ownerName) .. "' via " .. ownerResolution)
                        end
                        sourceName = ownerName
                    elseif type(sourceName) == "string" and sourceName ~= "" and not NameHasRealm(sourceName) and (tonumber(data.interrupts) or 0) > 0 then
                        L("WARN", "Interrupt attribution unresolved for pet-like source='" .. tostring(sourceName) .. "' guid='" .. tostring(sourceGUID) .. "' interrupts=" .. tostring(tonumber(data.interrupts) or 0))
                    end

                    -- Upgrade short owner names to Name-Realm when possible.
                    if type(sourceName) == "string" and sourceName ~= "" and (not NameHasRealm(sourceName)) and type(MPT.CombatLog.fullNameByShort) == "table" then
                        local upgraded = MPT.CombatLog.fullNameByShort[sourceName]
                        if type(upgraded) == "string" and upgraded ~= "" then
                            sourceName = upgraded
                        end
                    end
                end

                local entry = EnsureEntry(sourceName)
                if entry then
                    entry.interrupts = (entry.interrupts or 0) + (tonumber(data.interrupts) or 0)
                    entry.class = data.class or entry.class
                end
            end
        end

        if dispelData then
            for name, data in pairs(dispelData) do
                local entry = EnsureEntry(name)
                if entry then
                    entry.dispels = (entry.dispels or 0) + (tonumber(data.dispels) or 0)
                    entry.class = data.class or entry.class
                end
            end
        end

        if next(combined) then
            detailsStats = combined
            combatDataSource = "C_DamageMeter API"
            -- print("|cff00ffaa[StormsDungeonData]|r Combat data retrieved from C_DamageMeter API")
        else
            -- print("|cff00ffaa[StormsDungeonData]|r C_DamageMeter API returned no data, trying fallback sources...")
        end
    end

    local function EnsurePlayersFromStats(stats)
        if not stats then
            return
        end

        local function HasCombatActivity(data)
            return data and (
                (data.damage and data.damage > 0)
                or (data.healing and data.healing > 0)
                or (data.interrupts and data.interrupts > 0)
                or (data.dispels and data.dispels > 0)
            )
        end

        -- Remove invalid player entries (non-string names) before merging stats.
        if MPT.CurrentRunData.players then
            local cleaned = {}
            for _, p in ipairs(MPT.CurrentRunData.players) do
                if p and type(p.name) == "string" and p.name ~= "" then
                    table.insert(cleaned, p)
                end
            end
            MPT.CurrentRunData.players = cleaned
        end
        MPT.CurrentRunData.players = MPT.CurrentRunData.players or {}
        
        -- ONLY use combat log as the authoritative source - don't cross-check with damage meters
        -- since players may have left the party after the run
        local combatLogPlayers = nil
        if MPT.CombatLog and MPT.CombatLog.GetValidatedPlayerNames then
            combatLogPlayers = MPT.CombatLog:GetValidatedPlayerNames()
            if combatLogPlayers and next(combatLogPlayers) then
                local count = 0
                for _ in pairs(combatLogPlayers) do count = count + 1 end
                L("INFO","|cff00ffaa[StormsDungeonData]|r Combat log validated " .. count .. " players (authoritative source)")
            end
        end

        local rosterPlayers = nil
        if MPT.CombatLog and type(MPT.CombatLog.activeRoster) == "table" and next(MPT.CombatLog.activeRoster) then
            rosterPlayers = MPT.CombatLog.activeRoster
        end

        local useRosterFallback = (not combatLogPlayers or not next(combatLogPlayers)) and rosterPlayers
        if useRosterFallback then
            local rosterCount = 0
            for _ in pairs(rosterPlayers) do rosterCount = rosterCount + 1 end
            L("INFO","|cff00ffaa[StormsDungeonData]|r Combat log activity empty; using active roster fallback (" .. tostring(rosterCount) .. " players)")
        end
        
        local existing = {}
        for _, p in ipairs(MPT.CurrentRunData.players) do
            local key = NormalizeUnitName(p.name) or p.name
            if key then
                existing[key] = true
            end
        end
        
        -- Only add players from stats if they're in the combat log validation list
        for key, data in pairs(stats) do
            if not existing[key] then
                local isValid = false
                
                -- Accept only if validated by combat log and name has realm (no realm = pet)
                if combatLogPlayers and combatLogPlayers[key] then
                        local displayName = (type(data.name) == "string" and data.name ~= "" and data.name) or (type(key) == "string" and key ~= "" and key) or nil
                        displayName = ResolveFullPlayerName(displayName) or displayName
                    if displayName then
                        isValid = true
                        local class = data.class
                        table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(nil, displayName, class, nil))
                        existing[key] = true
                        L("INFO","|cff00ffaa[StormsDungeonData]|r ✓ Validated player: " .. displayName)
                    end
                elseif useRosterFallback and rosterPlayers[key] and HasCombatActivity(data) then
                    local displayName = (type(data.name) == "string" and data.name ~= "" and data.name) or (type(key) == "string" and key ~= "" and key) or nil
                    displayName = ResolveFullPlayerName(displayName) or displayName
                    if displayName then
                        isValid = true
                        local class = data.class
                        table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(nil, displayName, class, nil))
                        existing[key] = true
                        L("INFO","|cff00ffaa[StormsDungeonData]|r ✓ Roster-fallback player: " .. displayName)
                    end
                end
            end
        end

        -- Ensure all validated combat-log players are represented, even if C_DamageMeter
        -- omitted one player's rows for some metrics.
        if combatLogPlayers then
            for validatedName, isValid in pairs(combatLogPlayers) do
                if isValid and not existing[validatedName] then
                    local displayName = ResolveFullPlayerName(validatedName) or validatedName
                    if displayName and displayName ~= "" then
                        table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(nil, displayName, nil, nil))
                        existing[validatedName] = true
                        L("INFO","|cff00ffaa[StormsDungeonData]|r ✓ Added validated combat-log player: " .. tostring(displayName))
                    end
                end
            end
        end
        
        -- Final safety check: ensure we never have more than 5 players
        if #MPT.CurrentRunData.players > 5 then
            L("INFO","|cffff4444[StormsDungeonData]|r WARNING: Found " .. #MPT.CurrentRunData.players .. " players, trimming to 5 most active")
            -- Sort by total activity (damage + healing) and keep only top 5
            table.sort(MPT.CurrentRunData.players, function(a, b)
                local aKey = (a and a.name) and (NormalizeUnitName(a.name) or a.name) or nil
                local bKey = (b and b.name) and (NormalizeUnitName(b.name) or b.name) or nil
                local aStats = (aKey and stats and stats[aKey]) or {}
                local bStats = (bKey and stats and stats[bKey]) or {}
                local aActivity = (aStats.damage or 0) + (aStats.healing or 0) + ((aStats.interrupts or 0) * 25000)
                local bActivity = (bStats.damage or 0) + (bStats.healing or 0) + ((bStats.interrupts or 0) * 25000)
                return aActivity > bActivity
            end)
            -- Trim to 5 players
            local trimmed = {}
            for i = 1, math.min(5, #MPT.CurrentRunData.players) do
                table.insert(trimmed, MPT.CurrentRunData.players[i])
            end
            MPT.CurrentRunData.players = trimmed
            L("INFO","|cff00ffaa[StormsDungeonData]|r Kept top 5 players by activity")
        end
    end

    -- For abandoned runs, bypass the combat-log validator (which may contain stale players
    -- from the previous run) and build the player list directly from the C_DamageMeter
    -- data, which is always scoped to the current session and shows the correct group.
    if isAbandon and detailsStats and next(detailsStats) then
        MPT.CurrentRunData.players = {}
        local meterEntries = {}
        for key, data in pairs(detailsStats) do
            local displayName = (type(data.name) == "string" and data.name ~= "" and data.name)
                or (type(key) == "string" and key ~= "" and key) or nil
            displayName = ResolveFullPlayerName(displayName) or displayName
            if displayName and displayName ~= "" then
                local activity = (data.damage or 0) + (data.healing or 0) + ((data.interrupts or 0) * 25000)
                table.insert(meterEntries, { name = displayName, class = data.class, activity = activity })
            end
        end
        table.sort(meterEntries, function(a, b) return a.activity > b.activity end)
        for i = 1, math.min(5, #meterEntries) do
            local e = meterEntries[i]
            table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(nil, e.name, e.class, nil))
        end
        L("INFO", "Abandon: built player list from C_DamageMeter (" .. #MPT.CurrentRunData.players .. " players)")
    else
        EnsurePlayersFromStats(detailsStats)
    end

    local function SupplementPlayersFromSource(source, sourceLabel)
        if not source or type(source) ~= "table" then
            return 0
        end

        MPT.CurrentRunData.players = MPT.CurrentRunData.players or {}

        local existing = {}
        for _, p in ipairs(MPT.CurrentRunData.players) do
            if p and type(p.name) == "string" and p.name ~= "" then
                local key = NormalizeUnitName(p.name) or p.name
                if key then
                    existing[key] = true
                end
            end
        end

        local added = 0
        for _, member in ipairs(source) do
            if #MPT.CurrentRunData.players >= 5 then
                break
            end
            if member and type(member.name) == "string" and member.name ~= "" then
                local resolvedMemberName = ResolveFullPlayerName(member.name) or member.name
                local key = NormalizeUnitName(resolvedMemberName) or resolvedMemberName
                if key and not existing[key] then
                    table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(member.unitID, resolvedMemberName, member.class, member.role))
                    existing[key] = true
                    added = added + 1
                end
            end
        end

        if added > 0 then
            L("INFO","|cff00ffaa[StormsDungeonData]|r Player list supplemented from " .. tostring(sourceLabel) .. " (+" .. tostring(added) .. ", now " .. tostring(#MPT.CurrentRunData.players) .. "/5)")
        end

        return added
    end

    -- If the list is underpopulated (<5), supplement missing names from completion/party sources.
    -- This preserves already validated players while filling late-missing members at dungeon end.
    local playerCount = (MPT.CurrentRunData.players and #MPT.CurrentRunData.players) or 0
    if playerCount < 5 then
        if MPT.CurrentRunData.groupMembers and #MPT.CurrentRunData.groupMembers > 0 then
            SupplementPlayersFromSource(MPT.CurrentRunData.groupMembers, "existing group members")
        end

        local completionMembers = BuildGroupMembersFromCompletionMembers((GetCompletionInfoCompat() or {}).members)
        SupplementPlayersFromSource(completionMembers, "challenge completion members")

        if #MPT.CurrentRunData.players < 5 and MPT.CombatLog and type(MPT.CombatLog.activeRoster) == "table" and next(MPT.CombatLog.activeRoster) then
            local rosterFallback = {}
            for shortName, inRoster in pairs(MPT.CombatLog.activeRoster) do
                if inRoster and type(shortName) == "string" and shortName ~= "" then
                    local classToken = nil
                    if type(MPT.CombatLog.playerStats) == "table" and type(MPT.CombatLog.playerStats[shortName]) == "table" then
                        classToken = MPT.CombatLog.playerStats[shortName].class
                    end
                    table.insert(rosterFallback, MPT.Database:CreatePlayerStats(nil, shortName, classToken, nil))
                end
            end
            SupplementPlayersFromSource(rosterFallback, "combat-log roster")
        end

        if #MPT.CurrentRunData.players < 5 then
            local partyFallback = CollectGroupPlayerStats()
            SupplementPlayersFromSource(partyFallback, "current party roster")
        end

        if MPT.CurrentRunData.players and #MPT.CurrentRunData.players > 0 then
            MPT.CurrentRunData.groupMembers = ClonePlayerList(MPT.CurrentRunData.players)
        end
    end

    -- If we still don't have valid player names, fall back to group members.
    if (not MPT.CurrentRunData.players or #MPT.CurrentRunData.players == 0) and MPT.CurrentRunData.groupMembers then
        MPT.CurrentRunData.players = {}
        for _, p in ipairs(MPT.CurrentRunData.groupMembers) do
            if p and type(p.name) == "string" and p.name ~= "" then
                table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(p.unitID, p.name, p.class, p.role))
            end
        end
    end

    -- If players exist but none have names, rebuild from stats so UI can render safely.
    if detailsStats then
        local hasNamedPlayer = false
        if MPT.CurrentRunData.players then
            for _, p in ipairs(MPT.CurrentRunData.players) do
                if p and type(p.name) == "string" and p.name ~= "" then
                    hasNamedPlayer = true
                    break
                end
            end
        end

        if not hasNamedPlayer then
            MPT.CurrentRunData.players = {}
            for key, data in pairs(detailsStats) do
                local displayName = (type(data.name) == "string" and data.name ~= "" and data.name) or (type(key) == "string" and key ~= "" and key) or nil
                displayName = ResolveFullPlayerName(displayName) or displayName
                local allowed = (combatLogPlayers and combatLogPlayers[key]) or (useRosterFallback and rosterPlayers and rosterPlayers[key] and HasCombatActivity(data))
                if displayName and allowed then
                    local class = data.class
                    table.insert(MPT.CurrentRunData.players, MPT.Database:CreatePlayerStats(nil, displayName, class, nil))
                end
            end
        end
    end

    local function BuildRunPlayerGUIDMap()
        local byFullLower = {}
        local byShortLower = {}

        local function addNameGuid(rawName, guid)
            if type(rawName) ~= "string" or rawName == "" or type(guid) ~= "string" or guid == "" then
                return
            end
            local fullName = ResolveFullPlayerName(rawName) or rawName
            local shortName = NormalizeUnitName(fullName) or fullName
            byFullLower[string.lower(fullName)] = guid
            byShortLower[string.lower(shortName)] = guid
        end

        local completionInfo = GetCompletionInfoCompat()
        local completionMembers = completionInfo and completionInfo.members
        if type(completionMembers) == "table" then
            for _, member in ipairs(completionMembers) do
                if type(member) == "table" then
                    addNameGuid(member.name, member.memberGUID or member.guid)
                end
            end
        end

        if MPT.CurrentRunData then
            for _, sourceList in ipairs({ MPT.CurrentRunData.players, MPT.CurrentRunData.groupMembers }) do
                if type(sourceList) == "table" then
                    for _, player in ipairs(sourceList) do
                        if type(player) == "table" then
                            addNameGuid(player.name, player.guid)
                        end
                    end
                end
            end
        end

        if MPT.CombatLog and type(MPT.CombatLog.playerGUIDToName) == "table" then
            for guid, mappedName in pairs(MPT.CombatLog.playerGUIDToName) do
                addNameGuid(mappedName, guid)
            end
        end

        for i = 1, 5 do
            local unitID = (i == 1) and "player" or ("party" .. (i - 1))
            if UnitExists(unitID) then
                local unitGUID = UnitGUID(unitID)
                local unitName, unitRealm = UnitName(unitID)
                if type(unitName) == "string" and unitName ~= "" then
                    if unitRealm and unitRealm ~= "" then
                        unitName = unitName .. "-" .. unitRealm
                    end
                    addNameGuid(unitName, unitGUID)
                end
            end
        end

        return byFullLower, byShortLower
    end

    local guidByFullLower, guidByShortLower = BuildRunPlayerGUIDMap()

    local function ExtractDeathsFromMember(member)
        if type(member) ~= "table" then
            return nil
        end

        local function numberFrom(value)
            local n = tonumber(value)
            if n and n >= 0 then
                return n
            end
            return nil
        end

        local candidates = {
            member.deaths,
            member.deathCount,
            member.numDeaths,
            member.playerDeaths,
            member.totalDeaths,
            member.deathsTaken,
        }
        for _, value in ipairs(candidates) do
            local n = numberFrom(value)
            if n then
                return n
            end
        end

        if type(member.stats) == "table" then
            local statsCandidates = {
                member.stats.deaths,
                member.stats.deathCount,
                member.stats.numDeaths,
                member.stats.playerDeaths,
                member.stats.totalDeaths,
            }
            for _, value in ipairs(statsCandidates) do
                local n = numberFrom(value)
                if n then
                    return n
                end
            end
        end

        return nil
    end

    local function BuildCompletionDeathsMaps()
        local byGuid = {}
        local byFullLower = {}
        local byShortLower = {}

        local completionInfo = GetCompletionInfoCompat()
        local members = completionInfo and completionInfo.members
        if type(members) ~= "table" then
            return byGuid, byFullLower, byShortLower
        end

        for _, member in ipairs(members) do
            if type(member) == "table" then
                local deathCount = ExtractDeathsFromMember(member)
                if deathCount and deathCount >= 0 then
                    local memberGUID = member.memberGUID or member.guid
                    local rawName = member.name
                    local fullName = ResolveFullPlayerName(rawName) or rawName
                    local shortName = NormalizeUnitName(fullName) or fullName

                    if type(memberGUID) == "string" and memberGUID ~= "" then
                        byGuid[memberGUID] = deathCount
                    end
                    if type(fullName) == "string" and fullName ~= "" then
                        byFullLower[string.lower(fullName)] = deathCount
                    end
                    if type(shortName) == "string" and shortName ~= "" then
                        byShortLower[string.lower(shortName)] = deathCount
                    end
                end
            end
        end

        return byGuid, byFullLower, byShortLower
    end

    local completionDeathsByGuid, completionDeathsByFullLower, completionDeathsByShortLower = BuildCompletionDeathsMaps()

    if MPT.CurrentRunData.players then
        local hasCombatData = false
        
        -- Fetch deaths and avoidable damage from C_DamageMeter if available
        local deathsData = nil
        local avoidableData = nil
        if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus then
            deathsData = MPT.DamageMeterCompat:GetDeathsData()
            avoidableData = MPT.DamageMeterCompat:GetAvoidableDamageData()
            if deathsData and next(deathsData) then
                -- print("|cff00ffaa[StormsDungeonData]|r Retrieved deaths data from C_DamageMeter")
            end
            if avoidableData and next(avoidableData) then
                -- print("|cff00ffaa[StormsDungeonData]|r Retrieved avoidable damage data from C_DamageMeter")
            end
        end
        
        local function FindMetricByName(metricData, fullName, shortName)
            if type(metricData) ~= "table" then
                return nil
            end

            local fullNameLower = type(fullName) == "string" and string.lower(fullName) or nil
            local shortNameLower = type(shortName) == "string" and string.lower(shortName) or nil

            if fullName and metricData[fullName] then
                return metricData[fullName]
            end
            if shortName and metricData[shortName] then
                return metricData[shortName]
            end

            for rawName, metric in pairs(metricData) do
                if type(rawName) == "string" then
                    local rawShort = NormalizeUnitName(rawName) or rawName
                    local rawNameLower = string.lower(rawName)
                    local rawShortLower = string.lower(rawShort)
                    if (shortName and rawShort == shortName)
                        or (fullName and rawName == fullName)
                        or (shortNameLower and rawShortLower == shortNameLower)
                        or (fullNameLower and rawNameLower == fullNameLower)
                    then
                        return metric
                    end
                end
            end

            return nil
        end

        for _, p in ipairs(MPT.CurrentRunData.players) do
            p.name = ResolveFullPlayerName(p.name) or p.name
            local key = NormalizeUnitName(p.name) or p.name
            if (not p.guid or p.guid == "") and type(p.name) == "string" and p.name ~= "" then
                local fullLower = string.lower(p.name)
                local shortLower = string.lower(key)
                p.guid = guidByFullLower[fullLower] or guidByShortLower[shortLower] or p.guid
            end
            local stats = (detailsStats and key and detailsStats[key])
                or (MPT.CombatLog and MPT.CombatLog:GetPlayerStats(p.name))
                or {}
            
            L("INFO","|cff00ffaa[StormsDungeonData]|r Fetching stats for player: '" .. tostring(p.name) .. "', key='" .. tostring(key) .. "'")
            
            if combatDataSource == "none" and MPT.CombatLog and MPT.CombatLog.GetPlayerStats then
                local clStats = MPT.CombatLog:GetPlayerStats(p.name)
                if clStats and (clStats.damage > 0 or clStats.healing > 0 or clStats.interrupts > 0) then
                    stats = clStats
                    combatDataSource = "CombatLog"
                end
            end
            
            p.damage = stats.damage or 0
            p.healing = stats.healing or 0
            p.interrupts = stats.interrupts or 0
            p.dispels = stats.dispels or 0
            p.deaths = stats.deaths or 0
            p.avoidableDamageTaken = stats.avoidableDamageTaken or 0
            
            L("INFO","|cff00ffaa[StormsDungeonData]|r   Stats assigned: damage=" .. p.damage .. ", healing=" .. p.healing .. ", interrupts=" .. p.interrupts .. ", dispels=" .. p.dispels .. ", deaths=" .. p.deaths .. ", avoidable=" .. p.avoidableDamageTaken)
            
            -- Override deaths with C_DamageMeter data if available
            local baselineDeaths = p.deaths or 0
            local playerGUID = ResolvePlayerGUID(p.name, p.unitID, p.guid)
            local guidApiDeaths = nil
            local fallbackApiDeaths = nil
            local completionDeaths = nil

            if playerGUID then
                completionDeaths = completionDeathsByGuid[playerGUID]
            end
            if completionDeaths == nil and type(p.name) == "string" and p.name ~= "" then
                completionDeaths = completionDeathsByFullLower[string.lower(p.name)]
            end
            if completionDeaths == nil and key and type(key) == "string" and key ~= "" then
                completionDeaths = completionDeathsByShortLower[string.lower(key)]
            end

            if completionDeaths and completionDeaths > 0 then
                p.deaths = math.max(p.deaths or 0, completionDeaths)
            end

            if playerGUID and MPT.DamageMeterCompat and MPT.DamageMeterCompat.GetDeathCountForSourceGUID then
                guidApiDeaths = tonumber(MPT.DamageMeterCompat:GetDeathCountForSourceGUID(playerGUID)) or nil
            end

            if guidApiDeaths and guidApiDeaths > 0 then
                p.deaths = math.max(p.deaths or 0, guidApiDeaths)
            elseif deathsData then
                local deathInfo = FindMetricByName(deathsData, p.name, key)
                if deathInfo then
                    fallbackApiDeaths = tonumber(deathInfo.deaths) or 0
                    if fallbackApiDeaths > 0 then
                        p.deaths = math.max(p.deaths or 0, fallbackApiDeaths)
                    end
                end
            end

            if DEBUG_PERSONAL_DEATHS then
                -- print("|cff00ffaa[StormsDungeonData]|r DeathDebug player='" .. tostring(p.name)
                --     .. "' guid='" .. tostring(playerGUID)
                --     .. "' base=" .. tostring(baselineDeaths)
                --         .. " completion=" .. tostring(completionDeaths)
                --     .. " guidApi=" .. tostring(guidApiDeaths)
                --     .. " fallbackApi=" .. tostring(fallbackApiDeaths)
                --     .. " final=" .. tostring(p.deaths))
            end
            
            -- Override avoidable damage with C_DamageMeter data if available
            if avoidableData then
                local avoidableInfo = FindMetricByName(avoidableData, p.name, key)
                if avoidableInfo then
                    p.avoidableDamageTaken = avoidableInfo.avoidableDamageTaken or 0
                end
            end
            
            if p.damage > 0 or p.healing > 0 or p.interrupts > 0 then
                hasCombatData = true
            end

            local apiDPS = tonumber(stats.damagePerSecond) or tonumber(stats.dps)
            local apiHPS = tonumber(stats.healingPerSecond) or tonumber(stats.hps)

            if apiDPS and apiDPS > 0 then
                p.damagePerSecond = math.floor(apiDPS)
            elseif duration and duration > 0 then
                p.damagePerSecond = math.floor((p.damage or 0) / duration)
            else
                p.damagePerSecond = 0
            end

            if apiHPS and apiHPS > 0 then
                p.healingPerSecond = math.floor(apiHPS)
            elseif duration and duration > 0 then
                p.healingPerSecond = math.floor((p.healing or 0) / duration)
            else
                p.healingPerSecond = 0
            end

            if duration and duration > 0 then
                p.interruptsPerMinute = math.floor(((p.interrupts or 0) / duration) * 60)
            else
                p.interruptsPerMinute = 0
            end

            -- Base contribution used for points (our calculation)
            local base = (p.damage or 0) + (p.healing or 0) + ((p.interrupts or 0) * 25000) + ((p.dispels or 0) * 20000)
            p._pointsBase = base
            sumBase = sumBase + base
        end
        
        -- Provide diagnostic info if no combat data was found
        if not hasCombatData then
            if MPT.DamageMeterCompat and MPT.DamageMeterCompat.IsWoW12Plus then

            end
            if not MPT.CombatLog or not MPT.CombatLog.isTracking then
            end
        
        else
            L("INFO","|cff00ffaa[StormsDungeonData]|r Combat data source: " .. combatDataSource)
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

    -- If every player has all-zero combat stats, skip saving entirely (no DB write, no chat).
    if MPT.CurrentRunData.players and #MPT.CurrentRunData.players > 0 then
        local anyNonZero = false
        for _, p in ipairs(MPT.CurrentRunData.players) do
            if (p.damage or 0) > 0 or (p.healing or 0) > 0 or (p.interrupts or 0) > 0 then
                anyNonZero = true
                break
            end
        end
        if not anyNonZero then
            L("WARN", "FinalizeRun: all player stats are zero - skipping save")
            RecordFlow("FINALIZE_ABORT", "all_zeros")
            MPT.CurrentRunData = nil
            return false
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
        
        -- Save class information for filtering
        local localizedClass, classToken = UnitClass("player")
        if classToken then
            runRecord.class = classToken
            if localizedClass then
                runRecord.className = localizedClass
            elseif LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken] then
                runRecord.className = LOCALIZED_CLASS_NAMES_MALE[classToken]
            end
        end

        -- Persist season metadata so historical splits stay accurate across future seasons.
        if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" then
            runRecord.seasonID = C_MythicPlus.GetCurrentSeason()
        end
        if type(GetExpansionLevel) == "function" then
            runRecord.expansionLevel = GetExpansionLevel()
            local expansionAbbrevByLevel = {
                [7] = "BFA",
                [8] = "SL",
                [9] = "DF",
                [10] = "TWW",
                [11] = "Midnight",
            }
            runRecord.expansionAbbrev = expansionAbbrevByLevel[runRecord.expansionLevel]
        end
    end

    runRecord.mobsKilled = MPT.CurrentRunData.mobsKilled or 0
    runRecord.mobsTotal = MPT.CurrentRunData.mobsTotal or 0
    runRecord.overallMobPercentage = MPT.CurrentRunData.overallMobPercentage or 0
    -- Deaths: use C_ChallengeMode.GetDeathCount() as authoritative for the key (numDeaths, timeLost)
    local apiDeaths, apiTimeLost = nil, nil
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        apiDeaths, apiTimeLost = C_ChallengeMode.GetDeathCount()
    end
    if apiDeaths ~= nil and apiDeaths >= 0 then
        runRecord.deathCount = apiDeaths
    else
        local fallback = tonumber(MPT.CurrentRunData.deathCount)
        local sumDeaths = 0
        for _, p in ipairs(runRecord.players or {}) do
            sumDeaths = sumDeaths + (p.deaths or 0)
        end
        runRecord.deathCount = math.max(fallback or 0, sumDeaths)
    end
    runRecord.timeLost = (apiTimeLost ~= nil and apiTimeLost >= 0) and apiTimeLost or MPT.CurrentRunData.timeLost
    runRecord.finalizeReason = reason
    runRecord.groupMembers = MPT.CurrentRunData.groupMembers
    if MPT.CurrentRunData.abandonReason then
        runRecord.abandonReason = MPT.CurrentRunData.abandonReason
    end

    -- Mythic+ rating change for this run (used by History Viewer for score tracking)
    if not isAbandon then
        local oldScore = MPT.CurrentRunData.oldDungeonScore
        local newScore = MPT.CurrentRunData.newDungeonScore
        -- Fallback: read directly from Blizzard's completion API at save time
        if (not oldScore or not newScore) and C_ChallengeMode and type(C_ChallengeMode.GetChallengeCompletionInfo) == "function" then
            local completionInfo = C_ChallengeMode.GetChallengeCompletionInfo()
            if type(completionInfo) == "table" then
                oldScore = oldScore or completionInfo.oldOverallDungeonScore
                newScore = newScore or completionInfo.newOverallDungeonScore
            end
        end
        runRecord.oldDungeonScore = oldScore
        runRecord.newDungeonScore = newScore
    end

    -- Store MVP name (same logic as scoreboard) so History shows correct "you were MVP" for the run owner
    -- Skip MVP calculation for abandoned keys
    if not isAbandon then
        runRecord.mvpName = (MPT.Scoreboard and MPT.Scoreboard.ComputeMVPName) and MPT.Scoreboard:ComputeMVPName(runRecord) or nil
    else
        runRecord.mvpName = nil
        L("INFO", "Skipping MVP calculation for abandoned key")
    end

    -- Final pass: fill in any missing specIDs from the cache or live API before saving
    if runRecord.players then
        for _, p in ipairs(runRecord.players) do
            if not p.specID or p.specID == 0 then
                -- Try cache by GUID
                if p.guid and MPT.SpecCache[p.guid] then
                    p.specID = MPT.SpecCache[p.guid]
                -- Try live inspect if unit is still in group
                elseif p.unitID and UnitExists(p.unitID) and GetInspectSpecialization then
                    local sid = GetInspectSpecialization(p.unitID)
                    if sid and sid > 0 then
                        p.specID = sid
                        if p.guid then MPT.SpecCache[p.guid] = sid end
                    end
                end
            end
        end
    end

    local savedToDb, saveErr = MPT.Database:SaveRun(runRecord)
    if not savedToDb then
        if saveErr == "duplicate" then
            L("INFO", "FinalizeRun: duplicate run detected, skipping save")
            RecordFlow("FINALIZE_DUPLICATE", tostring(reason))
            print("|cff00ffaa[StormsDungeonData]|r This run was already saved. Skipping duplicate save.")
            MPT.CurrentRunData.saved = true
            MPT.CurrentRunData = nil
            MPT.RunJustSaved = true
            return false
        end
        L("ERROR", "FinalizeRun: failed to save run to DB")
        RecordFlow("FINALIZE_ERROR", "database save failed")
        print("|cffff4444[StormsDungeonData]|r ERROR: Failed to save run.")
        return false
    end

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

    -- Show scoreboard only for completed runs (not abandoned keys)
    -- Abandoned keys should be logged but not displayed
    if autoShow and not isAbandon then
        MPT.UI:ShowScoreboard(runRecord)
        MPT.LastSavedRunShown = true
    elseif isAbandon then
        local abandonDungeonName = (runRecord and runRecord.dungeonName) or (MPT.CurrentRunData and MPT.CurrentRunData.dungeonName) or "Dungeon"
        print("|cff00ffaa[StormsDungeonData]|r " .. abandonDungeonName .. " Abandon, Run saved.")
    end

    L("INFO", "Run saved successfully (reason=" .. tostring(reason) .. ")")
    RecordFlow("FINALIZE_SUCCESS", tostring(reason))
    MPT.CurrentRunData.saved = true
    if not isAbandon then
        print("|cff00ffaa[StormsDungeonData]|r Run Auto Saved!")
    end
    -- Key ended: stop collecting new live points but keep graph data visible until next Reset().
    if MPT.LiveTracker and MPT.LiveTracker.StopCollection then
        MPT.LiveTracker:StopCollection()
    end
    MPT.CurrentRunData = nil

    -- Stop the completion poller and combat tracking now that the run is saved.
    -- This prevents the 1s poller from re-triggering FinalizeRun while still inside
    -- the dungeon instance (which was causing 5+ duplicate save attempts).
    self:StopCriteriaCompletionTracker()
    if MPT.CombatLog and MPT.CombatLog.StopTracking then
        MPT.CombatLog:StopTracking()
        L("INFO", "Combat tracking stopped after successful run save")
    end

    -- Run is saved. Set RunJustSaved so no further saves occur for this instance.
    -- It is cleared only when CHALLENGE_MODE_START fires (new key begins).
    MPT.InMythicPlus = false
    MPT.RunJustSaved = true
    MPT.RunSavedAt = time()
    Events:StartRunStateWatcher(5)

    return true
end

-- Initialize run history tracking at the start of a M+ run
-- This captures the baseline history to compare against when checking for completion
function Events:InitializeRunHistoryTracking()
    -- Verify we have the API available
    if not C_MythicPlus or type(C_MythicPlus.GetRunHistory) ~= "function" then
        return
    end
    
    -- Reset the history tracker
    MPT.LastKnownRunHistory = {}
    
    -- Get current run history (this week only, completed runs only)
    local currentHistory = C_MythicPlus.GetRunHistory(false, false)
    if not currentHistory or type(currentHistory) ~= "table" then
        return
    end
    
    -- Store all completed runs from this week as baseline
    for _, run in ipairs(currentHistory) do
        if run.completed and run.thisWeek then
            local key = GetRunHistoryKey(run)
            if key then
                MPT.LastKnownRunHistory[key] = true
            end
        end
    end
    
    L("INFO", "Run history tracking initialized with " .. tostring(#currentHistory) .. " existing runs")
end

-- Check if a Mythic+ run has been completed by querying C_MythicPlus.GetRunHistory()
-- Called when combat ends (PLAYER_REGEN_ENABLED)
function Events:CheckRunHistoryForCompletion()
    -- No-op: end-of-run detection now uses boss/forces criteria only.
end

function Events:StopEndOfDungeonHistoryPoll()
    -- Cancel any lingering ticker for safety, then no-op.
    if self.endOfDungeonHistoryPollTicker then
        self.endOfDungeonHistoryPollTicker:Cancel()
        self.endOfDungeonHistoryPollTicker = nil
    end
end

function Events:StartEndOfDungeonHistoryPoll(reason)
    -- No-op: end-of-run detection now uses boss/forces criteria only.
end


-- Reconstruct CurrentRunData from C_MythicPlus.GetRunHistory() entry
function Events:ReconstructRunDataFromHistory(runInfo)
    if not runInfo then
        L("INFO","|cffff4444[StormsDungeonData]|r Cannot reconstruct run: no run info provided")
        return false
    end
    
    L("INFO","|cff00ffaa[StormsDungeonData]|r Reconstructing run data from history...")
    print("|cff00ffaa[StormsDungeonData]|r   mapChallengeModeID: " .. tostring(runInfo.mapChallengeModeID))
    print("|cff00ffaa[StormsDungeonData]|r   level: " .. tostring(runInfo.level))
    print("|cff00ffaa[StormsDungeonData]|r   completed: " .. tostring(runInfo.completed))
    print("|cff00ffaa[StormsDungeonData]|r   durationSec: " .. tostring(runInfo.durationSec))
    
    -- Get dungeon info
    local dungeonName = C_ChallengeMode.GetMapUIInfo(runInfo.mapChallengeModeID)
    if not dungeonName then
        dungeonName = "Unknown Dungeon"
        L("INFO","|cffff4444[StormsDungeonData]|r WARNING: Could not get dungeon name from mapID " .. tostring(runInfo.mapChallengeModeID))
    else
        print("|cff00ffaa[StormsDungeonData]|r   dungeonName: " .. dungeonName)
    end
    
    -- Get current affixes
    local affixes = {}
    local affixIDs = C_MythicPlus.GetCurrentAffixes()
    if affixIDs then
        for _, affixInfo in ipairs(affixIDs) do
            table.insert(affixes, affixInfo.id)
        end
    end
    
    -- Get actual enemy forces data - try live data first, then fall back to cached
    local enemyForces = GetEnemyForcesProgress()
    local enemyPercent = 100.0
    if enemyForces and enemyForces.percent then
        enemyPercent = enemyForces.percent
        L("INFO","|cff00ffaa[StormsDungeonData]|r Using live enemy forces: " .. string.format("%.1f%%", enemyPercent))
    elseif MPT.LastEnemyForces and MPT.LastEnemyForces.percent then
        enemyPercent = MPT.LastEnemyForces.percent
        L("INFO","|cff00ffaa[StormsDungeonData]|r Using cached enemy forces: " .. string.format("%.1f%%", enemyPercent))
    else
        L("INFO","|cff00ffaa[StormsDungeonData]|r No enemy forces data available, assuming 100%")
    end
    
    -- Determine completion timestamp (from history if possible)
    local completionTimestamp = time()
    if runInfo.completionDate then
        if type(runInfo.completionDate) == "table" then
            local ok, ts = pcall(time, runInfo.completionDate)
            if ok and ts then
                completionTimestamp = ts
            end
        elseif type(runInfo.completionDate) == "number" then
            completionTimestamp = runInfo.completionDate
        end
    end

    -- Initialize CurrentRunData
    -- CRITICAL: Ensure dungeonID is valid for save validation
    local validDungeonID = runInfo.mapChallengeModeID
    if not validDungeonID or validDungeonID == 0 then
        L("INFO","|cffff4444[StormsDungeonData]|r ERROR: runInfo has invalid mapChallengeModeID: " .. tostring(validDungeonID))
        return false
    end
    
    local deathCount = 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local deaths, _ = C_ChallengeMode.GetDeathCount()
        if deaths then deathCount = deaths end
    end
    local historyMembers = BuildGroupMembersFromCompletionMembers(runInfo.members)

    MPT.CurrentRunData = {
        dungeonName = dungeonName,
        dungeonID = validDungeonID,
        mapID = validDungeonID,
        keystoneLevel = runInfo.level,
        affixes = affixes,
        startTime = completionTimestamp - (runInfo.durationSec or 0), -- Estimate start time
        completionTime = completionTimestamp,
        completionDuration = runInfo.durationSec,
        completed = runInfo.completed,
        totalEnemyForces = enemyPercent,
        enemyForcesCurrent = enemyPercent,
        players = ClonePlayerList(historyMembers),
        groupMembers = historyMembers,
        saved = false,
        reconstructed = true, -- Flag to indicate this was reconstructed
        deathCount = deathCount,
    }
    
    -- IMPORTANT: Prefer run-history members here when available.
    -- FinalizeRun still refreshes stats from combat/meter data and can supplement missing members.
    if C_ChallengeMode and C_ChallengeMode.GetCompletionInfo then
        local completionInfo = C_ChallengeMode.GetCompletionInfo()
        if completionInfo then
            MPT.CurrentRunData.onTime = completionInfo.onTime
            MPT.CurrentRunData.keystoneUpgrades = completionInfo.keystoneUpgrades
        end
    end
    
    L("INFO","|cff00ffaa[StormsDungeonData]|r Reconstructed: " .. dungeonName .. " +" .. runInfo.level .. " (" .. runInfo.durationSec .. "s)")
    return true
end

-- ============================================================
-- Standalone M+ watcher bootstrap.
-- Starts a self-contained 5s ticker immediately after
-- ADDON_LOADED — no dependency on MPT:Initialize() or
-- Events:Initialize(). When a Mythic+ run is detected it
-- runs the same bootstrap logic as /sdd status automatically.
-- ============================================================
do
    local bootstrapFrame = CreateFrame("Frame")
    local watcherTicker = nil
    local watchTick = 0

    local function EnsureCoreInitialized()
        local MPT = StormsDungeonData
        if not MPT then return end
        if not MPT._coreInitialized then
            MPT._coreInitialized = true
            if MPT.Initialize then
                MPT:Initialize()
            end
        end
    end

    local function StartWatcher()
        if watcherTicker then return end  -- already running
        if not C_Timer or type(C_Timer.NewTicker) ~= "function" then
            L("INFO","|cffff4444[StormsDungeonData]|r ERROR: C_Timer not available, cannot start watcher!")
            return
        end
        print("|cff00ffaa[StormsDungeonData]|r M+ watcher initialized")
        watcherTicker = C_Timer.NewTicker(5, function()
            watchTick = watchTick + 1
            local MPT = StormsDungeonData
            if not MPT then return end

            -- Detect whether a Mythic+ run is active
            local challengeActive = false
            if C_ChallengeMode then
                if type(C_ChallengeMode.IsChallengeModeActive) == "function" then
                    challengeActive = C_ChallengeMode.IsChallengeModeActive() and true or false
                end
                if not challengeActive and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
                    local mid = C_ChallengeMode.GetActiveChallengeMapID()
                    if mid and mid > 0 then challengeActive = true end
                end
            end
            if not challengeActive then
                local _, iType, diff = GetInstanceInfo()
                if iType == "party" and diff == 8 then challengeActive = true end
            end

            if MPT.Log then
                MPT.Log:Log("INFO", "Bootstrap tick#" .. watchTick
                    .. " challengeActive=" .. tostring(challengeActive)
                    .. " InMythicPlus=" .. tostring(MPT.InMythicPlus or false))
            end

            -- If challenge just ended while RunJustSaved, DO NOT clear it here.
            -- RunJustSaved is cleared only on PLAYER_ENTERING_WORLD (true instance leave).
            -- Clearing it based on challengeActive=false is unreliable: IsChallengeModeActive and
            -- the instanceType=party/8 fallback disagree post-completion causing re-arm loops.

            -- If M+ active but not yet tracking, run the same logic as /sdd status.
            -- Skip re-bootstrap if a run was already saved for this instance.
            if challengeActive and not MPT.RunJustSaved and (not MPT.InMythicPlus or (MPT.Events and not MPT.Events.criteriaCompletionTracker)) then
                print("|cff00ffaa[StormsDungeonData]|r M+ Starting - auto-triggering run tracking")
                EnsureCoreInitialized()
                if MPT.Events then
                    if not MPT.InMythicPlus and MPT.Events.TryBootstrapMythicPlusRun then
                        MPT.Events:TryBootstrapMythicPlusRun("auto_bootstrap", true)
                    end
                    if MPT.InMythicPlus and MPT.Events.EnsureCriteriaTrackingForActiveRun then
                        MPT.Events:EnsureCriteriaTrackingForActiveRun("auto_bootstrap")
                    end
                end
            elseif not challengeActive and MPT.InMythicPlus then
                L("INFO","|cff00ffaa[StormsDungeonData]|r M+ no longer active - clearing saved variables")
                if MPT.Log then MPT.Log:Log("INFO", "Bootstrap: challengeActive=false, clearing InMythicPlus") end
                MPT.InMythicPlus = false
            end
        end)
    end

    bootstrapFrame:RegisterEvent("ADDON_LOADED")
    bootstrapFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bootstrapFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "StormsDungeonData" then
            -- Defer via C_Timer.After(0) to step outside any protected execution context
            -- before calling RegisterEvent(), avoiding ADDON_ACTION_FORBIDDEN in WoW 12+.
            C_Timer.After(0, function()
                EnsureCoreInitialized()
                StartWatcher()
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- PLAYER_ENTERING_WORLD can fire during combat (e.g. after /reload in combat).
            -- Defer to avoid calling RegisterEvent() from a protected/tainted context.
            C_Timer.After(0, function()
                EnsureCoreInitialized()
                StartWatcher()
            end)
        end
    end)
end
