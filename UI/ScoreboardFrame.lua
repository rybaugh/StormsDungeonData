-- Mythic Plus Tracker - Scoreboard Frame
-- Displays run statistics at dungeon completion
--
-- MVP uses balanced_roles: role-weighted scoring with per-spec weights.
-- Weights are looked up by specID first, then class token, then role fallback.
-- Non-manually-tuned specs are normalized at score time so total coefficient size does not
-- create a higher MVP ceiling by itself.
-- Interrupt weights use utility buckets instead of rewarding longer cooldowns:
--   12s premium kicks ~= 0.60, standard 15s kicks ~= 0.55, 24s ranged kicks ~= 0.45,
--   long-CD/special-case stops ~= 0.35.
-- Healers keep int = 0.00 because kick opportunities are scarce for healer roles.
-- A heal-share dampener (HEALER_HEAL_DAMPENER = 0.30) corrects for concentration asymmetry:
--   1 healer captures ~85-90% of group healing while each DPS captures only ~20-30% of damage.
--   Without dampening, healing contribution alone scores significantly higher than any DPS's damage.
-- Disp weights reflect each spec's dispel capability and expectation in M+.
local MPT = StormsDungeonData
local Scoreboard = {}
MPT.Scoreboard = Scoreboard

-- Per-spec weights keyed by specID. { dmg, heal, int, disp }
-- dmg + heal always sums to 1.0 (normalized from raw ratios for fairness across specs).
-- specID reference: https://warcraft.wiki.gg/wiki/SpecializationID
local SPEC_MVP_WEIGHTS = {
    -- Death Knight (no dispel)
    [250] = { 0.65, 0.35, 0.65, 0.00 }, -- Blood (tank)
    [251] = { 0.90, 0.10, 0.55, 0.00 }, -- Frost (DPS)
    [252] = { 0.90, 0.10, 0.55, 0.00 }, -- Unholy (DPS)
    -- Demon Hunter (no dispel)
    [577]  = { 0.90, 0.10, 0.55, 0.00 }, -- Havoc (DPS)      – 15s Disrupt
    [581]  = { 0.80, 0.20, 0.65, 0.00 }, -- Vengeance (tank)
    [1480] = { 0.90, 0.10, 0.55, 0.00 }, -- Devourer (DPS)   – interrupt CD assumed 15s
    -- Druid
    [102] = { 0.90, 0.10, 0.35, 0.05 }, -- Balance (DPS)      – Solar Beam 60s; Remove Corruption
    [103] = { 0.90, 0.10, 0.55, 0.05 }, -- Feral (DPS)        – Skull Bash 15s; Remove Corruption
    [104] = { 0.80, 0.20, 0.65, 0.10 }, -- Guardian (tank)    – Remove Corruption
    [105] = { 0.28, 0.72, 0.00, 0.08 }, -- Restoration (heal) – Nature's Cure
    -- Evoker
    [1467] = { 0.90, 0.10, 0.65, 0.00 }, -- Devastation (DPS)    – Quell 40s; no dispel
    [1468] = { 0.28, 0.72, 0.00, 0.08 }, -- Preservation (heal)  – Cauterize Magic
    [1473] = { 1.25, 0.10, 0.65, 0.00 }, -- Augmentation (DPS)   – Quell 40s; no dispel
    -- Hunter (no dispel)
    [253] = { 0.90, 0.10, 0.45, 0.00 }, -- Beast Mastery (DPS)  – Counter Shot 24s
    [254] = { 0.90, 0.10, 0.45, 0.00 }, -- Marksmanship (DPS)
    [255] = { 0.90, 0.10, 0.55, 0.00 }, -- Survival (DPS)       – Muzzle 15s
    -- Mage (Remove Curse – single type)
    [62] = { 0.90, 0.10, 0.45, 0.05 }, -- Arcane (DPS) – Counterspell 24s; Remove Curse
    [63] = { 0.90, 0.10, 0.45, 0.05 }, -- Fire (DPS)
    [64] = { 0.90, 0.10, 0.45, 0.05 }, -- Frost (DPS)
    -- Monk
    [268] = { 0.85, 0.15, 0.65, 0.00 }, -- Brewmaster (tank)   – no dispel
    [269] = { 0.90, 0.10, 0.55, 0.00 }, -- Windwalker (DPS)    – no dispel
    [270] = { 0.28, 0.72, 0.00, 0.08 }, -- Mistweaver (heal)   – Detox
    -- Paladin
    [65] = { 0.28, 0.72, 0.00, 0.08 }, -- Holy (heal)         – Cleanse
    [66] = { 0.80, 0.20, 0.55, 0.10 }, -- Protection (tank)   – Avenger's Shield / Rebuke
    [70] = { 0.90, 0.10, 0.55, 0.05 }, -- Retribution (DPS)   – Cleanse Toxins
    -- Priest
    [256] = { 0.28, 0.72, 0.00, 0.08 }, -- Discipline (heal) – Dispel Magic + Mass Dispel
    [257] = { 0.28, 0.72, 0.00, 0.08 }, -- Holy (heal)       – Dispel Magic + Mass Dispel
    [258] = { 0.90, 0.10, 0.35, 0.05 }, -- Shadow (DPS)      – Silence / Mass Dispel
    -- Rogue (no dispel)
    [259] = { 0.90, 0.10, 0.55, 0.00 }, -- Assassination
    [260] = { 0.90, 0.10, 0.55, 0.00 }, -- Outlaw
    [261] = { 0.90, 0.10, 0.55, 0.00 }, -- Subtlety
    -- Shaman
    [262] = { 0.90, 0.15, 0.60, 0.05 }, -- Elemental (DPS)    – Wind Shear 12s; Purge (enemy buffs)
    [263] = { 0.90, 0.15, 0.60, 0.05 }, -- Enhancement (DPS)  – Wind Shear 12s; Purge
    [264] = { 0.28, 0.72, 0.00, 0.08 }, -- Restoration (heal) – Cleanse Spirit + Purge
    -- Warlock (Singe Magic via pet – very limited)
    [265] = { 0.90, 0.10, 0.55, 0.00 }, -- Affliction
    [266] = { 0.90, 0.10, 0.55, 0.00 }, -- Demonology
    [267] = { 0.90, 0.10, 0.55, 0.00 }, -- Destruction
    -- Warrior (no dispel)
    [71] = { 0.90, 0.10, 0.55, 0.00 }, -- Arms
    [72] = { 0.90, 0.10, 0.55, 0.00 }, -- Fury
    [73] = { 0.80, 0.20, 0.65, 0.00 }, -- Protection
}

-- Per-class fallback weights when specID is unavailable. { dmg, heal, int, disp }
-- dmg + heal sums to 1.0 to match spec table fairness constraint.
local CLASS_MVP_WEIGHTS = {
    DEATHKNIGHT  = { TANK = { 0.80, 0.20, 0.65, 0.00 }, HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    DEMONHUNTER  = { TANK = { 0.80, 0.20, 0.65, 0.00 }, HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    DRUID        = { TANK = { 0.80, 0.20, 0.65, 0.10 }, HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.45, 0.05 } },
    EVOKER       = { TANK = nil,                         HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.65, 0.00 } },
    HUNTER       = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.45, 0.00 } },
    MAGE         = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.45, 0.05 } },
    MONK         = { TANK = { 0.80, 0.20, 0.65, 0.00 }, HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    PALADIN      = { TANK = { 0.80, 0.20, 0.55, 0.10 }, HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.55, 0.05 } },
    PRIEST       = { TANK = nil,                         HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.35, 0.05 } },
    ROGUE        = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    SHAMAN       = { TANK = nil,                         HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.15, 0.60, 0.05 } },
    WARLOCK      = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    WARRIOR      = { TANK = { 0.80, 0.20, 0.65, 0.00 }, HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
}

-- Role-only fallback weights (no class/spec data available). { dmg, heal, int, disp }
-- dmg + heal sums to 1.0 to match spec table fairness constraint.
local ROLE_MVP_WEIGHTS = {
    HEALER  = { 0.28, 0.72, 0.00, 0.08 },
    TANK    = { 0.80, 0.20, 0.65, 0.05 },
    DAMAGER = { 0.90, 0.10, 0.55, 0.05 },
}

local function GetMVPWeights(role, specID, class)
    -- 1. specID lookup (most precise)
    local specID_n = tonumber(specID)
    if specID_n and specID_n > 0 then
        local w = SPEC_MVP_WEIGHTS[specID_n]
        if w then return w[1], w[2], w[3], w[4] end
    end
    -- 2. class + role lookup
    local classWeights = class and CLASS_MVP_WEIGHTS[class]
    if classWeights then
        local r = (role == "TANK" or role == "HEALER" or role == "DAMAGER") and role or "DAMAGER"
        local w = classWeights[r]
        if w then return w[1], w[2], w[3], w[4] end
    end
    -- 3. role-only fallback
    local r = (role == "TANK" or role == "HEALER" or role == "DAMAGER") and role or "DAMAGER"
    local w = ROLE_MVP_WEIGHTS[r]
    return w[1], w[2], w[3], w[4]
end

-- Healing concentration correction factor: aligns healing contribution scale with
-- damage contribution scale so healers compete fairly for MVP.
local HEALER_HEAL_DAMPENER = 0.42

local function ShouldNormalizeMVPWeights(role, specID)
    local specID_n = tonumber(specID)
    -- Only Augmentation Evoker (1473) gets the unnormalized 1.25 damage boost.
    -- Devastation (1467) and Preservation (1468) follow standard normalization.
    if specID_n == 1473 then
        return false
    end
    return true
end

local function NormalizeMVPWeights(wDmg, wHeal, wInt, wDisp)
    local total = (wDmg or 0) + (wHeal or 0) + (wInt or 0) + (wDisp or 0)
    if total <= 0 then
        return 0, 0, 0, 0
    end
    return (wDmg or 0) / total, (wHeal or 0) / total, (wInt or 0) / total, (wDisp or 0) / total
end

local function MVPScoreBalancedRoles(role, dmgShare, healShare, intShare, deaths, avoidableShare, specID, class, dispelShare)
    local d, h, i, ds = dmgShare or 0, healShare or 0, intShare or 0, dispelShare or 0
    deaths = deaths or 0
    avoidableShare = avoidableShare or 0

    -- Dampen healing share for healers: corrects for 1-healer concentration vs 4-5 damage dealers
    if role == "HEALER" then
        h = h * HEALER_HEAL_DAMPENER
    end

    local wDmg, wHeal, wInt, wDisp = GetMVPWeights(role, specID, class)
    if ShouldNormalizeMVPWeights(role, specID) then
        wDmg, wHeal, wInt, wDisp = NormalizeMVPWeights(wDmg, wHeal, wInt, wDisp)
    end
    local baseScore = (wDmg * d) + (wHeal * h) + (wInt * i) + (wDisp * ds)

    -- Small flat boost for tanks: compensates for structurally lower damage/heal shares
    if role == "TANK" then
        baseScore = baseScore * 1.06
    end

    -- Penalties: each death reduces score by 8%, avoidable damage share subtracts proportionally
    local avoidablePenalty = avoidableShare * 0.35
    local deathMultiplier = (1 - 0.08) ^ deaths
    return math.max(0, (baseScore - avoidablePenalty) * deathMultiplier)
end

local TANK_CAPABLE_CLASSES = {
    DEATHKNIGHT = true,
    DEMONHUNTER = true,
    DRUID = true,
    MONK = true,
    PALADIN = true,
    WARRIOR = true,
}

local HEALER_CAPABLE_CLASSES = {
    DRUID = true,
    EVOKER = true,
    MONK = true,
    PALADIN = true,
    PRIEST = true,
    SHAMAN = true,
}

local function IsValidRole(role)
    return role == "TANK" or role == "HEALER" or role == "DAMAGER"
end

local function GetPlayerStatsView(player)
    if not player then
        return {}
    end
    if player.stats then
        return player.stats
    end
    if player.damage ~= nil or player.healing ~= nil or player.interrupts ~= nil or player.dispels ~= nil then
        return player
    end
    return {}
end

local function RoleFromSpecID(specID)
    local id = tonumber(specID)
    if not id or id <= 0 or type(GetSpecializationInfoByID) ~= "function" then
        return nil
    end
    local _, _, _, _, specRole = GetSpecializationInfoByID(id)
    return IsValidRole(specRole) and specRole or nil
end

local function InferSavedRole(player, stats)
    local directSpecRoles = {
        player and player.specRole,
        stats and stats.specRole,
    }
    for _, role in ipairs(directSpecRoles) do
        if IsValidRole(role) then
            return role
        end
    end

    local specRole = RoleFromSpecID((player and player.specID) or (stats and stats.specID))
    if specRole then
        return specRole
    end

    local directGroupRoles = {
        player and player.role,
        stats and stats.role,
    }
    for _, role in ipairs(directGroupRoles) do
        if IsValidRole(role) then
            return role
        end
    end

    return nil
end

local function AssignRolesFromPlayerData(playerData)
    local n = math.min(5, #playerData)
    local healing = {}
    local assignedRole = {}

    for j = 1, n do
        local p = playerData[j]
        local s = GetPlayerStatsView(p)
        healing[j] = tonumber(s.healing or p.healing) or 0
        local inferred = InferSavedRole(p, s)
        if inferred then
            assignedRole[j] = inferred
        end
    end

    local nTank, nHealer = 0, 0
    for j = 1, n do
        local role = assignedRole[j]
        if role == "TANK" then
            nTank = nTank + 1
        elseif role == "HEALER" then
            nHealer = nHealer + 1
        end
    end

    local unassigned = {}
    for j = 1, n do
        if not assignedRole[j] then
            unassigned[#unassigned + 1] = j
        end
    end

    if #unassigned > 0 then
        if nHealer < 1 then
            local bestHealer = nil
            local bestHealing = -1
            for _, idx in ipairs(unassigned) do
                local p = playerData[idx]
                local s = GetPlayerStatsView(p)
                local classToken = (p and p.class) or (s and s.class)
                if classToken and HEALER_CAPABLE_CLASSES[classToken] then
                    local h = healing[idx] or 0
                    if h > bestHealing then
                        bestHealer = idx
                        bestHealing = h
                    end
                end
            end
            if not bestHealer then
                bestHealer = unassigned[1]
                for _, idx in ipairs(unassigned) do
                    if (healing[idx] or 0) > (healing[bestHealer] or 0) then
                        bestHealer = idx
                    end
                end
            end
            if bestHealer then
                assignedRole[bestHealer] = "HEALER"
                for i = 1, #unassigned do
                    if unassigned[i] == bestHealer then
                        table.remove(unassigned, i)
                        break
                    end
                end
            end
        end

        if nTank < 1 and #unassigned > 0 then
            local tankIdx = nil
            local tankBestDps = nil
            for _, idx in ipairs(unassigned) do
                local p = playerData[idx]
                local s = GetPlayerStatsView(p)
                local classToken = (p and p.class) or (s and s.class)
                if classToken and TANK_CAPABLE_CLASSES[classToken] then
                    local damage = tonumber((s and s.damagePerSecond) or (p and p.damagePerSecond))
                    if not damage then
                        damage = tonumber((s and s.damage) or (p and p.damage)) or 0
                    end
                    if not tankIdx or damage < (tankBestDps or math.huge) then
                        tankIdx = idx
                        tankBestDps = damage
                    end
                end
            end
            if not tankIdx then
                tankIdx = unassigned[1]
            end
            assignedRole[tankIdx] = "TANK"
            for i = 1, #unassigned do
                if unassigned[i] == tankIdx then
                    table.remove(unassigned, i)
                    break
                end
            end
        end

        for _, idx in ipairs(unassigned) do
            assignedRole[idx] = "DAMAGER"
        end
    end

    for j = 1, n do
        if not assignedRole[j] then
            assignedRole[j] = "DAMAGER"
        end
    end

    return assignedRole, n
end

-- Build a short friend-list note from our good/bad counts (e.g. "SDD: Good +5, Bad +2")
local function GetRatingNoteForFriend(playerName)
    if not MPT.Database or not playerName then return "" end
    local goodCount = MPT.Database.GetPlayerGoodCount and MPT.Database:GetPlayerGoodCount(playerName) or 0
    local badCount = MPT.Database.GetPlayerBadCount and MPT.Database:GetPlayerBadCount(playerName) or 0
    if goodCount == 0 and badCount == 0 then return "" end
    local parts = {}
    if goodCount > 0 then parts[#parts + 1] = "Good +" .. goodCount end
    if badCount > 0 then parts[#parts + 1] = "Bad +" .. badCount end
    return "SDD: " .. table.concat(parts, ", ")
end

-- Check if playerName is on the current character's friend list (by iterating C_FriendList)
local function IsPlayerFriend(playerName)
    if not playerName or type(playerName) ~= "string" or not C_FriendList or not C_FriendList.GetNumFriends then
        return false
    end
    local num = C_FriendList.GetNumFriends()
    local nameNorm = playerName:gsub("%s+", ""):lower()
    for i = 1, num do
        local info = C_FriendList.GetFriendInfoByIndex(i)
        if info and info.name then
            local friendNorm = info.name:gsub("%s+", ""):lower()
            if friendNorm == nameNorm then return true end
            -- Also match "Name-Realm" vs "Name"
            local friendShort = friendNorm:match("^([^%-]+)") or friendNorm
            local nameShort = nameNorm:match("^([^%-]+)") or nameNorm
            if friendShort == nameShort then return true end
        end
    end
    return false
end

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

    if subTreeID and subTreeID ~= 0 then
        local heroName, heroIcon
        
        -- Try with configID first
        if configID then
            local subTreeInfo = GetSubTreeInfoSafe(configID, subTreeID)
            if type(subTreeInfo) == "table" then
                heroName = subTreeInfo.name
                heroIcon = subTreeInfo.icon or subTreeInfo.iconFileID or subTreeInfo.iconID
            end
            
            if not heroIcon then
                local treeInfo = GetTreeInfoSafe(configID, subTreeID)
                if type(treeInfo) == "table" then
                    heroName = heroName or treeInfo.name
                    heroIcon = treeInfo.icon or treeInfo.iconFileID or treeInfo.iconID
                end
            end
        end
        
        -- Try without configID if we still don't have an icon
        if not heroIcon then
            local subTreeInfo = GetSubTreeInfoSafe(nil, subTreeID)
            if type(subTreeInfo) == "table" then
                heroName = heroName or subTreeInfo.name
                heroIcon = subTreeInfo.icon or subTreeInfo.iconFileID or subTreeInfo.iconID
            end
            
            if not heroIcon then
                local treeInfo = GetTreeInfoSafe(nil, subTreeID)
                if type(treeInfo) == "table" then
                    heroName = heroName or treeInfo.name
                    heroIcon = treeInfo.icon or treeInfo.iconFileID or treeInfo.iconID
                end
            end
        end
        
        -- Try GetHeroTalentSpecInfo as last resort
        if not heroIcon and type(C_ClassTalents.GetHeroTalentSpecInfo) == "function" then
            local heroInfo = SafeCall(C_ClassTalents.GetHeroTalentSpecInfo, subTreeID)
            if type(heroInfo) == "table" then
                heroName = heroName or heroInfo.name or heroInfo.specName
                heroIcon = heroInfo.icon or heroInfo.iconFileID or heroInfo.iconID
            end
        end
        
        return {
            heroTreeID = subTreeID,
            heroName = heroName,
            heroIcon = heroIcon,
        }
    end

    return nil
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
    else
        -- No backdrop support, skip
        return
    end
end

function Scoreboard:Create()
    if self.frame then
        self.frame:Show()
        return self.frame
    end
    
    -- Main frame - wider for better layout
    local frame = CreateFrame("Frame", "StormsDungeonDataScoreboard", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1120, 500)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1000)
    frame:SetScale(MPT.UIUtils:ComputeWindowScale())

    frame.TitleBg:SetHeight(30)
    frame.InsetBg:SetAlpha(0.35)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame.TitleBg, "TOPLEFT", 10, -5)
    title:SetText("Run Complete")
    frame.Title = title

    -- Close button: BasicFrameTemplateWithInset already provides one; only create if missing.
    if not frame.CloseButton and not frame.closeButton then
        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -5, -5)
    end
    
    -- Dungeon info section - improved layout
    local dungeonInfoBg = CreateFrame("Frame", nil, frame)
    dungeonInfoBg:SetSize(1100, 90)
    dungeonInfoBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -45)
    
    local backdropInfo = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    }
    SetBackdropCompat(dungeonInfoBg, backdropInfo, {0.1, 0.1, 0.1, 0.5}, {1, 1, 1, 0.3})
    
    -- Dungeon name - Line 1
    local dungeonName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dungeonName:SetPoint("TOPLEFT", dungeonInfoBg, "TOPLEFT", 25, -10)
    dungeonName:SetJustifyH("LEFT")
    frame.DungeonName = dungeonName
    
    -- Line 2: Keystone level and Duration (same line)
    local keystoneLevel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keystoneLevel:SetPoint("TOPLEFT", dungeonName, "BOTTOMLEFT", 0, -6)
    keystoneLevel:SetJustifyH("LEFT")
    frame.KeystoneLevel = keystoneLevel

    local duration = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    duration:SetPoint("LEFT", keystoneLevel, "RIGHT", 10, 0)
    duration:SetJustifyH("LEFT")
    frame.Duration = duration

    -- Line 3: Spec and Hero (same line, under keystone/duration)
    local specIconFrame = CreateFrame("Frame", nil, frame)
    specIconFrame:SetSize(24, 24)
    specIconFrame:SetPoint("TOPLEFT", keystoneLevel, "BOTTOMLEFT", 0, -8)

    local specIconText = specIconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specIconText:SetPoint("CENTER", specIconFrame, "CENTER", 0, 0)
    specIconText:SetJustifyH("CENTER")
    frame.SpecIconText = specIconText

    local heroIconFrame = CreateFrame("Frame", nil, frame)
    heroIconFrame:SetSize(80, 24)
    heroIconFrame:SetPoint("LEFT", specIconFrame, "RIGHT", 8, 0)

    local heroIconText = heroIconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heroIconText:SetPoint("CENTER", heroIconFrame, "CENTER", 0, 0)
    heroIconText:SetJustifyH("CENTER")
    heroIconText:SetTextColor(0.8, 0.8, 1, 1)  -- Light blue tint
    frame.HeroIconText = heroIconText
    
    -- Player stats table header (Rank first per user request)
    local headerY = -175
    local headers = {"Rank", "Player", "Damage", "DPS", "Healing", "HPS", "Interrupts", "Dispels", "Deaths", "Avoidable"}
    local columnWidths = {64, 270, 120, 90, 120, 90, 80, 75, 70, 100}  -- Rank first, then Player, then stats
    local playerNameWidth = 168  -- Room for name; buttons start after this (roleIcon 16 + gap 4 + this + 2 + 22+2+22+2+54 = 268)
    local headerX = 10
    
    -- Create header background
    local headerBg = frame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetHeight(18)
    headerBg:SetWidth(1100)
    headerBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, headerY - 2)
    headerBg:SetColorTexture(0.12, 0.12, 0.18, 0.45)
    
    for i, header in ipairs(headers) do
        local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetText(header)
        headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, headerY)
        headerText:SetTextColor(1, 0.84, 0, 1)
        headerText:SetWidth(columnWidths[i])
        if i == 2 then
            headerText:SetJustifyH("LEFT")
        else
            headerText:SetJustifyH("CENTER")
        end
        headerX = headerX + columnWidths[i]
    end
    
    -- Player stats rows
    frame.PlayerRows = {}
    frame.ColumnWidths = columnWidths
    
    for i = 1, 5 do
        local rowY = -205 - ((i - 1) * 28)
        
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(1100, 24)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, rowY)

        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(row)
        hover:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        hover:SetAlpha(0.14)
        
        -- Alternating row backgrounds
        if i % 2 == 0 then
            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints(row)
            rowBg:SetColorTexture(0.1, 0.1, 0.1, 0.2)
        end

        local mvpBg = row:CreateTexture(nil, "BORDER")
        mvpBg:SetAllPoints(row)
        mvpBg:SetColorTexture(1, 0.84, 0, 0.12)
        mvpBg:Hide()
        
        local roleIconSize = 16
        local roleIconGap = 4
        local roleIcon = row:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(roleIconSize, roleIconSize)
        roleIcon:SetPoint("LEFT", row, "LEFT", columnWidths[1], 0)
        roleIcon:Hide()
        -- Text fallback (T/H/D) when Blizzard role texture doesn't load
        local roleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleLabel:SetPoint("LEFT", row, "LEFT", columnWidths[1], 0)
        roleLabel:SetSize(roleIconSize, roleIconSize)
        roleLabel:SetJustifyH("CENTER")
        roleLabel:SetJustifyV("MIDDLE")
        roleLabel:SetFont(roleLabel:GetFont(), 11, "OUTLINE")
        roleLabel:Hide()
        
        local playerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerName:SetPoint("LEFT", row, "LEFT", columnWidths[1] + roleIconSize + roleIconGap, 0)
        playerName:SetWidth(playerNameWidth)
        playerName:SetJustifyH("LEFT")
        
        -- Thumbs up (good) and thumbs down (bad) for non-user players
        -- Positioned right after player name, before damage column
        local ratingUpBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        ratingUpBtn:SetSize(22, 20)
        ratingUpBtn:SetPoint("LEFT", row, "LEFT", columnWidths[1] + roleIconSize + roleIconGap + playerNameWidth + 4, 0)
        ratingUpBtn:SetText("|cff00ff00+|r")
        ratingUpBtn:SetScript("OnClick", function() end)  -- Set per-row in Show()
        ratingUpBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Rate good") end)
        ratingUpBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ratingUpBtn:Hide()
        
        local ratingDownBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        ratingDownBtn:SetSize(22, 20)
        ratingDownBtn:SetPoint("LEFT", ratingUpBtn, "RIGHT", 2, 0)
        ratingDownBtn:SetText("|cffff4444-|r")
        ratingDownBtn:SetScript("OnClick", function() end)
        ratingDownBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Rate bad") end)
        ratingDownBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ratingDownBtn:Hide()
        
        -- Add Friend button (for non-user players)
        local addFriendBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        addFriendBtn:SetSize(54, 20)
        addFriendBtn:SetPoint("LEFT", ratingDownBtn, "RIGHT", 2, 0)
        addFriendBtn:SetText("Friend")
        addFriendBtn:SetScript("OnClick", function() end)
        addFriendBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Add to friend list") end)
        addFriendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        addFriendBtn:Hide()
        
        local score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        score:SetPoint("LEFT", row, "LEFT", 0, 0)
        score:SetWidth(columnWidths[1])
        score:SetJustifyH("CENTER")

        local damage = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        damage:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2], 0)
        damage:SetWidth(columnWidths[3])
        damage:SetJustifyH("CENTER")
        
        local dps = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dps:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3], 0)
        dps:SetWidth(columnWidths[4])
        dps:SetJustifyH("CENTER")
        
        local healing = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        healing:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4], 0)
        healing:SetWidth(columnWidths[5])
        healing:SetJustifyH("CENTER")
        
        local hps = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hps:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4] + columnWidths[5], 0)
        hps:SetWidth(columnWidths[6])
        hps:SetJustifyH("CENTER")
        
        local interrupts = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        interrupts:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4] + columnWidths[5] + columnWidths[6], 0)
        interrupts:SetWidth(columnWidths[7])
        interrupts:SetJustifyH("CENTER")
        
        local dispels = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dispels:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4] + columnWidths[5] + columnWidths[6] + columnWidths[7], 0)
        dispels:SetWidth(columnWidths[8])
        dispels:SetJustifyH("CENTER")
        
        local deaths = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        deaths:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4] + columnWidths[5] + columnWidths[6] + columnWidths[7] + columnWidths[8], 0)
        deaths:SetWidth(columnWidths[9])
        deaths:SetJustifyH("CENTER")
        
        local avoidable = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        avoidable:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4] + columnWidths[5] + columnWidths[6] + columnWidths[7] + columnWidths[8] + columnWidths[9], 0)
        avoidable:SetWidth(columnWidths[10])
        avoidable:SetJustifyH("CENTER")
        
        table.insert(frame.PlayerRows, {
            frame = row,
            mvpBg = mvpBg,
            roleIcon = roleIcon,
            roleLabel = roleLabel,
            name = playerName,
            score = score,
            damage = damage,
            dps = dps,
            healing = healing,
            hps = hps,
            interrupts = interrupts,
            dispels = dispels,
            deaths = deaths,
            avoidable = avoidable,
            ratingUpBtn = ratingUpBtn,
            ratingDownBtn = ratingDownBtn,
            addFriendBtn = addFriendBtn,
        })
    end

    -- Footer: Totals + MVP
    local footerBg = CreateFrame("Frame", nil, frame)
    footerBg:SetSize(980, 80)
    footerBg:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 50)
    SetBackdropCompat(footerBg, backdropInfo, {0.08, 0.08, 0.08, 0.45}, {1, 1, 1, 0.25})

    local totalsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsTitle:SetPoint("TOPLEFT", footerBg, "TOPLEFT", 12, -10)
    totalsTitle:SetTextColor(1, 0.84, 0, 1)
    totalsTitle:SetText("Totals")

    local totalsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalsText:SetPoint("TOPLEFT", footerBg, "TOPLEFT", 12, -28)
    totalsText:SetText("Damage: --   DPS: --   Healing: --   HPS: --   Interrupts: --   Deaths: --")
    frame.TotalsText = totalsText

    local mvpTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mvpTitle:SetPoint("TOP", dungeonInfoBg, "TOP", 300, -10)
    mvpTitle:SetTextColor(1, 0.84, 0, 1)
    mvpTitle:SetText("MVP")
    mvpTitle:SetJustifyH("CENTER")

    local mvpName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mvpName:SetPoint("TOP", mvpTitle, "BOTTOM", 0, -8)
    mvpName:SetText("--")
    mvpName:SetJustifyH("CENTER")
    frame.MVPName = mvpName

    local mvpDetails = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mvpDetails:SetPoint("TOP", mvpName, "BOTTOM", 0, -4)
    mvpDetails:SetText("--")
    mvpDetails:SetJustifyH("CENTER")
    frame.MVPDetails = mvpDetails
    
    -- Buttons at bottom: Previous run | Run X of Y | Next run ... History
    local buttonWidth = 100
    local buttonHeight = 24
    local buttonSpacing = 12  -- Increased spacing between buttons
    
    local prevButton = MPT.UIUtils:CreateButton(frame, "Previous", buttonWidth, buttonHeight, function()
        if MPT.Scoreboard.runList and MPT.Scoreboard.currentRunIndex and MPT.Scoreboard.currentRunIndex < #MPT.Scoreboard.runList then
            local nextIdx = MPT.Scoreboard.currentRunIndex + 1
            MPT.Scoreboard:Show(MPT.Scoreboard.runList[nextIdx])
        end
    end)
    prevButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 15)
    frame.PrevButton = prevButton
    
    local runNavLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    runNavLabel:SetPoint("LEFT", prevButton, "RIGHT", buttonSpacing, 0)
    runNavLabel:SetTextColor(0.9, 0.9, 0.9, 1)
    runNavLabel:SetText("")
    frame.RunNavLabel = runNavLabel
    
    local nextButton = MPT.UIUtils:CreateButton(frame, "Next", buttonWidth, buttonHeight, function()
        if MPT.Scoreboard.runList and MPT.Scoreboard.currentRunIndex and MPT.Scoreboard.currentRunIndex > 1 then
            local nextIdx = MPT.Scoreboard.currentRunIndex - 1
            MPT.Scoreboard:Show(MPT.Scoreboard.runList[nextIdx])
        end
    end)
    nextButton:SetPoint("LEFT", runNavLabel, "RIGHT", buttonSpacing, 0)
    frame.NextButton = nextButton
    
    local reportButton = MPT.UIUtils:CreateButton(frame, "Report", buttonWidth, buttonHeight, function() end)
    reportButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -(15 + buttonWidth + buttonSpacing), 15)

    -- Custom report menu positioned directly above Report button (avoids Blizzard dropdown going to top-left)
    local reportMenu = CreateFrame("Frame", nil, frame)
    reportMenu:SetSize(150, 80)
    reportMenu:SetPoint("BOTTOMLEFT", reportButton, "TOPLEFT", 0, 2)
    reportMenu:SetFrameStrata("TOOLTIP")
    reportMenu:SetFrameLevel(frame:GetFrameLevel() + 50)
    local menuBackdrop = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    }
    SetBackdropCompat(reportMenu, menuBackdrop, {0.15, 0.15, 0.15, 0.95}, {1, 1, 1, 0.4})
    reportMenu:Hide()
    frame.ReportMenuFrame = reportMenu

    local menuTitle = reportMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menuTitle:SetPoint("TOP", reportMenu, "TOP", 0, -8)
    menuTitle:SetTextColor(1, 0.84, 0, 1)
    menuTitle:SetText("Report Run")

    -- Screen 1: mode selection (MVP Report / Summary Report)
    local mvpReportBtn = MPT.UIUtils:CreateButton(reportMenu, "MVP Report", 130, 22, function() end)
    mvpReportBtn:SetPoint("TOP", menuTitle, "BOTTOM", 0, -6)

    local summaryReportBtn = MPT.UIUtils:CreateButton(reportMenu, "Summary Report", 130, 22, function() end)
    summaryReportBtn:SetPoint("TOP", mvpReportBtn, "BOTTOM", 0, -4)

    -- Screen 2: channel selection (Party / Guild / Back)
    local channelLabel = reportMenu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("TOP", menuTitle, "BOTTOM", 0, -6)
    channelLabel:SetTextColor(0.8, 0.8, 1, 1)
    channelLabel:SetText("")
    channelLabel:Hide()

    local partyBtn = MPT.UIUtils:CreateButton(reportMenu, "Party", 130, 22, function() end)
    partyBtn:SetPoint("TOP", channelLabel, "BOTTOM", 0, -4)
    partyBtn:Hide()

    local guildBtn = MPT.UIUtils:CreateButton(reportMenu, "Guild", 130, 22, function() end)
    guildBtn:SetPoint("TOP", partyBtn, "BOTTOM", 0, -4)
    guildBtn:Hide()

    local backBtn = MPT.UIUtils:CreateButton(reportMenu, "< Back", 130, 22, function() end)
    backBtn:SetPoint("TOP", guildBtn, "BOTTOM", 0, -4)
    backBtn:Hide()

    -- Helpers to switch between the two screens
    local reportMenuMode = "none"

    local function showModeScreen()
        reportMenu:SetSize(150, 80)
        mvpReportBtn:Show()
        summaryReportBtn:Show()
        channelLabel:Hide()
        partyBtn:Hide()
        guildBtn:Hide()
        backBtn:Hide()
    end

    local function showChannelScreen(mode)
        reportMenuMode = mode
        channelLabel:SetText(mode == "summary" and "MVP Report" or "Summary Report")
        reportMenu:SetSize(150, 120)
        mvpReportBtn:Hide()
        summaryReportBtn:Hide()
        channelLabel:Show()
        partyBtn:Show()
        partyBtn:SetEnabled(IsInGroup() and not IsInRaid())
        guildBtn:Show()
        guildBtn:SetEnabled(IsInGuild())
        backBtn:Show()
    end

    mvpReportBtn:SetScript("OnClick", function() showChannelScreen("summary") end)
    summaryReportBtn:SetScript("OnClick", function() showChannelScreen("full") end)

    partyBtn:SetScript("OnClick", function()
        MPT.Scoreboard:ReportRunToChat("PARTY", reportMenuMode)
        reportMenu:Hide()
        showModeScreen()
    end)

    guildBtn:SetScript("OnClick", function()
        MPT.Scoreboard:ReportRunToChat("GUILD", reportMenuMode)
        reportMenu:Hide()
        showModeScreen()
    end)

    backBtn:SetScript("OnClick", function() showModeScreen() end)

    reportButton:SetScript("OnClick", function()
        if reportMenu:IsShown() then
            reportMenu:Hide()
            showModeScreen()
        else
            showModeScreen()
            reportMenu:Show()
        end
    end)

    local historyButton = MPT.UIUtils:CreateButton(frame, "History", buttonWidth, buttonHeight, function()
        frame:Hide()
        if MPT.HistoryViewer then
            MPT.HistoryViewer:Show()
        end
    end)
    historyButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 15)

    -- Auto-report checkbox
    local autoReportCheck = CreateFrame("CheckButton", "StormsDungeonDataAutoReportCheck", frame, "UICheckButtonTemplate")
    autoReportCheck:SetSize(24, 24)
    autoReportCheck:SetPoint("RIGHT", reportButton, "LEFT", -8, 0)
    autoReportCheck.text:ClearAllPoints()
    autoReportCheck.text:SetPoint("RIGHT", autoReportCheck, "LEFT", -2, 0)
    autoReportCheck.text:SetJustifyH("RIGHT")
    autoReportCheck.text:SetText("Auto-report to party")
    autoReportCheck.text:SetTextColor(0.9, 0.9, 0.9, 1)

    local function GetAutoReportSetting()
        if StormsDungeonDataDB and StormsDungeonDataDB.settings then
            return StormsDungeonDataDB.settings.autoReportToParty == true
        end
        return false
    end

    autoReportCheck:SetChecked(GetAutoReportSetting())
    autoReportCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if StormsDungeonDataDB then
            StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
            StormsDungeonDataDB.settings.autoReportToParty = checked
        end
    end)
    frame.AutoReportCheck = autoReportCheck

    self.frame = frame
    return frame
end

-- Build multi-line run report and send each line to the given chat channel (e.g. "PARTY", "GUILD").
-- mode = "summary" (default): header + highlights (MVP, top DMG/Healing/INT, least avoidable).
-- mode = "full": header + one row per player with full stats.
function Scoreboard:ReportRunToChat(channel, mode)
    if not channel or (channel ~= "PARTY" and channel ~= "GUILD") then return end
    if channel == "GUILD" and not IsInGuild() then return end
    local runRecord = self.runList and self.runList[self.currentRunIndex]
    if not runRecord then return end
    mode = mode or "summary"

    local dungeonName = runRecord.dungeonName or "Dungeon"
    local level = tonumber(runRecord.keystoneLevel) or 0
    local durationSec = tonumber(runRecord.duration) or 0
    local minutes = math.floor(durationSec / 60)
    local seconds = durationSec % 60
    local timeStr = string.format("%d:%02d", minutes, seconds)
    local mvpName = runRecord.mvpName or self:ComputeMVPName(runRecord) or ""

    -- Normalize player list (same as Show)
    local playerData = runRecord.players or {}
    if #playerData == 0 and runRecord.groupMembers and #runRecord.groupMembers > 0 then
        playerData = runRecord.groupMembers
    end
    if #playerData == 0 and runRecord.playerStats then
        playerData = {}
        for name, stats in pairs(runRecord.playerStats) do
            playerData[#playerData + 1] = { name = name, class = "WARRIOR", stats = stats }
        end
    end

    local function fmtNum(n)
        if not MPT or not MPT.Utils or not MPT.Utils.FormatNumber then
            return tostring(math.floor(tonumber(n) or 0))
        end
        return MPT.Utils:FormatNumber(math.floor(tonumber(n) or 0))
    end

    local function playerDisplayName(p, stats)
        if type(p.name) == "string" and p.name ~= "" then return p.name end
        if type(p.unitID) == "string" and p.unitID ~= "" then return p.unitID end
        if stats and type(stats.name) == "string" and stats.name ~= "" then return stats.name end
        return "Unknown"
    end

    -- Resolve stats table for a player entry
    local function resolveStats(p)
        local s = p.stats or {}
        if s.damage == nil and (p.damage ~= nil or p.healing ~= nil or p.interrupts ~= nil or p.dispels ~= nil) then
            s = p
        end
        return s
    end

    -- WoW chat uses | for escape codes; use || for a literal pipe
    local function escapePipes(s)
        return (s:gsub("|", "||"))
    end

    local lines = {}
    lines[#lines + 1] = "********StormsDungeonData Addon********"
    lines[#lines + 1] = string.format("%s +%d completed in %s", dungeonName, level, timeStr)

    if mode == "full" then
        -- Full scoreboard: one line per player
        lines[#lines + 1] = "Player | Dmg | DPS | Healing | HPS | INT | DISP | Deaths | AvoidDmg"
        for i = 1, math.min(5, #playerData) do
            local p = playerData[i]
            local s = resolveStats(p)
            local damage    = tonumber(s.damage) or 0
            local healing   = tonumber(s.healing) or 0
            local interrupts= tonumber(s.interrupts) or 0
            local dispelsCt = tonumber(s.dispels) or 0
            local deaths    = tonumber(s.deaths) or 0
            local avoid     = tonumber(s.avoidableDamageTaken) or 0
            local dps = tonumber(s.damagePerSecond) or (durationSec > 0 and damage > 0 and (damage / durationSec) or 0)
            local hps = tonumber(s.healingPerSecond) or (durationSec > 0 and healing > 0 and (healing / durationSec) or 0)
            local name = playerDisplayName(p, s)
            lines[#lines + 1] = string.format("%s | %s | %s | %s | %s | %d | %d | %d | %s",
                name, fmtNum(damage), fmtNum(dps), fmtNum(healing), fmtNum(hps),
                interrupts, dispelsCt, deaths, fmtNum(avoid))
        end
        if mvpName and mvpName ~= "" and runRecord.abandonReason ~= "abandon" then
            lines[#lines + 1] = "MVP: " .. mvpName
        end
    else
        -- Summary: MVP + top highlights
        if mvpName and mvpName ~= "" and runRecord.abandonReason ~= "abandon" then
            lines[#lines + 1] = "MVP: " .. mvpName
        end

        -- Find top damage, healing, interrupts; and player(s) with least avoidable damage
        local topDmgName, topDmgVal     = nil, -1
        local topHealName, topHealVal   = nil, -1
        local topIntVal                 = -1
        local topIntNames               = {}
        local topDispVal                = -1
        local topDispNames              = {}
        local minAvoidVal               = math.huge
        local minAvoidNames             = {}

        for i = 1, math.min(5, #playerData) do
            local p = playerData[i]
            local s = resolveStats(p)
            local name       = playerDisplayName(p, s)
            local damage     = tonumber(s.damage) or 0
            local healing    = tonumber(s.healing) or 0
            local interrupts = tonumber(s.interrupts) or 0
            local dispels    = tonumber(s.dispels) or 0
            local avoid      = tonumber(s.avoidableDamageTaken) or 0

            if damage > topDmgVal then
                topDmgVal  = damage
                topDmgName = name
            end
            if healing > topHealVal then
                topHealVal  = healing
                topHealName = name
            end
            if interrupts > topIntVal then
                topIntVal   = interrupts
                topIntNames = { name }
            elseif interrupts == topIntVal then
                topIntNames[#topIntNames + 1] = name
            end
            if dispels > topDispVal then
                topDispVal   = dispels
                topDispNames = { name }
            elseif dispels == topDispVal then
                topDispNames[#topDispNames + 1] = name
            end
            if avoid < minAvoidVal then
                minAvoidVal   = avoid
                minAvoidNames = { name }
            elseif avoid == minAvoidVal then
                minAvoidNames[#minAvoidNames + 1] = name
            end
        end

        if topDmgName then
            lines[#lines + 1] = "Top DMG: " .. topDmgName .. " (" .. fmtNum(topDmgVal) .. ")"
        end
        if topHealName then
            lines[#lines + 1] = "Top Healing: " .. topHealName .. " (" .. fmtNum(topHealVal) .. ")"
        end
        if #topIntNames > 0 then
            lines[#lines + 1] = "Top Interrupts: " .. table.concat(topIntNames, ", ") .. " (" .. tostring(topIntVal) .. ")"
        end
        if #topDispNames > 0 and topDispVal > 0 then
            lines[#lines + 1] = "Top Dispels: " .. table.concat(topDispNames, ", ") .. " (" .. tostring(topDispVal) .. ")"
        end
        if #minAvoidNames > 0 then
            local avoidStr = table.concat(minAvoidNames, ", ")
            if minAvoidVal ~= math.huge then
                avoidStr = avoidStr .. " (" .. fmtNum(minAvoidVal) .. ")"
            end
            lines[#lines + 1] = "Avoidable DMG: " .. avoidStr
        end
    end

    lines[#lines + 1] = "**********************************"

    for _, line in ipairs(lines) do
        SendChatMessage(escapePipes(line), channel)
    end
end

-- Compute MVP player name from run record using the same role-weighted scoring as the scoreboard display.
-- Used when saving the run so History can show "you were MVP" from stored data instead of recomputing.
function Scoreboard:ComputeMVPName(runRecord)
    if not runRecord or runRecord.abandonReason == "abandon" then
        return nil
    end

    local ranking = self:GetMVPRanking(runRecord)
    local top = ranking and ranking[1]
    if top and type(top.name) == "string" and top.name ~= "" then
        return top.name
    end

    return nil
end

-- Returns MVP ranking for debug: array of { name, role, damage, healing, interrupts, score, rank } sorted by rank (1 = MVP).
function Scoreboard:GetMVPRanking(runRecord)
    if not runRecord then return {} end
    local playerData = runRecord.players or {}
    if #playerData == 0 and runRecord.groupMembers and #runRecord.groupMembers > 0 then
        playerData = runRecord.groupMembers
    end
    if #playerData == 0 and runRecord.playerStats then
        playerData = {}
        for name, stats in pairs(runRecord.playerStats) do
            playerData[#playerData + 1] = { name = name, stats = stats }
        end
    end
    if not playerData or #playerData == 0 then return {} end

    local function SafeShare(v, t)
        v = tonumber(v) or 0
        t = tonumber(t) or 0
        return t > 0 and (v / t) or 0
    end
    local assignedRole, n = AssignRolesFromPlayerData(playerData)

    local totalDamage, totalHealing, totalInterrupts, totalDispels = 0, 0, 0, 0
    local totalAvoidableDamage = 0
    for i = 1, n do
        local p = playerData[i]
        local s = p.stats or (p.damage ~= nil or p.healing ~= nil or p.interrupts ~= nil) and p or {}
        totalDamage = totalDamage + (s.damage or p.damage or 0)
        totalHealing = totalHealing + (s.healing or p.healing or 0)
        totalInterrupts = totalInterrupts + (s.interrupts or p.interrupts or 0)
        totalDispels = totalDispels + (s.dispels or p.dispels or 0)
        totalAvoidableDamage = totalAvoidableDamage + (s.avoidableDamageTaken or p.avoidableDamageTaken or 0)
    end

    local rows = {}
    for i = 1, n do
        local p = playerData[i]
        local s = p.stats or (p.damage ~= nil or p.healing ~= nil or p.interrupts ~= nil) and p or {}
        local role = assignedRole[i] or p.role or (s and s.role) or "DAMAGER"
        local dmgShare = SafeShare(s.damage or p.damage, totalDamage)
        local healShare = SafeShare(s.healing or p.healing, totalHealing)
        local intShare = SafeShare(s.interrupts or p.interrupts, totalInterrupts)
        local dispelShare = SafeShare(s.dispels or p.dispels, totalDispels)
        local deaths = s.deaths or p.deaths or 0
        local avoidableShare = SafeShare(s.avoidableDamageTaken or p.avoidableDamageTaken, totalAvoidableDamage)
        local specID = (s and s.specID) or p.specID
        local class  = (s and s.class)  or p.class
        local score = MVPScoreBalancedRoles(role, dmgShare, healShare, intShare, deaths, avoidableShare, specID, class, dispelShare)
        local name = type(p.name) == "string" and p.name ~= "" and p.name
            or (s and type(s.name) == "string" and s.name ~= "" and s.name)
            or type(p.unitID) == "string" and p.unitID ~= "" and p.unitID
            or ("Player" .. i)
        rows[#rows + 1] = {
            name = name,
            role = role,
            damage = s.damage or p.damage or 0,
            healing = s.healing or p.healing or 0,
            interrupts = s.interrupts or p.interrupts or 0,
            dispels = s.dispels or p.dispels or 0,
            score = score,
        }
    end
    table.sort(rows, function(a, b) return a.score > b.score end)
    for r = 1, #rows do
        rows[r].rank = r
    end
    return rows
end

-- Build list of all runs sorted newest-first; return { list, indexOfRun } or { list, nil } if runRecord not in list
function Scoreboard:GetRunListAndIndex(runRecord)
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    local list = {}
    for _, r in ipairs(runs) do
        if not r.deleted then
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    if not runRecord or #list == 0 then
        return list, nil
    end
    local ts = runRecord.timestamp
    local dur = runRecord.duration or 0
    local name = runRecord.dungeonName
    local id = runRecord.dungeonID or runRecord.dungeonId
    for i, r in ipairs(list) do
        if (r.timestamp == ts or (ts and r.timestamp and r.timestamp == ts))
            and (r.duration == dur or (r.duration or 0) == dur)
            and (r.dungeonName == name or r.dungeonID == id or (id and r.dungeonID == id)) then
            return list, i
        end
    end
    return list, nil
end

function Scoreboard:Show(runRecord)
    if not runRecord then
        print("|cff00ffaa[StormsDungeonData]|r No run record provided")
        return
    end
    
    local frame = self:Create()
    local runList, idx = self:GetRunListAndIndex(runRecord)
    self.runList = runList
    self.currentRunIndex = idx or 1
    
    -- Populate run info
    frame.DungeonName:SetText(runRecord.dungeonName)
    frame.KeystoneLevel:SetText(string.format("Level: %d", runRecord.keystoneLevel))

    if not runRecord.specIcon then
        local spec = GetPlayerSpecInfoSafe()
        if spec and spec.specIcon then
            runRecord.specIcon = spec.specIcon
        end
    end

    if not runRecord.heroIcon then
        local hero = GetHeroTalentInfoSafe()
        if hero and hero.heroIcon and hero.heroIcon ~= 0 then
            runRecord.heroIcon = hero.heroIcon
        end
    end

    if frame.SpecIconText then
        if runRecord.specIcon and runRecord.specIcon ~= 0 then
            frame.SpecIconText:SetText("|T" .. tostring(runRecord.specIcon) .. ":16:16:0:0|t")
        else
            frame.SpecIconText:SetText("")
        end
    end

    if frame.HeroIconText then
        if runRecord.heroName and runRecord.heroName ~= "" then
            frame.HeroIconText:SetText(runRecord.heroName)
        else
            frame.HeroIconText:SetText("")
        end
    end

    local durationSec = tonumber(runRecord.duration) or (runRecord.endTime and runRecord.startTime and (runRecord.endTime - runRecord.startTime)) or 0
    local minutes = math.floor(durationSec / 60)
    local seconds = durationSec % 60
    local durationStr = string.format("%02d:%02d", minutes, seconds)
    if runRecord.abandonReason == "abandon" then
        durationStr = durationStr .. " Abandon"
    end
    frame.Duration:SetText(durationStr)
    
    -- Populate player stats
    -- Support both real combat format (players array) and test format (playerStats dictionary)
    local playerData = runRecord.players or {}
    if not playerData or #playerData == 0 then
        if runRecord.groupMembers and #runRecord.groupMembers > 0 then
            playerData = runRecord.groupMembers
        end
    end
    if not playerData or #playerData == 0 then
        -- Use playerStats dictionary from test mode
        playerData = {}
        if runRecord.playerStats then
            local index = 1
            for name, stats in pairs(runRecord.playerStats) do
                playerData[index] = {
                    name = name,
                    class = "WARRIOR",  -- Default class for test data
                    stats = stats
                }
                index = index + 1
            end
        end
    end
    
    local function GetPersonalBestStats(dungeonID, dungeonName, playerName)
        local best = {damage = 0, healing = 0, interrupts = 0, dispels = 0}
        local db = StormsDungeonDataDB
        if not db or not db.runs then
            return best
        end

        -- Get all user's character names
        local userCharacters = {}
        if MPT.Database and MPT.Database.GetAllCharacters then
            local chars = MPT.Database:GetAllCharacters()
            for _, char in ipairs(chars) do
                local fullName = char.name .. "-" .. char.realm
                userCharacters[fullName] = true
                userCharacters[char.name] = true
            end
        end

        for _, run in ipairs(db.runs) do
            local sameDungeon = false
            if dungeonID and run.dungeonID and run.dungeonID ~= 0 then
                sameDungeon = run.dungeonID == dungeonID
            elseif dungeonName then
                sameDungeon = run.dungeonName == dungeonName
            end

            if sameDungeon then
                if run.playerStats then
                    for pName, pstats in pairs(run.playerStats) do
                        -- Check if this player is one of the user's characters
                        local shortName = pName:match("^([^%-]+)") or pName
                        if userCharacters[pName] or userCharacters[shortName] then
                            best.damage = math.max(best.damage, pstats.damage or 0)
                            best.healing = math.max(best.healing, pstats.healing or 0)
                            best.interrupts = math.max(best.interrupts, pstats.interrupts or 0)
                            best.dispels = math.max(best.dispels, pstats.dispels or 0)
                        end
                    end
                elseif run.players then
                    for _, p in ipairs(run.players) do
                        local shortName = p.name and (p.name:match("^([^%-]+)") or p.name)
                        if shortName and (userCharacters[p.name] or userCharacters[shortName]) then
                            best.damage = math.max(best.damage, p.damage or 0)
                            best.healing = math.max(best.healing, p.healing or 0)
                            best.interrupts = math.max(best.interrupts, p.interrupts or 0)
                            best.dispels = math.max(best.dispels, p.dispels or 0)
                        end
                    end
                end
            end
        end

        return best
    end

    local totalsDamage, totalsHealing, totalsInterrupts, totalsDeaths, totalsAvoidable = 0, 0, 0, 0, 0
    local mvpIndex = nil
    local mvpScore = nil
    local mvpStats = nil
    local mvpPlayer = nil

    local function SafeShare(value, total)
        value = tonumber(value) or 0
        total = tonumber(total) or 0
        if total <= 0 then
            return 0
        end
        return value / total
    end

    local mvpCandidates = {}

    local function SafeText(value, fallback)
        if value == nil then
            return fallback or ""
        end
        if type(value) == "string" then
            return value
        end
        return tostring(value)
    end

    local function NormalizeNameLookupKeys(name)
        if type(name) ~= "string" then
            return nil, nil
        end
        local normalized = name:gsub("%s+", "")
        if normalized == "" then
            return nil, nil
        end
        local fullKey = normalized:lower()
        local shortKey = (normalized:match("^([^%-]+)") or normalized):lower()
        return fullKey, shortKey
    end

    local function ResolvePlayerScoreDelta(player, stats, fallbackName, isUserCharacter)
        local delta = tonumber((player and player.scoreDelta) or (stats and stats.scoreDelta))
        if (not delta or delta == 0) and runRecord and type(runRecord.playerScoreDeltas) == "table" then
            local nameCandidates = {
                fallbackName,
                player and player.name,
                player and player.unitID,
                stats and stats.name,
            }
            for _, candidate in ipairs(nameCandidates) do
                local fullKey, shortKey = NormalizeNameLookupKeys(candidate)
                delta = (fullKey and runRecord.playerScoreDeltas[fullKey]) or (shortKey and runRecord.playerScoreDeltas[shortKey])
                if delta and delta ~= 0 then
                    break
                end
            end
        end
        if (not delta or delta == 0) and isUserCharacter and runRecord then
            local oldScore = tonumber(runRecord.oldDungeonScore)
            local newScore = tonumber(runRecord.newDungeonScore)
            if oldScore and newScore then
                delta = newScore - oldScore
            end
        end
        if not delta then
            return nil
        end
        local rounded = delta > 0 and math.floor(delta + 0.5) or math.ceil(delta - 0.5)
        if rounded == 0 then
            return nil
        end
        return rounded
    end

    local function FormatScoreDeltaTag(delta)
        if not delta then
            return nil
        end
        if delta > 0 then
            return "|cff00ff00(+" .. tostring(delta) .. ")|r"
        end
        return "|cffff4444(" .. tostring(delta) .. ")|r"
    end

    local assignedRole, maxPlayers = AssignRolesFromPlayerData(playerData)

    -- Compute totals and MVP score per player, then sort by score (MVP first)
    local totalsDamage, totalsHealing, totalsInterrupts, totalsAvoidable = 0, 0, 0, 0
    local totalsDispels = 0
    local totalsDPSFromPlayers, totalsHPSFromPlayers = 0, 0
    local hasAnyStoredDPS, hasAnyStoredHPS = false, false
    local candidateList = {}
    for i = 1, maxPlayers do
        local player = playerData[i]
        local stats = player.stats or {}
        if stats.damage == nil and (player.damage ~= nil or player.healing ~= nil or player.interrupts ~= nil) then
            stats = player
        end
        if (stats.damage == nil) and MPT.CombatLog and MPT.CombatLog.GetPlayerStats and player.name then
            stats = MPT.CombatLog:GetPlayerStats(player.name) or {}
        end
        totalsDamage = totalsDamage + (stats.damage or 0)
        totalsHealing = totalsHealing + (stats.healing or 0)
        totalsInterrupts = totalsInterrupts + (stats.interrupts or 0)
        totalsDispels = totalsDispels + (stats.dispels or 0)
        totalsAvoidable = totalsAvoidable + (stats.avoidableDamageTaken or 0)
        local role = assignedRole[i] or "DAMAGER"
        local dmgShare = SafeShare(stats.damage or 0, totalsDamage)
        local healShare = SafeShare(stats.healing or 0, totalsHealing)
        local intShare = SafeShare(stats.interrupts or 0, totalsInterrupts)
        local dispelShare = SafeShare(stats.dispels or 0, totalsDispels)
        local deaths = stats.deaths or 0
        local avoidableShare = SafeShare(stats.avoidableDamageTaken or 0, totalsAvoidable)
        local specID = stats.specID or player.specID
        local class  = stats.class  or player.class
        local score = MVPScoreBalancedRoles(role, dmgShare, healShare, intShare, deaths, avoidableShare, specID, class, dispelShare)
        candidateList[#candidateList + 1] = { player = player, stats = stats, role = role, score = score, specID = specID, class = class }
    end
    -- Recompute shares and scores with final totals (we summed incrementally above, so totals are correct after loop)
    totalsDamage = 0
    totalsHealing = 0
    totalsInterrupts = 0
    totalsDispels = 0
    totalsAvoidable = 0
    for _, c in ipairs(candidateList) do
        totalsDamage = totalsDamage + (c.stats.damage or 0)
        totalsHealing = totalsHealing + (c.stats.healing or 0)
        totalsInterrupts = totalsInterrupts + (c.stats.interrupts or 0)
        totalsDispels = totalsDispels + (c.stats.dispels or 0)
        totalsAvoidable = totalsAvoidable + (c.stats.avoidableDamageTaken or 0)
    end
    for _, c in ipairs(candidateList) do
        c.dmgShare = SafeShare(c.stats.damage or 0, totalsDamage)
        c.healShare = SafeShare(c.stats.healing or 0, totalsHealing)
        c.intShare = SafeShare(c.stats.interrupts or 0, totalsInterrupts)
        c.dispelShare = SafeShare(c.stats.dispels or 0, totalsDispels)
        c.deaths = c.stats.deaths or 0
        c.avoidableShare = SafeShare(c.stats.avoidableDamageTaken or 0, totalsAvoidable)
        c.score = MVPScoreBalancedRoles(c.role, c.dmgShare, c.healShare, c.intShare, c.deaths, c.avoidableShare, c.specID, c.class, c.dispelShare)
    end
    table.sort(candidateList, function(a, b) return (a.score or 0) > (b.score or 0) end)

    for i = 1, 5 do
        local entry = candidateList[i]
        local row = frame.PlayerRows[i]
        if not row then break end
        if not entry then
            row.name:SetText("")
            row.damage:SetText("")
            if row.dps then row.dps:SetText("") end
            row.healing:SetText("")
            if row.hps then row.hps:SetText("") end
            row.interrupts:SetText("")
            if row.dispels then row.dispels:SetText("") end
            if row.deaths then row.deaths:SetText("") end
            if row.avoidable then row.avoidable:SetText("") end
            if row.score then row.score:SetText("") end
            if row.roleIcon then row.roleIcon:Hide() end
            if row.ratingUpBtn then row.ratingUpBtn:Hide() end
            if row.ratingDownBtn then row.ratingDownBtn:Hide() end
            if row.addFriendBtn then row.addFriendBtn:Hide() end
            row.frame:Hide()
        else
            local player = entry.player
            local stats = entry.stats
            row.frame:Show()

            -- Color player name by class (use text color directly for reliability)
            local nameText = nil
            if type(player.name) == "string" and player.name ~= "" then
                nameText = player.name
            elseif type(player.unitID) == "string" and player.unitID ~= "" then
                nameText = player.unitID
            elseif type(stats.name) == "string" and stats.name ~= "" then
                nameText = stats.name
            end
            local baseNameText = SafeText(nameText, "Unknown")
            row.name:SetText(baseNameText)
            do
                local classToken = player.class
                local color
                if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
                    color = RAID_CLASS_COLORS[classToken]
                    row.name:SetTextColor(color.r, color.g, color.b)
                elseif classToken and MPT.Utils and MPT.Utils.GetClassColor and MPT.UIUtils and MPT.UIUtils.HexToRGB then
                    local r, g, b = MPT.UIUtils:HexToRGB(MPT.Utils:GetClassColor(classToken))
                    row.name:SetTextColor(r, g, b)
                else
                    row.name:SetTextColor(1, 0.82, 0, 1) -- default WoW-ish gold
                end
            end
            
            -- Role: use this candidate's role (rows are sorted by MVP score).
            local role = entry.role or "DAMAGER"
            if row.roleLabel then
                row.roleLabel:Hide()
            end
            if row.roleIcon then
                local useAtlas = false
                if C_Texture and C_Texture.GetAtlasInfo then
                    local roleKey = (role == "TANK" and "tank") or (role == "HEALER" and "healer") or "damager"
                    local candidates = {
                        "roleicon-" .. roleKey,
                        "RoleIcon-" .. roleKey:gsub("^%l", string.upper),
                        "groupfinder-icon-role-" .. roleKey,
                        "LFG-RoleIcon-" .. roleKey:gsub("^%l", string.upper),
                    }
                    for _, atlasName in ipairs(candidates) do
                        if C_Texture.GetAtlasInfo(atlasName) then
                            row.roleIcon:SetAtlas(atlasName)
                            row.roleIcon:Show()
                            useAtlas = true
                            break
                        end
                    end
                end
                if not useAtlas then
                    local path = "Interface\\LFGFrame\\UI-LFG-Icon-PortraitRoles"
                    local l, r, t, b
                    if role == "TANK" then
                        l, r, t, b = 0, 0.28125, 0.328125, 0.625
                    elseif role == "HEALER" then
                        l, r, t, b = 0.3125, 0.59375, 0, 0.296875
                    else
                        l, r, t, b = 0.3125, 0.59375, 0.328125, 0.625
                    end
                    row.roleIcon:SetTexture(path)
                    row.roleIcon:SetTexCoord(l, r, t, b)
                    row.roleIcon:SetDrawLayer("OVERLAY", 0)
                    row.roleIcon:Show()
                end
            end
            
            -- Check if this player is one of the user's characters
            local isUserCharacter = false
            if player.name then
                if MPT.Database and MPT.Database.GetAllCharacters then
                    local chars = MPT.Database:GetAllCharacters()
                    for _, char in ipairs(chars) do
                        local fullName = char.name .. "-" .. char.realm
                        local shortName = player.name:match("^([^%-]+)") or player.name
                        local shortCharName = char.name:match("^([^%-]+)") or char.name
                        if player.name == fullName or shortName == shortCharName then
                            isUserCharacter = true
                            break
                        end
                    end
                end
            end

            local scoreDelta = ResolvePlayerScoreDelta(player, stats, nameText, isUserCharacter)
            local scoreDeltaTag = FormatScoreDeltaTag(scoreDelta)
            if scoreDeltaTag then
                row.name:SetText(baseNameText .. " " .. scoreDeltaTag)
            else
                row.name:SetText(baseNameText)
            end
            
            local personalBest = GetPersonalBestStats(runRecord.dungeonID, runRecord.dungeonName, player.name)
            local damageValue = stats.damage or 0
            local healingValue = stats.healing or 0
            local interruptsValue = stats.interrupts or 0
            local dispelsValue = stats.dispels or 0
            local deathsValue = stats.deaths or 0
            local avoidableDamageTakenValue = stats.avoidableDamageTaken or 0
            local durationSec = (runRecord and runRecord.duration) and tonumber(runRecord.duration) or 0
            if durationSec <= 0 and runRecord and runRecord.duration then
                durationSec = tonumber(runRecord.duration) or 0
            end
            local dpsValue = stats.damagePerSecond or (durationSec > 0 and math.floor((damageValue or 0) / durationSec)) or 0
            local hpsValue = stats.healingPerSecond or (durationSec > 0 and math.floor((healingValue or 0) / durationSec)) or 0

            local damageText = MPT.Utils:FormatNumber(damageValue)
            local healingText = MPT.Utils:FormatNumber(healingValue)
            local dpsText = MPT.Utils:FormatNumber(dpsValue)
            local hpsText = MPT.Utils:FormatNumber(hpsValue)
            local interruptsText = tostring(interruptsValue)
            local dispelsText = tostring(dispelsValue)
            local deathsText = tostring(deathsValue)
            local avoidableText = MPT.Utils:FormatNumber(avoidableDamageTakenValue)

            if dpsValue and dpsValue > 0 then
                totalsDPSFromPlayers = totalsDPSFromPlayers + dpsValue
                hasAnyStoredDPS = true
            end
            if hpsValue and hpsValue > 0 then
                totalsHPSFromPlayers = totalsHPSFromPlayers + hpsValue
                hasAnyStoredHPS = true
            end

            -- Only highlight in orange if this is the user's character AND they achieved a personal best
            if isUserCharacter then
                if damageValue > 0 and damageValue >= personalBest.damage then
                    damageText = "|cffff8000" .. damageText .. "|r"
                end
                if healingValue > 0 and healingValue >= personalBest.healing then
                    healingText = "|cffff8000" .. healingText .. "|r"
                end
                if interruptsValue > 0 and interruptsValue >= personalBest.interrupts then
                    interruptsText = "|cffff8000" .. interruptsText .. "|r"
                end
                if dispelsValue > 0 and dispelsValue >= personalBest.dispels then
                    dispelsText = "|cffff8000" .. dispelsText .. "|r"
                end
            end

            row.damage:SetText(SafeText(damageText, "0"))
            if row.dps then row.dps:SetText(SafeText(dpsText, "0")) end
            row.healing:SetText(SafeText(healingText, "0"))
            if row.hps then row.hps:SetText(SafeText(hpsText, "0")) end
            row.interrupts:SetText(SafeText(interruptsText, "0"))
            if row.dispels then row.dispels:SetText(SafeText(dispelsText, "0")) end
            if row.deaths then row.deaths:SetText(SafeText(deathsText, "0")) end
            if row.avoidable then row.avoidable:SetText(SafeText(avoidableText, "0")) end
            
            -- Show rating and add-friend buttons only for non-user players
            local playerNameForActions = nameText or player.name
            if isUserCharacter then
                if row.ratingUpBtn then row.ratingUpBtn:Hide() end
                if row.ratingDownBtn then row.ratingDownBtn:Hide() end
                if row.addFriendBtn then row.addFriendBtn:Hide() end
            else
                -- Per-run rating: read and write rating scoped to this specific run's ID
                local runID = runRecord and runRecord.id
                local rating = (MPT.Database and MPT.Database.GetRunPlayerRating and playerNameForActions and runID) and MPT.Database:GetRunPlayerRating(runID, playerNameForActions) or nil
                local isFriend = IsPlayerFriend(playerNameForActions)
                
                if row.ratingUpBtn then
                    row.ratingUpBtn:Show()
                    -- Selected: white brackets + green plus. Unselected: dim green plus.
                    row.ratingUpBtn:SetText(rating == "good" and "|cffffffff[|r|cff00ff00+|r|cffffffff]|r" or "|cff88ff88+|r")
                    row.ratingUpBtn:SetScript("OnClick", function()
                        if MPT.Database and playerNameForActions and runID then
                            -- Toggle: clicking + again clears the rating for this run
                            local current = MPT.Database:GetRunPlayerRating(runID, playerNameForActions)
                            local newRating = (current == "good") and nil or "good"
                            MPT.Database:SetRunPlayerRating(runID, playerNameForActions, newRating)
                            if IsPlayerFriend(playerNameForActions) and C_FriendList and C_FriendList.SetFriendNotes then
                                C_FriendList.SetFriendNotes(playerNameForActions, GetRatingNoteForFriend(playerNameForActions))
                            end
                            Scoreboard:Show(runRecord)
                        end
                    end)
                end
                if row.ratingDownBtn then
                    row.ratingDownBtn:Show()
                    -- Selected: white brackets + red minus. Unselected: dim red minus.
                    row.ratingDownBtn:SetText(rating == "bad" and "|cffffffff[|r|cffff4444-|r|cffffffff]|r" or "|cffff8888-|r")
                    row.ratingDownBtn:SetScript("OnClick", function()
                        if MPT.Database and playerNameForActions and runID then
                            -- Toggle: clicking - again clears the rating for this run
                            local current = MPT.Database:GetRunPlayerRating(runID, playerNameForActions)
                            local newRating = (current == "bad") and nil or "bad"
                            MPT.Database:SetRunPlayerRating(runID, playerNameForActions, newRating)
                            if IsPlayerFriend(playerNameForActions) and C_FriendList and C_FriendList.SetFriendNotes then
                                C_FriendList.SetFriendNotes(playerNameForActions, GetRatingNoteForFriend(playerNameForActions))
                            end
                            Scoreboard:Show(runRecord)
                        end
                    end)
                end
                if row.addFriendBtn then
                    row.addFriendBtn:Show()
                    if isFriend then
                        row.addFriendBtn:SetText("Friends")
                        row.addFriendBtn:Disable()
                        row.addFriendBtn:SetScript("OnClick", function() end)
                        row.addFriendBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Already on friend list") end)
                    else
                        row.addFriendBtn:SetText("Add")
                        row.addFriendBtn:Enable()
                        row.addFriendBtn:SetScript("OnClick", function()
                            if C_FriendList and C_FriendList.AddFriend and playerNameForActions then
                                local note = GetRatingNoteForFriend(playerNameForActions)
                                C_FriendList.AddFriend(playerNameForActions, note)
                                row.addFriendBtn:SetText("Friends")
                                row.addFriendBtn:Disable()
                                row.addFriendBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Already on friend list") end)
                            end
                        end)
                        row.addFriendBtn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Add to friend list") end)
                    end
                    row.addFriendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
            end

            totalsDamage = totalsDamage + (stats.damage or 0)
            totalsHealing = totalsHealing + (stats.healing or 0)
            totalsInterrupts = totalsInterrupts + (stats.interrupts or 0)
            totalsDispels = totalsDispels + (stats.dispels or 0)
            totalsDeaths = totalsDeaths + (stats.deaths or 0)
            totalsAvoidable = totalsAvoidable + (stats.avoidableDamageTaken or 0)

            if row.score then
                row.score:SetText(tostring(i))
            end

            mvpCandidates[i] = {
                player = entry.player,
                stats = entry.stats,
                role = entry.role,
            }

            row.frame:Show()
        end
    end

    -- MVP must always match the ranked list: rank #1 is MVP.
    -- candidateList is already sorted by balanced_roles score (highest first), and mvpCandidates
    -- mirrors the displayed rows in that same order.
    if runRecord.abandonReason ~= "abandon" then
        local top = mvpCandidates[1]
        if top and top.stats then
            mvpIndex = 1
            mvpStats = top.stats
            mvpPlayer = top.player
            mvpScore = candidateList[1] and candidateList[1].score or nil
        end
    end

    -- Clear MVP highlights
    for i = 1, 5 do
        if frame.PlayerRows[i] and frame.PlayerRows[i].mvpBg then
            frame.PlayerRows[i].mvpBg:Hide()
        end
    end

    -- Check if we have any combat data at all
    local noCombatData = (totalsDamage == 0 and totalsHealing == 0 and totalsInterrupts == 0)
    
    -- Total deaths: use run record (already max of API and combat-log sum when saved), else sum from player rows
    local totalDeaths = (runRecord.deathCount ~= nil and runRecord.deathCount >= 0) and runRecord.deathCount or totalsDeaths
    totalDeaths = math.max(totalDeaths, totalsDeaths)

    local durationSec = (runRecord and runRecord.duration) and tonumber(runRecord.duration) or 0
    local totalDPS = hasAnyStoredDPS and totalsDPSFromPlayers or ((durationSec > 0 and totalsDamage > 0) and math.floor(totalsDamage / durationSec) or 0)
    local totalHPS = hasAnyStoredHPS and totalsHPSFromPlayers or ((durationSec > 0 and totalsHealing > 0) and math.floor(totalsHealing / durationSec) or 0)
    if noCombatData then
        frame.TotalsText:SetText("|cffff4444No combat data available - see chat for details|r")
    else
        frame.TotalsText:SetText(string.format(
            "Damage: |cffff8000%s|r   DPS: |cffff8000%s|r   Healing: |cff00ff00%s|r   HPS: |cff00ff00%s|r   Interrupts: |cff0088ff%d|r   Dispels: |cff00ffff%d|r   Deaths: |cffff4444%d|r",
            MPT.Utils:FormatNumber(totalsDamage),
            MPT.Utils:FormatNumber(totalDPS),
            MPT.Utils:FormatNumber(totalsHealing),
            MPT.Utils:FormatNumber(totalHPS),
            totalsInterrupts,
            totalsDispels,
            totalDeaths
        ))
    end

    if mvpIndex and frame.PlayerRows[mvpIndex] and frame.PlayerRows[mvpIndex].mvpBg then
        frame.PlayerRows[mvpIndex].mvpBg:Show()
    end

    if runRecord.abandonReason == "abandon" then
        frame.MVPName:SetText("--")
        frame.MVPName:SetTextColor(0.6, 0.6, 0.6, 1)
        frame.MVPDetails:SetText("")
    elseif mvpPlayer and frame.MVPName and frame.MVPDetails then
        -- MVP name (class-colored)
        local mvpName = nil
        if type(mvpPlayer.name) == "string" and mvpPlayer.name ~= "" then
            mvpName = mvpPlayer.name
        elseif type(mvpPlayer.unitID) == "string" and mvpPlayer.unitID ~= "" then
            mvpName = mvpPlayer.unitID
        elseif mvpStats and type(mvpStats.name) == "string" and mvpStats.name ~= "" then
            mvpName = mvpStats.name
        end
        frame.MVPName:SetText(SafeText(mvpName, "--"))
        if runRecord and mvpName and mvpName ~= "" then
            runRecord.mvpName = mvpName
        end
        local classToken = mvpPlayer.class
        if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] then
            local c = RAID_CLASS_COLORS[classToken]
            frame.MVPName:SetTextColor(c.r, c.g, c.b)
        elseif classToken and MPT.Utils and MPT.Utils.GetClassColor and MPT.UIUtils and MPT.UIUtils.HexToRGB then
            local r, g, b = MPT.UIUtils:HexToRGB(MPT.Utils:GetClassColor(classToken))
            frame.MVPName:SetTextColor(r, g, b)
        else
            frame.MVPName:SetTextColor(1, 0.82, 0, 1)
        end

        -- MVP section only shows the name, no stats
        frame.MVPDetails:SetText("")
    end

    -- Hide unused rows
    local numRows = #playerData
    for i = numRows + 1, 5 do
        if frame.PlayerRows[i] then
            if frame.PlayerRows[i].roleIcon then
                frame.PlayerRows[i].roleIcon:Hide()
            end
            if frame.PlayerRows[i].roleLabel then
                frame.PlayerRows[i].roleLabel:Hide()
            end
            frame.PlayerRows[i].frame:Hide()
        end
    end
    
    -- Update run navigation: label and button states
    local n = #(self.runList or {})
    if frame.RunNavLabel then
        if n > 0 and self.currentRunIndex then
            frame.RunNavLabel:SetText(string.format("Run %d of %d", self.currentRunIndex, n))
        else
            frame.RunNavLabel:SetText("")
        end
    end
    if frame.PrevButton then
        if n > 1 and self.currentRunIndex and self.currentRunIndex < n then
            frame.PrevButton:Enable()
        else
            frame.PrevButton:Disable()
        end
    end
    if frame.NextButton then
        if n > 1 and self.currentRunIndex and self.currentRunIndex > 1 then
            frame.NextButton:Enable()
        else
            frame.NextButton:Disable()
        end
    end
    
    frame:Show()

    -- Auto-report MVP report to party when the scoreboard first appears for a new run.
    -- The designated reporter is elected via hidden addon messages among clients
    -- that have auto-report enabled. If auto-report is off, this is skipped entirely.
    local runKey = runRecord and (
        tostring(runRecord.timestamp or "") ..
        "_" .. tostring(runRecord.mapID or "") ..
        "_" .. tostring(runRecord.keystoneLevel or "")
    )

    if runKey and runKey ~= self.lastAutoReportedRunKey then
        self.lastAutoReportedRunKey = runKey
        if IsInGroup() and not IsInRaid() then
            if MPT.ReporterElection and MPT.ReporterElection:IsDesignatedReporter() then
                self:ReportRunToChat("PARTY", "summary")
            end
        end
    end
end

function Scoreboard:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

