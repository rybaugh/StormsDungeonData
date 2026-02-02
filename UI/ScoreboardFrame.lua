-- Mythic Plus Tracker - Scoreboard Frame
-- Displays run statistics at dungeon completion

local MPT = StormsDungeonData
local Scoreboard = {}
MPT.Scoreboard = Scoreboard

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
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -5, -5)
    
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
    local headers = {"Player", "Damage", "Healing", "Interrupts", "Deaths", "Points"}
    local columnWidths = {180, 140, 140, 120, 100, 100}
    local headerX = 15
    
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
        headerText:SetJustifyH("LEFT")
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
        damage:SetJustifyH("LEFT")
        
        local healing = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        healing:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2], 0)
        healing:SetWidth(columnWidths[3])
        healing:SetJustifyH("LEFT")
        
        local interrupts = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        interrupts:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3], 0)
        interrupts:SetWidth(columnWidths[4])
        interrupts:SetJustifyH("CENTER")
        
        local deaths = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        deaths:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4], 0)
        deaths:SetWidth(columnWidths[5])
        deaths:SetJustifyH("CENTER")
        deaths:SetTextColor(0.8, 0.8, 0.8)  -- Grayed out
        
        local points = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        points:SetPoint("LEFT", row, "LEFT", columnWidths[1] + columnWidths[2] + columnWidths[3] + columnWidths[4] + columnWidths[5], 0)
        points:SetWidth(columnWidths[6])
        points:SetJustifyH("CENTER")
        
        table.insert(frame.PlayerRows, {
            frame = row,
            mvpBg = mvpBg,
            name = playerName,
            damage = damage,
            healing = healing,
            interrupts = interrupts,
            deaths = deaths,
            points = points,
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
    totalsText:SetText("Damage: --   Healing: --   Interrupts: --   Deaths: --")
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
        frame:Hide()
        MPT.HistoryViewer:Show()
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

    local totalsDamage, totalsHealing, totalsInterrupts, totalsDeaths = 0, 0, 0, 0
    local mvpIndex = nil
    local mvpScore = nil
    local mvpStats = nil
    local mvpPlayer = nil

    for i, player in ipairs(playerData) do
        if i <= 5 then
            local row = frame.PlayerRows[i]
            if not row then break end
            
            -- Get stats from either format
            local stats = player.stats or (MPT.CombatLog and MPT.CombatLog:GetPlayerStats(player.name)) or {}

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
                damageText = damageText .. " |cffffd100PB|r"
            end
            if healingValue > 0 and healingValue >= personalBest.healing then
                healingText = healingText .. " |cffffd100PB|r"
            end
            if interruptsValue > 0 and interruptsValue >= personalBest.interrupts then
                interruptsText = interruptsText .. " |cffffd100PB|r"
            end

            row.damage:SetText(damageText)
            row.healing:SetText(healingText)
            row.interrupts:SetText(interruptsText)
            row.deaths:SetText(tostring(stats.deaths or 0))
            row.points:SetText("0")  -- TODO: Calculate points

            totalsDamage = totalsDamage + (stats.damage or 0)
            totalsHealing = totalsHealing + (stats.healing or 0)
            totalsInterrupts = totalsInterrupts + (stats.interrupts or 0)
            totalsDeaths = totalsDeaths + (stats.deaths or 0)

            -- MVP heuristic: balanced contribution (damage + healing + interrupts weight) minus deaths
            local score = (stats.damage or 0) + (stats.healing or 0) + ((stats.interrupts or 0) * 25000) - ((stats.deaths or 0) * 100000)
            if (not mvpScore) or score > mvpScore then
                mvpScore = score
                mvpIndex = i
                mvpStats = stats
                mvpPlayer = player
            end
            
            row.frame:Show()
        end
    end

    -- Clear MVP highlights
    for i = 1, 5 do
        if frame.PlayerRows[i] and frame.PlayerRows[i].mvpBg then
            frame.PlayerRows[i].mvpBg:Hide()
        end
    end

    frame.TotalsText:SetText(string.format(
        "Damage: |cffff8000%s|r   Healing: |cff00ff00%s|r   Interrupts: |cff0088ff%d|r   Deaths: %d",
        MPT.Utils:FormatNumber(totalsDamage),
        MPT.Utils:FormatNumber(totalsHealing),
        totalsInterrupts,
        totalsDeaths
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
