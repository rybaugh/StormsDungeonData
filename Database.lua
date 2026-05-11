-- Mythic Plus Tracker - Database Module
-- Handles all data storage and retrieval

local MPT = StormsDungeonData
MPT.Database = MPT.Database or {}

local LEGACY_SEASON_MIGRATION_FLAG = "legacySeasonAssignedOnce"
local LEGACY_TIMED_RESULT_MIGRATION_FLAG = "legacyTimedResultBackfilledOnce"
local LEGACY_TIMED_RESULT_MIGRATION_V2_FLAG = "legacyTimedResultBackfilledV2"
local LEGACY_TWW_SEASON_REMIGRATION_FLAG = "twwSeasonAbsoluteIDMigrationV1"

local function GetCurrentSeasonMigrationData()
    local seasonID = nil
    if C_MythicPlus and type(C_MythicPlus.GetCurrentSeason) == "function" then
        seasonID = C_MythicPlus.GetCurrentSeason()
    end

    local expansionLevel = nil
    if type(GetExpansionLevel) == "function" then
        expansionLevel = GetExpansionLevel()
    end

    local expansionAbbrevByLevel = {
        [7] = "BFA",
        [8] = "SL",
        [9] = "DF",
        [10] = "TWW",
        [11] = "Midnight",
    }
    local expansionAbbrev = expansionAbbrevByLevel[expansionLevel]

    -- Safety fallback: if the API is unavailable, assume Midnight Season 1.
    if not seasonID then seasonID = 17 end
    if not expansionLevel then expansionLevel = 11 end
    if not expansionAbbrev then expansionAbbrev = "Midnight" end

    return seasonID, expansionLevel, expansionAbbrev
end

local function RunHasSeasonMetadata(run)
    if not run then return false end
    return (type(run.seasonID) == "number")
        or (type(run.seasonId) == "number")
        or (type(run.mythicPlusSeason) == "number")
        or (type(run.season) == "number")
end

local function GetDisplaySeasonNumberFromID(seasonID, expansionAbbrev)
    if type(seasonID) ~= "number" then
        return seasonID or "?"
    end
    if expansionAbbrev == "Midnight" and seasonID >= 17 then
        return seasonID - 16
    elseif expansionAbbrev == "TWW" and seasonID >= 13 and seasonID <= 16 then
        return seasonID - 12
    elseif expansionAbbrev == "DF" and seasonID >= 9 and seasonID <= 12 then
        return seasonID - 8
    elseif expansionAbbrev == "SL" and seasonID >= 5 and seasonID <= 8 then
        return seasonID - 4
    elseif expansionAbbrev == "BFA" and seasonID >= 1 and seasonID <= 4 then
        return seasonID
    end
    return seasonID
end

local function GetDungeonTimeLimitSecondsFromMap(mapID)
    if not mapID or not C_ChallengeMode or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        return nil
    end
    -- Returns (name, id, timeLimit, texture, bgTexture, mapID); timeLimit is in seconds.
    -- https://warcraft.wiki.gg/wiki/API_C_ChallengeMode.GetMapUIInfo
    local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    timeLimit = tonumber(timeLimit)
    if not timeLimit or timeLimit <= 0 then
        return nil
    end
    return math.floor(timeLimit)
end

local function NormalizeDurationSecondsForMigration(duration)
    duration = tonumber(duration)
    if not duration or duration <= 0 then
        return nil
    end
    if duration > 100000 then
        return math.floor(duration / 1000)
    end
    return math.floor(duration)
end

local function InferRunOnTime(run)
    if not run then
        return nil
    end
    if run.completed == false then
        return false
    end

    -- Use the API time limit as the sole source of truth.
    -- Do NOT use keystoneUpgrades: in Midnight (WoW 12.0+) it is always 0 for every run,
    -- timed or not, because key upgrades/depletions were removed from the game.
    local mapID = tonumber(run.dungeonID or run.dungeonId)
    local duration = NormalizeDurationSecondsForMigration(run.duration)
    if not mapID or not duration then
        return nil
    end

    local timeLimit = GetDungeonTimeLimitSecondsFromMap(mapID)
    if not timeLimit then
        return nil
    end

    return duration <= timeLimit
end

function MPT.Database:ApplyOneTimeLegacySeasonAssignment()
    if not StormsDungeonDataDB then
        return
    end
    StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
    if StormsDungeonDataDB.settings[LEGACY_SEASON_MIGRATION_FLAG] then
        return
    end

    local runs = StormsDungeonDataDB.runs or {}
    local seasonID, expansionLevel, expansionAbbrev = GetCurrentSeasonMigrationData()
    local updatedCount = 0

    for _, run in ipairs(runs) do
        if not run.deleted and not RunHasSeasonMetadata(run) then
            run.seasonID = seasonID
            run.expansionLevel = run.expansionLevel or expansionLevel
            run.expansionAbbrev = run.expansionAbbrev or expansionAbbrev
            updatedCount = updatedCount + 1
        end
    end

    StormsDungeonDataDB.settings[LEGACY_SEASON_MIGRATION_FLAG] = true
    if updatedCount > 0 then
        local displaySeason = GetDisplaySeasonNumberFromID(seasonID, expansionAbbrev)
        print("|cff00ffaa[StormsDungeonData]|r Assigned " .. tostring(updatedCount) .. " legacy runs to " .. tostring(expansionAbbrev) .. ": Season " .. tostring(displaySeason))
    end
end

-- Fixes runs whose seasonID ended up as a small relative number (1-4) instead of the
-- absolute global season ID, specifically for TWW runs.  This can happen when:
--   (a) The first-run migration ran with the old fallback (seasonID=3 instead of 15), or
--   (b) Runs were recorded/imported with run.season=N (relative) and run.seasonID=nil,
--       causing GetRunSeasonID to return the relative value and key them to the wrong bucket.
-- Both are identified by expansionAbbrev=="TWW" AND an effective seasonID in the range 1-12
-- (which is outside the valid TWW range of 13-16).
function MPT.Database:ApplyOneTimeTWWSeasonIDRemigration()
    if not StormsDungeonDataDB then
        return
    end
    StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
    if StormsDungeonDataDB.settings[LEGACY_TWW_SEASON_REMIGRATION_FLAG] then
        return
    end

    local runs = StormsDungeonDataDB.runs or {}
    local updatedCount = 0

    for _, run in ipairs(runs) do
        if not run.deleted and run.expansionAbbrev == "TWW" then
            local effectiveSeasonID = tonumber(run.seasonID)

            -- Case A: seasonID stored but is clearly a relative TWW season number (1-4),
            -- not a valid absolute ID (TWW absolute range: 13-16).
            if effectiveSeasonID and effectiveSeasonID >= 1 and effectiveSeasonID <= 12 then
                -- Treat the stored value as the relative season-within-expansion and convert.
                run.seasonID = effectiveSeasonID + 12
                updatedCount = updatedCount + 1

            -- Case B: seasonID absent but run.season exists as a relative number.
            elseif not effectiveSeasonID then
                local relativeSeason = tonumber(run.season)
                if relativeSeason and relativeSeason >= 1 and relativeSeason <= 4 then
                    run.seasonID = relativeSeason + 12
                    updatedCount = updatedCount + 1
                end
            end
        end
    end

    StormsDungeonDataDB.settings[LEGACY_TWW_SEASON_REMIGRATION_FLAG] = true
    if updatedCount > 0 then
        print("|cff00ffaa[StormsDungeonData]|r Re-migrated " .. tostring(updatedCount) .. " TWW run(s) to correct absolute season IDs.")
    end
end

function MPT.Database:ApplyOneTimeLegacyTimedResultBackfill()
    -- V1 migration (keystoneUpgrades-based) is superseded by V2 below; this is kept as a
    -- no-op stub so old saved-variable flags don't cause errors.
end

function MPT.Database:ApplyOneTimeLegacyTimedResultBackfillV2()
    if not StormsDungeonDataDB then
        return
    end

    StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
    if StormsDungeonDataDB.settings[LEGACY_TIMED_RESULT_MIGRATION_V2_FLAG] then
        return
    end

    -- V2: re-evaluate ALL completed runs unconditionally using duration vs the API time limit.
    -- This corrects runs that were mis-tagged by V1 (which used keystoneUpgrades=0 as a
    -- "failed" signal, but in Midnight that value is 0 for every run including timed ones).
    local runs = StormsDungeonDataDB.runs or {}
    local updatedCount = 0
    local timedCount = 0
    local overtimeCount = 0

    for _, run in ipairs(runs) do
        if not run.deleted then
            local inferredOnTime = InferRunOnTime(run)
            if inferredOnTime ~= nil then
                run.onTime = inferredOnTime
                updatedCount = updatedCount + 1
                if inferredOnTime then
                    timedCount = timedCount + 1
                else
                    overtimeCount = overtimeCount + 1
                end
            end
        end
    end

    StormsDungeonDataDB.settings[LEGACY_TIMED_RESULT_MIGRATION_V2_FLAG] = true

    if updatedCount > 0 then
        print("|cff00ffaa[StormsDungeonData]|r Corrected timed results for " .. tostring(updatedCount) .. " runs (timed=" .. tostring(timedCount) .. ", overtime=" .. tostring(overtimeCount) .. ")")
    end
end

-- ---------------------------------------------------------------------------
-- Live timed-status refresh (runs every login via PLAYER_ENTERING_WORLD)
-- ---------------------------------------------------------------------------

-- Builds a mapID -> timeLimitSeconds lookup for all dungeons the API knows about.
-- First seeds from the current season's active map IDs, then covers any additional
-- mapIDs present in stored runs (handles past-season dungeons).
-- Returns nil when C_ChallengeMode is not yet initialised.
local function BuildTimeLimitCacheForAllRuns()
    if not C_ChallengeMode or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        return nil
    end

    local cache = {}
    local gotAtLeastOne = false

    -- Seed with every dungeon in the current season.
    if type(C_ChallengeMode.GetActiveChallengeMapIDs) == "function" then
        local mapIDs = C_ChallengeMode.GetActiveChallengeMapIDs()
        if mapIDs then
            for _, mapID in ipairs(mapIDs) do
                if mapID and not cache[mapID] then
                    local limit = GetDungeonTimeLimitSecondsFromMap(mapID)
                    if limit then
                        cache[mapID] = limit
                        gotAtLeastOne = true
                    end
                end
            end
        end
    end

    -- Also cover any mapIDs from stored runs that may belong to past seasons.
    if StormsDungeonDataDB then
        for _, run in ipairs(StormsDungeonDataDB.runs or {}) do
            if not run.deleted then
                local mapID = tonumber(run.dungeonID or run.dungeonId)
                if mapID and not cache[mapID] then
                    local limit = GetDungeonTimeLimitSecondsFromMap(mapID)
                    if limit then
                        cache[mapID] = limit
                        gotAtLeastOne = true
                    end
                end
            end
        end
    end

    return gotAtLeastOne and cache or nil
end

-- RefreshAllRunTimedStatus: called on every PLAYER_ENTERING_WORLD so that the
-- onTime field for every stored run always reflects the time limit currently
-- returned by the API.  This self-corrects if Blizzard adjusts dungeon timers
-- mid-season, and also fixes any mis-tags from the one-time legacy migrations
-- that ran before the API was fully initialised.
function MPT.Database:RefreshAllRunTimedStatus()
    if not StormsDungeonDataDB then return end

    local timeLimitCache = BuildTimeLimitCacheForAllRuns()
    if not timeLimitCache then
        if MPT.Log then
            MPT.Log:Warn("RefreshAllRunTimedStatus: C_ChallengeMode not ready or returned no dungeons; skipping")
        end
        return
    end

    local runs = StormsDungeonDataDB.runs or {}
    local evaluated = 0
    local updated   = 0

    for _, run in ipairs(runs) do
        -- Skip deleted runs and runs that were explicitly not completed (abandoned/failed).
        if not run.deleted and run.completed ~= false then
            local mapID   = tonumber(run.dungeonID or run.dungeonId)
            local duration = NormalizeDurationSecondsForMigration(run.duration)
            if mapID and duration then
                local timeLimit = timeLimitCache[mapID]
                if timeLimit then
                    evaluated = evaluated + 1
                    local onTime = (duration <= timeLimit)
                    if run.onTime ~= onTime then
                        run.onTime = onTime
                        updated    = updated + 1
                    end
                end
            end
        end
    end

    if updated > 0 then
        print("|cff00ffaa[StormsDungeonData]|r Refreshed timed status: " .. tostring(updated) .. " run(s) corrected from current dungeon time limits.")
    end
    if MPT.Log then
        local cacheSize = 0
        for _ in pairs(timeLimitCache) do cacheSize = cacheSize + 1 end
        MPT.Log:Info("RefreshAllRunTimedStatus: evaluated=" .. tostring(evaluated) .. " updated=" .. tostring(updated) .. " cached_dungeons=" .. tostring(cacheSize))
    end
end

function MPT.Database:CreateDefaultDB()
    return {
        version = 1,
        runs = {},  -- List of all runs across all characters
        characters = {},  -- Character metadata
        playerRatings = {},  -- [playerNameKey] = "good" | "bad" (for non-user players in runs)
        playerRatingGoodCount = {},  -- [playerNameKey] = number of times rated good
        playerRatingBadCount = {},   -- [playerNameKey] = number of times rated bad
        settings = {
            autoShowScoreboard = true,
            playerTooltipEnabled = false,
        },
    }
end

function MPT.Database:Initialize()
    -- Verify DB structure
    if not StormsDungeonDataDB then
        StormsDungeonDataDB = self:CreateDefaultDB()
    end
    
    -- Ensure all tables exist
    if not StormsDungeonDataDB.runs then
        StormsDungeonDataDB.runs = {}
    end
    if not StormsDungeonDataDB.characters then
        StormsDungeonDataDB.characters = {}
    end
    if not StormsDungeonDataDB.settings then
        StormsDungeonDataDB.settings = {}
    end
    if StormsDungeonDataDB.settings.playerTooltipEnabled == nil then
        StormsDungeonDataDB.settings.playerTooltipEnabled = false
    end
    if not StormsDungeonDataDB.playerRatings then
        StormsDungeonDataDB.playerRatings = {}
    end
    if not StormsDungeonDataDB.playerRatingGoodCount then
        StormsDungeonDataDB.playerRatingGoodCount = {}
    end
    if not StormsDungeonDataDB.playerRatingBadCount then
        StormsDungeonDataDB.playerRatingBadCount = {}
    end

    self:ApplyOneTimeLegacySeasonAssignment()
    self:ApplyOneTimeTWWSeasonIDRemigration()        -- fix relative→absolute TWW season IDs
    self:ApplyOneTimeLegacyTimedResultBackfill()    -- stub; kept for saved-var compat
    self:ApplyOneTimeLegacyTimedResultBackfillV2()  -- correct Midnight-era mis-tags
end

-- Aggregate good rating count from all run records (one vote per run per player)
function MPT.Database:GetPlayerGoodCount(playerName)
    if not StormsDungeonDataDB then return 0 end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return 0 end
    local count = 0
    for _, run in ipairs(StormsDungeonDataDB.runs or {}) do
        if run.playerRatings and run.playerRatings[key] == "good" then
            count = count + 1
        end
    end
    return count
end

-- Aggregate bad rating count from all run records (one vote per run per player)
function MPT.Database:GetPlayerBadCount(playerName)
    if not StormsDungeonDataDB then return 0 end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return 0 end
    local count = 0
    for _, run in ipairs(StormsDungeonDataDB.runs or {}) do
        if run.playerRatings and run.playerRatings[key] == "bad" then
            count = count + 1
        end
    end
    return count
end

-- Kept for backward compatibility (no longer used for counting)
function MPT.Database:IncrementPlayerGoodCount(playerName) return true end
function MPT.Database:IncrementPlayerBadCount(playerName) return true end

-- Normalize player name for rating key (case-insensitive, full name-realm)
function MPT.Database:GetPlayerRatingKey(playerName)
    if not playerName or type(playerName) ~= "string" then return nil end
    local name = playerName:gsub("%s+", ""):lower()
    if name == "" then return nil end
    -- If no realm suffix, append current realm so same-name on different realms don't collide
    if not name:match("%-") and GetRealmName then
        name = name .. "-" .. (GetRealmName() or ""):gsub("%s+", ""):lower()
    end
    return name
end

function MPT.Database:GetPlayerRating(playerName)
    if not StormsDungeonDataDB or not StormsDungeonDataDB.playerRatings then return nil end
    local key = self:GetPlayerRatingKey(playerName)
    return key and StormsDungeonDataDB.playerRatings[key] or nil
end

function MPT.Database:SetPlayerRating(playerName, rating)
    if not StormsDungeonDataDB then return false end
    if not StormsDungeonDataDB.playerRatings then
        StormsDungeonDataDB.playerRatings = {}
    end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return false end
    if rating == "good" or rating == "bad" then
        StormsDungeonDataDB.playerRatings[key] = rating
        return true
    end
    StormsDungeonDataDB.playerRatings[key] = nil
    return true
end

-- Get the rating for a specific player within a specific run (per-run, not global)
function MPT.Database:GetRunPlayerRating(runID, playerName)
    if not StormsDungeonDataDB or not runID or not playerName then return nil end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return nil end
    for _, run in ipairs(StormsDungeonDataDB.runs or {}) do
        if run.id == runID then
            return run.playerRatings and run.playerRatings[key] or nil
        end
    end
    return nil
end

-- Set (or clear) the rating for a specific player within a specific run.
-- rating = "good"|"bad"|nil  (nil clears the rating)
function MPT.Database:SetRunPlayerRating(runID, playerName, rating)
    if not StormsDungeonDataDB or not runID or not playerName then return false end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return false end
    for _, run in ipairs(StormsDungeonDataDB.runs or {}) do
        if run.id == runID then
            if not run.playerRatings then run.playerRatings = {} end
            if rating == "good" or rating == "bad" then
                run.playerRatings[key] = rating
            else
                run.playerRatings[key] = nil
            end
            return true
        end
    end
    return false
end

-- Create a new run record
function MPT.Database:CreateRunRecord(dungeonID, dungeonName, keystoneLevel, completed, duration, players)
    return {
        id = self:GenerateRunID(),
        timestamp = time(),
        character = MPT:GetPlayerInfo().name,
        realm = GetRealmName(),
        characterClass = MPT:GetPlayerInfo().class,
        dungeonID = dungeonID,
        dungeonName = dungeonName,
        keystoneLevel = keystoneLevel,
        completed = completed,
        duration = duration,
        startTime = duration and (GetServerTime() - duration) or GetServerTime(),  -- Approximate; nil for abandoned runs
        endTime = GetServerTime(),
        players = players,  -- Array of player stats
        mobsKilled = 0,
        mobsTotal = 0,
        overallMobPercentage = 0,
    }
end

-- Create player stat record
function MPT.Database:CreatePlayerStats(unitID, name, class, role)
    -- Try to get spec ID for the unit
    local specID = nil
    local guid = nil
    if unitID and UnitExists(unitID) then
        guid = UnitGUID(unitID)
        if unitID == "player" then
            -- For player, use GetSpecialization
            local specIndex = GetSpecialization and GetSpecialization() or nil
            if specIndex and GetSpecializationInfo then
                specID = select(1, GetSpecializationInfo(specIndex))
            end
        else
            -- For party members, check the session spec cache first (populated by INSPECT_READY),
            -- then fall back to the live inspect API.
            local guid = UnitGUID(unitID)
            if guid and MPT.SpecCache and MPT.SpecCache[guid] then
                specID = MPT.SpecCache[guid]
            elseif GetInspectSpecialization then
                local sid = GetInspectSpecialization(unitID)
                if sid and sid > 0 then
                    specID = sid
                    -- Back-fill the cache for later use
                    if guid and MPT.SpecCache then
                        MPT.SpecCache[guid] = sid
                    end
                end
            end
        end
    end
    
    return {
        unitID = unitID,
        name = name,
        class = class,
        role = role,
        guid = guid,
        specID = specID,  -- Add spec ID for precise interrupt weight calculation
        damage = 0,
        healing = 0,
        interrupts = 0,
        dispels = 0,
        deaths = 0,
        pointsGained = 0,
        damagePerSecond = 0,
        healingPerSecond = 0,
        interruptsPerMinute = 0,
    }
end

local function NumberOrNil(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return tonumber(value)
    end
    return nil
end

local function AbsDiffWithin(a, b, tolerance)
    local na = NumberOrNil(a)
    local nb = NumberOrNil(b)
    if not na or not nb then
        return false
    end
    return math.abs(na - nb) <= tolerance
end

function MPT.Database:IsDuplicateRun(runRecord)
    if not runRecord or not runRecord.dungeonID then
        return false, nil
    end
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    local dungeonID = NumberOrNil(runRecord.dungeonID)
    local keystoneLevel = NumberOrNil(runRecord.keystoneLevel)
    local character = runRecord.character
    local realm = runRecord.realm
    local duration = NumberOrNil(runRecord.duration)
    local startTime = NumberOrNil(runRecord.startTime)
    local endTime = NumberOrNil(runRecord.endTime)
    local timestamp = NumberOrNil(runRecord.timestamp)
    local completionTime = NumberOrNil(runRecord.completionTime)
    local candidateEnd = endTime or completionTime or timestamp

    for _, existing in ipairs(runs) do
        if not existing.deleted then
            local sameDungeon = NumberOrNil(existing.dungeonID) == dungeonID
            local sameLevel = NumberOrNil(existing.keystoneLevel) == keystoneLevel
            local sameCharacter = (existing.character == character) and (existing.realm == realm)
            if sameDungeon and sameLevel and sameCharacter then
                local existingDuration = NumberOrNil(existing.duration)
                local existingStart = NumberOrNil(existing.startTime)
                local existingEnd = NumberOrNil(existing.endTime) or NumberOrNil(existing.completionTime) or NumberOrNil(existing.timestamp)

                -- Treat as duplicate when run timing and duration align closely.
                local sameEnd = candidateEnd and existingEnd and AbsDiffWithin(candidateEnd, existingEnd, 8)
                local sameStart = startTime and existingStart and AbsDiffWithin(startTime, existingStart, 8)
                local sameDuration = duration and existingDuration and AbsDiffWithin(duration, existingDuration, 8)
                if (sameEnd and sameDuration) or (sameStart and sameDuration) then
                    return true, existing
                end
            end
        end
    end
    return false, nil
end

-- Save a completed run
function MPT.Database:SaveRun(runRecord)
    if not runRecord or not runRecord.dungeonID then
        print("|cff00ffaa[StormsDungeonData]|r Error: Invalid run record")
        return false
    end
    if not StormsDungeonDataDB then
        StormsDungeonDataDB = self:CreateDefaultDB()
    end
    if not StormsDungeonDataDB.runs then
        StormsDungeonDataDB.runs = {}
    end
    local isDuplicate = self:IsDuplicateRun(runRecord)
    if isDuplicate then
        print("|cff00ffaa[StormsDungeonData]|r Duplicate run detected - skipping save")
        return false, "duplicate"
    end
    table.insert(StormsDungeonDataDB.runs, runRecord)
    return true
end

-- Delete a run by ID (soft delete: mark as deleted so it is excluded from stats and lists)
function MPT.Database:DeleteRun(runID)
    if not runID or not StormsDungeonDataDB or not StormsDungeonDataDB.runs then
        return false
    end
    for _, run in ipairs(StormsDungeonDataDB.runs) do
        if run.id == runID then
            run.deleted = true
            return true
        end
    end
    return false
end

-- Get all runs for a specific character (excludes soft-deleted runs)
function MPT.Database:GetRunsByCharacter(characterName, realm)
    local result = {}
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    for _, run in ipairs(runs) do
        if not run.deleted and run.character == characterName and run.realm == realm then
            table.insert(result, run)
        end
    end
    return result
end

-- Get runs for a specific dungeon (excludes soft-deleted runs)
function MPT.Database:GetRunsByDungeon(dungeonID, characterName, realm, dungeonName)
    local result = {}
    local runs = characterName and self:GetRunsByCharacter(characterName, realm) or (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    local hasDungeonID = (dungeonID and dungeonID ~= 0)
    for _, run in ipairs(runs) do
        if not run.deleted and ((hasDungeonID and run.dungeonID == dungeonID) or (not hasDungeonID and dungeonName and run.dungeonName == dungeonName)) then
            table.insert(result, run)
        end
    end
    
    -- Sort by timestamp descending (newest first)
    table.sort(result, function(a, b) return a.timestamp > b.timestamp end)
    return result
end

-- Get all unique characters in database (from non-deleted runs only)
function MPT.Database:GetAllCharacters()
    local characters = {}
    local seen = {}
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    for _, run in ipairs(runs) do
        if not run.deleted then
            -- Handle both real data (with character/realm) and test data (without)
            local character = run.character or UnitName("player") or "Unknown"
            local realm = run.realm or GetRealmName() or "Unknown"
            local key = character .. "-" .. realm
            if not seen[key] then
                seen[key] = true
                local classToken = run.characterClass
                if not classToken and run.players then
                    for _, p in ipairs(run.players) do
                        if p and p.name == character and p.class then
                            classToken = p.class
                            break
                        end
                    end
                end
                table.insert(characters, {
                    name = character,
                    realm = realm,
                    class = classToken or "UNKNOWN",
                })
            end
        end
    end
    
    table.sort(characters, function(a, b)
        if a.realm ~= b.realm then
            return a.realm < b.realm
        end
        return a.name < b.name
    end)
    
    return characters
end

-- Get all unique dungeons (from non-deleted runs only)
function MPT.Database:GetAllDungeons()
    local dungeons = {}
    local seen = {}
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    for _, run in ipairs(runs) do
        if not run.deleted then
            -- Use dungeonName as key since dungeonID may not exist in test data
            local key = run.dungeonName or "Unknown"
            if not seen[key] then
                seen[key] = true
                table.insert(dungeons, {
                    id = run.dungeonID or 0,
                    name = key,
                    count = 0,
                })
            end
        end
    end
    -- Count runs per dungeon (non-deleted only)
    for _, run in ipairs(runs) do
        if not run.deleted then
            for _, dungeon in ipairs(dungeons) do
                if (dungeon.id == run.dungeonID and dungeon.id ~= 0) or (dungeon.name == run.dungeonName) then
                    dungeon.count = dungeon.count + 1
                end
            end
        end
    end
    
    table.sort(dungeons, function(a, b) return a.name < b.name end)
    return dungeons
end

-- Generate unique run ID
function MPT.Database:GenerateRunID()
    return MPT:GetPlayerInfo().name .. "-" .. GetRealmName() .. "-" .. time() .. "-" .. math.random(1000, 9999)
end

-- Get run statistics for a dungeon
function MPT.Database:GetDungeonStatistics(dungeonID, characterName, realm, dungeonName, keystoneLevelFilter, resultFilter)
    local runs = self:GetRunsByDungeon(dungeonID, characterName, realm, dungeonName)
    
    if #runs == 0 then
        return nil
    end
    
    local stats = {
        totalRuns = 0,
        completedRuns = 0,
        failedRuns = 0,
        avgDuration = 0,
        avgKeystoneLevel = 0,
        avgDamage = 0,
        avgHealing = 0,
        avgInterrupts = 0,
        avgMobPercentage = 0,
        bestKeystoneLevel = 0,
        bestDuration = 0,
        bestTime = nil,
    }
    
    local totalDuration = 0
    local totalLevel = 0
    local totalDamage = 0
    local totalHealing = 0
    local totalInterrupts = 0
    local totalMobPercentage = 0
    local playerRunCount = 0
    local bestDamage = 0
    local bestHealing = 0
    local bestInterrupts = 0
    
    for _, run in ipairs(runs) do
        local runLevel = (run.keystoneLevel or run.dungeonLevel)
        if (not keystoneLevelFilter) or (runLevel == keystoneLevelFilter) then
            -- Apply result filter (completed/failed)
            local allowRun = true
            if resultFilter ~= nil then
                if resultFilter == true and not run.completed then
                    allowRun = false
                end
                if resultFilter == false and run.completed then
                    allowRun = false
                end
            end

            if allowRun then
                stats.totalRuns = stats.totalRuns + 1

                if run.completed then
                    stats.completedRuns = stats.completedRuns + 1
                else
                    stats.failedRuns = stats.failedRuns + 1
                end
            
            totalDuration = totalDuration + (run.duration or 0)
            totalLevel = totalLevel + (runLevel or 0)
            totalMobPercentage = totalMobPercentage + (run.overallMobPercentage or 0)
            
            -- Get best stats from completed runs only
            if run.completed and run.playerStats then
                for name, pstats in pairs(run.playerStats) do
                    bestDamage = math.max(bestDamage, pstats.damage or 0)
                    bestHealing = math.max(bestHealing, pstats.healing or 0)
                    bestInterrupts = math.max(bestInterrupts, pstats.interrupts or 0)
                end
            end
            
            -- Find player stats for current character
            if run.players then
                for _, player in ipairs(run.players) do
                    if player.name == characterName or not characterName then
                        totalDamage = totalDamage + (player.damage or 0)
                        totalHealing = totalHealing + (player.healing or 0)
                        totalInterrupts = totalInterrupts + (player.interrupts or 0)
                        playerRunCount = playerRunCount + 1
                    end
                end
            end
            
            if run.completed then
                if run.keystoneLevel and run.keystoneLevel > stats.bestKeystoneLevel then
                    stats.bestKeystoneLevel = run.keystoneLevel
                elseif run.dungeonLevel and run.dungeonLevel > stats.bestKeystoneLevel then
                    stats.bestKeystoneLevel = run.dungeonLevel
                end

                if run.duration and run.duration > stats.bestDuration then
                    stats.bestDuration = run.duration
                    stats.bestTime = run.timestamp
                end
            end
            end
        end
    end

    if stats.totalRuns == 0 then
        return nil
    end

    stats.avgDuration = stats.totalRuns > 0 and math.floor(totalDuration / stats.totalRuns) or 0
    stats.avgKeystoneLevel = stats.totalRuns > 0 and math.floor(totalLevel / stats.totalRuns) or 0
    stats.avgDamage = playerRunCount > 0 and math.floor(totalDamage / playerRunCount) or 0
    stats.avgHealing = playerRunCount > 0 and math.floor(totalHealing / playerRunCount) or 0
    stats.avgInterrupts = playerRunCount > 0 and math.floor(totalInterrupts / playerRunCount) or 0
    stats.avgMobPercentage = stats.totalRuns > 0 and math.floor(totalMobPercentage / stats.totalRuns) or 0
    stats.bestDamage = bestDamage
    stats.bestHealing = bestHealing
    stats.bestInterrupts = bestInterrupts
    
    return stats
end

-- Get overall run statistics (across all dungeons)
function MPT.Database:GetOverallStatistics(characterName, realm, keystoneLevelFilter, resultFilter)
    local runs = characterName and self:GetRunsByCharacter(characterName, realm) or (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}

    if not runs or #runs == 0 then
        return nil
    end

    local stats = {
        totalRuns = 0,
        completedRuns = 0,
        failedRuns = 0,
        avgDuration = 0,
        avgKeystoneLevel = 0,
        avgDamage = 0,
        avgHealing = 0,
        avgInterrupts = 0,
        avgMobPercentage = 0,
        bestKeystoneLevel = 0,
        bestDuration = 0,
        bestTime = nil,
    }

    local totalDuration = 0
    local totalLevel = 0
    local totalDamage = 0
    local totalHealing = 0
    local totalInterrupts = 0
    local totalMobPercentage = 0
    local playerRunCount = 0
    local bestDamage = 0
    local bestHealing = 0
    local bestInterrupts = 0

    for _, run in ipairs(runs) do
        local runLevel = (run.keystoneLevel or run.dungeonLevel)
        if (not keystoneLevelFilter) or (runLevel == keystoneLevelFilter) then
            -- Apply result filter (completed/failed)
            local allowRun = true
            if resultFilter ~= nil then
                if resultFilter == true and not run.completed then
                    allowRun = false
                end
                if resultFilter == false and run.completed then
                    allowRun = false
                end
            end

            if allowRun then
                stats.totalRuns = stats.totalRuns + 1

                if run.completed then
                    stats.completedRuns = stats.completedRuns + 1
                else
                    stats.failedRuns = stats.failedRuns + 1
                end

            totalDuration = totalDuration + (run.duration or 0)
            totalLevel = totalLevel + (runLevel or 0)
            totalMobPercentage = totalMobPercentage + (run.overallMobPercentage or 0)

            -- Best stats from completed runs only
            if run.completed then
                if run.playerStats then
                    for _, pstats in pairs(run.playerStats) do
                        bestDamage = math.max(bestDamage, pstats.damage or 0)
                        bestHealing = math.max(bestHealing, pstats.healing or 0)
                        bestInterrupts = math.max(bestInterrupts, pstats.interrupts or 0)
                    end
                elseif run.players then
                    for _, player in ipairs(run.players) do
                        bestDamage = math.max(bestDamage, player.damage or 0)
                        bestHealing = math.max(bestHealing, player.healing or 0)
                        bestInterrupts = math.max(bestInterrupts, player.interrupts or 0)
                    end
                end
            end

            -- Player averages (if run has players array)
            if run.players then
                for _, player in ipairs(run.players) do
                    if player.name == characterName or not characterName then
                        totalDamage = totalDamage + (player.damage or 0)
                        totalHealing = totalHealing + (player.healing or 0)
                        totalInterrupts = totalInterrupts + (player.interrupts or 0)
                        playerRunCount = playerRunCount + 1
                    end
                end
            end

            if run.completed then
                if runLevel and runLevel > stats.bestKeystoneLevel then
                    stats.bestKeystoneLevel = runLevel
                end

                if run.duration and run.duration > stats.bestDuration then
                    stats.bestDuration = run.duration
                    stats.bestTime = run.timestamp
                end
            end
            end
        end
    end

    if stats.totalRuns == 0 then
        return nil
    end

    stats.avgDuration = stats.totalRuns > 0 and math.floor(totalDuration / stats.totalRuns) or 0
    stats.avgKeystoneLevel = stats.totalRuns > 0 and math.floor(totalLevel / stats.totalRuns) or 0
    stats.avgDamage = playerRunCount > 0 and math.floor(totalDamage / playerRunCount) or 0
    stats.avgHealing = playerRunCount > 0 and math.floor(totalHealing / playerRunCount) or 0
    stats.avgInterrupts = playerRunCount > 0 and math.floor(totalInterrupts / playerRunCount) or 0
    stats.avgMobPercentage = stats.totalRuns > 0 and math.floor(totalMobPercentage / stats.totalRuns) or 0
    stats.bestDamage = bestDamage
    stats.bestHealing = bestHealing
    stats.bestInterrupts = bestInterrupts

    return stats
end

-- Get best performance stats
function MPT.Database:GetBestStats(character, dungeon)
    local bestDamage = 0
    local bestHealing = 0
    local bestInterrupts = 0
    local bestDamageRun = nil
    local bestHealingRun = nil
    local bestInterruptsRun = nil
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    for _, run in ipairs(runs) do
        local characterOk = (not character) or (not run.character) or (run.character == character)
        local dungeonOk = (not dungeon) or (not run.dungeonName) or (run.dungeonName == dungeon)
        if characterOk and dungeonOk and run.completed then
        -- Get max stats from playerStats
        local maxDamage = 0
        local maxHealing = 0
        local maxInterrupts = 0
        
        if run.playerStats then
            for name, stats in pairs(run.playerStats) do
                maxDamage = math.max(maxDamage, stats.damage or 0)
                maxHealing = math.max(maxHealing, stats.healing or 0)
                maxInterrupts = math.max(maxInterrupts, stats.interrupts or 0)
            end
        end
        
        if maxDamage > bestDamage then
            bestDamage = maxDamage
            bestDamageRun = run
        end
        
        if maxHealing > bestHealing then
            bestHealing = maxHealing
            bestHealingRun = run
        end
        
        if maxInterrupts > bestInterrupts then
            bestInterrupts = maxInterrupts
            bestInterruptsRun = run
        end

        end
    end
    
    return {
        bestDamage = bestDamage,
        bestDamageRun = bestDamageRun,
        bestHealing = bestHealing,
        bestHealingRun = bestHealingRun,
        bestInterrupts = bestInterrupts,
        bestInterruptsRun = bestInterruptsRun,
    }
end

-- Get all unique keystone levels
function MPT.Database:GetAllKeystoneLevels()
    local levels = {}
    local seen = {}
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    for _, run in ipairs(runs) do
        local level = run.dungeonLevel or run.keystoneLevel or 0
        if not seen[level] then
            seen[level] = true
            table.insert(levels, level)
        end
    end
    
    table.sort(levels)
    return levels
end

