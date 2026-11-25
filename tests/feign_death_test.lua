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

-- ---------------------------------------------------------------------------
-- FixSavedRun: runs saved before the fix
-- ---------------------------------------------------------------------------
local function savedRun(deathCount, players)
    return {character = "Me", deathCount = deathCount, players = players}
end

local run = savedRun(4, {
    {name = "Me-Realm", class = "MAGE", deaths = 1},
    {name = "Hunty-Other", class = "HUNTER", deaths = 21},
    {name = "Tanky-Realm", class = "WARRIOR", deaths = 3},
})
check("saved run: feigns removed", FD.FixSavedRun(run) == 21 and run.players[2].deaths == 0)
check("saved run: original count kept on the record", run.players[2].deathsBeforeFeignFix == 21)
check("saved run: other players untouched",
    run.players[1].deaths == 1 and run.players[3].deaths == 3 and run.players[3].deathsBeforeFeignFix == nil)
check("saved run: fixing twice changes nothing", FD.FixSavedRun(run) == 0 and run.players[2].deathsBeforeFeignFix == 21)

run = savedRun(0, {{name = "Me-Realm", class = "HUNTER", deaths = 2}, {name = "Pal-Realm", class = "PALADIN", deaths = 0}})
check("saved run: the recording hunter is left alone", FD.FixSavedRun(run) == 0 and run.players[1].deaths == 2)

run = savedRun(0, {{unitID = "player", name = "Renamed-Realm", class = "HUNTER", deaths = 2}})
check("saved run: unitID marks the recording player", FD.FixSavedRun(run) == 0 and run.players[1].deaths == 2)

run = savedRun(nil, {{name = "Me-Realm", class = "MAGE", deaths = 0}, {name = "Hunty-Other", class = "HUNTER", deaths = 5}})
check("saved run: no key count, no change", FD.FixSavedRun(run) == 0 and run.players[2].deaths == 5)

run = {character = "Gone", deathCount = 0, players = {{name = "Hunty-Other", class = "HUNTER", deaths = 5}}}
check("saved run: skipped when the recording player isn't on it", FD.FixSavedRun(run) == 0 and run.players[1].deaths == 5)

run = savedRun(1, {{name = "Me-Realm", class = "MAGE", deaths = 3}, {name = "Hunty-Other", class = "HUNTER", deaths = 2}})
check("saved run: bad key count leaves the hunter", FD.FixSavedRun(run) == 0 and run.players[2].deaths == 2)

check("saved run: junk input is ignored", FD.FixSavedRun(nil) == 0 and FD.FixSavedRun({players = "x"}) == 0)

-- Only hunters' counts are written, even when another row holds a bad value.
run = savedRun(0, {
    {name = "Me-Realm", class = "MAGE", deaths = 0},
    {name = "Tanky-Realm", class = "WARRIOR", deaths = -2},
    {name = "Heals-Realm", class = "PRIEST", deaths = "0"},
    {name = "Hunty-Other", class = "HUNTER", deaths = 3},
})
check("saved run: hunter trimmed beside odd rows", FD.FixSavedRun(run) == 3 and run.players[4].deaths == 0)
check("saved run: odd rows left exactly as saved",
    run.players[2].deaths == -2 and run.players[2].deathsBeforeFeignFix == nil
    and run.players[3].deaths == "0" and run.players[3].deathsBeforeFeignFix == nil)

run = savedRun(0, {{name = "Me-Realm", class = "MAGE", deaths = 0}, {name = "Hunty-Other", class = "HUNTER", deaths = 1e9}})
check("saved run: absurd count is skipped", FD.FixSavedRun(run) == 0 and run.players[2].deaths == 1e9)

run = savedRun(2, {
    {name = "Me-Realm", class = "MAGE", deaths = 1},
    {name = "Hunty-Other", class = "HUNTER", deaths = 5},
    {name = "Bowy-Other", class = "HUNTER", deaths = 3},
})
check("saved run: two hunters trimmed down to the key count",
    FD.FixSavedRun(run) == 7 and run.players[2].deaths + run.players[3].deaths == 1 and run.players[1].deaths == 1)

-- The one-time pass in Database.lua.
GetRealmName = function() return "Realm" end
time = os.time
local realPrint = print
local printed = {}
print = function(...) printed[#printed + 1] = table.concat({...}, " ") end
dofile(ADDON .. "/Database.lua")
local DB = StormsDungeonData.Database
StormsDungeonDataDB = {
    settings = {},
    runs = {
        savedRun(1, {{name = "Me-Realm", class = "MAGE", deaths = 1}, {name = "Hunty-Other", class = "HUNTER", deaths = 6}}),
        savedRun(2, {{name = "Me-Realm", class = "MAGE", deaths = 2}, {name = "Tanky-Realm", class = "WARRIOR", deaths = 0}}),
        {character = "Me", deathCount = 0, deleted = true,
            players = {{name = "Me-Realm", class = "MAGE", deaths = 0}, {name = "Hunty-Other", class = "HUNTER", deaths = 4}}},
    },
}
DB:ApplyOneTimeFeignDeathFix()
print = realPrint
check("migration fixes the hunter run", StormsDungeonDataDB.runs[1].players[2].deaths == 0)
check("migration skips deleted runs", StormsDungeonDataDB.runs[3].players[2].deaths == 4)
check("migration sets its flag", StormsDungeonDataDB.settings.feignDeathFixV1 == true)
check("migration tells the player once", #printed == 1 and printed[1]:find("1 run") ~= nil)

StormsDungeonDataDB.runs[1].players[2].deaths = 9
StormsDungeonDataDB.runs[1].players[2].deathsBeforeFeignFix = nil
DB:ApplyOneTimeFeignDeathFix()
check("migration runs only once", StormsDungeonDataDB.runs[1].players[2].deaths == 9)

-- One record that makes the fix throw is skipped; the rest are still corrected.
StormsDungeonDataDB = {
    settings = {},
    runs = {
        savedRun(0, {{name = "Me-Realm", class = "MAGE", deaths = 0}, {name = "Boom-Other", class = "HUNTER", deaths = 2}}),
        savedRun(0, {{name = "Me-Realm", class = "MAGE", deaths = 0}, {name = "Hunty-Other", class = "HUNTER", deaths = 2}}),
    },
}
local realFix = FD.FixSavedRun
FD.FixSavedRun = function(r)
    if r.players[2].name == "Boom-Other" then error("boom") end
    return realFix(r)
end
print = function() end
local okThrow = pcall(DB.ApplyOneTimeFeignDeathFix, DB)
print = realPrint
FD.FixSavedRun = realFix
check("migration survives a record that throws",
    okThrow and StormsDungeonDataDB.runs[2].players[2].deaths == 0 and StormsDungeonDataDB.settings.feignDeathFixV1 == true)

StormsDungeonDataDB = {settings = {}, runs = "junk"}
check("migration tolerates a damaged runs table", pcall(DB.ApplyOneTimeFeignDeathFix, DB))

-- Without the filter loaded the pass waits instead of marking itself done.
StormsDungeonDataDB = {settings = {}, runs = {}}
local savedFD = StormsDungeonData.FeignDeath
StormsDungeonData.FeignDeath = nil
DB:ApplyOneTimeFeignDeathFix()
StormsDungeonData.FeignDeath = savedFD
check("migration waits for the filter", StormsDungeonDataDB.settings.feignDeathFixV1 == nil)

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
