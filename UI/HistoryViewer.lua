-- Mythic Plus Tracker - History Viewer
-- Displays historical data for dungeons and characters

local MPT = StormsDungeonData
local HistoryViewer = {}
MPT.HistoryViewer = HistoryViewer

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
    end
end

HistoryViewer.selectedCharacter = nil
HistoryViewer.selectedDungeon = nil
HistoryViewer.selectedDungeonName = nil
HistoryViewer.selectedKeystoneLevel = nil

function HistoryViewer:Create()
    if self.frame then
        self.frame:Show()
        return self.frame
    end
    
    -- Main frame
    local frame = CreateFrame("Frame", "StormsDungeonDataHistory", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1000, 700)
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
    title:SetText("Run History")
    frame.Title = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Summary bar (top)
    local summaryPanel = CreateFrame("Frame", nil, frame)
    summaryPanel:SetSize(980, 52)
    summaryPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -45)

    local backdropInfo = {
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    }
    SetBackdropCompat(summaryPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})

    local summaryLabels = {"Total Runs", "Completed", "Failed", "Avg Level"}
    frame.SummaryValues = {}
    for i, label in ipairs(summaryLabels) do
        local colWidth = 980 / #summaryLabels
        local x = 10 + ((i - 1) * colWidth)

        local labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetText(label .. ":")
        labelText:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", x, -10)
        labelText:SetTextColor(1, 0.84, 0, 1)

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        valueText:SetText("--")
        valueText:SetPoint("TOPLEFT", summaryPanel, "TOPLEFT", x, -26)
        valueText:SetTextColor(1, 1, 1, 1)

        table.insert(frame.SummaryValues, valueText)
    end

    -- Filter bar
    local filterPanel = CreateFrame("Frame", nil, frame)
    filterPanel:SetSize(980, 70)
    filterPanel:SetPoint("TOPLEFT", summaryPanel, "BOTTOMLEFT", 0, -8)
    SetBackdropCompat(filterPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    
    local function CreateFilterDropdown(labelText, x, width)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(labelText)
        label:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", x + 8, -8)
        label:SetTextColor(1, 0.84, 0, 1)

        -- UIDropDownMenuTemplate relies on the dropdown having a name for correct anchoring
        -- (the template creates named children like <name>Button and uses them as anchor frames).
        local safeKey = (labelText or ""):gsub("%W", "")
        if safeKey == "" then safeKey = "Filter" end
        local dropdownName = "StormsDungeonDataHistory" .. safeKey .. "Dropdown"
        local dropdown = CreateFrame("Frame", dropdownName, filterPanel, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", x - 12, -22)
        UIDropDownMenu_SetWidth(dropdown, width)
        UIDropDownMenu_JustifyText(dropdown, "LEFT")
        UIDropDownMenu_SetText(dropdown, "All")

        -- Make the selected value text larger for readability.
        local dropdownText = _G[dropdownName .. "Text"]
        if dropdownText and dropdownText.SetFontObject then
            dropdownText:SetFontObject("GameFontNormal")
        end

        -- Force the menu to open directly below the dropdown button.
        -- UIDropDownMenuTemplate typically toggles from the button's OnMouseDown; if we only
        -- override OnClick, the default mouse-down toggle can open (default anchor) and then
        -- our OnClick toggles again, immediately closing it.
        local button = _G[dropdownName .. "Button"]
        if button then
            if UIDropDownMenu_SetAnchor then
                UIDropDownMenu_SetAnchor(dropdown, 0, 0, "TOPLEFT", button, "BOTTOMLEFT")
            end

            if ToggleDropDownMenu then
                local function RepositionDropdownList()
                    local list = _G["DropDownList1"]
                    if list and list:IsShown() then
                        list:ClearAllPoints()
                        list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
                    end
                end

                button:SetScript("OnMouseDown", function()
                    ToggleDropDownMenu(1, nil, dropdown, button, 0, 0)
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, RepositionDropdownList)
                    else
                        RepositionDropdownList()
                    end
                end)
                button:SetScript("OnClick", nil)
            end
        end
        return dropdown
    end

    local dropdownWidth = 200
    local colX = 10
    frame.CharacterDropdown = CreateFilterDropdown("Character", colX, dropdownWidth)
    colX = colX + 290
    frame.DungeonDropdown = CreateFilterDropdown("Dungeon", colX, dropdownWidth)
    colX = colX + 290
    frame.KeystoneDropdown = CreateFilterDropdown("Keystone", colX, dropdownWidth)

    local resetButton = MPT.UIUtils:CreateButton(filterPanel, "Reset Filters", 120, 22, function()
        self.selectedCharacter = nil
        self.selectedDungeon = nil
        self.selectedDungeonName = nil
        self.selectedKeystoneLevel = nil
        self:PopulateFilters()
    end)
    resetButton:SetPoint("BOTTOMRIGHT", filterPanel, "BOTTOMRIGHT", -12, 8)
    frame.ResetFiltersButton = resetButton
    
    -- Main stats panel
    local statsPanel = CreateFrame("Frame", nil, frame)
    statsPanel:SetPoint("TOPLEFT", filterPanel, "BOTTOMLEFT", 0, -10)
    statsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    SetBackdropCompat(statsPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    
    -- Stats content
    local statsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statsTitle:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, -10)
    statsTitle:SetText("Dungeon Statistics")
    frame.StatsTitle = statsTitle
    
    -- Averages & best stats grid
    local metricDefs = {
        {key = "avgDuration", label = "Avg Duration"},
        {key = "bestKeystoneLevel", label = "Best Level"},
        {key = "avgDamage", label = "Avg Damage"},
        {key = "bestDamage", label = "Best Damage"},
        {key = "avgHealing", label = "Avg Healing"},
        {key = "bestHealing", label = "Best Healing"},
        {key = "avgInterrupts", label = "Avg Interrupts"},
        {key = "bestInterrupts", label = "Best Interrupts"},
        {key = "avgMobPercentage", label = "Avg Mob %"},
    }

    frame.StatValues = {}
    local gridTopY = -40
    local columns = 3
    local colSpacing = 320
    local rowHeight = 30

    for i, metric in ipairs(metricDefs) do
        local colIndex = (i - 1) % columns
        local rowIndex = math.floor((i - 1) / columns)
        local x = 10 + (colIndex * colSpacing)
        local y = gridTopY - (rowIndex * rowHeight)

        local labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        labelText:SetText(metric.label .. ":")
        labelText:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", x, y)
        labelText:SetTextColor(1, 0.84, 0, 1)

        local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetText("--")
        valueText:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", x + 120, y)

        frame.StatValues[metric.key] = valueText
    end
    
    -- Run history header
    local rows = math.ceil(#metricDefs / columns)
    local historyHeaderY = gridTopY - (rows * rowHeight) - 10
    local historyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    historyLabel:SetText("Recent Runs:")
    historyLabel:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY)
    historyLabel:SetTextColor(1, 0.84, 0, 1)

    -- Recent runs column headers
    local headerBg = statsPanel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetHeight(18)
    headerBg:SetWidth(880)
    headerBg:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY - 20)
    headerBg:SetColorTexture(0.12, 0.12, 0.18, 0.35)

    local function HeaderText(text, x, width, justify)
        local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10 + x, historyHeaderY - 18)
        fs:SetWidth(width)
        fs:SetJustifyH(justify or "LEFT")
        fs:SetTextColor(1, 0.84, 0, 1)
        fs:SetText(text)
        return fs
    end

    local colX = 5
    HeaderText("Date", colX, 130, "LEFT"); colX = colX + 130
    HeaderText("Dungeon", colX, 250, "LEFT"); colX = colX + 250
    HeaderText("+", colX, 35, "CENTER"); colX = colX + 35
    HeaderText("Result", colX, 75, "LEFT"); colX = colX + 75
    HeaderText("Time", colX, 55, "CENTER"); colX = colX + 55
    HeaderText("Mobs", colX, 55, "CENTER"); colX = colX + 55
    HeaderText("DMG", colX, 95, "RIGHT"); colX = colX + 95
    HeaderText("HPS", colX, 95, "RIGHT"); colX = colX + 95
    HeaderText("INT", colX, 90, "CENTER")
    
    -- Run history scroll
    frame.RunScroll, frame.RunContent = MPT.UIUtils:CreateScrollFrame(statsPanel, 900, 300)
    frame.RunScroll:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY - 40)
    frame.RunScroll:SetPoint("BOTTOMLEFT", statsPanel, "BOTTOMLEFT", 10, 10)
    if frame.RunContent.SetBackdrop then
        frame.RunContent:SetBackdrop(nil)
    end
    frame.RunRows = {}
    
    self.frame = frame
    return frame
end

function HistoryViewer:Show()
    local frame = self:Create()
    -- Default to showing all runs when opening
    self.selectedDungeon = nil
    self.selectedDungeonName = nil
    self:PopulateFilters()
    frame:Show()
end

function HistoryViewer:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

function HistoryViewer:PopulateFilters()
    local function InitializeDropdown(dropdown, items, selectedValue, defaultText, onSelect)
        UIDropDownMenu_Initialize(dropdown, function()
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.text
                info.value = item.value
                -- Larger dropdown list item text.
                info.fontObject = "GameFontNormal"
                info.func = function()
                    UIDropDownMenu_SetSelectedValue(dropdown, item.value)
                    UIDropDownMenu_SetText(dropdown, item.text)
                    onSelect(item)
                end
                info.checked = (item.value == selectedValue)
                UIDropDownMenu_AddButton(info)
            end
        end)

        local selectedText = defaultText
        for _, item in ipairs(items) do
            if item.value == selectedValue then
                selectedText = item.text
                break
            end
        end
        UIDropDownMenu_SetSelectedValue(dropdown, selectedValue)
        UIDropDownMenu_SetText(dropdown, selectedText)
    end

    -- Character dropdown
    local characters = MPT.Database:GetAllCharacters()
    local charItems = {
        {text = "All Characters", value = "ALL"},
    }
    for _, char in ipairs(characters) do
        local displayName = (MPT.Utils and MPT.Utils.GetClassColoredName) and MPT.Utils:GetClassColoredName(char.name, char.class) or char.name
        table.insert(charItems, {
            text = displayName .. " - " .. char.realm,
            value = char.name .. "-" .. char.realm,
        })
    end

    local selectedCharValue = self.selectedCharacter or "ALL"
    InitializeDropdown(self.frame.CharacterDropdown, charItems, selectedCharValue, "All Characters", function(item)
        if item.value == "ALL" then
            self.selectedCharacter = nil
        else
            self.selectedCharacter = item.value
        end
        self:UpdateDisplay()
    end)

    -- Dungeon dropdown
    local dungeons = MPT.Database:GetAllDungeons()
    local dungeonItems = {
        {text = "All Dungeons", value = "ALL"},
    }
    for _, dungeon in ipairs(dungeons) do
        local label = (MPT.Utils and MPT.Utils.GetDungeonAcronym) and MPT.Utils:GetDungeonAcronym(dungeon.name) or dungeon.name
        label = label .. " (" .. dungeon.count .. ")"
        table.insert(dungeonItems, {
            text = label,
            value = dungeon.id,
            data = dungeon,
        })
    end

    local selectedDungeonValue = self.selectedDungeon or "ALL"
    InitializeDropdown(self.frame.DungeonDropdown, dungeonItems, selectedDungeonValue, "All Dungeons", function(item)
        if item.value == "ALL" then
            self.selectedDungeon = nil
            self.selectedDungeonName = nil
        else
            self.selectedDungeon = item.value
            self.selectedDungeonName = item.data and item.data.name or nil
        end
        self:UpdateDisplay()
    end)

    -- Keystone dropdown
    local keystoneLevels = MPT.Database:GetAllKeystoneLevels()
    local keystoneItems = {
        {text = "All Levels", value = "ALL"},
    }
    for _, level in ipairs(keystoneLevels) do
        table.insert(keystoneItems, {
            text = "M+ " .. level,
            value = level,
        })
    end

    local selectedKeystoneValue = self.selectedKeystoneLevel or "ALL"
    InitializeDropdown(self.frame.KeystoneDropdown, keystoneItems, selectedKeystoneValue, "All Levels", function(item)
        if item.value == "ALL" then
            self.selectedKeystoneLevel = nil
        else
            self.selectedKeystoneLevel = item.value
        end
        self:UpdateDisplay()
    end)

    self:UpdateDisplay()
end

function HistoryViewer:UpdateDisplay()
    local charName = nil
    local realm = nil
    if self.selectedCharacter then
        charName, realm = strsplit("-", self.selectedCharacter)
    end

    local stats
    if self.selectedDungeon or self.selectedDungeonName then
        self.frame.StatsTitle:SetText("Dungeon Statistics")
        stats = MPT.Database:GetDungeonStatistics(self.selectedDungeon, charName, realm, self.selectedDungeonName, self.selectedKeystoneLevel)
    else
        self.frame.StatsTitle:SetText("Overall Statistics")
        stats = MPT.Database:GetOverallStatistics(charName, realm, self.selectedKeystoneLevel)
    end
    
    if stats then
        if self.frame.SummaryValues then
            self.frame.SummaryValues[1]:SetText(tostring(stats.totalRuns))
            self.frame.SummaryValues[2]:SetText(tostring(stats.completedRuns))
            self.frame.SummaryValues[3]:SetText(tostring(stats.failedRuns))
            self.frame.SummaryValues[4]:SetText(tostring(stats.avgKeystoneLevel))
        end

        if self.frame.StatValues then
            self.frame.StatValues.avgDuration:SetText(MPT.Utils:FormatDuration(stats.avgDuration))
            self.frame.StatValues.bestKeystoneLevel:SetText(tostring(stats.bestKeystoneLevel))
            self.frame.StatValues.avgDamage:SetText(MPT.Utils:FormatNumber(stats.avgDamage))
            self.frame.StatValues.bestDamage:SetText(MPT.Utils:FormatNumber(stats.bestDamage))
            self.frame.StatValues.avgHealing:SetText(MPT.Utils:FormatNumber(stats.avgHealing))
            self.frame.StatValues.bestHealing:SetText(MPT.Utils:FormatNumber(stats.bestHealing))
            self.frame.StatValues.avgInterrupts:SetText(tostring(stats.avgInterrupts))
            self.frame.StatValues.bestInterrupts:SetText(tostring(stats.bestInterrupts))
            self.frame.StatValues.avgMobPercentage:SetText(string.format("%.1f%%", stats.avgMobPercentage))
        end
    end
    
    -- Populate run history
    local allRuns
    if self.selectedDungeon or self.selectedDungeonName then
        allRuns = MPT.Database:GetRunsByDungeon(self.selectedDungeon, charName, realm, self.selectedDungeonName)
    else
        allRuns = charName and MPT.Database:GetRunsByCharacter(charName, realm) or (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
        table.sort(allRuns, function(a, b)
            return (a.timestamp or 0) > (b.timestamp or 0)
        end)
    end

    -- Determine current personal-best run per dungeon (highest keystone level).
    -- If multiple runs share the best level, pick the most recent one.
    local pbLevelByDungeon = {}
    local pbTimestampByDungeon = {}
    for _, run in ipairs(allRuns) do
        local dungeonKey = run.dungeonName or tostring(run.dungeonId or run.dungeonID or run.dungeon or "--")
        local level = run.keystoneLevel or run.dungeonLevel or 0
        local ts = run.timestamp or 0
        local bestLevel = pbLevelByDungeon[dungeonKey]

        if bestLevel == nil or level > bestLevel then
            pbLevelByDungeon[dungeonKey] = level
            pbTimestampByDungeon[dungeonKey] = ts
        elseif level == bestLevel then
            local bestTs = pbTimestampByDungeon[dungeonKey] or 0
            if ts > bestTs then
                pbTimestampByDungeon[dungeonKey] = ts
            end
        end
    end

    local runs = allRuns
    
    -- Filter by keystone level if selected
    if self.selectedKeystoneLevel then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            if (run.dungeonLevel or run.keystoneLevel) == self.selectedKeystoneLevel then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end
    
    for _, row in ipairs(self.frame.RunRows) do
        row:Hide()
    end
    self.frame.RunRows = {}
    
    local function GetRunBestStats(run)
        local bestDamage, bestHealing, bestInterrupts = 0, 0, 0
        if run.playerStats then
            for _, pstats in pairs(run.playerStats) do
                bestDamage = math.max(bestDamage, pstats.damage or 0)
                bestHealing = math.max(bestHealing, pstats.healing or 0)
                bestInterrupts = math.max(bestInterrupts, pstats.interrupts or 0)
            end
        elseif run.players then
            for _, p in ipairs(run.players) do
                bestDamage = math.max(bestDamage, p.damage or 0)
                bestHealing = math.max(bestHealing, p.healing or 0)
                bestInterrupts = math.max(bestInterrupts, p.interrupts or 0)
            end
        end
        return bestDamage, bestHealing, bestInterrupts
    end

    local runY = 0
    for idx, run in ipairs(runs) do
        local runRow = CreateFrame("Frame", nil, self.frame.RunContent)
        runRow:SetSize(880, 22)
        runRow:SetPoint("TOPLEFT", self.frame.RunContent, "TOPLEFT", 0, -runY)

        local bg = runRow:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(runRow)

        local hover = runRow:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(runRow)
        hover:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        hover:SetAlpha(0.16)

        local level = run.keystoneLevel or run.dungeonLevel or 0
        local mobPct = run.overallMobPercentage or 0
        local bestDamage, bestHealing, bestInterrupts = GetRunBestStats(run)

        local dungeonKey = run.dungeonName or tostring(run.dungeonId or run.dungeonID or run.dungeon or "--")
        local isPersonalBest = (level > 0)
            and (level == (pbLevelByDungeon[dungeonKey] or -1))
            and ((run.timestamp or 0) == (pbTimestampByDungeon[dungeonKey] or -1))

        if isPersonalBest then
            bg:SetColorTexture(1, 0.84, 0, 0.18)
        elseif idx % 2 == 0 then
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.18)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end

        local x = 5

        local dateText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dateText:SetWidth(130)
        dateText:SetJustifyH("LEFT")
        dateText:SetText(date("%Y-%m-%d %H:%M", run.timestamp or time()))
        x = x + 130

        local dungeonText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dungeonText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dungeonText:SetWidth(250)
        dungeonText:SetJustifyH("LEFT")
        dungeonText:SetText(run.dungeonName or "--")
        x = x + 250

        local levelText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        levelText:SetWidth(35)
        levelText:SetJustifyH("CENTER")
        levelText:SetText("+" .. tostring(level))
        x = x + 35

        local completedText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        completedText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        completedText:SetWidth(75)
        completedText:SetJustifyH("LEFT")
        completedText:SetText(run.completed and "|cff00ff00Completed|r" or "|cffff0000Failed|r")
        x = x + 75

        local durationText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durationText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        durationText:SetWidth(55)
        durationText:SetJustifyH("CENTER")
        durationText:SetText(MPT.Utils:FormatDuration(run.duration or 0))
        x = x + 55

        local mobText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mobText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        mobText:SetWidth(55)
        mobText:SetJustifyH("CENTER")
        mobText:SetText(string.format("%.1f%%", mobPct))
        x = x + 55

        local dmgText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dmgText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dmgText:SetWidth(95)
        dmgText:SetJustifyH("RIGHT")
        dmgText:SetText(MPT.Utils:FormatNumber(bestDamage))
        x = x + 95

        local healText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        healText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        healText:SetWidth(95)
        healText:SetJustifyH("RIGHT")
        healText:SetText(MPT.Utils:FormatNumber(bestHealing))
        x = x + 95

        local intText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        intText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        intText:SetWidth(90)
        intText:SetJustifyH("CENTER")
        intText:SetText(tostring(bestInterrupts))

        table.insert(self.frame.RunRows, runRow)
        runY = runY + 24
    end
    
    self.frame.RunContent:SetHeight(math.max(runY, 1))
end

print("|cff00ffaa[StormsDungeonData]|r History Viewer module loaded")
