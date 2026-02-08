-- Mythic Plus Tracker - Database Module
-- Handles all data storage and retrieval

local MPT = StormsDungeonData
MPT.Database = MPT.Database or {}

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
    if not StormsDungeonDataDB.playerRatings then
        StormsDungeonDataDB.playerRatings = {}
    end
    if not StormsDungeonDataDB.playerRatingGoodCount then
        StormsDungeonDataDB.playerRatingGoodCount = {}
    end
    if not StormsDungeonDataDB.playerRatingBadCount then
        StormsDungeonDataDB.playerRatingBadCount = {}
    end
    
    print("|cff00ffaa[StormsDungeonData]|r Database initialized")
end

function MPT.Database:GetPlayerGoodCount(playerName)
    if not StormsDungeonDataDB or not StormsDungeonDataDB.playerRatingGoodCount then return 0 end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return 0 end
    local n = StormsDungeonDataDB.playerRatingGoodCount[key]
    return (type(n) == "number" and n > 0) and n or 0
end

function MPT.Database:IncrementPlayerGoodCount(playerName)
    if not StormsDungeonDataDB then return false end
    if not StormsDungeonDataDB.playerRatingGoodCount then
        StormsDungeonDataDB.playerRatingGoodCount = {}
    end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return false end
    local n = StormsDungeonDataDB.playerRatingGoodCount[key] or 0
    StormsDungeonDataDB.playerRatingGoodCount[key] = n + 1
    return true
end

function MPT.Database:GetPlayerBadCount(playerName)
    if not StormsDungeonDataDB or not StormsDungeonDataDB.playerRatingBadCount then return 0 end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return 0 end
    local n = StormsDungeonDataDB.playerRatingBadCount[key]
    return (type(n) == "number" and n > 0) and n or 0
end

function MPT.Database:IncrementPlayerBadCount(playerName)
    if not StormsDungeonDataDB then return false end
    if not StormsDungeonDataDB.playerRatingBadCount then
        StormsDungeonDataDB.playerRatingBadCount = {}
    end
    local key = self:GetPlayerRatingKey(playerName)
    if not key then return false end
    local n = StormsDungeonDataDB.playerRatingBadCount[key] or 0
    StormsDungeonDataDB.playerRatingBadCount[key] = n + 1
    return true
end

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
        startTime = GetServerTime() - duration,  -- Approximate
        endTime = GetServerTime(),
        players = players,  -- Array of player stats
        mobsKilled = 0,
        mobsTotal = 0,
        overallMobPercentage = 0,
    }
end

-- Create player stat record
function MPT.Database:CreatePlayerStats(unitID, name, class, role)
    return {
        unitID = unitID,
        name = name,
        class = class,
        role = role,
        damage = 0,
        healing = 0,
        interrupts = 0,
        deaths = 0,
        pointsGained = 0,
        damagePerSecond = 0,
        healingPerSecond = 0,
        interruptsPerMinute = 0,
    }
end

-- Save a completed run
function MPT.Database:SaveRun(runRecord)
    if not runRecord or not runRecord.dungeonID then
        print("|cff00ffaa[StormsDungeonData]|r Error: Invalid run record")
        return false
    end
    
    table.insert(StormsDungeonDataDB.runs, runRecord)
    return true
end

-- Delete a run by ID
function MPT.Database:DeleteRun(runID)
    if not runID or not StormsDungeonDataDB or not StormsDungeonDataDB.runs then
        return false
    end
    
    for i = #StormsDungeonDataDB.runs, 1, -1 do
        if StormsDungeonDataDB.runs[i].id == runID then
            table.remove(StormsDungeonDataDB.runs, i)
            return true
        end
    end
    
    return false
end

-- Get all runs for a specific character
function MPT.Database:GetRunsByCharacter(characterName, realm)
    local result = {}
    for _, run in ipairs(StormsDungeonDataDB.runs) do
        if run.character == characterName and run.realm == realm then
            table.insert(result, run)
        end
    end
    return result
end

-- Get runs for a specific dungeon
function MPT.Database:GetRunsByDungeon(dungeonID, characterName, realm, dungeonName)
    local result = {}
    local runs = characterName and self:GetRunsByCharacter(characterName, realm) or StormsDungeonDataDB.runs
    local hasDungeonID = (dungeonID and dungeonID ~= 0)
    
    for _, run in ipairs(runs) do
        if (hasDungeonID and run.dungeonID == dungeonID) or (not hasDungeonID and dungeonName and run.dungeonName == dungeonName) then
            table.insert(result, run)
        end
    end
    
    -- Sort by timestamp descending (newest first)
    table.sort(result, function(a, b) return a.timestamp > b.timestamp end)
    return result
end

-- Get all unique characters in database
function MPT.Database:GetAllCharacters()
    local characters = {}
    local seen = {}
    
    for _, run in ipairs(StormsDungeonDataDB.runs) do
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
    
    table.sort(characters, function(a, b)
        if a.realm ~= b.realm then
            return a.realm < b.realm
        end
        return a.name < b.name
    end)
    
    return characters
end

-- Get all unique dungeons
function MPT.Database:GetAllDungeons()
    local dungeons = {}
    local seen = {}
    
    for _, run in ipairs(StormsDungeonDataDB.runs) do
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
    
    -- Count runs per dungeon
    for _, run in ipairs(StormsDungeonDataDB.runs) do
        for _, dungeon in ipairs(dungeons) do
            if (dungeon.id == run.dungeonID and dungeon.id ~= 0) or (dungeon.name == run.dungeonName) then
                dungeon.count = dungeon.count + 1
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
    local runs = characterName and self:GetRunsByCharacter(characterName, realm) or StormsDungeonDataDB.runs

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
    
    for _, run in ipairs(StormsDungeonDataDB.runs) do
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
    
    for _, run in ipairs(StormsDungeonDataDB.runs) do
        local level = run.dungeonLevel or run.keystoneLevel or 0
        if not seen[level] then
            seen[level] = true
            table.insert(levels, level)
        end
    end
    
    table.sort(levels)
    return levels
end

print("|cff00ffaa[StormsDungeonData]|r Database module loaded")
