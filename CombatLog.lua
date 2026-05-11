-- Mythic Plus Tracker - Combat Log Module
-- Tracks combat events to gather statistics
-- Supports WoW 12.0+ using C_CombatLog namespace (removed deprecated COMBAT_LOG_EVENT_UNFILTERED)
-- Uses C_CombatLog.GetCurrentEventInfo for event data retrieval

local MPT = StormsDungeonData
local CombatLog = MPT.CombatLog

local function L(level, msg)
    if MPT.Log then MPT.Log:Log(level or "INFO", msg) end
end

local function ToPlainString(value)
    if value == nil then
        return nil
    end
    return tostring(value)
end

local function ToTableKey(value)
    local plain = ToPlainString(value)
    return plain
end

local function SafeMapSet(map, key, value)
    if type(map) ~= "table" or key == nil then
        return false
    end
    local ok = pcall(function()
        map[key] = value
    end)
    return ok
end

local function SafeMapGet(map, key)
    if type(map) ~= "table" or key == nil then
        return nil
    end
    local ok, value = pcall(function()
        return map[key]
    end)
    if not ok then
        return nil
    end
    return value
end

local function NormalizeUnitName(name)
    name = ToPlainString(name)
    if not name then
        return nil
    end
    -- Check if name has a realm suffix (e.g., "Name-Realm" or "Name-Realm-US")
    -- If no realm suffix, it's likely a pet - return nil to ignore it
    -- Must have at least one hyphen to be a player name
    local hyphenCount = select(2, name:gsub("%-", ""))
    if hyphenCount == 0 then
        -- No realm suffix = pet name, ignore it
        return nil
    end
    -- Strip realm suffix if present (e.g. Name-Realm -> Name or Name-Realm-US -> Name)
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
CombatLog.petOwnerNameByGUID = {}  -- [petGUID] = ownerFullName
CombatLog.petOwnerByPetName = {}   -- [petDisplayName] = ownerFullName  (GUID-less fallback)
CombatLog.activeRoster = {}  -- Short names seen at run start/current run
CombatLog.fullNameByShort = {}  -- [shortName] = Name-Realm observed from party roster
CombatLog.latestValidatedPlayers = nil  -- Snapshot of most recently completed run

local function HasCombatActivity(stats)
    return (stats.damage and stats.damage > 0)
        or (stats.healing and stats.healing > 0)
        or (stats.interrupts and stats.interrupts > 0)
        or (stats.dispels and stats.dispels > 0)
        or (stats.damageEvents and stats.damageEvents > 0)
        or (stats.healingEvents and stats.healingEvents > 0)
        or (stats.deaths and stats.deaths > 0)
end

local function BuildValidatedPlayersSnapshot(playerStats, activeRoster, includeRoster)
    local validPlayers = {}

    if type(activeRoster) == "table" and includeRoster then
        for shortName, isInRoster in pairs(activeRoster) do
            if isInRoster and type(shortName) == "string" and shortName ~= "" then
                validPlayers[shortName] = true
            end
        end
    end

    if type(playerStats) == "table" then
        for name, stats in pairs(playerStats) do
            if type(name) == "string" and name ~= "" and type(stats) == "table" then
                local shortName = NormalizeUnitName(name) or name
                local inRoster = (type(activeRoster) ~= "table") or activeRoster[shortName]
                if inRoster and HasCombatActivity(stats) then
                    validPlayers[shortName] = true
                end
            end
        end
    end

    return validPlayers
end

local function AddCurrentGroupToRoster(self)
    if type(self.activeRoster) ~= "table" then
        self.activeRoster = {}
    end
    if type(self.playerGUIDToName) ~= "table" then
        self.playerGUIDToName = {}
    end
    if type(self.fullNameByShort) ~= "table" then
        self.fullNameByShort = {}
    end
    if type(self.playerStats) ~= "table" then
        self.playerStats = {}
    end

    for i = 1, 5 do
        local unitID = "party" .. i
        if UnitExists(unitID) then
            local rawName, rawRealm = UnitName(unitID)
            local name = ToPlainString(rawName)
            local realm = ToPlainString(rawRealm)
            if realm and realm ~= "" then
                name = name .. "-" .. realm
            end
            local shortName = NormalizeUnitName(name) or name
            local guid = ToTableKey(UnitGUID(unitID))
            if guid and shortName then
                SafeMapSet(self.playerGUIDToName, guid, name)
                self.activeRoster[shortName] = true
                self.fullNameByShort[shortName] = name
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        dispels = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                        avoidableDamageTaken = 0,
                    }
                end
            end
        end
    end

    local rawPlayerName, rawPlayerRealm = UnitName("player")
    local playerName = ToPlainString(rawPlayerName)
    local playerRealm = ToPlainString(rawPlayerRealm)
    if playerRealm and playerRealm ~= "" then
        playerName = playerName .. "-" .. playerRealm
    end
    local playerShortName = NormalizeUnitName(playerName) or playerName
    local playerGUID = ToTableKey(UnitGUID("player"))
    if playerGUID and playerShortName then
        SafeMapSet(self.playerGUIDToName, playerGUID, playerName)
        self.activeRoster[playerShortName] = true
        self.fullNameByShort[playerShortName] = playerName
        if not self.playerStats[playerShortName] then
            self.playerStats[playerShortName] = {
                damage = 0,
                healing = 0,
                interrupts = 0,
                dispels = 0,
                deaths = 0,
                damageEvents = 0,
                healingEvents = 0,
                avoidableDamageTaken = 0,
            }
        end
    end

    -- Pre-register pet GUIDs and pet names for all current party members and the player.
    -- This handles pets that were summoned before tracking started and ensures
    -- pet interrupts (e.g. warlock Felhunter) are credited to the owner even
    -- if we never saw the SPELL_SUMMON event during this session.
    -- petOwnerByPetName is a display-name keyed fallback for when C_DamageMeter does
    -- not expose a sourceGUID for pet combat sources (which it sometimes omits).
    if type(self.petOwnerNameByGUID) ~= "table" then
        self.petOwnerNameByGUID = {}
    end
    if type(self.petOwnerByPetName) ~= "table" then
        self.petOwnerByPetName = {}
    end
    local function RegisterPetIfPresent(ownerUnitID, petUnitID)
        if UnitExists(ownerUnitID) and UnitExists(petUnitID) then
            local petGUID = ToTableKey(UnitGUID(petUnitID))
            local petName = ToTableKey(UnitName(petUnitID))
            local rawOwnerName, rawOwnerRealm = UnitName(ownerUnitID)
            local ownerN = ToPlainString(rawOwnerName)
            local ownerR = ToPlainString(rawOwnerRealm)
            if ownerR and ownerR ~= "" then
                ownerN = ownerN .. "-" .. ownerR
            end
            if ownerN then
                if petGUID then
                    SafeMapSet(self.petOwnerNameByGUID, petGUID, ownerN)
                end
                -- Also index by display name so we can resolve even when
                -- C_DamageMeter omits sourceGUID for the pet combat source.
                if petName then
                    SafeMapSet(self.petOwnerByPetName, petName, ownerN)
                end
            end
        end
    end
    RegisterPetIfPresent("player", "pet")
    for i = 1, 5 do
        RegisterPetIfPresent("party" .. i, "party" .. i .. "pet")
    end
end

local function GetCombatLogEventInfo()
    if CombatLogGetCurrentEventInfo then
        return CombatLogGetCurrentEventInfo()
    end
    if C_CombatLog and C_CombatLog.GetCurrentEventInfo then
        return C_CombatLog.GetCurrentEventInfo()
    end
end

function CombatLog:Initialize()
    self.playerGUID = ToTableKey(UnitGUID("player"))
    if self.useNewAPI then
    else
    end
end

function CombatLog:StartTracking()
    L("INFO", "=== CombatLog:StartTracking() called ===")
    if self.isTracking then
        AddCurrentGroupToRoster(self)
        L("INFO", "Combat tracking already active, refreshed roster only")
        return
    end
    self.isTracking = true
    self.startTime = time()
    self.playerGUID = ToTableKey(UnitGUID("player"))
    self.mobsKilled = 0
    self.mobsTotal = 0
    self.mobGuids = {}
    self.playerStats = {}
    self.playerGUIDToName = {}
    self.petOwnerNameByGUID = {}
    self.petOwnerByPetName = {}
    self.activeRoster = {}
    self.fullNameByShort = {}
    self.latestValidatedPlayers = nil
    L("INFO", "Combat tracking initialized, isTracking=" .. tostring(self.isTracking))
    
    -- Initialize player stats/roster from current group members
    AddCurrentGroupToRoster(self)
    
    -- Debug: print initialized player names
    local trackedCount = 0
    local trackedNames = {}
    for name, _ in pairs(self.playerStats) do
        trackedCount = trackedCount + 1
        table.insert(trackedNames, name)
    end
    L("INFO", "Combat tracking started - tracking " .. trackedCount .. " players: " .. table.concat(trackedNames, ", "))
    
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

    -- Snapshot only the most recently completed run.
    self.latestValidatedPlayers = BuildValidatedPlayersSnapshot(self.playerStats, self.activeRoster, true)

    local snapshotCount = 0
    for _ in pairs(self.latestValidatedPlayers or {}) do
        snapshotCount = snapshotCount + 1
    end
    L("INFO", "Latest run player snapshot captured: " .. tostring(snapshotCount) .. " players")
    L("INFO", "Combat tracking stopped")
end

-- Get list of players who were actually in the M+ run based on combat activity
function CombatLog:GetValidatedPlayerNames()
    local validPlayers = {}

    if not self.isTracking and type(self.latestValidatedPlayers) == "table" and next(self.latestValidatedPlayers) then
        for name, value in pairs(self.latestValidatedPlayers) do
            if value then
                validPlayers[name] = true
            end
        end
    else
        validPlayers = BuildValidatedPlayersSnapshot(self.playerStats, self.activeRoster, false)
    end
    
    local count = 0
    for _ in pairs(validPlayers) do count = count + 1 end
    L("INFO", "Combat log tracked " .. count .. " players with activity")
    
    -- Return as a table for easy lookup
    return validPlayers
end

-- Check if a player was actually in the dungeon based on combat log
function CombatLog:IsValidPlayer(playerName)
    if not playerName or playerName == "" then
        return false
    end
    
    local normalizedName = NormalizeUnitName(playerName) or playerName
    local validPlayers = self:GetValidatedPlayerNames()
    
    return validPlayers[normalizedName] == true or validPlayers[playerName] == true
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
            if type(playerName) == "string" and playerName:find("%-") and shortName then
                self.fullNameByShort[shortName] = playerName
            end
            if shortName then
                if type(self.activeRoster) ~= "table" then
                    self.activeRoster = {}
                end
                self.activeRoster[shortName] = true
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        dispels = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                        avoidableDamageTaken = 0,
                    }
                end
                self.playerStats[shortName].damage = stats.damage
                self.playerStats[shortName].damageEvents = 1  -- Placeholder
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
            if type(playerName) == "string" and playerName:find("%-") and shortName then
                self.fullNameByShort[shortName] = playerName
            end
            if shortName then
                if type(self.activeRoster) ~= "table" then
                    self.activeRoster = {}
                end
                self.activeRoster[shortName] = true
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        dispels = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                        avoidableDamageTaken = 0,
                    }
                end
                self.playerStats[shortName].healing = stats.healing
                self.playerStats[shortName].healingEvents = 1  -- Placeholder
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
            local resolvedName = playerName
            local sourceGUID = type(stats) == "table" and (stats.sourceGUID or stats.guid) or nil

            -- Primary: resolve pet → owner via GUID map.
            -- Try the primary GUID and all additional GUIDs collected when the same
            -- pet name appeared multiple times (resummoned during the run).
            local ownerFromGuid = nil
            if self.petOwnerNameByGUID then
                local guidsToTry = {}
                if sourceGUID then guidsToTry[#guidsToTry + 1] = sourceGUID end
                if type(stats) == "table" and type(stats.allGUIDs) == "table" then
                    for g in pairs(stats.allGUIDs) do
                        if g ~= sourceGUID then guidsToTry[#guidsToTry + 1] = g end
                    end
                end
                for _, guid in ipairs(guidsToTry) do
                    local v = SafeMapGet(self.petOwnerNameByGUID, guid)
                    if v and v ~= "" then ownerFromGuid = v; break end
                end
            end
            if ownerFromGuid then
                resolvedName = ownerFromGuid
            elseif NormalizeUnitName(playerName) == nil and self.petOwnerByPetName and SafeMapGet(self.petOwnerByPetName, playerName) then
                -- Fallback: C_DamageMeter sometimes omits sourceGUID for pet sources
                -- (e.g., warlock Felhunter / Voidwalker).  When that happens the GUID
                -- map is unreachable, but we can still match by the pet's display name.
                resolvedName = SafeMapGet(self.petOwnerByPetName, playerName)
            end
            -- If the resolved name has no realm suffix, upgrade it from fullNameByShort.
            -- Without this, NormalizeUnitName silently drops pet interrupts when the owner
            -- was a same-realm player (CLEU omits the realm for same-server names).
            if NormalizeUnitName(resolvedName) == nil and resolvedName then
                local upgraded = self.fullNameByShort[resolvedName]
                if upgraded then resolvedName = upgraded end
            end

            local shortName = NormalizeUnitName(resolvedName) or resolvedName
            if type(resolvedName) == "string" and resolvedName:find("%-") and shortName then
                self.fullNameByShort[shortName] = resolvedName
            end
            if shortName then
                if type(self.activeRoster) ~= "table" then
                    self.activeRoster = {}
                end
                self.activeRoster[shortName] = true
                if not self.playerStats[shortName] then
                    self.playerStats[shortName] = {
                        damage = 0,
                        healing = 0,
                        interrupts = 0,
                        dispels = 0,
                        deaths = 0,
                        damageEvents = 0,
                        healingEvents = 0,
                        avoidableDamageTaken = 0,
                    }
                end
                self.playerStats[shortName].interrupts = (self.playerStats[shortName].interrupts or 0) + (stats.interrupts or 0)
            end
        end
    end

    if not damageData and not healingData and not interruptData then
        L("WARN", "No C_DamageMeter data available (restricted or no session)")
    else
        L("INFO", "Combat data finalized from C_DamageMeter API")
    end
end

function CombatLog:OnCombatLogEvent(...)
    if not self.isTracking then
        -- Uncomment to debug if events are coming in but tracking isn't active:
        -- print("|cffff4444[StormsDungeonData]|r OnCombatLogEvent called but isTracking=false")
        return
    end

    local eventInfo = { GetCombatLogEventInfo() }
    local eventType = eventInfo[2]
    if not eventType then
        return
    end

    local sourceGUID = ToTableKey(eventInfo[4])
    local sourceName = ToPlainString(eventInfo[5])
    local sourceFlags = eventInfo[6]
    local destGUID = ToTableKey(eventInfo[8])
    local destName = ToPlainString(eventInfo[9])
    local destFlags = eventInfo[10]

    if type(sourceName) == "string" and sourceName:find("%-") then
        local sourceShort = NormalizeUnitName(sourceName)
        if sourceShort then
            self.fullNameByShort[sourceShort] = sourceName
        end
    end
    if type(destName) == "string" and destName:find("%-") then
        local destShort = NormalizeUnitName(destName)
        if destShort then
            self.fullNameByShort[destShort] = destName
        end
    end

    -- Track pet ownership so pet damage/healing is credited to the owner
    if eventType == "SPELL_SUMMON" and sourceName and destGUID then
        -- Prefer the full (Name-Realm) name from our roster map if possible.
        -- The CLEU sourceName for same-realm players often omits the realm suffix,
        -- which would cause NormalizeUnitName to treat the owner name as a pet and discard it.
        local ownerName = (sourceGUID and SafeMapGet(self.playerGUIDToName, sourceGUID)) or sourceName
        -- Secondary upgrade: if still no realm suffix, check fullNameByShort
        if NormalizeUnitName(ownerName) == nil and ownerName then
            local upgraded = self.fullNameByShort[ownerName]
            if upgraded then ownerName = upgraded end
        end
        SafeMapSet(self.petOwnerNameByGUID, destGUID, ownerName)
        -- Also store by pet display name (destName). C_DamageMeter sometimes omits
        -- sourceGUID for pet combat sources, making the GUID map unreachable.  The
        -- name map provides a reliable fallback in FinalizeNewAPIData.
        if destName and destName ~= "" and NormalizeUnitName(destName) == nil then
            SafeMapSet(self.petOwnerByPetName, destName, ownerName)
        end
        return
    end

    -- Track deaths and unique mob kills (needed in all versions)
    if eventType == "UNIT_DIED" or eventType == "UNIT_DESTROYED" then
        L("INFO", "UNIT_DIED event: destName='" .. tostring(destName) .. "', destGUID='" .. tostring(destGUID) .. "', destFlags=" .. tostring(destFlags))
        self:OnUnitDeath(destGUID, destName, destFlags)
        return
    end

    -- WoW 12.0+ prefers C_DamageMeter for totals, but keep CLEU as a fallback.
    if self.useNewAPI and not self.allowCLEUFallback then
        return
    end

    -- Credit pet events to owner when possible
    local petOwnerFromGuid = sourceGUID and SafeMapGet(self.petOwnerNameByGUID, sourceGUID) or nil
    if petOwnerFromGuid then
        sourceName = petOwnerFromGuid
    elseif (not sourceName or sourceName == "") and sourceGUID and SafeMapGet(self.playerGUIDToName, sourceGUID) then
        sourceName = SafeMapGet(self.playerGUIDToName, sourceGUID)
    else
        -- Fallback: detect player-controlled pets by combat log flags and scan live party
        -- unit IDs to find the owner. This handles pets summoned before tracking started
        -- or whose SPELL_SUMMON event was never seen (e.g., warlock demons across reloads).
        local PLAYER_CONTROLLED_PET = bit.bor(COMBATLOG_OBJECT_TYPE_PET, COMBATLOG_OBJECT_CONTROL_PLAYER)
        if sourceGUID and sourceFlags and bit.band(sourceFlags, PLAYER_CONTROLLED_PET) == PLAYER_CONTROLLED_PET then
            local ownerName = nil
            -- Check the local player's own pet
            if UnitExists("pet") and ToTableKey(UnitGUID("pet")) == sourceGUID then
                local rawName, rawRealm = UnitName("player")
                local n = ToPlainString(rawName)
                local r = ToPlainString(rawRealm)
                if r and r ~= "" then n = n .. "-" .. r end
                ownerName = n
            end
            -- Check each party member's pet
            if not ownerName then
                for i = 1, 5 do
                    if UnitExists("party" .. i .. "pet") and ToTableKey(UnitGUID("party" .. i .. "pet")) == sourceGUID then
                        local rawName, rawRealm = UnitName("party" .. i)
                        local n = ToPlainString(rawName)
                        local r = ToPlainString(rawRealm)
                        if r and r ~= "" then n = n .. "-" .. r end
                        ownerName = n
                        break
                    end
                end
            end
            if ownerName then
                SafeMapSet(self.petOwnerNameByGUID, sourceGUID, ownerName)  -- cache for future events
                -- Also build the name-keyed map while we have both the pet name and owner.
                if sourceName and sourceName ~= "" and NormalizeUnitName(sourceName) == nil then
                    SafeMapSet(self.petOwnerByPetName, sourceName, ownerName)
                end
                sourceName = ownerName
            end
        end
    end
    -- If the resolved owner name lacks a realm suffix (same-server CLEU omission), upgrade it
    -- using fullNameByShort so NormalizeUnitName does not discard it as an apparent pet name.
    -- Also check petOwnerByPetName: covers pets whose GUID changed after run-start (resurrection)
    -- when the live unit-scan above couldn't match the stale event GUID.
    if sourceName and NormalizeUnitName(sourceName) == nil then
        local upgraded = self.fullNameByShort[sourceName]
        if upgraded then
            sourceName = upgraded
        elseif self.petOwnerByPetName and SafeMapGet(self.petOwnerByPetName, sourceName) then
            sourceName = SafeMapGet(self.petOwnerByPetName, sourceName)
        end
    end

    if eventType == "SWING_DAMAGE" then
        local amount = eventInfo[12]
        self:OnDamage(sourceName, amount)
        -- Track damage taken by players (for avoidable damage)
        local isPlayerDest = destFlags and (bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER)
        if isPlayerDest and destName then
            self:OnDamageTaken(destName, amount)
        end
    elseif eventType == "SPELL_DAMAGE" or eventType == "SPELL_PERIODIC_DAMAGE" or eventType == "RANGE_DAMAGE" then
        local amount = eventInfo[15]
        self:OnDamage(sourceName, amount)
        -- Track damage taken by players (for avoidable damage)
        local isPlayerDest = destFlags and (bit.band(destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER)
        if isPlayerDest and destName then
            self:OnDamageTaken(destName, amount)
        end
    elseif eventType == "SPELL_HEAL" or eventType == "SPELL_PERIODIC_HEAL" then
        local amount = eventInfo[15]
        self:OnHealing(sourceName, amount)
    elseif eventType == "SPELL_INTERRUPT" then
        self:OnInterrupt(sourceName)
    elseif eventType == "SPELL_DISPEL" then
        self:OnDispel(sourceName)
    end
end

function CombatLog:OnUnitDeath(guid, name, flags)
    if not guid then
        return
    end

    if not name then
        name = SafeMapGet(self.playerGUIDToName, guid)
    end
    
    local normalizedName = NormalizeUnitName(name)
    if not normalizedName then
        -- No realm suffix = pet, ignore player death tracking
        -- Continue to check if it's an NPC death though
        normalizedName = name
    end

    -- Track player deaths - only for players with realm suffix (not pets)
    local isPlayer = flags and (bit.band(flags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER)
    local isPet    = flags and (bit.band(flags, COMBATLOG_OBJECT_TYPE_PET)    == COMBATLOG_OBJECT_TYPE_PET)
    if isPlayer and not isPet and normalizedName then
        -- Create entry if needed
        if not self.playerStats[normalizedName] then
            self.playerStats[normalizedName] = {
                damage = 0,
                healing = 0,
                interrupts = 0,                dispels = 0,                deaths = 0,
                damageEvents = 0,
                healingEvents = 0,
                avoidableDamageTaken = 0,
            }
        end
        self.playerStats[normalizedName].deaths = (self.playerStats[normalizedName].deaths or 0) + 1
        L("INFO", "DEATH tracked for '" .. normalizedName .. "' (from '" .. tostring(name) .. "'), total deaths now: " .. self.playerStats[normalizedName].deaths)
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

    local normalizedName = NormalizeUnitName(sourceName)
    if not normalizedName then
        -- No realm suffix. Allow through only if this is a known same-realm roster player;
        -- otherwise treat as an unresolved pet and ignore.
        if not (self.activeRoster and self.activeRoster[sourceName]) then return end
        normalizedName = sourceName
    end
    
    -- Create player stats entry if it doesn't exist (for players with realm suffix)
    if not self.playerStats[normalizedName] then
        self.playerStats[normalizedName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            dispels = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
            avoidableDamageTaken = 0,
        }
    end
    
    self.playerStats[normalizedName].damage = self.playerStats[normalizedName].damage + amount
    self.playerStats[normalizedName].damageEvents = self.playerStats[normalizedName].damageEvents + 1
    if MPT.LiveTracker and MPT.LiveTracker.CaptureFromCombatEvent then
        MPT.LiveTracker:CaptureFromCombatEvent()
    end
end

function CombatLog:OnHealing(sourceName, amount)
    if not sourceName or not amount then return end

    local normalizedName = NormalizeUnitName(sourceName)
    if not normalizedName then
        if not (self.activeRoster and self.activeRoster[sourceName]) then return end
        normalizedName = sourceName
    end
    
    -- Create player stats entry if it doesn't exist (for players with realm suffix)
    if not self.playerStats[normalizedName] then
        self.playerStats[normalizedName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            dispels = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
            avoidableDamageTaken = 0,
        }
    end
    
    self.playerStats[normalizedName].healing = self.playerStats[normalizedName].healing + amount
    self.playerStats[normalizedName].healingEvents = self.playerStats[normalizedName].healingEvents + 1
    if MPT.LiveTracker and MPT.LiveTracker.CaptureFromCombatEvent then
        MPT.LiveTracker:CaptureFromCombatEvent()
    end
end

function CombatLog:OnInterrupt(sourceName)
    if not sourceName then return end

    local normalizedName = NormalizeUnitName(sourceName)
    if not normalizedName then
        if not (self.activeRoster and self.activeRoster[sourceName]) then return end
        normalizedName = sourceName
    end
    
    -- Create player stats entry if it doesn't exist (for players with realm suffix)
    if not self.playerStats[normalizedName] then
        self.playerStats[normalizedName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            dispels = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
            avoidableDamageTaken = 0,
        }
    end
    
    self.playerStats[normalizedName].interrupts = self.playerStats[normalizedName].interrupts + 1
    if MPT.LiveTracker and MPT.LiveTracker.CaptureFromCombatEvent then
        MPT.LiveTracker:CaptureFromCombatEvent()
    end
end

function CombatLog:OnDispel(sourceName)
    if not sourceName then return end

    local normalizedName = NormalizeUnitName(sourceName)
    if not normalizedName then
        if not (self.activeRoster and self.activeRoster[sourceName]) then return end
        normalizedName = sourceName
    end
    
    -- Create player stats entry if it doesn't exist (for players with realm suffix)
    if not self.playerStats[normalizedName] then
        self.playerStats[normalizedName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            dispels = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
            avoidableDamageTaken = 0,
        }
    end
    
    self.playerStats[normalizedName].dispels = (self.playerStats[normalizedName].dispels or 0) + 1
    if MPT.LiveTracker and MPT.LiveTracker.CaptureFromCombatEvent then
        MPT.LiveTracker:CaptureFromCombatEvent()
    end
end

-- Called when any unit's pet slot changes (UNIT_PET event).
-- Re-registers the pet GUID and display name so interrupts are credited to the owner
-- even when the pet was summoned or respawned after run-start (new GUID every resurrection).
function CombatLog:OnUnitPetChanged(ownerUnitID)
    if not ownerUnitID then return end

    local petUnitID = (ownerUnitID == "player") and "pet" or (ownerUnitID .. "pet")
    if not UnitExists(ownerUnitID) or not UnitExists(petUnitID) then return end

    if type(self.petOwnerNameByGUID) ~= "table" then
        self.petOwnerNameByGUID = {}
    end
    if type(self.petOwnerByPetName) ~= "table" then
        self.petOwnerByPetName = {}
    end

    local petGUID = ToTableKey(UnitGUID(petUnitID))
    local petName = ToTableKey(UnitName(petUnitID))
    local rawOwnerName, rawOwnerRealm = UnitName(ownerUnitID)
    local ownerN = ToPlainString(rawOwnerName)
    local ownerR = ToPlainString(rawOwnerRealm)
    if ownerR and ownerR ~= "" then
        ownerN = ownerN .. "-" .. ownerR
    end
    if not ownerN then return end

    -- Prefer the full Name-Realm form stored from the roster scan
    if NormalizeUnitName(ownerN) == nil then
        local short = ownerN
        local upgraded = self.fullNameByShort and self.fullNameByShort[short]
        if upgraded then ownerN = upgraded end
    end

    if petGUID then
        SafeMapSet(self.petOwnerNameByGUID, petGUID, ownerN)
        L("INFO", "UNIT_PET: registered GUID " .. tostring(petGUID) .. " -> " .. ownerN)
    end
    if petName then
        SafeMapSet(self.petOwnerByPetName, petName, ownerN)
        L("INFO", "UNIT_PET: registered name '" .. petName .. "' -> " .. ownerN)
    end
end

function CombatLog:OnDamageTaken(destName, amount)
    if not destName or not amount then return end

    local normalizedName = NormalizeUnitName(destName)
    if not normalizedName then
        if not (self.activeRoster and self.activeRoster[destName]) then return end
        normalizedName = destName
    end
    
    -- Create player stats entry if it doesn't exist (for players with realm suffix)
    if not self.playerStats[normalizedName] then
        self.playerStats[normalizedName] = {
            damage = 0,
            healing = 0,
            interrupts = 0,
            dispels = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
            avoidableDamageTaken = 0,
        }
    end
    
    self.playerStats[normalizedName].avoidableDamageTaken = self.playerStats[normalizedName].avoidableDamageTaken + amount
    if MPT.LiveTracker and MPT.LiveTracker.CaptureFromCombatEvent then
        MPT.LiveTracker:CaptureFromCombatEvent()
    end
end

function CombatLog:GetPlayerStats(name)
    if not name then
        return {
            damage = 0,
            healing = 0,
            interrupts = 0,
            deaths = 0,
            damageEvents = 0,
            healingEvents = 0,
            avoidableDamageTaken = 0,
        }
    end

    -- Try exact match first
    if self.playerStats[name] then
        return self.playerStats[name]
    end

    -- Try normalized version (with realm stripped)
    local shortName = NormalizeUnitName(name)
    if shortName and self.playerStats[shortName] then
        return self.playerStats[shortName]
    end

    -- If name has no realm, try to find a match in playerStats keys that start with this name
    local hasRealm = name:find("-")
    if not hasRealm then
        for playerName, stats in pairs(self.playerStats) do
            -- Check if this playerStats key starts with the search name
            local playerShortName = NormalizeUnitName(playerName)
            if playerShortName == name then
                L("INFO", "GetPlayerStats: Matched '" .. name .. "' to '" .. playerName .. "'")
                return stats
            end
        end
    end

    -- Log failed lookups
    L("WARN", "GetPlayerStats failed for '" .. tostring(name) .. "', normalized='" .. tostring(shortName) .. "'")
    local availableNames = {}
    for pname, _ in pairs(self.playerStats) do
        table.insert(availableNames, pname)
    end
    if #availableNames > 0 then
        L("WARN", "  Available names: " .. table.concat(availableNames, ", "))
    else
        L("WARN", "  playerStats table is EMPTY!")
    end

    return {
        damage = 0,
        healing = 0,
        interrupts = 0,
        dispels = 0,
        deaths = 0,
        damageEvents = 0,
        healingEvents = 0,
        avoidableDamageTaken = 0,
    }
end

