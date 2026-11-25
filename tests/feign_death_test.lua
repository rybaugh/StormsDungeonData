-- Offline test: Blizzard's Deaths meter logs a hunter's Feign Death as a death on
-- every client but the hunter's own. FeignDeath tracks feigns on party units and
-- trims them from the per-player counts at save time.
-- Run from the addon folder with Lua 5.1:
--   lua tests/feign_death_test.lua

local ADDON = arg and arg[1] or "."
StormsDungeonData = {Log = {Log = function() end}, InMythicPlus = true}

-- Fake client state the module reads.
local units = {}      -- [unitToken] = {guid, name, feign, dead, ghost}
local secrets = {}
local officialDeaths = 0
local instanceType, difficultyID = "party", 8
local clock = 0

issecretvalue = function(v) return v ~= nil and secrets[v] == true end
GetTime = function() return clock end
UnitExists = function(unit) return units[unit] ~= nil end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitName = function(unit) return units[unit] and units[unit].name end
UnitIsFeignDeath = function(unit) return units[unit] and units[unit].feign or false end
UnitIsDeadOrGhost = function(unit) return units[unit] and (units[unit].dead or units[unit].ghost) or false end
UnitIsGhost = function(unit) return units[unit] and units[unit].ghost or false end
GetInstanceInfo = function() return "Dungeon", instanceType, difficultyID end
C_ChallengeMode = {GetDeathCount = function() return officialDeaths, officialDeaths * 15 end}

local onEvent
local registered = {}  -- ["EVENT:unit"] = true
CreateFrame = function()
    return {
        RegisterUnitEvent = function(_, event, ...)
            for _, unit in ipairs({...}) do
                registered[event .. ":" .. unit] = true
            end
        end,
        SetScript = function(_, _, fn) onEvent = fn end,
    }
end

dofile(ADDON .. "/FeignDeath.lua")
local FD = StormsDungeonData.FeignDeath

local failures = 0
local function check(name, cond)
    if cond then
        print("ok   " .. name)
    else
        print("FAIL " .. name)
        failures = failures + 1
    end
end

local function fire(event, unit, spellID)
    onEvent(nil, event, unit, "cast-guid", spellID)
end

local function reset()
    FD:Reset()
    units = {
        player = {guid = "Player-0001", name = "Me"},
        party1 = {guid = "Player-0002", name = "Hunty"},
        party2 = {guid = "Player-0003", name = "Tanky"},
    }
    secrets = {}
    officialDeaths = 0
    instanceType, difficultyID = "party", 8
    clock = 100
end

-- ---------------------------------------------------------------------------
-- Tracking feigns and real deaths from unit state
-- ---------------------------------------------------------------------------
reset()
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
local feigns, deaths = FD:GetCounts("Player-0002", "Hunty-Realm")
check("feign counted once", feigns == 1)
check("feign is not a real death", deaths == 0)

fire("UNIT_FLAGS", "party1")
check("same feign not counted twice", (FD:GetCounts("Player-0002")) == 1)

units.party1.feign, units.party1.dead = false, false
fire("UNIT_FLAGS", "party1")
clock = clock + 30
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
check("second feign counted", (FD:GetCounts("Player-0002")) == 2)

-- The cast event and the unit flag report the same feign.
reset()
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", 5384)
fire("UNIT_FLAGS", "party1")              -- flag not set yet
clock = clock + 0.2
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
check("cast plus flag is one feign", (FD:GetCounts("Player-0002")) == 1)

reset()
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", 19574)
check("other spells ignored", (FD:GetCounts("Player-0002")) == 0)

-- Real deaths.
reset()
units.party1.dead = true
fire("UNIT_FLAGS", "party1")
fire("UNIT_FLAGS", "party1")
feigns, deaths = FD:GetCounts("Player-0002")
check("real death counted once", feigns == 0 and deaths == 1)
units.party1.dead = false
fire("UNIT_FLAGS", "party1")
units.party1.dead = true
fire("UNIT_FLAGS", "party1")
check("second real death counted", select(2, FD:GetCounts("Player-0002")) == 2)

-- Feign, then die while the feign flag sticks; the ghost flag settles it.
reset()
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
units.party1.ghost = true
fire("UNIT_FLAGS", "party1")
feigns, deaths = FD:GetCounts("Player-0002")
check("ghost counts as a real death", feigns == 1 and deaths == 1)

-- Secret values never throw and never count.
reset()
secrets[5384] = true
local okSecretSpell = pcall(fire, "UNIT_SPELLCAST_SUCCEEDED", "party1", 5384)
check("secret spell id ignored", okSecretSpell and (FD:GetCounts("Player-0002")) == 0)

-- A secret GUID falls back to the unit's name.
reset()
secrets["Player-0002"] = true
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
check("secret guid tracked by name", (FD:GetCounts(nil, "Hunty-Realm")) == 1)

-- Outside a key nothing is tracked.
reset()
StormsDungeonData.InMythicPlus = false
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
check("not tracked outside a key", (FD:GetCounts("Player-0002")) == 0)
StormsDungeonData.InMythicPlus = true

-- Only party units; nameplates and the like are skipped.
reset()
units.nameplate3 = {guid = "Player-0009", name = "Stranger", feign = true, dead = true}
fire("UNIT_FLAGS", "nameplate3")
check("non-party units skipped", (FD:GetCounts("Player-0009")) == 0)

-- Every party unit is registered for both events.
local allRegistered = true
for i = 1, 4 do
    allRegistered = allRegistered
        and registered["UNIT_FLAGS:party" .. i] == true
        and registered["UNIT_SPELLCAST_SUCCEEDED:party" .. i] == true
end
check("both events registered for party1-4", allRegistered)

-- A feign counted by name while the GUID was secret is not counted again once the
-- GUID can be read.
reset()
secrets["Player-0002"] = true
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", 5384)
secrets["Player-0002"] = nil
clock = clock + 5
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
check("name-tracked feign not recounted under the guid", (FD:GetCounts("Player-0002", "Hunty-Realm")) == 1)

-- Unreadable unit state is skipped without an error.
reset()
secrets[true] = true
units.party1.feign, units.party1.dead = true, true
local okSecretState = pcall(fire, "UNIT_FLAGS", "party1")
secrets[true] = nil
check("secret unit state ignored", okSecretState and (FD:GetCounts("Player-0002")) == 0)

-- The key count is only used inside a keystone dungeon and when it reads as a number.
reset()
officialDeaths = 2
check("key count read inside the key", FD:GetOfficialDeathCount() == 2)
difficultyID = 23
check("key count ignored outside keystone difficulty", FD:GetOfficialDeathCount() == nil)
difficultyID = 8
secrets[2] = true
check("secret key count ignored", FD:GetOfficialDeathCount() == nil)
secrets[2] = nil
officialDeaths = -1
check("negative key count ignored", FD:GetOfficialDeathCount() == nil)

-- ---------------------------------------------------------------------------
-- Adjust: trimming feigns out of the meter's counts
-- ---------------------------------------------------------------------------
local function adjust(entries, groupDeaths)
    local out, removed = FD.Adjust(entries, groupDeaths)
    return out, removed
end

-- One hunter, the key's own count says 2 deaths, the meter says 5.
local out, removed = adjust({
    {deaths = 1},
    {deaths = 4, isHunter = true},
    {deaths = 0},
}, 2)
check("excess over the key count comes off the hunter", out[2] == 1 and removed == 3)
check("other players untouched", out[1] == 1 and out[3] == 0)

out = adjust({{deaths = 0}, {deaths = 6, isHunter = true}}, 0)
check("deathless key leaves the hunter at 0", out[2] == 0)

out, removed = adjust({{deaths = 2}, {deaths = 1, isHunter = true}}, 3)
check("matching totals change nothing", out[2] == 1 and removed == 0)

out, removed = adjust({{deaths = 1}, {deaths = 3, isHunter = true, feigns = 3}}, 5)
check("meter under the key count is left alone", out[2] == 3 and removed == 0)

out, removed = adjust({{deaths = 3, isHunter = true, isLocal = true}, {deaths = 1}}, 1)
check("own hunter never trimmed", out[1] == 3 and removed == 0)

out, removed = adjust({{deaths = 3}, {deaths = 2}}, 1)
check("no hunter, nothing trimmed", out[1] == 3 and out[2] == 2 and removed == 0)

-- Two hunters: tracked feigns decide who loses what.
out = adjust({
    {deaths = 4, isHunter = true, feigns = 3},
    {deaths = 2, isHunter = true, feigns = 1},
    {deaths = 1},
}, 3)
check("two hunters split by tracked feigns", out[1] == 1 and out[2] == 1 and out[3] == 1)

-- Tracking missed some feigns: the rest still comes off the hunters.
out = adjust({{deaths = 5, isHunter = true, feigns = 1}, {deaths = 1}}, 2)
check("untracked excess still trimmed", out[1] == 1)

-- A tracked feigner whose class is unknown is still a candidate.
out = adjust({{deaths = 2, feigns = 2}, {deaths = 1}}, 1)
check("tracked feigner without class trimmed", out[1] == 0)

-- No key count available: rely on what was tracked.
out, removed = adjust({{deaths = 3, isHunter = true, feigns = 2, realDeaths = 1}}, nil)
check("no key count: tracked feigns come off", out[1] == 1 and removed == 2)

out = adjust({{deaths = 3, isHunter = true, feigns = 5, realDeaths = 1}}, nil)
check("no key count: seen real deaths are kept", out[1] == 1)

out, removed = adjust({{deaths = 2, isHunter = true}}, nil)
check("no key count and nothing tracked: unchanged", out[1] == 2 and removed == 0)

-- A key count lower than the deaths of players who can't feign is wrong, so real
-- hunter deaths are not trimmed against it.
out, removed = adjust({{deaths = 2}, {deaths = 3, isHunter = true}}, 0)
check("bad key count leaves untracked hunter deaths", out[2] == 3 and removed == 0)

out = adjust({{deaths = 2}, {deaths = 3, isHunter = true, feigns = 1, realDeaths = 2}}, 0)
check("bad key count falls back to tracked feigns", out[2] == 2)

local input = {{deaths = 4, isHunter = true}}
adjust(input, 0)
check("input entries are not modified", input[1].deaths == 4)

-- ---------------------------------------------------------------------------
-- ApplyToPlayers: the save-time path
-- ---------------------------------------------------------------------------
reset()
officialDeaths = 1
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
local players = {
    {unitID = "player", name = "Me-Realm", class = "MAGE", guid = "Player-0001", deaths = 0},
    {unitID = "party1", name = "Hunty-Realm", class = "HUNTER", guid = "Player-0002", deaths = 3},
    {unitID = "party2", name = "Tanky-Realm", class = "WARRIOR", guid = "Player-0003", deaths = 1},
}
local trimmed = FD:ApplyToPlayers(players)
check("save path trims the hunter", players[2].deaths == 0 and trimmed == 3)
check("save path keeps the tank's death", players[3].deaths == 1)

-- Outside the dungeon the key count can't be trusted, so only tracked feigns come off.
reset()
instanceType, difficultyID = "none", 0
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
players = {
    {unitID = "party1", name = "Hunty-Realm", class = "HUNTER", guid = "Player-0002", deaths = 3},
}
FD:ApplyToPlayers(players)
check("outside the dungeon only tracked feigns come off", players[1].deaths == 2)

-- The local hunter's own count is already right.
reset()
officialDeaths = 0
players = {{unitID = "player", name = "Me-Realm", class = "HUNTER", guid = "Player-0001", deaths = 1}}
FD:ApplyToPlayers(players)
check("local hunter untouched on save", players[1].deaths == 1)

reset()
units.party1.feign, units.party1.dead = true, true
fire("UNIT_FLAGS", "party1")
FD:Reset()
check("reset clears tracked feigns", (FD:GetCounts("Player-0002", "Hunty")) == 0)

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
