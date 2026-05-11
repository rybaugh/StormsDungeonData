-- Storm's Dungeon Data - Player Tooltip
-- Appends SDD good/bad rating lines to the bottom of player unit tooltips.
--
-- WoW 12.0 taint: TooltipDataProcessor callbacks run in tainted context, so
-- data.guid is a "secret string" that cannot be passed to string methods or
-- most API calls.  We sidestep this by caching the mouseover player's name
-- from the UPDATE_MOUSEOVER_UNIT event (untainted) and reading that cache
-- when the tooltip callback fires.

local MPT = StormsDungeonData
if not MPT or not MPT.Database then return end

local PlayerTooltip = {}
MPT.PlayerTooltip = PlayerTooltip

-- Cached mouseover player full name, normalized rating key, and rating counts (set from UPDATE_MOUSEOVER_UNIT in untainted context).
local cachedMouseoverName = nil
local cachedMouseoverRatingKey = nil
local cachedMouseoverGoodCount = 0
local cachedMouseoverBadCount = 0

local function ClearCachedMouseoverData()
    cachedMouseoverName = nil
    cachedMouseoverRatingKey = nil
    cachedMouseoverGoodCount = 0
    cachedMouseoverBadCount = 0
end

local function NormalizePlayerNameForRatingKey(playerName)
    if not playerName or type(playerName) ~= "string" then return nil end
    local name = playerName:gsub("%s+", ""):lower()
    if name == "" then return nil end
    -- If no realm suffix, append current realm so same-name on different realms don't collide
    if not name:match("%-") and GetRealmName then
        name = name .. "-" .. (GetRealmName() or ""):gsub("%s+", ""):lower()
    end
    return name
end

local function SafeNormalizePlayerNameForRatingKey(playerName)
    local ok, normalized = pcall(NormalizePlayerNameForRatingKey, playerName)
    if ok then
        return normalized
    end
    return nil
end

local function CacheMouseoverPlayer()
    if not UnitIsPlayer("mouseover") then
        ClearCachedMouseoverData()
        return
    end

    local mouseoverName = nil
    if GetUnitName then
        local okFullName, fullName = pcall(GetUnitName, "mouseover", true)
        if okFullName and type(fullName) == "string" then
            mouseoverName = fullName
        end
    end

    if not mouseoverName then
        local okName, name = pcall(UnitName, "mouseover")
        if okName and type(name) == "string" then
            mouseoverName = name
        end
    end

    if not mouseoverName then
        ClearCachedMouseoverData()
        return
    end

    cachedMouseoverName = mouseoverName
    -- Normalize in protected mode so secret-string taint cannot hard-error.
    cachedMouseoverRatingKey = SafeNormalizePlayerNameForRatingKey(cachedMouseoverName)

    -- Compute rating counts in untainted context by iterating runs directly
    local goodCount = 0
    local badCount = 0
    if cachedMouseoverRatingKey and StormsDungeonDataDB and StormsDungeonDataDB.runs then
        for _, run in ipairs(StormsDungeonDataDB.runs) do
            if run.players then
                for _, player in ipairs(run.players) do
                    -- Safely compute player key once and compare
                    if player.name and type(player.name) == "string" then
                        local pKey = NormalizePlayerNameForRatingKey(player.name)
                        if pKey == cachedMouseoverRatingKey then
                            if player.rating == "good" then
                                goodCount = goodCount + 1
                            elseif player.rating == "bad" then
                                badCount = badCount + 1
                            end
                        end
                    end
                end
            end
        end
    end
    cachedMouseoverGoodCount = goodCount
    cachedMouseoverBadCount = badCount
end

-- Track whether we already added our lines to this tooltip refresh.
local sddTooltipAdded = false

local function IsPlayerTooltipEnabled()
    if StormsDungeonDataDB and StormsDungeonDataDB.settings then
        local enabled = StormsDungeonDataDB.settings.playerTooltipEnabled
        if enabled ~= nil then
            return enabled == true
        end
    end
    return false
end

-- Core logic: add SDD rating lines to the given tooltip.
-- Does NOT call tooltip:Show() — the tooltip framework handles that after
-- all processors run, which avoids the flicker/re-entry loop.
-- Uses pre-cached counts computed in untainted context to avoid any tainted operations.
local function AddRatingToTooltip(tooltip, goodCount, badCount)
    if sddTooltipAdded then return end
    if not IsPlayerTooltipEnabled() then return end
    if not tooltip or not MPT.Database then return end

    sddTooltipAdded = true
    local ratingText
    if goodCount > 0 and badCount > 0 then
        ratingText = "|cff00ff00+" .. goodCount .. " Good|r / |cffff4444+" .. badCount .. " Bad|r"
    elseif goodCount > 0 then
        ratingText = "|cff00ff00+" .. goodCount .. " Good|r"
    elseif badCount > 0 then
        ratingText = "|cffff4444+" .. badCount .. " Bad|r"
    else
        ratingText = "|cffffffffNo rating yet|r"
    end
    tooltip:AddLine("|cff00ffaaStorm's Dungeon Data:|r " .. ratingText)
end

function PlayerTooltip:Initialize()
    -- Listen for mouseover changes in untainted context to cache the player name.
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    eventFrame:SetScript("OnEvent", function()
        CacheMouseoverPlayer()
    end)

    -- Reset dedup flag whenever tooltip is cleared for new content.
    GameTooltip:HookScript("OnTooltipCleared", function()
        sddTooltipAdded = false
    end)

    -- Add lines immediately in the callback — no deferral, no Show() call.
    -- This places our text before other addons (like Raider.IO) that also
    -- hook TooltipDataProcessor, since registration order is preserved.
    -- UnitName/GetRealmName work fine here; the returned values may be
    -- tainted but we only use them for our own DB lookup.
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            if tooltip ~= GameTooltip then return end
            if not IsPlayerTooltipEnabled() then return end
            if cachedMouseoverRatingKey then
                -- Pass only the pre-computed counts; never pass tainted player name data
                AddRatingToTooltip(tooltip, cachedMouseoverGoodCount, cachedMouseoverBadCount)
            end
        end)
    elseif GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
            if not IsPlayerTooltipEnabled() then return end
            if cachedMouseoverRatingKey then
                -- Pass only the pre-computed counts; never pass tainted player name data
                AddRatingToTooltip(tooltip, cachedMouseoverGoodCount, cachedMouseoverBadCount)
            end
        end)
    end
end
