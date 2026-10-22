-- Offline tests for the 1-5 star player ratings in Database.lua and Utils.lua.
-- Run from the addon folder with Lua 5.1:
--   lua tests/star_rating_test.lua

local ADDON = arg and arg[1] or "."
StormsDungeonData = {Database = {}, Utils = {}}
GetRealmName = function() return "Home Realm" end
time = os.time
dofile(ADDON .. "/Utils.lua")
dofile(ADDON .. "/Database.lua")
local DB = StormsDungeonData.Database
local Utils = StormsDungeonData.Utils

local failures, passed = 0, 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failures = failures + 1
        print("FAIL " .. name .. "\n  " .. tostring(err))
    end
end

local function Fresh(runs)
    StormsDungeonDataDB = {runs = runs or {}, settings = {}}
end

test("legacy good/bad read as 5 and 1 stars", function()
    assert(DB:NormalizeStars("good") == 5)
    assert(DB:NormalizeStars("bad") == 1)
    assert(DB:NormalizeStars(3) == 3)
    assert(DB:NormalizeStars(9) == 5, "clamps high")
    assert(DB:NormalizeStars(0) == nil, "zero is unrated")
    assert(DB:NormalizeStars("meh") == nil)
end)

test("set, get and clear a run rating", function()
    Fresh({{id = "r1"}})
    assert(DB:SetRunPlayerRating("r1", "Pal-Other Realm", 4))
    assert(DB:GetRunPlayerRating("r1", "pal-otherrealm") == 4, "key is case and space insensitive")
    DB:SetRunPlayerRating("r1", "Pal-Other Realm", nil)
    assert(DB:GetRunPlayerRating("r1", "Pal-Other Realm") == nil)
    assert(DB:SetRunPlayerRating("missing", "Pal", 3) == false)
end)

test("summary averages non-deleted runs, mixing legacy and stars", function()
    Fresh({
        {id = "a", playerRatings = {["pal-homerealm"] = "good"}},
        {id = "b", playerRatings = {["pal-homerealm"] = 2}},
        {id = "c", playerRatings = {["pal-homerealm"] = 1}, deleted = true},
        {id = "d"},
    })
    local avg, count = DB:GetPlayerRatingSummary("Pal")
    assert(count == 2, "count " .. tostring(count))
    assert(math.abs(avg - 3.5) < 1e-9, "avg " .. tostring(avg))
    local none, zero = DB:GetPlayerRatingSummary("Nobody")
    assert(none == nil and zero == 0)
end)

test("migration converts strings once and sets its flag", function()
    Fresh({{id = "a", playerRatings = {x = "good", y = "bad", z = 4}}})
    StormsDungeonData.Log = nil
    DB:ApplyOneTimeStarRatingMigration()
    local r = StormsDungeonDataDB.runs[1].playerRatings
    assert(r.x == 5 and r.y == 1 and r.z == 4)
    assert(StormsDungeonDataDB.settings.starRatingMigrationV1 == true)
    r.x = "good"
    DB:ApplyOneTimeStarRatingMigration()
    assert(r.x == "good", "second call is a no-op")
end)

test("whisper flag is tracked per run and player", function()
    Fresh({{id = "a"}, {id = "b"}})
    assert(not DB:WasRatingWhisperSent("a", "Pal"))
    DB:MarkRatingWhisperSent("a", "Pal")
    assert(DB:WasRatingWhisperSent("a", "pal-home realm"))
    assert(not DB:WasRatingWhisperSent("b", "Pal"))
end)

test("star summary text", function()
    assert(Utils:FormatStarSummary(nil, 0):find("No rating yet"))
    local text = Utils:FormatStarSummary(4.25, 4)
    assert(text:find("4%.2/5") or text:find("4%.3/5"), text)
    assert(text:find("%(4 runs%)"), text)
    assert(text:find("5fd38d"), "4+ average is green")
    assert(Utils:FormatStarSummary(1, 1):find("%(1 run%)"))
    assert(Utils:FormatStarSummary(1, 1):find("ff6b6b"), "low average is red")
end)

print(string.format("%d passed, %d failed", passed, failures))
os.exit(failures == 0 and 0 or 1)
