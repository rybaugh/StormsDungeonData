-- Mythic Plus Tracker - Scoreboard Frame
-- Displays run statistics at dungeon completion

local MPT = StormsDungeonData
local Scoreboard = {}
MPT.Scoreboard = Scoreboard

-- Build a short friend-list note from our good/bad counts (e.g. "SDD: Good +5, Bad +2")
local function GetRatingNoteForFriend(playerName)
    if not MPT.Database or not playerName then return "" end
    local goodCount = MPT.Database.GetPlayerGoodCount and MPT.Database:GetPlayerGoodCount(playerName) or 0
    local badCount = MPT.Database.GetPlayerBadCount and MPT.Database:GetPlayerBadCount(playerName) or 0
    if goodCount == 0 and badCount == 0 then
        local rating = MPT.Database.GetPlayerRating and MPT.Database:GetPlayerRating(playerName)
        if rating == "good" then goodCount = 1 elseif rating == "bad" then badCount = 1 end
    end
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
    
    -- Player stats table header
    local headerY = -155
    local headers = {"Player", "Damage", "Healing", "Interrupts"}
    local columnWidths = {200, 200, 200, 180}
    local playerNameWidth = 118  -- Leave room for rating + add-friend buttons in same column
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
        
        local roleIconSize = 16
        local roleIconGap = 4
        local roleIcon = row:CreateTexture(nil, "OVERLAY")
        roleIcon:SetSize(roleIconSize, roleIconSize)
        roleIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
        roleIcon:Hide()
        -- Text fallback (T/H/D) when Blizzard role texture doesn't load
        local roleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleLabel:SetPoint("LEFT", row, "LEFT", 0, 0)
        roleLabel:SetSize(roleIconSize, roleIconSize)
        roleLabel:SetJustifyH("CENTER")
        roleLabel:SetJustifyV("MIDDLE")
        roleLabel:SetFont(roleLabel:GetFont(), 11, "OUTLINE")
        roleLabel:Hide()
        
        local playerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        playerName:SetPoint("LEFT", row, "LEFT", roleIconSize + roleIconGap, 0)
        playerName:SetWidth(playerNameWidth)
        playerName:SetJustifyH("LEFT")
        
        -- Thumbs up (good) and thumbs down (bad) for non-user players
        local ratingUpBtn = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
        ratingUpBtn:SetSize(22, 20)
        ratingUpBtn:SetPoint("LEFT", row, "LEFT", roleIconSize + roleIconGap + playerNameWidth + 2, 0)
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
            roleIcon = roleIcon,
            roleLabel = roleLabel,
            name = playerName,
            damage = damage,
            healing = healing,
            interrupts = interrupts,
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
    totalsText:SetText("Damage: --   Healing: --   Interrupts: --   Deaths: --")
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
    
    -- Buttons at bottom
    local buttonWidth = 100
    local buttonHeight = 24
    
    local historyButton = MPT.UIUtils:CreateButton(frame, "History", buttonWidth, buttonHeight, function()
        -- Hide the scoreboard before showing history
        frame:Hide()
        
        -- Show history centered, not anchored to scoreboard
        if MPT.HistoryViewer then
            MPT.HistoryViewer:Show()
        end
    end)
    historyButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 15)
    
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
        local best = {damage = 0, healing = 0, interrupts = 0}
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
                        end
                    end
                elseif run.players then
                    for _, p in ipairs(run.players) do
                        local shortName = p.name and (p.name:match("^([^%-]+)") or p.name)
                        if shortName and (userCharacters[p.name] or userCharacters[shortName]) then
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

    local function SafeText(value, fallback)
        if value == nil then
            return fallback or ""
        end
        if type(value) == "string" then
            return value
        end
        return tostring(value)
    end

    -- Use saved/spec roles (player.role, stats.role from UnitGroupRolesAssigned or spec at completion).
    -- Fill missing slots to enforce 1 tank, 1 healer, 3 damage: healer = max healing among unassigned; tank = first unassigned; rest = damager.
    local assignedRole = {}
    do
        local n = math.min(5, #playerData)
        local healing = {}
        for j = 1, n do
            local p = playerData[j]
            local s = p.stats or (p.damage ~= nil or p.healing ~= nil or p.interrupts ~= nil) and p or {}
            healing[j] = s.healing or p.healing or 0
            local saved = p.role or s.role
            if saved == "TANK" or saved == "HEALER" or saved == "DAMAGER" then
                assignedRole[j] = saved
            end
        end
        local nTank, nHealer, nDamager = 0, 0, 0
        for j = 1, n do
            local r = assignedRole[j]
            if r == "TANK" then nTank = nTank + 1 elseif r == "HEALER" then nHealer = nHealer + 1 elseif r == "DAMAGER" then nDamager = nDamager + 1 end
        end
        local unassigned = {}
        for j = 1, n do if not assignedRole[j] then unassigned[#unassigned + 1] = j end end
        if #unassigned > 0 then
            if nHealer < 1 then
                local best = unassigned[1]
                for _, idx in ipairs(unassigned) do
                    if healing[idx] > healing[best] then best = idx end
                end
                assignedRole[best] = "HEALER"
                nHealer = 1
                for i = 1, #unassigned do if unassigned[i] == best then table.remove(unassigned, i) break end end
            end
            if nTank < 1 and #unassigned > 0 then
                assignedRole[unassigned[1]] = "TANK"
                table.remove(unassigned, 1)
            end
            for _, idx in ipairs(unassigned) do assignedRole[idx] = "DAMAGER" end
        end
        for j = 1, n do if not assignedRole[j] then assignedRole[j] = "DAMAGER" end end
    end

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
            local nameText = nil
            if type(player.name) == "string" and player.name ~= "" then
                nameText = player.name
            elseif type(player.unitID) == "string" and player.unitID ~= "" then
                nameText = player.unitID
            elseif type(stats.name) == "string" and stats.name ~= "" then
                nameText = stats.name
            end
            row.name:SetText(SafeText(nameText, "Unknown"))
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
            
            -- Role: use assigned 1 tank / 1 healer / 3 damager from pre-pass (healer = max healing, tank = max interrupts among non-healers).
            local role = assignedRole[i] or "DAMAGER"
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
            
            local personalBest = GetPersonalBestStats(runRecord.dungeonID, runRecord.dungeonName, player.name)
            local damageValue = stats.damage or 0
            local healingValue = stats.healing or 0
            local interruptsValue = stats.interrupts or 0

            local damageText = MPT.Utils:FormatNumber(damageValue)
            local healingText = MPT.Utils:FormatNumber(healingValue)
            local interruptsText = tostring(interruptsValue)

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
            end

            row.damage:SetText(SafeText(damageText, "0"))
            row.healing:SetText(SafeText(healingText, "0"))
            row.interrupts:SetText(SafeText(interruptsText, "0"))

            -- Show rating and add-friend buttons only for non-user players
            local playerNameForActions = nameText or player.name
            if isUserCharacter then
                if row.ratingUpBtn then row.ratingUpBtn:Hide() end
                if row.ratingDownBtn then row.ratingDownBtn:Hide() end
                if row.addFriendBtn then row.addFriendBtn:Hide() end
            else
                local rating = (MPT.Database and MPT.Database.GetPlayerRating and playerNameForActions) and MPT.Database:GetPlayerRating(playerNameForActions) or nil
                local isFriend = IsPlayerFriend(playerNameForActions)
                
                if row.ratingUpBtn then
                    row.ratingUpBtn:Show()
                    local goodCount = (MPT.Database and MPT.Database.GetPlayerGoodCount and playerNameForActions) and MPT.Database:GetPlayerGoodCount(playerNameForActions) or 0
                    -- Selected: white brackets + green plus. Unselected: dim green plus.
                    row.ratingUpBtn:SetText(rating == "good" and "|cffffffff[|r|cff00ff00+|r|cffffffff]|r" or "|cff88ff88+|r")
                    row.ratingUpBtn:SetScript("OnClick", function()
                        if MPT.Database and playerNameForActions then
                            if MPT.Database.IncrementPlayerGoodCount then
                                MPT.Database:IncrementPlayerGoodCount(playerNameForActions)
                            end
                            if MPT.Database.SetPlayerRating then
                                MPT.Database:SetPlayerRating(playerNameForActions, "good")
                            end
                            if IsPlayerFriend(playerNameForActions) and C_FriendList and C_FriendList.SetFriendNotes then
                                C_FriendList.SetFriendNotes(playerNameForActions, GetRatingNoteForFriend(playerNameForActions))
                            end
                            Scoreboard:Show(runRecord)
                        end
                    end)
                end
                if row.ratingDownBtn then
                    row.ratingDownBtn:Show()
                    -- Selected: white brackets + red minus so "rated bad" is obvious on dark button. Unselected: dim red minus.
                    row.ratingDownBtn:SetText(rating == "bad" and "|cffffffff[|r|cffff4444-|r|cffffffff]|r" or "|cffff8888-|r")
                    row.ratingDownBtn:SetScript("OnClick", function()
                        if MPT.Database and playerNameForActions then
                            if MPT.Database.IncrementPlayerBadCount then
                                MPT.Database:IncrementPlayerBadCount(playerNameForActions)
                            end
                            if MPT.Database.SetPlayerRating then
                                MPT.Database:SetPlayerRating(playerNameForActions, "bad")
                            end
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
            totalsDeaths = totalsDeaths + (stats.deaths or 0)

            mvpCandidates[i] = {
                player = player,
                stats = stats,
                role = assignedRole[i] or player.role or stats.role,
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

    -- Check if we have any combat data at all
    local noCombatData = (totalsDamage == 0 and totalsHealing == 0 and totalsInterrupts == 0)
    
    -- Total deaths: prefer run record (C_ChallengeMode.GetDeathCount at completion), else sum from player rows
    local totalDeaths = (runRecord.deathCount ~= nil and runRecord.deathCount >= 0) and runRecord.deathCount or totalsDeaths

    if noCombatData then
        frame.TotalsText:SetText("|cffff4444No combat data available - see chat for details|r")
    else
        frame.TotalsText:SetText(string.format(
            "Damage: |cffff8000%s|r   Healing: |cff00ff00%s|r   Interrupts: |cff0088ff%d|r   Deaths: |cffff4444%d|r",
            MPT.Utils:FormatNumber(totalsDamage),
            MPT.Utils:FormatNumber(totalsHealing),
            totalsInterrupts,
            totalDeaths
        ))
    end

    if mvpIndex and frame.PlayerRows[mvpIndex] and frame.PlayerRows[mvpIndex].mvpBg then
        frame.PlayerRows[mvpIndex].mvpBg:Show()
    end

    if mvpPlayer and frame.MVPName and frame.MVPDetails then
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
    
    frame:Show()
end

function Scoreboard:Hide()
    if self.frame then
        self.frame:Hide()
    end
end

print("|cff00ffaa[StormsDungeonData]|r Scoreboard module loaded")
