-- StormsDungeonData - Insights advisor
-- Builds the Insights page recommendations. Each one is tied to an outcome (timed keys or
-- rating) and carries the evidence behind it. Pure data logic, no frames, so it can be
-- tested offline (tests/insights_advisor_test.lua).

local MPT = StormsDungeonData
local Advisor = {}
MPT.InsightsAdvisor = Advisor

local MIN_DUNGEON_RUNS = 3
local MIN_LEVEL_ATTEMPTS = 3
local MIN_GROUP_RUNS = 4
local MIN_TIMED_DUNGEONS_FOR_RATING = 3
local FOCUS_FAIL_RATE = 0.25
local NEAR_MISS_SECONDS = 60
local COMFORT_RATE = 0.6
local WALL_RATE = 0.4
local RATING_LAG_LEVELS = 2
local GROUP_RATE_EDGE = 0.15
local DEATH_DEPLETE_SHARE = 0.4
local EVEN_DEATH_SHARE = 0.2
local HIGH_DEATH_SHARE = 0.25
local MAX_RECOMMENDATIONS = 6
-- ratioToTeam is direction-aware (below 1 means behind), so 0.9 means at least 10% behind
local MAX_GAP_RATIO = 0.9

local ROLE_NOUNS = {DAMAGER = "DPS", HEALER = "healers", TANK = "tanks"}

-- Gaps worth acting on, by role. Raw damage/healing volume is left out on purpose: it
-- tracks pull size and incoming damage more than it tracks whether the key gets timed.
local GAP_ADVICE = {
    dps = {
        roles = {DAMAGER = true},
        label = "DPS",
        advice = "Check uptime on priority targets and line cooldowns up with the big pulls.",
    },
    interrupts = {
        roles = {DAMAGER = true, TANK = true},
        label = "Interrupts",
        perRun = true,
        advice = "Claim a kick target on every pull.",
    },
    deaths = {
        roles = {DAMAGER = true, HEALER = true, TANK = true},
        label = "Deaths",
        perRun = true,
        decimals = true,
        advice = "Every death adds to the timer; save a defensive for the pulls you die on.",
    },
    avoidableDamageTaken = {
        roles = {DAMAGER = true, HEALER = true, TANK = true},
        label = "Avoidable damage",
        perRun = true,
        advice = "That damage is dodgeable; it's free healer mana and fewer deaths.",
    },
}

local function Pct(value)
    return math.floor((value or 0) * 100 + 0.5)
end

local function Ratio(a, b)
    if not b or b == 0 then
        return 0
    end
    return a / b
end

local function FormatSeconds(seconds)
    local s = math.floor((seconds or 0) + 0.5)
    if s >= 60 then
        return string.format("%dm %02ds", math.floor(s / 60), s % 60)
    end
    return string.format("%ds", s)
end

local function FormatCompact(value, decimals)
    local n = tonumber(value) or 0
    if decimals then
        return string.format("%.1f", n)
    end
    local absN = math.abs(n)
    if absN >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif absN >= 1000 then
        return string.format("%.0fK", n / 1000)
    end
    return string.format("%.1f", n)
end

local function Recommendation(category, headline, detail)
    return {category = category, headline = headline, detail = detail}
end

local function IsAbandoned(run)
    return run.abandonReason == "abandon" or run.completed == false
end

-- outcome is "timed", "abandoned" or "overtime". Over-time runs also carry the margin they
-- missed by, and whether the death penalty alone was bigger than that margin.
local function ClassifyRun(run, ctx)
    if IsAbandoned(run) then
        return {outcome = "abandoned"}
    end
    if not ctx.isFailed(run) then
        return {outcome = "timed"}
    end
    local info = {outcome = "overtime"}
    local limit = ctx.getTimeLimit(run)
    local duration = ctx.getDuration(run)
    if limit and limit > 0 and duration and duration > limit then
        info.margin = duration - limit
        local penalty = tonumber(run.timeLost) or 0
        info.deathCaused = penalty > 0 and penalty >= info.margin
        info.nearMiss = info.margin <= NEAR_MISS_SECONDS
    end
    return info
end

local function ClassifyAll(runs, ctx)
    local classByRun = {}
    for _, run in ipairs(runs) do
        classByRun[run] = ClassifyRun(run, ctx)
    end
    return classByRun
end

local function TimedRate(runs, classByRun)
    local timed = 0
    for _, run in ipairs(runs) do
        if classByRun[run].outcome == "timed" then
            timed = timed + 1
        end
    end
    return Ratio(timed, #runs)
end

local function CollectDeathStats(runs, ctx, classByRun)
    local stats = {overtime = 0, deathCaused = 0, partyDeaths = 0, ownerDeaths = 0, penaltySum = 0, deathSum = 0}
    for _, run in ipairs(runs) do
        local class = classByRun[run]
        local deaths = tonumber(run.deathCount) or 0
        if deaths > 0 then
            stats.penaltySum = stats.penaltySum + (tonumber(run.timeLost) or 0)
            stats.deathSum = stats.deathSum + deaths
        end
        if class.outcome == "overtime" then
            stats.overtime = stats.overtime + 1
            if class.deathCaused then
                stats.deathCaused = stats.deathCaused + 1
            end
        end
        local owner = class.outcome ~= "timed" and ctx.getOwnerStats(run) or nil
        if owner and deaths > 0 then
            stats.partyDeaths = stats.partyDeaths + deaths
            stats.ownerDeaths = stats.ownerDeaths + math.min(tonumber(owner.deaths) or 0, deaths)
        end
    end
    return stats
end

local function AnalyzeSurvival(runs, ctx, classByRun)
    local s = CollectDeathStats(runs, ctx, classByRun)
    if s.overtime < 2 or s.deathCaused < 2 or Ratio(s.deathCaused, s.overtime) < DEATH_DEPLETE_SHARE then
        return nil
    end
    local detail = string.format(
        "In those runs the death penalty (about %s per death this season) was bigger than the amount you missed the timer by.",
        FormatSeconds(Ratio(s.penaltySum, s.deathSum)))
    local share = Ratio(s.ownerDeaths, s.partyDeaths)
    if s.partyDeaths >= 5 and share > HIGH_DEATH_SHARE then
        detail = detail .. string.format(
            " You took %d%% of the party's deaths in failed keys (an even share is %d%%), so start with your own defensives.",
            Pct(share), Pct(EVEN_DEATH_SHARE))
    elseif s.partyDeaths >= 5 then
        detail = detail .. string.format(
            " Your share of party deaths in failed keys is %d%%, so plan group defensives for the pulls that wipe.",
            Pct(share))
    end
    return Recommendation("SURVIVAL",
        string.format("Deaths cost you %d of %d over-time keys", s.deathCaused, s.overtime), detail)
end

local function NewDungeonBucket(name)
    return {name = name, runs = 0, timed = 0, abandoned = 0, overtime = 0,
        deathCaused = 0, nearMiss = 0, marginSum = 0, marginCount = 0,
        abandonForcesSum = 0, abandonDeathsSum = 0}
end

local function AddToDungeonBucket(d, class, run)
    d.runs = d.runs + 1
    if class.outcome == "timed" then
        d.timed = d.timed + 1
    elseif class.outcome == "abandoned" then
        d.abandoned = d.abandoned + 1
        d.abandonForcesSum = d.abandonForcesSum + (tonumber(run.overallMobPercentage) or 0)
        d.abandonDeathsSum = d.abandonDeathsSum + (tonumber(run.deathCount) or 0)
    else
        d.overtime = d.overtime + 1
        if class.deathCaused then d.deathCaused = d.deathCaused + 1 end
        if class.nearMiss then d.nearMiss = d.nearMiss + 1 end
        if class.margin then
            d.marginSum = d.marginSum + class.margin
            d.marginCount = d.marginCount + 1
        end
    end
end

-- Dungeons worth practicing, most failed keys first.
local function RankFocusDungeons(runs, classByRun)
    local byName = {}
    for _, run in ipairs(runs) do
        local name = run.dungeonName or "Unknown"
        byName[name] = byName[name] or NewDungeonBucket(name)
        AddToDungeonBucket(byName[name], classByRun[run], run)
    end
    local list = {}
    for _, d in pairs(byName) do
        d.failed = d.runs - d.timed
        d.failRate = Ratio(d.failed, d.runs)
        if d.runs >= MIN_DUNGEON_RUNS and d.failRate >= FOCUS_FAIL_RATE then
            table.insert(list, d)
        end
    end
    table.sort(list, function(a, b)
        if a.failed ~= b.failed then return a.failed > b.failed end
        if a.failRate ~= b.failRate then return a.failRate > b.failRate end
        return a.name < b.name
    end)
    return list
end

local function DiagnoseDungeon(d)
    if d.abandoned * 2 >= d.failed then
        return string.format(
            "%d of %d failed keys here were abandoned, on average at %d%% enemy forces with %.1f deaths. The key dies early, so fix the first wipe before the route.",
            d.abandoned, d.failed, math.floor(Ratio(d.abandonForcesSum, d.abandoned) + 0.5),
            Ratio(d.abandonDeathsSum, d.abandoned))
    end
    if d.overtime > 0 and d.deathCaused * 2 >= d.overtime then
        return string.format(
            "In %d of %d over-time runs the death penalty was bigger than the miss. Survive the dangerous pulls and this one times.",
            d.deathCaused, d.overtime)
    end
    if d.overtime > 0 and d.nearMiss * 2 >= d.overtime then
        return string.format(
            "%d of %d over-time runs missed by under a minute. Cut one pack or merge two pulls in the route.",
            d.nearMiss, d.overtime)
    end
    if d.marginCount > 0 then
        return string.format(
            "Over-time runs missed by %s on average without deaths being the cause, so it's pace: a tighter route or more trash damage.",
            FormatSeconds(Ratio(d.marginSum, d.marginCount)))
    end
    return string.format("%d failed keys here. Open one on the Runs page to see where the time went.", d.failed)
end

local function FocusRecommendation(d)
    return Recommendation("FOCUS",
        string.format("Practice %s: timed %d of %d (%d%%)", d.name, d.timed, d.runs, Pct(Ratio(d.timed, d.runs))),
        DiagnoseDungeon(d))
end

-- The character the per-character advice is about: the filtered one, otherwise the one
-- with the most runs in the season.
local function PickFocusCharacter(runs, ctx)
    local byKey, order = {}, {}
    for _, run in ipairs(runs) do
        local key, name = ctx.characterKey(run)
        if not byKey[key] then
            byKey[key] = {key = key, name = name or "Unknown", runs = {}}
            table.insert(order, key)
        end
        table.insert(byKey[key].runs, run)
    end
    local best = nil
    for _, key in ipairs(order) do
        local c = byKey[key]
        if not best or #c.runs > #best.runs then
            best = c
        end
    end
    return best
end

local function BuildLevelTable(charRuns, classByRun)
    local byLevel, levels = {}, {}
    for _, run in ipairs(charRuns) do
        local level = tonumber(run.keystoneLevel or run.dungeonLevel)
        if level and level > 0 then
            if not byLevel[level] then
                byLevel[level] = {level = level, attempts = 0, timed = 0}
                table.insert(levels, byLevel[level])
            end
            local b = byLevel[level]
            b.attempts = b.attempts + 1
            if classByRun[run].outcome == "timed" then
                b.timed = b.timed + 1
            end
        end
    end
    table.sort(levels, function(a, b) return a.level < b.level end)
    for _, b in ipairs(levels) do
        b.rate = Ratio(b.timed, b.attempts)
    end
    return levels
end

local function AnalyzeKeyLevels(character, classByRun)
    local levels = BuildLevelTable(character.runs, classByRun)
    local comfort = nil
    for _, b in ipairs(levels) do
        if b.attempts >= MIN_LEVEL_ATTEMPTS and b.rate >= COMFORT_RATE then
            comfort = b
        end
    end
    if not comfort then
        return nil
    end
    local aboveAttempts = 0
    for _, b in ipairs(levels) do
        if b.level > comfort.level then
            aboveAttempts = aboveAttempts + b.attempts
            if b.attempts >= MIN_LEVEL_ATTEMPTS and b.rate < WALL_RATE then
                return Recommendation("KEY LEVEL",
                    string.format("%s's wall is +%d: timed %d%% there vs %d%% at +%d",
                        character.name, b.level, Pct(b.rate), Pct(comfort.rate), comfort.level),
                    string.format(
                        "%d attempts at +%d so far. Time +%d in every dungeon first, then take +%d into your strongest dungeons.",
                        b.attempts, b.level, comfort.level, b.level))
            end
        end
    end
    if aboveAttempts >= MIN_LEVEL_ATTEMPTS then
        return nil
    end
    local aboveText = aboveAttempts == 0 and "no attempts"
        or string.format("only %d attempt%s", aboveAttempts, aboveAttempts == 1 and "" or "s")
    return Recommendation("KEY LEVEL",
        string.format("%s is ready for +%d", character.name, comfort.level + 1),
        string.format("You time %d%% of +%d keys (%d of %d) and have %s above it.",
            Pct(comfort.rate), comfort.level, comfort.timed, comfort.attempts, aboveText))
end

local function Median(values)
    table.sort(values)
    local n = #values
    if n == 0 then
        return 0
    end
    if n % 2 == 1 then
        return values[(n + 1) / 2]
    end
    return math.floor((values[n / 2] + values[n / 2 + 1]) / 2)
end

local function FindLaggingDungeons(character, classByRun, seasonDungeons, excluded)
    local bestByDungeon = {}
    for _, run in ipairs(character.runs) do
        local level = tonumber(run.keystoneLevel or run.dungeonLevel) or 0
        local name = run.dungeonName or "Unknown"
        if classByRun[run].outcome == "timed" and level > (bestByDungeon[name] or 0) then
            bestByDungeon[name] = level
        end
    end
    local bests = {}
    for _, level in pairs(bestByDungeon) do
        table.insert(bests, level)
    end
    if #bests < MIN_TIMED_DUNGEONS_FOR_RATING then
        return nil
    end
    local typical = Median(bests)
    local lagging = {}
    for _, name in ipairs(seasonDungeons) do
        local best = bestByDungeon[name] or 0
        if best <= typical - RATING_LAG_LEVELS and not excluded[name] then
            table.insert(lagging, {name = name, best = best})
        end
    end
    table.sort(lagging, function(a, b)
        if a.best ~= b.best then return a.best < b.best end
        return a.name < b.name
    end)
    return lagging, typical
end

-- excluded: dungeons already named by a FOCUS recommendation, so the card doesn't repeat itself
local function AnalyzeRating(character, classByRun, seasonDungeons, excluded)
    local lagging, typical = FindLaggingDungeons(character, classByRun, seasonDungeons or {}, excluded or {})
    if not lagging or #lagging == 0 then
        return nil
    end
    local parts = {}
    for i, d in ipairs(lagging) do
        if i > 3 then break end
        table.insert(parts, string.format("%s (%s)", d.name, d.best > 0 and ("+" .. d.best) or "none timed"))
    end
    return Recommendation("RATING",
        string.format("Bring %s up to +%d on %s", lagging[1].name, typical, character.name),
        string.format(
            "Your best timed keys sit around +%d, but these trail: %s. Only your best run per dungeon counts, so these are your cheapest rating points.",
            typical, table.concat(parts, ", ")))
end

local function GapRecommendation(gap)
    local advice = GAP_ADVICE[gap.key]
    local roleNoun = ROLE_NOUNS[gap.role] or "players in your role"
    local unit = advice.perRun and " per run" or ""
    return Recommendation("YOUR PLAY",
        string.format("%s: %s%s vs %s for other %s", advice.label,
            FormatCompact(gap.ownerAvg, advice.decimals), unit,
            FormatCompact(gap.teammateAvg, advice.decimals), roleNoun),
        string.format("Behind in %d%% of %d compared runs. %s",
            Pct(gap.belowRate), gap.comparedRuns or 0, advice.advice))
end

local function AnalyzeGaps(underperformingMetrics, limit)
    local out = {}
    for _, gap in ipairs(underperformingMetrics or {}) do
        local advice = GAP_ADVICE[gap.key]
        if advice and advice.roles[gap.role] and (gap.ratioToTeam or 1) <= MAX_GAP_RATIO then
            table.insert(out, GapRecommendation(gap))
            if #out >= limit then break end
        end
    end
    return out
end

local function AnalyzeGroup(synergyPairs, overallRate)
    local best = nil
    for _, s in ipairs(synergyPairs or {}) do
        if (s.runs or 0) >= MIN_GROUP_RUNS and (s.completionRate or 0) >= overallRate + GROUP_RATE_EDGE then
            if not best or s.completionRate > best.completionRate
                or (s.completionRate == best.completionRate and s.runs > best.runs) then
                best = s
            end
        end
    end
    if not best then
        return nil
    end
    local teammate = tostring(best.pair or ""):match("%+ (.+)$") or best.pair or "Unknown"
    return Recommendation("GROUP",
        string.format("Push keys with %s: timed %d%% together", teammate, Pct(best.completionRate)),
        string.format("%d runs together vs a %d%% timed rate overall. Bring them to your hardest keys.",
            best.runs, Pct(overallRate)))
end

local function AnalyzeTrend(trend)
    if not trend or not trend.first or not trend.last then
        return nil
    end
    if (trend.deltaTimedLevel or 0) >= 0 or (trend.deltaCompletionRate or 0) >= 0 then
        return nil
    end
    return Recommendation("TREND",
        string.format("Timed rate is down %d points in your latest runs", Pct(-trend.deltaCompletionRate)),
        string.format(
            "Latest %d runs: %d%% timed at avg +%.1f. First %d: %d%% at +%.1f. Drop a level to rebuild momentum, then push again.",
            trend.last.runCount or 0, Pct(trend.last.completionRate), trend.last.avgTimedLevel or 0,
            trend.first.runCount or 0, Pct(trend.first.completionRate), trend.first.avgTimedLevel or 0))
end

local function Append(list, rec)
    if rec and #list < MAX_RECOMMENDATIONS then
        table.insert(list, rec)
    end
end

-- ctx fields:
--   runs, seasonDungeons, isFailed, getTimeLimit, getDuration, getOwnerStats, characterKey,
--   underperformingMetrics, synergyPairs, overallTrend
-- Returns a list of {category, headline, detail}, most urgent first.
function Advisor:Build(ctx)
    local runs = ctx.runs or {}
    if #runs == 0 then
        return {}
    end
    local classByRun = ClassifyAll(runs, ctx)
    local focusDungeons = RankFocusDungeons(runs, classByRun)
    local character = PickFocusCharacter(runs, ctx)
    local gaps = AnalyzeGaps(ctx.underperformingMetrics, 2)
    local focusNames = {}
    for i = 1, math.min(2, #focusDungeons) do
        focusNames[focusDungeons[i].name] = true
    end

    local out = {}
    Append(out, AnalyzeSurvival(runs, ctx, classByRun))
    Append(out, focusDungeons[1] and FocusRecommendation(focusDungeons[1]))
    Append(out, character and AnalyzeRating(character, classByRun, ctx.seasonDungeons, focusNames))
    Append(out, character and AnalyzeKeyLevels(character, classByRun))
    for _, rec in ipairs(gaps) do
        Append(out, rec)
    end
    Append(out, focusDungeons[2] and FocusRecommendation(focusDungeons[2]))
    Append(out, AnalyzeGroup(ctx.synergyPairs, TimedRate(runs, classByRun)))
    Append(out, AnalyzeTrend(ctx.overallTrend))
    return out
end
