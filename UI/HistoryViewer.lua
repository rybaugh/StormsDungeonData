-- Mythic Plus Tracker - History Viewer
-- Displays historical data for dungeons and characters

local MPT = StormsDungeonData
local HistoryViewer = {}
MPT.HistoryViewer = HistoryViewer

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

-- Time limit in seconds for dungeon (for showing red time when over limit on old runs)
local function GetDungeonTimeLimitSeconds(mapID)
    if not mapID or not C_ChallengeMode or type(C_ChallengeMode.GetMapUIInfo) ~= "function" then
        return nil
    end
    local _, _, timeLimit = C_ChallengeMode.GetMapUIInfo(mapID)
    if timeLimit and timeLimit > 0 and timeLimit < 100000 then
        return timeLimit
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
    end
end

HistoryViewer.selectedCharacter = nil
HistoryViewer.selectedDungeon = nil
HistoryViewer.selectedDungeonName = nil
HistoryViewer.selectedKeystoneLevel = nil
HistoryViewer.selectedResult = nil
HistoryViewer.selectedSpecName = nil
HistoryViewer.selectedHeroName = nil

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

    -- Filter bar (2 rows, evenly spaced)
    local filterPanel = CreateFrame("Frame", nil, frame)
    filterPanel:SetSize(980, 100)
    filterPanel:SetPoint("TOPLEFT", summaryPanel, "BOTTOMLEFT", 0, -12)
    SetBackdropCompat(filterPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    
    local function CreateFilterDropdown(labelText, x, width, yOffset)
        yOffset = yOffset or 0
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(labelText)
        label:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", x + 8, -8 + yOffset)
        label:SetTextColor(1, 0.84, 0, 1)

        -- UIDropDownMenuTemplate relies on the dropdown having a name for correct anchoring
        -- (the template creates named children like <name>Button and uses them as anchor frames).
        local safeKey = (labelText or ""):gsub("%W", "")
        if safeKey == "" then safeKey = "Filter" end
        local dropdownName = "StormsDungeonDataHistory" .. safeKey .. "Dropdown"
        local dropdown = CreateFrame("Frame", dropdownName, filterPanel, "UIDropDownMenuTemplate")
        dropdown:SetPoint("TOPLEFT", filterPanel, "TOPLEFT", x - 12, -22 + yOffset)
        UIDropDownMenu_SetWidth(dropdown, width)
        UIDropDownMenu_JustifyText(dropdown, "LEFT")
        UIDropDownMenu_SetText(dropdown, "All")

        -- Make the selected value text larger for readability.
        local dropdownText = _G[dropdownName .. "Text"]
        if dropdownText and dropdownText.SetFontObject then
            dropdownText:SetFontObject("GameFontNormalLarge")
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

    local columns = 3
    local colWidth = math.floor(980 / columns)
    local dropdownWidth = colWidth - 30
    local row1Y = 0
    local row2Y = -46

    local function ColX(col)
        return 10 + ((col - 1) * colWidth)
    end

    -- Row 1
    frame.DungeonDropdown = CreateFilterDropdown("Dungeon", ColX(1), dropdownWidth, row1Y)
    frame.KeystoneDropdown = CreateFilterDropdown("Keystone", ColX(2), dropdownWidth, row1Y)
    frame.ResultDropdown = CreateFilterDropdown("Result", ColX(3), dropdownWidth, row1Y)

    -- Row 2
    frame.CharacterDropdown = CreateFilterDropdown("Character", ColX(1), dropdownWidth, row2Y)
    frame.SpecDropdown = CreateFilterDropdown("Spec", ColX(2), dropdownWidth, row2Y)
    frame.HeroDropdown = CreateFilterDropdown("Hero", ColX(3), dropdownWidth, row2Y)

    local resetButton = MPT.UIUtils:CreateButton(filterPanel, "Reset Filters", 120, 22, function()
        self.selectedCharacter = nil
        self.selectedDungeon = nil
        self.selectedDungeonName = nil
        self.selectedKeystoneLevel = nil
        self.selectedResult = nil
        self.selectedSpecName = nil
        self.selectedHeroName = nil
        self:PopulateFilters()
    end)
    resetButton:SetPoint("TOPLEFT", frame.HeroDropdown, "BOTTOMLEFT", 16, -6)
    frame.ResetFiltersButton = resetButton
    
    -- Main stats panel with proper spacing
    local statsPanel = CreateFrame("Frame", nil, frame)
    statsPanel:SetPoint("TOPLEFT", filterPanel, "BOTTOMLEFT", 0, -8)
    statsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    SetBackdropCompat(statsPanel, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})
    
    -- Stats content
    local statsTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    statsTitle:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, -10)
    statsTitle:SetText("Dungeon Statistics")
    frame.StatsTitle = statsTitle
    
    -- Averages & best stats grid
    local metricDefs = {
        -- Row 1: Best level, avg duration
        {key = "bestKeystoneLevel", label = "Best Level"},
        {key = "avgDuration", label = "Avg Duration"},

        -- Row 2: Best Damage, Best Healing, Best Interrupts
        {key = "bestDamage", label = "Best Damage"},
        {key = "bestHealing", label = "Best Healing"},
        {key = "bestInterrupts", label = "Best Interrupts"},

        -- Row 3: Avg Damage, Avg Healing, Avg Interrupts
        {key = "avgDamage", label = "Avg Damage"},
        {key = "avgHealing", label = "Avg Healing"},
        {key = "avgInterrupts", label = "Avg Interrupts"},
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

    local statsSectionFrame = CreateFrame("Frame", nil, statsPanel)
    statsSectionFrame:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 6, -6)
    statsSectionFrame:SetPoint("TOPRIGHT", statsPanel, "TOPRIGHT", -6, -6)
    statsSectionFrame:SetPoint("BOTTOMLEFT", statsPanel, "TOPLEFT", 6, historyHeaderY + 6)
    statsSectionFrame:SetPoint("BOTTOMRIGHT", statsPanel, "TOPRIGHT", -6, historyHeaderY + 6)
    SetBackdropCompat(statsSectionFrame, backdropInfo, {0.05, 0.05, 0.05, 0.5}, {1, 1, 1, 0.3})

    local historyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    historyLabel:SetText("Recent Runs:")
    historyLabel:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY)
    historyLabel:SetTextColor(1, 0.84, 0, 1)

    -- Recent runs column headers
    local headerBg = statsPanel:CreateTexture(nil, "BACKGROUND")
    headerBg:SetHeight(18)
    headerBg:SetWidth(840)
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
    HeaderText("Dungeon", colX, 175, "LEFT"); colX = colX + 175
    HeaderText("Key", colX, 40, "CENTER"); colX = colX + 40
    HeaderText("Time", colX, 55, "CENTER"); colX = colX + 55
    -- No Result column: failed runs shown by red Time text
    HeaderText("Spec", colX, 80, "CENTER"); colX = colX + 80
    HeaderText("Hero", colX, 80, "CENTER"); colX = colX + 80
    HeaderText("Date", colX, 110, "LEFT"); colX = colX + 110
    HeaderText("Damage", colX, 70, "RIGHT"); colX = colX + 70
    HeaderText("Healing", colX, 70, "RIGHT"); colX = colX + 70
    HeaderText("INT", colX, 50, "CENTER"); colX = colX + 50
    HeaderText("MVP", colX, 40, "CENTER")
    
    -- Run history scroll (reduced width to fit scrollbar within bounds, anchored right)
    frame.RunScroll, frame.RunContent = MPT.UIUtils:CreateScrollFrame(statsPanel, 860, 300)
    frame.RunScroll:SetPoint("TOPLEFT", statsPanel, "TOPLEFT", 10, historyHeaderY - 40)
    frame.RunScroll:SetPoint("BOTTOMRIGHT", statsPanel, "BOTTOMRIGHT", -28, 10)
    if frame.RunContent.SetBackdrop then
        frame.RunContent:SetBackdrop(nil)
    end
    frame.RunRows = {}
    
    self.frame = frame
    return frame
end

function HistoryViewer:Show()
    if MPT.Scoreboard and MPT.Scoreboard.Hide then
        MPT.Scoreboard:Hide()
    end
    local frame = self:Create()
    -- Default to showing all runs when opening
    self.selectedDungeon = nil
    self.selectedDungeonName = nil
    self:PopulateFilters()
    frame:Show()
end

function HistoryViewer:ShowAtAnchor(anchorFrame)
    if MPT.Scoreboard and MPT.Scoreboard.Hide then
        MPT.Scoreboard:Hide()
    end
    local frame = self:Create()
    self.selectedDungeon = nil
    self.selectedDungeonName = nil
    self:PopulateFilters()

    if anchorFrame and frame then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 12, 0)
    end
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
                info.fontObject = "GameFontHighlight"
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
    local function ColorizeNameByClass(name, classToken)
        if classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] and RAID_CLASS_COLORS[classToken].colorStr then
            return "|c" .. RAID_CLASS_COLORS[classToken].colorStr .. name .. "|r"
        end
        if MPT.Utils and MPT.Utils.GetClassColoredName then
            return MPT.Utils:GetClassColoredName(name, classToken)
        end
        return name
    end

    local characters = MPT.Database:GetAllCharacters()
    local charItems = {
        {text = "All Characters", value = "ALL"},
    }
    for _, char in ipairs(characters) do
        local displayName = ColorizeNameByClass(char.name, char.class)
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

    -- Result dropdown (Completed/Failed)
    local resultItems = {
        {text = "All Results", value = "ALL"},
        {text = "Completed", value = true},
        {text = "Failed", value = false},
    }

    local selectedResultValue = self.selectedResult or "ALL"
    InitializeDropdown(self.frame.ResultDropdown, resultItems, selectedResultValue, "All Results", function(item)
        if item.value == "ALL" then
            self.selectedResult = nil
        else
            self.selectedResult = item.value
        end
        self:UpdateDisplay()
    end)

    -- Spec dropdown
    local specItems = {
        {text = "All Specs", value = "ALL"},
    }
    local specCounts = {}
    local specUnknownCount = 0
    local runs = (StormsDungeonDataDB and StormsDungeonDataDB.runs) or {}
    for _, run in ipairs(runs) do
        local specName = run.specName
        if specName and specName ~= "" then
            specCounts[specName] = (specCounts[specName] or 0) + 1
        else
            specUnknownCount = specUnknownCount + 1
        end
    end
    local specNames = {}
    for name in pairs(specCounts) do
        table.insert(specNames, name)
    end
    table.sort(specNames)
    if specUnknownCount > 0 then
        table.insert(specItems, {text = "Unknown", value = "UNKNOWN"})
    end
    for _, name in ipairs(specNames) do
        table.insert(specItems, {text = name .. " (" .. specCounts[name] .. ")", value = name})
    end

    local selectedSpecValue = self.selectedSpecName or "ALL"
    InitializeDropdown(self.frame.SpecDropdown, specItems, selectedSpecValue, "All Specs", function(item)
        if item.value == "ALL" then
            self.selectedSpecName = nil
        else
            self.selectedSpecName = item.value
        end
        self:UpdateDisplay()
    end)

    -- Hero dropdown
    local heroItems = {
        {text = "All Hero Talents", value = "ALL"},
    }
    local heroCounts = {}
    local heroUnknownCount = 0
    for _, run in ipairs(runs) do
        local heroName = run.heroName
        if heroName and heroName ~= "" then
            heroCounts[heroName] = (heroCounts[heroName] or 0) + 1
        else
            heroUnknownCount = heroUnknownCount + 1
        end
    end
    local heroNames = {}
    for name in pairs(heroCounts) do
        table.insert(heroNames, name)
    end
    table.sort(heroNames)
    if heroUnknownCount > 0 then
        table.insert(heroItems, {text = "Unknown", value = "UNKNOWN"})
    end
    for _, name in ipairs(heroNames) do
        table.insert(heroItems, {text = name .. " (" .. heroCounts[name] .. ")", value = name})
    end

    local selectedHeroValue = self.selectedHeroName or "ALL"
    InitializeDropdown(self.frame.HeroDropdown, heroItems, selectedHeroValue, "All Hero Talents", function(item)
        if item.value == "ALL" then
            self.selectedHeroName = nil
        else
            self.selectedHeroName = item.value
        end
        self:UpdateDisplay()
    end)

    self:UpdateDisplay()
end

function HistoryViewer:UpdateDisplay()
    local function ComputeStatsFromRuns(runs, characterName)
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
            bestKeystoneLevel = 0,
            bestDuration = 0,
            bestTime = nil,
            bestDamage = 0,
            bestHealing = 0,
            bestInterrupts = 0,
        }

        local totalDuration = 0
        local totalLevel = 0
        local totalDamage = 0
        local totalHealing = 0
        local totalInterrupts = 0
        local playerRunCount = 0

        for _, run in ipairs(runs) do
            local runLevel = (run.keystoneLevel or run.dungeonLevel or 0)
            stats.totalRuns = stats.totalRuns + 1
            if run.completed then
                stats.completedRuns = stats.completedRuns + 1
            else
                stats.failedRuns = stats.failedRuns + 1
            end

            totalDuration = totalDuration + (run.duration or 0)
            totalLevel = totalLevel + (runLevel or 0)

            if run.playerStats then
                for _, pstats in pairs(run.playerStats) do
                    stats.bestDamage = math.max(stats.bestDamage, pstats.damage or 0)
                    stats.bestHealing = math.max(stats.bestHealing, pstats.healing or 0)
                    stats.bestInterrupts = math.max(stats.bestInterrupts, pstats.interrupts or 0)
                end
            elseif run.players then
                for _, p in ipairs(run.players) do
                    stats.bestDamage = math.max(stats.bestDamage, p.damage or 0)
                    stats.bestHealing = math.max(stats.bestHealing, p.healing or 0)
                    stats.bestInterrupts = math.max(stats.bestInterrupts, p.interrupts or 0)
                end
            end

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

            if runLevel and runLevel > stats.bestKeystoneLevel then
                stats.bestKeystoneLevel = runLevel
            end

            if run.duration and run.duration > stats.bestDuration then
                stats.bestDuration = run.duration
                stats.bestTime = run.timestamp
            end
        end

        stats.avgDuration = stats.totalRuns > 0 and math.floor(totalDuration / stats.totalRuns) or 0
        stats.avgKeystoneLevel = stats.totalRuns > 0 and math.floor(totalLevel / stats.totalRuns) or 0
        stats.avgDamage = playerRunCount > 0 and math.floor(totalDamage / playerRunCount) or 0
        stats.avgHealing = playerRunCount > 0 and math.floor(totalHealing / playerRunCount) or 0
        stats.avgInterrupts = playerRunCount > 0 and math.floor(totalInterrupts / playerRunCount) or 0

        return stats
    end

    local charName = nil
    local realm = nil
    if self.selectedCharacter then
        charName, realm = strsplit("-", self.selectedCharacter)
    end

    local stats
    if self.selectedDungeon or self.selectedDungeonName then
        self.frame.StatsTitle:SetText("Dungeon Statistics")
    else
        self.frame.StatsTitle:SetText("Overall Statistics")
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
    
    -- Filter by result (completed/failed) if selected
    if self.selectedResult ~= nil then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            if self.selectedResult == true and run.completed then
                table.insert(filteredRuns, run)
            elseif self.selectedResult == false and not run.completed then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    -- Filter by spec if selected
    if self.selectedSpecName then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            local specName = run.specName
            if self.selectedSpecName == "UNKNOWN" then
                if not specName or specName == "" then
                    table.insert(filteredRuns, run)
                end
            elseif specName == self.selectedSpecName then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    -- Filter by hero talent if selected
    if self.selectedHeroName then
        local filteredRuns = {}
        for _, run in ipairs(runs) do
            local heroName = run.heroName
            if self.selectedHeroName == "UNKNOWN" then
                if not heroName or heroName == "" then
                    table.insert(filteredRuns, run)
                end
            elseif heroName == self.selectedHeroName then
                table.insert(filteredRuns, run)
            end
        end
        runs = filteredRuns
    end

    stats = ComputeStatsFromRuns(runs, charName)

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
        end
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

    local function IsPlayerMVP(run)
        -- Check if any of the user's characters was MVP using the same scoring logic as scoreboard
        local players = run.playerStats or run.players
        if not players then return false end
        
        -- Get all user's characters
        local userCharacters = {}
        if MPT.Database and MPT.Database.GetAllCharacters then
            local chars = MPT.Database:GetAllCharacters()
            for _, char in ipairs(chars) do
                local fullName = char.name .. "-" .. char.realm
                userCharacters[fullName] = true
                userCharacters[char.name] = true
            end
        end
        
        -- Calculate totals
        local totalDamage, totalHealing, totalInterrupts = 0, 0, 0
        local playerList = {}
        
        for _, p in pairs(players) do
            local damage = p.damage or 0
            local healing = p.healing or 0
            local interrupts = p.interrupts or 0
            
            totalDamage = totalDamage + damage
            totalHealing = totalHealing + healing
            totalInterrupts = totalInterrupts + interrupts
            
            table.insert(playerList, {
                name = p.name,
                damage = damage,
                healing = healing,
                interrupts = interrupts,
                role = p.role
            })
        end
        
        -- Find MVP using role-weighted scoring
        local mvpScore = -1
        local mvpName = nil
        
        for _, p in ipairs(playerList) do
            local dmgShare = totalDamage > 0 and (p.damage / totalDamage) or 0
            local healShare = totalHealing > 0 and (p.healing / totalHealing) or 0
            local intShare = totalInterrupts > 0 and (p.interrupts / totalInterrupts) or 0
            
            local score = 0
            if p.role == "TANK" then
                score = (dmgShare * 0.3) + (healShare * 0.1) + (intShare * 0.6)
            elseif p.role == "HEALER" then
                score = (dmgShare * 0.2) + (healShare * 0.6) + (intShare * 0.2)
            else
                score = (dmgShare * 0.6) + (healShare * 0.1) + (intShare * 0.3)
            end
            
            if score > mvpScore then
                mvpScore = score
                mvpName = p.name
            end
        end
        
        -- Check if MVP is one of user's characters
        if mvpName then
            local shortName = mvpName:match("^([^%-]+)") or mvpName
            return userCharacters[mvpName] or userCharacters[shortName]
        end
        
        return false
    end

    -- Determine personal-best run stats per dungeon for the current view.
    -- We highlight only the specific stat numbers (DMG/HPS/INT), not the whole row.
    local pbDamageByDungeon, pbHealingByDungeon, pbInterruptsByDungeon = {}, {}, {}
    for _, run in ipairs(runs) do
        local dungeonKey = run.dungeonName or tostring(run.dungeonId or run.dungeonID or run.dungeon or "--")
        local bestDamage, bestHealing, bestInterrupts = GetRunBestStats(run)
        pbDamageByDungeon[dungeonKey] = math.max(pbDamageByDungeon[dungeonKey] or 0, bestDamage or 0)
        pbHealingByDungeon[dungeonKey] = math.max(pbHealingByDungeon[dungeonKey] or 0, bestHealing or 0)
        pbInterruptsByDungeon[dungeonKey] = math.max(pbInterruptsByDungeon[dungeonKey] or 0, bestInterrupts or 0)
    end

    local runY = 0
    for idx, run in ipairs(runs) do
        local runRow = CreateFrame("Frame", nil, self.frame.RunContent)
        runRow:SetSize(840, 22)
        runRow:SetPoint("TOPLEFT", self.frame.RunContent, "TOPLEFT", 0, -runY)
        runRow:EnableMouse(true)
        runRow:SetScript("OnMouseUp", function(_, button)
            if button == "LeftButton" then
                -- Hide the history viewer before showing scoreboard
                self:Hide()
                
                if MPT.UI and MPT.UI.ShowScoreboard then
                    MPT.UI:ShowScoreboard(run)
                elseif MPT.Scoreboard and MPT.Scoreboard.Show then
                    MPT.Scoreboard:Show(run)
                end
            end
        end)

        local bg = runRow:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(runRow)

        local hover = runRow:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(runRow)
        hover:SetTexture("Interface/QuestFrame/UI-QuestTitleHighlight")
        hover:SetBlendMode("ADD")
        hover:SetAlpha(0.16)

        local level = run.keystoneLevel or run.dungeonLevel or 0
        local bestDamage, bestHealing, bestInterrupts = GetRunBestStats(run)

        if idx % 2 == 0 then
            bg:SetColorTexture(0.1, 0.1, 0.1, 0.18)
        else
            bg:SetColorTexture(0, 0, 0, 0)
        end

        local x = 5

        local dungeonText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dungeonText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dungeonText:SetWidth(175)
        dungeonText:SetJustifyH("LEFT")
        dungeonText:SetText(run.dungeonName or "--")
        x = x + 175

        local levelText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        levelText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        levelText:SetWidth(40)
        levelText:SetJustifyH("CENTER")
        levelText:SetText("+" .. tostring(level))
        x = x + 40

        local durationText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durationText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        durationText:SetWidth(55)
        durationText:SetJustifyH("CENTER")
        durationText:SetText(MPT.Utils:FormatDuration(run.duration or 0))
        -- Red time = over limit (failed); normal color = completed in time. Also treat as over-time for old runs saved before we set completed=false.
        local overTime = not run.completed
        if not overTime and (run.duration or 0) > 0 and (run.dungeonID or run.dungeonId) then
            local timeLimit = GetDungeonTimeLimitSeconds(run.dungeonID or run.dungeonId)
            if timeLimit and run.duration > timeLimit then
                overTime = true
            end
        end
        if overTime then
            durationText:SetTextColor(1, 0.27, 0.27, 1)
        else
            durationText:SetTextColor(1, 0.84, 0, 1)
        end
        x = x + 55

        local specText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        specText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        specText:SetWidth(80)
        specText:SetJustifyH("CENTER")
        do
            local label = ""
            if run.specIcon then
                label = "|T" .. tostring(run.specIcon) .. ":14:14:0:0|t"
            end
            specText:SetText(label)
        end
        x = x + 80

        local heroText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heroText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        heroText:SetWidth(80)
        heroText:SetJustifyH("CENTER")
        heroText:SetTextColor(0.8, 0.8, 1, 1)  -- Light blue tint
        if run.heroName and run.heroName ~= "" then
            heroText:SetText(run.heroName)
        else
            heroText:SetText("")
        end
        x = x + 80

        local dateText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dateText:SetWidth(110)
        dateText:SetJustifyH("LEFT")
        dateText:SetText(date("%m-%d-%y %H:%M", run.timestamp or time()))
        x = x + 110

        local dmgText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dmgText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        dmgText:SetWidth(70)
        dmgText:SetJustifyH("RIGHT")
        local dungeonKey = run.dungeonName or tostring(run.dungeonId or run.dungeonID or run.dungeon or "--")
        local dmgValueText = MPT.Utils:FormatNumber(bestDamage)
        if (bestDamage or 0) > 0 and (bestDamage or 0) >= (pbDamageByDungeon[dungeonKey] or 0) then
            dmgValueText = "|cffff8000" .. dmgValueText .. "|r"
        end
        dmgText:SetText(dmgValueText)
        x = x + 70

        local healText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        healText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        healText:SetWidth(70)
        healText:SetJustifyH("RIGHT")
        local healValueText = MPT.Utils:FormatNumber(bestHealing)
        if (bestHealing or 0) > 0 and (bestHealing or 0) >= (pbHealingByDungeon[dungeonKey] or 0) then
            healValueText = "|cffff8000" .. healValueText .. "|r"
        end
        healText:SetText(healValueText)
        x = x + 70

        local intText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        intText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        intText:SetWidth(50)
        intText:SetJustifyH("CENTER")
        local intValueText = tostring(bestInterrupts)
        if (bestInterrupts or 0) > 0 and (bestInterrupts or 0) >= (pbInterruptsByDungeon[dungeonKey] or 0) then
            intValueText = "|cffff8000" .. intValueText .. "|r"
        end
        intText:SetText(intValueText)
        x = x + 50

        -- MVP indicator
        local mvpText = runRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mvpText:SetPoint("LEFT", runRow, "LEFT", x, 0)
        mvpText:SetWidth(40)
        mvpText:SetJustifyH("CENTER")
        if IsPlayerMVP(run) then
            mvpText:SetText("|TInterface\\Icons\\Achievement_Dungeon_HEROIC_GloryoftheRaider:16:16:0:0|t")
        else
            mvpText:SetText("")
        end
        x = x + 40

        -- Delete button
        local deleteBtn = CreateFrame("Button", nil, runRow)
        deleteBtn:SetSize(18, 18)
        deleteBtn:SetPoint("LEFT", runRow, "LEFT", x, 0)
        deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")
        deleteBtn:SetScript("OnClick", function()
            StaticPopupDialogs["STORMSDUNGEONDATA_DELETE_RUN"] = {
                text = "Delete this run?\n\n" .. (run.dungeonName or "Unknown") .. " +" .. (run.keystoneLevel or run.dungeonLevel or 0),
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    if MPT.Database:DeleteRun(run.id) then
                        print("|cff00ffaa[StormsDungeonData]|r Run deleted")
                        self:UpdateDisplay()
                    else
                        print("|cff00ffaa[StormsDungeonData]|r Error: Could not delete run")
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("STORMSDUNGEONDATA_DELETE_RUN")
        end)
        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Delete Run", 1, 1, 1)
            GameTooltip:AddLine("Click to permanently delete this run", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        table.insert(self.frame.RunRows, runRow)
        runY = runY + 24
    end
    
    self.frame.RunContent:SetHeight(math.max(runY, 1))
end

print("|cff00ffaa[StormsDungeonData]|r History Viewer module loaded")
