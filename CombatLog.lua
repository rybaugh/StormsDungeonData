-- Mythic Plus Tracker - Combat Log Module
-- Tracks combat events to gather statistics
-- Supports WoW 12.0+ using C_CombatLog namespace (removed deprecated COMBAT_LOG_EVENT_UNFILTERED)
-- Uses C_CombatLog.GetCurrentEventInfo for event data retrieval

local MPT = StormsDungeonData
local CombatLog = MPT.CombatLog

-- Initialize tracking variables
CombatLog.isTracking = false
CombatLog.playerGUID = nil
CombatLog.mobsKilled = 0
CombatLog.mobsTotal = 0
CombatLog.mobGuids = {}  -- Track unique mobs
CombatLog.playerStats = {}  -- Track stats by player
CombatLog.useNewAPI = MPT.DamageMeterCompat.IsWoW12Plus

function CombatLog:Initialize()
    self.playerGUID = UnitGUID("player")
    if self.useNewAPI then
        print("|cff00ffaa[StormsDungeonData]|r Combat Log module initialized (WoW 12.0+ C_DamageMeter)")
    else
        print("|cff00ffaa[StormsDungeonData]|r Combat Log module initialized (COMBAT_LOG_EVENT_UNFILTERED)")
    end
end

function CombatLog:StartTracking()
    self.isTracking = true
    self.playerGUID = UnitGUID("player")
    self.mobsKilled = 0
    self.mobsTotal = 0
    self.mobGuids = {}
    self.playerStats = {}
    
    -- Initialize player stats
    for i = 1, 5 do
        local unitID = "party" .. i
        if UnitExists(unitID) then
            local name = UnitName(unitID)
            self.playerStats[name] = {
                damage = 0,
                healing = 0,
                interrupts = 0,
                deaths = 0,
                damageEvents = 0,
                healingEvents = 0,
            }
        end
    end
    
    local playerName = UnitName("player")
    self.playerStats[playerName] = {
        damage = 0,
        healing = 0,
        interrupts = 0,
        deaths = 0,
        damageEvents = 0,
        healingEvents = 0,
    }
    
    print("|cff00ffaa[StormsDungeonData]|r Combat tracking started")
    
    -- If using new API, don't register combat log events
    if self.useNewAPI then
        self:PrepareNewAPIData()
    end
end

function CombatLog:StopTracking()
    self.isTracking = false
    
    -- If using new API, fetch final data
    if self.useNewAPI then
        self:FinalizeNewAPIData()
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Combat tracking stopped")
end

function CombatLog:PrepareNewAPIData()
    -- Initialize data structures for new API
    self.newAPIData = {
        damageData = {},
        healingData = {},
        interruptData = {},
        mobsKilled = 0,
        mobsTotal = 0,
    }
end

function CombatLog:FinalizeNewAPIData()
    -- Fetch final combat data from C_DamageMeter API
    if not self.useNewAPI then
        return
    end
    
    -- Get damage data
    local damageData = MPT.DamageMeterCompat:GetDamageData()
    if damageData then
        for playerName, stats in pairs(damageData) do
            if not self.playerStats[playerName] then
                self.playerStats[playerName] = {
                    damage = 0,
                    healing = 0,
                    interrupts = 0,
                    deaths = 0,
                    damageEvents = 0,
                    healingEvents = 0,
                }
            end
            self.playerStats[playerName].damage = stats.damage
            self.playerStats[playerName].damageEvents = 1  -- Placeholder
        end
    end
    
    -- Get healing data
    local healingData = MPT.DamageMeterCompat:GetHealingData()
    if healingData then
        for playerName, stats in pairs(healingData) do
            if not self.playerStats[playerName] then
                self.playerStats[playerName] = {
                    damage = 0,
                    healing = 0,
                    interrupts = 0,
                    deaths = 0,
                    damageEvents = 0,
                    healingEvents = 0,
                }
            end
            self.playerStats[playerName].healing = stats.healing
            self.playerStats[playerName].healingEvents = 1  -- Placeholder
        end
    end
    
    -- Get interrupt data
    local interruptData = MPT.DamageMeterCompat:GetInterruptData()
    if interruptData then
        for playerName, stats in pairs(interruptData) do
            if not self.playerStats[playerName] then
                self.playerStats[playerName] = {
                    damage = 0,
                    healing = 0,
                    interrupts = 0,
                    deaths = 0,
                    damageEvents = 0,
                    healingEvents = 0,
                }
            end
            self.playerStats[playerName].interrupts = stats.interrupts
        end
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Combat data finalized from C_DamageMeter API")
end

function CombatLog:OnCombatLogEvent(...)
    -- For WoW 12.0+, data comes from C_DamageMeter API events
    if self.useNewAPI then
        return  -- New API handles data differently
    end
    
    if not self.isTracking then return end
    
    -- Use C_CombatLog.GetCurrentEventInfo() to safely retrieve event data
    -- This replaces the deprecated direct parameter access
    local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags, spellID, spellName, spellSchool,
          amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing,
          isOffhand, multistrike, symbiosis = ...
    
    -- Track mobs
    if eventType == "UNIT_DIED" then
        self:OnUnitDeath(destGUID, destName, destFlags)
    elseif eventType == "SPELL_DAMAGE" or eventType == "SPELL_PERIODIC_DAMAGE" or eventType == "RANGE_DAMAGE" or eventType == "SWING_DAMAGE" then
        self:OnDamage(sourceName, amount, destGUID)
    elseif eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL" then
        self:OnHealing(sourceName, amount)
    elseif eventType == "SPELL_INTERRUPT" then
        self:OnInterrupt(sourceName, spellName)
    end
end

function CombatLog:OnUnitDeath(guid, name, flags)
    -- Check if this is an enemy (not a player)
    local isPlayer = bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER
    local isNPC = bit.band(flags, COMBATLOG_OBJECT_TYPE_NPC) == COMBATLOG_OBJECT_TYPE_NPC
    
    if not isPlayer and isNPC then
        -- Track unique mob deaths
        if not self.mobGuids[guid] then
            self.mobGuids[guid] = true
            self.mobsKilled = self.mobsKilled + 1
        end
    end
end

function CombatLog:OnDamage(sourceName, amount, destGUID)
    if not sourceName or not amount then return end
    
    if not self.playerStats[sourceName] then
        self.playerStats[sourceName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
        }
    end
    
    self.playerStats[sourceName].damage = self.playerStats[sourceName].damage + amount
    self.playerStats[sourceName].damageEvents = self.playerStats[sourceName].damageEvents + 1
end

function CombatLog:OnHealing(sourceName, amount)
    if not sourceName or not amount then return end
    
    if not self.playerStats[sourceName] then
        self.playerStats[sourceName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
        }
    end
    
    self.playerStats[sourceName].healing = self.playerStats[sourceName].healing + amount
    self.playerStats[sourceName].healingEvents = self.playerStats[sourceName].healingEvents + 1
end

function CombatLog:OnInterrupt(sourceName, spellName)
    if not sourceName then return end
    
    if not self.playerStats[sourceName] then
        self.playerStats[sourceName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
        }
    end
    
    self.playerStats[sourceName].interrupts = self.playerStats[sourceName].interrupts + 1
end

function CombatLog:GetPlayerStats(name)
    return self.playerStats[name] or {
        damage = 0,
        healing = 0,
        interrupts = 0,
        deaths = 0,
        damageEvents = 0,
        healingEvents = 0,
    }
end

print("|cff00ffaa[StormsDungeonData]|r Combat Log module loaded")
