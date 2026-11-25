-- Storm's Dungeon Data - Feign Death filter
-- Blizzard's Deaths meter (C_DamageMeter) logs a hunter's Feign Death as a death on
-- every client except the hunter's own, and the row carries nothing that tells a
-- feign from a real death. This module watches party units for feigns during a key
-- and, when the run is saved, trims them from the per-player death counts.
-- The key's own death count (C_ChallengeMode.GetDeathCount) is the timer-penalty
-- count, which a feign doesn't add to, so it is the reference whenever it can be read.

local MPT = StormsDungeonData
local FeignDeath = {}
MPT.FeignDeath = FeignDeath

local function L(level, msg)
    if MPT.Log then MPT.Log:Log(level or "INFO", msg) end
end

FeignDeath.SPELL_ID = 5384
-- One feign can arrive through both the unit flag and the cast event. Feign Death's
-- cooldown is far longer than this, so two starts this close are the same feign.
FeignDeath.DEDUPE_SECONDS = 3

local HUNTER_CLASS = "HUNTER"
local CHALLENGE_DIFFICULTY_ID = 8
local PARTY_UNIT_LIST = {"party1", "party2", "party3", "party4"}
local PARTY_UNITS = {}
for _, unit in ipairs(PARTY_UNIT_LIST) do
    PARTY_UNITS[unit] = true
end

FeignDeath.units = {}       -- [key] = {feigning, dead, feigns, deaths, lastFeignAt}
FeignDeath.guidByName = {}  -- [name key] = GUID key, learned while the GUID was readable

-- Secret values can't be compared or used as table keys, so every read is checked first.
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Now()
    return GetTime and GetTime() or 0
end

local function PlainString(v)
    if IsSecret(v) or type(v) ~= "string" or v == "" then
        return nil
    end
    return v
end

-- "Name" and "Name-Realm" map to one key.
local function NameKey(name)
    local plain = PlainString(name)
    if not plain then
        return nil
    end
    return "n:" .. string.lower(plain:match("^([^%-]+)") or plain)
end

function FeignDeath:Reset()
    self.units = {}
    self.guidByName = {}
    self.errorLogged = false
end

function FeignDeath:GetState(key)
    local state = self.units[key]
    if not state then
        state = {feigning = false, dead = false, feigns = 0, deaths = 0, lastFeignAt = nil}
        self.units[key] = state
    end
    return state
end

-- A unit tracked by name while its GUID was secret moves under the GUID once that
-- can be read, so one feign is never counted under two keys.
function FeignDeath:MergeState(fromKey, toKey)
    local from = self.units[fromKey]
    if not from or fromKey == toKey then
        return
    end
    local to = self.units[toKey]
    if not to then
        self.units[toKey] = from
    else
        to.feigns = to.feigns + from.feigns
        to.deaths = to.deaths + from.deaths
        to.feigning = to.feigning or from.feigning
        to.dead = to.dead or from.dead
        if from.lastFeignAt and (not to.lastFeignAt or from.lastFeignAt > to.lastFeignAt) then
            to.lastFeignAt = from.lastFeignAt
        end
    end
    self.units[fromKey] = nil
end

-- GUID when it can be read, otherwise the unit's name.
function FeignDeath:KeyForUnit(unit)
    local guid = PlainString(UnitGUID and UnitGUID(unit))
    local nameKey = NameKey(UnitName and UnitName(unit))
    if guid then
        if nameKey then
            self.guidByName[nameKey] = guid
            self:MergeState(nameKey, guid)
        end
        return guid
    end
    if nameKey then
        return self.guidByName[nameKey] or nameKey
    end
    return nil
end

function FeignDeath:CountFeign(key, now)
    local state = self:GetState(key)
    if state.lastFeignAt and (now - state.lastFeignAt) < self.DEDUPE_SECONDS then
        return
    end
    state.feigns = state.feigns + 1
    state.lastFeignAt = now
    L("INFO", "FeignDeath: feign #" .. state.feigns .. " for " .. tostring(key))
end

-- Feed one reading of a unit's state. A feigning hunter reads as dead to everyone
-- else, so only "dead and not feigning" (or a ghost) is a real death.
function FeignDeath:Observe(key, isFeign, isDead, isGhost, now)
    local state = self:GetState(key)
    if isFeign and not state.feigning then
        self:CountFeign(key, now)
    end
    state.feigning = isFeign

    local reallyDead = isGhost or (isDead and not isFeign)
    if reallyDead and not state.dead then
        state.deaths = state.deaths + 1
        state.dead = true
    elseif not isDead and not isGhost then
        state.dead = false
    end
end

function FeignDeath:ScanUnit(unit, now)
    if not (UnitExists and UnitIsFeignDeath and UnitIsDeadOrGhost and UnitIsGhost) then
        return
    end
    local exists = UnitExists(unit)
    if IsSecret(exists) or not exists then
        return
    end
    local isFeign = UnitIsFeignDeath(unit)
    local isDead = UnitIsDeadOrGhost(unit)
    local isGhost = UnitIsGhost(unit)
    if IsSecret(isFeign) or IsSecret(isDead) or IsSecret(isGhost) then
        return
    end
    local key = self:KeyForUnit(unit)
    if not key then
        return
    end
    self:Observe(key, isFeign == true, isDead == true, isGhost == true, now or Now())
end

function FeignDeath:ScanParty()
    local now = Now()
    for _, unit in ipairs(PARTY_UNIT_LIST) do
        self:ScanUnit(unit, now)
    end
end

function FeignDeath:OnEvent(event, unit, spellID)
    if not MPT.InMythicPlus then
        return
    end
    if IsSecret(unit) or not PARTY_UNITS[unit] then
        return
    end
    if event == "UNIT_FLAGS" then
        self:ScanUnit(unit, Now())
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if IsSecret(spellID) or spellID ~= self.SPELL_ID then
            return
        end
        local key = self:KeyForUnit(unit)
        if key then
            self:CountFeign(key, Now())
            self:GetState(key).feigning = true
        end
    end
end

-- Returns feigns seen and real deaths seen for a player, by GUID and/or name.
function FeignDeath:GetCounts(guid, name)
    local feigns, deaths = 0, 0
    local seen = {}
    local function add(key)
        local state = key and not seen[key] and self.units[key]
        if state then
            seen[key] = true
            feigns = feigns + state.feigns
            deaths = deaths + state.deaths
        end
    end
    local nameKey = NameKey(name)
    add(PlainString(guid))
    add(nameKey)
    add(nameKey and self.guidByName[nameKey])
    return feigns, deaths
end

-- The key's death count, or nil when it can't be trusted (outside the dungeon the
-- API can read 0 for a key that had deaths).
function FeignDeath:GetOfficialDeathCount()
    if not (C_ChallengeMode and C_ChallengeMode.GetDeathCount and GetInstanceInfo) then
        return nil
    end
    local _, instanceType, difficultyID = GetInstanceInfo()
    if instanceType ~= "party" or difficultyID ~= CHALLENGE_DIFFICULTY_ID then
        return nil
    end
    local deaths = C_ChallengeMode.GetDeathCount()
    if IsSecret(deaths) or type(deaths) ~= "number" or deaths < 0 then
        return nil
    end
    return deaths
end

-- No key count to check against: take off the feigns that were seen, but never
-- go below the real deaths that were seen.
local function TrimTracked(result, candidates)
    local removed = 0
    for _, c in ipairs(candidates) do
        if c.feigns > 0 then
            local deaths = result[c.index]
            local kept = math.min(deaths, math.max(c.realDeaths, deaths - c.feigns))
            removed = removed + (deaths - kept)
            result[c.index] = kept
        end
    end
    return removed
end

-- Take `excess` deaths off the candidates one at a time, from whoever has the most
-- left by `weight`. Returns how many could not be placed.
local function TakeExcess(result, candidates, excess, weight)
    while excess > 0 do
        local best, bestWeight = nil, 0
        for _, c in ipairs(candidates) do
            local w = math.min(weight(c), result[c.index])
            if w > bestWeight then
                best, bestWeight = c, w
            end
        end
        if not best then
            break
        end
        result[best.index] = result[best.index] - 1
        best.feignsLeft = best.feignsLeft - 1
        excess = excess - 1
    end
    return excess
end

-- Pure. entries[i] = {deaths, isHunter, isLocal, feigns, realDeaths}; groupDeaths is
-- the key's death count or nil. Returns the corrected death count per entry and how
-- many were removed. Only other players' hunters (or anyone seen feigning) are
-- touched: the local player's own count is already right.
function FeignDeath.Adjust(entries, groupDeaths)
    local result, candidates, total = {}, {}, 0
    for i, e in ipairs(entries) do
        local deaths = math.max(0, tonumber(e.deaths) or 0)
        local feigns = math.max(0, tonumber(e.feigns) or 0)
        result[i] = deaths
        total = total + deaths
        if not e.isLocal and deaths > 0 and (e.isHunter or feigns > 0) then
            candidates[#candidates + 1] = {
                index = i,
                feigns = feigns,
                feignsLeft = feigns,
                realDeaths = math.max(0, tonumber(e.realDeaths) or 0),
            }
        end
    end
    if #candidates == 0 then
        return result, 0
    end
    -- Everyone who can't have feigned already has more deaths than the key count:
    -- the key count is wrong (read too late or reset), so don't trim against it.
    local candidateDeaths = 0
    for _, c in ipairs(candidates) do
        candidateDeaths = candidateDeaths + result[c.index]
    end
    if type(groupDeaths) == "number" and (total - candidateDeaths) > groupDeaths then
        groupDeaths = nil
    end
    if type(groupDeaths) ~= "number" then
        return result, TrimTracked(result, candidates)
    end

    local excess = total - groupDeaths
    if excess <= 0 then
        return result, 0
    end
    -- Feigns that were seen come off first, then whatever the key count still disputes.
    local left = TakeExcess(result, candidates, excess, function(c) return c.feignsLeft end)
    left = TakeExcess(result, candidates, left, function(c) return result[c.index] end)
    return result, excess - left
end

-- Save-time entry point: corrects p.deaths on the run's player records in place,
-- the same way FinalizeRun fills them. Returns how many feigns were removed.
function FeignDeath:ApplyToPlayers(players)
    if type(players) ~= "table" then
        return 0
    end
    self:ScanParty()

    local localGUID = PlainString(UnitGUID and UnitGUID("player"))
    local entries = {}
    for i, p in ipairs(players) do
        local guid = PlainString(p.guid)
        local feigns, realDeaths = self:GetCounts(guid, p.name)
        entries[i] = {
            deaths = p.deaths,
            isHunter = p.class == HUNTER_CLASS,
            isLocal = p.unitID == "player" or (localGUID ~= nil and guid == localGUID),
            feigns = feigns,
            realDeaths = realDeaths,
        }
    end

    local groupDeaths = self:GetOfficialDeathCount()
    local adjusted, removed = FeignDeath.Adjust(entries, groupDeaths)
    for i, p in ipairs(players) do
        local before = tonumber(p.deaths) or 0
        if adjusted[i] ~= before then
            L("INFO", "FeignDeath: " .. tostring(p.name) .. " deaths " .. before .. " -> " .. adjusted[i]
                .. " (feigns seen=" .. entries[i].feigns .. ", key deaths=" .. tostring(groupDeaths) .. ")")
            p.deaths = adjusted[i]
        end
    end
    return removed
end

-- Registered at load time: Frame:RegisterEvent() is protected in WoW 12+ when called
-- from a tainted call chain, and top-level addon code is never tainted.
-- RegisterUnitEvent keeps the filtering in the client: these two events otherwise fire
-- for every nameplate and raid member. It is only sure to take two units per call, and
-- a second call on the same frame replaces the first, so each pair gets its own frame.
if CreateFrame then
    local function HandleEvent(_, event, unit, _, spellID)
        if not MPT.InMythicPlus then
            return
        end
        local ok, err = pcall(FeignDeath.OnEvent, FeignDeath, event, unit, spellID)
        -- A repeating error is logged once per key.
        if not ok and not FeignDeath.errorLogged then
            FeignDeath.errorLogged = true
            L("ERROR", "FeignDeath:OnEvent failed: " .. tostring(err))
        end
    end

    FeignDeath.frames = {}
    for i = 1, #PARTY_UNIT_LIST, 2 do
        local frame = CreateFrame("Frame")
        frame:RegisterUnitEvent("UNIT_FLAGS", PARTY_UNIT_LIST[i], PARTY_UNIT_LIST[i + 1])
        frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", PARTY_UNIT_LIST[i], PARTY_UNIT_LIST[i + 1])
        frame:SetScript("OnEvent", HandleEvent)
        FeignDeath.frames[#FeignDeath.frames + 1] = frame
    end
end
