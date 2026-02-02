-- Mythic Plus Tracker - Damage Meter Compatibility Layer
-- Handles WoW 12.0+ C_DamageMeter API with fallback to legacy combat log
-- WoW 12.0+: Uses C_DamageMeter for session data and C_CombatLog namespace for event info
-- Pre-12.0: Uses COMBAT_LOG_EVENT_UNFILTERED with C_CombatLog deprecation shims
-- Based on Details addon approach for maximum compatibility

local MPT = StormsDungeonData
local DamageMeterCompat = {}
MPT.DamageMeterCompat = DamageMeterCompat

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

function DamageMeterCompat:Initialize()
    print("|cff00ffaa[StormsDungeonData]|r Damage Meter Compat initialized")
    print("|cff00ffaa[StormsDungeonData]|r Using " .. (self.IsWoW12Plus and "C_DamageMeter API (WoW 12.0+)" or "COMBAT_LOG_EVENT_UNFILTERED"))
    
    if self.IsWoW12Plus then
        self:InitializeDamageMeterAPI()
    end
end

function DamageMeterCompat:InitializeDamageMeterAPI()
    -- Register for damage meter session updates
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("COMBAT_METRICS_SESSION_NEW")
    frame:RegisterEvent("COMBAT_METRICS_SESSION_UPDATED")
    frame:RegisterEvent("COMBAT_METRICS_SESSION_END")
    
    frame:SetScript("OnEvent", function(self, event, ...)
        DamageMeterCompat:OnDamageMeterEvent(event, ...)
    end)
    
    self.MetricsFrame = frame
    print("|cff00ffaa[StormsDungeonData]|r C_DamageMeter events registered")
end

function DamageMeterCompat:OnDamageMeterEvent(event, ...)
    if event == "COMBAT_METRICS_SESSION_NEW" then
        -- New combat session started
        local sessionID = ...
        self.CurrentSessionID = sessionID
        self.SessionData[sessionID] = {
            startTime = GetTime(),
            damageByPlayer = {},
            healingByPlayer = {},
            interruptsByPlayer = {},
        }
        print("|cff00ffaa[StormsDungeonData]|r New damage meter session: " .. sessionID)
        
    elseif event == "COMBAT_METRICS_SESSION_UPDATED" then
        -- Combat session data updated
        local sessionID = ...
        -- Data is available via C_DamageMeter API
        
    elseif event == "COMBAT_METRICS_SESSION_END" then
        -- Combat session ended
        local sessionID = ...
        if self.SessionData[sessionID] then
            self.SessionData[sessionID].endTime = GetTime()
        end
        print("|cff00ffaa[StormsDungeonData]|r Damage meter session ended: " .. sessionID)
    end
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
    if not self.IsWoW12Plus or not self.CurrentSessionID then
        return nil
    end
    
    local damageData = {}
    
    -- Check for restrictions before proceeding
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        print("|cff00ffaa[StormsDungeonData]|r Warning: Combat data restricted by Blizzard")
        return nil
    end
    
    -- Get damage done session
    local damageDoneSession = C_DamageMeter.GetCombatSessionFromID(
        self.CurrentSessionID,
        Enum.DamageMeterType.DamageDone
    )
    
    if damageDoneSession and damageDoneSession.combatSources then
        for _, source in ipairs(damageDoneSession.combatSources) do
            if source.name and source.sourceGUID then
                damageData[source.name] = {
                    damage = source.totalAmount,
                    dps = source.amountPerSecond,
                    class = source.classFilename,
                    specIcon = source.specIconID,
                }
            end
        end
    end
    
    return damageData
end

function DamageMeterCompat:GetHealingData()
    -- Get healing data from C_DamageMeter API
    if not self.IsWoW12Plus or not self.CurrentSessionID then
        return nil
    end
    
    local healingData = {}
    
    -- Check for restrictions
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end
    
    -- Get healing done session
    local healingDoneSession = C_DamageMeter.GetCombatSessionFromID(
        self.CurrentSessionID,
        Enum.DamageMeterType.HealingDone
    )
    
    if healingDoneSession and healingDoneSession.combatSources then
        for _, source in ipairs(healingDoneSession.combatSources) do
            if source.name and source.sourceGUID then
                healingData[source.name] = {
                    healing = source.totalAmount,
                    hps = source.amountPerSecond,
                    class = source.classFilename,
                    specIcon = source.specIconID,
                }
            end
        end
    end
    
    return healingData
end

function DamageMeterCompat:GetInterruptData()
    -- Get interrupt data from C_DamageMeter API
    if not self.IsWoW12Plus or not self.CurrentSessionID then
        return nil
    end
    
    local interruptData = {}
    
    -- Check for restrictions
    if self:IsRestricted(Enum.AddOnRestrictionType.Combat) then
        return nil
    end
    
    -- Get interrupts session
    local interruptsSession = C_DamageMeter.GetCombatSessionFromID(
        self.CurrentSessionID,
        Enum.DamageMeterType.Interrupts
    )
    
    if interruptsSession and interruptsSession.combatSources then
        for _, source in ipairs(interruptsSession.combatSources) do
            if source.name and source.sourceGUID then
                interruptData[source.name] = {
                    interrupts = source.totalAmount,
                    class = source.classFilename,
                }
            end
        end
    end
    
    return interruptData
end

function DamageMeterCompat:GetAvailableSessions()
    -- Get list of available combat sessions
    if not self.IsWoW12Plus then
        return {}
    end
    
    return C_DamageMeter.GetAvailableCombatSessions() or {}
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

print("|cff00ffaa[StormsDungeonData]|r Damage Meter Compat module loaded")
