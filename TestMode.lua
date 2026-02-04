-- Mythic Plus Tracker - Test Mode Module
-- Allows testing and simulating dungeon runs outside of actual dungeons
-- Useful for development and demonstration purposes

local MPT = StormsDungeonData
local TestMode = {}
MPT.TestMode = TestMode

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

local function GetPlayerSpecInfoSafe()
    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end

    local specID, specName, _, specIcon, role, classToken = GetSpecializationInfo(specIndex)
    if not specID then
        return nil
    end

    return {
        specID = specID,
        specName = specName,
        specIcon = specIcon,
        specRole = role,
        specClass = classToken,
    }
end

local function GetHeroTalentInfoSafe()
    if not C_ClassTalents or not C_Traits then
        return nil
    end

    local function GetSubTreeInfoSafe(configID, subTreeID)
        if type(C_Traits.GetSubTreeInfo) ~= "function" then
            return nil
        end
        local info = SafeCall(C_Traits.GetSubTreeInfo, configID, subTreeID)
        if not info and subTreeID then
            info = SafeCall(C_Traits.GetSubTreeInfo, subTreeID)
        end
        return info
    end

    local function GetTreeInfoSafe(configID, treeID)
        if type(C_Traits.GetTreeInfo) ~= "function" then
            return nil
        end
        local info = SafeCall(C_Traits.GetTreeInfo, configID, treeID)
        if not info and treeID then
            info = SafeCall(C_Traits.GetTreeInfo, treeID)
        end
        return info
    end

    local configID = SafeCall(C_ClassTalents.GetActiveConfigID)
    if not configID and type(C_Traits.GetActiveConfigID) == "function" then
        configID = SafeCall(C_Traits.GetActiveConfigID)
    end

    local heroSpecID = SafeCall(C_ClassTalents.GetActiveHeroTalentSpec)
    if heroSpecID and type(C_ClassTalents.GetHeroTalentSpecInfo) == "function" then
        local heroInfo = SafeCall(C_ClassTalents.GetHeroTalentSpecInfo, heroSpecID)
        if type(heroInfo) == "table" then
            local heroTreeID = heroInfo.subTreeID or heroInfo.heroTreeID or heroSpecID
            local heroName = heroInfo.name or heroInfo.specName
            local heroIcon = heroInfo.icon or heroInfo.iconFileID or heroInfo.iconID
            if heroTreeID or heroName or heroIcon then
                return {
                    heroTreeID = heroTreeID,
                    heroName = heroName,
                    heroIcon = heroIcon,
                }
            end
        end
    end

    local subTreeID = heroSpecID
    if not subTreeID then
        subTreeID = SafeCall(C_ClassTalents.GetActiveHeroTalentTreeID)
    end

    if (not subTreeID or subTreeID == 0) and configID and type(C_ClassTalents.GetHeroTalentSpecsForClassSpec) == "function" then
        local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
        local specID = specIndex and type(GetSpecializationInfo) == "function" and select(1, GetSpecializationInfo(specIndex)) or nil
        if specID then
            local subTreeIDs = SafeCall(C_ClassTalents.GetHeroTalentSpecsForClassSpec, configID, specID)
            if type(subTreeIDs) == "table" then
                for _, id in ipairs(subTreeIDs) do
                    local info = GetSubTreeInfoSafe(configID, id)
                    if info and info.isActive then
                        subTreeID = id
                        break
                    end
                end
            end
        end
    end

    if configID and subTreeID then
        local subTreeInfo = GetSubTreeInfoSafe(configID, subTreeID)
        if type(subTreeInfo) == "table" then
            return {
                heroTreeID = subTreeID,
                heroName = subTreeInfo.name,
                heroIcon = subTreeInfo.icon or subTreeInfo.iconFileID or subTreeInfo.iconID,
            }
        end

        local treeInfo = GetTreeInfoSafe(configID, subTreeID)
        if type(treeInfo) == "table" then
            return {
                heroTreeID = subTreeID,
                heroName = treeInfo.name,
                heroIcon = treeInfo.icon or treeInfo.iconFileID or treeInfo.iconID,
            }
        end
    end

    return subTreeID and { heroTreeID = subTreeID } or nil
end

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

    local names = {}
    for name in pairs(playerStats) do
        table.insert(names, name)
    end
    table.sort(names)

    local i = 1
    for _, name in ipairs(names) do
        local stats = playerStats[name] or {}
        local roleInfo = roleOrder[i] or roleOrder[#roleOrder]
        local role = roleInfo.role
        local classToken = roleInfo.class

        local lowerName = tostring(name):lower()
        if lowerName:find("tank") then
            role = "TANK"
            classToken = "WARRIOR"
        elseif lowerName:find("heal") then
            role = "HEALER"
            classToken = "PRIEST"
        elseif lowerName:find("dps") then
            role = "DAMAGER"
        else
            role = "DAMAGER"
        end

        if playerName and playerClass and name == playerName then
            classToken = playerClass
        end

        table.insert(players, {
            name = name,
            class = classToken,
            role = role,
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

        do
            local spec = GetPlayerSpecInfoSafe()
            if spec then
                runRecord.specID = spec.specID
                runRecord.specName = spec.specName
                runRecord.specIcon = spec.specIcon
                runRecord.specRole = spec.specRole
            end

            local hero = GetHeroTalentInfoSafe()
            if hero then
                runRecord.heroTreeID = hero.heroTreeID
                runRecord.heroName = hero.heroName
                runRecord.heroIcon = hero.heroIcon
            end
        end

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

    do
        local spec = GetPlayerSpecInfoSafe()
        if spec then
            runRecord.specID = spec.specID
            runRecord.specName = spec.specName
            runRecord.specIcon = spec.specIcon
            runRecord.specRole = spec.specRole
        end

        local hero = GetHeroTalentInfoSafe()
        if hero then
            runRecord.heroTreeID = hero.heroTreeID
            runRecord.heroName = hero.heroName
            runRecord.heroIcon = hero.heroIcon
        end
    end
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
