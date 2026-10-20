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
    [250] = { 0.67, 0.33, 0.40, 0.00 }, -- Blood (tank)
    [251] = { 0.92, 0.08, 0.55, 0.00 }, -- Frost (DPS)
    [252] = { 0.92, 0.08, 0.55, 0.00 }, -- Unholy (DPS)
    -- Demon Hunter (no dispel)
    [577]  = { 0.90, 0.10, 0.55, 0.00 }, -- Havoc (DPS)      – 15s Disrupt
    [581]  = { 0.80, 0.20, 0.40, 0.00 }, -- Vengeance (tank)
    [1480] = { 0.90, 0.10, 0.55, 0.00 }, -- Devourer (DPS)   – interrupt CD assumed 15s
    -- Druid
    [102] = { 0.90, 0.10, 0.35, 0.05 }, -- Balance (DPS)      – Solar Beam 60s; Remove Corruption
    [103] = { 0.90, 0.10, 0.55, 0.05 }, -- Feral (DPS)        – Skull Bash 15s; Remove Corruption
    [104] = { 0.80, 0.20, 0.40, 0.10 }, -- Guardian (tank)    – Remove Corruption
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
    [268] = { 0.85, 0.15, 0.40, 0.00 }, -- Brewmaster (tank)   – no dispel
    [269] = { 0.90, 0.10, 0.55, 0.00 }, -- Windwalker (DPS)    – no dispel
    [270] = { 0.28, 0.72, 0.00, 0.08 }, -- Mistweaver (heal)   – Detox
    -- Paladin
    [65] = { 0.28, 0.72, 0.00, 0.08 }, -- Holy (heal)         – Cleanse
    [66] = { 0.80, 0.20, 0.35, 0.10 }, -- Protection (tank)   – Avenger's Shield / Rebuke
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
    [73] = { 0.80, 0.20, 0.40, 0.00 }, -- Protection
}

-- Per-class fallback weights when specID is unavailable. { dmg, heal, int, disp }
-- dmg + heal sums to 1.0 to match spec table fairness constraint.
local CLASS_MVP_WEIGHTS = {
    DEATHKNIGHT  = { TANK = { 0.82, 0.18, 0.40, 0.00 }, HEALER = nil,                   DAMAGER = { 0.92, 0.08, 0.55, 0.00 } },
    DEMONHUNTER  = { TANK = { 0.80, 0.20, 0.40, 0.00 }, HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    DRUID        = { TANK = { 0.80, 0.20, 0.40, 0.10 }, HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.45, 0.05 } },
    EVOKER       = { TANK = nil,                         HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.65, 0.00 } },
    HUNTER       = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.45, 0.00 } },
    MAGE         = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.45, 0.05 } },
    MONK         = { TANK = { 0.80, 0.20, 0.40, 0.00 }, HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    PALADIN      = { TANK = { 0.80, 0.20, 0.35, 0.10 }, HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.55, 0.05 } },
    PRIEST       = { TANK = nil,                         HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.10, 0.35, 0.05 } },
    ROGUE        = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    SHAMAN       = { TANK = nil,                         HEALER = { 0.28, 0.72, 0.00, 0.08 }, DAMAGER = { 0.90, 0.15, 0.60, 0.05 } },
    WARLOCK      = { TANK = nil,                         HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
    WARRIOR      = { TANK = { 0.80, 0.20, 0.40, 0.00 }, HEALER = nil,                   DAMAGER = { 0.90, 0.10, 0.55, 0.00 } },
}

-- Role-only fallback weights (no class/spec data available). { dmg, heal, int, disp }
-- dmg + heal sums to 1.0 to match spec table fairness constraint.
local ROLE_MVP_WEIGHTS = {
    HEALER  = { 0.28, 0.72, 0.00, 0.08 },
    TANK    = { 0.80, 0.20, 0.40, 0.05 },
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

    -- Penalties: each death reduces score by 8%, avoidable damage scales score down proportionally
    local avoidableMultiplier = math.max(0.70, 1 - (avoidableShare * 0.25))
    local deathMultiplier = (1 - 0.08) ^ deaths
    return math.max(0, baseScore * avoidableMultiplier * deathMultiplier)
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

-- Build a short friend-list note from our star average (e.g. "SDD: 4.3/5 stars (7 runs)")
local function GetRatingNoteForFriend(playerName)
    if not MPT.Database or not playerName then return "" end
    local average, count = MPT.Database:GetPlayerRatingSummary(playerName)
    if not average then return "" end
    return string.format("SDD: %.1f/5 stars (%d %s)", average, count, count == 1 and "run" or "runs")
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

-- ---------------------------------------------------------------------------
-- Party Cards layout
-- ---------------------------------------------------------------------------

local T = function() return MPT.Theme end

local CARD_W, MVP_W, CARD_GAP = 204, 240, 12
local CARD_H, MVP_H = 352, 376
local STAR_SIZE, STAR_GAP = 18, 3
local FRIEND_BTN_W = 60
local WINDOW_W = 20 + MVP_W + (CARD_W * 4) + (CARD_GAP * 4) + 20
local WINDOW_H = 540
local CARDS_BOTTOM = 64

local ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

local function RoleMarkup(role)
    local atlas = ROLE_ATLAS[role or "DAMAGER"] or ROLE_ATLAS.DAMAGER
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return "|A:" .. atlas .. ":12:12|a "
    end
    return ""
end

local function SetCardGradient(tex, r, g, b)
    tex:SetTexture(MPT.Theme.TEX_WHITE)
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.30))
        if ok then return end
    end
    tex:SetColorTexture(r, g, b, 0.15)
end

-- One stat line inside a card: label left, value right, optional bar below.
local function AddCardStat(card, labelText, hasBar, y)
    local Theme = T()
    local label = Theme:Text(card, 11, "body", "muted")
    label:SetPoint("TOPLEFT", card.StatsBlock, "TOPLEFT", 0, -y)
    label:SetText(labelText)

    local value = Theme:Text(card, 12, "body", "text", "RIGHT")
    value:SetPoint("TOPRIGHT", card.StatsBlock, "TOPRIGHT", 0, -y)
    value:SetWidth(130)

    local bar
    if hasBar then
        bar = Theme:Bar(card, 3)
        bar:SetPoint("TOPLEFT", card.StatsBlock, "TOPLEFT", 0, -(y + 15))
        bar:SetPoint("TOPRIGHT", card.StatsBlock, "TOPRIGHT", 0, -(y + 15))
        return value, bar, y + 24
    end
    return value, nil, y + 17
end

local function CreateCard(parent, index)
    local Theme = T()
    local isLead = (index == 1)
    local w, h = isLead and MVP_W or CARD_W, isLead and MVP_H or CARD_H
    local avatarSize = isLead and 56 or 44

    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(w, h)
    card.isLead = isLead
    Theme:Panel(card, "surface", "line")
    card.Glow = Theme:Glow(card, "gold", 16)

    card.Band = card:CreateTexture(nil, "BACKGROUND", nil, -6)
    -- Inset past the rounded corners so the square band never pokes out
    card.Band:SetPoint("TOPLEFT", card, "TOPLEFT", 4, -4)
    card.Band:SetPoint("TOPRIGHT", card, "TOPRIGHT", -4, -4)
    card.Band:SetHeight(isLead and 128 or 110)

    -- MVP tag (lead card only)
    local tag = CreateFrame("Frame", nil, card)
    tag:SetSize(40, 16)
    tag:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -10)
    Theme:Panel(tag, "gold", "gold")
    local tagText = Theme:Text(tag, 10, "head", "bg", "CENTER")
    tagText:SetPoint("CENTER", tag, "CENTER", 0, 0)
    tagText:SetText("MVP")
    tag:Hide()
    card.MVPTag = tag

    card.RankText = Theme:Text(card, 12, "head", "muted", "RIGHT")
    card.RankText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12, -11)

    -- Avatar: class-colored ring with a round spec icon
    local mask = card:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(avatarSize, avatarSize)
    mask:SetPoint("TOP", card, "TOP", 0, -18)

    local ringMask = card:CreateMaskTexture()
    ringMask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    ringMask:SetSize(avatarSize + 6, avatarSize + 6)
    ringMask:SetPoint("CENTER", mask, "CENTER", 0, 0)

    card.Ring = card:CreateTexture(nil, "ARTWORK", nil, 1)
    card.Ring:SetAllPoints(ringMask)
    card.Ring:SetColorTexture(1, 1, 1, 1)
    card.Ring:AddMaskTexture(ringMask)

    card.Avatar = card:CreateTexture(nil, "ARTWORK", nil, 2)
    card.Avatar:SetAllPoints(mask)
    card.Avatar:AddMaskTexture(mask)

    card.Name = Theme:Text(card, isLead and 16 or 14, "head", "text", "CENTER")
    card.Name:SetPoint("TOP", mask, "BOTTOM", 0, -8)
    card.Name:SetWidth(w - 16)

    card.Spec = Theme:Text(card, 11, "body", "muted", "CENTER")
    card.Spec:SetPoint("TOP", card.Name, "BOTTOM", 0, -3)
    card.Spec:SetWidth(w - 16)

    card.Hero = Theme:Text(card, 10, "body", "muted", "CENTER")
    card.Hero:SetPoint("TOP", card.Spec, "BOTTOM", 0, -2)
    card.Hero:SetWidth(w - 16)
    card.Hero:SetHeight(12)

    card.Score = Theme:Text(card, isLead and 34 or 26, "head", "text", "RIGHT")
    card.Score:SetPoint("TOPRIGHT", card.Hero, "BOTTOM", 4, -6)
    card.ScoreLabel = Theme:Text(card, 11, "body", "muted")
    card.ScoreLabel:SetPoint("BOTTOMLEFT", card.Score, "BOTTOMRIGHT", 5, 4)
    card.ScoreLabel:SetText("score")

    card.Why = Theme:Text(card, 11, "body", "gold", "CENTER")
    card.Why:SetPoint("TOP", card.Score, "BOTTOM", 18, -4)
    card.Why:SetWidth(w - 16)

    -- Actions (bottom): 1-5 star rating for this run, then add friend
    local maxStars = MPT.Database.RATING_MAX_STARS
    card.StarRow = CreateFrame("Frame", nil, card)
    card.StarRow:SetSize(maxStars * STAR_SIZE + (maxStars - 1) * STAR_GAP, STAR_SIZE)
    card.StarRow:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 10)
    card.Stars = {}
    for i = 1, maxStars do
        local star = CreateFrame("Button", nil, card.StarRow)
        star:SetSize(STAR_SIZE, STAR_SIZE)
        star:SetPoint("LEFT", card.StarRow, "LEFT", (i - 1) * (STAR_SIZE + STAR_GAP), 0)
        star.Icon = star:CreateTexture(nil, "ARTWORK")
        star.Icon:SetAllPoints(star)
        star.Icon:SetTexture(Theme.TEX_STAR)
        star.value = i
        card.Stars[i] = star
    end
    card.FriendBtn = Theme:Button(card, "Friend", FRIEND_BTN_W, 22, "ghost")
    card.FriendBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
    card.YouText = Theme:Text(card, 11, "body", "muted", "CENTER")
    card.YouText:SetPoint("BOTTOM", card, "BOTTOM", 0, 14)
    card.YouText:SetText("You")

    -- Stats block sits above the actions
    card.StatsBlock = CreateFrame("Frame", nil, card)
    card.StatsBlock:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 38)
    card.StatsBlock:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -12, 38)
    card.StatsBlock:SetHeight(174)

    local y = 0
    card.dps, card.DPSBar, y = AddCardStat(card, "DPS", true, y)
    card.hps, card.HPSBar, y = AddCardStat(card, "HPS", true, y)
    card.interrupts, card.IntBar, y = AddCardStat(card, "Interrupts", true, y)
    card.dispels, card.DispBar, y = AddCardStat(card, "Dispels", true, y)
    card.avoidable, card.AvoidBar, y = AddCardStat(card, "Avoidable dmg", true, y)
    card.deaths, _, y = AddCardStat(card, "Deaths", false, y)
    card.AvoidBar:SetColor(MPT.Theme:Unpack("bad"))
    card.StatsBlock:SetHeight(y)

    return card
end

local function CreateReportMenu(frame, reportButton)
    local Theme = T()
    local menu = CreateFrame("Frame", nil, frame)
    menu:SetSize(150, 84)
    menu:SetPoint("BOTTOMLEFT", reportButton, "TOPLEFT", 0, 6)
    menu:SetFrameLevel(frame:GetFrameLevel() + 50)
    menu:EnableMouse(true)
    Theme:Panel(menu, "surface", "line")
    menu:Hide()

    local title = Theme:Text(menu, 11, "body", "muted", "CENTER")
    title:SetPoint("TOP", menu, "TOP", 0, -8)
    title:SetText("Report run")

    local mvpBtn = Theme:Button(menu, "MVP report", 130, 22)
    mvpBtn:SetPoint("TOP", title, "BOTTOM", 0, -6)
    local summaryBtn = Theme:Button(menu, "Summary report", 130, 22)
    summaryBtn:SetPoint("TOP", mvpBtn, "BOTTOM", 0, -4)

    local partyBtn = Theme:Button(menu, "Party", 130, 22)
    partyBtn:SetPoint("TOP", title, "BOTTOM", 0, -6)
    local guildBtn = Theme:Button(menu, "Guild", 130, 22)
    guildBtn:SetPoint("TOP", partyBtn, "BOTTOM", 0, -4)
    local backBtn = Theme:Button(menu, "Back", 130, 22, "ghost")
    backBtn:SetPoint("TOP", guildBtn, "BOTTOM", 0, -4)

    local mode = "summary"
    local function ShowModeScreen()
        menu:SetHeight(84)
        title:SetText("Report run")
        mvpBtn:Show(); summaryBtn:Show()
        partyBtn:Hide(); guildBtn:Hide(); backBtn:Hide()
    end
    local function ShowChannelScreen(newMode)
        mode = newMode
        menu:SetHeight(110)
        title:SetText(newMode == "summary" and "MVP report to..." or "Summary report to...")
        mvpBtn:Hide(); summaryBtn:Hide()
        partyBtn:Show(); guildBtn:Show(); backBtn:Show()
        partyBtn:SetEnabled(IsInGroup() and not IsInRaid())
        guildBtn:SetEnabled(IsInGuild())
    end

    -- "summary" mode is the MVP-highlights report; "full" is one line per player.
    mvpBtn:SetScript("OnClick", function() ShowChannelScreen("summary") end)
    summaryBtn:SetScript("OnClick", function() ShowChannelScreen("full") end)
    partyBtn:SetScript("OnClick", function()
        MPT.Scoreboard:ReportRunToChat("PARTY", mode)
        menu:Hide(); ShowModeScreen()
    end)
    guildBtn:SetScript("OnClick", function()
        MPT.Scoreboard:ReportRunToChat("GUILD", mode)
        menu:Hide(); ShowModeScreen()
    end)
    backBtn:SetScript("OnClick", ShowModeScreen)

    reportButton:SetScript("OnClick", function()
        if menu:IsShown() then
            menu:Hide()
        else
            ShowModeScreen()
            menu:Show()
        end
    end)
    return menu
end

function Scoreboard:Create()
    if self.frame then
        return self.frame
    end
    local Theme = T()

    local frame = Theme:Window("StormsDungeonDataScoreboard", WINDOW_W, WINDOW_H, "", "FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetScale(MPT.UIUtils:ComputeWindowScale())
    frame:Hide()

    -- Header: eyebrow, dungeon name, key chip, time, result, rating gain
    local eyebrow = Theme:Text(frame, 11, "body", "muted")
    eyebrow:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -14)
    frame.Eyebrow = eyebrow

    local specIconText = Theme:Text(frame, 11, "body", "muted")
    specIconText:SetPoint("LEFT", eyebrow, "RIGHT", 8, 0)
    frame.SpecIconText = specIconText
    local heroIconText = Theme:Text(frame, 11, "body", "muted")
    heroIconText:SetPoint("LEFT", specIconText, "RIGHT", 4, 0)
    frame.HeroIconText = heroIconText

    frame.Title:ClearAllPoints()
    frame.Title:SetPoint("TOPLEFT", eyebrow, "BOTTOMLEFT", 0, -4)
    Theme:SetFont(frame.Title, 22, "head")
    frame.DungeonName = frame.Title

    local keyChip = CreateFrame("Frame", nil, frame)
    keyChip:SetSize(44, 22)
    keyChip:SetPoint("LEFT", frame.Title, "RIGHT", 12, 0)
    Theme:Panel(keyChip, "raised", "line")
    frame.KeystoneLevel = Theme:Text(keyChip, 14, "head", "text", "CENTER")
    frame.KeystoneLevel:SetPoint("CENTER", keyChip, "CENTER", 0, 0)
    frame.KeyChip = keyChip

    frame.Duration = Theme:Text(frame, 13, "body", "muted")
    frame.Duration:SetPoint("LEFT", keyChip, "RIGHT", 12, 0)
    frame.Result = Theme:Text(frame, 13, "body", "good")
    frame.Result:SetPoint("LEFT", frame.Duration, "RIGHT", 8, 0)

    frame.RatingGain = Theme:Text(frame, 16, "head", "good", "RIGHT")
    frame.RatingGain:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -44, -26)

    -- Timer bar: duration against the dungeon's limit
    frame.TimerBar = Theme:Bar(frame, 3)
    frame.TimerBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -66)
    frame.TimerBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -66)

    -- Cards
    local cardsArea = CreateFrame("Frame", nil, frame)
    cardsArea:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, CARDS_BOTTOM)
    cardsArea:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -80)
    frame.CardsArea = cardsArea

    frame.PlayerRows = {}
    local x = 0
    for i = 1, 5 do
        local card = CreateCard(cardsArea, i)
        card.anchorX = x
        card:SetPoint("BOTTOMLEFT", cardsArea, "BOTTOMLEFT", x, 0)
        x = x + card:GetWidth() + CARD_GAP
        card.frame = card
        frame.PlayerRows[i] = card
    end

    -- Footer
    frame.PrevButton = Theme:Button(frame, "<", 28, 24, "default", function()
        if Scoreboard.runList and Scoreboard.currentRunIndex and Scoreboard.currentRunIndex < #Scoreboard.runList then
            Scoreboard:Show(Scoreboard.runList[Scoreboard.currentRunIndex + 1])
        end
    end)
    frame.PrevButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
    frame.PrevButton:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText("Older run"); GameTooltip:Show() end)
    frame.PrevButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.RunNavLabel = Theme:Text(frame, 12, "body", "muted", "CENTER")
    frame.RunNavLabel:SetPoint("LEFT", frame.PrevButton, "RIGHT", 8, 0)
    frame.RunNavLabel:SetWidth(96)

    frame.NextButton = Theme:Button(frame, ">", 28, 24, "default", function()
        if Scoreboard.runList and Scoreboard.currentRunIndex and Scoreboard.currentRunIndex > 1 then
            Scoreboard:Show(Scoreboard.runList[Scoreboard.currentRunIndex - 1])
        end
    end)
    frame.NextButton:SetPoint("LEFT", frame.RunNavLabel, "RIGHT", 8, 0)
    frame.NextButton:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText("Newer run"); GameTooltip:Show() end)
    frame.NextButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.TotalsText = Theme:Text(frame, 11, "body", "muted")
    frame.TotalsText:SetPoint("LEFT", frame.NextButton, "RIGHT", 16, 0)
    frame.TotalsText:SetWidth(420)

    local historyButton = Theme:Button(frame, "History", 90, 24, "primary", function()
        frame:Hide()
        if MPT.HistoryViewer then
            MPT.HistoryViewer:Show()
        end
    end)
    historyButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)

    local reportButton = Theme:Button(frame, "Report", 90, 24)
    reportButton:SetPoint("RIGHT", historyButton, "LEFT", -8, 0)
    frame.ReportMenuFrame = CreateReportMenu(frame, reportButton)

    local autoReport = Theme:Toggle(frame, "Auto-report to party",
        function() return Theme:GetSetting("autoReportToParty", false) == true end,
        function(v) Theme:SetSetting("autoReportToParty", v) end,
        "Post the MVP summary to party chat when a key ends. Only one SDD user in the group posts.")
    autoReport:SetWidth(160)
    autoReport:SetPoint("RIGHT", reportButton, "LEFT", -16, 0)
    frame.AutoReportCheck = autoReport

    frame:HookScript("OnHide", function()
        if frame.ReportMenuFrame then frame.ReportMenuFrame:Hide() end
    end)

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

local function ShortNameForCard(name)
    return (type(name) == "string" and name:match("^([^%-]+)")) or name or "Unknown"
end

-- Collects every user character name (full and short) once per Show call.
local function BuildUserCharacterSet()
    local set = {}
    if MPT.Database and MPT.Database.GetAllCharacters then
        for _, char in ipairs(MPT.Database:GetAllCharacters() or {}) do
            if char.name then
                set[char.name] = true
                set[char.name:match("^([^%-]+)") or char.name] = true
                if char.realm then
                    set[char.name .. "-" .. char.realm] = true
                end
            end
        end
    end
    return set
end

local function IsUserName(userSet, name)
    if type(name) ~= "string" or name == "" then
        return false
    end
    return userSet[name] or userSet[name:match("^([^%-]+)") or name] or false
end

local function GetPersonalBestStats(runRecord, userSet)
    local best = {damage = 0, healing = 0, interrupts = 0, dispels = 0}
    local db = StormsDungeonDataDB
    if not db or not db.runs then
        return best
    end
    local dungeonID, dungeonName = runRecord.dungeonID, runRecord.dungeonName
    local function Consider(name, s)
        if IsUserName(userSet, name) then
            best.damage = math.max(best.damage, s.damage or 0)
            best.healing = math.max(best.healing, s.healing or 0)
            best.interrupts = math.max(best.interrupts, s.interrupts or 0)
            best.dispels = math.max(best.dispels, s.dispels or 0)
        end
    end
    for _, run in ipairs(db.runs) do
        local sameDungeon
        if dungeonID and run.dungeonID and run.dungeonID ~= 0 then
            sameDungeon = run.dungeonID == dungeonID
        else
            sameDungeon = dungeonName and run.dungeonName == dungeonName
        end
        if sameDungeon and not run.deleted then
            if run.playerStats then
                for pName, pstats in pairs(run.playerStats) do
                    Consider(pName, pstats)
                end
            elseif run.players then
                for _, p in ipairs(run.players) do
                    Consider(p.name, p)
                end
            end
        end
    end
    return best
end

local function NormalizeNameLookupKeys(name)
    if type(name) ~= "string" then
        return nil, nil
    end
    local normalized = name:gsub("%s+", "")
    if normalized == "" then
        return nil, nil
    end
    return normalized:lower(), (normalized:match("^([^%-]+)") or normalized):lower()
end

local function ResolvePlayerScoreDelta(runRecord, player, stats, fallbackName, isUserCharacter)
    local delta = tonumber((player and player.scoreDelta) or (stats and stats.scoreDelta))
    if (not delta or delta == 0) and type(runRecord.playerScoreDeltas) == "table" then
        for _, candidate in ipairs({fallbackName, player and player.name, player and player.unitID, stats and stats.name}) do
            local fullKey, shortKey = NormalizeNameLookupKeys(candidate)
            delta = (fullKey and runRecord.playerScoreDeltas[fullKey]) or (shortKey and runRecord.playerScoreDeltas[shortKey])
            if delta and delta ~= 0 then
                break
            end
        end
    end
    if (not delta or delta == 0) and isUserCharacter then
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
        return MPT.Theme:Colorize("+" .. tostring(delta), "good")
    end
    return MPT.Theme:Colorize(tostring(delta), "bad")
end

local function ResolveDisplayName(player, stats)
    if type(player.name) == "string" and player.name ~= "" then
        return player.name
    elseif type(player.unitID) == "string" and player.unitID ~= "" then
        return player.unitID
    elseif type(stats.name) == "string" and stats.name ~= "" then
        return stats.name
    end
    return "Unknown"
end

-- Turns a run record into ordered card entries (MVP first) plus group totals.
local function BuildCandidates(runRecord)
    local playerData = runRecord.players or {}
    if #playerData == 0 and runRecord.groupMembers and #runRecord.groupMembers > 0 then
        playerData = runRecord.groupMembers
    end
    if #playerData == 0 then
        playerData = {}
        for name, stats in pairs(runRecord.playerStats or {}) do
            playerData[#playerData + 1] = {name = name, class = "WARRIOR", stats = stats}
        end
    end

    local assignedRole, maxPlayers = AssignRolesFromPlayerData(playerData)
    local candidates = {}
    for i = 1, maxPlayers do
        local player = playerData[i]
        local stats = player.stats or {}
        if stats.damage == nil and (player.damage ~= nil or player.healing ~= nil or player.interrupts ~= nil) then
            stats = player
        end
        if stats.damage == nil and MPT.CombatLog and MPT.CombatLog.GetPlayerStats and player.name then
            stats = MPT.CombatLog:GetPlayerStats(player.name) or {}
        end
        candidates[#candidates + 1] = {
            player = player,
            stats = stats,
            role = assignedRole[i] or "DAMAGER",
            specID = stats.specID or player.specID,
            class = stats.class or player.class,
        }
    end

    local totals = {damage = 0, healing = 0, interrupts = 0, dispels = 0, avoidable = 0, deaths = 0}
    for _, c in ipairs(candidates) do
        totals.damage = totals.damage + (c.stats.damage or 0)
        totals.healing = totals.healing + (c.stats.healing or 0)
        totals.interrupts = totals.interrupts + (c.stats.interrupts or 0)
        totals.dispels = totals.dispels + (c.stats.dispels or 0)
        totals.avoidable = totals.avoidable + (c.stats.avoidableDamageTaken or 0)
        totals.deaths = totals.deaths + (c.stats.deaths or 0)
    end

    local function Share(v, t)
        v, t = tonumber(v) or 0, tonumber(t) or 0
        return t > 0 and (v / t) or 0
    end
    for _, c in ipairs(candidates) do
        local s = c.stats
        c.score = MVPScoreBalancedRoles(c.role,
            Share(s.damage, totals.damage), Share(s.healing, totals.healing), Share(s.interrupts, totals.interrupts),
            s.deaths or 0, Share(s.avoidableDamageTaken, totals.avoidable), c.specID, c.class, Share(s.dispels, totals.dispels))
    end
    table.sort(candidates, function(a, b) return (a.score or 0) > (b.score or 0) end)
    return candidates, totals, #playerData
end

-- Short reasons the MVP won, e.g. "Top damage · 14 kicks · No deaths".
local function BuildMVPReasons(candidates)
    local top = candidates[1]
    if not top then return "" end
    local s = top.stats
    local maxDmg, maxHeal, maxInt, minAvoid = 0, 0, 0, math.huge
    for _, c in ipairs(candidates) do
        maxDmg = math.max(maxDmg, c.stats.damage or 0)
        maxHeal = math.max(maxHeal, c.stats.healing or 0)
        maxInt = math.max(maxInt, c.stats.interrupts or 0)
        minAvoid = math.min(minAvoid, c.stats.avoidableDamageTaken or 0)
    end
    local reasons = {}
    if (s.damage or 0) > 0 and (s.damage or 0) >= maxDmg then reasons[#reasons + 1] = "Top damage" end
    if (s.healing or 0) > 0 and (s.healing or 0) >= maxHeal then reasons[#reasons + 1] = "Top healing" end
    if (s.interrupts or 0) > 0 then
        reasons[#reasons + 1] = ((s.interrupts or 0) >= maxInt and "Most kicks" or (tostring(s.interrupts) .. " kicks"))
    end
    if (s.deaths or 0) == 0 then reasons[#reasons + 1] = "No deaths" end
    if #candidates > 1 and (s.avoidableDamageTaken or 0) <= minAvoid then reasons[#reasons + 1] = "Least avoidable" end
    while #reasons > 3 do table.remove(reasons) end
    return table.concat(reasons, " · ")
end

local RATING_WHISPER_WINDOW = 3 * 60 * 60  -- only whisper about runs that finished in the last 3 hours

-- Lights stars 1..lit in gold and dims the rest.
local function PaintStars(card, lit)
    local Theme = MPT.Theme
    for i, star in ipairs(card.Stars) do
        if i <= lit then
            star.Icon:SetVertexColor(Theme:Unpack("gold"))
        else
            star.Icon:SetVertexColor(Theme:Unpack("muted", 0.3))
        end
    end
end

-- Whisper targets need "Name-Realm" with no spaces; unit tokens can't be whispered.
local function WhisperTarget(playerName)
    if type(playerName) ~= "string" or playerName == "Unknown" then return nil end
    if playerName:match("^party%d") or playerName == "player" then return nil end
    return (playerName:gsub("%s+", ""))
end

local function SendWhisper(message, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not send then return false end
    return (pcall(send, message, "WHISPER", nil, target))
end

-- Tells the player they got 5 stars, once per run, and only while the run is recent.
local function WhisperFiveStarRating(runRecord, playerName)
    local db = MPT.Database
    local target = WhisperTarget(playerName)
    if not target or db:WasRatingWhisperSent(runRecord.id, playerName) then return end
    if time() - (runRecord.timestamp or 0) > RATING_WHISPER_WINDOW then return end

    local keyText = runRecord.dungeonName or "the dungeon"
    if runRecord.keystoneLevel then
        keyText = keyText .. " +" .. tostring(runRecord.keystoneLevel)
    end
    local message = string.format("You were rated 5 stars for that run (%s) on Storm's Dungeon Data. Thanks for the group!", keyText)
    if SendWhisper(message, target) then
        db:MarkRatingWhisperSent(runRecord.id, playerName)
    else
        print("|cff00ffaa[StormsDungeonData]|r Couldn't whisper " .. target .. " about their 5-star rating.")
    end
end

local function RateRunPlayer(runRecord, playerName, stars)
    local db = MPT.Database
    if not (db and playerName and runRecord.id) then return end
    -- Clicking the current rating again clears it for this run
    local current = db:GetRunPlayerRating(runRecord.id, playerName)
    local newStars = (current ~= stars) and stars or nil
    db:SetRunPlayerRating(runRecord.id, playerName, newStars)
    if newStars == db.RATING_MAX_STARS then
        WhisperFiveStarRating(runRecord, playerName)
    end
    if IsPlayerFriend(playerName) and C_FriendList and C_FriendList.SetFriendNotes then
        C_FriendList.SetFriendNotes(playerName, GetRatingNoteForFriend(playerName))
    end
    Scoreboard:Show(runRecord)
end

local function WireRatingButtons(card, runRecord, playerName)
    local db = MPT.Database
    local rating = (playerName and runRecord.id) and db:GetRunPlayerRating(runRecord.id, playerName) or 0
    PaintStars(card, rating)

    for _, star in ipairs(card.Stars) do
        local value = star.value
        star:SetScript("OnClick", function() RateRunPlayer(runRecord, playerName, value) end)
        star:SetScript("OnEnter", function(b)
            PaintStars(card, value)
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:SetText(string.format("Rate %d %s for this run", value, value == 1 and "star" or "stars"))
            if value == rating then
                GameTooltip:AddLine("Click again to clear", MPT.Theme:Unpack("muted"))
            elseif value == db.RATING_MAX_STARS and not db:WasRatingWhisperSent(runRecord.id, playerName) then
                GameTooltip:AddLine("Whispers " .. ShortNameForCard(playerName) .. " to let them know", MPT.Theme:Unpack("muted"))
            end
            GameTooltip:Show()
        end)
        star:SetScript("OnLeave", function()
            PaintStars(card, rating)
            GameTooltip:Hide()
        end)
    end

    local friendBtn = card.FriendBtn
    friendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if IsPlayerFriend(playerName) then
        friendBtn:SetText("Friends")
        friendBtn:Disable()
        friendBtn:SetScript("OnClick", nil)
        friendBtn:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText("Already on friend list"); GameTooltip:Show() end)
    else
        friendBtn:SetText("Friend")
        friendBtn:Enable()
        friendBtn:SetScript("OnEnter", function(b) GameTooltip:SetOwner(b, "ANCHOR_TOP"); GameTooltip:SetText("Add to friend list"); GameTooltip:Show() end)
        friendBtn:SetScript("OnClick", function()
            if C_FriendList and C_FriendList.AddFriend and playerName then
                C_FriendList.AddFriend(playerName, GetRatingNoteForFriend(playerName))
                friendBtn:SetText("Friends")
                friendBtn:Disable()
            end
        end)
    end
end

local function HighlightIfBest(text, value, best, isUser)
    if isUser and value > 0 and value >= best then
        return MPT.Theme:Colorize(text, "pb")
    end
    return text
end

-- Fills one card. Returns the scoreDelta for the user's own card (or nil).
local function PopulateCard(card, entry, rank, ctx)
    local Theme = MPT.Theme
    local player, stats = entry.player, entry.stats
    local nameText = ResolveDisplayName(player, stats)
    local isUser = IsUserName(ctx.userSet, player.name)

    local r, g, b = Theme:ClassColor(entry.class)
    SetCardGradient(card.Band, r, g, b)
    card.Ring:SetVertexColor(r, g, b, 1)
    local spec = Theme:SpecInfo(entry.specID)
    card.Avatar:SetTexture((spec and spec.icon) or Theme:ClassIcon(entry.class))
    card.Avatar:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local scoreDelta = ResolvePlayerScoreDelta(ctx.runRecord, player, stats, nameText, isUser)
    local deltaTag = FormatScoreDeltaTag(scoreDelta)
    card.Name:SetText(deltaTag and (ShortNameForCard(nameText) .. " " .. deltaTag) or ShortNameForCard(nameText))
    card.Name:SetTextColor(r, g, b, 1)

    local specLine = spec and (spec.name .. " " .. (spec.className or "")) or (entry.class and entry.class:sub(1, 1) .. entry.class:sub(2):lower() or "")
    card.Spec:SetText(RoleMarkup(entry.role) .. specLine)
    card.Hero:SetText((isUser and ctx.runRecord.heroName) or "")
    card.RankText:SetText("#" .. tostring(rank))

    local rel = (ctx.topScore and ctx.topScore > 0) and math.floor((entry.score or 0) / ctx.topScore * 100 + 0.5) or 0
    card.relScore = rel

    local duration = ctx.duration
    local damage, healing = stats.damage or 0, stats.healing or 0
    local interrupts, dispels = stats.interrupts or 0, stats.dispels or 0
    local deaths, avoidable = stats.deaths or 0, stats.avoidableDamageTaken or 0
    local dps = stats.damagePerSecond or (duration > 0 and math.floor(damage / duration)) or 0
    local hps = stats.healingPerSecond or (duration > 0 and math.floor(healing / duration)) or 0
    local pb = ctx.personalBest

    local F = function(n) return MPT.Utils:FormatNumber(n) end
    card.interrupts:SetText(HighlightIfBest(tostring(interrupts), interrupts, pb.interrupts, isUser))
    card.dispels:SetText(HighlightIfBest(tostring(dispels), dispels, pb.dispels, isUser))
    card.dps:SetText(F(dps))
    card.hps:SetText(F(hps))
    card.avoidable:SetText(F(avoidable))
    card.deaths:SetText(deaths > 0 and Theme:Colorize(deaths, "bad") or "0")

    card.barValues = {
        dps = ctx.max.dps > 0 and dps / ctx.max.dps or 0,
        hps = ctx.max.hps > 0 and hps / ctx.max.hps or 0,
        int = ctx.max.int > 0 and interrupts / ctx.max.int or 0,
        disp = ctx.max.disp > 0 and dispels / ctx.max.disp or 0,
        avoid = ctx.max.avoid > 0 and avoidable / ctx.max.avoid or 0,
    }
    for _, bar in ipairs({card.DPSBar, card.HPSBar, card.IntBar, card.DispBar}) do
        bar:SetColor(r, g, b)
    end

    if isUser then
        card.StarRow:Hide(); card.FriendBtn:Hide()
        card.YouText:Show()
    else
        card.YouText:Hide()
        card.StarRow:Show(); card.FriendBtn:Show()
        WireRatingButtons(card, ctx.runRecord, nameText)
    end

    return isUser and scoreDelta or nil, dps, hps
end

-- Header line: key, time vs limit, timed result, timer bar.
local function PopulateHeader(frame, runRecord, duration)
    local Theme = MPT.Theme
    frame.DungeonName:SetText(runRecord.dungeonName or "Unknown dungeon")
    frame.KeystoneLevel:SetText("+" .. tostring(runRecord.keystoneLevel or 0))
    frame.KeyChip:SetWidth(math.max(40, frame.KeystoneLevel:GetStringWidth() + 18))
    frame.Eyebrow:SetText("Run complete · " .. date("%b %d, %I:%M %p", runRecord.timestamp or time()))

    local info = Theme:DungeonInfo(runRecord.dungeonID or runRecord.mapID)
    local limit = info and info.timeLimit
    local timeText = MPT.Utils:FormatDuration(duration)
    frame.Duration:SetText(limit and (timeText .. " of " .. MPT.Utils:FormatDuration(limit)) or timeText)

    local resultText, resultColor
    if runRecord.abandonReason == "abandon" then
        resultText, resultColor = "Abandoned", "bad"
    else
        local chests = Theme:ChestCount(duration, limit)
        if chests and chests > 0 then
            resultText, resultColor = "Timed +" .. chests, "good"
        elseif chests == 0 or runRecord.onTime == false or runRecord.completed == false then
            resultText, resultColor = "Depleted", "bad"
        elseif runRecord.onTime then
            resultText, resultColor = "Timed", "good"
        end
    end
    frame.Result:SetText(resultText or "")
    if resultColor then frame.Result:SetTextColor(Theme:Unpack(resultColor)) end

    if limit and limit > 0 then
        frame.TimerBar:Show()
        frame.TimerBar:SetColor(Theme:Unpack(resultColor == "bad" and "bad" or "good"))
        return math.min(1, duration / limit)
    end
    frame.TimerBar:Hide()
    return nil
end

local function PlayIntro(frame, cards, visibleCount, isMVP, timerFraction)
    local Theme = MPT.Theme
    if timerFraction then frame.TimerBar:SetFraction(timerFraction, true, 0.1) end
    for i = 1, visibleCount do
        local card = cards[i]
        local delay = 0.08 + (i - 1) * 0.11
        card.Glow:SetAlpha(0)
        Theme:SlideIn(card, {"BOTTOMLEFT", frame.CardsArea, "BOTTOMLEFT", card.anchorX, 0}, 90, 0, 0.45, delay, nil,
            (i == 1 and isMVP) and function()
                -- MVP card lifts 8px and pulses gold once
                Theme:Tween(card, 0.35, 0, function(p)
                    card:ClearAllPoints()
                    card:SetPoint("BOTTOMLEFT", frame.CardsArea, "BOTTOMLEFT", card.anchorX, 8 * p)
                end)
                Theme:Pulse(card.Glow, 0.9, 0.35, 1.4, 0.15)
            end or nil)
        Theme:CountUp(card.Score, card.relScore or 0, 0.7, delay + 0.25)
        local bv = card.barValues or {}
        card.DPSBar:SetFraction(bv.dps, true, delay + 0.35)
        card.HPSBar:SetFraction(bv.hps, true, delay + 0.4)
        card.IntBar:SetFraction(bv.int, true, delay + 0.45)
        card.DispBar:SetFraction(bv.disp, true, delay + 0.5)
        card.AvoidBar:SetFraction(bv.avoid, true, delay + 0.55)
    end
end

local function ShowStatic(frame, cards, visibleCount, isMVP, timerFraction)
    if timerFraction then frame.TimerBar:SetFraction(timerFraction, false) end
    for i = 1, visibleCount do
        local card = cards[i]
        MPT.Theme:CancelTween(card)
        MPT.Theme:CancelTween(card.Score)
        MPT.Theme:CancelTween(card.Glow)
        card:ClearAllPoints()
        card:SetPoint("BOTTOMLEFT", frame.CardsArea, "BOTTOMLEFT", card.anchorX, (i == 1 and isMVP) and 8 or 0)
        card:SetAlpha(1)
        card.Glow:SetAlpha((i == 1 and isMVP) and 0.35 or 0)
        card.Score:SetText(tostring(card.relScore or 0))
        local bv = card.barValues or {}
        card.DPSBar:SetFraction(bv.dps); card.HPSBar:SetFraction(bv.hps)
        card.IntBar:SetFraction(bv.int); card.DispBar:SetFraction(bv.disp)
        card.AvoidBar:SetFraction(bv.avoid)
    end
end

function Scoreboard:Show(runRecord)
    if not runRecord then
        print("|cff00ffaa[StormsDungeonData]|r No run record provided")
        return
    end

    local Theme = MPT.Theme
    local frame = self:Create()
    local wasShown = frame:IsShown()
    local previousRunID = self.displayedRunID
    local runList, idx = self:GetRunListAndIndex(runRecord)
    self.runList = runList
    self.currentRunIndex = idx or 1
    self.displayedRunID = runRecord.id or runRecord.timestamp

    if not runRecord.specIcon then
        local spec = GetPlayerSpecInfoSafe()
        if spec and spec.specIcon then runRecord.specIcon = spec.specIcon end
    end
    if not runRecord.heroIcon then
        local hero = GetHeroTalentInfoSafe()
        if hero and hero.heroIcon and hero.heroIcon ~= 0 then runRecord.heroIcon = hero.heroIcon end
    end
    frame.SpecIconText:SetText((runRecord.specIcon and runRecord.specIcon ~= 0) and ("|T" .. tostring(runRecord.specIcon) .. ":14:14:0:0|t") or "")
    frame.HeroIconText:SetText(runRecord.heroName or "")

    local duration = tonumber(runRecord.duration) or (runRecord.endTime and runRecord.startTime and (runRecord.endTime - runRecord.startTime)) or 0
    local timerFraction = PopulateHeader(frame, runRecord, duration)

    local candidates, totals, playerCount = BuildCandidates(runRecord)
    local isAbandoned = runRecord.abandonReason == "abandon"
    local userSet = BuildUserCharacterSet()
    local ctx = {
        runRecord = runRecord,
        userSet = userSet,
        duration = duration,
        topScore = candidates[1] and candidates[1].score or 0,
        personalBest = GetPersonalBestStats(runRecord, userSet),
        max = {dps = 0, hps = 0, int = 0, disp = 0, avoid = 0},
    }
    for _, c in ipairs(candidates) do
        local s = c.stats
        ctx.max.dps = math.max(ctx.max.dps, s.damagePerSecond or (duration > 0 and (s.damage or 0) / duration) or 0)
        ctx.max.hps = math.max(ctx.max.hps, s.healingPerSecond or (duration > 0 and (s.healing or 0) / duration) or 0)
        ctx.max.int = math.max(ctx.max.int, s.interrupts or 0)
        ctx.max.disp = math.max(ctx.max.disp, s.dispels or 0)
        ctx.max.avoid = math.max(ctx.max.avoid, s.avoidableDamageTaken or 0)
    end

    local userDelta
    local totalDPS, totalHPS = 0, 0
    local visibleCount = math.min(5, #candidates)
    for i = 1, 5 do
        local card = frame.PlayerRows[i]
        local entry = candidates[i]
        if entry then
            card:Show()
            local delta, dps, hps = PopulateCard(card, entry, i, ctx)
            userDelta = userDelta or delta
            totalDPS = totalDPS + (dps or 0)
            totalHPS = totalHPS + (hps or 0)
        else
            card:Hide()
        end
    end

    -- MVP: rank #1 by balanced_roles score; none for abandoned keys
    local isMVP = (not isAbandoned) and candidates[1] ~= nil
    local lead = frame.PlayerRows[1]
    lead.MVPTag:SetShown(isMVP)
    Theme:SetPanelColors(lead, "surface", isMVP and "gold" or "line")
    lead.Score:SetTextColor(Theme:Unpack(isMVP and "gold" or "text"))
    lead.Why:SetText(isMVP and BuildMVPReasons(candidates) or "")
    if isMVP then
        runRecord.mvpName = ResolveDisplayName(candidates[1].player, candidates[1].stats)
    end

    frame.RatingGain:SetText(userDelta and ((userDelta > 0 and "+" or "") .. tostring(userDelta) .. " rating") or "")
    frame.RatingGain:SetTextColor(Theme:Unpack((userDelta or 0) < 0 and "bad" or "good"))

    if totals.damage == 0 and totals.healing == 0 and totals.interrupts == 0 then
        frame.TotalsText:SetText(Theme:Colorize("No combat data available. See chat for details.", "bad"))
    else
        local totalDeaths = math.max(tonumber(runRecord.deathCount) or 0, totals.deaths)
        frame.TotalsText:SetText(string.format("Group: %s dps · %s hps · %d kicks · %d dispels · %d deaths",
            MPT.Utils:FormatNumber(totalDPS), MPT.Utils:FormatNumber(totalHPS),
            totals.interrupts, totals.dispels, totalDeaths))
    end

    local n = #(self.runList or {})
    frame.RunNavLabel:SetText((n > 0 and self.currentRunIndex) and string.format("Run %d of %d", self.currentRunIndex, n) or "")
    frame.PrevButton:SetEnabled(n > 1 and self.currentRunIndex < n)
    frame.NextButton:SetEnabled(n > 1 and self.currentRunIndex > 1)
    if frame.AutoReportCheck and frame.AutoReportCheck.Refresh then
        frame.AutoReportCheck:Refresh()
    end

    frame:Show()
    -- Animate when the window opens or switches runs; rating clicks re-render in place.
    if (not wasShown) or previousRunID ~= self.displayedRunID then
        PlayIntro(frame, frame.PlayerRows, visibleCount, isMVP, timerFraction)
    else
        ShowStatic(frame, frame.PlayerRows, visibleCount, isMVP, timerFraction)
    end

    -- Auto-report MVP summary to party once per run when this client is the elected reporter.
    local runKey = tostring(runRecord.timestamp or "") .. "_" .. tostring(runRecord.mapID or "") .. "_" .. tostring(runRecord.keystoneLevel or "")
    if runKey ~= self.lastAutoReportedRunKey then
        self.lastAutoReportedRunKey = runKey
        if IsInGroup() and not IsInRaid() and MPT.ReporterElection and MPT.ReporterElection:IsDesignatedReporter() then
            self:ReportRunToChat("PARTY", "summary")
        end
    end
end

function Scoreboard:Hide()
    if self.frame then
        self.frame:Hide()
    end
end
