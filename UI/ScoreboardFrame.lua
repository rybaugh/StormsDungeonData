-- Mythic Plus Tracker - Scoreboard Frame
-- Displays run statistics at dungeon completion

local MPT = StormsDungeonData
local Scoreboard = {}
MPT.Scoreboard = Scoreboard

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
    frame:SetSize(1000, 500)
    frame:SetPoint("CENTER", UIParent, "CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameLevel(100)
    
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
    dungeonInfoBg:SetSize(980, 90)
    dungeonInfoBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -45)
    
    local backdropInfo = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    }
    SetBackdropCompat(dungeonInfoBg, backdropInfo, {0.1, 0.1, 0.1, 0.5}, {1, 1, 1, 0.3})
    
    -- Dungeon name - centered
    local dungeonName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    dungeonName:SetPoint("TOP", dungeonInfoBg, "TOP", 0, -10)
    dungeonName:SetJustifyH("CENTER")
    frame.DungeonName = dungeonName
    
    -- Keystone level - under dungeon name
    local keystoneLevel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keystoneLevel:SetPoint("TOP", dungeonName, "BOTTOM", 0, -4)
    keystoneLevel:SetJustifyH("CENTER")
    frame.KeystoneLevel = keystoneLevel

    -- Spec/Hero icon slots (icons only, centered)
    local specIconFrame = CreateFrame("Frame", nil, frame)
    specIconFrame:SetSize(24, 24)
    specIconFrame:SetPoint("RIGHT", keystoneLevel, "LEFT", -8, 0)

    local specIconText = specIconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specIconText:SetPoint("CENTER", specIconFrame, "CENTER", 0, 0)
    specIconText:SetJustifyH("CENTER")
    frame.SpecIconText = specIconText

    local heroIconFrame = CreateFrame("Frame", nil, frame)
    heroIconFrame:SetSize(80, 24)
    heroIconFrame:SetPoint("LEFT", keystoneLevel, "RIGHT", 8, 0)

    local heroIconText = heroIconFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heroIconText:SetPoint("CENTER", heroIconFrame, "CENTER", 0, 0)
    heroIconText:SetJustifyH("CENTER")
    heroIconText:SetTextColor(0.8, 0.8, 1, 1)  -- Light blue tint
    frame.HeroIconText = heroIconText

    -- Duration + Mob % - bigger and under dungeon name
    local duration = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    duration:SetPoint("TOPRIGHT", keystoneLevel, "BOTTOM", -10, -6)
    duration:SetJustifyH("RIGHT")
    frame.Duration = duration

    local mobPercent = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    mobPercent:SetPoint("TOPLEFT", keystoneLevel, "BOTTOM", 10, -6)
    mobPercent:SetJustifyH("LEFT")
    frame.MobPercent = mobPercent
    
    -- Player stats table header
    local headerY = -155
    local headers = {"Player", "Damage", "Healing", "Interrupts"}
    local columnWidths = {200, 200, 200, 180}
    local headerX = 10
    
    -- Create header background
    local headerBg = frame:CreateTexture(nil, "BACKGROUND")
    headerBg:SetHeight(18)
    headerBg:SetWidth(980)
    headerBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, headerY - 2)
    headerBg:SetColorTexture(0.12, 0.12, 0.18, 0.45)
    
    for i, header in ipairs(headers) do
        local headerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetText(header)
        headerText:SetPoint("TOPLEFT", frame, "TOPLEFT", headerX, headerY)
        headerText:SetTextColor(1, 0.84, 0, 1)
        headerText:SetWidth(columnWidths[i])
        if i == 1 then
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
        local rowY = -185 - ((i - 1) * 28)
        
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(980, 24)
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
        
        local playerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerName:SetPoint("LEFT", row, "LEFT", 0, 0)
        playerName:SetWidth(columnWidths[1])
        playerName:SetJustifyH("LEFT")
        
        local damage = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        damage:SetPoint("LEFT", row, "LEFT", columnWidths[1], 0)
        damage:SetWidth(columnWidths[2])
        damage:SetJustifyH("CENTER")
        
        local healing = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        healing:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2], 0)
        healing:SetWidth(columnWidths[3])
        healing:SetJustifyH("CENTER")
        
        local interrupts = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        interrupts:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3], 0)
        interrupts:SetWidth(columnWidths[4])
        interrupts:SetJustifyH("CENTER")
        
        table.insert(frame.PlayerRows, {
            frame = row,
            mvpBg = mvpBg,
            name = playerName,
            damage = damage,
            healing = healing,
            interrupts = interrupts,
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
    totalsText:SetText("Damage: --   Healing: --   Interrupts: --")
    frame.TotalsText = totalsText

    local mvpTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mvpTitle:SetPoint("TOPLEFT", footerBg, "TOPLEFT", 520, -10)
    mvpTitle:SetTextColor(1, 0.84, 0, 1)
    mvpTitle:SetText("MVP")

    local mvpName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    mvpName:SetPoint("TOPLEFT", footerBg, "TOPLEFT", 520, -26)
    mvpName:SetText("--")
    frame.MVPName = mvpName

    local mvpDetails = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mvpDetails:SetPoint("TOPLEFT", footerBg, "TOPLEFT", 520, -48)
    mvpDetails:SetText("--")
    frame.MVPDetails = mvpDetails
    
    -- Buttons at bottom
    local buttonWidth = 100
    local buttonHeight = 24
    
    local closeButton = MPT.UIUtils:CreateButton(frame, "Close", buttonWidth, buttonHeight, function()
        frame:Hide()
    end)
    closeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 15)
    
    local historyButton = MPT.UIUtils:CreateButton(frame, "History", buttonWidth, buttonHeight, function()
        if MPT.HistoryViewer and MPT.HistoryViewer.ShowAtAnchor then
            MPT.HistoryViewer:ShowAtAnchor(frame)
        else
            MPT.HistoryViewer:Show()
        end
    end)
    historyButton:SetPoint("BOTTOMRIGHT", closeButton, "BOTTOMLEFT", -5, 0)
    
    self.frame = frame
    return frame
end

function Scoreboard:Show(runRecord)
    if not runRecord then
        print("|cff00ffaa[StormsDungeonData]|r No run record provided")
        return
    end
    
    local frame = self:Create()
    
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

    local minutes = math.floor(runRecord.duration / 60)
    local seconds = runRecord.duration % 60
    frame.Duration:SetText(string.format("%02d:%02d", minutes, seconds))
    
    frame.MobPercent:SetText(string.format("%.1f%%", runRecord.overallMobPercentage or 0))
    
    -- Populate player stats
    -- Support both real combat format (players array) and test format (playerStats dictionary)
    local playerData = runRecord.players or {}
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
        local best = {damage = 0, healing = 0, interrupts = 0}
        local db = StormsDungeonDataDB
        if not db or not db.runs then
            return best
        end

        for _, run in ipairs(db.runs) do
            local sameDungeon = false
            if dungeonID and run.dungeonID and run.dungeonID ~= 0 then
                sameDungeon = run.dungeonID == dungeonID
            elseif dungeonName then
                sameDungeon = run.dungeonName == dungeonName
            end

            if sameDungeon then
                if run.playerStats and run.playerStats[playerName] then
                    local pstats = run.playerStats[playerName]
                    best.damage = math.max(best.damage, pstats.damage or 0)
                    best.healing = math.max(best.healing, pstats.healing or 0)
                    best.interrupts = math.max(best.interrupts, pstats.interrupts or 0)
                elseif run.players then
                    for _, p in ipairs(run.players) do
                        if p.name == playerName then
                            best.damage = math.max(best.damage, p.damage or 0)
                            best.healing = math.max(best.healing, p.healing or 0)
                            best.interrupts = math.max(best.interrupts, p.interrupts or 0)
                        end
                    end
                end
            end
        end

        return best
    end

    local totalsDamage, totalsHealing, totalsInterrupts = 0, 0, 0
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

    local function MVPScoreFor(role, dmgShare, healShare, intShare)
        role = role or ""

        -- Scores are designed to be comparable across roles.
        if role == "HEALER" then
            return (0.20 * dmgShare) + (1.00 * healShare) + (0.10 * intShare)
        elseif role == "TANK" then
            return (0.60 * dmgShare) + (0.40 * healShare) + (0.80 * intShare)
        else -- DAMAGER / unknown
            return (1.00 * dmgShare) + (0.10 * healShare) + (0.60 * intShare)
        end
    end

    local mvpCandidates = {}

    for i, player in ipairs(playerData) do
        if i <= 5 then
            local row = frame.PlayerRows[i]
            if not row then break end
            
            -- Get stats from either format
            -- Prefer runRecord player fields (what we save), then test-mode nested stats, then live CombatLog lookup.
            local stats = player.stats or {}
            if stats.damage == nil and (player.damage ~= nil or player.healing ~= nil or player.interrupts ~= nil) then
                stats = player
            end
            if (stats.damage == nil) and MPT.CombatLog and MPT.CombatLog.GetPlayerStats and player.name then
                stats = MPT.CombatLog:GetPlayerStats(player.name) or {}
            end

            -- Color player name by class (use text color directly for reliability)
            row.name:SetText(player.name or "")
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
            local personalBest = GetPersonalBestStats(runRecord.dungeonID, runRecord.dungeonName, player.name)
            local damageValue = stats.damage or 0
            local healingValue = stats.healing or 0
            local interruptsValue = stats.interrupts or 0

            local damageText = MPT.Utils:FormatNumber(damageValue)
            local healingText = MPT.Utils:FormatNumber(healingValue)
            local interruptsText = tostring(interruptsValue)

            if damageValue > 0 and damageValue >= personalBest.damage then
                damageText = "|cffff8000" .. damageText .. "|r"
            end
            if healingValue > 0 and healingValue >= personalBest.healing then
                healingText = "|cffff8000" .. healingText .. "|r"
            end
            if interruptsValue > 0 and interruptsValue >= personalBest.interrupts then
                interruptsText = "|cffff8000" .. interruptsText .. "|r"
            end

            row.damage:SetText(damageText)
            row.healing:SetText(healingText)
            row.interrupts:SetText(interruptsText)

            totalsDamage = totalsDamage + (stats.damage or 0)
            totalsHealing = totalsHealing + (stats.healing or 0)
            totalsInterrupts = totalsInterrupts + (stats.interrupts or 0)

            mvpCandidates[i] = {
                player = player,
                stats = stats,
                role = player.role or stats.role,
            }
            
            row.frame:Show()
        end
    end

    -- Compute MVP using final totals for proper normalization.
    for i = 1, 5 do
        local c = mvpCandidates[i]
        if c and c.stats then
            local dmgShare = SafeShare(c.stats.damage or 0, totalsDamage)
            local healShare = SafeShare(c.stats.healing or 0, totalsHealing)
            local intShare = SafeShare(c.stats.interrupts or 0, totalsInterrupts)
            local score = MVPScoreFor(c.role, dmgShare, healShare, intShare)
            if (not mvpScore) or score > mvpScore then
                mvpScore = score
                mvpIndex = i
                mvpStats = c.stats
                mvpPlayer = c.player
            end
        end
    end

    -- Clear MVP highlights
    for i = 1, 5 do
        if frame.PlayerRows[i] and frame.PlayerRows[i].mvpBg then
            frame.PlayerRows[i].mvpBg:Hide()
        end
    end

    frame.TotalsText:SetText(string.format(
        "Damage: |cffff8000%s|r   Healing: |cff00ff00%s|r   Interrupts: |cff0088ff%d|r",
        MPT.Utils:FormatNumber(totalsDamage),
        MPT.Utils:FormatNumber(totalsHealing),
        totalsInterrupts
    ))

    if mvpIndex and frame.PlayerRows[mvpIndex] and frame.PlayerRows[mvpIndex].mvpBg then
        frame.PlayerRows[mvpIndex].mvpBg:Show()
    end

    if mvpPlayer and frame.MVPName and frame.MVPDetails then
        -- MVP name (class-colored)
        frame.MVPName:SetText(mvpPlayer.name or "--")
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

        frame.MVPDetails:SetText(string.format(
            "DMG: %s   HPS: %s   INT: %d   Deaths: %d",
            MPT.Utils:FormatNumber(mvpStats and mvpStats.damage or 0),
            MPT.Utils:FormatNumber(mvpStats and mvpStats.healing or 0),
            (mvpStats and mvpStats.interrupts or 0),
            (mvpStats and mvpStats.deaths or 0)
        ))
    end
    
    -- Hide unused rows
    local numRows = #playerData
    for i = numRows + 1, 5 do
        if frame.PlayerRows[i] then
            frame.PlayerRows[i].frame:Hide()
        end
    end
    
    frame:Show()
end

function Scoreboard:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

print("|cff00ffaa[StormsDungeonData]|r Scoreboard module loaded")
