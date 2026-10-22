-- Offline tests for InsightsAdvisor.lua. Run from the addon folder with Lua 5.1:
--   lua tests/insights_advisor_test.lua

StormsDungeonData = {}
dofile((arg and arg[1] or ".") .. "/InsightsAdvisor.lua")
local Advisor = StormsDungeonData.InsightsAdvisor

local TIME_LIMIT = 1800
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

local function Run(t)
    local run = {
        dungeonName = "Alpha", dungeonID = 1, keystoneLevel = 10, completed = true,
        duration = 1500, timeLost = 0, deathCount = 0, character = "Me", realm = "Realm",
        owner = {deaths = 0},
    }
    for k, v in pairs(t or {}) do
        run[k] = v
    end
    return run
end

local function Repeat(n, t)
    local out = {}
    for _ = 1, n do
        table.insert(out, Run(t))
    end
    return out
end

local function Concat(...)
    local out = {}
    for _, list in ipairs({...}) do
        for _, v in ipairs(list) do
            table.insert(out, v)
        end
    end
    return out
end

local function Build(runs, extra)
    local ctx = {
        runs = runs,
        seasonDungeons = {},
        isFailed = function(run)
            return run.completed == false or (run.duration or 0) > TIME_LIMIT
        end,
        getTimeLimit = function() return TIME_LIMIT end,
        getDuration = function(run) return run.duration end,
        getOwnerStats = function(run) return run.owner end,
        characterKey = function(run) return run.character .. "-" .. run.realm, run.character end,
    }
    for k, v in pairs(extra or {}) do
        ctx[k] = v
    end
    return Advisor:Build(ctx)
end

local function Find(recs, category)
    for _, rec in ipairs(recs) do
        if rec.category == category then
            return rec
        end
    end
    return nil
end

local function Count(recs, category)
    local n = 0
    for _, rec in ipairs(recs) do
        if rec.category == category then n = n + 1 end
    end
    return n
end

local function AssertContains(text, needle)
    assert(text and text:find(needle, 1, true), string.format("expected %q in %q", needle, tostring(text)))
end

test("returns no recommendations for an empty season", function()
    assert(#Build({}) == 0)
end)

test("flags deaths when the penalty covered the miss in most over-time keys", function()
    -- 1830s with 45s of penalty: missed by 30s, deaths cost 45s
    local deathDepletes = Repeat(3, {duration = 1830, timeLost = 45, deathCount = 3, owner = {deaths = 2}})
    local paceDeplete = Repeat(1, {duration = 1900, timeLost = 15, deathCount = 1, owner = {deaths = 0}})
    local recs = Build(Concat(deathDepletes, paceDeplete, Repeat(4, {})))
    local rec = Find(recs, "SURVIVAL")
    assert(rec, "expected a SURVIVAL recommendation")
    AssertContains(rec.headline, "3 of 4 over-time keys")
    AssertContains(rec.detail, "15s per death")
    -- owner took 6 of 10 party deaths in failed keys
    AssertContains(rec.detail, "You took 60%")
end)

test("skips the deaths line when over-time keys were about pace", function()
    local recs = Build(Concat(Repeat(4, {duration = 1900, timeLost = 15, deathCount = 1}), Repeat(4, {})))
    assert(not Find(recs, "SURVIVAL"))
end)

test("diagnoses a dungeon where keys get abandoned early", function()
    local abandons = Repeat(3, {dungeonName = "Bravo", completed = false, abandonReason = "abandon",
        duration = nil, overallMobPercentage = 20, deathCount = 6})
    local recs = Build(Concat(abandons, Repeat(2, {dungeonName = "Bravo"})))
    local rec = Find(recs, "FOCUS")
    assert(rec, "expected a FOCUS recommendation")
    AssertContains(rec.headline, "Practice Bravo: timed 2 of 5 (40%)")
    AssertContains(rec.detail, "3 of 3 failed keys here were abandoned, on average at 20% enemy forces with 6.0 deaths")
end)

test("diagnoses near misses as a route problem", function()
    local nearMisses = Repeat(3, {dungeonName = "Charlie", duration = 1830})
    local recs = Build(Concat(nearMisses, Repeat(2, {dungeonName = "Charlie"})))
    AssertContains(Find(recs, "FOCUS").detail, "3 of 3 over-time runs missed by under a minute")
end)

test("diagnoses big misses without deaths as pace", function()
    local slow = Repeat(3, {dungeonName = "Delta", duration = 1950})
    local recs = Build(Concat(slow, Repeat(2, {dungeonName = "Delta"})))
    AssertContains(Find(recs, "FOCUS").detail, "missed by 2m 30s on average")
end)

test("ignores dungeons that time reliably", function()
    local recs = Build(Concat(Repeat(9, {dungeonName = "Echo"}), Repeat(1, {dungeonName = "Echo", duration = 1830})))
    assert(not Find(recs, "FOCUS"))
end)

test("finds the key-level wall", function()
    local recs = Build(Concat(
        Repeat(4, {keystoneLevel = 12}),
        Repeat(1, {keystoneLevel = 13}), Repeat(3, {keystoneLevel = 13, duration = 1900}),
        Repeat(1, {keystoneLevel = 14, dungeonName = "Bravo"})))
    local rec = Find(recs, "KEY LEVEL")
    assert(rec, "expected a KEY LEVEL recommendation")
    AssertContains(rec.headline, "Me's wall is +13: timed 25% there vs 100% at +12")
end)

test("says when a character is ready for the next level", function()
    local recs = Build(Repeat(5, {keystoneLevel = 12}))
    local rec = Find(recs, "KEY LEVEL")
    AssertContains(rec.headline, "Me is ready for +13")
    AssertContains(rec.detail, "no attempts above it")
end)

test("points rating advice at the weakest dungeon and skips focus dungeons", function()
    local runs = Concat(
        Repeat(1, {dungeonName = "A", keystoneLevel = 15}),
        Repeat(1, {dungeonName = "B", keystoneLevel = 15}),
        Repeat(1, {dungeonName = "C", keystoneLevel = 15}),
        Repeat(1, {dungeonName = "D", keystoneLevel = 11}),
        Repeat(3, {dungeonName = "E", keystoneLevel = 15, completed = false, abandonReason = "abandon"}))
    local recs = Build(runs, {seasonDungeons = {"A", "B", "C", "D", "E", "F"}})
    local rec = Find(recs, "RATING")
    assert(rec, "expected a RATING recommendation")
    AssertContains(rec.headline, "Bring F up to +15 on Me")
    AssertContains(rec.detail, "F (none timed), D (+11)")
    assert(not rec.detail:find("E (", 1, true), "E is already a focus dungeon")
end)

test("keeps only outcome-linked role gaps that are at least 10% behind", function()
    local gaps = {
        {key = "hps", role = "HEALER", ownerAvg = 1, teammateAvg = 2, ratioToTeam = 0.5, belowRate = 1, comparedRuns = 9},
        {key = "avoidableDamageTaken", role = "DAMAGER", ownerAvg = 162, teammateAvg = 161, ratioToTeam = 0.99, belowRate = 0.6, comparedRuns = 9},
        {key = "deaths", role = "HEALER", ownerAvg = 1.4, teammateAvg = 0.7, ratioToTeam = 0.5, belowRate = 0.8, comparedRuns = 10},
        {key = "interrupts", role = "HEALER", ownerAvg = 0, teammateAvg = 3, ratioToTeam = 0, belowRate = 1, comparedRuns = 10},
    }
    local recs = Build(Repeat(4, {}), {underperformingMetrics = gaps})
    assert(Count(recs, "YOUR PLAY") == 1, "expected only the deaths gap")
    local rec = Find(recs, "YOUR PLAY")
    AssertContains(rec.headline, "Deaths: 1.4 per run vs 0.7 for other healers")
    AssertContains(rec.detail, "Behind in 80% of 10 compared runs")
end)

test("recommends a teammate who clearly lifts the timed rate", function()
    local pairList = {
        {pair = "Me + Pal", runs = 6, completionRate = 1.0},
        {pair = "Me + Rare", runs = 2, completionRate = 1.0},
    }
    local runs = Concat(Repeat(3, {}), Repeat(2, {duration = 1900}))
    local rec = Find(Build(runs, {synergyPairs = pairList}), "GROUP")
    AssertContains(rec.headline, "Push keys with Pal: timed 100% together")
    AssertContains(rec.detail, "vs a 60% timed rate overall")
end)

test("warns about a slide only when key level and timed rate both drop", function()
    local slipping = {
        deltaTimedLevel = -1, deltaCompletionRate = -0.2,
        first = {runCount = 5, completionRate = 0.8, avgTimedLevel = 14},
        last = {runCount = 5, completionRate = 0.6, avgTimedLevel = 13},
    }
    AssertContains(Find(Build(Repeat(4, {}), {overallTrend = slipping}), "TREND").headline, "down 20 points")
    local mixed = {deltaTimedLevel = -1, deltaCompletionRate = 0.1, first = {}, last = {}}
    assert(not Find(Build(Repeat(4, {}), {overallTrend = mixed}), "TREND"))
end)

test("never returns more than six recommendations", function()
    local runs = Concat(
        Repeat(3, {duration = 1830, timeLost = 45, deathCount = 3}),
        Repeat(3, {dungeonName = "Bravo", completed = false, abandonReason = "abandon"}),
        Repeat(3, {dungeonName = "Charlie", duration = 1830}),
        Repeat(5, {keystoneLevel = 9}))
    local gaps = {
        {key = "dps", role = "DAMAGER", ownerAvg = 1, teammateAvg = 2, ratioToTeam = 0.5, belowRate = 1, comparedRuns = 9},
        {key = "deaths", role = "DAMAGER", ownerAvg = 2, teammateAvg = 1, ratioToTeam = 0.5, belowRate = 1, comparedRuns = 9},
    }
    local slipping = {deltaTimedLevel = -1, deltaCompletionRate = -0.2, first = {}, last = {}}
    local recs = Build(runs, {underperformingMetrics = gaps, overallTrend = slipping,
        synergyPairs = {{pair = "Me + Pal", runs = 9, completionRate = 1}}})
    assert(#recs == 6, "expected 6, got " .. #recs)
    assert(recs[1].category == "SURVIVAL", "deaths come first")
end)

print(string.format("%d passed, %d failed", passed, failures))
os.exit(failures == 0 and 0 or 1)
