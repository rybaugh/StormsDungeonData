-- Offline test: a player who leaves before the run ends comes back from C_DamageMeter
-- with a secret GUID. GetDeathCountForSourceGUID must skip that row instead of
-- comparing it (secret == string throws in the real client).
-- Run from the addon folder with Lua 5.1:
--   lua tests/secret_guid_deaths_test.lua

local ADDON = arg and arg[1] or "."
StormsDungeonData = {Log = {Log = function() end}}
Enum = {
    DamageMeterType = {Deaths = 5},
    DamageMeterSessionType = {Overall = 0, Current = 1, Expired = 2},
    AddOnRestrictionType = {Combat = 0},
}
C_RestrictedActions = {GetAddOnRestrictionState = function() return 0 end}

-- Rows the fake meter returns: { guid }. GUIDs listed in `secrets` read as secret.
-- Lua 5.1 can't make a plain string throw on ==, so the test checks behavior instead:
-- a secret row must never match, even when its text equals the target.
local rows = {}
local secrets = {}
issecretvalue = function(v) return v ~= nil and secrets[v] == true end

C_DamageMeter = {
    GetAvailableCombatSessions = function() return {} end,
    GetCombatSessionSourceFromType = function() return nil end,
    GetCombatSessionFromType = function(sessionType, meterType)
        assert(meterType == Enum.DamageMeterType.Deaths)
        local sources = {}
        for _, r in ipairs(rows) do
            sources[#sources + 1] = {sourceGUID = r.guid, deathRecapID = 1}
        end
        return {combatSources = sources}
    end,
}

dofile(ADDON .. "/DamageMeterCompat.lua")
local Compat = StormsDungeonData.DamageMeterCompat

local failures = 0
local function check(name, cond)
    if cond then
        print("ok   " .. name)
    else
        print("FAIL " .. name)
        failures = failures + 1
    end
end

-- Player-0001 stayed; Player-0002 left before the end and reads as secret.
rows = {{guid = "Player-0001"}, {guid = "Player-0002"}}
secrets["Player-0002"] = true

local ok, deaths = pcall(Compat.GetDeathCountForSourceGUID, Compat, "Player-0001")
check("no error with a secret row in the session", ok)
check("stayed player's deaths still counted", ok and deaths == 1)

local okLeft, leftDeaths = pcall(Compat.GetDeathCountForSourceGUID, Compat, "Player-0002")
check("left player lookup does not error", okLeft)
check("left player returns nil (no readable row)", okLeft and leftDeaths == nil)

-- A secret GUID passed in as the target is refused up front.
local secretTarget = "Player-0003"
secrets[secretTarget] = true
local okTarget, targetDeaths = pcall(Compat.GetDeathCountForSourceGUID, Compat, secretTarget)
check("secret target refused", okTarget and targetDeaths == nil)

if failures > 0 then
    print(failures .. " failure(s)")
    os.exit(1)
end
print("all passed")
