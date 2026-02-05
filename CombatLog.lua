-- Mythic Plus Tracker - Combat Log Module
-- Tracks combat events to gather statistics
-- Supports WoW 12.0+ using C_CombatLog namespace (removed deprecated COMBAT_LOG_EVENT_UNFILTERED)
-- Uses C_CombatLog.GetCurrentEventInfo for event data retrieval

local MPT = StormsDungeonData
local CombatLog = MPT.CombatLog

local function NormalizeUnitName(name)
    if type(name) ~= "string" then
        return nil
    end
    -- Strip realm suffix if present (e.g. Name-Realm)
    local short = name:match("^([^%-]+)%-")
    return short or name
end

-- Initialize tracking variables
CombatLog.isTracking = false
CombatLog.playerGUID = nil
CombatLog.mobsKilled = 0
CombatLog.mobsTotal = 0
CombatLog.mobGuids = {}  -- Track unique mobs
CombatLog.playerStats = {}  -- Track stats by player
CombatLog.useNewAPI = MPT.DamageMeterCompat.IsWoW12Plus
CombatLog.allowCLEUFallback = true
CombatLog.playerGUIDToName = {}
CombatLog.petOwnerNameByGUID = {}

local function GetCombatLogEventInfo()
    if CombatLogGetCurrentEventInfo then
        return CombatLogGetCurrentEventInfo()
    end
    if C_CombatLog and C_CombatLog.GetCurrentEventInfo then
        return C_CombatLog.GetCurrentEventInfo()
    end
end

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
    self.startTime = time()
    self.playerGUID = UnitGUID("player")
    self.mobsKilled = 0
    self.mobsTotal = 0
    self.mobGuids = {}
    self.playerStats = {}
    self.playerGUIDToName = {}
    self.petOwnerNameByGUID = {}
    
    -- Initialize player stats
    for i = 1, 5 do
        local unitID = "party" .. i
        if UnitExists(unitID) then
            local name = UnitName(unitID)
            local shortName = NormalizeUnitName(name) or name
            local guid = UnitGUID(unitID)
            if guid and name then
                self.playerGUIDToName[guid] = shortName
            end
            self.playerStats[shortName] = {
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
    local playerShortName = NormalizeUnitName(playerName) or playerName
    local playerGUID = UnitGUID("player")
    if playerGUID and playerShortName then
        self.playerGUIDToName[playerGUID] = playerShortName
    end
    self.playerStats[playerShortName] = {
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
    self.startTime = nil
    
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
    if damageData and not next(damageData) then
        damageData = nil
    end
    if damageData then
        for playerName, stats in pairs(damageData) do
            local shortName = NormalizeUnitName(playerName) or playerName
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

            if shortName ~= playerName then
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                    }
                end
                self.playerStats[shortName].damage = stats.damage
                self.playerStats[shortName].damageEvents = 1
            end
        end
    end
    
    -- Get healing data
    local healingData = MPT.DamageMeterCompat:GetHealingData()
    if healingData and not next(healingData) then
        healingData = nil
    end
    if healingData then
        for playerName, stats in pairs(healingData) do
            local shortName = NormalizeUnitName(playerName) or playerName
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

            if shortName ~= playerName then
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                    }
                end
                self.playerStats[shortName].healing = stats.healing
                self.playerStats[shortName].healingEvents = 1
            end
        end
    end
    
    -- Get interrupt data
    local interruptData = MPT.DamageMeterCompat:GetInterruptData()
    if interruptData and not next(interruptData) then
        interruptData = nil
    end
    if interruptData then
        for playerName, stats in pairs(interruptData) do
            local shortName = NormalizeUnitName(playerName) or playerName
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

            if shortName ~= playerName then
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                    }
                end
                self.playerStats[shortName].interrupts = stats.interrupts
            end
        end
    end

    if not damageData and not healingData and not interruptData then
        print("|cff00ffaa[StormsDungeonData]|r Warning: No C_DamageMeter data available (restricted or no session)")
    else
        print("|cff00ffaa[StormsDungeonData]|r Combat data finalized from C_DamageMeter API")
    end
end

function CombatLog:OnCombatLogEvent(...)
    if not self.isTracking then return end

    local eventInfo = { GetCombatLogEventInfo() }
    local eventType = eventInfo[2]
    if not eventType then
        return
    end

    local sourceGUID = eventInfo[4]
    local sourceName = eventInfo[5]
    local destGUID = eventInfo[8]
    local destName = eventInfo[9]
    local destFlags = eventInfo[10]

    -- Track pet ownership so pet damage/healing is credited to the owner (Details-style)
    if eventType == "SPELL_SUMMON" and sourceName and destGUID then
        self.petOwnerNameByGUID[destGUID] = NormalizeUnitName(sourceName) or sourceName
        return
    end

    -- Track deaths and unique mob kills (needed in all versions)
    if eventType == "UNIT_DIED" or eventType == "UNIT_DESTROYED" then
        self:OnUnitDeath(destGUID, destName, destFlags)
        return
    end

    -- WoW 12.0+ prefers C_DamageMeter for totals, but keep CLEU as a fallback.
    if self.useNewAPI and not self.allowCLEUFallback then
        return
    end

    -- Credit pet events to owner when possible
    if sourceGUID and self.petOwnerNameByGUID[sourceGUID] then
        sourceName = self.petOwnerNameByGUID[sourceGUID]
    elseif (not sourceName or sourceName == "") and sourceGUID and self.playerGUIDToName[sourceGUID] then
        sourceName = self.playerGUIDToName[sourceGUID]
    end

    if eventType == "SWING_DAMAGE" then
        local amount = eventInfo[12]
        self:OnDamage(sourceName, amount)
    elseif eventType == "SPELL_DAMAGE" or eventType == "SPELL_PERIODIC_DAMAGE" or eventType == "RANGE_DAMAGE" then
        local amount = eventInfo[15]
        self:OnDamage(sourceName, amount)
    elseif eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL" then
        local amount = eventInfo[15]
        self:OnHealing(sourceName, amount)
    elseif eventType == "SPELL_INTERRUPT" then
        self:OnInterrupt(sourceName)
    end
end

function CombatLog:OnUnitDeath(guid, name, flags)
    if not guid then
        return
    end

    if not name then
        name = self.playerGUIDToName[guid]
    end
    name = NormalizeUnitName(name) or name

    -- Track player deaths
    local isPlayer = flags and (bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER)
    if isPlayer and name then
        if not self.playerStats[name] then
            self.playerStats[name] = {
                damage = 0,
                healing = 0,
                interrupts = 0,
                deaths = 0,
                damageEvents = 0,
                healingEvents = 0,
            }
        end
        self.playerStats[name].deaths = (self.playerStats[name].deaths or 0) + 1
        return
    end

    -- Check if this is an enemy (not a player)
    local isNPC = flags and (bit.band(flags, COMBATLOG_OBJECT_TYPE_NPC) == COMBATLOG_OBJECT_TYPE_NPC)
    
    if not isPlayer and isNPC then
        -- Track unique mob deaths
        if not self.mobGuids[guid] then
            self.mobGuids[guid] = true
            self.mobsKilled = self.mobsKilled + 1
        end
    end
end

function CombatLog:OnDamage(sourceName, amount)
    if not sourceName or not amount then return end

    sourceName = NormalizeUnitName(sourceName) or sourceName
    
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

    sourceName = NormalizeUnitName(sourceName) or sourceName
    
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

function CombatLog:OnInterrupt(sourceName)
    if not sourceName then return end

    sourceName = NormalizeUnitName(sourceName) or sourceName
    
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
    if name and self.playerStats[name] then
        return self.playerStats[name]
    end

    local shortName = NormalizeUnitName(name)
    if shortName and self.playerStats[shortName] then
        return self.playerStats[shortName]
    end

    return {
        damage = 0,
        healing = 0,
        interrupts = 0,
        deaths = 0,
        damageEvents = 0,
        healingEvents = 0,
    }
end

print("|cff00ffaa[StormsDungeonData]|r Combat Log module loaded")
