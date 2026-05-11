-- Mythic Plus Tracker - History Viewer
-- Displays historical data for dungeons and characters

local MPT = StormsDungeonData
local HistoryViewer = {}
MPT.HistoryViewer = HistoryViewer

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, a, b, c, d = pcall(func, ...)
    if not ok then
        return nil
    end
    return a, b, c, d
end

-- Session cache for dungeon time limits so GetMapUIInfo isn't hammered per history row.
-- Only successful lookups are cached; failed lookups are retried so a temporary API
-- unavailability (e.g. first render before data loads) doesn't poison the cache.
local dungeonTimeLimitCache = {}

-- Returns the time limit in seconds for a dungeon via the live API.
-- C_ChallengeMode.GetMapUIInfo returns (name, id, timeLimit, texture, bgTexture, mapID)
-- where timeLimit is in plain seconds: https://warcraft.wiki.gg/wiki/API_C_ChallengeMode.GetMapUIInfo
local function GetDungeonTimeLimitSeconds(mapID)
    if not mapID then
        return nil
    end
    -- Only return the cached value when we actually have a positive number
    local cached = dungeonTimeLimitCache[mapID]
    if cached and cached > 0 then
        return cached
    end
    if not C_ChallengeMode or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        return nil
    end
    local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    timeLimit = tonumber(timeLimit)
    if not timeLimit or timeLimit <= 0 then
        -- Don't cache failures; retry on next call
        return nil
    end
    -- API always returns seconds; cache and return
    dungeonTimeLimitCache[mapID] = timeLimit
    return timeLimit
end

local function NormalizeRunDurationSeconds(duration)
    duration = tonumber(duration)
    if not duration or duration <= 0 then
        return 0
    end
    -- Stored duration should be seconds; guard against accidental millisecond values
    if duration > 100000 then
        return math.floor(duration / 1000)
    end
    return math.floor(duration)
end

-- True if the run was NOT completed within the dungeon time limit.
-- Primary determination: compare stored duration against the time limit fetched live from
-- C_ChallengeMode.GetMapUIInfo.  This is the most reliable method, especially in
-- Midnight (WoW 12.0+) where keystoneUpgrades was removed and is always 0 for every run
-- regardless of whether it was timed -- making upgrades-based inference completely wrong.
local function RunIsFailed(run)
    -- Dungeon was never finished
    if run.completed == false then
        return true
    end

    -- Authoritative check: duration vs the live API time limit
    local mapID = run.dungeonID or run.dungeonId
    local duration = NormalizeRunDurationSeconds(run.duration)
    if mapID and duration > 0 then
        local timeLimit = GetDungeonTimeLimitSeconds(mapID)
        if timeLimit and timeLimit > 0 then
            return duration > timeLimit
        end
    end

    -- Fallback only when the API cannot supply a time limit (older/different-patch mapIDs)
    if run.onTime ~= nil then
        return run.onTime ~= true
    end

    -- Cannot determine; treat a finished run as timed rather than guessing wrong
    return false
end

-- Helper function to set backdrop compatibility with WoW 12.0+
local function SetBackdropCompat(frame, backdropInfo, backdropColor, backdropBorderColor)
    if frame.SetBackdrop then
        -- Legacy API (pre-12.0)
        frame:SetBackdrop(backdropInfo)
        if backdropColor then
            frame:SetBackdropColor(backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4])
        end
        if backdropBorderColor then
            frame:SetBackdropBorderColor(backdropBorderColor[1], backdropBorderColor[2], backdropBorderColor[3], backdropBorderColor[4])
        end
    elseif frame.SetBackdropInfo then
        -- New API (WoW 12.0+)
        frame:SetBackdropInfo(backdropInfo)
        if backdropColor then
            frame:SetBackdropColor(backdropColor[1], backdropColor[2], backdropColor[3], backdropColor[4])
        end
        if backdropBorderColor then
            frame:SetBackdropBorderColor(backdropBorderColor[1], backdropBorderColor[2], backdropBorderColor[3], backdropBorderColor[4])
        end
    end
end

HistoryViewer.selectedCharacter = nil
HistoryViewer.selectedDungeon = nil
HistoryViewer.selectedDungeonName = nil
HistoryViewer.selectedKeystoneLevel = nil
HistoryViewer.selectedResult = nil
HistoryViewer.selectedRole = nil
-- Multi-select storage (tables instead of single values)
HistoryViewer.selectedDungeons = {}  -- {[dungeonID] = true}
HistoryViewer.selectedKeystoneLevels = {}  -- {[level] = true}
HistoryViewer.selectedResults = {}  -- {[true/false] = true}
-- Hierarchical class/spec/hero filters
HistoryViewer.selectedClassSpecHero = {
    classes = {},      -- {["SHAMAN"] = true}
    specs = {},        -- {["Enhancement"] = true}
    heroTalents = {}   -- {["Stormbringer"] = true}
}
HistoryViewer.selectedSeasonFilter = nil -- e.g. "season:15", "unknown"
HistoryViewer.activePage = "history"

local EXPANSION_ABBREV_BY_LEVEL = {
    [7] = "BFA",
    [8] = "SL",
    [9] = "DF",
    [10] = "TWW",
    [11] = "Midnight",
}

local function ToNumberOrNil(value)
    local n = tonumber(value)
    if n then
        return n
    end
    return nil
end

local function ResolvePerSecondMetric(stats, storedKey, totalKey, runDuration)
    if type(stats) ~= "table" then
        return 0
    end

    local stored = tonumber(stats[storedKey])
    if stored ~= nil then
        return math.floor(stored)
    end

    local total = tonumber(stats[totalKey]) or 0
    local duration = tonumber(runDuration) or 0
    if duration > 0 and total > 0 then
        return math.floor(total / duration)
    end

    return 0
end

local function GetDamagePerSecond(stats, runDuration)
    return ResolvePerSecondMetric(stats, "damagePerSecond", "damage", runDuration)
end

local function GetHealingPerSecond(stats, runDuration)
    return ResolvePerSecondMetric(stats, "healingPerSecond", "healing", runDuration)
end

local function GetRunSeasonID(run)
    if not run then return nil end
    return ToNumberOrNil(run.seasonID)
        or ToNumberOrNil(run.seasonId)
        or ToNumberOrNil(run.mythicPlusSeason)
        or ToNumberOrNil(run.season)
end

local function GetRunExpansionLevel(run)
    if not run then return nil end
    return ToNumberOrNil(run.expansionLevel)
end

local function GetRunExpansionAbbrev(run)
    if not run then return nil end
    if type(run.expansionAbbrev) == "string" and run.expansionAbbrev ~= "" then
        return run.expansionAbbrev
    end
    local level = GetRunExpansionLevel(run)
    if level and EXPANSION_ABBREV_BY_LEVEL[level] then
        return EXPANSION_ABBREV_BY_LEVEL[level]
    end
    return nil
end

local function BuildCurrentSeasonContext()
    local ctx = {
        currentSeasonID = nil,
        currentSeasonMaps = {},
        hasSignal = false,
    }

    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" then
        ctx.currentSeasonID = SafeCall(C_MythicPlus.GetCurrentSeason)
    end

    if C_ChallengeMode and type(C_ChallengeMode.GetMapTable) == "function" then
        local mapTable = C_ChallengeMode.GetMapTable()
        if type(mapTable) == "table" then
            for _, mapID in ipairs(mapTable) do
                if mapID then
                    ctx.currentSeasonMaps[mapID] = true
                end
            end
        end
    end

    ctx.hasSignal = (ctx.currentSeasonID ~= nil) or (next(ctx.currentSeasonMaps) ~= nil)
    return ctx
end

local function InferExpansionAndNumberFromSeasonID(seasonID)
    if not seasonID then
        return nil, nil
    end
    if seasonID >= 17 then
        return "Midnight", seasonID - 16
    elseif seasonID >= 13 then
        return "TWW", seasonID - 12
    elseif seasonID >= 9 then
        return "DF", seasonID - 8
    elseif seasonID >= 5 then
        return "SL", seasonID - 4
    elseif seasonID >= 1 then
        return "BFA", seasonID
    end
    return nil, nil
end

local function GetSeasonNumberForExpansion(seasonID, expansionAbbrev)
    if not seasonID then
        return nil
    end
    local abbrev = (type(expansionAbbrev) == "string" and expansionAbbrev:upper()) or nil
    if abbrev == "MIDNIGHT" then
        if seasonID >= 17 then return seasonID - 16 end
        return nil
    elseif abbrev == "TWW" then
        if seasonID >= 13 and seasonID <= 16 then return seasonID - 12 end
        return nil
    elseif abbrev == "DF" then
        if seasonID >= 9 and seasonID <= 12 then return seasonID - 8 end
        return nil
    elseif abbrev == "SL" then
        if seasonID >= 5 and seasonID <= 8 then return seasonID - 4 end
        return nil
    elseif abbrev == "BFA" then
        if seasonID >= 1 and seasonID <= 4 then return seasonID end
        return nil
    end
    return nil
end

local function BuildSeasonLabel(seasonID, expansionAbbrev)
    if seasonID then
        local abbrev = (type(expansionAbbrev) == "string" and expansionAbbrev:upper()) or nil
        local seasonNumber = abbrev and GetSeasonNumberForExpansion(seasonID, abbrev) or nil
        if (not abbrev) or (not seasonNumber) then
            local inferredAbbrev, inferredNumber = InferExpansionAndNumberFromSeasonID(seasonID)
            if not abbrev then
                abbrev = inferredAbbrev
            end
            if not seasonNumber then
                seasonNumber = inferredNumber
            end
        end
        if abbrev and seasonNumber then
            return string.format("%s: Season %d", abbrev, seasonNumber)
        end
        return string.format("Season %d", seasonID)
    end
    return "Unknown Season"
end

function HistoryViewer:GetSeasonKeyForRun(run, context)
    context = context or BuildCurrentSeasonContext()
    local runSeasonID = GetRunSeasonID(run)
    if runSeasonID then
        return "season:" .. tostring(runSeasonID), runSeasonID
    end

    -- Legacy runs without stored season metadata are treated as current-season runs.
    -- This keeps catalog building and display filtering consistent.
    if context.currentSeasonID then
        return "season:" .. tostring(context.currentSeasonID), context.currentSeasonID
    end

    return "unknown", nil
end

function HistoryViewer:BuildSeasonCatalog()
    local context = BuildCurrentSeasonContext()
    local allRunsRaw = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    local byKey = {}
    local currentKey = context.currentSeasonID and ("season:" .. tostring(context.currentSeasonID)) or nil

    local function EnsureEntry(key, seasonID)
        if not byKey[key] then
            byKey[key] = {
                key = key,
                seasonID = seasonID,
                runs = {},
                runCount = 0,
                expansionAbbrev = nil,
                sortSeasonID = seasonID or -1,
            }
        end
        return byKey[key]
    end

    for _, run in ipairs(allRunsRaw) do
        if not run.deleted then
            local key, seasonID = self:GetSeasonKeyForRun(run, context)
            local entry = EnsureEntry(key, seasonID)
            entry.runCount = entry.runCount + 1
            table.insert(entry.runs, run)
            if not entry.expansionAbbrev then
                entry.expansionAbbrev = GetRunExpansionAbbrev(run)
            end
        end
    end

    if context.currentSeasonID then
        EnsureEntry(currentKey, context.currentSeasonID)
        local currentExpansionLevel = (type(GetExpansionLevel) == "function") and GetExpansionLevel() or nil
        if currentExpansionLevel and byKey[currentKey] then
            byKey[currentKey].expansionAbbrev = EXPANSION_ABBREV_BY_LEVEL[currentExpansionLevel]
        end
    end

    for _, entry in pairs(byKey) do
        entry.label = BuildSeasonLabel(entry.seasonID, entry.expansionAbbrev)
    end

    local ordered = {}
    for _, entry in pairs(byKey) do
        table.insert(ordered, entry)
    end
    table.sort(ordered, function(a, b)
        if a.key == currentKey then return true end
        if b.key == currentKey then return false end
        if a.sortSeasonID ~= b.sortSeasonID then
            return a.sortSeasonID > b.sortSeasonID
        end
        return a.label < b.label
    end)

    return {
        byKey = byKey,
        ordered = ordered,
        currentKey = currentKey,
    }
end

function HistoryViewer:RunMatchesSeasonFilter(run, seasonKey, context)
    if not seasonKey then
        return true
    end
    context = context or BuildCurrentSeasonContext()
    local runKey = self:GetSeasonKeyForRun(run, context)
    return runKey == seasonKey
end

local function GetCharacterKey(run)
    local name = (run and run.character) or "Unknown"
    local realm = (run and run.realm) or "Unknown"
    return name .. "-" .. realm, name, realm
end

local function AverageFromSum(sum, count)
    if not count or count == 0 then
        return 0
    end
    return sum / count
end

function HistoryViewer:GetSeasonRuns()
    local seasonCatalog = self:BuildSeasonCatalog()
    local seasonRuns = {}
    local selected = self.selectedSeasonFilter and seasonCatalog.byKey[self.selectedSeasonFilter]
    if selected and selected.runs then
        for _, run in ipairs(selected.runs) do
            if not run.deleted then
                table.insert(seasonRuns, run)
            end
        end
    end
    return seasonRuns
end

local function ShortName(fullName)
    if type(fullName) ~= "string" then
        return "Unknown"
    end
    return fullName:match("^([^%-]+)") or fullName
end

local function NormalizePlayerName(name)
    if type(name) ~= "string" then
        return nil
    end
    local trimmed = name:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then
        return nil
    end
    return trimmed:lower()
end

local function GetAvoidableDamageValue(playerStats)
    if type(playerStats) ~= "table" then
        return 0
    end
    return playerStats.avoidableDamageTaken
        or playerStats.avoidableDamage
        or playerStats.avoidable
        or 0
end

local function GetOwnerStats(run)
    if not run then
        return nil
    end

    local ownerName = run.character
    if not ownerName then
        return nil
    end

    local ownerShort = ShortName(ownerName)
    local ownerFull = ownerName
    if run.realm and type(run.realm) == "string" and run.realm ~= "" and not ownerName:find("%-", 1, true) then
        ownerFull = ownerName .. "-" .. run.realm
    end

    local ownerNameNorm = NormalizePlayerName(ownerName)
    local ownerShortNorm = NormalizePlayerName(ownerShort)
    local ownerFullNorm = NormalizePlayerName(ownerFull)

    local function IsOwnerName(playerName)
        local nameNorm = NormalizePlayerName(playerName)
        if not nameNorm then
            return false
        end
        if nameNorm == ownerNameNorm or nameNorm == ownerShortNorm or nameNorm == ownerFullNorm then
            return true
        end

        local shortNorm = NormalizePlayerName(ShortName(playerName))
        return shortNorm and (shortNorm == ownerNameNorm or shortNorm == ownerShortNorm)
    end

    if run.players then
        for _, p in ipairs(run.players) do
            if p and IsOwnerName(p.name) then
                p.avoidableDamageTaken = GetAvoidableDamageValue(p)
                return p
            end
        end
    end

    if run.playerStats then
        for key, p in pairs(run.playerStats) do
            local candidateName = (type(p) == "table" and p.name) or key
            if IsOwnerName(candidateName) and type(p) == "table" then
                if not p.name and type(key) == "string" then
                    p.name = key
                end
                p.avoidableDamageTaken = GetAvoidableDamageValue(p)
                return p
            end
        end
    end

    return nil
end

local function ComputeImprovementFromRuns(runs)
    if not runs or #runs < 4 then
        return nil
    end

    local ordered = {}
    for _, run in ipairs(runs) do
        if run and not run.deleted then
            table.insert(ordered, run)
        end
    end
    if #ordered < 4 then
        return nil
    end

    table.sort(ordered, function(a, b)
        return (a.timestamp or 0) < (b.timestamp or 0)
    end)

    local window = math.max(2, math.floor(#ordered / 3))

    local function ComputeWindowStats(startIndex, endIndex)
        local total = 0
        local completed = 0
        local levelSum = 0
        local durationSum = 0
        local durationCount = 0
        local damageSum = 0
        local healingSum = 0
        local interruptsSum = 0
        local dispelsSum = 0
        local deathsSum = 0
        local avoidableSum = 0
        local totalDuration = 0
        local dpsSum = 0
        local hpsSum = 0
        local dpsCount = 0
        local hpsCount = 0

        for i = startIndex, endIndex do
            local run = ordered[i]
            if run then
                total = total + 1
                local level = run.keystoneLevel or run.dungeonLevel or 0
                if not RunIsFailed(run) then
                    completed = completed + 1
                    levelSum = levelSum + level
                    if run.duration and run.duration > 0 then
                        durationSum = durationSum + run.duration
                        durationCount = durationCount + 1
                        totalDuration = totalDuration + run.duration
                    end
                end
                -- Get owner stats for this run
                local ownerStats = GetOwnerStats(run)
                if ownerStats then
                    damageSum = damageSum + (ownerStats.damage or 0)
                    healingSum = healingSum + (ownerStats.healing or 0)
                    interruptsSum = interruptsSum + (ownerStats.interrupts or 0)
                    dispelsSum = dispelsSum + (ownerStats.dispels or 0)
                    deathsSum = deathsSum + (ownerStats.deaths or 0)
                    avoidableSum = avoidableSum + (ownerStats.avoidableDamageTaken or 0)
                    dpsSum = dpsSum + GetDamagePerSecond(ownerStats, run.duration)
                    hpsSum = hpsSum + GetHealingPerSecond(ownerStats, run.duration)
                    dpsCount = dpsCount + 1
                    hpsCount = hpsCount + 1
                end
            end
        end

        return {
            runCount = total,
            completionRate = (total > 0) and (completed / total) or 0,
            avgTimedLevel = AverageFromSum(levelSum, completed),
            avgTimedDuration = AverageFromSum(durationSum, durationCount),
            avgDamage = total > 0 and (damageSum / total) or 0,
            avgHealing = total > 0 and (healingSum / total) or 0,
            avgInterrupts = total > 0 and (interruptsSum / total) or 0,
            avgDispels = total > 0 and (dispelsSum / total) or 0,
            avgDeaths = total > 0 and (deathsSum / total) or 0,
            avgAvoidable = total > 0 and (avoidableSum / total) or 0,
            avgDPS = AverageFromSum(dpsSum, dpsCount),
            avgHPS = AverageFromSum(hpsSum, hpsCount),
        }
    end

    local firstStats = ComputeWindowStats(1, window)
    local lastStats = ComputeWindowStats(#ordered - window + 1, #ordered)

    return {
        first = firstStats,
        last = lastStats,
        deltaCompletionRate = lastStats.completionRate - firstStats.completionRate,
        deltaTimedLevel = lastStats.avgTimedLevel - firstStats.avgTimedLevel,
        deltaTimedDuration = firstStats.avgTimedDuration - lastStats.avgTimedDuration,
        deltaDPS = lastStats.avgDPS - firstStats.avgDPS,
        deltaHPS = lastStats.avgHPS - firstStats.avgHPS,
        deltaInterrupts = lastStats.avgInterrupts - firstStats.avgInterrupts,
        deltaDispels = lastStats.avgDispels - firstStats.avgDispels,
        deltaDeaths = firstStats.avgDeaths - lastStats.avgDeaths,
        deltaAvoidable = firstStats.avgAvoidable - lastStats.avgAvoidable,
    }
end

function HistoryViewer:BuildInsightsData()
    local runs = self:GetSeasonRuns()
    if not runs or #runs == 0 then
        return nil
    end

    -- Insights can be scoped to a single character via Character filter.
    if self.selectedCharacter then
        local selectedName, selectedRealm = strsplit("-", self.selectedCharacter)
        local scoped = {}
        for _, run in ipairs(runs) do
            if run.character == selectedName and run.realm == selectedRealm then
                table.insert(scoped, run)
            end
        end
        runs = scoped
        if #runs == 0 then
            return nil
        end
    end

    local dungeons = {}
    local characters = {}
    local bestByDungeonCharacter = {}
    local runsByCharacter = {}
    local roleStats = {}
    local dungeonPain = {}
    local dungeonPainWeekly = {}
    local synergy = {}
    local weeklyByOverall = {}
    local weeklyByCharacter = {}
    local pbFeed = {}
    local teammateGapByMetric = {}
    local roleMetricBaselines = {}
    local scoreGained7dByCharacter = {}

    local sparkChars = {" ", ".", ":", "-", "=", "+", "*", "#", "%", "@"}

    local metricDefs = {
        { key = "damage", label = "Damage", getter = function(p, runDuration)
            return p and (p.damage or 0) or 0
        end },
        { key = "dps", label = "DPS", getter = function(p, runDuration)
            return GetDamagePerSecond(p, runDuration)
        end },
        { key = "healing", label = "Healing", getter = function(p, runDuration)
            return p and (p.healing or 0) or 0
        end },
        { key = "hps", label = "HPS", getter = function(p, runDuration)
            return GetHealingPerSecond(p, runDuration)
        end },
        { key = "interrupts", label = "Interrupts", getter = function(p, runDuration)
            return p and (p.interrupts or 0) or 0
        end },
        { key = "dispels", label = "Dispels", getter = function(p, runDuration)
            return p and (p.dispels or 0) or 0
        end },
        { key = "deaths", label = "Deaths", inverseMetric = true, getter = function(p, runDuration)
            return p and (p.deaths or 0) or 0
        end },
        { key = "avoidableDamageTaken", label = "Avoidable Dmg", inverseMetric = true, getter = function(p, runDuration)
            return p and (p.avoidableDamageTaken or 0) or 0
        end },
    }
    local metricGettersByKey = {}
    for _, metric in ipairs(metricDefs) do
        metricGettersByKey[metric.key] = metric.getter
    end

    local roleMetricWhitelist = {
        DAMAGER = {damage = true, dps = true, interrupts = true, dispels = true, deaths = true, avoidableDamageTaken = true},
        HEALER = {healing = true, hps = true, interrupts = true, dispels = true, deaths = true, avoidableDamageTaken = true},
        TANK = {damage = true, dps = true, interrupts = true, dispels = true, deaths = true, avoidableDamageTaken = true},
    }

    local function GetWeekKey(ts)
        local stamp = ts or time()
        local year = tonumber(date("%Y", stamp)) or 0
        local week = tonumber(date("%W", stamp)) or 0
        return string.format("%04d-%02d", year, week)
    end

    local function AddWeeklyPoint(target, run, failed, level)
        local key = GetWeekKey(run.timestamp)
        target[key] = target[key] or {
            key = key,
            runs = 0,
            timedRuns = 0,
            timedLevelSum = 0,
        }
        local row = target[key]
        row.runs = row.runs + 1
        if not failed then
            row.timedRuns = row.timedRuns + 1
            row.timedLevelSum = row.timedLevelSum + (level or 0)
        end
    end

    local function BuildTimeline(weeklyMap)
        local timeline = {}
        for _, row in pairs(weeklyMap) do
            row.avgTimedLevel = AverageFromSum(row.timedLevelSum, row.timedRuns)
            row.completionRate = AverageFromSum(row.timedRuns, row.runs)
            table.insert(timeline, row)
        end
        table.sort(timeline, function(a, b) return a.key < b.key end)

        local minLevel, maxLevel = nil, nil
        local values = {}
        for _, row in ipairs(timeline) do
            local v = row.avgTimedLevel or 0
            table.insert(values, v)
            if not minLevel or v < minLevel then minLevel = v end
            if not maxLevel or v > maxLevel then maxLevel = v end
        end

        local spark = ""
        if #values > 0 then
            for _, v in ipairs(values) do
                local idx = 1
                if maxLevel and minLevel and maxLevel > minLevel then
                    local normalized = (v - minLevel) / (maxLevel - minLevel)
                    idx = math.floor(normalized * (#sparkChars - 1)) + 1
                end
                if idx < 1 then idx = 1 end
                if idx > #sparkChars then idx = #sparkChars end
                spark = spark .. sparkChars[idx]
            end
        end

        return {
            points = timeline,
            spark = spark,
        }
    end

    local function ComputeSummary(runsList)
        local out = {
            totalRuns = 0,
            timedRuns = 0,
            timedLevelSum = 0,
            timedDurationSum = 0,
            timedDurationCount = 0,
        }
        for _, run in ipairs(runsList or {}) do
            local failed = RunIsFailed(run)
            local level = run.keystoneLevel or run.dungeonLevel or 0
            out.totalRuns = out.totalRuns + 1
            if not failed then
                out.timedRuns = out.timedRuns + 1
                out.timedLevelSum = out.timedLevelSum + level
                if run.duration and run.duration > 0 then
                    out.timedDurationSum = out.timedDurationSum + run.duration
                    out.timedDurationCount = out.timedDurationCount + 1
                end
            end
        end
        out.avgTimedLevel = AverageFromSum(out.timedLevelSum, out.timedRuns)
        out.completionRate = AverageFromSum(out.timedRuns, out.totalRuns)
        out.avgTimedDuration = AverageFromSum(out.timedDurationSum, out.timedDurationCount)
        return out
    end

    local function BuildPainRisk(failRate, avgTimeLost, avgDeaths)
        return (failRate * 100) + (avgTimeLost / 30) + (avgDeaths * 2)
    end

    local function GetStartOfDay(ts)
        local stamp = ts or time()
        local t = date("*t", stamp)
        t.hour, t.min, t.sec = 0, 0, 0
        return time(t)
    end

    local function EnsureDungeon(run)
        local dungeonID = run.dungeonID or run.dungeonId or 0
        local dungeonName = run.dungeonName or "Unknown"
        local key = tostring(dungeonID) .. "::" .. dungeonName
        if not dungeons[key] then
            dungeons[key] = {
                key = key,
                id = dungeonID,
                name = dungeonName,
                totalRuns = 0,
                timedRuns = 0,
                timedLevelSum = 0,
                bestTimedLevel = 0,
            }
        end
        return dungeons[key], key
    end

    local function EnsureCharacter(run)
        local charKey, charName, realm = GetCharacterKey(run)
        if not characters[charKey] then
            characters[charKey] = {
                key = charKey,
                name = charName,
                realm = realm,
                class = run.characterClass or run.class or "UNKNOWN",
                totalRuns = 0,
                timedRuns = 0,
                timedLevelSum = 0,
                bestTimedLevel = 0,
                totalDeaths = 0,
                totalAvoidableDamage = 0,
                totalDamage = 0,
                totalHealing = 0,
                totalInterrupts = 0,
                totalDispels = 0,
                totalDuration = 0,
                totalDPS = 0,
                totalHPS = 0,
                dpsSamples = 0,
                hpsSamples = 0,
            }
        end
        if not runsByCharacter[charKey] then
            runsByCharacter[charKey] = {}
        end
        if not weeklyByCharacter[charKey] then
            weeklyByCharacter[charKey] = {}
        end
        return characters[charKey], charKey
    end

    local pbByCharDungeon = {}
    local todayStart = GetStartOfDay(time())
    local scoreWindowStart = todayStart - (6 * 86400)

    for _, run in ipairs(runs) do
        local level = run.keystoneLevel or run.dungeonLevel or 0
        local failed = RunIsFailed(run)
        local dungeon, dungeonKey = EnsureDungeon(run)
        local character, charKey = EnsureCharacter(run)
        local role = run.specRole or "UNKNOWN"
        local ownerStats = GetOwnerStats(run)
        local runTimestamp = run.timestamp or 0

        table.insert(runsByCharacter[charKey], run)
        AddWeeklyPoint(weeklyByOverall, run, failed, level)
        AddWeeklyPoint(weeklyByCharacter[charKey], run, failed, level)

        dungeon.totalRuns = dungeon.totalRuns + 1
        character.totalRuns = character.totalRuns + 1

        roleStats[role] = roleStats[role] or {
            role = role,
            totalRuns = 0,
            timedRuns = 0,
            timedLevelSum = 0,
            bestTimedLevel = 0,
            bestCharacterKey = nil,
            bestCharacterAvg = 0,
            perCharacter = {},
        }
        roleStats[role].totalRuns = roleStats[role].totalRuns + 1

        dungeonPain[dungeonKey] = dungeonPain[dungeonKey] or {
            dungeonName = dungeon.name,
            runs = 0,
            failed = 0,
            timeLostSum = 0,
            deathSum = 0,
            avoidableDamageSum = 0,
        }
        dungeonPain[dungeonKey].runs = dungeonPain[dungeonKey].runs + 1
        dungeonPain[dungeonKey].timeLostSum = dungeonPain[dungeonKey].timeLostSum + (run.timeLost or 0)
        if ownerStats then
            dungeonPain[dungeonKey].deathSum = dungeonPain[dungeonKey].deathSum + (ownerStats.deaths or 0)
            dungeonPain[dungeonKey].avoidableDamageSum = dungeonPain[dungeonKey].avoidableDamageSum + (ownerStats.avoidableDamageTaken or 0)
        end
        if failed then
            dungeonPain[dungeonKey].failed = dungeonPain[dungeonKey].failed + 1
        end

        if runTimestamp and runTimestamp > 0 then
            local weekKey = GetWeekKey(runTimestamp)
            dungeonPainWeekly[dungeonKey] = dungeonPainWeekly[dungeonKey] or {
                dungeonName = dungeon.name,
                weekly = {},
            }
            dungeonPainWeekly[dungeonKey].weekly[weekKey] = dungeonPainWeekly[dungeonKey].weekly[weekKey] or {
                key = weekKey,
                runs = 0,
                failed = 0,
                timeLostSum = 0,
                deathSum = 0,
                avoidableDamageSum = 0,
            }
            local bucket = dungeonPainWeekly[dungeonKey].weekly[weekKey]
            bucket.runs = bucket.runs + 1
            bucket.timeLostSum = bucket.timeLostSum + (run.timeLost or 0)
            if ownerStats then
                bucket.deathSum = bucket.deathSum + (ownerStats.deaths or 0)
                bucket.avoidableDamageSum = bucket.avoidableDamageSum + (ownerStats.avoidableDamageTaken or 0)
            end
            if failed then
                bucket.failed = bucket.failed + 1
            end
        end

        local groupNames = {}
        if run.players then
            for _, p in ipairs(run.players) do
                local s = ShortName(p.name)
                if s and s ~= "" then
                    groupNames[s] = true
                end
            end
        elseif run.groupMembers then
            for _, g in ipairs(run.groupMembers) do
                local s = ShortName(g.name or g)
                if s and s ~= "" then
                    groupNames[s] = true
                end
            end
        end
        local list = {}
        for name in pairs(groupNames) do
            table.insert(list, name)
        end
        table.sort(list)
        local ownerShort = ShortName(character and character.name or run.character)
        if ownerShort and ownerShort ~= "" then
            for _, teammateName in ipairs(list) do
                if teammateName ~= ownerShort then
                    local pairKey = ownerShort .. " + " .. teammateName
                    synergy[pairKey] = synergy[pairKey] or {
                        pair = pairKey,
                        runs = 0,
                        timedRuns = 0,
                        timedLevelSum = 0,
                    }
                    synergy[pairKey].runs = synergy[pairKey].runs + 1
                    if not failed then
                        synergy[pairKey].timedRuns = synergy[pairKey].timedRuns + 1
                        synergy[pairKey].timedLevelSum = synergy[pairKey].timedLevelSum + level
                    end
                end
            end
        end

        if not failed then
            dungeon.timedRuns = dungeon.timedRuns + 1
            dungeon.timedLevelSum = dungeon.timedLevelSum + level
            if level > dungeon.bestTimedLevel then
                dungeon.bestTimedLevel = level
            end

            character.timedRuns = character.timedRuns + 1
            character.timedLevelSum = character.timedLevelSum + level
            if level > character.bestTimedLevel then
                character.bestTimedLevel = level
            end

            roleStats[role].timedRuns = roleStats[role].timedRuns + 1
            roleStats[role].timedLevelSum = roleStats[role].timedLevelSum + level
            if level > roleStats[role].bestTimedLevel then
                roleStats[role].bestTimedLevel = level
            end
            roleStats[role].perCharacter[charKey] = roleStats[role].perCharacter[charKey] or {
                timedRuns = 0,
                timedLevelSum = 0,
            }
            roleStats[role].perCharacter[charKey].timedRuns = roleStats[role].perCharacter[charKey].timedRuns + 1
            roleStats[role].perCharacter[charKey].timedLevelSum = roleStats[role].perCharacter[charKey].timedLevelSum + level

            bestByDungeonCharacter[dungeonKey] = bestByDungeonCharacter[dungeonKey] or {}
            bestByDungeonCharacter[dungeonKey][charKey] = bestByDungeonCharacter[dungeonKey][charKey] or {
                charKey = charKey,
                timedRuns = 0,
                timedLevelSum = 0,
                bestTimedLevel = 0,
            }
            local combo = bestByDungeonCharacter[dungeonKey][charKey]
            combo.timedRuns = combo.timedRuns + 1
            combo.timedLevelSum = combo.timedLevelSum + level
            combo.bestTimedLevel = math.max(combo.bestTimedLevel, level)
        end

        -- Track deaths, avoidable damage, and performance stats for the character
        if ownerStats then
            character.totalDeaths = character.totalDeaths + (ownerStats.deaths or 0)
            character.totalAvoidableDamage = character.totalAvoidableDamage + (ownerStats.avoidableDamageTaken or 0)
            character.totalDamage = character.totalDamage + (ownerStats.damage or 0)
            character.totalHealing = character.totalHealing + (ownerStats.healing or 0)
            character.totalInterrupts = character.totalInterrupts + (ownerStats.interrupts or 0)
            character.totalDispels = character.totalDispels + (ownerStats.dispels or 0)
            character.totalDPS = character.totalDPS + GetDamagePerSecond(ownerStats, run.duration)
            character.totalHPS = character.totalHPS + GetHealingPerSecond(ownerStats, run.duration)
            character.dpsSamples = character.dpsSamples + 1
            character.hpsSamples = character.hpsSamples + 1
        end
        if run.duration and run.duration > 0 then
            character.totalDuration = character.totalDuration + run.duration
        end

        if run.players and #run.players > 0 then
            local duration = run.duration or 0
            for _, p in ipairs(run.players) do
                local pRole = p.role or ((p == ownerStats) and role) or "UNKNOWN"
                if not roleMetricBaselines[pRole] then
                    roleMetricBaselines[pRole] = {}
                end
                for _, metric in ipairs(metricDefs) do
                    if roleMetricWhitelist[pRole] and roleMetricWhitelist[pRole][metric.key] then
                        roleMetricBaselines[pRole][metric.key] = roleMetricBaselines[pRole][metric.key] or {sum = 0, count = 0}
                        local bucket = roleMetricBaselines[pRole][metric.key]
                        bucket.sum = bucket.sum + (metric.getter(p, duration) or 0)
                        bucket.count = bucket.count + 1
                    end
                end
            end
        end

        if ownerStats and run.players and #run.players > 1 then
            local duration = run.duration or 0
            local ownerRole = ownerStats.role or role or "UNKNOWN"
            for _, metric in ipairs(metricDefs) do
                if roleMetricWhitelist[ownerRole] and roleMetricWhitelist[ownerRole][metric.key] then
                    local ownerValue = metric.getter(ownerStats, duration)
                    local teammateSum, teammateCount = 0, 0
                    for _, p in ipairs(run.players) do
                        local pRole = p.role or "UNKNOWN"
                        if p ~= ownerStats and pRole == ownerRole then
                            teammateSum = teammateSum + (metric.getter(p, duration) or 0)
                            teammateCount = teammateCount + 1
                        end
                    end
                    local teamAvg = nil
                    local source = nil
                    if teammateCount > 0 then
                        teamAvg = teammateSum / teammateCount
                        source = "same-role teammate"
                    else
                        local baseline = roleMetricBaselines[ownerRole]
                            and roleMetricBaselines[ownerRole][metric.key]
                            or nil
                        if baseline and baseline.count and baseline.count >= 3 then
                            teamAvg = baseline.sum / baseline.count
                            source = "same-role season"
                        end
                    end
                    if teamAvg and teamAvg > 0 then
                        local gapKey = ownerRole .. "::" .. metric.key
                        teammateGapByMetric[gapKey] = teammateGapByMetric[gapKey] or {
                            key = metric.key,
                            label = metric.label,
                            role = ownerRole,
                            comparedRuns = 0,
                            belowCount = 0,
                            significantlyBelowCount = 0,
                            aboveCount = 0,
                            significantlyAboveCount = 0,
                            deltaSum = 0,
                            ownerSum = 0,
                            teammateSum = 0,
                            sourcePeerCount = 0,
                            sourceSeasonCount = 0,
                        }
                        local gap = teammateGapByMetric[gapKey]
                        gap.comparedRuns = gap.comparedRuns + 1
                        gap.deltaSum = gap.deltaSum + (ownerValue - teamAvg)
                        gap.ownerSum = gap.ownerSum + ownerValue
                        gap.teammateSum = gap.teammateSum + teamAvg
                        if source == "same-role teammate" then
                            gap.sourcePeerCount = gap.sourcePeerCount + 1
                        else
                            gap.sourceSeasonCount = gap.sourceSeasonCount + 1
                        end
                        
                        -- For inverse metrics (deaths, avoidable damage), lower is better
                        -- So we invert the comparison logic
                        local isInverse = metric.inverseMetric or false
                        
                        if isInverse then
                            -- Lower is better: ownerValue < teamAvg means performing ABOVE average
                            if ownerValue < teamAvg then
                                gap.aboveCount = gap.aboveCount + 1
                            end
                            if ownerValue < (teamAvg * 0.9) then
                                gap.significantlyAboveCount = gap.significantlyAboveCount + 1
                            end
                            if ownerValue > teamAvg then
                                gap.belowCount = gap.belowCount + 1
                            end
                            if ownerValue > (teamAvg * 1.1) then
                                gap.significantlyBelowCount = gap.significantlyBelowCount + 1
                            end
                        else
                            -- Normal metrics: higher is better
                            if ownerValue < teamAvg then
                                gap.belowCount = gap.belowCount + 1
                            end
                            if ownerValue < (teamAvg * 0.9) then
                                gap.significantlyBelowCount = gap.significantlyBelowCount + 1
                            end
                            if ownerValue > teamAvg then
                                gap.aboveCount = gap.aboveCount + 1
                            end
                            if ownerValue > (teamAvg * 1.1) then
                                gap.significantlyAboveCount = gap.significantlyAboveCount + 1
                            end
                        end
                    end
                end
            end
        end

        -- Abandoned keys are saved but never count toward personal bests
        local isAbandoned = run.abandonReason == "abandon"
        local pbKey = charKey .. "::" .. dungeonKey
        pbByCharDungeon[pbKey] = pbByCharDungeon[pbKey] or {
            bestLevel = 0,
            bestDamage = 0,
            bestHealing = 0,
            bestInterrupts = 0,
            bestDispels = 0,
        }
        if not isAbandoned then
            local prev = pbByCharDungeon[pbKey]
            local tags = {}
            if not failed and level > prev.bestLevel then
                prev.bestLevel = level
                table.insert(tags, "key +" .. tostring(level))
            end
            if ownerStats then
                local dmg = ownerStats.damage or 0
                local heal = ownerStats.healing or 0
                local ints = ownerStats.interrupts or 0
                local disps = ownerStats.dispels or 0
                if dmg > prev.bestDamage then
                    prev.bestDamage = dmg
                    table.insert(tags, "damage")
                end
                if heal > prev.bestHealing then
                    prev.bestHealing = heal
                    table.insert(tags, "healing")
                end
                if ints > prev.bestInterrupts then
                    prev.bestInterrupts = ints
                    table.insert(tags, "interrupts")
                end
                if disps > prev.bestDispels then
                    prev.bestDispels = disps
                    table.insert(tags, "dispels")
                end
            end
            if #tags > 0 then
                table.insert(pbFeed, {
                    timestamp = run.timestamp or time(),
                    characterName = character.name,
                    realm = character.realm,
                    class = character.class,
                    dungeonName = dungeon.name,
                    tags = tags,
                })
            end
        end

        -- Track score gain by character over the last 7 days (owner/player only).
        -- Only count runs where the character's overall Mythic+ rating actually increased
        -- (newDungeonScore > oldDungeonScore). This avoids counting completions that did not
        -- improve the character's standing (e.g. duplicate or lower-rated runs).
        if ownerStats and runTimestamp and runTimestamp >= scoreWindowStart then
            local oldScore = tonumber(run.oldDungeonScore)
            local newScore = tonumber(run.newDungeonScore)
            local scoreDelta = (oldScore and newScore) and (newScore - oldScore) or nil
            -- Only include the run if there is an actual rating increase; skip if the rating
            -- did not change, went down, or if the scores were not recorded for this run.
            if scoreDelta and scoreDelta > 0 then
                scoreGained7dByCharacter[charKey] = scoreGained7dByCharacter[charKey] or {
                    charKey = charKey,
                    name = character.name,
                    realm = character.realm,
                    class = character.class,
                    gained = 0,
                    runCount = 0,
                }
                local entry = scoreGained7dByCharacter[charKey]
                entry.gained = entry.gained + scoreDelta
                entry.runCount = entry.runCount + 1
            end
        end
    end

    local bestDungeon = nil
    for _, dungeon in pairs(dungeons) do
        dungeon.avgTimedLevel = AverageFromSum(dungeon.timedLevelSum, dungeon.timedRuns)
        dungeon.completionRate = AverageFromSum(dungeon.timedRuns, dungeon.totalRuns)
        if dungeon.timedRuns > 0 then
            if (not bestDungeon)
                or (dungeon.avgTimedLevel > bestDungeon.avgTimedLevel)
                or (dungeon.avgTimedLevel == bestDungeon.avgTimedLevel and dungeon.completionRate > bestDungeon.completionRate)
                or (dungeon.avgTimedLevel == bestDungeon.avgTimedLevel and dungeon.completionRate == bestDungeon.completionRate and dungeon.totalRuns > bestDungeon.totalRuns) then
                bestDungeon = dungeon
            end
        end
    end

    local function Clamp01(value)
        if value < 0 then
            return 0
        end
        if value > 1 then
            return 1
        end
        return value
    end

    local function ComputeCharacterPerformanceScore(character)
        local throughput = math.max(character.avgDPS or 0, character.avgHPS or 0)
        local throughputNorm = throughput > 0 and (throughput / (throughput + 60000)) or 0
        local interruptsNorm = (character.avgInterrupts or 0) / ((character.avgInterrupts or 0) + 10)
        local dispelsNorm = (character.avgDispels or 0) / ((character.avgDispels or 0) + 5)
        local completionNorm = Clamp01(character.completionRate or 0)
        local survivalNorm = 1 / (1 + math.max(0, character.avgDeaths or 0))
        local avoidableNorm = 1 / (1 + (math.max(0, character.avgAvoidableDamage or 0) / 3000000))
        local keyNorm = Clamp01((character.avgTimedLevel or 0) / 20)

        local score =
            (throughputNorm * 0.42) +
            (interruptsNorm * 0.13) +
            (dispelsNorm * 0.05) +
            (completionNorm * 0.18) +
            (survivalNorm * 0.12) +
            (avoidableNorm * 0.07) +
            (keyNorm * 0.02)

        return score * 100
    end

    local bestCharacter = nil
    for _, character in pairs(characters) do
        character.avgTimedLevel = AverageFromSum(character.timedLevelSum, character.timedRuns)
        character.completionRate = AverageFromSum(character.timedRuns, character.totalRuns)
        character.avgDeaths = AverageFromSum(character.totalDeaths, character.totalRuns)
        character.avgAvoidableDamage = AverageFromSum(character.totalAvoidableDamage, character.totalRuns)
        character.avgDamage = AverageFromSum(character.totalDamage, character.totalRuns)
        character.avgHealing = AverageFromSum(character.totalHealing, character.totalRuns)
        character.avgInterrupts = AverageFromSum(character.totalInterrupts, character.totalRuns)
        character.avgDispels = AverageFromSum(character.totalDispels, character.totalRuns)
        character.avgDPS = AverageFromSum(character.totalDPS, character.dpsSamples)
        character.avgHPS = AverageFromSum(character.totalHPS, character.hpsSamples)
        if character.timedRuns > 0 then
            character.performanceScore = ComputeCharacterPerformanceScore(character)
        end
    end

    local bestCharacterPerDungeon = {}
    for dungeonKey, perChar in pairs(bestByDungeonCharacter) do
        local top = nil
        for charKey, combo in pairs(perChar) do
            combo.avgTimedLevel = AverageFromSum(combo.timedLevelSum, combo.timedRuns)
            if combo.timedRuns > 0 then
                if (not top)
                    or (combo.avgTimedLevel > top.avgTimedLevel)
                    or (combo.avgTimedLevel == top.avgTimedLevel and combo.bestTimedLevel > top.bestTimedLevel)
                    or (combo.avgTimedLevel == top.avgTimedLevel and combo.bestTimedLevel == top.bestTimedLevel and combo.timedRuns > top.timedRuns) then
                    top = combo
                end
            end
        end
        if top then
            local dungeon = dungeons[dungeonKey]
            local character = characters[top.charKey]
            table.insert(bestCharacterPerDungeon, {
                dungeonName = dungeon and dungeon.name or "Unknown",
                characterName = character and character.name or "Unknown",
                realm = character and character.realm or "Unknown",
                class = character and character.class or "UNKNOWN",
                avgTimedLevel = top.avgTimedLevel or 0,
                bestTimedLevel = top.bestTimedLevel or 0,
                timedRuns = top.timedRuns or 0,
            })
        end
    end
    table.sort(bestCharacterPerDungeon, function(a, b)
        return a.dungeonName < b.dungeonName
    end)

    local trendsPerCharacter = {}
    for charKey, charRuns in pairs(runsByCharacter) do
        local trend = ComputeImprovementFromRuns(charRuns)
        if trend then
            local character = characters[charKey]
            table.insert(trendsPerCharacter, {
                name = character and character.name or "Unknown",
                realm = character and character.realm or "Unknown",
                class = character and character.class or "UNKNOWN",
                completionRate = character and character.completionRate or 0,
                trend = trend,
            })
        end
    end
    table.sort(trendsPerCharacter, function(a, b)
        return (a.trend.deltaTimedLevel or 0) > (b.trend.deltaTimedLevel or 0)
    end)

    local roleInsights = {}
    for _, info in pairs(roleStats) do
        info.avgTimedLevel = AverageFromSum(info.timedLevelSum, info.timedRuns)
        local bestCharKey = nil
        local bestAvg = -1
        for charKey, per in pairs(info.perCharacter) do
            local avg = AverageFromSum(per.timedLevelSum, per.timedRuns)
            if avg > bestAvg then
                bestAvg = avg
                bestCharKey = charKey
            end
        end
        if bestCharKey and characters[bestCharKey] then
            local c = characters[bestCharKey]
            info.bestCharacterKey = bestCharKey
            info.bestCharacterAvg = bestAvg
            info.bestCharacterName = c.name
            info.bestCharacterRealm = c.realm
            info.bestCharacterClass = c.class
        end
        table.insert(roleInsights, info)
    end
    table.sort(roleInsights, function(a, b)
        return (a.avgTimedLevel or 0) > (b.avgTimedLevel or 0)
    end)

    local consistencyRanking = {}
    local minConsistencyRunsPerDungeon = 3
    for charKey, charRuns in pairs(runsByCharacter) do
        local c = characters[charKey]
        if c and #charRuns >= 3 then
            local successfulRuns = 0
            local byDungeon = {}
            local roleCounts = {}
            for _, run in ipairs(charRuns) do
                if not RunIsFailed(run) then
                    local ownerStats = GetOwnerStats(run)
                    if ownerStats then
                        successfulRuns = successfulRuns + 1
                        local runDuration = run.duration or 0
                        local dungeonID = run.dungeonID or run.dungeonId or 0
                        local dungeonName = run.dungeonName or "Unknown"
                        local dungeonKey = tostring(dungeonID) .. "::" .. dungeonName
                        byDungeon[dungeonKey] = byDungeon[dungeonKey] or {}
                        table.insert(byDungeon[dungeonKey], {
                            damage = (metricGettersByKey.damage and metricGettersByKey.damage(ownerStats, runDuration)) or 0,
                            dps = (metricGettersByKey.dps and metricGettersByKey.dps(ownerStats, runDuration)) or 0,
                            healing = (metricGettersByKey.healing and metricGettersByKey.healing(ownerStats, runDuration)) or 0,
                            hps = (metricGettersByKey.hps and metricGettersByKey.hps(ownerStats, runDuration)) or 0,
                            interrupts = (metricGettersByKey.interrupts and metricGettersByKey.interrupts(ownerStats, runDuration)) or 0,
                            dispels = (metricGettersByKey.dispels and metricGettersByKey.dispels(ownerStats, runDuration)) or 0,
                        })
                        -- Track role frequency
                        local role = run.specRole or "UNKNOWN"
                        roleCounts[role] = (roleCounts[role] or 0) + 1
                    end
                end
            end

            -- Find most common role
            local mostCommonRole = "UNKNOWN"
            local maxRoleCount = 0
            for role, count in pairs(roleCounts) do
                if count > maxRoleCount then
                    maxRoleCount = count
                    mostCommonRole = role
                end
            end

            local dungeonScores = {}
            local variabilitySum = 0
            local variabilityCount = 0
            local metricKeys = {"damage", "dps", "healing", "hps", "interrupts", "dispels", "deaths", "avoidableDamageTaken"}
            for _, samples in pairs(byDungeon) do
                if #samples >= minConsistencyRunsPerDungeon then
                    local dungeonMetricScoreSum = 0
                    local dungeonMetricScoreCount = 0
                    for _, metricKey in ipairs(metricKeys) do
                        local sum = 0
                        local count = 0
                        for _, sample in ipairs(samples) do
                            sum = sum + (sample[metricKey] or 0)
                            count = count + 1
                        end
                        local avg = AverageFromSum(sum, count)
                        local variance = 0
                        for _, sample in ipairs(samples) do
                            local d = (sample[metricKey] or 0) - avg
                            variance = variance + (d * d)
                        end
                        variance = AverageFromSum(variance, count)
                        local stddev = math.sqrt(variance)
                        local variability = 0
                        if avg > 0 then
                            variability = stddev / avg
                        end
                        local metricConsistency = math.max(0, 100 - (variability * 100))
                        dungeonMetricScoreSum = dungeonMetricScoreSum + metricConsistency
                        dungeonMetricScoreCount = dungeonMetricScoreCount + 1
                        variabilitySum = variabilitySum + variability
                        variabilityCount = variabilityCount + 1
                    end
                    table.insert(dungeonScores, AverageFromSum(dungeonMetricScoreSum, dungeonMetricScoreCount))
                end
            end

            if #dungeonScores > 0 and successfulRuns > 0 then
                local totalDungeonScore = 0
                for _, score in ipairs(dungeonScores) do
                    totalDungeonScore = totalDungeonScore + score
                end
                local finalScore = AverageFromSum(totalDungeonScore, #dungeonScores)
                local avgVariability = AverageFromSum(variabilitySum, variabilityCount)
                table.insert(consistencyRanking, {
                    name = c.name,
                    realm = c.realm,
                    class = c.class,
                    role = mostCommonRole,
                    score = finalScore,
                    avgVariability = avgVariability,
                    stddev = avgVariability, -- compatibility fallback for display fields
                    runCount = successfulRuns,
                    dungeonCount = #dungeonScores,
                    minRunsPerDungeon = minConsistencyRunsPerDungeon,
                })
            end
        end
    end
    table.sort(consistencyRanking, function(a, b) return (a.score or 0) > (b.score or 0) end)

    local painPoints = {}
    for _, p in pairs(dungeonPain) do
        p.failRate = AverageFromSum(p.failed, p.runs)
        p.avgTimeLost = AverageFromSum(p.timeLostSum, p.runs)
        p.avgDeaths = AverageFromSum(p.deathSum, p.runs)
        p.avgAvoidableDamage = AverageFromSum(p.avoidableDamageSum, p.runs)
        p.riskScore = BuildPainRisk(p.failRate, p.avgTimeLost, p.avgDeaths)
        table.insert(painPoints, p)
    end
    table.sort(painPoints, function(a, b) return (a.riskScore or 0) > (b.riskScore or 0) end)

    local painPointTrends = {}
    for _, payload in pairs(dungeonPainWeekly) do
        local weeklyRows = {}
        for _, row in pairs(payload.weekly or {}) do
            table.insert(weeklyRows, row)
        end
        table.sort(weeklyRows, function(a, b) return (a.key or "") < (b.key or "") end)

        if #weeklyRows > 0 then
            local recentCount = math.min(4, #weeklyRows)
            local recentStart = #weeklyRows - recentCount + 1

            local function AggregateRange(startIndex, endIndex)
                local runsN, failedN, timeLostN, deathsN, avoidDmgN = 0, 0, 0, 0, 0
                for i = startIndex, endIndex do
                    local w = weeklyRows[i]
                    if w then
                        runsN = runsN + (w.runs or 0)
                        failedN = failedN + (w.failed or 0)
                        timeLostN = timeLostN + (w.timeLostSum or 0)
                        deathsN = deathsN + (w.deathSum or 0)
                        avoidDmgN = avoidDmgN + (w.avoidableDamageSum or 0)
                    end
                end
                local failRate = AverageFromSum(failedN, runsN)
                local avgTimeLost = AverageFromSum(timeLostN, runsN)
                local avgDeaths = AverageFromSum(deathsN, runsN)
                local avgAvoidableDamage = AverageFromSum(avoidDmgN, runsN)
                local risk = BuildPainRisk(failRate, avgTimeLost, avgDeaths)
                return {
                    runs = runsN,
                    failRate = failRate,
                    avgTimeLost = avgTimeLost,
                    avgDeaths = avgDeaths,
                    avgAvoidableDamage = avgAvoidableDamage,
                    risk = risk,
                }
            end

            local recent = AggregateRange(recentStart, #weeklyRows)
            local previous = nil
            local previousStart = recentStart - recentCount
            local previousEnd = recentStart - 1
            if previousStart >= 1 and previousEnd >= previousStart then
                previous = AggregateRange(previousStart, previousEnd)
            end

            table.insert(painPointTrends, {
                dungeonName = payload.dungeonName or "Unknown",
                recent = recent,
                previous = previous,
                deltaRisk = previous and (recent.risk - previous.risk) or nil,
                deltaFailRate = previous and (recent.failRate - previous.failRate) or nil,
                deltaTimeLost = previous and (recent.avgTimeLost - previous.avgTimeLost) or nil,
                deltaDeaths = previous and (recent.avgDeaths - previous.avgDeaths) or nil,
                deltaAvoidableDamage = previous and (recent.avgAvoidableDamage - previous.avgAvoidableDamage) or nil,
                recentFromWeek = weeklyRows[recentStart] and weeklyRows[recentStart].key or nil,
                recentToWeek = weeklyRows[#weeklyRows] and weeklyRows[#weeklyRows].key or nil,
            })
        end
    end
    table.sort(painPointTrends, function(a, b)
        local ad = a.deltaRisk
        local bd = b.deltaRisk
        if ad == nil and bd ~= nil then return false end
        if ad ~= nil and bd == nil then return true end
        if ad ~= nil and bd ~= nil and ad ~= bd then
            return ad > bd
        end
        return (a.recent and a.recent.risk or 0) > (b.recent and b.recent.risk or 0)
    end)

    local synergyPairs = {}
    for _, s in pairs(synergy) do
        if s.runs >= 2 then
            s.completionRate = AverageFromSum(s.timedRuns, s.runs)
            s.avgTimedLevel = AverageFromSum(s.timedLevelSum, s.timedRuns)
            table.insert(synergyPairs, s)
        end
    end
    table.sort(synergyPairs, function(a, b)
        if (a.avgTimedLevel or 0) ~= (b.avgTimedLevel or 0) then
            return (a.avgTimedLevel or 0) > (b.avgTimedLevel or 0)
        end
        return (a.completionRate or 0) > (b.completionRate or 0)
    end)

    table.sort(pbFeed, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)

    local underperformingMetrics = {}
    local outperformingMetrics = {}
    for _, gap in pairs(teammateGapByMetric) do
        gap.belowRate = AverageFromSum(gap.belowCount, gap.comparedRuns)
        gap.significantlyBelowRate = AverageFromSum(gap.significantlyBelowCount, gap.comparedRuns)
        gap.aboveRate = AverageFromSum(gap.aboveCount, gap.comparedRuns)
        gap.significantlyAboveRate = AverageFromSum(gap.significantlyAboveCount, gap.comparedRuns)
        gap.avgDelta = AverageFromSum(gap.deltaSum, gap.comparedRuns)
        gap.ownerAvg = AverageFromSum(gap.ownerSum, gap.comparedRuns)
        gap.teammateAvg = AverageFromSum(gap.teammateSum, gap.comparedRuns)
        gap.ratioToTeam = (gap.teammateAvg and gap.teammateAvg > 0) and (gap.ownerAvg / gap.teammateAvg) or 1
        if (gap.comparedRuns or 0) >= 3 and (gap.significantlyBelowRate or 0) >= 0.5 and (gap.avgDelta or 0) < 0 then
            table.insert(underperformingMetrics, gap)
        end
        if (gap.comparedRuns or 0) >= 3 and (gap.significantlyAboveRate or 0) >= 0.5 and (gap.avgDelta or 0) > 0 then
            table.insert(outperformingMetrics, gap)
        end
    end
    table.sort(underperformingMetrics, function(a, b)
        if (a.significantlyBelowRate or 0) ~= (b.significantlyBelowRate or 0) then
            return (a.significantlyBelowRate or 0) > (b.significantlyBelowRate or 0)
        end
        return (a.avgDelta or 0) < (b.avgDelta or 0)
    end)
    table.sort(outperformingMetrics, function(a, b)
        if (a.significantlyAboveRate or 0) ~= (b.significantlyAboveRate or 0) then
            return (a.significantlyAboveRate or 0) > (b.significantlyAboveRate or 0)
        end
        return (a.avgDelta or 0) > (b.avgDelta or 0)
    end)

    local overallTimeline = BuildTimeline(weeklyByOverall)
    local characterTimelines = {}
    for charKey, weekly in pairs(weeklyByCharacter) do
        local c = characters[charKey]
        if c then
            local timeline = BuildTimeline(weekly)
            table.insert(characterTimelines, {
                name = c.name,
                realm = c.realm,
                class = c.class,
                timeline = timeline,
            })
        end
    end
    table.sort(characterTimelines, function(a, b)
        local aLast = a.timeline.points[#a.timeline.points]
        local bLast = b.timeline.points[#b.timeline.points]
        return ((aLast and aLast.avgTimedLevel) or 0) > ((bLast and bLast.avgTimedLevel) or 0)
    end)

    local scoreProgress7d = {characters = {}, totalGained = 0, totalRuns = 0}
    for _, entry in pairs(scoreGained7dByCharacter) do
        table.insert(scoreProgress7d.characters, entry)
        scoreProgress7d.totalGained = scoreProgress7d.totalGained + (entry.gained or 0)
        scoreProgress7d.totalRuns = scoreProgress7d.totalRuns + (entry.runCount or 0)
    end
    table.sort(scoreProgress7d.characters, function(a, b)
        if (a.gained or 0) ~= (b.gained or 0) then
            return (a.gained or 0) > (b.gained or 0)
        end
        return (a.runCount or 0) > (b.runCount or 0)
    end)

    local seasonComparison = nil
    do
        local catalog = self:BuildSeasonCatalog()
        local selectedKey = self.selectedSeasonFilter
        local selectedIndex = nil
        for i, entry in ipairs(catalog.ordered or {}) do
            if entry.key == selectedKey then
                selectedIndex = i
                break
            end
        end
        if selectedIndex and catalog.ordered[selectedIndex + 1] then
            local previous = catalog.ordered[selectedIndex + 1]
            local previousRuns = {}
            for _, run in ipairs(previous.runs or {}) do
                if not run.deleted then
                    table.insert(previousRuns, run)
                end
            end
            if #previousRuns > 0 then
                local currentSummary = ComputeSummary(runs)
                local previousSummary = ComputeSummary(previousRuns)
                seasonComparison = {
                    previousLabel = previous.label or "Previous Season",
                    previousRuns = previousSummary.totalRuns,
                    currentRuns = currentSummary.totalRuns,
                    deltaCompletionRate = currentSummary.completionRate - previousSummary.completionRate,
                    deltaTimedLevel = currentSummary.avgTimedLevel - previousSummary.avgTimedLevel,
                    deltaTimedDuration = previousSummary.avgTimedDuration - currentSummary.avgTimedDuration,
                }
            end
        end
    end

    local recommendations = {}

    -- Priority 1: Role-specific performance gaps first, deduped by metric family
    local gapFamilyOrder = {"healing", "damage", "interrupts"}
    local gapFamilyByMetric = {
        healing = "healing",
        hps = "healing",
        damage = "damage",
        dps = "damage",
        interrupts = "interrupts",
    }
    local bestGapByFamily = {}
    local function IsGapStronger(a, b)
        if not b then return true end
        if (a.significantlyBelowRate or 0) ~= (b.significantlyBelowRate or 0) then
            return (a.significantlyBelowRate or 0) > (b.significantlyBelowRate or 0)
        end
        if (a.belowRate or 0) ~= (b.belowRate or 0) then
            return (a.belowRate or 0) > (b.belowRate or 0)
        end
        return (a.avgDelta or 0) < (b.avgDelta or 0)
    end
    for _, metric in ipairs(underperformingMetrics) do
        local family = gapFamilyByMetric[metric.key]
        if family and IsGapStronger(metric, bestGapByFamily[family]) then
            bestGapByFamily[family] = metric
        end
    end
    for _, family in ipairs(gapFamilyOrder) do
        local metric = bestGapByFamily[family]
        if metric then
            table.insert(recommendations, string.format(
                "Role-specific gap (%s %s): below comparable average in %d%% of runs (%d%% significantly below).",
                metric.role or "UNKNOWN",
                metric.label or metric.key or "Metric",
                math.floor((metric.belowRate or 0) * 100 + 0.5),
                math.floor((metric.significantlyBelowRate or 0) * 100 + 0.5)
            ))
        end
    end

    -- Remaining recommendations
    for i, p in ipairs(painPoints) do
        if i > 3 then break end
        if p.runs >= 3 then
            table.insert(recommendations, string.format(
                "Focus %s next: %d%% fail rate, avg %.1fs time lost, avg %.1f deaths.",
                p.dungeonName or "Unknown",
                math.floor((p.failRate or 0) * 100 + 0.5),
                p.avgTimeLost or 0,
                p.avgDeaths or 0
            ))
        end
    end
    if #trendsPerCharacter > 0 and trendsPerCharacter[#trendsPerCharacter] then
        local slowest = trendsPerCharacter[#trendsPerCharacter]
        -- Only recommend route/planning review when both key level and completion trend are down,
        -- and the character isn't already completing most keys.
        local completionRate = slowest.completionRate or 0
        if (slowest.trend.deltaTimedLevel or 0) < 0 
            and (slowest.trend.deltaCompletionRate or 0) < 0 
            and completionRate < 0.95 then
            table.insert(recommendations, string.format(
                "Review route/planning on %s-%s: timed key trend is %+0.2f.",
                slowest.name or "Unknown",
                slowest.realm or "Unknown",
                slowest.trend.deltaTimedLevel or 0
            ))
        end
    end

    local overallTrend = ComputeImprovementFromRuns(runs)

    -- Create a sorted list of all characters
    local allCharacters = {}
    for _, character in pairs(characters) do
        if character.timedRuns and character.timedRuns > 0 then
            table.insert(allCharacters, character)
        end
    end
    table.sort(allCharacters, function(a, b)
        if (a.performanceScore or 0) ~= (b.performanceScore or 0) then
            return (a.performanceScore or 0) > (b.performanceScore or 0)
        end
        if (a.completionRate or 0) ~= (b.completionRate or 0) then
            return (a.completionRate or 0) > (b.completionRate or 0)
        end
        if (a.avgTimedLevel or 0) ~= (b.avgTimedLevel or 0) then
            return (a.avgTimedLevel or 0) > (b.avgTimedLevel or 0)
        end
        return (a.totalRuns or 0) > (b.totalRuns or 0)
    end)

    bestCharacter = allCharacters[1]

    return {
        totalRuns = #runs,
        bestDungeon = bestDungeon,
        bestCharacter = bestCharacter,
        allCharacters = allCharacters,
        bestCharacterPerDungeon = bestCharacterPerDungeon,
        overallTrend = overallTrend,
        trendsPerCharacter = trendsPerCharacter,
        roleInsights = roleInsights,
        consistencyRanking = consistencyRanking,
        overallTimeline = overallTimeline,
        characterTimelines = characterTimelines,
        painPoints = painPoints,
        painPointTrends = painPointTrends,
        synergyPairs = synergyPairs,
        personalBestFeed = pbFeed,
        underperformingMetrics = underperformingMetrics,
        outperformingMetrics = outperformingMetrics,
        scoreProgress7d = scoreProgress7d,
        seasonComparison = seasonComparison,
        recommendations = recommendations,
    }
end

function HistoryViewer:ResetNonSeasonFilters()
    self.selectedCharacter = nil
    self.selectedDungeon = nil
    self.selectedDungeonName = nil
    self.selectedKeystoneLevel = nil
    self.selectedResult = nil
    self.selectedRole = nil
    self.selectedDungeons = {}
    self.selectedKeystoneLevels = {}
    self.selectedResults = {}
    self.selectedClassSpecHero = {classes = {}, specs = {}, heroTalents = {}}
end

function HistoryViewer:RefreshSeasonDropdown(catalog)
    if not self.frame or not self.frame.SeasonDropdown then
        return
    end

    local dropdown = self.frame.SeasonDropdown
    local items = {}
    for _, season in ipairs(catalog.ordered or {}) do
        if (season.runCount and season.runCount > 0) or (catalog.currentKey and season.key == catalog.currentKey) then
            table.insert(items, season)
        end
    end

    UIDropDownMenu_Initialize(dropdown, function()
        for _, season in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            local suffix = ((season.runCount or 0) == 0) and " (0 runs)" or ""
            info.text = season.label .. suffix
            info.value = season.key
            info.func = function()
                if self.selectedSeasonFilter ~= season.key then
                    self.selectedSeasonFilter = season.key
                    self:ResetNonSeasonFilters()
                    self:PopulateFilters()
                end
            end
            info.checked = (self.selectedSeasonFilter == season.key)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local selectedLabel = nil
    for _, season in ipairs(items) do
        if season.key == self.selectedSeasonFilter then
            local suffix = ((season.runCount or 0) == 0) and " (0 runs)" or ""
            selectedLabel = season.label .. suffix
            break
        end
    end
    UIDropDownMenu_SetSelectedValue(dropdown, self.selectedSeasonFilter)
    UIDropDownMenu_SetText(dropdown, selectedLabel or "No Seasons")
end

function HistoryViewer:Create()
    if self.frame then
        self.frame:Show()
        return self.frame
    end
    
    -- Main frame
    local frame = CreateFrame("Frame", "StormsDungeonDataHistory", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1000, 700)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(100)
    frame:SetScale(MPT.UIUtils:ComputeWindowScale())
    -- Allow Escape key to close this window from any page/tab state.
    if UISpecialFrames and frame.GetName then
        local frameName = frame:GetName()
        local alreadyRegistered = false
        for _, name in ipairs(UISpecialFrames) do
            if name == frameName then
                alreadyRegistered = true
                break
            end
        end
        if not alreadyRegistered then
            table.insert(UISpecialFrames, frameName)
        end
    end
    
    frame.TitleBg:SetHeight(30)
    frame.InsetBg:SetAlpha(0.35)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame.TitleBg, "TOPLEFT", 10, -5)
    title:SetText("Run History")
    frame.Title = title
    
    local historyTab = MPT.UIUtils:CreateButton(frame, "History", 90, 22, function()
        self:SetActivePage("history")
    end)
    historyTab:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -200, -32)
    frame.HistoryTab = historyTab

    local insightsTab = MPT.UIUtils:CreateButton(frame, "Insights", 90, 22, function()
        self:SetActivePage("insights")
    end)
    insightsTab:SetPoint("LEFT", historyTab, "RIGHT", 6, 0)
    frame.InsightsTab = insightsTab

    local tierListTab = MPT.UIUtils:CreateButton(frame, "Tier List", 90, 22, function()
        self:SetActivePage("tierlist")
    end)
    tierListTab:SetPoint("LEFT", insightsTab, "RIGHT", 6, 0)
    frame.TierListTab = tierListTab

    -- Shared backdrop
    local backdropInfo = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    }

    -- Season filter row (top of history page)
    local seasonPanel = CreateFrame("Frame", nil, frame)
    seasonPanel:SetSize(980, 36)
    seasonPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -70)
    SetBackdropCompat(seasonPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})

    local seasonLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    seasonLabel:SetPoint("LEFT", seasonPanel, "LEFT", 12, 0)
    seasonLabel:SetText("Season:")
    seasonLabel:SetTextColor(1, 0.84, 0, 1)

    local seasonDropdown = CreateFrame("Frame", "StormsDungeonDataHistorySeasonDropdown", seasonPanel, "UIDropDownMenuTemplate")
    seasonDropdown:SetPoint("LEFT", seasonLabel, "RIGHT", -2, -3)
    UIDropDownMenu_SetWidth(seasonDropdown, 220)
    UIDropDownMenu_JustifyText(seasonDropdown, "LEFT")
    UIDropDownMenu_SetText(seasonDropdown, "Select Season")
    do
        local seasonButton = _G["StormsDungeonDataHistorySeasonDropdownButton"]
        local seasonText = _G["StormsDungeonDataHistorySeasonDropdownText"]
        if seasonButton then
            seasonButton:ClearAllPoints()
            seasonButton:SetPoint("RIGHT", seasonDropdown, "RIGHT", -16, 2)
        end
        if seasonText and seasonButton then
            seasonText:ClearAllPoints()
            seasonText:SetPoint("LEFT", seasonDropdown, "LEFT", 24, 2)
            seasonText:SetPoint("RIGHT", seasonButton, "LEFT", -2, 2)
        end
        if seasonButton and ToggleDropDownMenu then
            local function RepositionSeasonDropdownList()
                local list = _G["DropDownList1"]
                if list and list:IsShown() then
                    list:SetFrameStrata("TOOLTIP")
                    list:SetFrameLevel(frame:GetFrameLevel() + 100)
                    list:ClearAllPoints()
                    list:SetPoint("TOPLEFT", seasonDropdown, "BOTTOMLEFT", 8, -2)
                end
            end
            seasonButton:SetScript("OnMouseDown", function()
                ToggleDropDownMenu(1, nil, seasonDropdown, seasonDropdown, 8, 0)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, RepositionSeasonDropdownList)
                else
                    RepositionSeasonDropdownList()
                end
            end)
            seasonButton:SetScript("OnClick", nil)
        end
    end
    frame.SeasonDropdown = seasonDropdown

    frame.SeasonPanel = seasonPanel

    -- Summary bar
    local summaryPanel = CreateFrame("Frame", nil, frame)
    summaryPanel:SetSize(980, 52)
    summaryPanel:SetPoint("TOPLEFT", seasonPanel, "BOTTOMLEFT", 0, -8)
    SetBackdropCompat(summaryPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    frame.SummaryPanel = summaryPanel

    local summaryLabels = {"Total Runs", "Completed", "Failed", "Avg Level"}
    frame.SummaryValues = {}
    frame.SummaryLabels = {}
    for i, label in ipairs(summaryLabels) do
        local colWidth = 980 / #summaryLabels
        local x = 10 + ((i - 1) * colWidth)

        local labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetText(label .. ":")
        labelText:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", x, -10)
        labelText:SetTextColor(1, 0.84, 0, 1)

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        valueText:SetText("--")
        valueText:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", x, -26)
        valueText:SetTextColor(1, 1, 1, 1)

        table.insert(frame.SummaryLabels, labelText)
        table.insert(frame.SummaryValues, valueText)
    end

    -- Filter bar (2 rows, evenly spaced)
    local filterPanel = CreateFrame("Frame", nil, frame)
    filterPanel:SetSize(980, 100)
    filterPanel:SetPoint("TOPLEFT", summaryPanel, "BOTTOMLEFT", 0, -12)
    SetBackdropCompat(filterPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    frame.FilterPanel = filterPanel
    
    local function CreateFilterDropdown(labelText, x, width, yOffset)
        yOffset = yOffset or 0
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(labelText)
        label:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", x + 8, -8 + yOffset)
        label:SetTextColor(1, 0.84, 0, 1)

        -- UIDropDownMenuTemplate relies on the dropdown having a name for correct anchoring
        -- (the template creates named children like <name>Button and uses them as anchor frames).
        local safeKey = (labelText or ""):gsub("%W", "")
        if safeKey == "" then safeKey = "Filter" end
        local dropdownName = "StormsDungeonDataHistory" .. safeKey .. "Dropdown"
        local dropdown = CreateFrame("Frame", dropdownName, filterPanel, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", x - 12, -22 + yOffset)
        UIDropDownMenu_SetWidth(dropdown, width)
        UIDropDownMenu_JustifyText(dropdown, "LEFT")
        UIDropDownMenu_SetText(dropdown, "All")

        -- Make the selected value text larger for readability.
        local dropdownText = _G[dropdownName .. "Text"]
        if dropdownText and dropdownText.SetFontObject then
            dropdownText:SetFontObject("GameFontNormalLarge")
        end

        -- Force the menu to open directly below the dropdown button.
        -- UIDropDownMenuTemplate typically toggles from the button's OnMouseDown; if we only
        -- override OnClick, the default mouse-down toggle can open (default anchor) and then
        -- our OnClick toggles again, immediately closing it.
        local button = _G[dropdownName .. "Button"]
        if button then
            -- Move dropdown arrow button back to the right side.
            button:ClearAllPoints()
            button:SetPoint("RIGHT", dropdown, "RIGHT", -16, 2)
            if dropdownText then
                dropdownText:ClearAllPoints()
                dropdownText:SetPoint("LEFT", dropdown, "LEFT", 24, 2)
                dropdownText:SetPoint("RIGHT", button, "LEFT", -2, 2)
            end

            if UIDropDownMenu_SetAnchor then
                UIDropDownMenu_SetAnchor(dropdown, 8, 0, "TOPLEFT", dropdown, "BOTTOMLEFT")
            end

            if ToggleDropDownMenu then
                local function RepositionDropdownList()
                    local list = _G["DropDownList1"]
                    if list and list:IsShown() then
                        -- Ensure dropdown list draws on top of the history window (same strata, higher level)
                        list:SetFrameStrata("TOOLTIP")
                        list:SetFrameLevel(frame:GetFrameLevel() + 100)
                        list:ClearAllPoints()
                        list:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 8, -2)
                    end
                end

                button:SetScript("OnMouseDown", function()
                    ToggleDropDownMenu(1, nil, dropdown, dropdown, 8, 0)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, RepositionDropdownList)
                    else
                        RepositionDropdownList()
                    end
                end)
                button:SetScript("OnClick", nil)
            end
        end
        dropdown.FilterLabel = label
        return dropdown
    end

    local columns = 3
    local colWidth = math.floor(980 / columns)
    local dropdownWidth = colWidth - 30
    local colSpacing = colWidth - dropdownWidth  -- Spacing between columns (30px)
    local row1Y = 0
    local row2Y = -46

    local function ColX(col)
        return 10 + ((col - 1) * colWidth)
    end

    -- Row 1
    frame.DungeonDropdown = CreateFilterDropdown("Dungeon", ColX(1), dropdownWidth, row1Y)
    frame.KeystoneDropdown = CreateFilterDropdown("Keystone", ColX(2), dropdownWidth, row1Y)
    frame.ResultDropdown = CreateFilterDropdown("Result", ColX(3), dropdownWidth, row1Y)

    -- Row 2
    frame.CharacterDropdown = CreateFilterDropdown("Character", ColX(1), dropdownWidth, row2Y)
    frame.RoleDropdown = CreateFilterDropdown("Role", ColX(2), dropdownWidth, row2Y)
    frame.ClassSpecHeroDropdown = CreateFilterDropdown("Class/Spec", ColX(3), dropdownWidth, row2Y)

    local resetButton = MPT.UIUtils:CreateButton(filterPanel, "Reset Filters", 120, 22, function()
        self:ResetNonSeasonFilters()
        self:PopulateFilters()
    end)
    resetButton:SetPoint("TOPLEFT", frame.ClassSpecHeroDropdown, "BOTTOMLEFT", 16, -6)
    frame.ResetFiltersButton = resetButton

    -- Insights score panel (shown only on Insights page, right side).
    -- Tall layout: starts below tabs and ends above the main insights content panel.
    local insightsScorePanel = CreateFrame("Frame", nil, frame)
    insightsScorePanel:SetSize(620, 180)
    insightsScorePanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -58)
    SetBackdropCompat(insightsScorePanel, backdropInfo, {0.04, 0.04, 0.06, 0.65}, {1, 1, 1, 0.25})
    insightsScorePanel:Hide()
    frame.InsightsScorePanel = insightsScorePanel

    local insightsScoreTitle = insightsScorePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    insightsScoreTitle:SetPoint("TOPLEFT", insightsScorePanel, "TOPLEFT", 8, -6)
    insightsScoreTitle:SetText("Character Score Gained (Last 7 Days)")
    insightsScoreTitle:SetTextColor(1, 0.84, 0, 1)
    frame.InsightsScoreTitle = insightsScoreTitle

    frame.InsightsScoreRows = {}
    frame.InsightsScoreScroll, frame.InsightsScoreContent = MPT.UIUtils:CreateScrollFrame(insightsScorePanel, 600, 60)
    frame.InsightsScoreScroll:SetPoint("TOPLEFT", insightsScorePanel, "TOPLEFT", 8, -20)
    frame.InsightsScoreScroll:SetPoint("BOTTOMRIGHT", insightsScorePanel, "BOTTOMRIGHT", -16, 8)
    if frame.InsightsScoreContent and frame.InsightsScoreContent.SetBackdrop then
        frame.InsightsScoreContent:SetBackdrop(nil)
    end

    local insightsScoreEmpty = insightsScorePanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    insightsScoreEmpty:SetPoint("TOPLEFT", insightsScorePanel, "TOPLEFT", 8, -38)
    insightsScoreEmpty:SetText("No character gained score in the last 7 days.")
    insightsScoreEmpty:Hide()
    frame.InsightsScoreEmpty = insightsScoreEmpty
    
    -- Main stats panel with proper spacing
    local statsPanel = CreateFrame("Frame", nil, frame)
    statsPanel:SetPoint("TOPLEFT", filterPanel, "BOTTOMLEFT", 0, -8)
    statsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    SetBackdropCompat(statsPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    frame.StatsPanel = statsPanel
    
    -- Stats content
    local statsTitle = statsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statsTitle:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, -10)
    statsTitle:SetText("Dungeon Statistics")
    frame.StatsTitle = statsTitle
    
    -- Averages & best stats grid: 4 columns, 4 rows (row 1 has 3 filled columns)
    local metricDefs = {
        -- Row 1: Best Level, Avg Duration, MVP % (col 4 intentionally empty)
        {key = "bestKeystoneLevel", label = "Best Level", clickable = true},
        {key = "avgDuration", label = "Avg Duration"},
        {key = "mvpPercent", label = "MVP %"},
        {key = "_spacer1", spacer = true},
        -- Row 2: Best Damage, Best DPS, Best Healing, Best HPS
        {key = "bestDamage", label = "Best Damage", clickable = true},
        {key = "bestDPS", label = "Best DPS", clickable = true},
        {key = "bestHealing", label = "Best Healing", clickable = true},
        {key = "bestHPS", label = "Best HPS", clickable = true},
        -- Row 3: Avg Damage, Avg DPS, Avg Healing, Avg HPS
        {key = "avgDamage", label = "Avg Damage"},
        {key = "avgDPS", label = "Avg DPS"},
        {key = "avgHealing", label = "Avg Healing"},
        {key = "avgHPS", label = "Avg HPS"},
        -- Row 4: Avg Avoid Dmg, Avg Deaths, Best Interrupts, Avg Interrupts
        {key = "avgAvoidableDamage", label = "Avg Avoid Dmg"},
        {key = "avgDeaths", label = "Avg Deaths"},
        {key = "bestInterrupts", label = "Best Interrupts", clickable = true},
        {key = "avgInterrupts", label = "Avg Interrupts"},
        -- Row 5: Best Dispels, Avg Dispels
        {key = "bestDispels", label = "Best Dispels", clickable = true},
        {key = "avgDispels", label = "Avg Dispels"},
        {key = "_spacer2", spacer = true},
        {key = "_spacer3", spacer = true},
    }

    frame.StatValues = {}
    frame.StatLabels = {}
    local gridTopY = -40
    local columns = 4
    local colSpacing = 240
    local rowHeight = 30
    local labelWidth = 100

    for i, metric in ipairs(metricDefs) do
        if not metric.spacer then
        local colIndex = (i - 1) % columns
        local rowIndex = math.floor((i - 1) / columns)
        local x = 10 + (colIndex * colSpacing)
        local y = gridTopY - (rowIndex * rowHeight)

        local labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetText(metric.label .. ":")
        labelText:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", x, y)
        labelText:SetTextColor(1, 0.84, 0, 1)

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetText("--")
        valueText:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", x + labelWidth, y)

        if metric.clickable then
            valueText:EnableMouse(true)
            valueText:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and valueText._sddLinkedRun then
                    OpenRunScoreboardFromHistory(self, valueText._sddLinkedRun)
                end
            end)
            valueText:SetScript("OnEnter", function()
                if not valueText._sddLinkedRun then
                    return
                end
                if GameTooltip then
                    local run = valueText._sddLinkedRun
                    local level = run.keystoneLevel or run.dungeonLevel or 0
                    GameTooltip:SetOwner(valueText, "ANCHOR_TOP")
                    GameTooltip:SetText("Click to open scoreboard", 1, 0.84, 0)
                    GameTooltip:AddLine((run.dungeonName or "Unknown") .. " +" .. tostring(level), 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            valueText:SetScript("OnLeave", function()
                if GameTooltip then
                    GameTooltip:Hide()
                end
            end)
        end

        frame.StatValues[metric.key] = valueText
        table.insert(frame.StatLabels, labelText)
        end -- not spacer
    end
    
    -- Run history header
    local rows = math.ceil(#metricDefs / columns)
    local historyHeaderY = gridTopY - (rows * rowHeight) - 10

    local statsSectionFrame = CreateFrame("Frame", nil, statsPanel)
    statsSectionFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 6, -38)
    statsSectionFrame:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", -6, -38)
    statsSectionFrame:SetPoint("BOTTOMLEFT", statsPanel, "TOPLEFT", 6, historyHeaderY + 6)
    statsSectionFrame:SetPoint("BOTTOMRIGHT", statsPanel, "TOPRIGHT", -6, historyHeaderY + 6)
    SetBackdropCompat(statsSectionFrame, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})

    local historyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    historyLabel:SetText("Recent Runs:")
    historyLabel:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY)
    historyLabel:SetTextColor(1, 0.84, 0, 1)
    frame.HistoryLabel = historyLabel

    -- Auto-report to party toggle (mirrors the same setting on the scoreboard)
    local autoReportCheck = CreateFrame("CheckButton", "StormsDungeonDataHistoryAutoReportCheck", statsPanel, "UICheckButtonTemplate")
    autoReportCheck:SetSize(24, 24)
    autoReportCheck:SetPoint("LEFT", historyLabel, "RIGHT", 16, 0)
    autoReportCheck.text:ClearAllPoints()
    autoReportCheck.text:SetPoint("LEFT", autoReportCheck, "RIGHT", 2, 0)
    autoReportCheck.text:SetJustifyH("LEFT")
    autoReportCheck.text:SetText("Auto-report to party")
    autoReportCheck.text:SetTextColor(0.9, 0.9, 0.9, 1)

    local function GetAutoReportSettingForHistory()
        if StormsDungeonDataDB and StormsDungeonDataDB.settings then
            return StormsDungeonDataDB.settings.autoReportToParty == true
        end
        return false
    end

    autoReportCheck:SetChecked(GetAutoReportSettingForHistory())
    autoReportCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if StormsDungeonDataDB then
            StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
            StormsDungeonDataDB.settings.autoReportToParty = checked
        end
        local sbCheck = _G["StormsDungeonDataAutoReportCheck"]
        if sbCheck and sbCheck.SetChecked then
            sbCheck:SetChecked(checked)
        end
    end)
    frame.AutoReportCheck = autoReportCheck

    -- Player tooltip toggle
    local tooltipCheck = CreateFrame("CheckButton", "StormsDungeonDataHistoryPlayerTooltipCheck", statsPanel, "UICheckButtonTemplate")
    tooltipCheck:SetSize(24, 24)
    tooltipCheck:SetPoint("LEFT", autoReportCheck.text, "RIGHT", 20, 0)
    tooltipCheck.text:ClearAllPoints()
    tooltipCheck.text:SetPoint("LEFT", tooltipCheck, "RIGHT", 2, 0)
    tooltipCheck.text:SetJustifyH("LEFT")
    tooltipCheck.text:SetText("Player tooltip ratings")
    tooltipCheck.text:SetTextColor(0.9, 0.9, 0.9, 1)

    local function GetPlayerTooltipSettingForHistory()
        if StormsDungeonDataDB and StormsDungeonDataDB.settings then
            local v = StormsDungeonDataDB.settings.playerTooltipEnabled
            if v ~= nil then
                return v == true
            end
        end
        return false
    end

    tooltipCheck:SetChecked(GetPlayerTooltipSettingForHistory())
    tooltipCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if StormsDungeonDataDB then
            StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
            StormsDungeonDataDB.settings.playerTooltipEnabled = checked
        end
    end)
    frame.PlayerTooltipCheck = tooltipCheck

    -- Recent runs column headers
    local headerBg = statsPanel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetHeight(18)
    headerBg:SetWidth(840)
    headerBg:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY - 20)
    headerBg:SetColorTexture(0.12, 0.12, 0.18, 0.35)
    frame.RunHeaderBg = headerBg
    frame.RunColumnHeaders = {}

    local function HeaderText(text, x, width, justify)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10 + x, historyHeaderY - 18)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetTextColor(1, 0.84, 0, 1)
        fs:SetText(text)
        table.insert(frame.RunColumnHeaders, fs)
        return fs
    end

    local colX = 5
    HeaderText("Dungeon", colX, 155, "LEFT"); colX = colX + 155
    HeaderText("Key", colX, 35, "CENTER"); colX = colX + 35
    HeaderText("Time", colX, 55, "CENTER"); colX = colX + 55
    -- No Result column: failed runs shown by red Time text
    HeaderText("Spec", colX, 50, "CENTER"); colX = colX + 50
    HeaderText("Hero", colX, 75, "CENTER"); colX = colX + 90
    HeaderText("Date", colX, 50, "CENTER"); colX = colX + 50
    HeaderText("Damage", colX, 70, "RIGHT"); colX = colX + 70
    HeaderText("DPS", colX, 50, "RIGHT"); colX = colX + 50
    HeaderText("Healing", colX, 70, "RIGHT"); colX = colX + 70
    HeaderText("HPS", colX, 50, "RIGHT"); colX = colX + 50
    HeaderText("INT", colX, 50, "CENTER"); colX = colX + 50
    HeaderText("DISP", colX, 40, "CENTER"); colX = colX + 40
    HeaderText("Avoid Dmg", colX, 65, "CENTER"); colX = colX + 65
    HeaderText("Deaths", colX, 50, "CENTER"); colX = colX + 50
    HeaderText("MVP", colX, 40, "CENTER")
    
    -- Run history scroll (reduced width to fit scrollbar within bounds, anchored right)
    frame.RunScroll, frame.RunContent = MPT.UIUtils:CreateScrollFrame(statsPanel, 860, 300)
    frame.RunScroll:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY - 40)
    frame.RunScroll:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -28, 10)
    if frame.RunContent.SetBackdrop then
        frame.RunContent:SetBackdrop(nil)
    end
    frame.RunRows = {}

    local insightsPanel = CreateFrame("Frame", nil, frame)
    insightsPanel:SetPoint("TOPLEFT", filterPanel, "BOTTOMLEFT", 0, -8)
    insightsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    SetBackdropCompat(insightsPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    insightsPanel:Hide()
    frame.InsightsPanel = insightsPanel

    -- Tier List panel
    local tierListPanel = CreateFrame("Frame", nil, frame)
    tierListPanel:SetPoint("TOPLEFT", seasonPanel, "BOTTOMLEFT", 0, -8)
    tierListPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    SetBackdropCompat(tierListPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    tierListPanel:Hide()
    frame.TierListPanel = tierListPanel

    local tierListTitle = tierListPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tierListTitle:SetPoint("TOPLEFT", tierListPanel, "TOPLEFT", 10, -10)
    tierListTitle:SetText("Spec Tier List")
    frame.TierListTitle = tierListTitle

    local tierListNote = tierListPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tierListNote:SetPoint("TOPLEFT", tierListTitle, "BOTTOMLEFT", 0, -6)
    tierListNote:SetText("Ranked by specialization across all players in YOUR season runs. The higher the key, the more weight performances have on rankings. F tier: insufficient data.")
    tierListNote:SetTextColor(0.65, 0.65, 0.65, 1)
    tierListNote:SetWidth(960)
    tierListNote:SetWordWrap(true)
    tierListNote:SetJustifyH("LEFT")
    frame.TierListNote = tierListNote

    frame.TierListScroll, frame.TierListContent = MPT.UIUtils:CreateScrollFrame(tierListPanel, 940, 500)
    frame.TierListScroll:SetPoint("TOPLEFT", tierListNote, "BOTTOMLEFT", 0, -12)
    frame.TierListScroll:SetPoint("BOTTOMRIGHT", tierListPanel, "BOTTOMRIGHT", -28, 10)
    if frame.TierListContent.SetBackdrop then
        frame.TierListContent:SetBackdrop(nil)
    end
    frame.TierListRows = {}

    if frame.InsightsScorePanel then
        frame.InsightsScorePanel:ClearAllPoints()
        frame.InsightsScorePanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -58)
        frame.InsightsScorePanel:SetPoint("BOTTOMRIGHT", insightsPanel, "TOPRIGHT", -16, 6)
    end

    local insightsTitle = insightsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    insightsTitle:SetPoint("TOPLEFT", insightsPanel, "TOPLEFT", 10, -10)
    insightsTitle:SetText("Season Insights")
    frame.InsightsTitle = insightsTitle

    frame.InsightsScroll, frame.InsightsContent = MPT.UIUtils:CreateScrollFrame(insightsPanel, 900, 420)
    frame.InsightsScroll:SetPoint("TOPLEFT", insightsPanel, "TOPLEFT", 10, -36)
    frame.InsightsScroll:SetPoint("BOTTOMRIGHT", insightsPanel, "BOTTOMRIGHT", -28, 10)
    if frame.InsightsContent.SetBackdrop then
        frame.InsightsContent:SetBackdrop(nil)
    end
    frame.InsightsRows = {}

    self.frame = frame
    self:SetActivePage(self.activePage or "history")
    return frame
end

function HistoryViewer:SetActivePage(page)
    if page == "insights" then
        self.activePage = "insights"
    elseif page == "tierlist" then
        self.activePage = "tierlist"
    else
        self.activePage = "history"
    end
    if not self.frame then
        return
    end

    local isHistory  = (self.activePage == "history")
    local isInsights = (self.activePage == "insights")
    local isTierList = (self.activePage == "tierlist")

    -- Content panels
    if self.frame.StatsPanel then
        if isHistory then self.frame.StatsPanel:Show() else self.frame.StatsPanel:Hide() end
    end
    if self.frame.InsightsPanel then
        if isInsights then self.frame.InsightsPanel:Show() else self.frame.InsightsPanel:Hide() end
    end
    if self.frame.TierListPanel then
        if isTierList then self.frame.TierListPanel:Show() else self.frame.TierListPanel:Hide() end
    end
    if self.frame.SummaryPanel then
        if isHistory then self.frame.SummaryPanel:Show() else self.frame.SummaryPanel:Hide() end
    end
    if self.frame.FilterPanel then
        if isTierList then self.frame.FilterPanel:Hide() else self.frame.FilterPanel:Show() end
    end

    -- Tab enabled states (disable the tab for the current page)
    if self.frame.HistoryTab and self.frame.HistoryTab.SetEnabled then
        self.frame.HistoryTab:SetEnabled(not isHistory)
    end
    if self.frame.InsightsTab and self.frame.InsightsTab.SetEnabled then
        self.frame.InsightsTab:SetEnabled(not isInsights)
    end
    if self.frame.TierListTab and self.frame.TierListTab.SetEnabled then
        self.frame.TierListTab:SetEnabled(not isTierList)
    end

    -- Title
    if self.frame.Title then
        if isInsights then
            self.frame.Title:SetText("Season Insights")
        elseif isTierList then
            self.frame.Title:SetText("Spec Tier List")
        else
            self.frame.Title:SetText("Run History")
        end
    end

    -- History-only widgets
    local showHistoryWidgets = isHistory
    if self.frame.StatsTitle then
        if showHistoryWidgets then self.frame.StatsTitle:Show() else self.frame.StatsTitle:Hide() end
    end
    if self.frame.HistoryLabel then
        if showHistoryWidgets then self.frame.HistoryLabel:Show() else self.frame.HistoryLabel:Hide() end
    end
    if self.frame.RunHeaderBg then
        if showHistoryWidgets then self.frame.RunHeaderBg:Show() else self.frame.RunHeaderBg:Hide() end
    end
    if self.frame.StatLabels then
        for _, fs in ipairs(self.frame.StatLabels) do
            if showHistoryWidgets then fs:Show() else fs:Hide() end
        end
    end
    if self.frame.StatValues then
        for _, fs in pairs(self.frame.StatValues) do
            if showHistoryWidgets then fs:Show() else fs:Hide() end
        end
    end
    if self.frame.RunColumnHeaders then
        for _, fs in ipairs(self.frame.RunColumnHeaders) do
            if showHistoryWidgets then fs:Show() else fs:Hide() end
        end
    end
    if self.frame.SummaryLabels then
        for _, fs in ipairs(self.frame.SummaryLabels) do
            if showHistoryWidgets then fs:Show() else fs:Hide() end
        end
    end
    if self.frame.SummaryValues then
        for _, fs in ipairs(self.frame.SummaryValues) do
            if showHistoryWidgets then fs:Show() else fs:Hide() end
        end
    end

    -- Filter panel layout helper
    local function SetDropdownVisible(dropdown, visible)
        if not dropdown then return end
        if visible then dropdown:Show() else dropdown:Hide() end
        if dropdown.FilterLabel then
            if visible then dropdown.FilterLabel:Show() else dropdown.FilterLabel:Hide() end
        end
    end

    if isInsights then
        if self.frame.FilterPanel and self.frame.SeasonPanel then
            self.frame.FilterPanel:ClearAllPoints()
            self.frame.FilterPanel:SetPoint("TOPLEFT", self.frame.SeasonPanel, "BOTTOMLEFT", 0, -4)
        end
        SetDropdownVisible(self.frame.DungeonDropdown, false)
        SetDropdownVisible(self.frame.KeystoneDropdown, false)
        SetDropdownVisible(self.frame.ResultDropdown, false)
        SetDropdownVisible(self.frame.RoleDropdown, false)
        SetDropdownVisible(self.frame.ClassSpecHeroDropdown, false)
        SetDropdownVisible(self.frame.CharacterDropdown, true)
        if self.frame.CharacterDropdown then
            self.frame.CharacterDropdown:ClearAllPoints()
            self.frame.CharacterDropdown:SetPoint("TOPLEFT", self.frame.FilterPanel, "TOPLEFT", -2, -22)
        end
        if self.frame.CharacterDropdown and self.frame.CharacterDropdown.FilterLabel then
            self.frame.CharacterDropdown.FilterLabel:ClearAllPoints()
            self.frame.CharacterDropdown.FilterLabel:SetPoint("TOPLEFT", self.frame.FilterPanel, "TOPLEFT", 18, -8)
        end
        if self.frame.ResetFiltersButton then
            self.frame.ResetFiltersButton:Hide()
        end
        if self.frame.InsightsScorePanel then self.frame.InsightsScorePanel:Show() end
        if self.frame.InsightsScoreTitle then self.frame.InsightsScoreTitle:Show() end
    elseif isHistory then
        if self.frame.FilterPanel and self.frame.SummaryPanel then
            self.frame.FilterPanel:ClearAllPoints()
            self.frame.FilterPanel:SetPoint("TOPLEFT", self.frame.SummaryPanel, "BOTTOMLEFT", 0, -12)
        end
        SetDropdownVisible(self.frame.DungeonDropdown, true)
        SetDropdownVisible(self.frame.KeystoneDropdown, true)
        SetDropdownVisible(self.frame.ResultDropdown, true)
        SetDropdownVisible(self.frame.RoleDropdown, true)
        SetDropdownVisible(self.frame.ClassSpecHeroDropdown, true)
        SetDropdownVisible(self.frame.CharacterDropdown, true)
        if self.frame.CharacterDropdown then
            self.frame.CharacterDropdown:ClearAllPoints()
            self.frame.CharacterDropdown:SetPoint("TOPLEFT", self.frame.FilterPanel, "TOPLEFT", -2, -68)
        end
        if self.frame.CharacterDropdown and self.frame.CharacterDropdown.FilterLabel then
            self.frame.CharacterDropdown.FilterLabel:ClearAllPoints()
            self.frame.CharacterDropdown.FilterLabel:SetPoint("TOPLEFT", self.frame.FilterPanel, "TOPLEFT", 18, -54)
        end
        if self.frame.ResetFiltersButton then self.frame.ResetFiltersButton:Show() end
        if self.frame.InsightsScorePanel then self.frame.InsightsScorePanel:Hide() end
        if self.frame.InsightsScoreTitle then self.frame.InsightsScoreTitle:Hide() end
    else
        -- Tier List: filter panel hidden; also hide dropdown labels since they are parented to frame, not FilterPanel
        SetDropdownVisible(self.frame.DungeonDropdown, false)
        SetDropdownVisible(self.frame.KeystoneDropdown, false)
        SetDropdownVisible(self.frame.ResultDropdown, false)
        SetDropdownVisible(self.frame.RoleDropdown, false)
        SetDropdownVisible(self.frame.ClassSpecHeroDropdown, false)
        SetDropdownVisible(self.frame.CharacterDropdown, false)
        if self.frame.ResetFiltersButton then self.frame.ResetFiltersButton:Hide() end
        if self.frame.InsightsScorePanel then self.frame.InsightsScorePanel:Hide() end
        if self.frame.InsightsScoreTitle then self.frame.InsightsScoreTitle:Hide() end
    end

    if isInsights then
        self:UpdateInsightsDisplay()
    elseif isTierList then
        self:UpdateTierListDisplay()
    else
        self:UpdateDisplay()
    end
end

function HistoryViewer:Show()
    if MPT.Scoreboard and MPT.Scoreboard.Hide then
        MPT.Scoreboard:Hide()
    end
    local frame = self:Create()
    -- Reset to nil so PopulateFilters picks the best default (current season if it has
    -- runs, otherwise the most-recently-populated past season).
    self.selectedSeasonFilter = nil
    self:ResetNonSeasonFilters()
    self:PopulateFilters()
    -- Sync auto-report checkbox with current saved setting
    if frame.AutoReportCheck then
        local v = StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.autoReportToParty
        frame.AutoReportCheck:SetChecked(v == true)
    end
    if frame.PlayerTooltipCheck then
        local v = StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.playerTooltipEnabled
        if v == nil then v = false end
        frame.PlayerTooltipCheck:SetChecked(v == true)
    end
    frame:Show()
end

function HistoryViewer:ShowAtAnchor(anchorFrame)
    if MPT.Scoreboard and MPT.Scoreboard.Hide then
        MPT.Scoreboard:Hide()
    end
    local frame = self:Create()
    self.selectedSeasonFilter = nil
    self:ResetNonSeasonFilters()
    self:PopulateFilters()
    -- Sync auto-report checkbox with current saved setting
    if frame.AutoReportCheck then
        local v = StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.autoReportToParty
        frame.AutoReportCheck:SetChecked(v == true)
    end
    if frame.PlayerTooltipCheck then
        local v = StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.playerTooltipEnabled
        if v == nil then v = false end
        frame.PlayerTooltipCheck:SetChecked(v == true)
    end

    if anchorFrame and frame then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 12, 0)
    end
    frame:Show()
end

function HistoryViewer:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function HistoryViewer:PopulateFilters()
    -- Hide any existing flyouts when repopulating
    self:HideSpecFlyout()

    local seasonCatalog = self:BuildSeasonCatalog()
    local seasonsWithData = {}
    for _, season in ipairs(seasonCatalog.ordered or {}) do
        if season.runCount and season.runCount > 0 then
            table.insert(seasonsWithData, season)
        end
    end

    if (not self.selectedSeasonFilter) or (not seasonCatalog.byKey[self.selectedSeasonFilter]) then
        local currentEntry = seasonCatalog.currentKey and seasonCatalog.byKey[seasonCatalog.currentKey]
        local currentHasRuns = currentEntry and (currentEntry.runCount or 0) > 0
        if currentHasRuns then
            -- Current season has runs — show them by default.
            self.selectedSeasonFilter = seasonCatalog.currentKey
        elseif seasonsWithData[1] then
            -- Current season is empty (e.g. just launched a new expansion) — default
            -- to the most-recently-populated season so the user sees their history
            -- immediately rather than an empty display.
            self.selectedSeasonFilter = seasonsWithData[1].key
        else
            -- No seasons have data yet; fall back to the current season entry.
            self.selectedSeasonFilter = seasonCatalog.currentKey
        end
    end

    self:RefreshSeasonDropdown(seasonCatalog)

    local seasonRuns = {}
    do
        local selected = self.selectedSeasonFilter and seasonCatalog.byKey[self.selectedSeasonFilter]
        if selected and selected.runs then
            for _, run in ipairs(selected.runs) do
                table.insert(seasonRuns, run)
            end
        end
    end
    
    local function InitializeDropdown(dropdown, items, selectedValue, defaultText, onSelect)
        UIDropDownMenu_Initialize(dropdown, function()
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.value = item.value
                -- Larger dropdown list item text.
                info.fontObject = "GameFontHighlight"
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                    UIDropDownMenu_SetText(dropdown, item.text)
                    onSelect(item)
                end
                info.checked = (item.value == selectedValue)
                UIDropDownMenu_AddButton(info)
            end
        end)

        local selectedText = defaultText
        for _, item in ipairs(items) do
            if item.value == selectedValue then
                selectedText = item.text
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(dropdown, selectedValue)
        UIDropDownMenu_SetText(dropdown, selectedText)
    end

    -- Multi-select dropdown (checkboxes, keeps menu open)
    local function InitializeMultiSelectDropdown(dropdown, items, selectedSet, defaultText, allValue, onChange)
        local function UpdateMultiSelectDropdownText()
            -- Keep the collapsed dropdown title in sync with current selections.
            local count = 0
            for _ in pairs(selectedSet) do
                count = count + 1
            end

            local displayText
            if count == 0 then
                displayText = defaultText
            elseif count == 1 then
                local selectedValue
                for value in pairs(selectedSet) do
                    selectedValue = value
                    break
                end

                for _, item in ipairs(items) do
                    if item.value == selectedValue or tostring(item.value) == tostring(selectedValue) then
                        displayText = item.text
                        break
                    end
                end

                if not displayText then
                    displayText = "1 selected"
                end
            else
                displayText = count .. " selected"
            end

            UIDropDownMenu_SetText(dropdown, displayText)
        end

        UIDropDownMenu_Initialize(dropdown, function()
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.value = item.value
                info.fontObject = "GameFontHighlight"
                info.keepShownOnClick = true  -- Keep dropdown open after clicking
                info.isNotRadio = true  -- Show checkboxes instead of radio buttons
                
                if item.value == allValue then
                    -- "All" option clears the selection
                    info.func = function()
                        for k in pairs(selectedSet) do
                            selectedSet[k] = nil
                        end
                        UpdateMultiSelectDropdownText()
                        onChange()
                    end
                    info.checked = (next(selectedSet) == nil)  -- Checked if nothing selected
                else
                    -- Regular option toggles its selection
                    info.func = function()
                        selectedSet[item.value] = not selectedSet[item.value] or nil
                        UpdateMultiSelectDropdownText()
                        onChange()
                    end
                    info.checked = (selectedSet[item.value] == true)
                end
                
                UIDropDownMenu_AddButton(info)
            end
        end)
        UpdateMultiSelectDropdownText()
    end

    -- Character dropdown
    local function ColorizeNameByClass(name, classToken)
        if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] and RAID_CLASS_COLORS[classToken].colorStr then
            return "|c" .. RAID_CLASS_COLORS[classToken].colorStr .. name .. "|r"
        end
        if MPT.Utils and MPT.Utils.GetClassColoredName then
            return MPT.Utils:GetClassColoredName(name, classToken)
        end
        return name
    end

    local function PruneSelectedSetToValidKeys(selectedSet, validSet)
        for key in pairs(selectedSet) do
            if not validSet[key] then
                selectedSet[key] = nil
            end
        end
    end

    local characters = {}
    local seenCharacters = {}
    for _, run in ipairs(seasonRuns) do
        local character = run.character or UnitName("player") or "Unknown"
        local realm = run.realm or GetRealmName() or "Unknown"
        local key = character .. "-" .. realm
        if not seenCharacters[key] then
            seenCharacters[key] = true
            table.insert(characters, {
                name = character,
                realm = realm,
                class = run.characterClass or run.class or "UNKNOWN",
            })
        end
    end
    table.sort(characters, function(a, b)
        if a.realm ~= b.realm then
            return a.realm < b.realm
        end
        return a.name < b.name
    end)
    local charItems = {
        {text = "All Characters", value = "ALL"},
    }
    for _, char in ipairs(characters) do
        local displayName = ColorizeNameByClass(char.name, char.class)
        table.insert(charItems, {
            text = displayName .. " - " .. char.realm,
            value = char.name .. "-" .. char.realm,
        })
    end

    local selectedCharValue = self.selectedCharacter or "ALL"
    if self.selectedCharacter and not seenCharacters[self.selectedCharacter] then
        self.selectedCharacter = nil
        selectedCharValue = "ALL"
    end
    InitializeDropdown(self.frame.CharacterDropdown, charItems, selectedCharValue, "All Characters", function(item)
        if item.value == "ALL" then
            self.selectedCharacter = nil
        else
            self.selectedCharacter = item.value
        end
        self:UpdateDisplay()
    end)

    -- Role dropdown (single-select)
    local roleCounts = {TANK = 0, HEALER = 0, DAMAGER = 0}
    for _, run in ipairs(seasonRuns) do
        local role = run.specRole
        if role and roleCounts[role] ~= nil then
            roleCounts[role] = roleCounts[role] + 1
        end
    end
    local roleItems = {
        {text = "All Roles", value = "ALL"},
        {text = "Tank" .. ((roleCounts.TANK > 0) and (" (" .. roleCounts.TANK .. ")") or ""), value = "TANK"},
        {text = "Healer" .. ((roleCounts.HEALER > 0) and (" (" .. roleCounts.HEALER .. ")") or ""), value = "HEALER"},
        {text = "DPS" .. ((roleCounts.DAMAGER > 0) and (" (" .. roleCounts.DAMAGER .. ")") or ""), value = "DAMAGER"},
    }
    local selectedRoleValue = self.selectedRole or "ALL"
    InitializeDropdown(self.frame.RoleDropdown, roleItems, selectedRoleValue, "All Roles", function(item)
        if item.value == "ALL" then
            self.selectedRole = nil
        else
            self.selectedRole = item.value
        end
        self:UpdateDisplay()
    end)

    -- Dungeon dropdown (multi-select)
    local dungeonCounts = {}
    local dungeonNamesByID = {}
    local dungeonNameCounts = {}
    for _, run in ipairs(seasonRuns) do
        local mapID = run.dungeonID or run.dungeonId or 0
        local name = run.dungeonName or "Unknown"
        if mapID ~= 0 then
            dungeonCounts[mapID] = (dungeonCounts[mapID] or 0) + 1
            if not dungeonNamesByID[mapID] then
                dungeonNamesByID[mapID] = name
            end
        else
            dungeonNameCounts[name] = (dungeonNameCounts[name] or 0) + 1
        end
    end

    local dungeons = {}
    for id, count in pairs(dungeonCounts) do
        table.insert(dungeons, {id = id, name = dungeonNamesByID[id] or "Unknown", count = count})
    end
    for name, count in pairs(dungeonNameCounts) do
        table.insert(dungeons, {id = 0, name = name, count = count})
    end
    table.sort(dungeons, function(a, b) return a.name < b.name end)

    local dungeonItems = {
        {text = "All Dungeons", value = "ALL"},
    }
    for _, dungeon in ipairs(dungeons) do
        local label = (MPT.Utils and MPT.Utils.GetDungeonAcronym) and MPT.Utils:GetDungeonAcronym(dungeon.name) or dungeon.name
        label = label .. " (" .. dungeon.count .. ")"
        table.insert(dungeonItems, {
            text = label,
            value = dungeon.id,
            data = dungeon,
        })
    end

    local validDungeonSet = {}
    for _, dungeon in ipairs(dungeons) do
        validDungeonSet[dungeon.id] = true
    end
    PruneSelectedSetToValidKeys(self.selectedDungeons, validDungeonSet)

    InitializeMultiSelectDropdown(self.frame.DungeonDropdown, dungeonItems, self.selectedDungeons, "All Dungeons", "ALL", function()
        self:UpdateDisplay()
    end)

    -- Keystone dropdown (multi-select)
    local keystoneLevels = {}
    local seenLevels = {}
    for _, run in ipairs(seasonRuns) do
        local level = run.dungeonLevel or run.keystoneLevel or 0
        if not seenLevels[level] then
            seenLevels[level] = true
            table.insert(keystoneLevels, level)
        end
    end
    table.sort(keystoneLevels)
    local keystoneItems = {
        {text = "All Levels", value = "ALL"},
    }
    for _, level in ipairs(keystoneLevels) do
        table.insert(keystoneItems, {
            text = "M+ " .. level,
            value = level,
        })
    end

    PruneSelectedSetToValidKeys(self.selectedKeystoneLevels, seenLevels)

    InitializeMultiSelectDropdown(self.frame.KeystoneDropdown, keystoneItems, self.selectedKeystoneLevels, "All Levels", "ALL", function()
        self:UpdateDisplay()
    end)

    -- Result dropdown (multi-select: Completed/Failed)
    local resultItems = {
        {text = "All Results", value = "ALL"},
        {text = "Completed", value = "completed"},
        {text = "Failed", value = "failed"},
    }

    InitializeMultiSelectDropdown(self.frame.ResultDropdown, resultItems, self.selectedResults, "All Results", "ALL", function()
        self:UpdateDisplay()
    end)

    -- Build hierarchical class > spec > hero talent data structure
    local runs = {}
    for _, run in ipairs(seasonRuns) do
        if not run.deleted then
            table.insert(runs, run)
        end
    end
    
    -- Static game data: all classes, specs, and hero talents
    local GAME_CLASS_DATA = {
        {token = "DEATHKNIGHT", name = "Death Knight", specs = {
            {name = "Blood", heroTalents = {"Deathbringer", "San'layn"}},
            {name = "Frost", heroTalents = {"Deathbringer", "Rider of the Apocalypse"}},
            {name = "Unholy", heroTalents = {"Rider of the Apocalypse", "San'layn"}},
        }},
        {token = "DEMONHUNTER", name = "Demon Hunter", specs = {
            {name = "Havoc", heroTalents = {"Aldrachi Reaver", "Scarred"}},
            {name = "Vengeance", heroTalents = {"Aldrachi Reaver", "Scarred"}},
            {name = "Devourer", heroTalents = {"Annihilator", "Scarred"}},
        }},
        {token = "DRUID", name = "Druid", specs = {
            {name = "Balance", heroTalents = {"Elune's Chosen", "Keeper of the Grove"}},
            {name = "Feral", heroTalents = {"Druid of the Claw", "Wildstalker"}},
            {name = "Guardian", heroTalents = {"Druid of the Claw", "Elune's Chosen"}},
            {name = "Restoration", heroTalents = {"Keeper of the Grove", "Wildstalker"}},
        }},
        {token = "EVOKER", name = "Evoker", specs = {
            {name = "Devastation", heroTalents = {"Chronowarden", "Scalecommander"}},
            {name = "Preservation", heroTalents = {"Chronowarden", "Flameshaper"}},
            {name = "Augmentation", heroTalents = {"Flameshaper", "Scalecommander"}},
        }},
        {token = "HUNTER", name = "Hunter", specs = {
            {name = "Beast Mastery", heroTalents = {"Dark Ranger", "Pack Leader"}},
            {name = "Marksmanship", heroTalents = {"Dark Ranger", "Sentinel"}},
            {name = "Survival", heroTalents = {"Pack Leader", "Sentinel"}},
        }},
        {token = "MAGE", name = "Mage", specs = {
            {name = "Arcane", heroTalents = {"Spellslinger", "Sunfury"}},
            {name = "Fire", heroTalents = {"Frostfire", "Sunfury"}},
            {name = "Frost", heroTalents = {"Frostfire", "Spellslinger"}},
        }},
        {token = "MONK", name = "Monk", specs = {
            {name = "Brewmaster", heroTalents = {"Master of Harmony", "Shado-Pan"}},
            {name = "Mistweaver", heroTalents = {"Conduit of the Celestials", "Master of Harmony"}},
            {name = "Windwalker", heroTalents = {"Conduit of the Celestials", "Shado-Pan"}},
        }},
        {token = "PALADIN", name = "Paladin", specs = {
            {name = "Holy", heroTalents = {"Herald of the Sun", "Lightsmith"}},
            {name = "Protection", heroTalents = {"Herald of the Sun", "Templar"}},
            {name = "Retribution", heroTalents = {"Lightsmith", "Templar"}},
        }},
        {token = "PRIEST", name = "Priest", specs = {
            {name = "Discipline", heroTalents = {"Archon", "Voidweaver"}},
            {name = "Holy", heroTalents = {"Archon", "Oracle"}},
            {name = "Shadow", heroTalents = {"Oracle", "Voidweaver"}},
        }},
        {token = "ROGUE", name = "Rogue", specs = {
            {name = "Assassination", heroTalents = {"Deathstalker", "Fatebound"}},
            {name = "Outlaw", heroTalents = {"Fatebound", "Trickster"}},
            {name = "Subtlety", heroTalents = {"Deathstalker", "Trickster"}},
        }},
        {token = "SHAMAN", name = "Shaman", specs = {
            {name = "Elemental", heroTalents = {"Farseer", "Stormbringer"}},
            {name = "Enhancement", heroTalents = {"Stormbringer", "Totemic"}},
            {name = "Restoration", heroTalents = {"Farseer", "Totemic"}},
        }},
        {token = "WARLOCK", name = "Warlock", specs = {
            {name = "Affliction", heroTalents = {"Diabolist", "Hellcaller"}},
            {name = "Demonology", heroTalents = {"Diabolist", "Soul Harvester"}},
            {name = "Destruction", heroTalents = {"Hellcaller", "Soul Harvester"}},
        }},
        {token = "WARRIOR", name = "Warrior", specs = {
            {name = "Arms", heroTalents = {"Colossus", "Slayer"}},
            {name = "Fury", heroTalents = {"Mountain Thane", "Slayer"}},
            {name = "Protection", heroTalents = {"Colossus", "Mountain Thane"}},
        }},
    }
    
    -- Build run counts for each class/spec/hero combination
    local runCounts = {
        classes = {},
        specs = {},
        heroTalents = {},
        specsByClass = {},          -- key: CLASS::SPEC
        heroTalentsBySpecPath = {}  -- key: CLASS::SPEC::HERO
    }
    
    -- Map spec names to class tokens for inferring class from old runs
    local specToClass = {}
    for _, classData in ipairs(GAME_CLASS_DATA) do
        for _, specData in ipairs(classData.specs) do
            specToClass[specData.name] = classData.token
        end
    end
    
    for _, run in ipairs(runs) do
        local classToken = run.class or run.characterClass
        local specName = run.specName
        local heroName = run.heroName
        
        -- Infer class from spec if missing
        if (not classToken or classToken == "") and specName then
            classToken = specToClass[specName]
        end
        
        -- Count runs for this class/spec/hero
        if classToken and classToken ~= "" then
            runCounts.classes[classToken] = (runCounts.classes[classToken] or 0) + 1
        end
        if specName and specName ~= "" then
            runCounts.specs[specName] = (runCounts.specs[specName] or 0) + 1
        end
        if heroName and heroName ~= "" then
            runCounts.heroTalents[heroName] = (runCounts.heroTalents[heroName] or 0) + 1
        end
        if classToken and classToken ~= "" and specName and specName ~= "" then
            local specKey = classToken .. "::" .. specName
            runCounts.specsByClass[specKey] = (runCounts.specsByClass[specKey] or 0) + 1
            if heroName and heroName ~= "" then
                local heroPathKey = specKey .. "::" .. heroName
                runCounts.heroTalentsBySpecPath[heroPathKey] = (runCounts.heroTalentsBySpecPath[heroPathKey] or 0) + 1
            end
        end
    end
    
    -- Store static game data and run counts for flyout menus
    MPT.HistoryViewer.gameClassData = GAME_CLASS_DATA
    MPT.HistoryViewer.runCounts = runCounts
    MPT.HistoryViewer.specToClass = specToClass
    
    -- Initialize Class/Spec/Hero dropdown with static 3-level submenu structure.
    local classByToken = {}
    for _, c in ipairs(GAME_CLASS_DATA) do
        classByToken[c.token] = c
    end

    UIDropDownMenu_Initialize(self.frame.ClassSpecHeroDropdown, function(_, level, menuList)
        level = level or 1

        if level == 1 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "All Classes"
            info.value = "ALL"
            info.isNotRadio = true
            info.func = function()
                self.selectedClassSpecHero.classes = {}
                self.selectedClassSpecHero.specs = {}
                self.selectedClassSpecHero.heroTalents = {}
                self:UpdateDisplay()
                self:UpdateClassSpecHeroText()
                self:RefreshClassSpecDropdownMenu()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        self:RefreshClassSpecDropdownMenu()
                    end)
                end
            end
            info.checked = (next(self.selectedClassSpecHero.classes) == nil and
                           next(self.selectedClassSpecHero.specs) == nil and
                           next(self.selectedClassSpecHero.heroTalents) == nil)
            UIDropDownMenu_AddButton(info, level)

            for _, classData in ipairs(GAME_CLASS_DATA) do
                local classToken = classData.token
                local count = runCounts.classes[classToken] or 0
                info = UIDropDownMenu_CreateInfo()
                info.text = (count > 0) and (classData.name .. " (" .. count .. ")") or classData.name
                info.value = classToken
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.hasArrow = true
                info.menuList = classToken
                info.func = function()
                    self.selectedClassSpecHero.classes[classToken] = not self.selectedClassSpecHero.classes[classToken] or nil
                    self:UpdateDisplay()
                    self:UpdateClassSpecHeroText()
                    self:RefreshClassSpecDropdownMenu()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            self:RefreshClassSpecDropdownMenu()
                        end)
                    end
                end
                info.checked = (self.selectedClassSpecHero.classes[classToken] == true)
                if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                    local c = RAID_CLASS_COLORS[classToken]
                    info.colorCode = string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
                end
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end

        if level == 2 then
            local classToken = menuList
            local classData = classByToken[classToken]
            if not classData then return end

            for _, specData in ipairs(classData.specs) do
                local specName = specData.name
                local specKey = classToken .. "::" .. specName
                local count = runCounts.specsByClass[specKey] or 0
                local info = UIDropDownMenu_CreateInfo()
                info.text = (count > 0) and (specName .. " (" .. count .. ")") or specName
                info.value = specName
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.hasArrow = true
                info.menuList = { classToken = classToken, specName = specName, specKey = specKey, heroTalents = specData.heroTalents }
                info.func = function()
                    self.selectedClassSpecHero.specs[specKey] = not self.selectedClassSpecHero.specs[specKey] or nil
                    self:UpdateDisplay()
                    self:UpdateClassSpecHeroText()
                    self:RefreshClassSpecDropdownMenu()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            self:RefreshClassSpecDropdownMenu()
                        end)
                    end
                end
                info.checked = (self.selectedClassSpecHero.specs[specKey] == true)
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end

        if level == 3 then
            local payload = menuList
            if type(payload) ~= "table" or type(payload.heroTalents) ~= "table" then return end
            local specKey = payload.specKey or ((payload.classToken or "UNKNOWN") .. "::" .. (payload.specName or "Unknown"))
            for _, heroName in ipairs(payload.heroTalents) do
                local heroPathKey = specKey .. "::" .. heroName
                local count = runCounts.heroTalentsBySpecPath[heroPathKey] or 0
                local info = UIDropDownMenu_CreateInfo()
                info.text = (count > 0) and (heroName .. " (" .. count .. ")") or heroName
                info.value = heroName
                info.isNotRadio = true
                info.keepShownOnClick = true
                info.func = function()
                    self.selectedClassSpecHero.heroTalents[heroPathKey] = not self.selectedClassSpecHero.heroTalents[heroPathKey] or nil
                    self:UpdateDisplay()
                    self:UpdateClassSpecHeroText()
                    self:RefreshClassSpecDropdownMenu()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            self:RefreshClassSpecDropdownMenu()
                        end)
                    end
                end
                info.checked = (self.selectedClassSpecHero.heroTalents[heroPathKey] == true)
                UIDropDownMenu_AddButton(info, level)
            end
            return
        end
    end)
    
    self:UpdateClassSpecHeroText()

    self:UpdateDisplay()
    if self.activePage == "insights" then
        self:UpdateInsightsDisplay()
    elseif self.activePage == "tierlist" then
        self:UpdateTierListDisplay()
    end
end

function HistoryViewer:UpdateInsightsDisplay()
    if not self.frame or not self.frame.InsightsContent then
        return
    end

    for _, row in ipairs(self.frame.InsightsRows or {}) do
        row:Hide()
    end
    self.frame.InsightsRows = {}

    local content = self.frame.InsightsContent
    local y = 0

    local function FormatSignedDuration(seconds)
        local value = math.floor(seconds or 0)
        local sign = ""
        if value > 0 then
            sign = "+"
        elseif value < 0 then
            sign = "-"
            value = math.abs(value)
        end
        return sign .. MPT.Utils:FormatDuration(value)
    end

    local function UpdateInsightsScorePanel(insightsData)
        if not self.frame or not self.frame.InsightsScorePanel or not self.frame.InsightsScoreRows or not self.frame.InsightsScoreContent then
            return
        end
        local score7 = (insightsData and insightsData.scoreProgress7d) or {}
        local scoreCharacters = {}
        for _, p in ipairs((score7 and score7.characters) or {}) do
            if (tonumber(p.gained) or 0) > 0 then
                table.insert(scoreCharacters, p)
            end
        end

        local function GetNiceScaleMax(value)
            local v = tonumber(value) or 0
            if v <= 0 then return 25 end
            local padded = math.floor((v * 1.1) + 0.5)
            local magnitude = 10 ^ math.floor(math.log10(math.max(1, padded)))
            local normalized = padded / magnitude
            local step = (normalized <= 1 and 1) or (normalized <= 2 and 2) or (normalized <= 5 and 5) or 10
            return step * magnitude
        end

        local maxGained = 0
        for _, p in ipairs(scoreCharacters) do
            maxGained = math.max(maxGained, p.gained or 0)
        end
        local chartMax = GetNiceScaleMax(maxGained)

        local contentFrame = self.frame.InsightsScoreContent
        local rowHeight = 17
        local function EnsureRow(index)
            local row = self.frame.InsightsScoreRows[index]
            if row then
                return row
            end

            row = CreateFrame("Frame", nil, contentFrame)
            row:SetSize(596, 16)
            row:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -((index - 1) * rowHeight))

            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            nameText:SetPoint("LEFT", row, "LEFT", 0, 0)
            nameText:SetWidth(180)
            nameText:SetJustifyH("LEFT")
            nameText:SetText("")

            local barBg = row:CreateTexture(nil, "BACKGROUND")
            barBg:SetPoint("LEFT", row, "LEFT", 184, 0)
            barBg:SetSize(280, 10)
            barBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)

            local bar = CreateFrame("StatusBar", nil, row)
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            bar:SetPoint("LEFT", row, "LEFT", 184, 0)
            bar:SetSize(280, 10)
            bar:SetMinMaxValues(0, 1)
            bar:SetValue(0)
            bar:SetStatusBarColor(0.20, 0.75, 1.00, 1)

            local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valueText:SetPoint("LEFT", row, "LEFT", 470, 0)
            valueText:SetWidth(120)
            valueText:SetJustifyH("LEFT")
            valueText:SetText("")

            row.NameText = nameText
            row.Bar = bar
            row.ValueText = valueText
            self.frame.InsightsScoreRows[index] = row
            return row
        end

        for _, row in ipairs(self.frame.InsightsScoreRows) do
            row:Hide()
        end

        for i, p in ipairs(scoreCharacters) do
            local row = EnsureRow(i)
            local displayName = (MPT.Utils and MPT.Utils.GetClassColoredName and p.name)
                and (MPT.Utils:GetClassColoredName(p.name, p.class) .. "-" .. (p.realm or "Unknown"))
                or ((p.name or "Unknown") .. "-" .. (p.realm or "Unknown"))
            row.NameText:SetText(displayName)
            row.Bar:SetMinMaxValues(0, chartMax)
            row.Bar:SetValue(math.max(0, math.min(chartMax, p.gained or 0)))
            row.ValueText:SetText("+" .. MPT.Utils:FormatNumber(math.floor(p.gained or 0)))
            row:Show()
        end

        if self.frame.InsightsScoreEmpty then
            if #scoreCharacters > 0 then
                self.frame.InsightsScoreEmpty:Hide()
            else
                self.frame.InsightsScoreEmpty:Show()
            end
        end

        local contentHeight = math.max(1, #scoreCharacters * rowHeight)
        contentFrame:SetHeight(contentHeight)
        if self.frame.InsightsScoreScroll and self.frame.InsightsScoreScroll.UpdateScrollChildRect then
            self.frame.InsightsScoreScroll:UpdateScrollChildRect()
        end
    end

    local insights = self:BuildInsightsData()
    if not insights then
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        fs:SetWidth(860)
        fs:SetJustifyH("LEFT")
        fs:SetText("No runs available for the selected season.")
        fs:SetTextColor(1, 0.35, 0.35, 1)
        table.insert(self.frame.InsightsRows, fs)
        UpdateInsightsScorePanel(nil)
        content:SetHeight(math.max(y, 1))
        return
    end
    UpdateInsightsScorePanel(insights)

    local cardBackdrop = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    }

    local wrapWidth = 828
    local measureText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    measureText:SetWidth(wrapWidth)
    measureText:SetJustifyH("LEFT")
    if measureText.SetWordWrap then
        measureText:SetWordWrap(true)
    end
    if measureText.SetNonSpaceWrap then
        measureText:SetNonSpaceWrap(false)
    end
    measureText:Hide()

    local function GetWrappedLineHeight(text)
        measureText:SetText(tostring(text or ""))
        return math.max(16, math.floor((measureText:GetStringHeight() or 16) + 2))
    end

    local function AddCard(title, lines)
        lines = lines or {}
        local titleHeight = 22
        local padding = 10
        local bodyHeight = 0
        for _, line in ipairs(lines) do
            if type(line) == "table" and line.type == "bar" then
                bodyHeight = bodyHeight + 20
            elseif type(line) == "table" and line.type == "tableRow" then
                bodyHeight = bodyHeight + 18
            else
                bodyHeight = bodyHeight + GetWrappedLineHeight(line)
            end
        end
        local height = titleHeight + bodyHeight + padding
        if height < 44 then
            height = 44
        end

        local card = CreateFrame("Frame", nil, content)
        card:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        card:SetSize(854, height)
        SetBackdropCompat(card, cardBackdrop, {0.06, 0.06, 0.08, 0.72}, {0.45, 0.45, 0.45, 0.75})

        local titleFs = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleFs:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -8)
        titleFs:SetText(title)
        titleFs:SetTextColor(1, 0.84, 0, 1)

        local divider = card:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.12)
        divider:SetPoint("TOPLEFT", card, "TOPLEFT", 8, -24)
        divider:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -24)
        divider:SetHeight(1)

        local lineY = -30
        for _, line in ipairs(lines) do
            if type(line) == "table" and line.type == "bar" then
                local label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("TOPLEFT", card, "TOPLEFT", 12, lineY)
                label:SetWidth(240)
                label:SetJustifyH("LEFT")
                label:SetText(line.label or "")

                local barBg = card:CreateTexture(nil, "BACKGROUND")
                barBg:SetPoint("TOPLEFT", card, "TOPLEFT", 250, lineY - 2)
                barBg:SetSize(430, 12)
                barBg:SetColorTexture(0.12, 0.12, 0.12, 0.9)

                local bar = CreateFrame("StatusBar", nil, card)
                bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                bar:SetPoint("TOPLEFT", card, "TOPLEFT", 250, lineY - 2)
                bar:SetSize(430, 12)
                local maxValue = line.maxValue or 100
                local value = line.value or 0
                if maxValue <= 0 then
                    maxValue = 1
                end
                if value < 0 then
                    value = 0
                end
                if value > maxValue then
                    value = maxValue
                end
                bar:SetMinMaxValues(0, maxValue)
                bar:SetValue(value)
                local c = line.color or {0.2, 0.7, 1.0, 1}
                bar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)

                local valueText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                valueText:SetPoint("TOPLEFT", card, "TOPLEFT", 688, lineY)
                valueText:SetWidth(150)
                valueText:SetJustifyH("LEFT")
                valueText:SetText(line.text or tostring(line.value or 0))

                lineY = lineY - 20
            elseif type(line) == "table" and line.type == "tableRow" then
                local x = 12
                for _, col in ipairs(line.columns or {}) do
                    local colWidth = col.width or 90
                    local fs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, lineY)
                    fs:SetWidth(colWidth)
                    fs:SetJustifyH(col.align or "LEFT")
                    fs:SetText(col.text or "")
                    if col.color and fs.SetTextColor then
                        fs:SetTextColor(col.color[1] or 1, col.color[2] or 1, col.color[3] or 1, col.color[4] or 1)
                    end
                    x = x + colWidth
                end
                lineY = lineY - 18
            else
                local fs = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetPoint("TOPLEFT", card, "TOPLEFT", 12, lineY)
                fs:SetWidth(wrapWidth)
                fs:SetJustifyH("LEFT")
                if fs.SetWordWrap then
                    fs:SetWordWrap(true)
                end
                if fs.SetNonSpaceWrap then
                    fs:SetNonSpaceWrap(false)
                end
                fs:SetText(line)
                lineY = lineY - GetWrappedLineHeight(line)
            end
        end

        table.insert(self.frame.InsightsRows, card)
        y = y + height + 8
    end

    local summaryLines = {
        string.format("Total runs: %d", insights.totalRuns or 0),
    }
    if insights.bestDungeon then
        table.insert(summaryLines, string.format(
            "Best dungeon: %s (avg timed +%.1f, completion %d%%)",
            insights.bestDungeon.name or "Unknown",
            insights.bestDungeon.avgTimedLevel or 0,
            math.floor((insights.bestDungeon.completionRate or 0) * 100 + 0.5)
        ))
    end
    
    -- Display character rankings as a table
    local rankedCharacters = {}
    if insights.allCharacters and #insights.allCharacters > 0 then
        rankedCharacters = insights.allCharacters
    elseif insights.bestCharacter then
        rankedCharacters = {insights.bestCharacter}
    end

    local function FormatCompactHundredth(value)
        local numeric = tonumber(value) or 0
        local absValue = math.abs(numeric)
        if absValue >= 1000000000 then
            return string.format("%.2fB", numeric / 1000000000)
        elseif absValue >= 1000000 then
            return string.format("%.2fM", numeric / 1000000)
        elseif absValue >= 1000 then
            return string.format("%.2fK", numeric / 1000)
        end
        return string.format("%.2f", numeric)
    end

    if #rankedCharacters > 0 then
        table.insert(summaryLines, "Character ranks:")
        table.insert(summaryLines, {
            type = "tableRow",
            columns = {
                {text = "#", width = 40, color = {1, 0.84, 0, 1}},
                {text = "Character", width = 160, color = {1, 0.84, 0, 1}},
                {text = "DPS", width = 70, color = {1, 0.84, 0, 1}},
                {text = "HPS", width = 70, color = {1, 0.84, 0, 1}},
                {text = "Damage", width = 82, color = {1, 0.84, 0, 1}},
                {text = "Healing", width = 82, color = {1, 0.84, 0, 1}},
                {text = "Avoidable", width = 90, color = {1, 0.84, 0, 1}},
                {text = "Int", width = 45, color = {1, 0.84, 0, 1}, align = "RIGHT"},
                {text = "Disp", width = 45, color = {1, 0.84, 0, 1}, align = "RIGHT"},
                {text = "Deaths", width = 45, color = {1, 0.84, 0, 1}, align = "RIGHT"},
                {text = "Key", width = 52, color = {1, 0.84, 0, 1}, align = "RIGHT"},
                {text = "Comp", width = 58, color = {1, 0.84, 0, 1}, align = "RIGHT"},
            }
        })

        for i, character in ipairs(rankedCharacters) do
            table.insert(summaryLines, {
                type = "tableRow",
                columns = {
                    {text = tostring(i), width = 40},
                    {
                        text = string.format("%s-%s", MPT.Utils:GetClassColoredName(character.name, character.class), character.realm or "Unknown"),
                        width = 160
                    },
                    {text = FormatCompactHundredth(character.avgDPS or 0), width = 70},
                    {text = FormatCompactHundredth(character.avgHPS or 0), width = 70},
                    {text = FormatCompactHundredth(character.avgDamage or 0), width = 82},
                    {text = FormatCompactHundredth(character.avgHealing or 0), width = 82},
                    {text = FormatCompactHundredth(character.avgAvoidableDamage or 0), width = 90},
                    {text = string.format("%.2f", character.avgInterrupts or 0), width = 45, align = "RIGHT"},
                    {text = string.format("%.2f", character.avgDispels or 0), width = 45, align = "RIGHT"},
                    {text = string.format("%.2f", character.avgDeaths or 0), width = 45, align = "RIGHT"},
                    {text = string.format("+%.2f", character.avgTimedLevel or 0), width = 52, align = "RIGHT"},
                    {text = string.format("%.2f%%", (character.completionRate or 0) * 100), width = 58, align = "RIGHT"},
                }
            })
        end
    end
    
    if insights.seasonComparison then
        local cmp = insights.seasonComparison
        table.insert(summaryLines, string.format(
            "Vs %s: key %+0.2f, completion %+d%%, duration %s",
            cmp.previousLabel or "Previous",
            cmp.deltaTimedLevel or 0,
            math.floor((cmp.deltaCompletionRate or 0) * 100 + 0.5),
            FormatSignedDuration(cmp.deltaTimedDuration or 0)
        ))
    end
    AddCard("Season Summary", summaryLines)

    local trendLines = {}
    -- Color helpers: green = improving, light red = declining
    local colorGreen = {0.2, 1.0, 0.3, 1}
    local colorRed   = {1.0, 0.45, 0.45, 1}
    local colorGold  = {1, 0.84, 0, 1}
    local colorWhite = {1, 1, 1, 1}
    local function DeltaColor(delta, higherIsBetter)
        if not delta or delta == 0 then return colorWhite end
        return ((delta > 0) == higherIsBetter) and colorGreen or colorRed
    end
    -- Format a signed delta as compact k/M with 2 decimal places (e.g. "+103.72 k")
    local function FormatDeltaK(value)
        local n = tonumber(value) or 0
        local absn = math.abs(n)
        local sign = n >= 0 and "+" or ""
        if absn >= 1000000 then
            return string.format("%s%.2f M", sign, n / 1000000)
        elseif absn >= 1000 then
            return string.format("%s%.2f k", sign, n / 1000)
        end
        return string.format("%s%.2f", sign, n)
    end

    -- Build trend rows: overall first, then one row per character
    local allTrendRows = {}
    if insights.overallTrend then
        table.insert(allTrendRows, {label = "Overall", trend = insights.overallTrend})
    end
    for _, row in ipairs(insights.trendsPerCharacter or {}) do
        table.insert(allTrendRows, {
            label = string.format("%s-%s",
                MPT.Utils:GetClassColoredName(row.name, row.class),
                row.realm or "?"),
            trend = row.trend,
        })
    end

    if #allTrendRows == 0 then
        table.insert(trendLines, "Improvement Trends needs at least 4 runs in this season.")
    else
        -- Header: Character | DPS | HPS | Interrupts | Deaths | Key Level
        table.insert(trendLines, {
            type = "tableRow",
            columns = {
                {text = "Character",  width = 155, align = "LEFT",  color = colorGold},
                {text = "DPS",        width = 110, align = "RIGHT", color = colorGold},
                {text = "HPS",        width = 100, align = "RIGHT", color = colorGold},
                {text = "Interrupts", width = 80,  align = "RIGHT", color = colorGold},
                {text = "Dispels",    width = 70,  align = "RIGHT", color = colorGold},
                {text = "Deaths",     width = 80,  align = "RIGHT", color = colorGold},
                {text = "Key Level",  width = 80,  align = "RIGHT", color = colorGold},
            }
        })
        for _, entry in ipairs(allTrendRows) do
            local t = entry.trend
            local deltaDPS   = t.deltaDPS or 0
            local deltaHPS   = t.deltaHPS or 0
            local deltaInt   = t.deltaInterrupts or 0
            local deltaDisp  = t.deltaDispels or 0
            local deltaDeath = (t.last and t.last.avgDeaths or 0) - (t.first and t.first.avgDeaths or 0)
            local deltaKey   = t.deltaTimedLevel or 0
            table.insert(trendLines, {
                type = "tableRow",
                columns = {
                    {text = entry.label,                        width = 155, align = "LEFT"},
                    {text = FormatDeltaK(deltaDPS),             width = 110, align = "RIGHT", color = DeltaColor(deltaDPS,   true)},
                    {text = FormatDeltaK(deltaHPS),             width = 100, align = "RIGHT", color = DeltaColor(deltaHPS,   true)},
                    {text = string.format("%+.2f", deltaInt),   width = 80,  align = "RIGHT", color = DeltaColor(deltaInt,   true)},
                    {text = string.format("%+.2f", deltaDisp),  width = 70,  align = "RIGHT", color = DeltaColor(deltaDisp,  true)},
                    {text = string.format("%+.2f", deltaDeath), width = 80,  align = "RIGHT", color = DeltaColor(deltaDeath, false)},
                    {text = string.format("%+.2f", deltaKey),   width = 80,  align = "RIGHT", color = DeltaColor(deltaKey,   true)},
                }
            })
        end
    end
    AddCard("Improvement Trends", trendLines)

    local roleLines = {}
    table.insert(roleLines, "Consistency uses successful keys only (key level is ignored).")
    table.insert(roleLines, "Only dungeons with at least 3 successful runs are included.")
    table.insert(roleLines, "For each included dungeon, we compare your Damage/DPS/Healing/HPS/Interrupts/Deaths/Avoidable Damage across runs, score how similar those values are, then average across dungeons.")
    table.insert(roleLines, " ")
    
    -- Group consistency rankings by role
    local consistencyByRole = {}
    for _, row in ipairs(insights.consistencyRanking or {}) do
        local role = row.role or "UNKNOWN"
        consistencyByRole[role] = consistencyByRole[role] or {}
        table.insert(consistencyByRole[role], row)
    end
    
    -- Sort each role group by consistency score (best to worst)
    local roleOrder = {"TANK", "HEALER", "DAMAGER", "UNKNOWN"}
    for _, role in ipairs(roleOrder) do
        local roleEntries = consistencyByRole[role]
        if roleEntries then
            table.sort(roleEntries, function(a, b) return (a.score or 0) > (b.score or 0) end)
        end
    end
    
    -- Display consistency grouped by role as a table with bars
    local maxConsistencyScore = 0
    for _, row in ipairs(insights.consistencyRanking or {}) do
        maxConsistencyScore = math.max(maxConsistencyScore, row.score or 0)
    end
    if maxConsistencyScore <= 0 then
        maxConsistencyScore = 100
    end
    
    for _, role in ipairs(roleOrder) do
        local roleEntries = consistencyByRole[role]
        if roleEntries and #roleEntries > 0 then
            table.insert(roleLines, string.format("%s:", tostring(role)))
            for i, row in ipairs(roleEntries) do
                local characterName = MPT.Utils:GetClassColoredName(row.name, row.class) .. "-" .. (row.realm or "Unknown")
                local scoreValue = row.score or 0
                local variabilityPct = (row.avgVariability or 0) * 100
                table.insert(roleLines, {
                    type = "bar",
                    label = string.format("%d. %s", i, characterName),
                    value = scoreValue,
                    maxValue = maxConsistencyScore,
                    text = string.format("%.1f (%.1f%% var, %d runs)", 
                        scoreValue, 
                        variabilityPct, 
                        row.runCount or 0),
                    color = {0.2, 0.85, 0.4, 1}
                })
            end
            table.insert(roleLines, " ")
        end
    end
    AddCard("Role and Consistency", roleLines)

    local painLines = {}
    table.insert(painLines, "Shows recent dungeon pain trends from the last few weeks, compared to the prior few weeks when available.")
    local shownPain = 0
    for _, p in ipairs(insights.painPointTrends or {}) do
        local recent = p.recent or {}
        -- Do not list pain points when the recent fail rate is 0%.
        if (recent.failRate or 0) <= 0 then
            -- skip
        elseif shownPain >= 5 then
            break
        else
            shownPain = shownPain + 1
            if p.deltaRisk ~= nil then
                local trendWord = "stable"
                if p.deltaRisk > 1 then
                    trendWord = "worsening"
                elseif p.deltaRisk < -1 then
                    trendWord = "improving"
                end
                table.insert(painLines, string.format(
                    "%s: %s (risk %+0.1f) | recent fail %d%%, lost %.1fs, deaths %.1f, avoid %.0fk",
                    p.dungeonName or "Unknown",
                    trendWord,
                    p.deltaRisk or 0,
                    math.floor((recent.failRate or 0) * 100 + 0.5),
                    recent.avgTimeLost or 0,
                    recent.avgDeaths or 0,
                    (recent.avgAvoidableDamage or 0) / 1000
                ))
            else
                table.insert(painLines, string.format(
                    "%s: recent fail %d%%, lost %.1fs, deaths %.1f, avoid %.0fk (need more prior weeks for trend)",
                    p.dungeonName or "Unknown",
                    math.floor((recent.failRate or 0) * 100 + 0.5),
                    recent.avgTimeLost or 0,
                    recent.avgDeaths or 0,
                    (recent.avgAvoidableDamage or 0) / 1000
                ))
            end
        end
    end
    if shownPain == 0 then
        table.insert(painLines, "No pain points to show (all tracked dungeons are at 0% recent fail rate).")
    end
    AddCard("Trending Pain Points (Last Few Weeks)", painLines)

    local synergyLines = {}
    for i, s in ipairs(insights.synergyPairs or {}) do
        if i > 3 then break end
        table.insert(synergyLines, string.format(
            "%s: avg +%.1f, completion %d%% (%d runs)",
            s.pair or "Unknown",
            s.avgTimedLevel or 0,
            math.floor((s.completionRate or 0) * 100 + 0.5),
            s.runs or 0
        ))
    end
    if #synergyLines == 0 then
        table.insert(synergyLines, "No repeated group pairings yet.")
    end
    AddCard("Recent Synergy", synergyLines)

    local gapLines = {}
    local under = insights.underperformingMetrics or {}
    local over = insights.outperformingMetrics or {}
    if #under == 0 and #over == 0 then
        table.insert(gapLines, "No sustained personal performance gaps detected versus your role-matched teammates/baseline.")
    else
        table.insert(gapLines, "This card compares YOU against role-specific teammates (or same-role season baseline if no same-role teammate in run).")
        if #under > 0 then
            table.insert(gapLines, "Underperforming signals:")
        end
        for i, metric in ipairs(under) do
            if i > 5 then break end
            local ratioPct = math.floor((metric.ratioToTeam or 1) * 100 + 0.5)
            local ratioColor = {0.15, 0.8, 0.25, 1}
            if ratioPct < 95 then
                ratioColor = {0.95, 0.35, 0.25, 1}
            elseif ratioPct < 100 then
                ratioColor = {0.95, 0.75, 0.25, 1}
            end
            table.insert(gapLines, {
                type = "bar",
                label = string.format("%s %s", metric.role or "Role", metric.label or metric.key or "Metric"),
                value = math.max(0, math.min(120, ratioPct)),
                maxValue = 120,
                text = string.format("%d%% of role benchmark", ratioPct),
                color = ratioColor,
            })
            -- Break up statistics into organized lines
            table.insert(gapLines, string.format(
                "  Below benchmark: %d%% of runs (%d%% significantly below)",
                math.floor((metric.belowRate or 0) * 100 + 0.5),
                math.floor((metric.significantlyBelowRate or 0) * 100 + 0.5)
            ))
            table.insert(gapLines, string.format(
                "  Average deficit: %s",
                MPT.Utils:FormatNumber(math.floor(metric.avgDelta or 0))
            ))
            table.insert(gapLines, string.format(
                "  Data sources: %d peer-run, %d season-baseline",
                metric.sourcePeerCount or 0,
                metric.sourceSeasonCount or 0
            ))
            -- Add spacing between metrics
            if i < math.min(#under, 5) then
                table.insert(gapLines, " ")
            end
        end

        if #over > 0 then
            if #under > 0 then
                table.insert(gapLines, " ")
            end
            table.insert(gapLines, "Outperforming signals:")
        end
        for i, metric in ipairs(over) do
            if i > 5 then break end
            local ratioPct = math.floor((metric.ratioToTeam or 1) * 100 + 0.5)
            local ratioColor = {0.15, 0.80, 0.25, 1}
            if ratioPct > 130 then
                ratioColor = {0.10, 0.65, 0.20, 1}
            end
            table.insert(gapLines, {
                type = "bar",
                label = string.format("%s %s", metric.role or "Role", metric.label or metric.key or "Metric"),
                value = math.max(0, math.min(140, ratioPct)),
                maxValue = 140,
                text = string.format("%d%% of role benchmark", ratioPct),
                color = ratioColor,
            })
            -- Break up statistics into organized lines
            table.insert(gapLines, string.format(
                "  Above benchmark: %d%% of runs (%d%% significantly above)",
                math.floor((metric.aboveRate or 0) * 100 + 0.5),
                math.floor((metric.significantlyAboveRate or 0) * 100 + 0.5)
            ))
            table.insert(gapLines, string.format(
                "  Average surplus: %s",
                MPT.Utils:FormatNumber(math.floor(metric.avgDelta or 0))
            ))
            table.insert(gapLines, string.format(
                "  Data sources: %d peer-run, %d season-baseline",
                metric.sourcePeerCount or 0,
                metric.sourceSeasonCount or 0
            ))
            -- Add spacing between metrics
            if i < math.min(#over, 5) then
                table.insert(gapLines, " ")
            end
        end
    end
    AddCard("Your Role Performance vs Team", gapLines)

    local pbLines = {}
    for i, ev in ipairs(insights.personalBestFeed or {}) do
        if i > 5 then break end
        table.insert(pbLines, string.format(
            "%s - %s-%s in %s (%s)",
            date("%m-%d %H:%M", ev.timestamp or time()),
            MPT.Utils:GetClassColoredName(ev.characterName, ev.class),
            ev.realm or "Unknown",
            ev.dungeonName or "Unknown",
            table.concat(ev.tags or {}, ", ")
        ))
    end
    if #pbLines == 0 then
        table.insert(pbLines, "No personal-best events in this season.")
    end
    AddCard("Recent Personal Bests", pbLines)

    local recommendationLines = {}
    if not insights.recommendations or #insights.recommendations == 0 then
        table.insert(recommendationLines, "Not enough data yet for targeted recommendations.")
    else
        for i, rec in ipairs(insights.recommendations) do
            if i > 6 then break end
            table.insert(recommendationLines, "- " .. tostring(rec))
        end
    end
    AddCard("Recommendations", recommendationLines)

    content:SetHeight(math.max(y, 1))
end

-- Setup flyout submenus for class dropdown buttons (appears on hover like reference image)
function HistoryViewer:SetupClassFlyouts()
    local dropdown = DropDownList1
    if not dropdown or not dropdown:IsShown() then return end
    
    local gameClassData = MPT.HistoryViewer.gameClassData
    if not gameClassData then return end
    
    -- Hook dropdown OnLeave to hide flyouts (only once globally)
    if not MPT.HistoryViewer.dropdownLeaveHooked then
        MPT.HistoryViewer.dropdownLeaveHooked = true
        dropdown:HookScript("OnLeave", function()
            C_Timer.After(0.15, function()
                if not MouseIsOver(MPT.HistoryViewer.specFlyout or CreateFrame("Frame")) and 
                   not MouseIsOver(MPT.HistoryViewer.heroFlyout or CreateFrame("Frame")) then
                    self:HideSpecFlyout()
                end
            end)
        end)
    end
    
    -- Create a lookup table for quick class data access
    local classLookup = {}
    for _, classData in ipairs(gameClassData) do
        classLookup[classData.token] = classData
    end
    
    -- Find all buttons in the dropdown
    for i = 1, dropdown and UIDROPDOWNMENU_MAXBUTTONS or 0 do
        local button = _G["DropDownList1Button" .. i]
        if button and button:IsShown() and button.arg1 then
            local classToken = button.arg1
            local classData = classLookup[classToken]
            
            if classData and not button.staticFlyoutHooked then
                button.staticFlyoutHooked = true
                
                button:HookScript("OnEnter", function(btn)
                    local token = btn.arg1
                    local data = btn.arg2
                    if token and data then
                        self:ShowSpecFlyout(btn, token, data)
                    end
                end)
                
                button:HookScript("OnLeave", function(btn)
                    C_Timer.After(0.1, function()
                        if not MouseIsOver(MPT.HistoryViewer.specFlyout or CreateFrame("Frame")) then
                            self:HideSpecFlyout()
                        end
                    end)
                end)
            end
        end
    end
end

-- Show spec flyout to the right of class button
function HistoryViewer:ShowSpecFlyout(parentButton, classToken, classData)
    self:HideHeroFlyout()
    
    local flyout = MPT.HistoryViewer.specFlyout
    if not flyout then
        flyout = CreateFrame("Frame", "MPT_SpecFlyout", UIParent)
        flyout:SetSize(200, 300)
        flyout:SetFrameStrata("FULLSCREEN_DIALOG")
        flyout:SetFrameLevel(100)
        
        local backdrop = {
            bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = {left = 3, right = 3, top = 3, bottom = 3}
        }
        SetBackdropCompat(flyout, backdrop, {0.1, 0.1, 0.1, 0.95}, {0.4, 0.4, 0.4, 1})
        
        flyout.buttons = {}
        MPT.HistoryViewer.specFlyout = flyout
        
        flyout:SetScript("OnLeave", function()
            C_Timer.After(0.1, function()
                if not MouseIsOver(parentButton) and not MouseIsOver(MPT.HistoryViewer.heroFlyout or CreateFrame("Frame")) then
                    self:HideSpecFlyout()
                end
            end)
        end)
    end
    
    -- Clear old buttons
    for _, btn in ipairs(flyout.buttons) do
        btn:Hide()
    end
    flyout.buttons = {}
    
    local runCounts = MPT.HistoryViewer.runCounts or {classes = {}, specs = {}, heroTalents = {}}
    
    local yOffset = -10
    for _, specData in ipairs(classData.specs) do
        local specName = specData.name
        local count = runCounts.specs[specName] or 0
        local btn = CreateFrame("CheckButton", nil, flyout)
        btn:SetSize(170, 20)
        btn:SetPoint("TOP", flyout, "TOP", 0, yOffset)
        
        -- Highlight texture on hover
        local highlight = btn:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0)
        btn.highlight = highlight
        
        local checkbox = btn:CreateTexture(nil, "ARTWORK")
        checkbox:SetSize(16, 16)
        checkbox:SetPoint("LEFT", btn, "LEFT", 5, 0)
        if self.selectedClassSpecHero.specs[specName] then
            checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Check")
        else
            checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Up")
        end
        btn.checkbox = checkbox
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        if count > 0 then
            text:SetText(specName .. " (" .. count .. ")")
        else
            text:SetText(specName)
        end
        btn.text = text
        
        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(12, 12)
        arrow:SetPoint("RIGHT", btn, "RIGHT", -5, 0)
        arrow:SetTexture("Interface/Buttons/UI-MicroButton-CharacterInfo-Up")
        arrow:SetTexCoord(0.5, 1, 0, 0.5)  -- Right-pointing arrow
        btn.arrow = arrow
        
        btn:SetScript("OnClick", function()
            self.selectedClassSpecHero.specs[specName] = not self.selectedClassSpecHero.specs[specName] or nil
            if self.selectedClassSpecHero.specs[specName] then
                checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Check")
            else
                checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Up")
            end
            self:UpdateDisplay()
            self:UpdateClassSpecHeroText()
        end)
        
        btn:SetScript("OnEnter", function(self2)
            highlight:SetAlpha(0.5)
            text:SetTextColor(1, 1, 0)
            HistoryViewer:ShowHeroFlyout(btn, classToken, specName, specData)
        end)
        
        btn:SetScript("OnLeave", function(self2)
            highlight:SetAlpha(0)
            text:SetTextColor(1, 1, 1)
            C_Timer.After(0.1, function()
                if not MouseIsOver(MPT.HistoryViewer.heroFlyout or CreateFrame("Frame")) then
                    HistoryViewer:HideHeroFlyout()
                end
            end)
        end)
        
        table.insert(flyout.buttons, btn)
        btn:Show()
        yOffset = yOffset - 22
    end
    
    flyout:SetHeight(math.max(50, (#classData.specs * 22) + 20))
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", parentButton, "TOPRIGHT", 0, 0)
    flyout:Show()
end

-- Show hero talent flyout to the right of spec button
function HistoryViewer:ShowHeroFlyout(parentButton, classToken, specName, specData)
    local flyout = MPT.HistoryViewer.heroFlyout
    if not flyout then
        flyout = CreateFrame("Frame", "MPT_HeroFlyout", UIParent)
        flyout:SetSize(200, 200)
        flyout:SetFrameStrata("FULLSCREEN_DIALOG")
        flyout:SetFrameLevel(101)
        
        local backdrop = {
            bgFile = "Interface/DialogFrame/UI-DialogBox-Background-Dark",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = {left = 3, right = 3, top = 3, bottom = 3}
        }
        SetBackdropCompat(flyout, backdrop, {0.1, 0.1, 0.1, 0.95}, {0.4, 0.4, 0.4, 1})
        
        flyout.buttons = {}
        MPT.HistoryViewer.heroFlyout = flyout
        
        flyout:SetScript("OnLeave", function()
            C_Timer.After(0.1, function()
                if not MouseIsOver(parentButton) and not MouseIsOver(MPT.HistoryViewer.specFlyout or CreateFrame("Frame")) then
                    self:HideHeroFlyout()
                end
            end)
        end)
    end
    
    -- Clear old buttons
    for _, btn in ipairs(flyout.buttons) do
        btn:Hide()
    end
    flyout.buttons = {}
    
    local runCounts = MPT.HistoryViewer.runCounts or {classes = {}, specs = {}, heroTalents = {}}
    
    -- specData is now the static data with heroTalents array
    local heroTalents = specData.heroTalents or {}
    
    if #heroTalents == 0 then
        flyout:Hide()
        return
    end
    
    local yOffset = -10
    for _, heroName in ipairs(heroTalents) do
        local count = runCounts.heroTalents[heroName] or 0
        local btn = CreateFrame("CheckButton", nil, flyout)
        btn:SetSize(170, 20)
        btn:SetPoint("TOP", flyout, "TOP", 0, yOffset)
        
        -- Highlight texture on hover
        local highlight = btn:CreateTexture(nil, "BACKGROUND")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0)
        btn.highlight = highlight
        
        local checkbox = btn:CreateTexture(nil, "ARTWORK")
        checkbox:SetSize(16, 16)
        checkbox:SetPoint("LEFT", btn, "LEFT", 5, 0)
        if self.selectedClassSpecHero.heroTalents[heroName] then
            checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Check")
        else
            checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Up")
        end
        btn.checkbox = checkbox
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
        if count > 0 then
            text:SetText(heroName .. " (" .. count .. ")")
        else
            text:SetText(heroName)
        end
        btn.text = text
        
        btn:SetScript("OnClick", function()
            self.selectedClassSpecHero.heroTalents[heroName] = not self.selectedClassSpecHero.heroTalents[heroName] or nil
            if self.selectedClassSpecHero.heroTalents[heroName] then
                checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Check")
            else
                checkbox:SetTexture("Interface/Buttons/UI-CheckBox-Up")
            end
            self:UpdateDisplay()
            self:UpdateClassSpecHeroText()
        end)
        
        btn:SetScript("OnEnter", function()
            highlight:SetAlpha(0.5)
            text:SetTextColor(1, 1, 0)
        end)
        
        btn:SetScript("OnLeave", function()
            highlight:SetAlpha(0)
            text:SetTextColor(1, 1, 1)
        end)
        
        table.insert(flyout.buttons, btn)
        btn:Show()
        yOffset = yOffset - 22
    end
    
    flyout:SetHeight(math.max(50, (#heroTalents * 22) + 20))
    flyout:ClearAllPoints()
    flyout:SetPoint("TOPLEFT", parentButton, "TOPRIGHT", 0, 0)
    flyout:Show()
end

function HistoryViewer:HideSpecFlyout()
    if MPT.HistoryViewer.specFlyout then
        MPT.HistoryViewer.specFlyout:Hide()
    end
    self:HideHeroFlyout()
end

function HistoryViewer:HideHeroFlyout()
    if MPT.HistoryViewer.heroFlyout then
        MPT.HistoryViewer.heroFlyout:Hide()
    end
end

-- Force dropdown checkmarks to refresh immediately while menu remains open.
function HistoryViewer:RefreshClassSpecDropdownMenu()
    if not self.frame or not self.frame.ClassSpecHeroDropdown then
        return
    end
    if UIDropDownMenu_RefreshAll then
        UIDropDownMenu_RefreshAll(self.frame.ClassSpecHeroDropdown)
    end
    if UIDropDownMenu_Refresh then
        UIDropDownMenu_Refresh(self.frame.ClassSpecHeroDropdown, nil, 1)
        UIDropDownMenu_Refresh(self.frame.ClassSpecHeroDropdown, nil, 2)
        UIDropDownMenu_Refresh(self.frame.ClassSpecHeroDropdown, nil, 3)
    end
end

-- Update the Class/Spec/Hero dropdown button text based on selections
function HistoryViewer:UpdateClassSpecHeroText()
    if not self.frame or not self.frame.ClassSpecHeroDropdown then return end
    
    local totalSelected = 0
    for _ in pairs(self.selectedClassSpecHero.classes) do totalSelected = totalSelected + 1 end
    for _ in pairs(self.selectedClassSpecHero.specs) do totalSelected = totalSelected + 1 end
    for _ in pairs(self.selectedClassSpecHero.heroTalents) do totalSelected = totalSelected + 1 end
    
    if totalSelected == 0 then
        UIDropDownMenu_SetText(self.frame.ClassSpecHeroDropdown, "All Classes")
    elseif totalSelected == 1 then
        -- Show the single selected item
        for classToken in pairs(self.selectedClassSpecHero.classes) do
            -- Get the localized class name from static game data
            local gameClassData = MPT.HistoryViewer.gameClassData or {}
            local displayName = classToken
            for _, classData in ipairs(gameClassData) do
                if classData.token == classToken then
                    displayName = classData.name
                    break
                end
            end
            UIDropDownMenu_SetText(self.frame.ClassSpecHeroDropdown, displayName)
            return
        end
        for specName in pairs(self.selectedClassSpecHero.specs) do
            local displaySpec = specName
            local _, _, parsedSpec = string.find(specName, "^([^:]+)::(.+)$")
            if parsedSpec and parsedSpec ~= "" then
                displaySpec = parsedSpec
            end
            UIDropDownMenu_SetText(self.frame.ClassSpecHeroDropdown, displaySpec)
            return
        end
        for heroName in pairs(self.selectedClassSpecHero.heroTalents) do
            local displayHero = heroName
            local _, _, parsedHero = string.find(heroName, "^[^:]+::[^:]+::(.+)$")
            if parsedHero and parsedHero ~= "" then
                displayHero = parsedHero
            end
            UIDropDownMenu_SetText(self.frame.ClassSpecHeroDropdown, displayHero)
            return
        end
    else
        UIDropDownMenu_SetText(self.frame.ClassSpecHeroDropdown, totalSelected .. " selected")
    end
end

-- ============================================================
-- TIER LIST
-- ============================================================

function HistoryViewer:BuildTierListData()
    local runs = self:GetSeasonRuns()
    if not runs or #runs == 0 then
        return nil
    end

    local CLASS_NAMES = {
        DEATHKNIGHT = "Death Knight",
        DEMONHUNTER = "Demon Hunter",
        DRUID       = "Druid",
        EVOKER      = "Evoker",
        HUNTER      = "Hunter",
        MAGE        = "Mage",
        MONK        = "Monk",
        PALADIN     = "Paladin",
        PRIEST      = "Priest",
        ROGUE       = "Rogue",
        SHAMAN      = "Shaman",
        WARLOCK     = "Warlock",
        WARRIOR     = "Warrior",
    }

    local CLASS_ABBR = {
        DEATHKNIGHT = "DK",
        DEMONHUNTER = "DH",
        DRUID       = "Druid",
        EVOKER      = "Evoker",
        HUNTER      = "Hunt",
        MAGE        = "Mage",
        MONK        = "Monk",
        PALADIN     = "Pala",
        PRIEST      = "Priest",
        ROGUE       = "Rogue",
        SHAMAN      = "Sham",
        WARLOCK     = "Lock",
        WARRIOR     = "Warr",
    }

    -- Determine the top-20% keystone level threshold
    local allLevels = {}
    for _, run in ipairs(runs) do
        local level = run.keystoneLevel or run.dungeonLevel or 0
        if level > 0 then table.insert(allLevels, level) end
    end
    table.sort(allLevels)
    local topKeyThreshold = 0
    if #allLevels > 0 then
        local threshIdx = math.floor(#allLevels * 0.80) + 1
        topKeyThreshold = allLevels[math.min(threshIdx, #allLevels)]
    end

    -- Accumulate stats per specialization bucket (keyed by specID when available, else classToken::role)
    -- For class+role combos with only one possible spec, we can infer the specID
    -- when it was not recorded. DPS is usually ambiguous so is excluded here.
    local CLASS_ROLE_SINGLE_SPEC = {
        DEATHKNIGHT = { TANK    = 250 },                         -- Blood
        DEMONHUNTER = { TANK    = 581 },                         -- Vengeance
        DRUID       = { HEALER  = 105, TANK = 104 },             -- Restoration, Guardian
        EVOKER      = { HEALER  = 1468 },                        -- Preservation
        MONK        = { HEALER  = 270,  TANK = 268 },            -- Mistweaver, Brewmaster
        PALADIN     = { HEALER  = 65,   TANK = 66  },            -- Holy, Protection
        SHAMAN      = { HEALER  = 264 },                         -- Restoration
        WARRIOR     = { TANK    = 73  },                         -- Protection
    }

    local entries = {}
    local function EnsureEntry(p)
        local classToken = p.class
        local role = p.role
        if not classToken or classToken == "" or not role or role == "" or role == "UNKNOWN" then return nil end

        local specID = p.specID and (p.specID > 0) and p.specID or nil
        -- Without a specID, try to infer it for unambiguous class+role combos.
        if not specID then
            local classMap = CLASS_ROLE_SINGLE_SPEC[classToken]
            specID = classMap and classMap[role] or nil
        end
        -- Still no specID — truly ambiguous (e.g. a DPS Druid), skip.
        if not specID then return nil end

        local key = tostring(specID)
        -- Entry should already exist from pre-population; if somehow missing, create it now.
        if not entries[key] then
            local specName, specIconID
            if GetSpecializationInfoByID then
                local _, sName, _, sIcon = GetSpecializationInfoByID(specID)
                specName   = sName
                specIconID = sIcon
            end
            entries[key] = {
                key           = key,
                specID        = specID,
                specName      = specName or (CLASS_NAMES[classToken] or classToken),
                specIconID    = specIconID,
                classToken    = classToken,
                role          = role,
                className     = CLASS_NAMES[classToken] or classToken,
                classAbbr     = CLASS_ABBR[classToken] or classToken:sub(1,4),
                sampleCount   = 0,
                dpsCount      = 0,
                hpsCount      = 0,
                dpsSum        = 0,
                hpsSum        = 0,
                levelSum      = 0,
                timedRuns     = 0,
                totalRuns     = 0,
                topKeyCount   = 0,
                pendingRuns   = {},
            }
        end
        return entries[key]
    end

    -- Pre-populate every known spec so unseen specs still appear (they end up in F tier)
    if GetNumClasses and GetClassInfo and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        local numClasses = GetNumClasses()
        for classID = 1, numClasses do
            local _, classToken = GetClassInfo(classID)
            if classToken then
                local numSpecs = GetNumSpecializationsForClassID(classID) or 0
                for specIdx = 1, numSpecs do
                    local specID, specName, _, specIcon, role = GetSpecializationInfoForClassID(classID, specIdx)
                    if specID and specID > 0 and role and role ~= "" and role ~= "NONE" then
                        local key = tostring(specID)
                        if not entries[key] then
                            entries[key] = {
                                key         = key,
                                specID      = specID,
                                specName    = specName or (CLASS_NAMES[classToken] or classToken),
                                specIconID  = specIcon,
                                classToken  = classToken,
                                role        = role,
                                className   = CLASS_NAMES[classToken] or classToken,
                                classAbbr   = CLASS_ABBR[classToken] or classToken:sub(1,4),
                                sampleCount = 0,
                                dpsCount    = 0,
                                hpsCount    = 0,
                                dpsSum      = 0,
                                hpsSum      = 0,
                                levelSum    = 0,
                                timedRuns   = 0,
                                totalRuns   = 0,
                                topKeyCount = 0,
                                pendingRuns = {},
                            }
                        end
                    end
                end
            end
        end
    end

    -- Pass 1: collect every appearance per spec into pendingRuns.
    -- sampleCount tracks ALL appearances for the MIN_APPEARANCES gate;
    -- the stats themselves are computed from a trimmed set (see Pass 2).
    local SMALL_SPEC_THRESHOLD = 15   -- at or below this, use all runs
    local TOP_PERCENT          = 0.30 -- above threshold, use best 30% by key level
    for _, run in ipairs(runs) do
        local duration = run.duration or 0
        local failed   = RunIsFailed(run)
        local level    = run.keystoneLevel or run.dungeonLevel or 0

        if run.players then
            for _, p in ipairs(run.players) do
                if p and p.class and p.class ~= "" and p.role and p.role ~= "" and p.role ~= "UNKNOWN" then
                    local e = EnsureEntry(p)
                    if e then
                        e.sampleCount = e.sampleCount + 1
                        table.insert(e.pendingRuns, {
                            duration = duration,
                            failed   = failed,
                            level    = level,
                            p        = p,
                        })
                    end
                end
            end
        end
    end

    if not next(entries) then
        return nil
    end

    -- Pass 2: for each spec, trim to the relevant runs by spec performance, then
    -- aggregate stats from that trimmed set.
    -- ≤ SMALL_SPEC_THRESHOLD appearances → use all runs.
    -- > SMALL_SPEC_THRESHOLD appearances → keep best TOP_PERCENT by role-appropriate
    --   performance metric: DPS for DAMAGER, HPS for HEALER, DPS+HPS for TANK.
    local function GetRunPerf(r, role)
        local dps = GetDamagePerSecond(r.p, r.duration)
        local hps = GetHealingPerSecond(r.p, r.duration)
        if role == "HEALER" then
            return hps
        elseif role == "TANK" then
            return dps + hps
        else
            return dps
        end
    end
    for _, e in pairs(entries) do
        local n = #e.pendingRuns
        if n > SMALL_SPEC_THRESHOLD then
            local role = e.role
            table.sort(e.pendingRuns, function(a, b)
                return GetRunPerf(a, role) > GetRunPerf(b, role)
            end)
            local keep = math.max(1, math.floor(n * TOP_PERCENT + 0.5))
            local trimmed = {}
            for i = 1, keep do
                trimmed[i] = e.pendingRuns[i]
            end
            e.pendingRuns = trimmed
        end
        for _, r in ipairs(e.pendingRuns) do
            e.totalRuns = e.totalRuns + 1
            local dps = GetDamagePerSecond(r.p, r.duration)
            local hps = GetHealingPerSecond(r.p, r.duration)
            if dps > 0 then
                e.dpsSum   = e.dpsSum + dps
                e.dpsCount = e.dpsCount + 1
            end
            if hps > 0 then
                e.hpsSum   = e.hpsSum + hps
                e.hpsCount = e.hpsCount + 1
            end
            -- Always track the key level so untimed runs still
            -- contribute to avgLevel; completionRate penalises them.
            e.levelSum = e.levelSum + r.level
            if not r.failed then
                e.timedRuns = e.timedRuns + 1
            end
        end
        e.pendingRuns = nil  -- free memory
    end

    -- Compute averages
    for _, e in pairs(entries) do
        e.avgDPS          = e.dpsCount > 0 and (e.dpsSum / e.dpsCount) or 0
        e.avgHPS          = e.hpsCount > 0 and (e.hpsSum / e.hpsCount) or 0
        e.avgLevel        = e.totalRuns > 0 and (e.levelSum / e.totalRuns) or 0
        e.completionRate  = e.totalRuns > 0 and (e.timedRuns / e.totalRuns) or 0
    end

    -- Separate by role
    local byRole = { DAMAGER = {}, HEALER = {}, TANK = {} }
    for _, e in pairs(entries) do
        if byRole[e.role] then
            table.insert(byRole[e.role], e)
        end
    end

    -- Normalize within each role group and compute score.
    -- Performance (DPS/HPS) is multiplied by normalized avg key level before
    -- weighting, so specs that perform well only in low keys score lower than
    -- specs that put up similar numbers in harder content.  No separate top-key
    -- gate is needed — key level is already baked into the score.
    local function ScoreRoleGroup(list, role)
        if #list == 0 then return end
        local maxDPS, maxHPS, maxLevel = 0, 0, 0
        for _, e in ipairs(list) do
            if e.avgDPS > maxDPS then maxDPS = e.avgDPS end
            if e.avgHPS > maxHPS then maxHPS = e.avgHPS end
            if e.avgLevel > maxLevel then maxLevel = e.avgLevel end
        end
        if maxDPS <= 0 then maxDPS = 1 end
        if maxHPS <= 0 then maxHPS = 1 end
        if maxLevel <= 0 then maxLevel = 1 end

        for _, e in ipairs(list) do
            local nDPS  = e.avgDPS / maxDPS
            local nHPS  = e.avgHPS / maxHPS
            local nLvl  = e.avgLevel / maxLevel
            -- Completion penalty shrinks at higher key levels: at the top of the
            -- range (nLvl = 1) an untimed run is treated nearly the same as a
            -- timed one; at the bottom (nLvl ≈ 0) the full raw rate is used.
            -- effectiveComp blends completionRate toward 1.0 as nLvl rises.
            local effectiveComp = e.completionRate + (1 - e.completionRate) * nLvl

            -- Level-adjusted performance: output * level normalisation.
            -- A spec doing 300k at key 12 outscores one doing 300k at key 8.
            if role == "DAMAGER" then
                e.score = (nDPS * nLvl * 0.85) + (effectiveComp * 0.15)
            elseif role == "HEALER" then
                e.score = (nHPS * nLvl * 0.85) + (effectiveComp * 0.15)
            else -- TANK
                e.score = (nDPS * nLvl * 0.60) + (effectiveComp * 0.15) + (nHPS * nLvl * 0.25)
            end
            e.score = e.score * 100
        end
        table.sort(list, function(a, b) return (a.score or 0) > (b.score or 0) end)
    end

    ScoreRoleGroup(byRole.DAMAGER, "DAMAGER")
    ScoreRoleGroup(byRole.HEALER, "HEALER")
    ScoreRoleGroup(byRole.TANK,   "TANK")

    -- S tier: top 3 DPS + top 1 Healer + top 1 Tank.
    -- Specs with fewer than MIN_APPEARANCES recorded appearances land in F tier.
    -- High-key vs low-key distinction is handled by the score formula, not a gate.
    local MIN_APPEARANCES = 4
    local sTier    = {}
    local remaining = {}

    local function assignRole(roleList, sSlots)
        local sPicked = 0
        for _, e in ipairs(roleList) do
            if e.sampleCount < MIN_APPEARANCES then
                e.tier = "F"  -- insufficient data
            elseif sPicked < sSlots then
                e.tier = "S"
                table.insert(sTier, e)
                sPicked = sPicked + 1
            else
                table.insert(remaining, e)
            end
        end
    end

    assignRole(byRole.DAMAGER, 3)
    assignRole(byRole.HEALER, 1)
    assignRole(byRole.TANK, 1)

    -- Distribute remaining seen specs across A-D (4 buckets / quartiles)
    local TIER_LABELS = {"A", "B", "C", "D"}
    local function AssignRemainingTiers(roleList)
        local rem = {}
        for _, e in ipairs(roleList) do
            if not e.tier then table.insert(rem, e) end
        end
        local n = #rem
        if n == 0 then return end
        local perBucket = n / #TIER_LABELS
        for i, e in ipairs(rem) do
            local idx = math.min(#TIER_LABELS, math.ceil(i / math.max(perBucket, 0.0001)))
            if idx < 1 then idx = 1 end
            e.tier = TIER_LABELS[idx]
        end
    end

    AssignRemainingTiers(byRole.DAMAGER)
    AssignRemainingTiers(byRole.HEALER)
    AssignRemainingTiers(byRole.TANK)

    -- Build tier map
    local TIER_ORDER = {"S", "A", "B", "C", "D", "F"}
    local tierMap = {}
    for _, label in ipairs(TIER_ORDER) do tierMap[label] = {} end

    for _, e in pairs(entries) do
        if e.tier and tierMap[e.tier] then
            table.insert(tierMap[e.tier], e)
        end
    end

    -- Sort within each tier: S keeps DPS first, then Healer, then Tank; others by score
    local roleOrder = { DAMAGER = 1, HEALER = 2, TANK = 3 }
    for _, label in ipairs(TIER_ORDER) do
        table.sort(tierMap[label], function(a, b)
            if label == "S" then
                local ao = roleOrder[a.role] or 9
                local bo = roleOrder[b.role] or 9
                if ao ~= bo then return ao < bo end
            end
            return (a.score or 0) > (b.score or 0)
        end)
    end

    return {
        tiers     = tierMap,
        tierOrder = TIER_ORDER,
        byRole    = byRole,
    }
end

function HistoryViewer:UpdateTierListDisplay()
    if not self.frame or not self.frame.TierListContent then return end

    -- Clear old rows
    for _, obj in ipairs(self.frame.TierListRows or {}) do
        obj:Hide()
    end
    self.frame.TierListRows = {}

    local content = self.frame.TierListContent
    local y = 0

    local TIER_COLORS = {
        S = {0.90, 0.25, 0.25},
        A = {0.90, 0.50, 0.10},
        B = {0.88, 0.78, 0.10},
        C = {0.40, 0.80, 0.30},
        D = {0.22, 0.60, 0.85},
        F = {0.50, 0.35, 0.75},
    }

    local ROLE_ABBR = { DAMAGER = "DPS", HEALER = "HPS", TANK = "Tank" }

    local backdropInfo = {
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    }

    local data = self:BuildTierListData()
    if not data then
        local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -10)
        fs:SetText("No player data available for the selected season. Run some keys to populate the tier list!")
        fs:SetTextColor(0.65, 0.65, 0.65, 1)
        table.insert(self.frame.TierListRows, fs)
        content:SetHeight(60)
        return
    end

    local ROW_MIN_HEIGHT = 84
    local LABEL_WIDTH    = 52
    local CHIP_WIDTH     = 64
    local CHIP_HEIGHT    = 78
    local CHIP_SPACING   = 4
    local ROW_PADDING_V  = 3
    local ROW_V_PAD      = 6   -- vertical padding inside row (top & bottom)
    local CONTENT_WIDTH  = 900
    local CHIPS_WIDTH    = CONTENT_WIDTH - LABEL_WIDTH - 6  -- available width for chips
    local ICON_SIZE      = 44

    local CLASS_ICONS = {
        DEATHKNIGHT = "Interface/Icons/ClassIcon_DeathKnight",
        DEMONHUNTER = "Interface/Icons/ClassIcon_DemonHunter",
        DRUID       = "Interface/Icons/ClassIcon_Druid",
        EVOKER      = "Interface/Icons/ClassIcon_Evoker",
        HUNTER      = "Interface/Icons/ClassIcon_Hunter",
        MAGE        = "Interface/Icons/ClassIcon_Mage",
        MONK        = "Interface/Icons/ClassIcon_Monk",
        PALADIN     = "Interface/Icons/ClassIcon_Paladin",
        PRIEST      = "Interface/Icons/ClassIcon_Priest",
        ROGUE       = "Interface/Icons/ClassIcon_Rogue",
        SHAMAN      = "Interface/Icons/ClassIcon_Shaman",
        WARLOCK     = "Interface/Icons/ClassIcon_Warlock",
        WARRIOR     = "Interface/Icons/ClassIcon_Warrior",
    }

    for _, tierLabel in ipairs(data.tierOrder) do
        local tierEntries = data.tiers[tierLabel]
        -- Always show all tier rows (even empty ones up to F)
        local tc = TIER_COLORS[tierLabel] or {0.5, 0.5, 0.5}

        -- Calculate how many rows of chips this tier needs so we can size things upfront
        local numEntries = (tierEntries and #tierEntries) or 0
        local chipsPerRow = math.max(1, math.floor((CHIPS_WIDTH + CHIP_SPACING) / (CHIP_WIDTH + CHIP_SPACING)))
        local chipRowCount = math.max(1, math.ceil(numEntries / chipsPerRow))
        local rowHeight = ROW_V_PAD + chipRowCount * CHIP_HEIGHT + (chipRowCount - 1) * CHIP_SPACING + ROW_V_PAD
        rowHeight = math.max(rowHeight, ROW_MIN_HEIGHT)

        -- Row container (height determined above)
        local rowFrame = CreateFrame("Frame", nil, content)
        rowFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        rowFrame:SetSize(CONTENT_WIDTH, rowHeight)

        -- Tier label cell (full row height, label centered)
        local labelCell = CreateFrame("Frame", nil, rowFrame)
        labelCell:SetSize(LABEL_WIDTH, rowHeight)
        labelCell:SetPoint("LEFT", rowFrame, "LEFT", 0, 0)
        SetBackdropCompat(labelCell, backdropInfo, {tc[1]*0.9, tc[2]*0.9, tc[3]*0.9, 1.0}, {tc[1], tc[2], tc[3], 1.0})

        local labelText = labelCell:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        labelText:SetPoint("CENTER", labelCell, "CENTER", 0, 0)
        labelText:SetText(tierLabel)
        labelText:SetTextColor(1, 1, 1, 1)

        -- Chips area (fills the right portion of the row)
        local chipsArea = CreateFrame("Frame", nil, rowFrame)
        chipsArea:SetPoint("TOPLEFT",    rowFrame, "TOPLEFT",    LABEL_WIDTH + 4, -ROW_V_PAD)
        chipsArea:SetPoint("BOTTOMRIGHT",rowFrame, "BOTTOMRIGHT", 0,               ROW_V_PAD)

        -- Place chips in a wrapping grid
        local chipX = 0
        local chipY = 0
        local lineHeight = 0

        if tierEntries and #tierEntries > 0 then
            for _, entry in ipairs(tierEntries) do
                -- Wrap to next line if this chip would overflow
                if chipX > 0 and (chipX + CHIP_WIDTH) > CHIPS_WIDTH then
                    chipX = 0
                    chipY = chipY + CHIP_HEIGHT + CHIP_SPACING
                end

                -- Class color
                local cr, cg, cb = 0.8, 0.8, 0.8
                if RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.classToken] then
                    local c = RAID_CLASS_COLORS[entry.classToken]
                    cr, cg, cb = c.r, c.g, c.b
                end

                -- Resolve icon: prefer spec icon, fall back to class icon
                local iconTexture = entry.specIconID
                    or CLASS_ICONS[entry.classToken]
                    or "Interface/Icons/INV_Misc_QuestionMark"

                local chip = CreateFrame("Frame", nil, chipsArea)
                chip:SetSize(CHIP_WIDTH, CHIP_HEIGHT)
                chip:SetPoint("TOPLEFT", chipsArea, "TOPLEFT", chipX, -chipY)

                -- Chip background using the class color (darkened)
                SetBackdropCompat(chip, backdropInfo,
                    {cr * 0.28, cg * 0.28, cb * 0.28, 0.95},
                    {cr * 0.8,  cg * 0.8,  cb * 0.8,  1.0})

                -- Spec icon
                local iconTex = chip:CreateTexture(nil, "ARTWORK")
                iconTex:SetSize(ICON_SIZE, ICON_SIZE)
                iconTex:SetPoint("TOP", chip, "TOP", 0, -ROW_PADDING_V)
                iconTex:SetTexture(iconTexture)
                iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

                -- Spec name text below the icon
                local specLabel = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                specLabel:SetPoint("TOPLEFT",  chip, "TOPLEFT",  2, -(ROW_PADDING_V + ICON_SIZE + 3))
                specLabel:SetPoint("TOPRIGHT", chip, "TOPRIGHT", -2, -(ROW_PADDING_V + ICON_SIZE + 3))
                specLabel:SetJustifyH("CENTER")
                specLabel:SetWordWrap(false)
                specLabel:SetText(entry.specName or entry.classAbbr)
                specLabel:SetTextColor(cr, cg, cb, 1)

                -- Tooltip
                local tooltipTitle = entry.specName
                    .. (entry.specName ~= entry.className and (" (" .. entry.className .. ")") or "")
                    .. " - " .. (ROLE_ABBR[entry.role] or entry.role)
                chip:EnableMouse(true)
                chip:SetScript("OnEnter", function(self2)
                    if GameTooltip then
                        GameTooltip:SetOwner(self2, "ANCHOR_TOP")
                        GameTooltip:SetText(tooltipTitle, cr, cg, cb, 1)
                        if entry.role == "DAMAGER" then
                            GameTooltip:AddLine(string.format("Avg DPS: %s", MPT.Utils:FormatNumber(entry.avgDPS or 0)), 1, 1, 1)
                        elseif entry.role == "HEALER" then
                            GameTooltip:AddLine(string.format("Avg HPS: %s", MPT.Utils:FormatNumber(entry.avgHPS or 0)), 1, 1, 1)
                        else
                            GameTooltip:AddLine(string.format("Avg DPS: %s", MPT.Utils:FormatNumber(entry.avgDPS or 0)), 1, 1, 1)
                            if (entry.avgHPS or 0) > 0 then
                                GameTooltip:AddLine(string.format("Avg HPS: %s", MPT.Utils:FormatNumber(entry.avgHPS or 0)), 1, 1, 1)
                            end
                        end
                        GameTooltip:AddLine(string.format("Avg Key: +%.1f", entry.avgLevel or 0), 1, 1, 1)
                        GameTooltip:AddLine(string.format("Completion: %d%%", math.floor((entry.completionRate or 0) * 100)), 1, 1, 1)
                        GameTooltip:AddLine(string.format("Appearances: %d", entry.sampleCount or 0), 0.7, 0.7, 0.7)
                        GameTooltip:AddLine(string.format("Avg key level: %.1f", entry.avgLevel or 0), 0.7, 0.7, 0.7)
                        GameTooltip:AddLine(string.format("Score: %.1f", entry.score or 0), 0.7, 0.7, 0.7)
                        GameTooltip:Show()
                    end
                end)
                chip:SetScript("OnLeave", function()
                    if GameTooltip then GameTooltip:Hide() end
                end)

                chipX = chipX + CHIP_WIDTH + CHIP_SPACING
                table.insert(self.frame.TierListRows, chip)
            end
        end

        -- Empty-tier label if no entries
        if not tierEntries or #tierEntries == 0 then
            local emptyText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            emptyText:SetPoint("LEFT", rowFrame, "LEFT", LABEL_WIDTH + 12, 0)
            emptyText:SetText("No data")
            emptyText:SetTextColor(0.4, 0.4, 0.4, 1)
            table.insert(self.frame.TierListRows, emptyText)
        end

        -- Divider line — child of rowFrame so it renders within this row's
        -- layer, not behind subsequent rowFrames on the content texture layer.
        local divider = rowFrame:CreateTexture(nil, "OVERLAY")
        divider:SetColorTexture(1, 1, 1, 0.15)
        divider:SetHeight(1)
        divider:SetPoint("BOTTOMLEFT",  rowFrame, "BOTTOMLEFT",  0, 0)
        divider:SetPoint("BOTTOMRIGHT", rowFrame, "BOTTOMRIGHT", 0, 0)
        table.insert(self.frame.TierListRows, divider)
        table.insert(self.frame.TierListRows, rowFrame)

        y = y + rowHeight + 1
    end

    content:SetHeight(math.max(y + 10, 1))
    if self.frame.TierListScroll and self.frame.TierListScroll.UpdateScrollChildRect then
        self.frame.TierListScroll:UpdateScrollChildRect()
    end
end

-- ============================================================
-- END TIER LIST
-- ============================================================

local function OpenRunScoreboardFromHistory(historyViewer, run)
    if not historyViewer or not run then
        return
    end

    historyViewer:Hide()

    if MPT.UI and MPT.UI.ShowScoreboard then
        MPT.UI:ShowScoreboard(run)
    elseif MPT.Scoreboard and MPT.Scoreboard.Show then
        MPT.Scoreboard:Show(run)
    end
end

function HistoryViewer:UpdateDisplay()
    local function ComputeStatsFromRuns(runs, characterName)
        if not runs or #runs == 0 then
            return nil
        end
        -- Exclude soft-deleted runs from all averages and counts
        local function isDeleted(r) return r and r.deleted end
        local function NameMatchesCharacter(playerName, selectedCharacter)
            if not selectedCharacter then
                return true
            end

            local playerNorm = NormalizePlayerName(playerName)
            local selectedNorm = NormalizePlayerName(selectedCharacter)
            if not playerNorm or not selectedNorm then
                return false
            end

            if playerNorm == selectedNorm then
                return true
            end

            local playerShortNorm = NormalizePlayerName(ShortName(playerName))
            local selectedShortNorm = NormalizePlayerName(ShortName(selectedCharacter))
            return playerShortNorm and selectedShortNorm and (playerShortNorm == selectedShortNorm)
        end

        local stats = {
            totalRuns = 0,
            completedRuns = 0,
            failedRuns = 0,
            mvpRuns = 0,
            avgDuration = 0,
            avgKeystoneLevel = 0,
            avgDamage = 0,
            avgHealing = 0,
            avgInterrupts = 0,
            bestKeystoneLevel = 0,
            bestDuration = 0,
            bestTime = nil,
            bestDamage = 0,
            bestHealing = 0,
            bestInterrupts = 0,
            bestDPS = 0,
            bestHPS = 0,
            avgDPS = 0,
            avgHPS = 0,
            bestAvoidableDamage = 999999999,
            avgAvoidableDamage = 0,
            bestDeaths = 999999999,
            avgDeaths = 0,
            bestRuns = {
                bestKeystoneLevel = nil,
                bestDamage = nil,
                bestInterrupts = nil,
                bestDispels = nil,
                bestHealing = nil,
                bestDPS = nil,
                bestHPS = nil,
            },
        }

        local totalDuration = 0
        local totalLevel = 0
        local totalDamage = 0
        local totalHealing = 0
        local totalInterrupts = 0
        local totalDispels = 0
        local totalDPS = 0
        local totalHPS = 0
        local totalAvoidableDamage = 0
        local totalDeaths = 0
        local playerRunCount = 0

        local function UpdateBestMetric(metricKey, metricValue, run)
            local value = tonumber(metricValue) or 0
            if value > (stats[metricKey] or 0) then
                stats[metricKey] = value
                stats.bestRuns[metricKey] = run
            end
        end

        for _, run in ipairs(runs) do
            if isDeleted(run) then
                -- skip deleted runs
            else
                local runLevel = (run.keystoneLevel or run.dungeonLevel or 0)
                local runDuration = run.duration or 0
                stats.totalRuns = stats.totalRuns + 1
                if RunIsFailed(run) then
                    stats.failedRuns = stats.failedRuns + 1
                else
                    stats.completedRuns = stats.completedRuns + 1
                end

                -- Track MVP runs
                local mvpName = run.mvpName
                if not mvpName or mvpName == "" then
                    mvpName = (MPT.Scoreboard and MPT.Scoreboard.ComputeMVPName) and MPT.Scoreboard:ComputeMVPName(run) or nil
                end
                if mvpName and mvpName ~= "" then
                    local owner = (run.character and run.realm) and (run.character .. "-" .. run.realm) or run.character
                    if owner then
                        local mvpShort = mvpName:match("^([^%-]+)") or mvpName
                        local ownerShort = owner:match("^([^%-]+)") or owner
                        if mvpName == owner or mvpName == ownerShort or mvpShort == ownerShort then
                            stats.mvpRuns = stats.mvpRuns + 1
                        end
                    end
                end

                totalDuration = totalDuration + runDuration
                totalLevel = totalLevel + (runLevel or 0)

                local ownerStats = GetOwnerStats(run)
                local ownerName = ownerStats and (ownerStats.name or run.character) or run.character
                if ownerStats and NameMatchesCharacter(ownerName, characterName) then
                    local damage = ownerStats.damage or 0
                    local healing = ownerStats.healing or 0
                    local interrupts = ownerStats.interrupts or 0
                    local dispels = ownerStats.dispels or 0
                    local dps = GetDamagePerSecond(ownerStats, runDuration)
                    local hps = GetHealingPerSecond(ownerStats, runDuration)

                    totalDamage = totalDamage + damage
                    totalHealing = totalHealing + healing
                    totalInterrupts = totalInterrupts + interrupts
                    totalDispels = totalDispels + dispels
                    totalDPS = totalDPS + dps
                    totalHPS = totalHPS + hps
                    totalAvoidableDamage = totalAvoidableDamage + GetAvoidableDamageValue(ownerStats)
                    totalDeaths = totalDeaths + (ownerStats.deaths or 0)
                    playerRunCount = playerRunCount + 1

                    -- Abandoned keys are saved but never count toward personal bests
                    if run.abandonReason ~= "abandon" then
                        UpdateBestMetric("bestDamage", damage, run)
                        UpdateBestMetric("bestHealing", healing, run)
                        UpdateBestMetric("bestInterrupts", interrupts, run)
                        UpdateBestMetric("bestDispels", dispels, run)
                        UpdateBestMetric("bestDPS", dps, run)
                        UpdateBestMetric("bestHPS", hps, run)

                        stats.bestAvoidableDamage = math.min(stats.bestAvoidableDamage, GetAvoidableDamageValue(ownerStats))
                        stats.bestDeaths = math.min(stats.bestDeaths, ownerStats.deaths or 0)
                    end
                end

                if run.abandonReason ~= "abandon" then
                    if runLevel and runLevel > stats.bestKeystoneLevel then
                        stats.bestKeystoneLevel = runLevel
                        stats.bestRuns.bestKeystoneLevel = run
                    end

                    if run.duration and run.duration > stats.bestDuration then
                        stats.bestDuration = run.duration
                        stats.bestTime = run.timestamp
                    end
                end
            end
        end

        stats.avgDuration = stats.totalRuns > 0 and math.floor(totalDuration / stats.totalRuns) or 0
        stats.avgKeystoneLevel = stats.totalRuns > 0 and math.floor(totalLevel / stats.totalRuns) or 0
        stats.avgDamage = playerRunCount > 0 and math.floor(totalDamage / playerRunCount) or 0
        stats.avgHealing = playerRunCount > 0 and math.floor(totalHealing / playerRunCount) or 0
        stats.avgInterrupts = playerRunCount > 0 and math.floor(totalInterrupts / playerRunCount) or 0
        stats.avgDispels = playerRunCount > 0 and math.floor(totalDispels / playerRunCount) or 0
        stats.avgDPS = playerRunCount > 0 and math.floor(totalDPS / playerRunCount) or 0
        stats.avgHPS = playerRunCount > 0 and math.floor(totalHPS / playerRunCount) or 0
        stats.avgAvoidableDamage = playerRunCount > 0 and math.floor(totalAvoidableDamage / playerRunCount) or 0
        stats.avgDeaths = playerRunCount > 0 and (totalDeaths / playerRunCount) or 0
        if stats.bestAvoidableDamage == 999999999 then stats.bestAvoidableDamage = 0 end
        if stats.bestDeaths == 999999999 then stats.bestDeaths = 0 end
        stats.mvpPercent = stats.totalRuns > 0 and math.floor((stats.mvpRuns / stats.totalRuns) * 100) or 0

        return stats
    end

    local charName = nil
    local realm = nil
    if self.selectedCharacter then
        charName, realm = strsplit("-", self.selectedCharacter)
    end

    local stats
    local hasAnyFilter = (next(self.selectedDungeons) ~= nil) or self.selectedDungeon or self.selectedDungeonName
    if hasAnyFilter then
        self.frame.StatsTitle:SetText("Dungeon Statistics")
    else
        self.frame.StatsTitle:SetText("Overall Statistics")
    end
    
    -- Populate run history
    local allRuns = charName and MPT.Database:GetRunsByCharacter(charName, realm) or (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    -- When using raw DB (All Characters), exclude soft-deleted runs so they don't affect stats or list
    if not charName and allRuns then
        local filtered = {}
        for _, r in ipairs(allRuns) do
            if not r.deleted then table.insert(filtered, r) end
        end
        allRuns = filtered
    end

    -- Season split: default current season, optional past seasons.
    local seasonContext = BuildCurrentSeasonContext()
    do
        local filtered = {}
        for _, run in ipairs(allRuns) do
            if self:RunMatchesSeasonFilter(run, self.selectedSeasonFilter, seasonContext) then
                table.insert(filtered, run)
            end
        end
        allRuns = filtered
    end

    table.sort(allRuns, function(a, b)
        return (a.timestamp or 0) > (b.timestamp or 0)
    end)

    local runs = allRuns

    -- Filter by dungeon(s) if selected (multi-select)
    if next(self.selectedDungeons) ~= nil then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            local runDungeonID = run.dungeonID or run.dungeonId
            if self.selectedDungeons[runDungeonID] then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    -- Filter by keystone level(s) if selected (multi-select)
    if next(self.selectedKeystoneLevels) ~= nil then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            local runLevel = run.dungeonLevel or run.keystoneLevel
            if self.selectedKeystoneLevels[runLevel] then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end
    
    -- Filter by result (completed/failed) if selected (multi-select)
    if next(self.selectedResults) ~= nil then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            local failed = RunIsFailed(run)
            local matchesFilter = false
            if self.selectedResults["completed"] and not failed then
                matchesFilter = true
            end
            if self.selectedResults["failed"] and failed then
                matchesFilter = true
            end
            if matchesFilter then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    -- Filter by role if selected
    if self.selectedRole then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            if run.specRole == self.selectedRole then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    -- Filter by hierarchical class/spec/hero if selected
    local hasClassFilter = next(self.selectedClassSpecHero.classes) ~= nil
    local hasSpecFilter = next(self.selectedClassSpecHero.specs) ~= nil
    local hasHeroFilter = next(self.selectedClassSpecHero.heroTalents) ~= nil
    
    if hasClassFilter or hasSpecFilter or hasHeroFilter then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            local matchesFilter = false
            
            -- If any class is selected, check if run's class matches
            if hasClassFilter then
                local runClassToken = run.class or run.characterClass
                if (not runClassToken or runClassToken == "") and run.specName then
                    local specToClass = MPT.HistoryViewer and MPT.HistoryViewer.specToClass
                    runClassToken = specToClass and specToClass[run.specName] or nil
                end
                runClassToken = runClassToken or "UNKNOWN"
                if self.selectedClassSpecHero.classes[runClassToken] then
                    matchesFilter = true
                end
            end
            
            -- If any spec is selected, check if run's spec matches
            if hasSpecFilter then
                local runSpecName = run.specName or "Unknown"
                local runClassTokenForSpec = run.class or run.characterClass
                if (not runClassTokenForSpec or runClassTokenForSpec == "") and runSpecName then
                    local specToClass = MPT.HistoryViewer and MPT.HistoryViewer.specToClass
                    runClassTokenForSpec = specToClass and specToClass[runSpecName] or nil
                end
                local runSpecKey = (runClassTokenForSpec and runClassTokenForSpec ~= "") and (runClassTokenForSpec .. "::" .. runSpecName) or runSpecName
                if self.selectedClassSpecHero.specs[runSpecKey] or self.selectedClassSpecHero.specs[runSpecName] then
                    matchesFilter = true
                end
            end
            
            -- If any hero talent is selected, check if run's hero matches
            if hasHeroFilter then
                local runHeroName = run.heroName or "Unknown"
                local runSpecNameForHero = run.specName or "Unknown"
                local runClassTokenForHero = run.class or run.characterClass
                if (not runClassTokenForHero or runClassTokenForHero == "") and runSpecNameForHero then
                    local specToClass = MPT.HistoryViewer and MPT.HistoryViewer.specToClass
                    runClassTokenForHero = specToClass and specToClass[runSpecNameForHero] or nil
                end
                local runHeroKey = ((runClassTokenForHero and runClassTokenForHero ~= "") and (runClassTokenForHero .. "::" .. runSpecNameForHero) or runSpecNameForHero) .. "::" .. runHeroName
                if self.selectedClassSpecHero.heroTalents[runHeroKey] or self.selectedClassSpecHero.heroTalents[runHeroName] then
                    matchesFilter = true
                end
            end
            
            if matchesFilter then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    stats = ComputeStatsFromRuns(runs, charName)

    if stats then
        if self.frame.SummaryValues then
            self.frame.SummaryValues[1]:SetText(tostring(stats.totalRuns))
            self.frame.SummaryValues[2]:SetText(tostring(stats.completedRuns))
            self.frame.SummaryValues[3]:SetText(tostring(stats.failedRuns))
            self.frame.SummaryValues[4]:SetText(tostring(stats.avgKeystoneLevel))
        end

        if self.frame.StatValues then
            self.frame.StatValues.avgDuration:SetText(MPT.Utils:FormatDuration(stats.avgDuration))
            self.frame.StatValues.bestKeystoneLevel:SetText(tostring(stats.bestKeystoneLevel))
            self.frame.StatValues.mvpPercent:SetText(string.format("%d%%", stats.mvpPercent or 0))
            self.frame.StatValues.avgDamage:SetText(MPT.Utils:FormatNumber(stats.avgDamage))
            self.frame.StatValues.bestDamage:SetText(MPT.Utils:FormatNumber(stats.bestDamage))
            self.frame.StatValues.avgDPS:SetText(MPT.Utils:FormatNumber(stats.avgDPS or 0))
            self.frame.StatValues.bestDPS:SetText(MPT.Utils:FormatNumber(stats.bestDPS or 0))
            self.frame.StatValues.avgHealing:SetText(MPT.Utils:FormatNumber(stats.avgHealing))
            self.frame.StatValues.bestHealing:SetText(MPT.Utils:FormatNumber(stats.bestHealing))
            self.frame.StatValues.avgHPS:SetText(MPT.Utils:FormatNumber(stats.avgHPS or 0))
            self.frame.StatValues.bestHPS:SetText(MPT.Utils:FormatNumber(stats.bestHPS or 0))
            self.frame.StatValues.avgInterrupts:SetText(tostring(stats.avgInterrupts))
            self.frame.StatValues.bestInterrupts:SetText(tostring(stats.bestInterrupts))
            self.frame.StatValues.avgDispels:SetText(tostring(stats.avgDispels))
            self.frame.StatValues.bestDispels:SetText(tostring(stats.bestDispels))
            self.frame.StatValues.avgAvoidableDamage:SetText(MPT.Utils:FormatNumber(stats.avgAvoidableDamage or 0))
            self.frame.StatValues.avgDeaths:SetText(string.format("%.1f", stats.avgDeaths or 0))

            local bestMetricKeys = {
                "bestKeystoneLevel",
                "bestInterrupts",
                "bestDispels",
                "bestDamage",
                "bestDPS",
                "bestHealing",
                "bestHPS",
            }
            for _, metricKey in ipairs(bestMetricKeys) do
                local valueText = self.frame.StatValues[metricKey]
                if valueText then
                    valueText._sddLinkedRun = (stats.bestRuns and stats.bestRuns[metricKey]) or nil
                end
            end
        end
    end
    
    if not stats then
        -- No runs matched the current filter — reset all stat labels to zero so
        -- stale values from a previous filter/season don't bleed through.
        if self.frame.SummaryValues then
            self.frame.SummaryValues[1]:SetText("0")
            self.frame.SummaryValues[2]:SetText("0")
            self.frame.SummaryValues[3]:SetText("0")
            self.frame.SummaryValues[4]:SetText("0")
        end
        if self.frame.StatValues then
            self.frame.StatValues.avgDuration:SetText("--")
            self.frame.StatValues.bestKeystoneLevel:SetText("0")
            self.frame.StatValues.mvpPercent:SetText("0%")
            self.frame.StatValues.avgDamage:SetText("0")
            self.frame.StatValues.bestDamage:SetText("0")
            self.frame.StatValues.avgDPS:SetText("0")
            self.frame.StatValues.bestDPS:SetText("0")
            self.frame.StatValues.avgHealing:SetText("0")
            self.frame.StatValues.bestHealing:SetText("0")
            self.frame.StatValues.avgHPS:SetText("0")
            self.frame.StatValues.bestHPS:SetText("0")
            self.frame.StatValues.avgInterrupts:SetText("0")
            self.frame.StatValues.bestInterrupts:SetText("0")
            self.frame.StatValues.avgDispels:SetText("0")
            self.frame.StatValues.bestDispels:SetText("0")
            self.frame.StatValues.avgAvoidableDamage:SetText("0")
            self.frame.StatValues.avgDeaths:SetText("0.0")
        end
    end

    for _, row in ipairs(self.frame.RunRows) do
        row:Hide()
    end
    self.frame.RunRows = {}
    
    local function GetRunBestStats(run)
        local bestDamage, bestHealing, bestInterrupts = 0, 0, 0
        local bestDPS, bestHPS = 0, 0
        local runDuration = run.duration or 0
        if run.playerStats then
            for _, pstats in pairs(run.playerStats) do
                bestDamage = math.max(bestDamage, pstats.damage or 0)
                bestHealing = math.max(bestHealing, pstats.healing or 0)
                bestInterrupts = math.max(bestInterrupts, pstats.interrupts or 0)
                local dps = GetDamagePerSecond(pstats, runDuration)
                local hps = GetHealingPerSecond(pstats, runDuration)
                bestDPS = math.max(bestDPS, dps)
                bestHPS = math.max(bestHPS, hps)
            end
        elseif run.players then
            for _, p in ipairs(run.players) do
                bestDamage = math.max(bestDamage, p.damage or 0)
                bestHealing = math.max(bestHealing, p.healing or 0)
                bestInterrupts = math.max(bestInterrupts, p.interrupts or 0)
                local dps = GetDamagePerSecond(p, runDuration)
                local hps = GetHealingPerSecond(p, runDuration)
                bestDPS = math.max(bestDPS, dps)
                bestHPS = math.max(bestHPS, hps)
            end
        end
        return bestDamage, bestHealing, bestInterrupts, bestDPS, bestHPS
    end

    -- Get the run owner's (your) player stats for this run for display in Recent Runs.
    local function GetMyPlayerStatsInRun(run)
        local runDuration = run.duration or 0
        local ownerStats = GetOwnerStats(run)
        if not ownerStats then
            return nil
        end

        local d = ownerStats.damage or 0
        local h = ownerStats.healing or 0
        return {
            damage = d,
            healing = h,
            interrupts = ownerStats.interrupts or 0,
            dispels = ownerStats.dispels or 0,
            deaths = ownerStats.deaths or 0,
            avoidableDamageTaken = GetAvoidableDamageValue(ownerStats),
            damagePerSecond = GetDamagePerSecond(ownerStats, runDuration),
            healingPerSecond = GetHealingPerSecond(ownerStats, runDuration),
        }
    end

    local function IsPlayerMVP(run)
        -- Use stored MVP name from when the run was saved (matches scoreboard)
        local mvpName = run.mvpName
        if not mvpName or mvpName == "" then
            -- Fallback: same scoring as scoreboard for runs saved before mvpName was stored
            mvpName = (MPT.Scoreboard and MPT.Scoreboard.ComputeMVPName) and MPT.Scoreboard:ComputeMVPName(run) or nil
        end
        if mvpName and mvpName ~= "" then
            local owner = (run.character and run.realm) and (run.character .. "-" .. run.realm) or run.character
            if not owner then return false end
            local mvpShort = mvpName:match("^([^%-]+)") or mvpName
            local ownerShort = owner:match("^([^%-]+)") or owner
            return mvpName == owner or mvpName == ownerShort or mvpShort == ownerShort
        end
        return false
    end

    -- Personal-best stats per dungeon for the run owner (for orange highlight in Recent Runs).
    local pbDamageByDungeon, pbHealingByDungeon, pbInterruptsByDungeon, pbDispelsByDungeon, pbDPSByDungeon, pbHPSByDungeon = {}, {}, {}, {}, {}, {}
    for _, run in ipairs(runs) do
        -- Abandoned keys are saved but never count toward personal bests
        if run.abandonReason ~= "abandon" then
            local dungeonKey = run.dungeonName or tostring(run.dungeonId or run.dungeonID or run.dungeon or "--")
            local myStats = GetMyPlayerStatsInRun(run)
            if myStats then
                pbDamageByDungeon[dungeonKey] = math.max(pbDamageByDungeon[dungeonKey] or 0, myStats.damage or 0)
                pbHealingByDungeon[dungeonKey] = math.max(pbHealingByDungeon[dungeonKey] or 0, myStats.healing or 0)
                pbInterruptsByDungeon[dungeonKey] = math.max(pbInterruptsByDungeon[dungeonKey] or 0, myStats.interrupts or 0)
                pbDispelsByDungeon[dungeonKey] = math.max(pbDispelsByDungeon[dungeonKey] or 0, myStats.dispels or 0)
                pbDPSByDungeon[dungeonKey] = math.max(pbDPSByDungeon[dungeonKey] or 0, myStats.damagePerSecond or 0)
                pbHPSByDungeon[dungeonKey] = math.max(pbHPSByDungeon[dungeonKey] or 0, myStats.healingPerSecond or 0)
            end
        end
    end

    local runY = 0
    for idx, run in ipairs(runs) do
        local runRow = CreateFrame("Frame", nil, self.frame.RunContent)
        runRow:SetSize(840, 22)
        runRow:SetPoint("TOPLEFT", self.frame.RunContent, "TOPLEFT", 0, -runY)
        runRow:EnableMouse(true)
        runRow:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                OpenRunScoreboardFromHistory(self, run)
            end
        end)

        local bg = runRow:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(runRow)

        local hover = runRow:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(runRow)
        hover:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        hover:SetAlpha(0.16)

        local level = run.keystoneLevel or run.dungeonLevel or 0
        local myStats = GetMyPlayerStatsInRun(run)
        local dispDamage = myStats and (myStats.damage or 0) or 0
        local dispHealing = myStats and (myStats.healing or 0) or 0
        local dispInterrupts = myStats and (myStats.interrupts or 0) or 0
        local dispDispels = myStats and (myStats.dispels or 0) or 0
        local dispDPS = myStats and (myStats.damagePerSecond or 0) or 0
        local dispHPS = myStats and (myStats.healingPerSecond or 0) or 0
        local dispAvoidableDamage = myStats and (myStats.avoidableDamageTaken or 0) or 0
        local dispDeaths = myStats and (myStats.deaths or 0) or 0

        if idx % 2 == 0 then
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.18)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end

        local x = 5

        local dungeonText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dungeonText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dungeonText:SetWidth(155)
        dungeonText:SetJustifyH("LEFT")
        dungeonText:SetText(run.dungeonName or "--")
        x = x + 155

        local levelText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        levelText:SetWidth(35)
        levelText:SetJustifyH("CENTER")
        levelText:SetText("+" .. tostring(level))
        x = x + 35

        local durationText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durationText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        durationText:SetWidth(55)
        durationText:SetJustifyH("CENTER")
        local durationDisplay
        if run.abandonReason == "abandon" then
            durationDisplay = "Abandon"
        else
            durationDisplay = MPT.Utils:FormatDuration(run.duration or 0)
        end
        durationText:SetText(durationDisplay)
        local overTime = run.abandonReason == "abandon" or RunIsFailed(run)
        if overTime then
            durationText:SetTextColor(1, 0.27, 0.27, 1)
        else
            durationText:SetTextColor(1, 0.84, 0, 1)
        end
        x = x + 55

        local specText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        specText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        specText:SetWidth(50)
        specText:SetJustifyH("CENTER")
        do
            local label = ""
            if run.specIcon then
                label = "|T" .. tostring(run.specIcon) .. ":14:14:0:0|t"
            end
            specText:SetText(label)
        end
        x = x + 50

        local heroText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heroText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        heroText:SetWidth(75)
        heroText:SetJustifyH("CENTER")
        heroText:SetTextColor(0.8, 0.8, 1, 1)  -- Light blue tint
        if run.heroName and run.heroName ~= "" then
            heroText:SetText(run.heroName)
        else
            heroText:SetText("")
        end
        x = x + 90

        local dateText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dateText:SetWidth(50)
        dateText:SetJustifyH("CENTER")
        dateText:SetText(date("%m/%d/%y", run.timestamp or time()))
        x = x + 50

        local dungeonKey = run.dungeonName or tostring(run.dungeonId or run.dungeonID or run.dungeon or "--")
        local isAbandonedRun = run.abandonReason == "abandon"
        local dmgText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dmgText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dmgText:SetWidth(70)
        dmgText:SetJustifyH("RIGHT")
        local dmgValueText = MPT.Utils:FormatNumber(dispDamage)
        if not isAbandonedRun and dispDamage > 0 and dispDamage >= (pbDamageByDungeon[dungeonKey] or 0) then
            dmgValueText = "|cffff8000" .. dmgValueText .. "|r"
        end
        dmgText:SetText(dmgValueText)
        x = x + 70

        local dpsText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dpsText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dpsText:SetWidth(50)
        dpsText:SetJustifyH("RIGHT")
        local dpsValueText = MPT.Utils:FormatNumber(dispDPS)
        if not isAbandonedRun and dispDPS > 0 and dispDPS >= (pbDPSByDungeon[dungeonKey] or 0) then
            dpsValueText = "|cffff8000" .. dpsValueText .. "|r"
        end
        dpsText:SetText(dpsValueText)
        x = x + 50

        local healText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        healText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        healText:SetWidth(70)
        healText:SetJustifyH("RIGHT")
        local healValueText = MPT.Utils:FormatNumber(dispHealing)
        if not isAbandonedRun and dispHealing > 0 and dispHealing >= (pbHealingByDungeon[dungeonKey] or 0) then
            healValueText = "|cffff8000" .. healValueText .. "|r"
        end
        healText:SetText(healValueText)
        x = x + 70

        local hpsText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hpsText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        hpsText:SetWidth(50)
        hpsText:SetJustifyH("RIGHT")
        local hpsValueText = MPT.Utils:FormatNumber(dispHPS)
        if not isAbandonedRun and dispHPS > 0 and dispHPS >= (pbHPSByDungeon[dungeonKey] or 0) then
            hpsValueText = "|cffff8000" .. hpsValueText .. "|r"
        end
        hpsText:SetText(hpsValueText)
        x = x + 50

        local intText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        intText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        intText:SetWidth(50)
        intText:SetJustifyH("CENTER")
        local intValueText = tostring(dispInterrupts)
        if not isAbandonedRun and dispInterrupts > 0 and dispInterrupts >= (pbInterruptsByDungeon[dungeonKey] or 0) then
            intValueText = "|cffff8000" .. intValueText .. "|r"
        end
        intText:SetText(intValueText)
        x = x + 50

        local dispText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dispText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dispText:SetWidth(40)
        dispText:SetJustifyH("CENTER")
        local dispValueText = tostring(dispDispels)
        if not isAbandonedRun and dispDispels > 0 and dispDispels >= (pbDispelsByDungeon[dungeonKey] or 0) then
            dispValueText = "|cffff8000" .. dispValueText .. "|r"
        end
        dispText:SetText(dispValueText)
        x = x + 40

        local avoidText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        avoidText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        avoidText:SetWidth(65)
        avoidText:SetJustifyH("CENTER")
        local avoidValueText = MPT.Utils:FormatNumber(dispAvoidableDamage)
        avoidText:SetText(avoidValueText)
        x = x + 65

        local deathsText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        deathsText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        deathsText:SetWidth(50)
        deathsText:SetJustifyH("CENTER")
        local deathsValueText = tostring(dispDeaths)
        -- Color deaths red if > 0
        if dispDeaths > 0 then
            deathsValueText = "|cffff2727" .. deathsValueText .. "|r"
        end
        deathsText:SetText(deathsValueText)
        x = x + 50

        -- MVP indicator
        local mvpText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mvpText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        mvpText:SetWidth(40)
        mvpText:SetJustifyH("CENTER")
        if IsPlayerMVP(run) then
            mvpText:SetText("|TInterface\\Icons\\Achievement_Dungeon_HEROIC_GloryoftheRaider:16:16:0:0|t")
        else
            mvpText:SetText("")
        end
        x = x + 40

        -- Delete button
        local deleteBtn = CreateFrame("Button", nil, runRow)
        deleteBtn:SetSize(18, 18)
        deleteBtn:SetPoint("LEFT", runRow, "LEFT", x, 0)
        deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        deleteBtn:SetScript("OnClick", function()
            StaticPopupDialogs["STORMSDUNGEONDATA_DELETE_RUN"] = {
                text = "Delete this run?\n\n" .. (run.dungeonName or "Unknown") .. " +" .. (run.keystoneLevel or run.dungeonLevel or 0),
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    if MPT.Database:DeleteRun(run.id) then
                        print("|cff00ffaa[StormsDungeonData]|r Run deleted")
                        self:UpdateDisplay()
                    else
                        print("|cff00ffaa[StormsDungeonData]|r Error: Could not delete run")
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("STORMSDUNGEONDATA_DELETE_RUN")
        end)
        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Delete Run", 1, 1, 1)
            GameTooltip:AddLine("Click to permanently delete this run", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        table.insert(self.frame.RunRows, runRow)
        runY = runY + 24
    end
    
    self.frame.RunContent:SetHeight(math.max(runY, 1))
    if self.activePage == "insights" then
        self:UpdateInsightsDisplay()
    elseif self.activePage == "tierlist" then
        self:UpdateTierListDisplay()
    end
end

