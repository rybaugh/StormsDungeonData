-- Mythic Plus Tracker - Test Mode Module
-- Allows testing and simulating dungeon runs outside of actual dungeons
-- Useful for development and demonstration purposes

local MPT = StormsDungeonData
local TestMode = {}
MPT.TestMode = TestMode

-- Test data presets - realistic player stats
TestMode.TestPresets = {
    DungeonPresets = {
        { id = 670, name = "Nerub-ar Palace" },
        { id = 1107, name = "Cinderbrew Meadery" },
        { id = 1110, name = "Darkflesh Thicket" },
        { id = 938, name = "Underrot" },
        { id = 1347, name = "The Nokhud Offensive" },
        { id = 968, name = "Atal'Dazar" },
        { id = 721, name = "Black Rook Hold" },
        { id = 1182, name = "Sanguine Depths" },
    },
    
    -- Realistic DPS values (damage per second)
    DamageProfile = {
        min = 50000,
        max = 150000,
        avgEvents = 200,
    },
    
    -- Realistic healing values
    HealingProfile = {
        min = 30000,
        max = 100000,
        avgEvents = 150,
    },
    
    -- Realistic interrupt profile
    InterruptProfile = {
        minInterrupts = 2,
        maxInterrupts = 8,
    },
}

-- Generate random dungeon data
function TestMode:GenerateDungeonData()
    local presets = self.TestPresets.DungeonPresets
    local preset = presets[math.random(#presets)]
    local dungeonName = preset.name or preset
    local dungeonLevel = 2 + math.random(0, 18)  -- M+ 2-20
    
    return {
        id = preset.id or 0,
        name = dungeonName,
        level = dungeonLevel,
        timeLimit = 45 * 60,  -- 45 minutes in seconds
    }
end

local function ConvertPlayerStatsToPlayersArray(playerStats)
    local players = {}
    if not playerStats then
        return players
    end

    local playerName = UnitName("player")
    local playerClass = select(2, UnitClass("player"))

    local roleOrder = {
        { role = "TANK", class = "WARRIOR" },
        { role = "HEALER", class = "PRIEST" },
        { role = "DAMAGER", class = "MAGE" },
        { role = "DAMAGER", class = "ROGUE" },
        { role = "DAMAGER", class = "HUNTER" },
    }

    local i = 1
    for name, stats in pairs(playerStats) do
        local roleInfo = roleOrder[i] or roleOrder[#roleOrder]
        local classToken = roleInfo.class
        if playerName and playerClass and name == playerName then
            classToken = playerClass
        end
        table.insert(players, {
            name = name,
            class = classToken,
            role = roleInfo.role,
            damage = stats.damage or 0,
            healing = stats.healing or 0,
            interrupts = stats.interrupts or 0,
            deaths = stats.deaths or 0,
        })
        i = i + 1
    end

    return players
end

function TestMode:SeedHistory(count)
    count = tonumber(count) or 15
    count = math.floor(count)
    if count < 1 then count = 1 end
    if count > 200 then count = 200 end

    if not StormsDungeonDataDB then
        if MPT.Database and MPT.Database.CreateDefaultDB then
            StormsDungeonDataDB = MPT.Database:CreateDefaultDB()
        else
            StormsDungeonDataDB = { version = 1, runs = {}, characters = {}, settings = {} }
        end
    end

    if MPT.Database and MPT.Database.Initialize then
        MPT.Database:Initialize()
    else
        StormsDungeonDataDB.runs = StormsDungeonDataDB.runs or {}
        StormsDungeonDataDB.characters = StormsDungeonDataDB.characters or {}
        StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
    end

    for i = 1, count do
        local dungeonData = self:GenerateDungeonData()
        local playerStats = self:GeneratePlayerStats()
        local players = ConvertPlayerStatsToPlayersArray(playerStats)

        local duration = math.random(1200, 2700)
        local completed = (math.random(1, 10) ~= 1) -- ~90% completed

        local runRecord = MPT.Database:CreateRunRecord(
            dungeonData.id,
            dungeonData.name,
            dungeonData.level,
            completed,
            duration,
            players
        )

        local offset = math.random(600, 7 * 24 * 60 * 60) -- within last week
        runRecord.timestamp = time() - offset
        if runRecord.endTime then
            runRecord.endTime = GetServerTime() - offset
            runRecord.startTime = runRecord.endTime - duration
        end

        runRecord.dungeonLevel = dungeonData.level
        runRecord.playerStats = playerStats
        runRecord.overallMobPercentage = completed and 100 or math.random(70, 99)
        runRecord.isTestRun = true

        table.insert(StormsDungeonDataDB.runs, runRecord)
    end

    print(string.format("|cff00ffaa[StormsDungeonData]|r Generated %d fake runs. Use |cff00ffaa/sdd history|r.", count))
end

-- Generate realistic player stats for a test run
function TestMode:GeneratePlayerStats()
    local stats = {}
    
    -- Always generate 5 party members for M+ groups
    local playerName = UnitName("player")
    local partyNames = {playerName, "Healer", "Tank", "DPS1", "DPS2"}
    
    for i = 1, 5 do
        local name = partyNames[i]
        
        -- Generate realistic damage values
        local damageAmount = math.random(
            self.TestPresets.DamageProfile.min,
            self.TestPresets.DamageProfile.max
        )
        
        -- Generate realistic healing (for healers, 0 for DPS)
        local isHealer = (i == 2)  -- Second member is the healer
        local healingAmount = isHealer and math.random(
            self.TestPresets.HealingProfile.min,
            self.TestPresets.HealingProfile.max
        ) or 0
        
        -- Generate interrupts
        local interruptCount = math.random(
            self.TestPresets.InterruptProfile.minInterrupts,
            self.TestPresets.InterruptProfile.maxInterrupts
        )
        
        stats[name] = {
            damage = damageAmount,
            healing = healingAmount,
            interrupts = interruptCount,
            deaths = (math.random(1, 20) == 1) and 1 or 0,  -- 5% chance to die
            damageEvents = math.random(math.floor(self.TestPresets.DamageProfile.avgEvents * 0.7), math.ceil(self.TestPresets.DamageProfile.avgEvents * 1.3)),
            healingEvents = isHealer and math.random(math.floor(self.TestPresets.HealingProfile.avgEvents * 0.7), math.ceil(self.TestPresets.HealingProfile.avgEvents * 1.3)) or 0,
        }
    end
    
    return stats
end

-- Simulate a complete dungeon run
function TestMode:SimulateDungeonRun()
    print("|cff00ffaa[StormsDungeonData]|r Starting test dungeon simulation...")
    
    -- Initialize database if it doesn't exist
    if not StormsDungeonDataDB then
        StormsDungeonDataDB = MPT.Database:CreateDefaultDB()
        MPT.Database:Initialize()
    end
    
    -- Ensure runs table exists
    if not StormsDungeonDataDB.runs then
        StormsDungeonDataDB.runs = {}
    end
    
    -- Generate test data
    local dungeonData = self:GenerateDungeonData()
    local playerStats = self:GeneratePlayerStats()
    
    -- Generate run metadata
    local duration = math.random(1200, 2700)  -- 20-45 minutes
    local actualTime = duration
    local timeLimit = dungeonData.timeLimit
    local completed = true
    local timeCompleted = "in time"
    
    -- Calculate affix percent
    local affixPercent = 100 + math.random(0, 200)  -- 100-300%
    
    local players = ConvertPlayerStatsToPlayersArray(playerStats)

    -- Create run record (real schema) + keep legacy fields for compatibility
    local runRecord = MPT.Database:CreateRunRecord(
        dungeonData.id,
        dungeonData.name,
        dungeonData.level,
        completed,
        duration,
        players
    )
    runRecord.dungeonLevel = dungeonData.level
    runRecord.actualTime = actualTime
    runRecord.timeLimit = timeLimit
    runRecord.timeCompleted = timeCompleted
    runRecord.affixPercent = affixPercent
    runRecord.playerStats = playerStats
    runRecord.overallMobPercentage = 100
    runRecord.isTestRun = true  -- Mark as test data
    
    -- Store in database
    table.insert(StormsDungeonDataDB.runs, runRecord)
    
    -- Store character history
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    local fullCharName = playerName .. "-" .. realmName
    
    if not StormsDungeonDataDB.characterRuns then
        StormsDungeonDataDB.characterRuns = {}
    end
    
    if not StormsDungeonDataDB.characterRuns[fullCharName] then
        StormsDungeonDataDB.characterRuns[fullCharName] = {}
    end
    
    table.insert(StormsDungeonDataDB.characterRuns[fullCharName], runRecord)
    
    -- Display test run summary
    print("|cffaabbff========== TEST RUN SUMMARY ==========|r")
    print("|cff00ffaa" .. dungeonData.name .. " M+" .. dungeonData.level .. "|r")
    print("Duration: " .. MPT.Utils:FormatDuration(duration) .. " (" .. timeCompleted .. ")")
    print("Affixes: " .. affixPercent .. "%")
    print("")
    print("|cffaabbffParty Performance:|r")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    local totalDamage = 0
    local totalHealing = 0
    local totalInterrupts = 0
    
    for playerName, stats in pairs(playerStats) do
        totalDamage = totalDamage + stats.damage
        totalHealing = totalHealing + stats.healing
        totalInterrupts = totalInterrupts + stats.interrupts
        
        local dps = math.floor(stats.damage / duration)
        local hps = stats.healing > 0 and math.floor(stats.healing / duration) or 0
        
        print(string.format("|cff%s%-12s|r DMG: %s (%s) | HPS: %s | INT: %d",
            (stats.deaths > 0) and "ff0000" or "00ff00",
            playerName .. (stats.deaths > 0 and " ✗" or ""),
            MPT.Utils:FormatNumber(stats.damage),
            MPT.Utils:FormatNumber(dps) .. " dps",
            MPT.Utils:FormatNumber(hps) .. " hps",
            stats.interrupts
        ))
    end
    
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("|cffaabbffTotals:|r")
    print(string.format("  Total Damage: |cffff8000%s|r", MPT.Utils:FormatNumber(totalDamage)))
    print(string.format("  Total Healing: |cff00ff00%s|r", MPT.Utils:FormatNumber(totalHealing)))
    print(string.format("  Total Interrupts: |cff0088ff%d|r", totalInterrupts))
    print("|cffaabbff=========================================|r")
    print("|cff00ffaa[StormsDungeonData]|r Test run saved! Use |cff00ffaa/sdd history|r to view.")
    
    -- Show scoreboard
    if MPT.UI and MPT.UI.ShowScoreboard then
        MPT.UI:ShowScoreboard(runRecord)
    end
end

print("|cff00ffaa[StormsDungeonData]|r Test Mode module loaded")
