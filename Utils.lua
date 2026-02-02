-- Mythic Plus Tracker - Utility Module
-- Helper functions used throughout the addon

local MPT = StormsDungeonData
local Utils = MPT.Utils

-- String formatting helpers
function Utils:FormatNumber(num)
    if num >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.2fK", num / 1000)
    else
        return tostring(num)
    end
end

function Utils:FormatPercentage(current, total)
    if total == 0 then return "0%" end
    return string.format("%.1f%%", (current / total) * 100)
end

function Utils:FormatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    
    if hours > 0 then
        return string.format("%02d:%02d:%02d", hours, minutes, secs)
    else
        return string.format("%02d:%02d", minutes, secs)
    end
end

-- Table utilities
function Utils:DeepCopy(tbl)
    if type(tbl) ~= "table" then return tbl end
    local result = {}
    for k, v in pairs(tbl) do
        result[k] = Utils:DeepCopy(v)
    end
    return result
end

function Utils:TableConcat(t, sep)
    local result = {}
    for i, v in ipairs(t) do
        table.insert(result, tostring(v))
    end
    return table.concat(result, sep or ", ")
end

-- Class color helpers
function Utils:GetClassColor(class)
    local colors = {
        WARRIOR = "C79C6E",
        PALADIN = "F58CBA",
        HUNTER = "ABD473",
        ROGUE = "FFF569",
        PRIEST = "FFFFFF",
        DEATHKNIGHT = "C41E3A",
        SHAMAN = "0070DD",
        MAGE = "69CCF0",
        WARLOCK = "9482CA",
        MONK = "00FF98",
        DRUID = "FF7D0A",
        DEMONHUNTER = "A335EE",
    }
    return colors[class] or "FFFFFF"
end

function Utils:ColorText(text, color)
    return "|cff" .. color .. text .. "|r"
end

function Utils:GetClassColoredName(name, class)
    local color = Utils:GetClassColor(class)
    return Utils:ColorText(name, color)
end

-- Dungeon info
function Utils:GetDungeonName(dungeonID)
    local dungeonNames = {
        [399] = "Shadowmoon Burial Grounds",
        [400] = "The Everbloom",
        [402] = "Upper Blackrock Spire",
        [403] = "The Underrot",
        [404] = "Temple of the Jade Serpent",
        [405] = "Mists of Tirna Scithe",
        [406] = "The Necrotic Wake",
        [407] = "Plaguefall",
        [408] = "Sanguine Depths",
        [409] = "Spires of Ascension",
        [410] = "Theater of Pain",
        [411] = "De Other Side",
        [457] = "Halls of Valor",
        [458] = "Vault of the Wardens",
        [459] = "Neltharion's Lair",
        [460] = "Eye of Azshara",
        [461] = "Darkheart Thicket",
        [462] = "Black Rook Hold",
        [463] = "Halls of Infusion",
        [464] = "Uldaman: Legacy of Tyr",
        [465] = "Neltharus",
        [466] = "Ruby Life Pools",
        [467] = "The Nokhud Offensive",
        [468] = "Brackenhide Hollow",
        [469] = "Freehold",
        [470] = "Tol Dagor",
        [471] = "The MOTHERLODE!!",
        [472] = "Waycrest Manor",
        [473] = "Atal'Dazar",
        [474] = "King's Rest",
        [475] = "Temple of Sethraliss",
        [476] = "Shrine of the Storm",
    }
    return dungeonNames[dungeonID] or ("Dungeon " .. dungeonID)
end

function Utils:GetDungeonAcronym(dungeonName)
    local acronyms = {
        ["Shadowmoon Burial Grounds"] = "SMBG",
        ["The Everbloom"] = "EB",
        ["Upper Blackrock Spire"] = "UBRS",
        ["The Underrot"] = "UR",
        ["Temple of the Jade Serpent"] = "TTJS",
        ["Mists of Tirna Scithe"] = "MOTS",
        ["The Necrotic Wake"] = "TNW",
        ["Plaguefall"] = "PF",
        ["Sanguine Depths"] = "SD",
        ["Spires of Ascension"] = "SoA",
        ["Theater of Pain"] = "TOP",
        ["De Other Side"] = "DOS",
        ["Halls of Valor"] = "HoV",
        ["Vault of the Wardens"] = "VotW",
        ["Neltharion's Lair"] = "NL",
        ["Eye of Azshara"] = "EoA",
        ["Darkheart Thicket"] = "DHT",
        ["Black Rook Hold"] = "BRH",
        ["Halls of Infusion"] = "HoI",
        ["Uldaman: Legacy of Tyr"] = "ULT",
        ["Neltharus"] = "NELT",
        ["Ruby Life Pools"] = "RLP",
        ["The Nokhud Offensive"] = "TNO",
        ["Brackenhide Hollow"] = "BH",
        ["Freehold"] = "FH",
        ["Tol Dagor"] = "TD",
        ["The MOTHERLODE!!"] = "ML",
        ["Waycrest Manor"] = "WM",
        ["Atal'Dazar"] = "AD",
        ["King's Rest"] = "KR",
        ["Temple of Sethraliss"] = "TS",
        ["Shrine of the Storm"] = "SS",
    }
    return acronyms[dungeonName] or dungeonName
end

print("|cff00ffaa[StormsDungeonData]|r Utils module loaded")
