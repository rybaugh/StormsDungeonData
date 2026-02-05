-- Mythic Plus Tracker - Main Module
-- Initializes UI and slash commands

local MPT = StormsDungeonData

local function GetMinimapAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    if not mx or not my then
        return math.rad(225)
    end
    local scale = Minimap:GetEffectiveScale() or 1
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    return math.atan2(cy - my, cx - mx)
end

local function PositionMinimapButton(btn, angle)
    local radius = 72
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function IsLibDBIconRegistered()
    if not LibStub then
        return false
    end
    local dbIcon = LibStub("LibDBIcon-1.0", true)
    if not dbIcon or not dbIcon.IsRegistered then
        return false
    end
    return dbIcon:IsRegistered("StormsDungeonData")
end

local function CreateBasicMinimapButton(onClick)
    if not Minimap or not CreateFrame then
        return nil
    end
    local btn = _G["StormsDungeonDataMinimapButton"]
    if not btn then
        btn = CreateFrame("Button", "StormsDungeonDataMinimapButton", UIParent)
    end
    btn:SetSize(32, 32)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(200)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    btn:SetNormalTexture("Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32")
    btn:SetPushedTexture("Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32")
    btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("StormsDungeonData", 1, 1, 1)
        GameTooltip:AddLine("Left-click: Open history", 0.2, 1, 0.2)
        GameTooltip:AddLine("Right-click: Save pending run", 0.2, 1, 0.2)
        GameTooltip:AddLine("Drag to reposition", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    if onClick then
        btn:SetScript("OnClick", onClick)
    end

    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            PositionMinimapButton(self, GetMinimapAngleFromCursor())
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)

        local angle = GetMinimapAngleFromCursor()
        StormsDungeonDataDB = StormsDungeonDataDB or {}
        StormsDungeonDataDB.settings = StormsDungeonDataDB.settings or {}
        StormsDungeonDataDB.settings.minimap = StormsDungeonDataDB.settings.minimap or {}
        StormsDungeonDataDB.settings.minimap.angle = angle
        PositionMinimapButton(self, angle)
    end)

    local angle = math.rad(225)
    if StormsDungeonDataDB and StormsDungeonDataDB.settings and StormsDungeonDataDB.settings.minimap and StormsDungeonDataDB.settings.minimap.angle then
        angle = StormsDungeonDataDB.settings.minimap.angle
    end
    PositionMinimapButton(btn, angle)

    btn:Show()
    return btn
end

local function IsPlayerInCorrectDungeon()
    if not MPT.CurrentRunData or not MPT.CurrentRunData.dungeonID then
        return false
    end
    
    local _, instanceType, difficultyID = GetInstanceInfo()
    -- Must be in a Mythic+ dungeon (difficultyID 8 is Mythic Keystone)
    if instanceType ~= "party" or difficultyID ~= 8 then
        return false
    end
    
    -- Check if current challenge mode matches the pending run
    if C_ChallengeMode and type(C_ChallengeMode.GetActiveChallengeMapID) == "function" then
        local currentMapID = C_ChallengeMode.GetActiveChallengeMapID()
        if currentMapID and currentMapID == MPT.CurrentRunData.dungeonID then
            return true
        end
    end
    
    return false
end

function MPT.UI:Initialize()
    -- Modules are loaded via the .toc file in order; don't overwrite them here.
    -- Just ensure tables exist so later calls don't hard error.
    MPT.Scoreboard = MPT.Scoreboard or {}
    MPT.HistoryViewer = MPT.HistoryViewer or {}
    
    local function OnMinimapClick(_, button)
        if button == "RightButton" then
            if not IsPlayerInCorrectDungeon() then
                print("|cff00ffaa[StormsDungeonData]|r Manual save only allowed inside the dungeon you just completed")
                return
            end
            local saved = false
            if MPT.Events and MPT.Events.FinalizeRun then
                saved = MPT.Events:FinalizeRun("manual") or false
            end
            if saved then
                -- Scoreboard is shown by FinalizeRun when autoShow is enabled
                -- If disabled, we could show it here explicitly with MPT.UI:ShowScoreboard(MPT.LastSavedRun)
            else
                print("|cff00ffaa[StormsDungeonData]|r No pending run to save")
            end
        else
            MPT.HistoryViewer:Show()
        end
    end

    -- Minimap button is created via UI/MinimapButton.xml (fallback to code if XML fails)
    if not _G["StormsDungeonDataMinimapButton"] and MPT.UIUtils and MPT.UIUtils.CreateMinimapButton then
        MPT.UIUtils:CreateMinimapButton("StormsDungeonDataMinimapButton", "Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32", OnMinimapClick)
    end
    if not _G["StormsDungeonDataMinimapButton"] and not IsLibDBIconRegistered() then
        CreateBasicMinimapButton(OnMinimapClick)
    end
    if _G["StormsDungeonDataMinimapButton"] then
        _G["StormsDungeonDataMinimapButton"]:Show()
        if _G["StormsDungeonDataMinimapButton"].ResetPosition then
            _G["StormsDungeonDataMinimapButton"]:ResetPosition()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if not _G["StormsDungeonDataMinimapButton"] and MPT.UIUtils and MPT.UIUtils.CreateMinimapButton then
                MPT.UIUtils:CreateMinimapButton("StormsDungeonDataMinimapButton", "Interface/AddOns/StormsDungeonData/stormsdungeondata_32x32", OnMinimapClick)
            end
            if not _G["StormsDungeonDataMinimapButton"] and not IsLibDBIconRegistered() then
                CreateBasicMinimapButton(OnMinimapClick)
            end
            if _G["StormsDungeonDataMinimapButton"] then
                _G["StormsDungeonDataMinimapButton"]:Show()
                if _G["StormsDungeonDataMinimapButton"].ResetPosition then
                    _G["StormsDungeonDataMinimapButton"]:ResetPosition()
                end
            end
        end)
    end
    
    print("|cff00ffaa[StormsDungeonData]|r UI module initialized")
end

function MPT.UI:ShowScoreboard(runRecord)
    if MPT.Scoreboard and MPT.Scoreboard.Show then
        MPT.Scoreboard:Show(runRecord)
    end
end

-- Slash command handler function (defined at load time)
local function HandleSlashCommand(msg, editbox)
    msg = (msg or ""):lower():trim()
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    rest = rest or ""

    if cmd == "history" or cmd == "h" then
        MPT.HistoryViewer:Show()
    elseif cmd == "save" then
        if not IsPlayerInCorrectDungeon() then
            print("|cff00ffaa[StormsDungeonData]|r Manual save only allowed inside the dungeon you just completed")
            return
        end
        local saved = false
        if MPT.Events and MPT.Events.FinalizeRun then
            saved = MPT.Events:FinalizeRun("manual") or false
        end
        if saved then
            -- Scoreboard is shown by FinalizeRun when autoShow is enabled
            -- If disabled, we could show it here explicitly with MPT.UI:ShowScoreboard(MPT.LastSavedRun)
            print("|cff00ffaa[StormsDungeonData]|r Run saved manually!")
        else
            print("|cff00ffaa[StormsDungeonData]|r No pending run to save")
        end
    elseif cmd == "reset" then
        StormsDungeonDataDB = MPT.Database:CreateDefaultDB()
        print("|cff00ffaa[StormsDungeonData]|r Database reset!")
    elseif cmd == "status" then
        print("|cff00ffaa[StormsDungeonData]|r Status:")
        print("  Total runs: " .. #StormsDungeonDataDB.runs)
        print("  Type |cff00ffaa/sdd history|r to view history")
    elseif cmd == "" or cmd == "help" then
        print("|cff00ffaa[StormsDungeonData]|r Commands:")
        print("  |cff00ffaa/sdd history|r - Show run history")
        print("  |cff00ffaa/sdd save|r - Manually save pending run")
        print("  |cff00ffaa/sdd status|r - Show addon status")
        print("  |cff00ffaa/sdd reset|r - Reset database")
        print("  |cff00ffaa/sdd help|r - Show this message")
    else
        print("|cff00ffaa[StormsDungeonData]|r Unknown command: " .. msg)
    end
end

-- Register slash commands safely
-- Use pcall to prevent issues if SlashCmdList doesn't exist yet
if SlashCmdList then
    SLASH_STORMSDUNGEONDATA1 = "/sdd"
    SLASH_STORMSDUNGEONDATA2 = "/stormsdungeondata"
    SlashCmdList.STORMSDUNGEONDATA = HandleSlashCommand
end

print("|cff00ffaa[StormsDungeonData]|r Main module loaded")
