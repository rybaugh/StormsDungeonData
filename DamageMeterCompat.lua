-- Mythic Plus Tracker - Damage Meter Compatibility Layer
-- Handles WoW 12.0+ C_DamageMeter API with fallback to legacy combat log
-- WoW 12.0+: Uses C_DamageMeter for session data and C_CombatLog namespace for event info
-- Pre-12.0: Uses COMBAT_LOG_EVENT_UNFILTERED with C_CombatLog deprecation shims
-- Uses Blizzard combat meter APIs with compatibility fallbacks

local MPT = StormsDungeonData
local DamageMeterCompat = {}
MPT.DamageMeterCompat = DamageMeterCompat

local function L(level, msg)
    if MPT.Log then MPT.Log:Log(level or "INFO", msg) end
end

-- Version detection
DamageMeterCompat.IsWoW12Plus = C_DamageMeter ~= nil
DamageMeterCompat.UsesCombatLog = not DamageMeterCompat.IsWoW12Plus

-- Session tracking for WoW 12.0+
DamageMeterCompat.CurrentSessionID = nil
DamageMeterCompat.SessionData = {}

-- Restriction state tracking
DamageMeterCompat.RestrictionState = {
    Combat = 0x1,
    Encounter = 0x2,
    ChallengeMode = 0x4,
    PvPMatch = 0x8,
    Map = 0x10,
}

DamageMeterCompat.CurrentRestrictions = 0x0

local function NormalizeSessionID(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        local n = tonumber(value)
        if n then
            return n
        end
    end
    if type(value) == "table" then
        local n = value.sessionID or value.sessionId or value.id or value.ID
        if type(n) == "number" then
            return n
        end
        if type(n) == "string" then
            n = tonumber(n)
            if n then
                return n
            end
        end
    end
    return nil
end

local function ExtractDeathCountFromSource(source)
    if type(source) ~= "table" then
        return 0
    end

    local candidates = {
        source.totalAmount,
        source.totalCount,
        source.amount,
        source.value,
        source.count,
        source.numDeaths,
        source.deaths,
        source.eventCount,
    }

    for _, value in ipairs(candidates) do
        local n = tonumber(value)
        if n and n >= 0 then
            return n
        end
    end

    if type(source.deathEvents) == "table" then
        return #source.deathEvents
    end
    if type(source.events) == "table" then
        return #source.events
    end

    return 0
end

local function CountDeadlySpells(source)
    if type(source) ~= "table" or type(source.combatSpells) ~= "table" then
        return 0
    end

    local deadlyCount = 0
    for _, spell in ipairs(source.combatSpells) do
        if type(spell) == "table" and spell.isDeadly then
            local n = tonumber(spell.totalAmount) or tonumber(spell.amount) or 0
            if n > 0 then
                deadlyCount = deadlyCount + n
            else
                deadlyCount = deadlyCount + 1
            end
        end
    end

    return deadlyCount
end

local function HasDeathMarker(source)
    if type(source) ~= "table" then
        return false
    end
    if source.deathRecapID ~= nil then
        return true
    end
    if source.deathTimeSeconds ~= nil then
        return true
    end
    return CountDeadlySpells(source) > 0
end

local function ExtractDeathCountWithFallback(source)
    local deaths = ExtractDeathCountFromSource(source)
    if deaths and deaths > 0 then
        return deaths
    end

    local deadlySpells = CountDeadlySpells(source)
    if deadlySpells > 0 then
        return deadlySpells
    end

    if HasDeathMarker(source) then
        return 1
    end

    return 0
end

local function AggregateDeathsBySource(session, targetSourceGUID)
    if type(session) ~= "table" or type(session.combatSources) ~= "table" then
        return nil
    end

    local total = 0
    local found = false
    for _, source in ipairs(session.combatSources) do
        if type(source) == "table" then
            local sourceGUID = source.sourceGUID or source.guid
            if (not targetSourceGUID) or (sourceGUID == targetSourceGUID) then
                found = true
                total = total + (ExtractDeathCountWithFallback(source) or 0)
            end
        end
    end

    if not found then
        return nil
    end

    return total
end

local function SafeMapSet(map, key, value)
    if type(map) ~= "table" then
        return false
    end
    local success, err = pcall(function()
        map[key] = value
    end)
    if not success then
        L("DEBUG", "SafeMapSet failed: " .. tostring(err))
    end
    return success
end

local function SafeMapGet(map, key)
    if type(map) ~= "table" then
        return nil
    end
    local result
    local success, err = pcall(function()
        result = map[key]
    end)
    if not success then
        L("DEBUG", "SafeMapGet failed: " .. tostring(err))
        return nil
    end
    return result
end

local function ToPlainString(value)
    return tostring(value)
end

-- WoW 12.0+ returns "secret strings" from C_DamageMeter when addon code is tainted.
-- These can be used as table keys (via pcall) but throw on == / ~= comparisons.
-- This helper wraps the check so a taint error returns false rather than propagating.
local function SafeNonEmpty(s)
    if s == nil then return false end
    local ok, result = pcall(function() return s ~= "" end)
    return ok and result
end

function DamageMeterCompat:EnsureSessionID()
    if not self.IsWoW12Plus then
        return false
    end

    self.CurrentSessionID = NormalizeSessionID(self.CurrentSessionID)
    if self.CurrentSessionID then
        return true
    end

    local sessions = self:GetAvailableSessions()
    if not sessions then
        return false
    end

    local numericSessions = {}
    for _, v in pairs(sessions) do
        local id = NormalizeSessionID(v)
        if id then
            table.insert(numericSessions, id)
        end
    end

    if #numericSessions == 0 then
        return false
    end

    table.sort(numericSessions)
    self.CurrentSessionID = numericSessions[#numericSessions]
    return self.CurrentSessionID ~= nil
end

function DamageMeterCompat:Initialize()
    if self.IsWoW12Plus then
        self:InitializeDamageMeterAPI()
    end
end

function DamageMeterCompat:InitializeDamageMeterAPI()
    -- C_DamageMeter is a polling API; there are no session-change events in WoW.
    -- Initialization is intentionally a no-op here; data is fetched on demand.
end

function DamageMeterCompat:OnDamageMeterEvent(event, ...)
    -- Stub: COMBAT_METRICS_SESSION_* events do not exist in WoW.
    -- C_DamageMeter is a polling API; session data is queried on demand.
end

function DamageMeterCompat:CheckRestrictions()
    -- Check addon restrictions (WoW 12.0+ feature)
    if not Enum.AddOnRestrictionType then
        return false  -- Restrictions don't exist in this version
    end
    
    self.CurrentRestrictions = 0x0
    
    -- Check each restriction type
    local combatState = C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Combat)
    if combatState > 0 then
        self.CurrentRestrictions = self.CurrentRestrictions + self.RestrictionState.Combat
    end
    
    local encounterState = C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Encounter)
    if encounterState > 0 then
        self.CurrentRestrictions = self.CurrentRestrictions + self.RestrictionState.Encounter
    end
    
    local challengeModeState = C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.ChallengeMode)
    if challengeModeState > 0 then
        self.CurrentRestrictions = self.CurrentRestrictions + self.RestrictionState.ChallengeMode
    end
    
    local pvpState = C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.PvPMatch)
    if pvpState > 0 then
        self.CurrentRestrictions = self.CurrentRestrictions + self.RestrictionState.PvPMatch
    end
    
    local mapState = C_RestrictedActions.GetAddOnRestrictionState(Enum.AddOnRestrictionType.Map)
    if mapState > 0 then
        self.CurrentRestrictions = self.CurrentRestrictions + self.RestrictionState.Map
    end
    
    return self.CurrentRestrictions > 0
end

function DamageMeterCompat:IsRestricted(restrictionType)
    -- Check if a specific restriction is active
    if not Enum.AddOnRestrictionType then
        return false
    end
    
    local state = C_RestrictedActions.GetAddOnRestrictionState(restrictionType)
    return state > 0
end

function DamageMeterCompat:GetDamageData()
    -- Get damage data from C_DamageMeter API
    if not self.IsWoW12Plus then
        return nil
    end

    local damageData = {}

    -- Check for restrictions before proceeding
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        print("|cff00ffaa[StormsDungeonData]|r Warning: Combat data restricted by Blizzard")
        return nil
    end
    
    -- List all available combat sessions
    if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions then
        local sessions = C_DamageMeter.GetAvailableCombatSessions()
        if not sessions or #sessions == 0 then
            L("INFO", "No combat sessions available from C_DamageMeter")
        end
    end

    local damageDoneSession
    if C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType then
        damageDoneSession = C_DamageMeter.GetCombatSessionFromType(
            Enum.DamageMeterSessionType.Overall,
            Enum.DamageMeterType.DamageDone
        )
    end

    if (not damageDoneSession or not damageDoneSession.combatSources) then
        if not self:EnsureSessionID() then
            return nil
        end
        if type(self.CurrentSessionID) ~= "number" then
            return nil
        end
        damageDoneSession = C_DamageMeter.GetCombatSessionFromID(
            self.CurrentSessionID,
            Enum.DamageMeterType.DamageDone
        )
    end
    
    if damageDoneSession and damageDoneSession.combatSources then
        for _, source in ipairs(damageDoneSession.combatSources) do
            if source.name and source.sourceGUID then
                local plainName = ToPlainString(source.name)
                SafeMapSet(damageData, plainName, {
                    damage = source.totalAmount,
                    dps = source.amountPerSecond,
                    class = source.classFilename,
                    specIcon = source.specIconID,
                })
            end
        end
    end
    
    return damageData
end

function DamageMeterCompat:GetHealingData()
    -- Get healing data from C_DamageMeter API
    if not self.IsWoW12Plus then
        return nil
    end

    local healingData = {}

    -- Check for restrictions
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end

    local healingDoneSession
    if C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType then
        healingDoneSession = C_DamageMeter.GetCombatSessionFromType(
            Enum.DamageMeterSessionType.Overall,
            Enum.DamageMeterType.HealingDone
        )
    end

    if (not healingDoneSession or not healingDoneSession.combatSources) then
        if not self:EnsureSessionID() then
            return nil
        end
        if type(self.CurrentSessionID) ~= "number" then
            return nil
        end
        healingDoneSession = C_DamageMeter.GetCombatSessionFromID(
            self.CurrentSessionID,
            Enum.DamageMeterType.HealingDone
        )
    end
    
    if healingDoneSession and healingDoneSession.combatSources then
        for _, source in ipairs(healingDoneSession.combatSources) do
            if source.name and source.sourceGUID then
                local plainName = ToPlainString(source.name)
                SafeMapSet(healingData, plainName, {
                    healing = source.totalAmount,
                    hps = source.amountPerSecond,
                    class = source.classFilename,
                    specIcon = source.specIconID,
                })
            end
        end
    end
    
    return healingData
end

function DamageMeterCompat:GetInterruptData()
    if not self.IsWoW12Plus then
        return nil
    end

    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end

    local interruptData = {}

    -- Helper: merge one combatSources list into interruptData.
    -- Accumulates counts so the same pet name across multiple summon sessions
    -- is credited in full rather than only for the most-recently-seen session.
    local function mergeSources(sources)
        if type(sources) ~= "table" then return end
        for _, source in ipairs(sources) do
            if source.name then
                local plainName = ToPlainString(source.name)
                local existing = SafeMapGet(interruptData, plainName)
                if existing then
                    existing.interrupts = (existing.interrupts or 0) + (source.totalAmount or 0)
                    if source.sourceGUID then
                        if not existing.allGUIDs then existing.allGUIDs = {} end
                        existing.allGUIDs[tostring(source.sourceGUID)] = true
                        existing.sourceGUID = source.sourceGUID
                        existing.guid = source.sourceGUID
                    end
                else
                    local newEntry = {
                        interrupts = source.totalAmount,
                        class = source.classFilename,
                        guid = source.sourceGUID,
                        sourceGUID = source.sourceGUID,
                    }
                    if source.sourceGUID then
                        newEntry.allGUIDs = { [tostring(source.sourceGUID)] = true }
                    end
                    SafeMapSet(interruptData, plainName, newEntry)
                end
            end
        end
    end

    -- Always iterate every individual session so that interrupts from all pulls
    -- are captured regardless of whether the Overall session is complete.
    -- The Overall session can be incomplete for interrupts when a resummoned pet's
    -- earlier sessions are not aggregated — individual sessions are authoritative.
    local hasIndividualSessions = false
    if C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions
            and C_DamageMeter.GetCombatSessionFromID
            and Enum and Enum.DamageMeterType then
        local rawSessions = C_DamageMeter.GetAvailableCombatSessions()
        if rawSessions and #rawSessions > 0 then
            hasIndividualSessions = true
            for _, s in ipairs(rawSessions) do
                local sid = NormalizeSessionID(s.sessionID)
                if sid then
                    local sess = C_DamageMeter.GetCombatSessionFromID(sid, Enum.DamageMeterType.Interrupts)
                    if sess and sess.combatSources then
                        mergeSources(sess.combatSources)
                    end
                end
            end
        end
    end

    -- Fallback: use Overall session when individual sessions are unavailable.
    if not hasIndividualSessions then
        if C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType then
            local overallSession = C_DamageMeter.GetCombatSessionFromType(
                Enum.DamageMeterSessionType.Overall,
                Enum.DamageMeterType.Interrupts
            )
            if overallSession and overallSession.combatSources then
                mergeSources(overallSession.combatSources)
            end
        end
        -- Last resort: single most-recent session ID.
        if not next(interruptData) then
            if self:EnsureSessionID() and type(self.CurrentSessionID) == "number" then
                local sess = C_DamageMeter.GetCombatSessionFromID(
                    self.CurrentSessionID,
                    Enum.DamageMeterType.Interrupts
                )
                if sess and sess.combatSources then
                    mergeSources(sess.combatSources)
                end
            end
        end
    end

    return interruptData
end

function DamageMeterCompat:GetDispelData()
    -- Get dispel data from C_DamageMeter API (WoW 12.0+ Dispels metric if available).
    -- Falls back to nil when the metric type does not exist; CombatLog SPELL_DISPEL tracking
    -- is the primary source in that case.
    if not self.IsWoW12Plus then
        return nil
    end

    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end

    -- Enum.DamageMeterType.Dispels may not exist on all builds; guard with pcall-style check.
    local dispelType = Enum and Enum.DamageMeterType and Enum.DamageMeterType.Dispels
    if not dispelType then
        return nil
    end

    local dispelSession
    if C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum.DamageMeterSessionType then
        dispelSession = C_DamageMeter.GetCombatSessionFromType(
            Enum.DamageMeterSessionType.Overall,
            dispelType
        )
    end

    if not dispelSession or not dispelSession.combatSources then
        if not self:EnsureSessionID() then return nil end
        if type(self.CurrentSessionID) ~= "number" then return nil end
        dispelSession = C_DamageMeter.GetCombatSessionFromID(self.CurrentSessionID, dispelType)
    end

    if not dispelSession or not dispelSession.combatSources then
        return nil
    end

    local dispelData = {}
    for _, source in ipairs(dispelSession.combatSources) do
        if source.name then
            local plainName = ToPlainString(source.name)
            local existing = SafeMapGet(dispelData, plainName)
            if existing then
                existing.dispels = (existing.dispels or 0) + (source.totalAmount or 0)
            else
                SafeMapSet(dispelData, plainName, {
                    dispels = source.totalAmount,
                    class = source.classFilename,
                    guid = source.sourceGUID,
                    sourceGUID = source.sourceGUID,
                })
            end
        end
    end
    return dispelData
end

function DamageMeterCompat:GetDeathsData()
    -- Get deaths data from C_DamageMeter API
    if not self.IsWoW12Plus then
        return nil
    end

    local deathsData = {}

    -- Check for restrictions
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end

    local deathsSession
    if C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType then
        -- Try common enum names for deaths metric
        if Enum.DamageMeterType.Deaths then
            deathsSession = C_DamageMeter.GetCombatSessionFromType(
                Enum.DamageMeterSessionType.Overall,
                Enum.DamageMeterType.Deaths
            )
        elseif Enum.DamageMeterType.PlayerDeaths then
            deathsSession = C_DamageMeter.GetCombatSessionFromType(
                Enum.DamageMeterSessionType.Overall,
                Enum.DamageMeterType.PlayerDeaths
            )
        end
    end

    if (not deathsSession or not deathsSession.combatSources) then
        if not self:EnsureSessionID() then
            return nil
        end
        if type(self.CurrentSessionID) ~= "number" then
            return nil
        end
        -- Try to get from session ID
        if Enum.DamageMeterType.Deaths then
            deathsSession = C_DamageMeter.GetCombatSessionFromID(
                self.CurrentSessionID,
                Enum.DamageMeterType.Deaths
            )
        elseif Enum.DamageMeterType.PlayerDeaths then
            deathsSession = C_DamageMeter.GetCombatSessionFromID(
                self.CurrentSessionID,
                Enum.DamageMeterType.PlayerDeaths
            )
        end
    end
    
    if deathsSession and deathsSession.combatSources then
        for _, source in ipairs(deathsSession.combatSources) do
            if source.name and source.sourceGUID then
                local plainName = ToPlainString(source.name)
                local existing = SafeMapGet(deathsData, plainName)
                local deathValue = ExtractDeathCountWithFallback(source)
                SafeMapSet(deathsData, plainName, {
                    deaths = ((existing and existing.deaths) or 0) + (deathValue or 0),
                    class = source.classFilename or (existing and existing.class),
                    guid = source.sourceGUID,
                    sourceGUID = source.sourceGUID,
                })
            end
        end
    end
    
    return deathsData
end

function DamageMeterCompat:GetDeathCountForSourceGUID(sourceGUID, sessionID)
    if not self.IsWoW12Plus then
        return nil
    end
    if type(sourceGUID) ~= "string" or sourceGUID == "" then
        return nil
    end
    if not Enum or not Enum.DamageMeterType or not Enum.DamageMeterType.Deaths then
        return nil
    end
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end

    local maxDeaths = nil

    if C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType and Enum.DamageMeterSessionType then
        local sessionTypes = {
            Enum.DamageMeterSessionType.Overall,
            Enum.DamageMeterSessionType.Current,
            Enum.DamageMeterSessionType.Expired,
        }
        for _, sessionType in ipairs(sessionTypes) do
            if sessionType ~= nil then
                local source = C_DamageMeter.GetCombatSessionSourceFromType(
                    sessionType,
                    Enum.DamageMeterType.Deaths,
                    sourceGUID
                )
                if source then
                    local value = ExtractDeathCountWithFallback(source)
                    if value and value >= 0 then
                        maxDeaths = (maxDeaths == nil) and value or math.max(maxDeaths, value)
                    end
                end

                if C_DamageMeter.GetCombatSessionFromType then
                    local session = C_DamageMeter.GetCombatSessionFromType(sessionType, Enum.DamageMeterType.Deaths)
                    local aggregated = AggregateDeathsBySource(session, sourceGUID)
                    if aggregated and aggregated >= 0 then
                        maxDeaths = (maxDeaths == nil) and aggregated or math.max(maxDeaths, aggregated)
                    end
                end
            end
        end
    end

    if C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromID then
        local targetSessionID = NormalizeSessionID(sessionID)
        if not targetSessionID then
            self:EnsureSessionID()
            targetSessionID = NormalizeSessionID(self.CurrentSessionID)
        end
        if type(targetSessionID) == "number" then
            local source = C_DamageMeter.GetCombatSessionSourceFromID(
                targetSessionID,
                Enum.DamageMeterType.Deaths,
                sourceGUID
            )
            if source then
                local value = ExtractDeathCountWithFallback(source)
                if value and value >= 0 then
                    maxDeaths = (maxDeaths == nil) and value or math.max(maxDeaths, value)
                end
            end

            if C_DamageMeter.GetCombatSessionFromID then
                local session = C_DamageMeter.GetCombatSessionFromID(targetSessionID, Enum.DamageMeterType.Deaths)
                local aggregated = AggregateDeathsBySource(session, sourceGUID)
                if aggregated and aggregated >= 0 then
                    maxDeaths = (maxDeaths == nil) and aggregated or math.max(maxDeaths, aggregated)
                end
            end
        end
    end

    if maxDeaths == nil then
        return nil
    end

    return maxDeaths
end

function DamageMeterCompat:GetAvoidableDamageData()
    -- Get avoidable damage taken from C_DamageMeter API
    if not self.IsWoW12Plus then
        return nil
    end

    local avoidableData = {}

    -- Check for restrictions
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end

    local avoidableSession
    if C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterSessionType then
        -- Try common enum names for avoidable damage metric
        if Enum.DamageMeterType.AvoidableDamageTaken then
            avoidableSession = C_DamageMeter.GetCombatSessionFromType(
                Enum.DamageMeterSessionType.Overall,
                Enum.DamageMeterType.AvoidableDamageTaken
            )
        elseif Enum.DamageMeterType.DamageTaken then
            avoidableSession = C_DamageMeter.GetCombatSessionFromType(
                Enum.DamageMeterSessionType.Overall,
                Enum.DamageMeterType.DamageTaken
            )
        end
    end

    if (not avoidableSession or not avoidableSession.combatSources) then
        if not self:EnsureSessionID() then
            return nil
        end
        if type(self.CurrentSessionID) ~= "number" then
            return nil
        end
        -- Try to get from session ID
        if Enum.DamageMeterType.AvoidableDamageTaken then
            avoidableSession = C_DamageMeter.GetCombatSessionFromID(
                self.CurrentSessionID,
                Enum.DamageMeterType.AvoidableDamageTaken
            )
        elseif Enum.DamageMeterType.DamageTaken then
            avoidableSession = C_DamageMeter.GetCombatSessionFromID(
                self.CurrentSessionID,
                Enum.DamageMeterType.DamageTaken
            )
        end
    end
    
    if avoidableSession and avoidableSession.combatSources then
        for _, source in ipairs(avoidableSession.combatSources) do
            if source.name and source.sourceGUID then
                local plainName = ToPlainString(source.name)
                SafeMapSet(avoidableData, plainName, {
                    avoidableDamageTaken = source.totalAmount or 0,
                    class = source.classFilename,
                    guid = source.sourceGUID,
                    sourceGUID = source.sourceGUID,
                })
            end
        end
    end
    
    return avoidableData
end

function DamageMeterCompat:GetAvailableSessions()
    -- Get list of available combat sessions
    if not self.IsWoW12Plus then
        return {}
    end
    
    return C_DamageMeter.GetAvailableCombatSessions() or {}
end

-- Returns data for every session currently tracked by C_DamageMeter, including per-player
-- amountPerSecond (true session DPS/HPS) and totalAmount.  Only works on WoW 12.0+.
-- Returns an array ordered by ascending sessionID:
--   { { sessionID, name, durationSeconds, players = { [rawPlayerName] = { dps, hps, damage, healing } } }, ... }
function DamageMeterCompat:GetAllSessionsWithStats()
    if not self.IsWoW12Plus or not C_DamageMeter then return nil end
    if not C_DamageMeter.GetAvailableCombatSessions then return nil end

    -- Combat-restriction check: read is blocked while in combat on WoW 12.0+.
    if Enum and Enum.AddOnRestrictionType and Enum.AddOnRestrictionType.Combat then
        if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then return nil end
    end

    local rawSessions = C_DamageMeter.GetAvailableCombatSessions()
    if not rawSessions or #rawSessions == 0 then return nil end

    -- Sort by sessionID ascending so callers can rely on ordering.
    local sorted = {}
    for _, s in ipairs(rawSessions) do
        local id = NormalizeSessionID(s.sessionID)
        if id then
            table.insert(sorted, { sessionID = id, name = s.name, durationSeconds = s.durationSeconds })
        end
    end
    if #sorted == 0 then return nil end
    table.sort(sorted, function(a, b) return a.sessionID < b.sessionID end)

    local result = {}
    for _, info in ipairs(sorted) do
        local sid = info.sessionID
        local players = {}

        -- Damage done for this session
        if C_DamageMeter.GetCombatSessionFromID and Enum and Enum.DamageMeterType then
            local dmgSession = C_DamageMeter.GetCombatSessionFromID(sid, Enum.DamageMeterType.DamageDone)
            if dmgSession and dmgSession.combatSources then
                for _, src in ipairs(dmgSession.combatSources) do
                    if src.name then
                        local plainName = ToPlainString(src.name)
                        if SafeNonEmpty(plainName) then
                            local entry = SafeMapGet(players, plainName)
                            if not entry then
                                entry = {}
                                SafeMapSet(players, plainName, entry)
                            end
                            if entry then
                                entry.dps    = src.amountPerSecond or 0
                                entry.damage = src.totalAmount     or 0
                            end
                        end
                    end
                end
            end

            -- Healing done for this session
            local healSession = C_DamageMeter.GetCombatSessionFromID(sid, Enum.DamageMeterType.HealingDone)
            if healSession and healSession.combatSources then
                for _, src in ipairs(healSession.combatSources) do
                    if src.name then
                        local plainName = ToPlainString(src.name)
                        if SafeNonEmpty(plainName) then
                            local entry = SafeMapGet(players, plainName)
                            if not entry then
                                entry = {}
                                SafeMapSet(players, plainName, entry)
                            end
                            if entry then
                                entry.hps     = src.amountPerSecond or 0
                                entry.healing = src.totalAmount     or 0
                            end
                        end
                    end
                end
            end
        end

        table.insert(result, {
            sessionID       = sid,
            name            = info.name,
            durationSeconds = info.durationSeconds,
            players         = players,
        })
    end

    return result
end

function DamageMeterCompat:GetSessionInfo(sessionID)
    -- Get complete info for a specific session
    if not self.IsWoW12Plus then
        return nil
    end
    
    local damageDone = C_DamageMeter.GetCombatSessionFromID(sessionID, Enum.DamageMeterType.DamageDone)
    local healing = C_DamageMeter.GetCombatSessionFromID(sessionID, Enum.DamageMeterType.HealingDone)
    local interrupts = C_DamageMeter.GetCombatSessionFromID(sessionID, Enum.DamageMeterType.Interrupts)
    
    return {
        sessionID = sessionID,
        damage = damageDone,
        healing = healing,
        interrupts = interrupts,
    }
end

-- Fallback for combat log parsing (pre-12.0)
function DamageMeterCompat:IsUsingCombatLogFallback()
    return self.UsesCombatLog
end

